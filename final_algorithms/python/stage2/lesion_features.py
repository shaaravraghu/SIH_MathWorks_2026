"""#Pre-Feature Engineering / #Feature Engineering (Haemorrhage, Nerve Fibre
Ischemia, Hard Exudate) - see
notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "Pre-Feature Engineering"
and "Feature Engineering" sections.

Candidate finding and every feature below use COLOUR RATIOS, never absolute
R/G/B. Why: a microaneurysm classifier fed absolute colour reported AUC
0.995 - it had learned CAMERA IDENTITY (top features r_mean 0.237, b_mean
0.204). Banning absolute intensity dropped it to an honest 0.742. Module 2
features already predict image RESOLUTION at 67.8% against a 17% chance
baseline, i.e. features can silently encode capture-device artifacts rather
than disease.

Class separation on ratios (see notes):
    Haemorrhage            low b_over_g (dark, red),   moderate edge, off-vessel
    Hard Exudate            saturated yellow,            SHARP edge,    often clustered/ring
    Nerve Fibre Ischemia    HIGH b_over_g (pale/white),  GRADUAL edge,  along nerve fibres
The yellow-vs-white split between hard exudate and cotton-wool spot is
exactly a blue/green ratio question, which an absolute range would discard.

Shape features are implemented via cv2 contour moments / ellipse fit rather
than skimage.measure.regionprops: skimage is not part of stage1's
numpy/opencv/scipy stack and is not installed in this environment -
documented equivalent, judgment call.
"""

import cv2
import numpy as np
from scipy import ndimage

# --- local context windows ----------------------------------------------------
LOCAL_CONTRAST_ANNULUS_INNER_PX = 12  # pinned: "12-24 px surrounding annulus"
LOCAL_CONTRAST_ANNULUS_OUTER_PX = 24  # pinned

# --- candidate/spot finding (colour-ratio, high recall) -----------------------
SPOT_LOCAL_WINDOW_PX = 9  # placeholder: smoothing window for local colour-ratio maps, not pinned in notes
# Deviation-from-local-background thresholds for the ratio-based spot finder
# - none of these are pinned numerically in the notes -> calibration
# placeholders.
THRESH_SPOT_HAEM_B_OVER_G_DEVIATION = 0.05
THRESH_SPOT_HE_SATURATION = 0.35
THRESH_SPOT_NFI_B_OVER_G_DEVIATION = 0.05

FEATURE_ORDER = [
    "b_over_g", "r_over_g", "saturation",
    "grad_mag_rim", "edge_sharpness", "boundary_smoothness",
    "area_px", "perimeter_px", "circularity", "eccentricity", "solidity",
    "dist_od_dd", "dist_fovea_dd", "dist_vessel_px",
    "local_contrast", "bg_ratio",
]


# --- colour ratios ------------------------------------------------------------

def _mean_rgb(pixels):
    """pixels: (N, 3) array of RGB samples."""
    if pixels.size == 0:
        return np.zeros(3)
    return pixels.astype(np.float64).mean(axis=0)


def b_over_g(pixels):
    m = _mean_rgb(pixels)
    return float(m[2] / (m[1] + 1e-6))


def r_over_g(pixels):
    m = _mean_rgb(pixels)
    return float(m[0] / (m[1] + 1e-6))


def mean_saturation(pixels):
    if pixels.size == 0:
        return 0.0
    hsv = cv2.cvtColor(pixels.reshape(-1, 1, 3).astype(np.uint8), cv2.COLOR_RGB2HSV)
    return float(hsv[..., 1].mean()) / 255.0


# --- candidate/spot finding ---------------------------------------------------

def _local_ratio_maps(image_rgb, window_px=SPOT_LOCAL_WINDOW_PX):
    img = image_rgb.astype(np.float64)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    r_loc = cv2.boxFilter(r, -1, (window_px, window_px))
    g_loc = cv2.boxFilter(g, -1, (window_px, window_px))
    b_loc = cv2.boxFilter(b, -1, (window_px, window_px))
    b_over_g_map = b_loc / (g_loc + 1e-6)
    r_over_g_map = r_loc / (g_loc + 1e-6)
    hsv = cv2.cvtColor(image_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV)
    sat_map = hsv[..., 1].astype(np.float64) / 255.0
    sat_map = cv2.boxFilter(sat_map, -1, (window_px, window_px))
    return b_over_g_map, r_over_g_map, sat_map


def find_candidate_spots(image_rgb, mask, lesion_class):
    """High-recall, low-precision spot mask from local colour-ratio
    deviation (step 3 input for Haemorrhage/Hard-Exudate/Nerve-Fibre-
    Ischemia, per the notes' "Pre-Feature Engineering" section). Deviation
    thresholds are calibration placeholders (see module constants)."""
    b_g_map, r_g_map, sat_map = _local_ratio_maps(image_rgb)
    bg_window = max(LOCAL_CONTRAST_ANNULUS_OUTER_PX, SPOT_LOCAL_WINDOW_PX * 3)
    local_bg_b_g = cv2.boxFilter(b_g_map, -1, (bg_window, bg_window))

    if lesion_class == "haemorrhage":
        candidate = (local_bg_b_g - b_g_map) > THRESH_SPOT_HAEM_B_OVER_G_DEVIATION
    elif lesion_class == "hard_exudate":
        candidate = sat_map > THRESH_SPOT_HE_SATURATION
    elif lesion_class == "nerve_fibre_ischemia":
        candidate = (b_g_map - local_bg_b_g) > THRESH_SPOT_NFI_B_OVER_G_DEVIATION
    else:
        candidate = np.zeros(b_g_map.shape, dtype=bool)

    if mask is not None:
        candidate &= mask
    return candidate


# --- per-candidate feature extraction -----------------------------------------

def local_contrast(gray, mask, inner_px=LOCAL_CONTRAST_ANNULUS_INNER_PX, outer_px=LOCAL_CONTRAST_ANNULUS_OUTER_PX):
    """candidate mean vs a 12-24 px surrounding annulus (pinned range).
    gray/mask should already be a small patch padded by >= outer_px around
    the candidate, not the full image, for performance."""
    inner_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * inner_px + 1,) * 2)
    outer_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * outer_px + 1,) * 2)
    inner_dilated = cv2.dilate(mask.astype(np.uint8), inner_kernel).astype(bool)
    outer_dilated = cv2.dilate(mask.astype(np.uint8), outer_kernel).astype(bool)
    annulus = outer_dilated & ~inner_dilated
    candidate_mean = float(gray[mask].mean()) if mask.any() else 0.0
    annulus_mean = float(gray[annulus].mean()) if annulus.any() else candidate_mean
    return candidate_mean - annulus_mean, candidate_mean, annulus_mean


def _crop_with_pad(image, bbox, pad):
    x, y, w, h = bbox
    H, W = image.shape[:2]
    x0, y0 = max(0, x - pad), max(0, y - pad)
    x1, y1 = min(W, x + w + pad), min(H, y + h + pad)
    return image[y0:y1, x0:x1], (x0, y0)


def _largest_contour(mask):
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return None
    return max(contours, key=cv2.contourArea)


def _radial_edge_sharpness(gray, cx, cy, max_radius_px=15, n_samples=16):
    """Steepness of the intensity transition across the candidate boundary,
    averaged over several outward rays from the centroid: max |gradient| of
    the radially-averaged intensity profile. Documented approximation - the
    notes describe sharp-vs-gradual qualitatively but do not pin a formula."""
    h, w = gray.shape
    profiles = []
    for k in range(n_samples):
        theta = 2 * np.pi * k / n_samples
        dx, dy = np.cos(theta), np.sin(theta)
        vals = []
        for r in range(max_radius_px):
            x, y = int(round(cx + r * dx)), int(round(cy + r * dy))
            if 0 <= x < w and 0 <= y < h:
                vals.append(gray[y, x])
            else:
                break
        if len(vals) >= 2:
            profiles.append(vals)
    if not profiles:
        return 0.0
    min_len = min(len(p) for p in profiles)
    if min_len < 2:
        return 0.0
    profile = np.mean([p[:min_len] for p in profiles], axis=0)
    gradient = np.gradient(profile)
    return float(np.max(np.abs(gradient)))


def extract_candidate_features(image_rgb, shade_corrected_green, candidate, vessel_mask,
                                optic_disc=None, fovea=None, fov_mask=None,
                                vessel_distance_transform=None):
    """Step 4 (mandatory): the full per-candidate feature vector - colour,
    edge, shape, location, context (see notes, "Feature Engineering"
    section). NEVER absolute intensity - see module docstring.

    candidate: dict with "bbox" (x, y, w, h), "mask_local" (boolean mask
    cropped to bbox) and "centroid" (cx, cy) in full-image coordinates.
    vessel_distance_transform: optional precomputed
    scipy.ndimage.distance_transform_edt(~vessel_mask), passed in so it is
    computed once per image rather than once per candidate.
    """
    x, y, w, h = candidate["bbox"]
    mask_local = candidate["mask_local"]
    cx, cy = candidate["centroid"]

    pad = LOCAL_CONTRAST_ANNULUS_OUTER_PX
    rgb_crop, (ox, oy) = _crop_with_pad(image_rgb, (x, y, w, h), pad)
    green_crop, _ = _crop_with_pad(shade_corrected_green, (x, y, w, h), pad)

    mask_full_crop = np.zeros(rgb_crop.shape[:2], dtype=bool)
    mask_full_crop[y - oy:y - oy + h, x - ox:x - ox + w] = mask_local

    # colour (ratios only)
    candidate_pixels = rgb_crop[mask_full_crop]
    colour = {
        "b_over_g": b_over_g(candidate_pixels),
        "r_over_g": r_over_g(candidate_pixels),
        "saturation": mean_saturation(candidate_pixels),
    }

    # edge
    gray_crop = cv2.cvtColor(rgb_crop.astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float64)
    gx = cv2.Sobel(gray_crop, cv2.CV_64F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray_crop, cv2.CV_64F, 0, 1, ksize=3)
    grad_mag = np.hypot(gx, gy)
    rim = cv2.dilate(mask_full_crop.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool) & ~mask_full_crop
    grad_at_rim = float(grad_mag[rim].mean()) if rim.any() else 0.0
    edge_sharpness = _radial_edge_sharpness(gray_crop, cx - ox, cy - oy)

    contour = _largest_contour(mask_full_crop)
    if contour is not None and len(contour) >= 3:
        perimeter = cv2.arcLength(contour, True)
        hull = cv2.convexHull(contour)
        hull_perimeter = cv2.arcLength(hull, True)
        boundary_smoothness = float(hull_perimeter / perimeter) if perimeter > 0 else 0.0
    else:
        perimeter = 0.0
        boundary_smoothness = 0.0

    edge = {"grad_mag_rim": grad_at_rim, "edge_sharpness": edge_sharpness, "boundary_smoothness": boundary_smoothness}

    # shape
    area_px = int(mask_full_crop.sum())
    if contour is not None and len(contour) >= 5:
        (_, _), (major, minor), _ = cv2.fitEllipse(contour)
        major, minor = max(major, minor), min(major, minor)
        eccentricity = float(np.sqrt(max(1 - (minor / major) ** 2, 0.0))) if major > 0 else 0.0
    else:
        eccentricity = 0.0
    circularity = float(4 * np.pi * area_px / (perimeter ** 2)) if perimeter > 0 else 0.0
    if contour is not None:
        hull_area = cv2.contourArea(cv2.convexHull(contour))
    else:
        hull_area = 0.0
    solidity = float(area_px / hull_area) if hull_area > 0 else 0.0

    shape = {"area_px": area_px, "perimeter_px": float(perimeter), "circularity": circularity,
              "eccentricity": eccentricity, "solidity": solidity}

    # location
    dd_px = 2.0 * optic_disc.radius if optic_disc is not None else None
    if optic_disc is not None and dd_px:
        dist_od = float(np.hypot(cx - optic_disc.center_x, cy - optic_disc.center_y) / dd_px)
    else:
        dist_od = float("nan")
    if fovea is not None and dd_px:
        dist_fovea = float(np.hypot(cx - fovea.x, cy - fovea.y) / dd_px)
    else:
        dist_fovea = float("nan")

    if vessel_distance_transform is not None:
        dist_transform = vessel_distance_transform
    elif vessel_mask is not None and vessel_mask.any():
        dist_transform = ndimage.distance_transform_edt(~vessel_mask)
    else:
        dist_transform = None
    if dist_transform is not None:
        yi = int(np.clip(round(cy), 0, dist_transform.shape[0] - 1))
        xi = int(np.clip(round(cx), 0, dist_transform.shape[1] - 1))
        dist_vessel_px = float(dist_transform[yi, xi])
    else:
        dist_vessel_px = float("nan")

    location = {"dist_od_dd": dist_od, "dist_fovea_dd": dist_fovea, "dist_vessel_px": dist_vessel_px}

    # context
    contrast, cand_mean, bg_mean = local_contrast(green_crop, mask_full_crop)
    bg_ratio = float(cand_mean / bg_mean) if bg_mean != 0 else float("nan")
    context = {"local_contrast": contrast, "bg_ratio": bg_ratio}

    features = {}
    features.update(colour)
    features.update(edge)
    features.update(shape)
    features.update(location)
    features.update(context)
    return features


def features_to_matrix(feature_dicts):
    matrix = np.array(
        [[np.nan_to_num(fd.get(name, np.nan), nan=0.0, posinf=0.0, neginf=0.0) for name in FEATURE_ORDER]
         for fd in feature_dicts],
        dtype=np.float64,
    )
    if matrix.size == 0:
        matrix = matrix.reshape(0, len(FEATURE_ORDER))
    return matrix, list(FEATURE_ORDER)

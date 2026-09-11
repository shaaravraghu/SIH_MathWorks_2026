"""#VESSELS (a)-(c): matched-filter + Frangi calibre map, and fine-scale-excess
abnormal-vessel labelling (see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN,
"VESSELS" section).

(b): calibre comes from the Frangi SCALE (sigma) at which the multi-scale
response peaks, never from the blobness ratio rb = |lambda1|/|lambda2| - rb is
built to be scale-invariant (tube vs blob shape only) and the notes are
emphatic it carries almost no width information.

(c): major-vessel / neovascularisation / IRMA labelling is by FINE-SCALE
EXCESS, not density - density alone is measured WRONG-SIGNED (rho -0.391) and
density x orientation-incoherence is incoherent (-0.307..+0.279); fine-scale
excess measured rho +0.438 and is stable across every sharpness band.
IRMA vs NV is NOT separable on a colour fundus image by this method (needs
fluorescein angiography / FGADR depth+leakage annotations) - labels 1 and 2
are therefore reported as a single "abnormal vessel" class here.
nv_score itself is UNVALIDATED: it correlates with grade but has never been
checked against annotated neovascularisation (APTOS has none).

Frangi is implemented directly via Hessian eigenvalues (scipy.ndimage
Gaussian derivatives) rather than skimage.filters.frangi: skimage is not
part of stage1's numpy/opencv/scipy stack and is not installed in this
environment - documented judgment call.

line_detector() below is reused VERBATIM (not approximated) from the
previous Module 2 implementation
(code_testing/python/extract_module2_features.py::line_detector), per the
Module3_Plan.md feature-schema spec, so the measured nv_score evidence
(within rho +0.355, code_testing) transfers unchanged. It expects the green
channel scaled to [0, 1] (it inverts internally: dark ridges respond high).
"""

from dataclasses import dataclass

import cv2
import numpy as np
from scipy import ndimage

# --- scale table (VESSELS, shared px<->um conversion) -----------------------
UM_PER_PX = 14.9
VESSEL_WIDTH_UM_MIN = 40.0
VESSEL_WIDTH_UM_MAX = 150.0
VESSEL_WIDTH_PX_MIN = VESSEL_WIDTH_UM_MIN / UM_PER_PX   # ~2.7 px
VESSEL_WIDTH_PX_MAX = VESSEL_WIDTH_UM_MAX / UM_PER_PX   # ~10.1 px

# calibre bands, in px, anchored to the scale table (pinned exactly in notes)
MINOR_VESSEL_MIN_PX = VESSEL_WIDTH_PX_MIN     # 2.7 px
FIRST_BRANCH_MIN_PX = 4.0
MAJOR_VESSEL_MIN_PX = 7.0
# Widths above VESSEL_WIDTH_PX_MAX (10.1 px, the scale table's own upper
# bound) are outside the normal major-vessel band -> venous beading. The
# notes say "width above the major-vessel band" without a numeric cap, so
# the scale table's own ceiling is used as that cap - documented judgment
# call, flagged for review.
BEADING_MIN_PX = VESSEL_WIDTH_PX_MAX

VESSEL_CALIBRE_BEADING = 0
VESSEL_CALIBRE_MAJOR = 1
VESSEL_CALIBRE_FIRST_BRANCH = 2
VESSEL_CALIBRE_MINOR = 3

VESSEL_CLASS_MAJOR = 0
VESSEL_CLASS_NEOVASCULARISATION = 1
VESSEL_CLASS_IRMA = 2

# --- (a) matched filtering ---------------------------------------------------
# Chaudhuri-style: a bank of oriented Gaussian-cross-section kernels, matched
# to "approx. width of main & 1st branch" vessels. The notes do not pin
# sigma/length/orientation-count/binarisation-percentile for this filter ->
# placeholders below (calibrate before use).
MATCHED_FILTER_SIGMA_PX = 2.0           # placeholder: ~half of the 4-10px major/1st-branch band
MATCHED_FILTER_LENGTH_PX = 9            # placeholder
MATCHED_FILTER_N_ORIENTATIONS = 12      # placeholder: 15 degree steps
THRESH_MATCHED_FILTER_PERCENTILE = 90.0  # placeholder: binarisation threshold not pinned in notes

# --- (b) Frangi multi-scale vesselness --------------------------------------
# sigma ~ vessel_radius / sqrt(2). Do NOT add a sigma below ~2.7 px - the
# notes report that a sigma of 1.2 px (18 um) corrupted the map, moving
# measured branchpoints from 195 to 2,539.
FRANGI_SIGMA_FLOOR_PX = 2.7
# Tension in the notes, documented rather than silently resolved: the width
# formula above would want sigma ~0.95px for the MINOR_VESSEL_MIN_PX (2.7px)
# band, which is below the floor just stated. The floor wins here (per the
# explicit branchpoint-corruption warning), so calibre resolution below
# roughly a 7.6px-equivalent width is coarser than the formula alone would
# give. Judgment call - flagged for review.
FRANGI_SIGMA_MAX_PX = 6.0   # placeholder: covers up to ~17px width (venous-beading range)
FRANGI_N_SCALES = 8         # placeholder: number of sigma steps in the scan
FRANGI_BETA = 0.5           # standard Frangi blobness-term sensitivity
FRANGI_GAMMA = 15.0         # standard Frangi structureness-term sensitivity (placeholder magnitude - image-intensity dependent)

# --- (c) fine-scale excess (major / NV / IRMA) ------------------------------
FINE_LINE_LENGTH_PX = 9     # pinned: L=9
FINE_LINE_WIDTH_PX = 11     # pinned: W=11
COARSE_LINE_LENGTH_PX = 31  # pinned: L=31
COARSE_LINE_WIDTH_PX = 31   # pinned: W=31
EXCESS_PERCENTILE = 92.0    # pinned: p92
COARSE_DILATE_KERNEL_PX = 5  # pinned: 5x5 dilation
LINE_DETECTOR_N_ORIENTATIONS = 12  # pinned (matches the reused line_detector definition)

NVD_MAX_DISC_DIAMETERS = 1.0  # pinned: NVD if within 1 DD of the OD centre


@dataclass
class VesselMapResult:
    matched_filter_mask: np.ndarray  # (a): boolean, pixel true -> 1
    vesselness: np.ndarray           # (b): max Frangi response over scale
    width_px: np.ndarray             # (b): calibre width estimate, from argmax sigma
    calibre: np.ndarray              # (b): int8 bands, -1 = reject/not-a-vessel, else 0-3
    vessel_class: np.ndarray         # (c): int8, -1 = no vessel, else 0-2 (see classify_vessel_pixels)
    excess_mask: np.ndarray          # (c): fine-scale-excess boolean mask
    nv_score: float                  # (c): 100 * |excess| / |FOV|, UNVALIDATED (see module docstring)


# --- (a) matched filtering ---------------------------------------------------

def _oriented_matched_kernel(theta_deg, sigma=MATCHED_FILTER_SIGMA_PX, length=MATCHED_FILTER_LENGTH_PX):
    half = length // 2
    ys, xs = np.mgrid[-half:half + 1, -half:half + 1].astype(np.float64)
    theta = np.deg2rad(theta_deg)
    x_along = xs * np.cos(theta) + ys * np.sin(theta)
    y_across = -xs * np.sin(theta) + ys * np.cos(theta)
    kernel = -np.exp(-(y_across ** 2) / (2 * sigma ** 2))
    kernel[np.abs(x_along) > length / 2.0] = 0.0
    nonzero = kernel[kernel != 0]
    if nonzero.size:
        kernel -= nonzero.mean()
    return kernel


def matched_filter_response(green):
    green = green.astype(np.float64)
    best = None
    for k in range(MATCHED_FILTER_N_ORIENTATIONS):
        theta = 180.0 * k / MATCHED_FILTER_N_ORIENTATIONS
        kernel = _oriented_matched_kernel(theta)
        resp = cv2.filter2D(green, -1, kernel)
        best = resp if best is None else np.maximum(best, resp)
    return best


def matched_filter_vessel_map(green, fov_mask=None):
    """(a): boolean vessel map at approx. main & 1st-branch width via a bank
    of oriented matched filters (Chaudhuri-style). pixel true -> 1, per the
    notes' concept line."""
    response = matched_filter_response(green)
    values = response[fov_mask] if fov_mask is not None else response
    thresh = np.percentile(values, THRESH_MATCHED_FILTER_PERCENTILE) if values.size else 0.0
    vessel_map = response > thresh
    if fov_mask is not None:
        vessel_map &= fov_mask
    return vessel_map


# --- (b) Frangi multi-scale vesselness --------------------------------------

def _hessian_elements(gray, sigma):
    Ixx = ndimage.gaussian_filter(gray, sigma=sigma, order=(0, 2))
    Iyy = ndimage.gaussian_filter(gray, sigma=sigma, order=(2, 0))
    Ixy = ndimage.gaussian_filter(gray, sigma=sigma, order=(1, 1))
    # gamma-normalised derivatives (standard scale-space practice) so
    # responses are comparable across sigma.
    norm = sigma ** 2
    return Ixx * norm, Iyy * norm, Ixy * norm


def _hessian_eigenvalues(Ixx, Iyy, Ixy):
    tmp = np.sqrt((Ixx - Iyy) ** 2 + 4 * Ixy ** 2)
    a = 0.5 * (Ixx + Iyy + tmp)
    b = 0.5 * (Ixx + Iyy - tmp)
    swap = np.abs(a) > np.abs(b)
    lambda1 = np.where(swap, b, a)
    lambda2 = np.where(swap, a, b)
    return lambda1, lambda2


def frangi_response(gray, sigma, beta=FRANGI_BETA, gamma=FRANGI_GAMMA, dark_ridges=True):
    """2D Frangi vesselness at one scale. Retinal vessels are DARK relative
    to background in the green channel, so dark_ridges=True keeps only the
    polarity where the cross-ridge second derivative is positive
    (lambda2 > 0); bright-ridge structure is suppressed."""
    Ixx, Iyy, Ixy = _hessian_elements(gray.astype(np.float64), sigma)
    lambda1, lambda2 = _hessian_eigenvalues(Ixx, Iyy, Ixy)
    lambda2_safe = np.where(lambda2 == 0, 1e-6, lambda2)

    rb = lambda1 / lambda2_safe  # blobness - NOT used for width, see module docstring
    s = np.sqrt(lambda1 ** 2 + lambda2 ** 2)
    v = np.exp(-(rb ** 2) / (2 * beta ** 2)) * (1 - np.exp(-(s ** 2) / (2 * gamma ** 2)))

    polarity_ok = (lambda2 > 0) if dark_ridges else (lambda2 < 0)
    v = np.where(polarity_ok, v, 0.0)
    return v


def frangi_sigma_scale_set():
    """Sigma scan array, floored at FRANGI_SIGMA_FLOOR_PX per the
    branchpoint-corruption caveat (see module docstring)."""
    return np.linspace(FRANGI_SIGMA_FLOOR_PX, FRANGI_SIGMA_MAX_PX, FRANGI_N_SCALES)


def multiscale_frangi(gray, sigmas=None):
    if sigmas is None:
        sigmas = frangi_sigma_scale_set()
    responses = np.stack([frangi_response(gray, s) for s in sigmas], axis=0)
    best_idx = np.argmax(responses, axis=0)
    vesselness = np.max(responses, axis=0)
    sigma_at_peak = np.asarray(sigmas)[best_idx]
    return vesselness, sigma_at_peak


def calibre_width_px(sigma_at_peak):
    """Inverse of sigma ~ vessel_radius / sqrt(2): width = 2*sqrt(2)*sigma."""
    return 2.0 * np.sqrt(2.0) * sigma_at_peak


def band_calibre(width_px, vessel_mask=None):
    bands = np.full(width_px.shape, -1, dtype=np.int8)  # -1 = reject / not a vessel
    bands[width_px >= MINOR_VESSEL_MIN_PX] = VESSEL_CALIBRE_MINOR
    bands[width_px >= FIRST_BRANCH_MIN_PX] = VESSEL_CALIBRE_FIRST_BRANCH
    bands[width_px >= MAJOR_VESSEL_MIN_PX] = VESSEL_CALIBRE_MAJOR
    bands[width_px >= BEADING_MIN_PX] = VESSEL_CALIBRE_BEADING
    if vessel_mask is not None:
        bands[~vessel_mask] = -1
    return bands


def build_vessel_calibre_map(green, vessel_mask=None, sigmas=None):
    vesselness, sigma_at_peak = multiscale_frangi(green, sigmas)
    width_px = calibre_width_px(sigma_at_peak)
    bands = band_calibre(width_px, vessel_mask=vessel_mask)
    return {"vesselness": vesselness, "width_px": width_px, "calibre": bands}


# --- (c) fine-scale excess (major / NV / IRMA) ------------------------------

def _line_se(length, deg):
    se = np.zeros((length, length), dtype=np.float64)
    se[length // 2, :] = 1.0
    rot = cv2.getRotationMatrix2D((length / 2 - 0.5, length / 2 - 0.5), deg, 1.0)
    return cv2.warpAffine(se, rot, (length, length))


def line_detector(gray_0_1, length, width, n_orientations=LINE_DETECTOR_N_ORIENTATIONS):
    """Reused verbatim from the previous Module 2 implementation
    (code_testing/python/extract_module2_features.py::line_detector), per
    Module3_Plan.md's spec, so the measured nv_score evidence transfers.
    gray_0_1 must be [0, 1]-scaled - it inverts internally (dark ridges
    respond high) and box-blur-subtracts the local mean."""
    inv = 1.0 - gray_0_1
    box = cv2.blur(inv, (width, width))
    best = np.full(gray_0_1.shape, -np.inf, dtype=np.float64)
    for a in range(n_orientations):
        se = _line_se(length, a * 180.0 / n_orientations)
        kernel = se / max(se.sum(), 1e-6)
        resp = cv2.filter2D(inv, -1, kernel)
        best = np.maximum(best, resp)
    return best - box


def fine_scale_excess(green_0_1, fov_mask=None):
    fine = line_detector(green_0_1, FINE_LINE_LENGTH_PX, FINE_LINE_WIDTH_PX)
    coarse = line_detector(green_0_1, COARSE_LINE_LENGTH_PX, COARSE_LINE_WIDTH_PX)

    vals_fine = fine[fov_mask] if fov_mask is not None else fine
    vals_coarse = coarse[fov_mask] if fov_mask is not None else coarse
    p_fine = np.percentile(vals_fine, EXCESS_PERCENTILE) if vals_fine.size else 0.0
    p_coarse = np.percentile(vals_coarse, EXCESS_PERCENTILE) if vals_coarse.size else 0.0

    kernel = np.ones((COARSE_DILATE_KERNEL_PX, COARSE_DILATE_KERNEL_PX), np.uint8)
    coarse_dilated = cv2.dilate((coarse > p_coarse).astype(np.uint8), kernel).astype(bool)
    excess = (fine > p_fine) & ~coarse_dilated
    if fov_mask is not None:
        excess &= fov_mask

    fov_area = fov_mask.sum() if fov_mask is not None else green_0_1.size
    nv_score = 100.0 * float(excess.sum()) / max(float(fov_area), 1.0)
    return {"fine": fine, "coarse": coarse, "excess": excess, "nv_score": nv_score}


def classify_vessel_pixels(calibre_bands, excess_mask):
    """(c) label: 0 = major/regular vessel (Frangi calibre, not excess-
    flagged); 1|2 = abnormal vessel (neovascularisation/IRMA, reported here
    as a single combined class - see module docstring). -1 = no vessel."""
    vessel_present = calibre_bands >= 0
    abnormal = vessel_present & excess_mask
    vessel_class = np.where(abnormal, VESSEL_CLASS_NEOVASCULARISATION, VESSEL_CLASS_MAJOR)
    vessel_class = np.where(vessel_present, vessel_class, -1)
    return vessel_class.astype(np.int8)


def split_nvd_nve(excess_mask, optic_disc):
    """NVD if a candidate's centroid is within 1 DD of the OD centre, else
    NVE. IRMA vs NV cannot be separated on colour fundus alone (see module
    docstring) - every candidate here is under the single combined
    abnormal-vessel class; this only splits by LOCATION, not NV-vs-IRMA."""
    n_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
        excess_mask.astype(np.uint8), connectivity=8)
    dd_px = 2.0 * optic_disc.radius
    nvd, nve = [], []
    for i in range(1, n_labels):
        cx, cy = centroids[i]
        dist = float(np.hypot(cx - optic_disc.center_x, cy - optic_disc.center_y))
        entry = {"centroid": (float(cx), float(cy)), "area_px": int(stats[i, cv2.CC_STAT_AREA])}
        (nvd if dist <= NVD_MAX_DISC_DIAMETERS * dd_px else nve).append(entry)
    return {"nvd": nvd, "nve": nve, "nvd_count": len(nvd), "nve_count": len(nve)}


# --- top-level entry point ---------------------------------------------------

def build_vessel_map(image_rgb, fov_mask=None) -> VesselMapResult:
    green = image_rgb[..., 1].astype(np.float64)
    green_01 = np.clip(green / 255.0, 0.0, 1.0)

    matched = matched_filter_vessel_map(green, fov_mask=fov_mask)
    calibre_result = build_vessel_calibre_map(green, vessel_mask=matched)
    excess = fine_scale_excess(green_01, fov_mask=fov_mask)
    vessel_class = classify_vessel_pixels(calibre_result["calibre"], excess["excess"])

    return VesselMapResult(
        matched_filter_mask=matched,
        vesselness=calibre_result["vesselness"],
        width_px=calibre_result["width_px"],
        calibre=calibre_result["calibre"],
        vessel_class=vessel_class,
        excess_mask=excess["excess"],
        nv_score=excess["nv_score"],
    )

"""#4 Enhancement (Illumination / Exposure / Contrast) for Borderline images.

#4.1 Flat Field Correction  -> Exit (Fail)
#4.2 CLAHE                  -> Exit (Fail)
"""

import cv2
import numpy as np

# #4.1
FFC_DOWNSCALE = 0.125            # estimate illumination at reduced resolution
FFC_SEVERE_LOW = 0.35            # background / global-median below this = severely dark
FFC_SEVERE_HIGH = 1.8            # background / global-median above this = severely bright
FFC_WHOLE_IMAGE_SEVERE_FRAC = 0.9
FFC_MAX_CONTRAST_LOSS = 0.25     # >25% drop in local contrast -> retain original

# #4.2
CLAHE_CLIP_LIMITS = (2.0, 1.5, 1.0)   # try progressively milder parameters
CLAHE_TILE_GRID = (8, 8)
CLAHE_SATURATION_LEVEL_LOW = 5
CLAHE_SATURATION_LEVEL_HIGH = 250
CLAHE_MAX_SATURATION_INCREASE = 0.02  # absolute increase in saturated-pixel fraction
CLAHE_MAX_NOISE_INCREASE = 1.5        # ratio of high-frequency energy after/before


def local_contrast(channel: np.ndarray, mask: np.ndarray, ksize: int = 15) -> float:
    """Mean local standard deviation inside the FOV."""
    channel = channel.astype(np.float64)
    mean = cv2.blur(channel, (ksize, ksize))
    sq_mean = cv2.blur(channel ** 2, (ksize, ksize))
    local_std = np.sqrt(np.maximum(sq_mean - mean ** 2, 0))
    return float(local_std[mask].mean()) if mask.any() else 0.0


def saturation_fraction(channel: np.ndarray, mask: np.ndarray) -> float:
    vals = channel[mask]
    if vals.size == 0:
        return 0.0
    return float(np.mean((vals <= CLAHE_SATURATION_LEVEL_LOW) | (vals >= CLAHE_SATURATION_LEVEL_HIGH)))


def high_frequency_energy(channel: np.ndarray, mask: np.ndarray) -> float:
    lap = cv2.Laplacian(channel.astype(np.float64), cv2.CV_64F)
    return float(np.mean(np.abs(lap[mask]))) if mask.any() else 0.0


# --- #4.1 Flat Field Correction ----------------------------------------------

def _fit_plane(background: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Plane fit: a*x + b*y + c, models directional brightness variation."""
    h, w = background.shape
    yy, xx = np.mgrid[0:h, 0:w]
    A = np.column_stack([xx[mask], yy[mask], np.ones(mask.sum())])
    coeffs, *_ = np.linalg.lstsq(A, background[mask], rcond=None)
    return coeffs[0] * xx + coeffs[1] * yy + coeffs[2]


def _fit_radial(background: np.ndarray, mask: np.ndarray, degree: int = 2) -> np.ndarray:
    """Radial fit: polynomial in distance from FOV centre, models vignetting."""
    h, w = background.shape
    yy, xx = np.mgrid[0:h, 0:w]
    ys, xs = np.nonzero(mask)
    cy, cx = ys.mean(), xs.mean()
    r = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    r_norm = r / (r[mask].max() + 1e-6)
    coeffs = np.polyfit(r_norm[mask], background[mask], degree)
    return np.polyval(coeffs, r_norm)


def estimate_illumination_field(channel: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Estimate the smooth illumination field at reduced resolution, then
    upsample to full size. Plane and radial models are combined by taking
    whichever explains the low-res background with lower residual."""
    h, w = channel.shape
    small_w = max(8, int(w * FFC_DOWNSCALE))
    small_h = max(8, int(h * FFC_DOWNSCALE))

    small = cv2.resize(channel.astype(np.float64), (small_w, small_h), interpolation=cv2.INTER_AREA)
    small_mask = cv2.resize(mask.astype(np.uint8), (small_w, small_h), interpolation=cv2.INTER_NEAREST).astype(bool)

    if small_mask.sum() < 10:
        return np.full_like(channel, channel[mask].mean() if mask.any() else 1.0, dtype=np.float64)

    # Median filter suppresses vessels/lesions before fitting the background.
    ksize = max(3, (min(small_w, small_h) // 8) | 1)
    background = cv2.medianBlur(small.astype(np.float32), ksize).astype(np.float64)

    plane = _fit_plane(background, small_mask)
    radial = _fit_radial(background, small_mask)

    plane_resid = np.mean((background[small_mask] - plane[small_mask]) ** 2)
    radial_resid = np.mean((background[small_mask] - radial[small_mask]) ** 2)
    field_small = plane if plane_resid <= radial_resid else radial

    return cv2.resize(field_small, (w, h), interpolation=cv2.INTER_LINEAR)


def flat_field_correction(image: np.ndarray, mask: np.ndarray) -> dict:
    """#4.1. Normalises the image against its estimated illumination field,
    but only where illumination is severely low/high.

    Fails (exit) if the WHOLE image is severely low/high illuminated.
    Retains the original if correction significantly reduces local contrast.
    """
    img = image.astype(np.float64)
    green = img[..., 1]

    field = estimate_illumination_field(green, mask)
    global_median = float(np.median(green[mask])) if mask.any() else 1.0
    relative = field / (global_median + 1e-6)

    severe = ((relative < FFC_SEVERE_LOW) | (relative > FFC_SEVERE_HIGH)) & mask
    severe_frac = severe.sum() / max(mask.sum(), 1)

    if severe_frac >= FFC_WHOLE_IMAGE_SEVERE_FRAC:
        return {"status": "fail", "reason": "whole_image_severe_illumination",
                "image": image, "severe_fraction": severe_frac}

    if not severe.any():
        return {"status": "pass", "applied": False, "image": image, "severe_fraction": severe_frac}

    gain = global_median / np.maximum(field, 1e-6)
    # Feather the correction so only severely-lit regions are adjusted.
    weight = cv2.GaussianBlur(severe.astype(np.float64), (0, 0), sigmaX=max(image.shape[:2]) / 50)
    weight = np.clip(weight / (weight.max() + 1e-6), 0, 1)
    blended_gain = 1.0 + weight * (gain - 1.0)

    corrected = img * blended_gain[..., None]
    corrected[~mask] = img[~mask]
    corrected = np.clip(corrected, 0, 255).astype(np.uint8)

    before = local_contrast(green, mask)
    after = local_contrast(corrected[..., 1], mask)
    if before > 0 and (before - after) / before > FFC_MAX_CONTRAST_LOSS:
        return {"status": "pass", "applied": False, "reason": "contrast_loss_retain_original",
                "image": image, "severe_fraction": severe_frac}

    return {"status": "pass", "applied": True, "image": corrected, "severe_fraction": severe_frac}


# --- #4.2 CLAHE ---------------------------------------------------------------

def _apply_clahe_green(image: np.ndarray, mask: np.ndarray, clip_limit: float) -> np.ndarray:
    """CLAHE on the green (retinal-detail) channel, restricted to the FOV."""
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=CLAHE_TILE_GRID)
    out = image.copy()
    green = image[..., 1]
    enhanced = clahe.apply(green)
    out[..., 1] = np.where(mask, enhanced, green)
    return out


def clahe_enhancement(image: np.ndarray, mask: np.ndarray) -> dict:
    """#4.2. Tries progressively milder CLAHE parameters. Accepts the first
    that improves local contrast without a significant increase in
    saturation or noise; otherwise exits (fail)."""
    green = image[..., 1]
    base_contrast = local_contrast(green, mask)
    base_saturation = saturation_fraction(green, mask)
    base_noise = high_frequency_energy(green, mask)

    attempts = []
    for clip in CLAHE_CLIP_LIMITS:
        candidate = _apply_clahe_green(image, mask, clip)
        g = candidate[..., 1]
        contrast = local_contrast(g, mask)
        saturation = saturation_fraction(g, mask)
        noise = high_frequency_energy(g, mask)

        metrics = {
            "clip_limit": clip,
            "local_contrast": contrast,
            "saturation": saturation,
            "noise_ratio": noise / (base_noise + 1e-6),
        }
        attempts.append(metrics)

        contrast_ok = contrast > base_contrast
        saturation_ok = (saturation - base_saturation) <= CLAHE_MAX_SATURATION_INCREASE
        noise_ok = metrics["noise_ratio"] <= CLAHE_MAX_NOISE_INCREASE

        if contrast_ok and saturation_ok and noise_ok:
            return {"status": "pass", "image": candidate, "chosen": metrics, "attempts": attempts}

    return {"status": "fail", "reason": "clahe_degrades_image", "image": image, "attempts": attempts}


def enhance_borderline(image: np.ndarray, mask: np.ndarray) -> dict:
    """#4: Flat Field Correction -> CLAHE -> Image Updation."""
    ffc = flat_field_correction(image, mask)
    if ffc["status"] == "fail":
        return {"status": "fail", "stage": "flat_field_correction", "ffc": ffc}

    clahe = clahe_enhancement(ffc["image"], mask)
    if clahe["status"] == "fail":
        return {"status": "fail", "stage": "clahe", "ffc": ffc, "clahe": clahe}

    return {"status": "pass", "image": clahe["image"], "ffc": ffc, "clahe": clahe}

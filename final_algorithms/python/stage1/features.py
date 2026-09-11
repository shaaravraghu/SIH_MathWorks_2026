"""Stage 1 feature row for Module 3 (Module3_Plan.md §2.1, S1-01 .. S1-21).

Stage 1 contributes NO model inputs: every column is QC, CONF or EXCLUDE
(decision D7). Within resolution strata every sharpness metric's apparent link
to grade turns out to be the camera, and megapixels alone predicts referable DR
at AUC 0.809, so none of these may reach the grading network.

The cascade short-circuits on its first fail, but the CSV needs every column for
every image (Phase 2 exit criterion: no blanks; §4.4 records rejections per
grade). Metrics a failed cascade skipped are computed here anyway; metrics the
cascade did compute are reused so the row agrees with the verdict.
"""

import numpy as np
import cv2
from scipy import ndimage

from .enhancement import local_contrast, saturation_fraction
from .fov_detection import area_ratio_check, build_fov_mask
from .pipeline import load_rgb, run_stage1
from .sharpness_contrast import (brenner_gradient_gate, region_min, spec_slope_gate,
                                 tenengrad_var_gate, to_gray, variance_of_laplacian_normed)

STAGE1_COLUMNS = [
    "megapixels",               # S1-01
    "aspect_ratio",             # S1-02
    "area_ratio_s1",            # S1-03
    "area_ratio_s2",            # S1-04
    "black_region_pct",         # S1-05
    "varLapNorm",               # S1-06
    "specSlope",                # S1-07
    "brenner",                  # S1-08
    "tenengradVar",             # S1-09
    "regionMin",                # S1-10
    "region_centre",            # S1-11
    "region_q1",                # S1-12
    "region_q2",                # S1-13
    "region_q3",                # S1-14
    "region_q4",                # S1-15
    "illum_plane_tilt",         # S1-16
    "illum_radial",             # S1-17
    "local_contrast",           # S1-18
    "saturation_count",         # S1-19
    "stage1_verdict",           # S1-20
    "enhancement_applied",      # S1-21
]

STAGE1_ROLES = {
    "megapixels": "EXCLUDE", "aspect_ratio": "EXCLUDE", "black_region_pct": "EXCLUDE",
    "tenengradVar": "EXCLUDE",  # pooled rho +0.352 but within rho +0.024: the camera
    "area_ratio_s1": "QC", "area_ratio_s2": "QC", "varLapNorm": "QC", "specSlope": "QC",
    "brenner": "QC", "regionMin": "QC", "region_centre": "QC", "region_q1": "QC",
    "region_q2": "QC", "region_q3": "QC", "region_q4": "QC", "illum_plane_tilt": "QC",
    "illum_radial": "QC", "local_contrast": "QC", "saturation_count": "QC",
    "stage1_verdict": "CONF", "enhancement_applied": "CONF",
}

# Nearest column in data/aptos_train_module1_features.csv. Same name does not
# mean same algorithm (sampling differs), so compare by rank, not by value.
MODULE1_EQUIVALENT = {
    "megapixels": "megapixels", "aspect_ratio": "aspect", "black_region_pct": "black_bg_pct",
    "varLapNorm": "varLapNorm", "specSlope": "specSlope", "brenner": "brenner",
    "tenengradVar": "tenengradVar", "regionMin": "regionMin",
    "illum_plane_tilt": "bgTiltMag", "illum_radial": "bgRadial", "local_contrast": "localContrast",
}

# Counter-clockwise from top-right, the usual mathematical quadrant order.
REGION_QUADRANT_NAMES = {
    "region_q1": "top_right", "region_q2": "top_left",
    "region_q3": "bottom_left", "region_q4": "bottom_right",
}

# enhancement_applied is a bit field; > 0 means the image was altered (§6.4 routing).
ENHANCED_FLAT_FIELD = 1
ENHANCED_CLAHE = 2

# --- S1-16 / S1-17 illumination ------------------------------------------------
ILLUM_DOWNSCALE = 0.125
# Window must comfortably exceed the optic disc (~0.29 R across), or the disc
# survives into the "illumination" field.
ILLUM_WINDOW_FRAC_OF_R = 0.4


def illumination_fit(green: np.ndarray, mask: np.ndarray):
    """Plane tilt magnitude and radial slope of the background field (#4.1).

    Symmetric falloff is normal vignetting; asymmetric tilt is a fault, and
    separating them needs two fits. Coordinates are in units of the retinal
    radius and intensities in [0, 1], so both values mean the same thing at
    every resolution. A negative radial slope is the normal centre-bright field.
    """
    ys, xs = np.nonzero(mask)
    if ys.size < 10:
        return float("nan"), float("nan")
    cy, cx = ys.mean(), xs.mean()
    radius = max(np.sqrt(ys.size / np.pi), 1.0)

    h, w = green.shape
    small_w, small_h = max(8, int(w * ILLUM_DOWNSCALE)), max(8, int(h * ILLUM_DOWNSCALE))
    scale = w / small_w
    small = cv2.resize(green.astype(np.float32) / 255.0, (small_w, small_h), interpolation=cv2.INTER_AREA)
    small_mask = cv2.resize(mask.astype(np.uint8), (small_w, small_h),
                            interpolation=cv2.INTER_NEAREST).astype(bool)
    if small_mask.sum() < 10:
        return float("nan"), float("nan")

    # Black surround near 0 would drag the field down at the rim and fake a falloff.
    filled = small.copy()
    filled[~small_mask] = np.median(small[small_mask])
    win = max(5, int(2 * round(0.5 * ILLUM_WINDOW_FRAC_OF_R * radius / scale) + 1))
    background = ndimage.median_filter(filled, size=win, mode="nearest")

    sy, sx = np.nonzero(small_mask)
    x = (sx * scale - cx) / radius
    y = (sy * scale - cy) / radius
    values = background[small_mask]

    plane, *_ = np.linalg.lstsq(np.column_stack([x, y, np.ones(x.size)]), values, rcond=None)
    r = np.hypot(x, y)
    radial, *_ = np.linalg.lstsq(np.column_stack([r, np.ones(r.size)]), values, rcond=None)
    return float(np.hypot(plane[0], plane[1])), float(radial[0])


def _verdict(result: dict) -> str:
    if result["status"] == "fail":
        return "fail"
    return "borderline" if result.get("borderline") else "pass"


def extract_stage1_features(image, seed: int = 0) -> dict:
    """One S1-01 .. S1-21 row. image: file path or RGB uint8 array.

    Also returns the Stage 1 output under "_stage1" (final image and FOV mask),
    which Stage 2 consumes; it is not a CSV column.
    """
    if isinstance(image, str):
        image = load_rgb(image)

    result = run_stage1(image, seed=seed)
    rng = np.random.default_rng(seed)
    height, width = image.shape[:2]
    gray = to_gray(image)
    green = image[..., 1]

    if "fov_detection" in result:
        fov = result["fov_detection"]["fov"]
        area = result["fov_detection"]["area_ratio"]
    else:
        fov = build_fov_mask(image)
        area = area_ratio_check(fov)

    sharp = result.get("sharpness_contrast")
    brenner = sharp.brenner if sharp and sharp.brenner else brenner_gradient_gate(gray, rng=rng)
    if sharp and sharp.laplacian_spec:
        lap, spec = sharp.laplacian_spec["laplacian"], sharp.laplacian_spec["spec_slope"]
    else:
        lap, spec = variance_of_laplacian_normed(gray, rng=rng), spec_slope_gate(gray, rng=rng)
    tenengrad = sharp.tenengrad if sharp and sharp.tenengrad else tenengrad_var_gate(gray, rng=rng)
    regions = sharp.region_min if sharp and sharp.region_min else region_min(gray, lap, fov_mask=fov.mask)

    tilt, radial = illumination_fit(green, fov.mask)

    verdict = _verdict(result)
    applied = 0
    enhancement = result.get("enhancement")
    if verdict == "borderline" and enhancement:
        if enhancement["ffc"].get("applied"):
            applied |= ENHANCED_FLAT_FIELD
        if enhancement["clahe"]["status"] == "pass":
            applied |= ENHANCED_CLAHE

    row = {
        "megapixels": width * height / 1_000_000.0,
        "aspect_ratio": width / height,
        "area_ratio_s1": area["s1"],
        "area_ratio_s2": area["s2"],
        # Whole-image value; the #2.2 gate itself only samples 10% of rows.
        "black_region_pct": 100.0 * float((~fov.mask).mean()),
        "varLapNorm": lap["score"],
        "specSlope": spec["score"],
        "brenner": brenner["score"],
        "tenengradVar": tenengrad["score"],
        "regionMin": regions["score"],
        "region_centre": regions["region_scores"]["centre"],
        **{col: regions["region_scores"][name] for col, name in REGION_QUADRANT_NAMES.items()},
        "illum_plane_tilt": tilt,
        "illum_radial": radial,
        # Measured on the ORIGINAL image for every row, in [0, 1] units like Module 1.
        "local_contrast": local_contrast(green, fov.mask) / 255.0,
        # Stored as a percentage of FOV pixels: a raw count scales with megapixels,
        # which is camera identity.
        "saturation_count": 100.0 * saturation_fraction(green, fov.mask),
        "stage1_verdict": verdict,
        "enhancement_applied": applied,
    }
    row = {col: row[col] for col in STAGE1_COLUMNS}
    row["_stage1"] = {"image": result["image"], "fov_mask": fov.mask, "status": result["status"]}
    return row

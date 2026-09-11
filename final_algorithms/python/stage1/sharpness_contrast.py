"""#3 Sharpness/Contrast cascade.

Order (per workflow diagram): Brenner Gradient (#3.2) -> Variance of Laplacian
(NORMED) + SpecSlope (#3.1) -> TenengradVar (#3.3) -> Region Min (#3.4).

Region Min is retained because it is the only metric here that detects
PARTIAL blur (a single weak region makes the image ungradable even though
global/whole-image metrics average it away).

NOTE: exact pass/fail/borderline numeric thresholds for #3.1-#3.3 are not
pinned in the source notes (only the sampling strategy is). The THRESH_*
constants below are placeholders that must be calibrated empirically before
these gates are used to reject images; the sampling/metric math itself
follows the notes exactly.
"""

from dataclasses import dataclass

import numpy as np
from scipy import ndimage

DIAMETER_FRACTION = 0.75  # of image height, centered at image midpoint
POINT_SAMPLE_FRACTION = 0.10  # #3.1
SQUARE_AREA_FRACTION = 0.025  # #3.2 / #3.3, of retina area
N_SQUARES = 8  # #3.2 / #3.3

# Placeholder thresholds (calibrate against a labelled set before deploying).
THRESH_BRENNER_FAIL = 50.0
THRESH_LAPLACIAN_VAR_NORMED_FAIL = 0.0015
THRESH_LAPLACIAN_VAR_NORMED_BORDERLINE = 0.0030
THRESH_TENENGRAD_VAR_FAIL = 0.02
THRESH_TENENGRAD_VAR_BORDERLINE = 0.05
THRESH_REGION_MIN_FAIL = 0.0010
THRESH_REGION_MIN_BORDERLINE = 0.0020


def to_gray(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return image.astype(np.float64)
    # Rec. 601 luma.
    r, g, b = image[..., 0], image[..., 1], image[..., 2]
    return (0.299 * r + 0.587 * g + 0.114 * b).astype(np.float64)


def _retina_center_and_radius(image_shape, center=None):
    h, w = image_shape[:2]
    if center is None:
        center = (h // 2, w // 2)
    radius = (DIAMETER_FRACTION * h) / 2.0
    return center, radius


def sample_points_in_disk(image_shape, n_points=None, center=None, rng=None):
    """#3.1 sampling: random points within the 0.75*height-diameter disk."""
    if rng is None:
        rng = np.random.default_rng()
    (cy, cx), radius = _retina_center_and_radius(image_shape, center)

    if n_points is None:
        n_points = max(1, int(round(np.pi * radius ** 2 * POINT_SAMPLE_FRACTION)))

    theta = rng.uniform(0, 2 * np.pi, size=n_points * 3)
    r = radius * np.sqrt(rng.uniform(0, 1, size=n_points * 3))
    rows = (cy + r * np.sin(theta)).astype(int)
    cols = (cx + r * np.cos(theta)).astype(int)

    h, w = image_shape[:2]
    valid = (rows >= 2) & (rows < h - 2) & (cols >= 2) & (cols < w - 2)
    rows, cols = rows[valid][:n_points], cols[valid][:n_points]
    return rows, cols


def sample_squares_in_disk(image_shape, n_squares=N_SQUARES, center=None, rng=None):
    """#3.2 / #3.3 sampling: n_squares patches each ~SQUARE_AREA_FRACTION of retina area."""
    if rng is None:
        rng = np.random.default_rng()
    (cy, cx), radius = _retina_center_and_radius(image_shape, center)

    retina_area = np.pi * radius ** 2
    side = int(round(np.sqrt(retina_area * SQUARE_AREA_FRACTION)))
    side = max(side, 4)

    h, w = image_shape[:2]
    boxes = []
    attempts = 0
    while len(boxes) < n_squares and attempts < n_squares * 50:
        attempts += 1
        theta = rng.uniform(0, 2 * np.pi)
        r = (radius - side) * np.sqrt(rng.uniform(0, 1))
        row = int(cy + r * np.sin(theta))
        col = int(cx + r * np.cos(theta))
        r0, r1 = row - side // 2, row - side // 2 + side
        c0, c1 = col - side // 2, col - side // 2 + side
        if r0 < 0 or c0 < 0 or r1 >= h or c1 >= w:
            continue
        boxes.append((r0, r1, c0, c1))
    return boxes


# --- #3.2 Brenner Gradient ---------------------------------------------------

def brenner_gradient(patch: np.ndarray, shift: int = 2) -> float:
    """Brenner gradient, evaluated in both directions ("the 2 functions")
    and combined as their mean."""
    patch = patch.astype(np.float64)
    h, w = patch.shape

    horiz = 0.0
    if w > shift:
        diff_h = patch[:, shift:] - patch[:, :-shift]
        horiz = float(np.mean(diff_h ** 2))

    vert = 0.0
    if h > shift:
        diff_v = patch[shift:, :] - patch[:-shift, :]
        vert = float(np.mean(diff_v ** 2))

    return (horiz + vert) / 2.0


def brenner_gradient_gate(gray: np.ndarray, rng=None) -> dict:
    boxes = sample_squares_in_disk(gray.shape, rng=rng)
    scores = [brenner_gradient(gray[r0:r1, c0:c1]) for r0, r1, c0, c1 in boxes]
    score = float(np.mean(scores)) if scores else 0.0
    status = "fail" if score < THRESH_BRENNER_FAIL else "pass"
    return {"score": score, "status": status, "n_patches": len(boxes)}


# --- #3.1 Variance of Laplacian (NORMED) + SpecSlope -------------------------

def _point_laplacian(gray: np.ndarray, rows, cols) -> np.ndarray:
    """5-point-stencil Laplacian evaluated only at sampled points (Right,
    Left, Up, Down neighbours), avoiding a full-image convolution."""
    center = gray[rows, cols]
    right = gray[rows, cols + 1]
    left = gray[rows, cols - 1]
    up = gray[rows - 1, cols]
    down = gray[rows + 1, cols]
    return (right + left + up + down - 4.0 * center)


def _normed_variance(lap_vals: np.ndarray, intensities: np.ndarray) -> float:
    # NORMED: variance scaled by (mean intensity)^2 to remove global
    # brightness/exposure dependence.
    mean_intensity = float(np.mean(intensities)) + 1e-6
    return float(np.var(lap_vals)) / (mean_intensity ** 2)


def variance_of_laplacian_normed(gray: np.ndarray, rng=None) -> dict:
    rows, cols = sample_points_in_disk(gray.shape, rng=rng)
    if rows.size == 0:
        return {"score": 0.0, "status": "fail", "rows": rows, "cols": cols, "lap_vals": np.array([])}

    lap_vals = _point_laplacian(gray, rows, cols)
    normed_variance = _normed_variance(lap_vals, gray[rows, cols])

    if normed_variance < THRESH_LAPLACIAN_VAR_NORMED_FAIL:
        status = "fail"
    elif normed_variance < THRESH_LAPLACIAN_VAR_NORMED_BORDERLINE:
        status = "borderline"
    else:
        status = "pass"

    return {"score": normed_variance, "status": status, "n_points": rows.size,
            "rows": rows, "cols": cols, "lap_vals": lap_vals}


def spec_slope(patch: np.ndarray) -> float:
    """Slope of the radially-averaged power spectrum on a log-log scale.

    A steeper (more negative) slope indicates energy concentrated at low
    spatial frequencies (blur); a shallower slope indicates rich
    high-frequency content such as blood vessels.
    """
    patch = patch.astype(np.float64)
    patch = patch - patch.mean()
    h, w = patch.shape

    window = np.outer(np.hanning(h), np.hanning(w))
    spectrum = np.fft.fftshift(np.fft.fft2(patch * window))
    power = np.abs(spectrum) ** 2

    cy, cx = h // 2, w // 2
    y, x = np.indices((h, w))
    radius = np.sqrt((y - cy) ** 2 + (x - cx) ** 2).astype(int)

    max_r = radius.max()
    radial_sum = np.bincount(radius.ravel(), weights=power.ravel(), minlength=max_r + 1)
    radial_count = np.bincount(radius.ravel(), minlength=max_r + 1)
    radial_profile = radial_sum / np.maximum(radial_count, 1)

    # Skip the DC/very-low-frequency bins; fit log(power) vs log(radius).
    valid = np.arange(1, max_r + 1)
    profile = radial_profile[1:]
    keep = profile > 0
    if keep.sum() < 2:
        return 0.0

    log_r = np.log(valid[keep])
    log_p = np.log(profile[keep])
    slope, _intercept = np.polyfit(log_r, log_p, 1)
    return float(slope)


def spec_slope_gate(gray: np.ndarray, rng=None) -> dict:
    boxes = sample_squares_in_disk(gray.shape, rng=rng)
    slopes = [spec_slope(gray[r0:r1, c0:c1]) for r0, r1, c0, c1 in boxes]
    score = float(np.mean(slopes)) if slopes else 0.0
    return {"score": score, "n_patches": len(boxes)}


def laplacian_and_spec_slope_gate(gray: np.ndarray, rng=None) -> dict:
    lap = variance_of_laplacian_normed(gray, rng=rng)
    spec = spec_slope_gate(gray, rng=rng)
    return {"laplacian": lap, "spec_slope": spec, "status": lap["status"]}


# --- #3.3 TenengradVar (confirmation for #3.1) --------------------------------

def tenengrad_var(patch: np.ndarray) -> float:
    gx = ndimage.sobel(patch.astype(np.float64), axis=1)
    gy = ndimage.sobel(patch.astype(np.float64), axis=0)
    gradient_magnitude_sq = gx ** 2 + gy ** 2
    return float(np.var(gradient_magnitude_sq)) / (float(np.mean(patch) + 1e-6) ** 2)


def tenengrad_var_gate(gray: np.ndarray, rng=None) -> dict:
    boxes = sample_squares_in_disk(gray.shape, rng=rng)
    scores = [tenengrad_var(gray[r0:r1, c0:c1]) for r0, r1, c0, c1 in boxes]
    score = float(np.mean(scores)) if scores else 0.0

    if score < THRESH_TENENGRAD_VAR_FAIL:
        status = "fail"
    elif score < THRESH_TENENGRAD_VAR_BORDERLINE:
        status = "borderline"
    else:
        status = "pass"

    return {"score": score, "status": status, "n_patches": len(boxes)}


# --- #3.4 Region Min ----------------------------------------------------------

def region_min(gray: np.ndarray, lap_result: dict, fov_mask: np.ndarray = None) -> dict:
    """Split the retinal area into 5 regions (centre + 4 quadrants), compute
    the focus metric (variance-of-Laplacian, NORMED) per region, and take the
    MINIMUM across them. A single weak region is enough to fail the image.

    Reuses the Laplacian samples already computed in #3.1 (lap_result), so
    this is only 5 grouped statistics over an existing array.
    """
    h, w = gray.shape[:2]
    rows, cols, lap_vals = lap_result["rows"], lap_result["cols"], lap_result["lap_vals"]

    if fov_mask is not None and fov_mask.any():
        ys, xs = np.nonzero(fov_mask)
        r0, r1 = ys.min(), ys.max()
        c0, c1 = xs.min(), xs.max()
    else:
        r0, r1, c0, c1 = 0, h - 1, 0, w - 1

    cy, cx = (r0 + r1) // 2, (c0 + c1) // 2
    qh, qw = (r1 - r0) // 4, (c1 - c0) // 4  # quarter spans for the centre region

    regions = {
        "top_left": (r0, cy, c0, cx),
        "top_right": (r0, cy, cx, c1),
        "bottom_left": (cy, r1, c0, cx),
        "bottom_right": (cy, r1, cx, c1),
        "centre": (max(r0, cy - qh), min(r1, cy + qh), max(c0, cx - qw), min(c1, cx + qw)),
    }

    region_scores = {}
    for name, (rr0, rr1, cc0, cc1) in regions.items():
        in_region = (rows >= rr0) & (rows < rr1) & (cols >= cc0) & (cols < cc1)
        if in_region.sum() < 2:
            region_scores[name] = 0.0
            continue
        region_scores[name] = _normed_variance(lap_vals[in_region], gray[rows[in_region], cols[in_region]])

    min_region = min(region_scores, key=region_scores.get)
    min_score = region_scores[min_region]

    if min_score < THRESH_REGION_MIN_FAIL:
        status = "fail"
    elif min_score < THRESH_REGION_MIN_BORDERLINE:
        status = "borderline"
    else:
        status = "pass"

    return {"region_scores": region_scores, "min_region": min_region, "score": min_score, "status": status}


@dataclass
class SharpnessResult:
    status: str
    brenner: dict
    laplacian_spec: dict
    tenengrad: dict
    region_min: dict


def sharpness_contrast_cascade(image: np.ndarray, fov_mask: np.ndarray = None, rng=None) -> SharpnessResult:
    """Runs #3 in cascade order, short-circuiting on the first fail."""
    if rng is None:
        rng = np.random.default_rng()
    gray = to_gray(image)

    brenner = brenner_gradient_gate(gray, rng=rng)
    if brenner["status"] == "fail":
        return SharpnessResult("fail", brenner, {}, {}, {})

    lap_spec = laplacian_and_spec_slope_gate(gray, rng=rng)
    if lap_spec["status"] == "fail":
        return SharpnessResult("fail", brenner, lap_spec, {}, {})

    tenengrad = tenengrad_var_gate(gray, rng=rng)
    if tenengrad["status"] == "fail":
        return SharpnessResult("fail", brenner, lap_spec, tenengrad, {})

    r_min = region_min(gray, lap_spec["laplacian"], fov_mask=fov_mask)
    if r_min["status"] == "fail":
        return SharpnessResult("fail", brenner, lap_spec, tenengrad, r_min)

    statuses = [lap_spec["status"], tenengrad["status"], r_min["status"]]
    overall = "borderline" if "borderline" in statuses else "pass"

    return SharpnessResult(overall, brenner, lap_spec, tenengrad, r_min)

"""#2 FOV Detection: Area Ratio (#2.1) and Black Region (#2.2) gates.

Not worried about offset (misalignment doesn't change quality of the interested
section of the image). AreaFrac, BorderFrac and Radius are a function of the
black region of the image.
"""

from dataclasses import dataclass

import numpy as np

# --- #2.1 Area Ratio -------------------------------------------------------

AREA_RATIO_LOW = 0.85
AREA_RATIO_HIGH = 1.15

# --- #2.2 Black Region -------------------------------------------------------
# aspect (width/height) -> (low %, high %) black-region band.
ASPECT_BLACK_BANDS = {
    1.00: (15.0, 25.0),
    1.33: (15.0, 45.0),
    1.39: (15.0, 47.5),
    1.51: (15.0, 50.0),
}

BLACK_PIXEL_RGB = (0, 0, 0)
ROW_SAMPLE_FRACTION = 0.10
ROW_PASS_FRACTION = 0.80


@dataclass
class FOVMask:
    mask: np.ndarray  # boolean, True = foreground (non-black FOV)
    center_row: int
    center_col: int
    horizontal_radius: float
    vertical_radius: float


def build_fov_mask(image: np.ndarray, black_thresh: int = 10) -> FOVMask:
    """Binary mask of the retinal FOV vs. the black surround.

    A pixel is considered "black" (background) if all channels are below
    black_thresh. The FOV mask extents (not a traced boundary) are used to
    derive horizontal/vertical radii, per the compute-reduction note in #2.1.
    """
    if image.ndim == 3:
        is_black = np.all(image <= black_thresh, axis=-1)
    else:
        is_black = image <= black_thresh

    mask = ~is_black

    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        h, w = mask.shape[:2]
        return FOVMask(mask=mask, center_row=h // 2, center_col=w // 2,
                        horizontal_radius=0.0, vertical_radius=0.0)

    center_row = int(round(ys.mean()))
    center_col = int(round(xs.mean()))

    # Horizontal radius: half of the mask extent along the row through the centroid.
    row_pixels = np.nonzero(mask[center_row, :])[0]
    horizontal_extent = (row_pixels.max() - row_pixels.min() + 1) if row_pixels.size else 0
    horizontal_radius = horizontal_extent / 2.0

    # Vertical radius: half of the mask extent along the column through the centroid.
    col_pixels = np.nonzero(mask[:, center_col])[0]
    vertical_extent = (col_pixels.max() - col_pixels.min() + 1) if col_pixels.size else 0
    vertical_radius = vertical_extent / 2.0

    return FOVMask(
        mask=mask,
        center_row=center_row,
        center_col=center_col,
        horizontal_radius=horizontal_radius,
        vertical_radius=vertical_radius,
    )


def area_ratio_check(fov: FOVMask) -> dict:
    """#2.1 Area Ratio gate.

    Compares the area implied by the horizontal/vertical radii against the
    area implied by their mean radius (area ~ r^2, so no pi factor needed
    since it cancels in the ratio).
    """
    r_h = fov.horizontal_radius
    r_v = fov.vertical_radius
    r_mean = (r_h + r_v) / 2.0

    if r_mean == 0:
        return {"s1": 0.0, "s2": 0.0, "pass": False}

    s1 = (r_h ** 2) / (r_mean ** 2)
    s2 = (r_v ** 2) / (r_mean ** 2)

    passed = (AREA_RATIO_LOW < s1 < AREA_RATIO_HIGH) and (AREA_RATIO_LOW < s2 < AREA_RATIO_HIGH)

    return {"s1": s1, "s2": s2, "pass": passed}


def _nearest_aspect_band(aspect: float):
    nearest = min(ASPECT_BLACK_BANDS.keys(), key=lambda a: abs(a - aspect))
    return ASPECT_BLACK_BANDS[nearest]


def _row_black_fraction(row: np.ndarray, black_thresh: int = 10) -> float:
    if row.ndim == 2:
        is_black = np.all(row <= black_thresh, axis=-1)
    else:
        is_black = row <= black_thresh
    return float(is_black.mean())


def black_region_check(image: np.ndarray, rng: np.random.Generator = None,
                        black_thresh: int = 10) -> dict:
    """#2.2 Black Region gate.

    Band depends on aspect ratio (width/height). Optimization: sample a
    random 10% of rows and require >=80% of those rows to have a black
    fraction within the aspect-appropriate band.
    """
    if rng is None:
        rng = np.random.default_rng()

    height, width = image.shape[:2]
    aspect = width / height
    low, high = _nearest_aspect_band(aspect)

    n_rows = max(1, int(round(height * ROW_SAMPLE_FRACTION)))
    sampled_rows = rng.choice(height, size=n_rows, replace=False)

    in_band_count = 0
    for r in sampled_rows:
        black_pct = _row_black_fraction(image[r], black_thresh=black_thresh) * 100.0
        if low <= black_pct <= high:
            in_band_count += 1

    in_band_fraction = in_band_count / n_rows
    passed = in_band_fraction >= ROW_PASS_FRACTION

    return {
        "aspect": aspect,
        "band": (low, high),
        "in_band_fraction": in_band_fraction,
        "pass": passed,
    }


def fov_detection(image: np.ndarray, rng: np.random.Generator = None) -> dict:
    """#2 FOV Detection: runs Area Ratio (#2.1) then Black Region (#2.2)."""
    fov = build_fov_mask(image)
    area_result = area_ratio_check(fov)

    if not area_result["pass"]:
        return {"status": "fail", "stage": "area_ratio", "fov": fov, "area_ratio": area_result}

    black_result = black_region_check(image, rng=rng)

    if not black_result["pass"]:
        return {
            "status": "fail",
            "stage": "black_region",
            "fov": fov,
            "area_ratio": area_result,
            "black_region": black_result,
        }

    return {
        "status": "pass",
        "fov": fov,
        "area_ratio": area_result,
        "black_region": black_result,
    }

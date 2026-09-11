"""#FOVEA: search along the OD-fovea axis, up to 1.25x the expected fovea
distance with a +-25 degree axis tilt allowed; the darkest candidate wins,
confirmed with a radial-brightness-increase sanity check (see
notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "FOVEA" section). Output
is (x, y) only - the notes are explicit that no radius is needed since only
the fovea point (not macula extent) matters.
"""

from dataclasses import dataclass

import numpy as np

FOVEA_SEARCH_MAX_FACTOR = 1.25    # pinned: "+- 1.25X of expected fovea location"
FOVEA_AXIS_TILT_DEG = 25.0        # pinned: "+-25 degree axis tilt allowed"

# Expected OD-fovea distance is not pinned to a number in the notes ->
# placeholder (anatomical rule of thumb for a 45 degree fundus field is
# roughly 2.4-2.5 disc diameters temporal to the disc; calibrate before use).
EXPECTED_FOVEA_DISTANCE_DD = 2.4
FOVEA_SEARCH_MIN_FACTOR = 0.5     # placeholder: avoids sampling on the OD's own dark rim at the near end

FOVEA_DARKNESS_PATCH_RADIUS_PX = 6         # placeholder: window used to score "darkest" at a candidate point
FOVEA_RADIAL_CHECK_STEPS_DD = (0.15, 0.3)  # placeholder radii (in DD) for the brightness-increase sanity check
FOVEA_SEARCH_RADIAL_STEPS = 20   # placeholder: sampling density along the search radius
FOVEA_SEARCH_ANGULAR_STEPS = 11  # placeholder: sampling density across the +-25 degree tilt

# Caution (per Stage_2_CNN_Proposed_Changes.md, item M4): reporting that the
# chosen fovea falls within this same search band is not independent
# validation - the search enforces that by construction. The radial-
# brightness-increase check below is the one part of this module that is an
# independent test.


@dataclass
class FoveaResult:
    x: float
    y: float
    darkness_score: float
    radial_brightness_increasing: bool


def _luminance(image_rgb):
    r = image_rgb[..., 0].astype(np.float64)
    g = image_rgb[..., 1].astype(np.float64)
    b = image_rgb[..., 2].astype(np.float64)
    return 0.299 * r + 0.587 * g + 0.114 * b


def _axis_angle_deg(od_center, image_shape, fov_mask=None):
    """Direction of the OD-fovea axis. The notes fix the search fan (+-25
    deg, up to 1.25x expected distance) but not how to pick the axis heading
    itself (left/right eye is not known here) - documented judgment call:
    point the axis from the OD centre toward the FOV centroid, which is
    where the fovea/macula sits relative to a temporally-offset disc in a
    standard 45-degree posterior-pole fundus photo."""
    h, w = image_shape[:2]
    if fov_mask is not None and fov_mask.any():
        ys, xs = np.nonzero(fov_mask)
        center = (float(xs.mean()), float(ys.mean()))
    else:
        center = (w / 2.0, h / 2.0)
    dx = center[0] - od_center[0]
    dy = center[1] - od_center[1]
    if dx == 0 and dy == 0:
        return 0.0
    return float(np.degrees(np.arctan2(dy, dx)))


def _mean_patch(brightness, x, y, radius):
    h, w = brightness.shape
    x0, x1 = max(0, int(x - radius)), min(w, int(x + radius) + 1)
    y0, y1 = max(0, int(y - radius)), min(h, int(y + radius) + 1)
    if x1 <= x0 or y1 <= y0:
        yy, xx = int(np.clip(y, 0, h - 1)), int(np.clip(x, 0, w - 1))
        return float(brightness[yy, xx])
    return float(brightness[y0:y1, x0:x1].mean())


def locate_fovea(image_rgb, optic_disc, fov_mask=None) -> FoveaResult:
    brightness = _luminance(image_rgb)
    h, w = brightness.shape
    od_center = (optic_disc.center_x, optic_disc.center_y)
    dd_px = 2.0 * optic_disc.radius

    axis_deg = _axis_angle_deg(od_center, brightness.shape, fov_mask=fov_mask)
    expected_dist_px = EXPECTED_FOVEA_DISTANCE_DD * dd_px
    max_dist_px = FOVEA_SEARCH_MAX_FACTOR * expected_dist_px
    min_dist_px = FOVEA_SEARCH_MIN_FACTOR * expected_dist_px

    angles = np.linspace(axis_deg - FOVEA_AXIS_TILT_DEG, axis_deg + FOVEA_AXIS_TILT_DEG, FOVEA_SEARCH_ANGULAR_STEPS)
    radii = np.linspace(min_dist_px, max_dist_px, FOVEA_SEARCH_RADIAL_STEPS)

    best = None
    for theta in angles:
        rad = np.radians(theta)
        for r in radii:
            x = od_center[0] + r * np.cos(rad)
            y = od_center[1] + r * np.sin(rad)
            if not (0 <= x < w and 0 <= y < h):
                continue
            if fov_mask is not None and not fov_mask[int(y), int(x)]:
                continue
            score = _mean_patch(brightness, x, y, FOVEA_DARKNESS_PATCH_RADIUS_PX)
            if best is None or score < best["score"]:
                best = {"score": score, "x": x, "y": y}

    if best is None:
        # No valid candidate in the search fan (e.g. it falls entirely
        # outside the FOV) - fall back to the raw expected-distance point.
        return FoveaResult(x=float(od_center[0] + expected_dist_px), y=float(od_center[1]),
                            darkness_score=float("nan"), radial_brightness_increasing=False)

    fx, fy = best["x"], best["y"]
    center_score = best["score"]

    # radial-brightness-increase sanity check: brightness should rise moving
    # outward from a true fovea (a vessel shadow, by contrast, stays dark).
    radial_dir = np.arctan2(fy - od_center[1], fx - od_center[0])
    outward_scores = []
    for step_dd in FOVEA_RADIAL_CHECK_STEPS_DD:
        step_px = step_dd * dd_px
        ox = fx + step_px * np.cos(radial_dir)
        oy = fy + step_px * np.sin(radial_dir)
        if 0 <= ox < w and 0 <= oy < h:
            outward_scores.append(_mean_patch(brightness, ox, oy, FOVEA_DARKNESS_PATCH_RADIUS_PX))
    increasing = bool(all(s > center_score for s in outward_scores)) if outward_scores else False

    return FoveaResult(x=float(fx), y=float(fy), darkness_score=float(center_score),
                        radial_brightness_increasing=increasing)

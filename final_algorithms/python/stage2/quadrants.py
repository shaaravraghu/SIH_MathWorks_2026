"""#Draw Segmentation of Quadrants / #Apply count function ... 4-2-1 rule
(see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, matching section
headers).

Quadrants are anchored to the OD-fovea axis, never the frame's horizontal /
vertical axes.

The textbook 4-2-1 constant (>20 haemorrhages in each of 4 quadrants) does
NOT transfer here: measured, it fired on 0/70 images at every grade,
including grade 3 - it assumes a dilated seven-field exam, and a single
45-degree field sees a different sample. Re-derived: >3 gives 93%
specificity at grades 0-2 and 64% sensitivity at grades 3-4.
"""

from dataclasses import dataclass

import numpy as np

QUADRANT_COUNT_THRESH = 3  # pinned: re-derived constant (>3, not the textbook >20)


@dataclass
class QuadrantResult:
    axis_angle_deg: float
    counts: list        # raw, UNTHRESHOLDED per-quadrant counts, index 0-3
    flags: list          # per-quadrant bool: count > QUADRANT_COUNT_THRESH
    four_two_one: bool   # all four quadrants over threshold (the "4" criterion of 4-2-1)


def quadrant_axis_angle(od_center, fovea_point) -> float:
    dx = fovea_point[0] - od_center[0]
    dy = fovea_point[1] - od_center[1]
    return float(np.degrees(np.arctan2(dy, dx)))


def assign_quadrant(point, od_center, axis_angle_deg) -> int:
    """Quadrant index 0-3, boundaries at axis_angle + {0, 90, 180, 270} deg."""
    dx = point[0] - od_center[0]
    dy = point[1] - od_center[1]
    angle = np.degrees(np.arctan2(dy, dx)) - axis_angle_deg
    angle = angle % 360.0
    return int(angle // 90.0) % 4


def quadrant_boundaries(od_center, fovea_point):
    """Four quadrant angular boundaries (degrees, absolute frame), anchored
    to the OD-fovea axis rather than the frame's own axes."""
    axis = quadrant_axis_angle(od_center, fovea_point)
    return [float((axis + 90.0 * k) % 360.0) for k in range(4)]


def count_quadrants(points, od_center, fovea_point) -> QuadrantResult:
    """Buckets already-classified lesion candidate points (e.g. haemorrhage
    centroids) into the four OD-fovea-anchored quadrants and applies the
    re-derived 4-2-1-style count threshold. Raw counts are always returned
    alongside the thresholded flag so the constant can be refit later
    without re-extraction (per the notes)."""
    axis = quadrant_axis_angle(od_center, fovea_point)
    counts = [0, 0, 0, 0]
    for p in points:
        counts[assign_quadrant(p, od_center, axis)] += 1
    flags = [c > QUADRANT_COUNT_THRESH for c in counts]
    return QuadrantResult(axis_angle_deg=axis, counts=counts, flags=flags, four_two_one=all(flags))

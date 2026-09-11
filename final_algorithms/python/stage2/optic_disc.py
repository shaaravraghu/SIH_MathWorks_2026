"""#OPTIC DISC: brightness-based primary localization, confirmed by centre-
surround contrast and a percentage-of-FOV-radius plausibility check (see
notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "OPTIC DISC" section).

Vessel-detected pixels are masked out of the brightness search before
picking a candidate, per the notes' explicit instruction ("avoid regions
with blood vessel detected, to avoid confusion"). Note: a later companion
review (Stage_2_CNN_Proposed_Changes.md, item M3) argues vessels actually
CONVERGE at the disc and that excluding them pushes the search away from the
correct answer - that proposal was deliberately NOT applied here, since the
task spec is Stage_2_CNN as written. Flagged for review, not silently
resolved either way.
"""

from dataclasses import dataclass

import cv2
import numpy as np

# --- percentage-of-FOV-radius plausibility band ------------------------------
# Anatomically the OD diameter is roughly 1/5-1/8 of the horizontal FOV, but
# the notes do not pin an exact fraction -> placeholders, calibrate before
# use. The search band is kept WIDER than the plausibility band so the
# confirmation step can actually fail (a search restricted to exactly the
# plausibility band would make that check tautological).
OD_SEARCH_FRACTION_LOW = 0.03
OD_SEARCH_FRACTION_HIGH = 0.15
OD_SEARCH_RADIUS_STEPS = 5   # placeholder: number of candidate radii tried

OD_RADIUS_FOV_FRACTION_LOW = 0.05
OD_RADIUS_FOV_FRACTION_HIGH = 0.12

# --- centre-surround confirmation --------------------------------------------
OD_ANNULUS_OUTER_FACTOR = 2.0   # surround annulus outer radius = candidate_radius * this
THRESH_OD_CENTRE_SURROUND_MIN_CONTRAST = 5.0  # placeholder: not pinned in notes


@dataclass
class OpticDiscResult:
    center_x: float
    center_y: float
    radius: float
    centre_surround_contrast: float
    confirmed: bool


def _luminance(image_rgb):
    r = image_rgb[..., 0].astype(np.float64)
    g = image_rgb[..., 1].astype(np.float64)
    b = image_rgb[..., 2].astype(np.float64)
    return 0.299 * r + 0.587 * g + 0.114 * b


def _disc_mean_map(brightness, vessel_mask, radius):
    """Mean brightness within a circular window of the given radius, at
    every pixel, with vessel-detected pixels excluded (normalised
    correlation: sum(brightness*valid) / sum(valid))."""
    ksize = int(round(radius)) * 2 + 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksize, ksize)).astype(np.float64)
    valid = (~vessel_mask).astype(np.float64) if vessel_mask is not None else np.ones_like(brightness)
    weighted = brightness * valid
    sum_weighted = cv2.filter2D(weighted, -1, kernel, borderType=cv2.BORDER_REPLICATE)
    sum_valid = cv2.filter2D(valid, -1, kernel, borderType=cv2.BORDER_REPLICATE)
    return sum_weighted / np.maximum(sum_valid, 1e-6)


def locate_optic_disc(image_rgb, vessel_mask=None, fov_mask=None) -> OpticDiscResult:
    h, w = image_rgb.shape[:2]
    if fov_mask is not None and fov_mask.any():
        ys, xs = np.nonzero(fov_mask)
        fov_radius = (float(xs.max() - xs.min()) + float(ys.max() - ys.min())) / 4.0
    else:
        fov_radius = min(h, w) / 2.0

    brightness = _luminance(image_rgb)

    best = None
    fractions = np.linspace(OD_SEARCH_FRACTION_LOW, OD_SEARCH_FRACTION_HIGH, OD_SEARCH_RADIUS_STEPS)
    for frac in fractions:
        radius = max(3.0, frac * fov_radius)
        disc_mean = _disc_mean_map(brightness, vessel_mask, radius)
        if fov_mask is not None:
            disc_mean = np.where(fov_mask, disc_mean, -np.inf)
        idx = np.unravel_index(np.argmax(disc_mean), disc_mean.shape)
        score = disc_mean[idx]
        if best is None or score > best["score"]:
            best = {"score": score, "y": idx[0], "x": idx[1], "radius": radius}

    cy, cx, radius = best["y"], best["x"], best["radius"]

    inner_u8 = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(inner_u8, (int(cx), int(cy)), max(int(round(radius)), 1), 1, -1)
    inner_mask = inner_u8.astype(bool)

    outer_r = max(int(round(radius * OD_ANNULUS_OUTER_FACTOR)), 1)
    outer_u8 = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(outer_u8, (int(cx), int(cy)), outer_r, 1, -1)
    outer_mask = outer_u8.astype(bool) & ~inner_mask

    mean_inner = image_rgb[inner_mask].astype(np.float64).mean(axis=0) if inner_mask.any() else np.zeros(3)
    mean_outer = image_rgb[outer_mask].astype(np.float64).mean(axis=0) if outer_mask.any() else np.zeros(3)
    # [mean_col(OD) - mean_col(surr)] summarised as a single scalar contrast
    # (the notes give it per-channel; a vector magnitude is used here as the
    # scalar confirmation score - documented judgment call).
    contrast = float(np.linalg.norm(mean_inner - mean_outer))

    radius_fraction = radius / fov_radius if fov_radius > 0 else 0.0
    plausible = OD_RADIUS_FOV_FRACTION_LOW <= radius_fraction <= OD_RADIUS_FOV_FRACTION_HIGH
    confirmed = bool(plausible and contrast >= THRESH_OD_CENTRE_SURROUND_MIN_CONTRAST)

    return OpticDiscResult(
        center_x=float(cx), center_y=float(cy), radius=float(radius),
        centre_surround_contrast=contrast, confirmed=confirmed,
    )

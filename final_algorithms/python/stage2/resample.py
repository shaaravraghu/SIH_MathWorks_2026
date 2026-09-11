"""Working-resolution normalisation shared by every Stage 2 feature (see
notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md sections 2.2 and 4.1,
and code_testing/python/extract_module2_features.py load_norm/prep_green,
which this reproduces at the coordinator's specified constants). Every pixel
constant quoted in Stage_2_CNN (2.7-10.1 px vessel bands, 14.9 um/px, L=15/41
structuring elements, 1 DD for NVD/NVE, etc.) assumes images are resampled
so the retina radius is exactly TARGET_R pixels - they are meaningless at
any other scale.
"""

import numpy as np
from scipy import ndimage

TARGET_R = 436                           # pinned: working-resolution retina radius, px
OD_R_PX = int(round(TARGET_R / 7.0))     # 62 px
DD_PX = 2 * OD_R_PX                      # 124 px, one disc diameter
UM_PER_PX = 1850.0 / DD_PX               # ~14.9 um/px - where the scale table's 14.9 comes from
DME_RADIUS_PX = 34                       # pinned: 500 um DME zone radius

_HALF = TARGET_R
PIXEL_Y, PIXEL_X = np.mgrid[0:2 * _HALF, 0:2 * _HALF].astype(np.float64)
_RADIUS_FROM_CENTRE = np.hypot(PIXEL_Y - _HALF, PIXEL_X - _HALF)

RETINA_MASK = _RADIUS_FROM_CENTRE <= TARGET_R * 0.95       # RET
MEASUREMENT_MASK = _RADIUS_FROM_CENTRE <= TARGET_R * 0.92  # MM - every "% of FOV" feature divides by this


def resample_to_working_resolution(image_rgb, fov_mask):
    """Rescales image_rgb so the FOV radius (derived from fov_mask, e.g.
    stage1's build_fov_mask) equals TARGET_R, then crops
    2*TARGET_R x 2*TARGET_R centred on the FOV, with everything outside
    RETINA_MASK zeroed. Returns a float64 [0, 1] RGB array of shape
    (2*TARGET_R, 2*TARGET_R, 3)."""
    if fov_mask is None:
        raise ValueError("fov_mask is required - reuse Stage 1's build_fov_mask/FOVMask.mask")

    ys, xs = np.nonzero(fov_mask)
    if ys.size == 0:
        h, w = image_rgb.shape[:2]
        cy, cx, radius = h / 2.0, w / 2.0, min(h, w) / 2.0
    else:
        cy, cx = float(ys.mean()), float(xs.mean())
        r_h = (xs.max() - xs.min()) / 2.0
        r_v = (ys.max() - ys.min()) / 2.0
        radius = (r_h + r_v) / 2.0
        if radius <= 0:
            radius = min(image_rgb.shape[:2]) / 2.0

    scale = TARGET_R / radius
    img = image_rgb.astype(np.float64) / 255.0
    zoomed = ndimage.zoom(img, (scale, scale, 1), order=1)

    pad = _HALF + 10
    padded = np.pad(zoomed, ((pad, pad), (pad, pad), (0, 0)))
    r0 = int(round(cy * scale + pad)) - _HALF
    c0 = int(round(cx * scale + pad)) - _HALF
    r0 = int(np.clip(r0, 0, max(padded.shape[0] - 2 * _HALF, 0)))
    c0 = int(np.clip(c0, 0, max(padded.shape[1] - 2 * _HALF, 0)))

    cropped = np.ascontiguousarray(padded[r0:r0 + 2 * _HALF, c0:c0 + 2 * _HALF])
    if cropped.shape[0] != 2 * _HALF or cropped.shape[1] != 2 * _HALF:
        # Degenerate FOV (e.g. near image edge) - pad out to the expected size.
        fix = np.zeros((2 * _HALF, 2 * _HALF, 3), dtype=cropped.dtype)
        fix[:cropped.shape[0], :cropped.shape[1]] = cropped
        cropped = fix
    cropped[~RETINA_MASK] = 0
    return cropped


def prep_green(work_rgb):
    """Shade-corrected green at working resolution: green / (background
    estimated by a sigma=7.5 Gaussian at 1/8 scale) * mean background. NOT
    CLAHE - the previous implementation measured CLAHE costing 20% of
    microaneurysm contrast for no vessel benefit (Module3_Plan.md S2.1,
    S1-21; code_testing prep_green docstring). Returns a [0, 1] array."""
    g = work_rgb[:, :, 1].astype(np.float64)
    fill_value = float(g[RETINA_MASK].mean()) if RETINA_MASK.any() else 0.0
    filled = np.where(RETINA_MASK, g, fill_value)

    small = ndimage.zoom(filled, 1 / 8, order=1)
    bg = ndimage.zoom(ndimage.gaussian_filter(small, 7.5), 8, order=1)
    bg = bg[:g.shape[0], :g.shape[1]]
    if bg.shape != g.shape:
        bg = np.pad(bg, ((0, g.shape[0] - bg.shape[0]), (0, g.shape[1] - bg.shape[1])), mode="edge")

    bg_mean = max(float(bg[RETINA_MASK].mean()) if RETINA_MASK.any() else 1e-3, 1e-3)
    out = np.clip(g / np.maximum(bg, 1e-3) * bg_mean, 0, 1)
    out[~RETINA_MASK] = float(out[RETINA_MASK].mean()) if RETINA_MASK.any() else 0.0
    return out


def raw_green(work_rgb):
    """Green channel, NOT shade-corrected, surround filled with the interior
    mean - see optic_disc.py / Stage_2_CNN_Proposed_Changes.md item m1 for
    why the optic disc wants raw green while vessels want shade-corrected
    green (this module does not itself enforce that split - callers choose
    which green channel to feed each detector)."""
    g = work_rgb[:, :, 1].astype(np.float64).copy()
    g[~RETINA_MASK] = float(g[RETINA_MASK].mean()) if RETINA_MASK.any() else 0.0
    return g

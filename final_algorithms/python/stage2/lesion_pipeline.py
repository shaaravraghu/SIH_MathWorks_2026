"""#THE FIVE-STEP LESION PIPELINE (applies to every lesion class): preprocess
-> subtract vessels -> threshold to candidates -> per-candidate features ->
classifier keep/reject (see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN,
"THE FIVE-STEP LESION PIPELINE" section).

Steps 4 and 5 are made structurally mandatory here, not optional hooks:
measured across four components, EVERY one that stopped at step 3
(threshold only) failed, and every one that added steps 4-5 worked
(microaneurysms rho -0.117 -> +0.508; haemorrhages rho 0.036 -> +0.553;
4-2-1 quadrants: fired on 2/70 wrong images -> fires only at grades 3-4).

The classify=False mode below is the one deliberate exception, added for
Module3_Plan.md's CV-fold-safe extraction requirement (S4.1/S6.1): a lesion
classifier must be fitted per cross-validation fold on training rows only,
so candidate extraction (steps 1-4) has to be separable from classification
(step 5). classify=False stops after step 4 and returns candidates without
a keep/reject decision - callers MUST still run them through
classifier.classify_candidates() before treating anything as a final
result; step 5 is deferred, not skipped.
"""

import cv2
import numpy as np
from scipy import ndimage

from . import classifier as classifier_module
from . import lesion_features

# --- step 1: preprocess -------------------------------------------------------
SHADE_CORRECTION_KERNEL_FRACTION = 0.10  # placeholder: background-blur extent as a fraction of image height

# --- step 2: subtract vessels -------------------------------------------------
VESSEL_DILATION_PX = 3   # pinned: "dilate the vessel mask 2-3 px before subtracting"

# --- step 3: threshold to candidates ------------------------------------------
# Scale-matched structuring elements: one SE cannot serve both an 8px
# microaneurysm and a 30px haemorrhage, because closing only fills what the
# SE BRIDGES.
LESION_STRUCTURING_ELEMENT_LENGTH_PX = {
    "microaneurysm": 15,   # pinned: L=15
    "haemorrhage": 41,     # pinned: L=41
    # hard_exudate / nerve_fibre_ischemia are not size-pinned in the notes -
    # they rely on the colour-ratio spot finder in lesion_features.py (see
    # the "Pre-Feature Engineering" note section) instead; these SE lengths
    # are placeholders kept only as a secondary/optional morphological pass.
    "hard_exudate": 21,
    "nerve_fibre_ischemia": 25,
}
THRESH_CANDIDATE_TOPHAT_PERCENTILE = 95.0  # placeholder: not pinned in notes

# Lesion classes whose step-3 threshold combines the SE top-hat with the
# colour-ratio spot finder (see notes: "Pre-Feature Engineering ... for
# Haemorrhage, Nerve Fibre Ischemia, and Hard Exudates"). Microaneurysms use
# the SE top-hat alone.
RATIO_SPOT_LESION_CLASSES = ("haemorrhage", "hard_exudate", "nerve_fibre_ischemia")
TOPHAT_LESION_CLASSES = ("microaneurysm", "haemorrhage")

MIN_CANDIDATE_AREA_PX = 3  # placeholder: drop single/near-single-pixel noise before feature extraction


# --- step 1: preprocess -------------------------------------------------------

def shade_correct(green, mask=None):
    """Local light shade-correction (step 1). Not a reuse of stage1's flat
    field correction module (that is per-image quality gating); this is a
    lightweight local background subtraction so lesion candidates aren't
    swamped by large-scale illumination gradients. Exact method is not
    pinned in the notes - documented approximation: subtract a heavily
    blurred estimate of the background and re-add the global mean."""
    green = green.astype(np.float64)
    h = green.shape[0]
    blur_extent_px = max(int(round(h * SHADE_CORRECTION_KERNEL_FRACTION)), 3)
    background = cv2.GaussianBlur(green, (0, 0), sigmaX=blur_extent_px / 3.0)
    valid = mask if mask is not None else np.ones_like(green, dtype=bool)
    global_mean = float(green[valid].mean()) if valid.any() else float(green.mean())
    return green - background + global_mean


# --- step 2: subtract vessels -------------------------------------------------

def subtract_vessels(mask, vessel_mask):
    """Step 2: dilate the vessel mask 2-3px before subtracting, so vessel
    edges don't leak into lesion candidates."""
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * VESSEL_DILATION_PX + 1,) * 2)
    dilated_vessels = cv2.dilate(vessel_mask.astype(np.uint8), kernel).astype(bool)
    return mask & ~dilated_vessels


# --- step 3: threshold to candidates ------------------------------------------

def _tophat_candidates(corrected_green, working_mask, se_length_px):
    se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (se_length_px, se_length_px))
    # Microaneurysms/haemorrhages are DARK spots -> black-tophat (closing minus original).
    closed = cv2.morphologyEx(corrected_green.astype(np.float32), cv2.MORPH_CLOSE, se)
    tophat = closed - corrected_green.astype(np.float32)
    vals = tophat[working_mask] if working_mask is not None else tophat
    if vals.size == 0:
        return np.zeros_like(tophat, dtype=bool)
    thresh = np.percentile(vals, THRESH_CANDIDATE_TOPHAT_PERCENTILE)
    candidate = tophat > thresh
    if working_mask is not None:
        candidate &= working_mask
    return candidate


def threshold_candidates(image_rgb, corrected_green, working_mask, lesion_class):
    """Step 3: high-recall / low-precision candidate mask (100+ per image is
    expected and fine - steps 4-5 do the precision work)."""
    candidate = np.zeros(corrected_green.shape, dtype=bool)
    if lesion_class in TOPHAT_LESION_CLASSES:
        se_len = LESION_STRUCTURING_ELEMENT_LENGTH_PX[lesion_class]
        candidate |= _tophat_candidates(corrected_green, working_mask, se_len)
    if lesion_class in RATIO_SPOT_LESION_CLASSES:
        candidate |= lesion_features.find_candidate_spots(image_rgb, working_mask, lesion_class)
    return candidate


def _candidate_components(candidate_mask):
    n_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(candidate_mask.astype(np.uint8), connectivity=8)
    components = []
    for i in range(1, n_labels):
        area = int(stats[i, cv2.CC_STAT_AREA])
        if area < MIN_CANDIDATE_AREA_PX:
            continue
        x, y, w, h = (int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP]),
                      int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT]))
        mask_local = (labels[y:y + h, x:x + w] == i)
        components.append({
            "label_id": i, "centroid": (float(centroids[i][0]), float(centroids[i][1])),
            "area_px": area, "bbox": (x, y, w, h), "mask_local": mask_local,
        })
    return components


def run_lesion_pipeline(image_rgb, lesion_class, vessel_mask, fov_mask=None,
                         optic_disc=None, fovea=None, model=None, classify=True):
    """Runs the five-step pipeline for one lesion class. With classify=True
    (default) it returns kept + rejected candidates with feature vectors and
    keep/score decisions - the standalone Stage_2_CNN demonstration path.
    With classify=False it stops after step 4 (features) and returns
    candidates without a decision, for CV-fold-safe extraction - see module
    docstring."""
    green = image_rgb[..., 1]
    working_mask = fov_mask.copy() if fov_mask is not None else np.ones(green.shape, dtype=bool)

    if optic_disc is not None:
        od_mask = np.zeros(green.shape, dtype=np.uint8)
        cv2.circle(od_mask, (int(round(optic_disc.center_x)), int(round(optic_disc.center_y))),
                   max(int(round(optic_disc.radius * 1.2)), 1), 1, -1)
        working_mask &= ~od_mask.astype(bool)

    if fovea is not None:
        fovea_mask = np.zeros(green.shape, dtype=np.uint8)
        fovea_radius_px = 0.5 * (2.0 * optic_disc.radius) if optic_disc is not None else 10
        cv2.circle(fovea_mask, (int(round(fovea.x)), int(round(fovea.y))), max(int(round(fovea_radius_px)), 1), 1, -1)
        working_mask &= ~fovea_mask.astype(bool)

    # step 1
    corrected = shade_correct(green, mask=working_mask)
    # step 2
    working_mask = subtract_vessels(working_mask, vessel_mask)
    # step 3
    candidate_mask = threshold_candidates(image_rgb, corrected, working_mask, lesion_class)
    components = _candidate_components(candidate_mask)

    # step 4 (mandatory): per-candidate features, always computed
    vessel_dist_transform = ndimage.distance_transform_edt(~vessel_mask) if vessel_mask is not None else None
    candidates = []
    for comp in components:
        feats = lesion_features.extract_candidate_features(
            image_rgb, corrected, comp, vessel_mask, optic_disc, fovea, fov_mask,
            vessel_distance_transform=vessel_dist_transform)
        candidates.append({**comp, "features": feats})

    if not classify:
        return {
            "lesion_class": lesion_class, "candidate_mask": candidate_mask,
            "candidates": candidates, "kept": None,
            "n_candidates": len(candidates), "n_kept": None,
        }

    # step 5 (mandatory): classifier keep/reject
    if candidates:
        feature_matrix, _ = lesion_features.features_to_matrix([c["features"] for c in candidates])
        keep, scores = classifier_module.classify_candidates(feature_matrix, model=model)
    else:
        keep, scores = np.array([], dtype=bool), np.array([], dtype=float)

    for c, k, s in zip(candidates, keep, scores):
        c["keep"] = bool(k)
        c["score"] = float(s)

    kept = [c for c in candidates if c["keep"]]

    return {
        "lesion_class": lesion_class, "candidate_mask": candidate_mask,
        "candidates": candidates, "kept": kept,
        "n_candidates": len(candidates), "n_kept": len(kept),
    }

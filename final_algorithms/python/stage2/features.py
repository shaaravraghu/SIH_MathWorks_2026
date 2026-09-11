"""Stage 2 Module 3 feature schema (S2-01..S2-45) - see
notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md sections 2.2, 3 and
4.1, and code_testing/python/extract_module2_features.py (read-only
reference, not imported; several formulas below are reused from it
verbatim, per the coordinator's spec, so the measured within-resolution
correlations transfer).

CV-fold-safe API (Module3_Plan.md S4.1, S6.1): lesion candidate classifiers
must be fitted per cross-validation fold, on training rows only, or the
grading model learns its own weak labels back out of the lesion counts -
this already happened once (see the leakage table in S4.1). So extraction
is split in two:

  extract_stage2_candidates(image, fov_mask)
      -> Stage2Candidates, image-derived only, cacheable, contains nothing
         from a fitted classifier.
  stage2_features_from_candidates(candidates, classifiers=None)
      -> the S2-01..S2-45 row (dict). classifiers is a dict
         {"ma"|"haem"|"hard_exudate"|"cws": model-with-predict_proba, or
         (model, threshold), or an object exposing .model/.threshold};
         a missing/None entry falls back to classifier.py's placeholder
         rule.
  extract_stage2_features(image, fov_mask, classifiers=None)
      -> the two calls combined, for convenience / non-CV use.
"""

from dataclasses import dataclass

import cv2
import numpy as np
from scipy import ndimage

from . import classifier as classifier_module
from . import lesion_features
from . import lesion_pipeline
from . import quadrants
from . import resample
from . import vessels
from .fovea import locate_fovea
from .optic_disc import locate_optic_disc
from .pipeline import load_rgb

# --- microaneurysm / haemorrhage candidate finding ---------------------------
# Reused from the previous implementation's min_close/ma_candidates/
# hem_candidates (code_testing/python/extract_module2_features.py), per the
# coordinator's spec - these numbers are pinned, not placeholders.
MA_STRUCTURING_ELEMENT_LENGTH_PX = 15
MA_CANDIDATE_PERCENTILE = 99.0
MA_MIN_AREA_PX = 3
MA_MAX_AREA_PX = np.pi * (125.0 / resample.UM_PER_PX / 2.0) ** 2  # 125 um lesion diameter

HAEM_STRUCTURING_ELEMENT_LENGTH_PX = 41
HAEM_CANDIDATE_PERCENTILE = 96.0
HAEM_MAX_AREA_PX = np.pi * 17.0 ** 2
# Lower area bound for haemorrhage candidates is not restated by the
# coordinator, but the reference extractor rejects anything below
# MA_MAX_AREA_PX so the two lesion classes don't double-count the same
# blobs - reused here for continuity (documented judgment call).
HAEM_MIN_AREA_PX = MA_MAX_AREA_PX

SMALL_LESION_N_ORIENTATIONS = 12         # pinned
SMALL_LESION_VESSEL_DILATE_ITERS = 3     # pinned: "vessel mask dilated 3x3 for 3 iterations"

# --- quadrant pixel-count placeholders ----------------------------------------
# Not pinned by the coordinator ("a placeholder minimum pixel count") -
# calibrate before use.
VENOUS_BEADING_MIN_QUADRANT_PIXELS = 10
NV_IRMA_MIN_QUADRANT_PIXELS = 10

# --- column schema -------------------------------------------------------------

STAGE2_COLUMNS = [
    "vessel_density_pct", "vessel_fragmentation", "vessel_components",
    "vessel_largest_tree_pct", "vessel_length", "vessel_orientation_coherence",
    "major_vessel_pct", "branch1_vessel_pct", "minor_vessel_pct",
    "venous_beading_pct", "venous_beading_quadrants",
    "nv_score", "nv_score_max", "nvd_score", "nve_score", "nv_irma_quadrants",
    "od_x", "od_y", "od_radius_pct", "od_contrast",
    "fovea_x", "fovea_y", "od_fovea_dist_dd",
    "haem_count", "haem_q1", "haem_q2", "haem_q3", "haem_q4", "haem_q_min", "haem_q_max",
    "hard_exudate_count", "hard_exudate_area_pct", "exudate_fovea_min_dist_dd", "dme_flag",
    "cws_count", "cws_area_pct",
    "rule421_haem", "rule421_beading", "rule421_irma", "severe_npdr_flag",
    "ma_count", "ma_q1", "ma_q2", "ma_q3", "ma_q4",
]

_EXCLUDE = {"od_x", "od_y", "fovea_x", "fovea_y"}
_QC = {"od_radius_pct", "od_contrast", "od_fovea_dist_dd"}

STAGE2_ROLES = {
    name: ("EXCLUDE" if name in _EXCLUDE else "QC" if name in _QC else "MODEL")
    for name in STAGE2_COLUMNS
}

MODULE2_EQUIVALENT = {
    "vessel_density_pct": "vessel_pct",
    "vessel_fragmentation": "vessel_frag",
    "vessel_components": "vessel_comps",
    "vessel_largest_tree_pct": "vessel_largest_pct",
    "vessel_length": "vessel_skel_len",
    "vessel_orientation_coherence": "vessel_coh",
    "nv_score": "nv_fine",
    "nv_score_max": "nv_fine_max",
    "od_x": "od_x",
    "od_y": "od_y",
    "fovea_x": "fovea_x",
    "fovea_y": "fovea_y",
    "od_fovea_dist_dd": "fovea_od_dd",
    "haem_count": "hem_n",
    "haem_q_min": "q_min",
    "haem_q_max": "q_max",
    "rule421_haem": "rule421",
    "hard_exudate_count": "exu_n",
    "hard_exudate_area_pct": "exu_area",
    "ma_count": "ma_n",
}


@dataclass
class Stage2Candidates:
    # Holds only scalars and per-candidate arrays, never full-resolution images:
    # it is pickled once per image and reloaded in every CV fold, and 872x872
    # arrays would cost ~15 MB per image.
    image_features: dict        # every classifier-independent S2 column (vessels, calibre, NV, OD, fovea)
    optic_disc: object          # optic_disc.OpticDiscResult
    fovea: object               # fovea.FoveaResult
    lesion_candidates: dict     # {"ma"|"haem"|"hard_exudate"|"cws": {"features", "feature_names", "centroids", "areas", ...}}


# --- microaneurysm / haemorrhage candidate finding (reused from old code) ----

def _line_se(length, deg):
    se = np.zeros((length, length), dtype=np.uint8)
    se[length // 2, :] = 1
    rot = cv2.getRotationMatrix2D((length / 2 - 0.5, length / 2 - 0.5), deg, 1.0)
    return (cv2.warpAffine(se, rot, (length, length)) > 0).astype(np.uint8)


def _min_close(u8_img, length, n_orientations=SMALL_LESION_N_ORIENTATIONS):
    """Minimum over closings by line structuring elements at n_orientations
    - a structure is filled only if some single line BRIDGES it (reused
    verbatim from the previous implementation's min_close: L=15 for
    microaneurysms, L=41 for haemorrhages)."""
    closed_min = None
    for a in range(n_orientations):
        se = _line_se(length, a * 180.0 / n_orientations)
        closed = cv2.morphologyEx(u8_img, cv2.MORPH_CLOSE, se)
        closed_min = closed if closed_min is None else np.minimum(closed_min, closed)
    return closed_min


def _small_lesion_candidates(green01, vessel_mask, se_length_px, percentile, min_area, max_area,
                              vessel_dilate_iters=SMALL_LESION_VESSEL_DILATE_ITERS):
    """Steps 1-3 for microaneurysms/haemorrhages: scale-matched closing
    minus the image, vessel-masked (dilated 3x3 x vessel_dilate_iters),
    percentile-thresholded inside MEASUREMENT_MASK, area-filtered (reused
    from the previous implementation - see module docstring)."""
    u8 = (np.clip(green01, 0, 1) * 255).astype(np.uint8)
    closed = _min_close(u8, se_length_px)
    diff = (closed.astype(np.float64) - u8.astype(np.float64)) / 255.0

    dilated_vessel = ndimage.binary_dilation(vessel_mask, np.ones((3, 3)), iterations=vessel_dilate_iters)
    diff[dilated_vessel] = 0
    diff[~resample.MEASUREMENT_MASK] = 0

    if not np.any(diff > 0):
        return []
    thresh = max(float(np.percentile(diff[resample.MEASUREMENT_MASK], percentile)), 1e-4)
    bw = diff > thresh
    labels, n = ndimage.label(bw)
    if n == 0:
        return []

    candidates = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        mask_local = labels[sl] == i
        area = int(mask_local.sum())
        if area < min_area or area > max_area:
            continue
        y0, x0 = sl[0].start, sl[1].start
        h, w = mask_local.shape
        ys, xs = np.nonzero(mask_local)
        cy, cx = y0 + ys.mean(), x0 + xs.mean()
        candidates.append({
            "label_id": i, "centroid": (float(cx), float(cy)), "area_px": area,
            "bbox": (x0, y0, w, h), "mask_local": mask_local,
        })
    return candidates


def _features_for_candidates(candidates, work_rgb_u8, green255, vessel_mask, optic_disc, fovea, vessel_dist_transform):
    feats = [
        lesion_features.extract_candidate_features(
            work_rgb_u8, green255, c, vessel_mask, optic_disc, fovea, resample.MEASUREMENT_MASK,
            vessel_distance_transform=vessel_dist_transform)
        for c in candidates
    ]
    if feats:
        matrix, names = lesion_features.features_to_matrix(feats)
    else:
        matrix, names = np.zeros((0, len(lesion_features.FEATURE_ORDER))), lesion_features.FEATURE_ORDER
    centroids = np.array([c["centroid"] for c in candidates], dtype=np.float64).reshape(-1, 2)
    areas = np.array([c["area_px"] for c in candidates], dtype=np.float64)
    return {"features": matrix, "feature_names": names, "centroids": centroids, "areas": areas}


def _dme_touch(centroids, areas, fovea_point):
    """Approximate per-candidate pixel-level DME test: candidate touches the
    500um (34px) DME zone if its centroid, minus its own effective radius
    (area-equivalent disc), lies within DME_RADIUS_PX of the fovea.
    Documented approximation - an exact per-pixel mask test would need every
    candidate's full-resolution mask retained; this uses only centroid+area,
    which are already cacheable/classifier-free (Module3_Plan.md S4.1)."""
    if len(centroids) == 0:
        return np.zeros(0, dtype=bool)
    eff_radius = np.sqrt(np.maximum(areas, 0) / np.pi)
    dist = np.hypot(centroids[:, 0] - fovea_point[0], centroids[:, 1] - fovea_point[1])
    return (dist - eff_radius) <= resample.DME_RADIUS_PX


# --- vessel-map statistics (reused from the previous implementation) ---------

def _component_lengths(bw):
    """Skeleton length without thinning: w ~ 4*mean(EDT), L ~ area/w (reused
    verbatim from the previous implementation - ~160x faster than thinning,
    vectorised over all components)."""
    labels, n = ndimage.label(bw)
    if n == 0:
        return np.zeros(0), labels, 0, np.zeros(0)
    flat = labels.ravel()
    area = np.bincount(flat, minlength=n + 1)[1:].astype(np.float64)
    edt = ndimage.distance_transform_edt(bw)
    esum = np.bincount(flat, weights=edt.ravel(), minlength=n + 1)[1:]
    width = 4.0 * esum / np.maximum(area, 1)
    return area / np.maximum(width, 1e-6), labels, n, area


def _vessel_topology_stats(vessel_mask, green01):
    mm_area = float(resample.MEASUREMENT_MASK.sum())
    bw = vessel_mask & resample.MEASUREMENT_MASK
    lengths, _labels, n, area = _component_lengths(bw)
    total = int(bw.sum())
    vessel_length = float(lengths.sum()) if n else 0.0

    stats = {
        "vessel_density_pct": 100.0 * total / max(mm_area, 1.0),
        "vessel_components": int(n),
        "vessel_largest_tree_pct": 100.0 * (float(area.max()) / max(total, 1)) if n else 0.0,
        "vessel_length": vessel_length,
        "vessel_fragmentation": 1000.0 * n / max(vessel_length, 1.0),
    }

    gx = ndimage.sobel(green01, 1)
    gy = ndimage.sobel(green01, 0)
    Jxx = ndimage.gaussian_filter(gx * gx, 2.0)
    Jyy = ndimage.gaussian_filter(gy * gy, 2.0)
    Jxy = ndimage.gaussian_filter(gx * gy, 2.0)
    trace = Jxx + Jyy
    disc = np.sqrt(np.maximum((Jxx - Jyy) ** 2 + 4 * Jxy * Jxy, 0))
    with np.errstate(all="ignore"):
        coherence = np.nan_to_num(disc / np.maximum(trace, 1e-12))
    stats["vessel_orientation_coherence"] = float(coherence[bw].mean()) if total else 0.0
    return stats


def _calibre_pct(calibre):
    mm_area = float(resample.MEASUREMENT_MASK.sum())
    within_mm = calibre[resample.MEASUREMENT_MASK]

    def pct(label):
        return 100.0 * float(np.sum(within_mm == label)) / max(mm_area, 1.0)

    return {
        "major_vessel_pct": pct(vessels.VESSEL_CALIBRE_MAJOR),
        "branch1_vessel_pct": pct(vessels.VESSEL_CALIBRE_FIRST_BRANCH),
        "minor_vessel_pct": pct(vessels.VESSEL_CALIBRE_MINOR),
        "venous_beading_pct": pct(vessels.VESSEL_CALIBRE_BEADING),
    }


# --- OD-fovea quadrant convention (reused from the previous implementation) --

def _quadrant_axis(od_center, fovea_point):
    return float(np.arctan2(fovea_point[1] - od_center[1], fovea_point[0] - od_center[0]))


def _quadrant_index(points_xy, od_center, fovea_point):
    """ax = atan2(fovea_y-od_y, fovea_x-od_x);
    ang = mod(atan2(cy-od_y, cx-od_x) - ax, 2*pi);
    quadrant = clip(floor(ang/(pi/2)), 0, 3).
    Reused verbatim from the previous implementation's quadrant convention
    (coordinator's spec) so haem/ma/beading/NV quadrants stay comparable."""
    if len(points_xy) == 0:
        return np.zeros(0, dtype=int)
    points_xy = np.asarray(points_xy, dtype=np.float64)
    ax = _quadrant_axis(od_center, fovea_point)
    ang = np.mod(np.arctan2(points_xy[:, 1] - od_center[1], points_xy[:, 0] - od_center[0]) - ax, 2 * np.pi)
    return np.clip((ang // (np.pi / 2)).astype(int), 0, 3)


def _quadrant_counts(points_xy, od_center, fovea_point):
    idx = _quadrant_index(points_xy, od_center, fovea_point)
    if len(idx) == 0:
        return np.zeros(4, dtype=int)
    return np.bincount(idx, minlength=4)[:4]


def _pixel_quadrant_map(od_center, fovea_point, shape):
    """Quadrant index (0-3) for every pixel, same convention as
    _quadrant_index - used for pixel-mass features (venous beading, NV/IRMA
    quadrants) that have no discrete candidate centroid."""
    y, x = resample.PIXEL_Y, resample.PIXEL_X
    ax = _quadrant_axis(od_center, fovea_point)
    ang = np.mod(np.arctan2(y - od_center[1], x - od_center[0]) - ax, 2 * np.pi)
    return np.clip((ang // (np.pi / 2)).astype(int), 0, 3)


def _quadrants_holding(quadrant_map, mask, min_pixels):
    counts = [int(np.sum(mask & (quadrant_map == q))) for q in range(4)]
    n_quadrants = sum(1 for c in counts if c > min_pixels)
    return counts, n_quadrants


# --- neovascularisation / IRMA scores -----------------------------------------

def _nv_scores(green01, optic_disc):
    result = vessels.fine_scale_excess(green01, fov_mask=resample.MEASUREMENT_MASK)
    excess = result["excess"]
    mm = resample.MEASUREMENT_MASK
    mm_area = float(mm.sum())

    nv_score = result["nv_score"]
    nv_score_max = float(
        ndimage.uniform_filter(excess.astype(np.float64), size=int(resample.DD_PX))[mm].max()
    ) if mm.any() else 0.0

    dist_from_od = np.hypot(resample.PIXEL_Y - optic_disc.center_y, resample.PIXEL_X - optic_disc.center_x)
    within_1dd = dist_from_od <= resample.DD_PX
    nvd_score = 100.0 * float(np.sum(excess & within_1dd)) / max(mm_area, 1.0)
    nve_score = nv_score - nvd_score

    stats = {"nv_score": nv_score, "nv_score_max": nv_score_max, "nvd_score": nvd_score, "nve_score": nve_score}
    return stats, excess


# --- classifier resolution -----------------------------------------------------

def _resolve_classifier(entry):
    if entry is None:
        return None, classifier_module.THRESH_CLASSIFIER_KEEP_PROB
    if isinstance(entry, tuple) and len(entry) == 2:
        return entry[0], entry[1]
    model = getattr(entry, "model", entry)
    threshold = getattr(entry, "threshold", classifier_module.THRESH_CLASSIFIER_KEEP_PROB)
    return model, threshold


# --- public API ----------------------------------------------------------------

def extract_stage2_candidates(image, fov_mask) -> Stage2Candidates:
    """Image-derived-only extraction (Module3_Plan.md S4.1/S6.1): contains
    nothing from a fitted classifier, so it is safe to cache once per image
    and reuse across every cross-validation fold."""
    if isinstance(image, str):
        image = load_rgb(image)

    work01 = resample.resample_to_working_resolution(image, fov_mask)
    work_u8 = (np.clip(work01, 0, 1) * 255).astype(np.uint8)
    green01 = resample.prep_green(work01)
    green255 = green01 * 255.0

    vessels_result = vessels.build_vessel_map(work_u8, fov_mask=resample.RETINA_MASK)
    # "The vessel map is the finalized one: matched filtering (a) OR Frangi
    # calibre labels 1-3 (b)" - per the coordinator's spec.
    vessel_mask = vessels_result.matched_filter_mask | np.isin(
        vessels_result.calibre,
        [vessels.VESSEL_CALIBRE_MAJOR, vessels.VESSEL_CALIBRE_FIRST_BRANCH, vessels.VESSEL_CALIBRE_MINOR],
    )

    optic_disc = locate_optic_disc(work_u8, vessel_mask=vessel_mask, fov_mask=resample.RETINA_MASK)
    fovea = locate_fovea(work_u8, optic_disc, fov_mask=resample.RETINA_MASK)
    fovea_point = (fovea.x, fovea.y)

    vessel_dist_transform = ndimage.distance_transform_edt(~vessel_mask)

    image_features = _image_features(vessel_mask, vessels_result.calibre, green01, optic_disc, fovea)

    lesion_candidates = {}

    ma_raw = _small_lesion_candidates(green01, vessel_mask, MA_STRUCTURING_ELEMENT_LENGTH_PX,
                                       MA_CANDIDATE_PERCENTILE, MA_MIN_AREA_PX, MA_MAX_AREA_PX)
    lesion_candidates["ma"] = _features_for_candidates(ma_raw, work_u8, green255, vessel_mask, optic_disc, fovea, vessel_dist_transform)

    haem_raw = _small_lesion_candidates(green01, vessel_mask, HAEM_STRUCTURING_ELEMENT_LENGTH_PX,
                                         HAEM_CANDIDATE_PERCENTILE, HAEM_MIN_AREA_PX, HAEM_MAX_AREA_PX)
    lesion_candidates["haem"] = _features_for_candidates(haem_raw, work_u8, green255, vessel_mask, optic_disc, fovea, vessel_dist_transform)

    for key, lesion_class in (("hard_exudate", "hard_exudate"), ("cws", "nerve_fibre_ischemia")):
        result = lesion_pipeline.run_lesion_pipeline(
            work_u8, lesion_class, vessel_mask, fov_mask=resample.MEASUREMENT_MASK,
            optic_disc=optic_disc, fovea=fovea, classify=False)
        candidates = result["candidates"]
        feats = [c["features"] for c in candidates]
        if feats:
            matrix, names = lesion_features.features_to_matrix(feats)
        else:
            matrix, names = np.zeros((0, len(lesion_features.FEATURE_ORDER))), lesion_features.FEATURE_ORDER
        centroids = np.array([c["centroid"] for c in candidates], dtype=np.float64).reshape(-1, 2)
        areas = np.array([c["area_px"] for c in candidates], dtype=np.float64)
        packed = {"features": matrix, "feature_names": names, "centroids": centroids, "areas": areas}
        if key == "hard_exudate":
            packed["dme_touch"] = _dme_touch(centroids, areas, fovea_point)
        lesion_candidates[key] = packed

    return Stage2Candidates(image_features=image_features, optic_disc=optic_disc, fovea=fovea,
                            lesion_candidates=lesion_candidates)


def _image_features(vessel_mask, calibre, green01, optic_disc, fovea) -> dict:
    """Every S2 column no lesion classifier touches, computed once per image so
    CV folds never re-run the vessel and line-detector filters."""
    row = {}
    row.update(_vessel_topology_stats(vessel_mask, green01))
    row.update(_calibre_pct(calibre))

    od_center = (optic_disc.center_x, optic_disc.center_y)
    fovea_point = (fovea.x, fovea.y)
    quadrant_map = _pixel_quadrant_map(od_center, fovea_point, green01.shape)

    beading_mask = (calibre == vessels.VESSEL_CALIBRE_BEADING) & resample.MEASUREMENT_MASK
    _, row["venous_beading_quadrants"] = _quadrants_holding(
        quadrant_map, beading_mask, VENOUS_BEADING_MIN_QUADRANT_PIXELS)

    nv_stats, excess = _nv_scores(green01, optic_disc)
    row.update(nv_stats)
    _, row["nv_irma_quadrants"] = _quadrants_holding(
        quadrant_map, excess & resample.MEASUREMENT_MASK, NV_IRMA_MIN_QUADRANT_PIXELS)

    row["od_x"] = optic_disc.center_x
    row["od_y"] = optic_disc.center_y
    row["od_radius_pct"] = 100.0 * optic_disc.radius / resample.TARGET_R
    row["od_contrast"] = optic_disc.centre_surround_contrast
    row["fovea_x"] = fovea.x
    row["fovea_y"] = fovea.y
    row["od_fovea_dist_dd"] = float(
        np.hypot(fovea.x - optic_disc.center_x, fovea.y - optic_disc.center_y) / resample.DD_PX)
    return row


def stage2_features_from_candidates(candidates: Stage2Candidates, classifiers=None) -> dict:
    """Turns cached, classifier-free candidates into the S2-01..S2-45 row.
    classifiers: optional dict {"ma"|"haem"|"hard_exudate"|"cws": model or
    (model, threshold) or object with .model/.threshold}; a missing/None
    entry falls back to classifier.py's placeholder rule."""
    classifiers = classifiers or {}
    row = dict(candidates.image_features)

    od = candidates.optic_disc
    fovea = candidates.fovea
    od_center = (od.center_x, od.center_y)
    fovea_point = (fovea.x, fovea.y)
    venous_beading_quadrants = row["venous_beading_quadrants"]
    nv_irma_quadrants = row["nv_irma_quadrants"]

    mm_area = float(resample.MEASUREMENT_MASK.sum())

    # haemorrhages
    haem = candidates.lesion_candidates["haem"]
    model, thresh = _resolve_classifier(classifiers.get("haem"))
    keep, _scores = classifier_module.classify_candidates(haem["features"], model=model, threshold=thresh)
    kept_centroids = haem["centroids"][keep] if len(keep) else np.zeros((0, 2))
    counts = _quadrant_counts(kept_centroids, od_center, fovea_point)
    row["haem_count"] = int(keep.sum())
    row["haem_q1"], row["haem_q2"], row["haem_q3"], row["haem_q4"] = [int(c) for c in counts]
    row["haem_q_min"] = int(counts.min())
    row["haem_q_max"] = int(counts.max())
    row["rule421_haem"] = int(row["haem_q_min"] > quadrants.QUADRANT_COUNT_THRESH)

    # microaneurysms
    ma = candidates.lesion_candidates["ma"]
    model, thresh = _resolve_classifier(classifiers.get("ma"))
    keep, _scores = classifier_module.classify_candidates(ma["features"], model=model, threshold=thresh)
    kept_centroids = ma["centroids"][keep] if len(keep) else np.zeros((0, 2))
    counts = _quadrant_counts(kept_centroids, od_center, fovea_point)
    row["ma_count"] = int(keep.sum())
    row["ma_q1"], row["ma_q2"], row["ma_q3"], row["ma_q4"] = [int(c) for c in counts]

    # hard exudates
    exu = candidates.lesion_candidates["hard_exudate"]
    model, thresh = _resolve_classifier(classifiers.get("hard_exudate"))
    keep, _scores = classifier_module.classify_candidates(exu["features"], model=model, threshold=thresh)
    row["hard_exudate_count"] = int(keep.sum())
    kept_areas = exu["areas"][keep] if len(keep) else np.zeros(0)
    row["hard_exudate_area_pct"] = 100.0 * float(kept_areas.sum()) / max(mm_area, 1.0)

    max_possible_dist_dd = (2 * resample.TARGET_R * np.sqrt(2.0)) / resample.DD_PX
    if keep.any():
        kept_centroids = exu["centroids"][keep]
        dists = np.hypot(kept_centroids[:, 0] - fovea.x, kept_centroids[:, 1] - fovea.y) / resample.DD_PX
        row["exudate_fovea_min_dist_dd"] = float(dists.min())
    else:
        row["exudate_fovea_min_dist_dd"] = float(max_possible_dist_dd)

    dme_touch = exu.get("dme_touch", np.zeros(len(keep), dtype=bool))
    row["dme_flag"] = int(np.any(dme_touch[keep])) if keep.any() else 0

    # cotton-wool spots (nerve fibre ischemia)
    cws = candidates.lesion_candidates["cws"]
    model, thresh = _resolve_classifier(classifiers.get("cws"))
    keep, _scores = classifier_module.classify_candidates(cws["features"], model=model, threshold=thresh)
    row["cws_count"] = int(keep.sum())
    kept_areas = cws["areas"][keep] if len(keep) else np.zeros(0)
    row["cws_area_pct"] = 100.0 * float(kept_areas.sum()) / max(mm_area, 1.0)

    row["rule421_beading"] = int(venous_beading_quadrants >= 2)
    row["rule421_irma"] = int(nv_irma_quadrants >= 1)
    row["severe_npdr_flag"] = int(bool(row["rule421_haem"]) or bool(row["rule421_beading"]) or bool(row["rule421_irma"]))

    return {name: row[name] for name in STAGE2_COLUMNS}


def extract_stage2_features(image, fov_mask, classifiers=None) -> dict:
    candidates = extract_stage2_candidates(image, fov_mask)
    return stage2_features_from_candidates(candidates, classifiers=classifiers)

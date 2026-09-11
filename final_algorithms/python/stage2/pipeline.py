"""Stage 2 workflow: resample to the working resolution (see resample.py -
every pixel constant in Stage_2_CNN assumes it), build the vessel map
(matched filtering + Frangi calibre bands + fine-scale-excess abnormal-
vessel labelling), locate the optic disc, locate the fovea, derive the
OD-fovea quadrant axis, run the five-step lesion pipeline per lesion class,
and bucket haemorrhage candidates into OD-fovea-anchored quadrants for the
re-derived 4-2-1 count.

See notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN for the full spec;
each stage-specific module docstring quotes the relevant section. This is
the standalone Stage_2_CNN demonstration entry point (steps 4-5 of the
lesion pipeline always classify inline, falling back to the placeholder
rule with model=None); the CV-fold-safe Module 3 feature schema
(S2-01..S2-45) lives in features.py instead.
"""

from dataclasses import dataclass

import cv2
import numpy as np

from . import resample
from .fovea import FoveaResult, locate_fovea
from .lesion_pipeline import run_lesion_pipeline
from .optic_disc import OpticDiscResult, locate_optic_disc
from .quadrants import QuadrantResult, count_quadrants
from .vessels import VesselMapResult, build_vessel_map, split_nvd_nve

LESION_CLASSES = ("microaneurysm", "haemorrhage", "hard_exudate", "nerve_fibre_ischemia")


def load_rgb(path: str) -> np.ndarray:
    bgr = cv2.imread(path, cv2.IMREAD_COLOR)
    if bgr is None:
        raise FileNotFoundError(path)
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def _fov_mask_from_image(image, black_thresh=10):
    """Minimal FOV mask (non-black region), matching stage1's approach, so
    stage2 can run standalone. Pass an explicit fov_mask (e.g. stage1's
    build_fov_mask output) to reuse stage1's FOV detection instead."""
    if image.ndim == 3:
        is_black = np.all(image <= black_thresh, axis=-1)
    else:
        is_black = image <= black_thresh
    return ~is_black


@dataclass
class Stage2Report:
    vessels: VesselMapResult
    optic_disc: OpticDiscResult
    fovea: FoveaResult
    quadrant_axis_deg: float
    lesions: dict               # lesion_class -> run_lesion_pipeline() result dict
    nv_score: float
    nvd_nve: dict                # {"nvd": [...], "nve": [...], "nvd_count", "nve_count"}
    quadrants: QuadrantResult    # haemorrhage-candidate quadrant counts + 4-2-1 flag


def run_stage2(image, fov_mask=None, model=None) -> Stage2Report:
    """image: file path or RGB uint8 numpy array. fov_mask: boolean mask at
    the ORIGINAL image resolution (recommended: stage1's
    fov_detection.build_fov_mask output); if omitted a minimal non-black
    mask is derived here. The image is resampled internally to the working
    resolution (resample.TARGET_R) before anything else runs.
    model: optional shared sklearn-compatible classifier passed to every
    lesion class's step-5 classifier (see classifier.py).
    """
    if isinstance(image, str):
        image = load_rgb(image)

    if fov_mask is None:
        fov_mask = _fov_mask_from_image(image)

    work01 = resample.resample_to_working_resolution(image, fov_mask)
    work_u8 = (np.clip(work01, 0, 1) * 255).astype(np.uint8)
    working_fov_mask = resample.RETINA_MASK

    vessels = build_vessel_map(work_u8, fov_mask=working_fov_mask)

    # Optic disc: brightness search masks out vessel-detected pixels first,
    # per the notes ("avoid regions with blood vessel detected").
    optic_disc = locate_optic_disc(work_u8, vessel_mask=vessels.matched_filter_mask, fov_mask=working_fov_mask)

    fovea = locate_fovea(work_u8, optic_disc, fov_mask=working_fov_mask)

    quadrant_axis_deg = float(np.degrees(np.arctan2(
        fovea.y - optic_disc.center_y, fovea.x - optic_disc.center_x)))

    lesions = {}
    for lesion_class in LESION_CLASSES:
        lesions[lesion_class] = run_lesion_pipeline(
            work_u8, lesion_class, vessels.matched_filter_mask, fov_mask=working_fov_mask,
            optic_disc=optic_disc, fovea=fovea, model=model)

    nvd_nve = split_nvd_nve(vessels.excess_mask, optic_disc)

    haem_points = [c["centroid"] for c in lesions["haemorrhage"]["kept"]]
    od_center = (optic_disc.center_x, optic_disc.center_y)
    fovea_point = (fovea.x, fovea.y)
    quadrants = count_quadrants(haem_points, od_center, fovea_point)

    return Stage2Report(
        vessels=vessels,
        optic_disc=optic_disc,
        fovea=fovea,
        quadrant_axis_deg=quadrant_axis_deg,
        lesions=lesions,
        nv_score=vessels.nv_score,
        nvd_nve=nvd_nve,
        quadrants=quadrants,
    )

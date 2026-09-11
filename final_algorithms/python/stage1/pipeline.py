"""Stage 1 workflow:

Start -> Pixel Dimension (#1) -> FOV Detection (#2) -> Sharpness/Contrast (#3) -> PASS
Borderline -> Enhancement (#4: Flat Field Correction, CLAHE) -> Image Updation -> PASS

Fail at any gate exits immediately. Borderline results are recorded and the
cascade CONTINUES (so a later fail still rejects); if anything was borderline
at the end, the image goes through the enhancement branch.
"""

import cv2
import numpy as np

from .enhancement import enhance_borderline
from .fov_detection import fov_detection
from .pixel_dimension import check_pixel_dimension_image
from .sharpness_contrast import sharpness_contrast_cascade


def load_rgb(path: str) -> np.ndarray:
    bgr = cv2.imread(path, cv2.IMREAD_COLOR)
    if bgr is None:
        raise FileNotFoundError(path)
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def run_stage1(image, seed: int = None) -> dict:
    """image: file path or RGB uint8 numpy array.

    Returns {"status": "pass"|"fail", "image": final image, "borderline": bool, ...}.
    """
    if isinstance(image, str):
        image = load_rgb(image)

    rng = np.random.default_rng(seed)
    report = {"borderline_sources": []}

    # #1 Pixel Dimension
    pixel = check_pixel_dimension_image(image)
    report["pixel_dimension"] = pixel
    if pixel.status == "fail":
        return {"status": "fail", "stage": "pixel_dimension", "image": image, **report}
    if pixel.status == "borderline":
        report["borderline_sources"].append("pixel_dimension")

    # #2 FOV Detection
    fov = fov_detection(image, rng=rng)
    report["fov_detection"] = fov
    if fov["status"] == "fail":
        return {"status": "fail", "stage": f"fov_{fov['stage']}", "image": image, **report}
    fov_mask = fov["fov"].mask

    # #3 Sharpness / Contrast
    sharp = sharpness_contrast_cascade(image, fov_mask=fov_mask, rng=rng)
    report["sharpness_contrast"] = sharp
    if sharp.status == "fail":
        return {"status": "fail", "stage": "sharpness_contrast", "image": image, **report}
    if sharp.status == "borderline":
        report["borderline_sources"].append("sharpness_contrast")

    if not report["borderline_sources"]:
        return {"status": "pass", "borderline": False, "image": image, "fov_mask": fov_mask, **report}

    # #4 Enhancement for Borderline images
    enhanced = enhance_borderline(image, fov_mask)
    report["enhancement"] = enhanced
    if enhanced["status"] == "fail":
        return {"status": "fail", "stage": f"enhancement_{enhanced['stage']}", "image": image, **report}

    # Image Updation
    return {"status": "pass", "borderline": True, "image": enhanced["image"], "fov_mask": fov_mask, **report}

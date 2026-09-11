"""#5 CLASSIFIER step of the five-step lesion pipeline (see
notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "THE FIVE-STEP LESION
PIPELINE" and "Feature Engineering" sections).

Thin, swappable keep/reject interface only - this module does NOT implement
a training loop.

Intended training protocol (not implemented here, per Module3_Plan.md
S4.1/S6.1): weak labels (grade 0 vs grades 3-4) with GroupKFold BY IMAGE so
no image scores itself, and every lesion classifier fitted INSIDE each
cross-validation fold on training rows only - leakage has already happened
once in the previous implementation (a microaneurysm classifier trained on
250 images scored those same 250 images inside its own feature table).
Every new feature must also be verified WITHIN RESOLUTION STRATA before
being trusted - stage1's Module 2 features reportedly predict image
RESOLUTION at 67.8% against a 17% chance baseline, i.e. features can
silently encode capture-device artifacts rather than disease.

Classifier threshold: fix the selection criterion BEFORE sweeping (e.g. "the
lowest probability at which the grade-0 median count is 0"). Choosing the
threshold to maximise a correlation, then reporting that correlation, is
circular - the notes call this out explicitly.
"""

import numpy as np

# Placeholder: not pinned in notes. Fix the selection criterion before
# sweeping - see module docstring.
THRESH_CLASSIFIER_KEEP_PROB = 0.5


def classify_candidates(feature_matrix: np.ndarray, model=None, threshold: float = THRESH_CLASSIFIER_KEEP_PROB):
    """Returns (keep: bool array, score: float array).

    model: optional sklearn-compatible fitted classifier exposing
    predict_proba(X) -> (N, 2), positive ("keep") class in column 1.
    With no model supplied, falls back to a documented placeholder rule so
    step 5 is never a silent no-op.
    """
    if feature_matrix is None or len(feature_matrix) == 0:
        return np.array([], dtype=bool), np.array([], dtype=float)

    if model is not None and hasattr(model, "predict_proba"):
        scores = np.asarray(model.predict_proba(feature_matrix))[:, 1]
    else:
        scores = _placeholder_score(feature_matrix)

    keep = scores >= threshold
    return keep, scores


def _placeholder_score(feature_matrix: np.ndarray) -> np.ndarray:
    """Fallback scoring when no fitted model is supplied: per-column min-max
    normalisation, averaged into a single 0-1 score. This is NOT a trained
    classifier - it exists only so the pipeline's step 5 always runs code
    (steps 4-5 are structurally mandatory, per the notes' measured result
    that thresholding alone always fails). Replace with a real fitted model
    before drawing conclusions from kept candidates.
    """
    col_min = feature_matrix.min(axis=0, keepdims=True)
    col_max = feature_matrix.max(axis=0, keepdims=True)
    span = np.maximum(col_max - col_min, 1e-6)
    normed = (feature_matrix - col_min) / span
    return normed.mean(axis=1)

"""S6.4 / S7.1: turn the continuous grade score into a calibrated referable
probability, and apply the confidence routing and DME override.

Both calibrators are fitted on the 425 OUT-OF-FOLD dev predictions and frozen
before the test set is touched (S7.2).
"""

import numpy as np

from sklearn.isotonic import IsotonicRegression
from sklearn.linear_model import LogisticRegression

# S6.4: confidence is lowered for images Stage 1 flagged. These are CONF
# columns, never model inputs (D7). The multipliers are NOT pinned by the
# plan - placeholders, calibrate before use.
CONFIDENCE_PENALTY_BORDERLINE = 0.85   # placeholder: stage1_verdict = borderline (S1-20)
CONFIDENCE_PENALTY_ENHANCED = 0.90     # placeholder: enhancement_applied = 1 (S1-21)


class PlattCalibrator:
    """Logistic (Platt) calibration of the continuous score into P(referable)."""

    def __init__(self):
        self.model = None

    def fit(self, scores, labels):
        self.model = LogisticRegression(solver="lbfgs")
        self.model.fit(np.asarray(scores).reshape(-1, 1), np.asarray(labels).astype(int))
        return self

    def predict(self, scores):
        return self.model.predict_proba(np.asarray(scores).reshape(-1, 1))[:, 1]


class IsotonicCalibrator:
    """Isotonic calibration - more flexible than Platt, but it can overfit on
    425 rows, so compare ECE before adopting it (S7.1)."""

    def __init__(self):
        self.model = None

    def fit(self, scores, labels):
        self.model = IsotonicRegression(out_of_bounds="clip", y_min=0.0, y_max=1.0)
        self.model.fit(np.asarray(scores, dtype=np.float64), np.asarray(labels).astype(float))
        return self

    def predict(self, scores):
        return self.model.predict(np.asarray(scores, dtype=np.float64))


CALIBRATORS = {"platt": PlattCalibrator, "isotonic": IsotonicCalibrator}


def apply_confidence_routing(probabilities, borderline, enhanced):
    """S6.4: lower the calibrated probability for borderline / enhanced images.

    This changes the CONFIDENCE attached to a prediction, not the prediction
    itself - S1-21 exists because CLAHE cost 20% of microaneurysm
    detectability in Module 1 testing, and this is how Module 3 detects that
    effect rather than silently absorbing it.
    """
    out = np.asarray(probabilities, dtype=np.float64).copy()
    out = np.where(np.asarray(borderline), out * CONFIDENCE_PENALTY_BORDERLINE, out)
    out = np.where(np.asarray(enhanced), out * CONFIDENCE_PENALTY_ENHANCED, out)
    return np.clip(out, 0.0, 1.0)


def apply_dme_override(referable_decisions, dme_flags):
    """S6.4: dme_flag (S2-34) forces urgent referral REGARDLESS of grade.

    An exudate within 500 um (34 px) of the fovea is sight-threatening on its
    own, so it overrides the grading decision rather than feeding into it.
    Returns (decision, urgent) where `urgent` marks the overridden rows.
    """
    decisions = np.asarray(referable_decisions).astype(bool)
    dme = np.asarray(dme_flags).astype(bool)
    return (decisions | dme), dme


def calibrate_and_route(scores, labels, borderline, enhanced, method="platt"):
    """Fit a calibrator on out-of-fold scores and return both the raw and the
    confidence-routed probabilities, for the S7.1 reliability comparison."""
    calibrator = CALIBRATORS[method]().fit(scores, labels)
    raw = calibrator.predict(scores)
    routed = apply_confidence_routing(raw, borderline, enhanced)
    return calibrator, raw, routed

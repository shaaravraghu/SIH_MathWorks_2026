"""S6.2 / D6: turn the network's continuous grade score into a 5-class grade by
rounding at CUTPOINTS FITTED ON THE DEV DATA, not at 0.5/1.5/2.5/3.5.

WHY FITTED CUTPOINTS. Rounding a regression output pulls predictions toward the
middle grades (S7.3). The previous model predicted grade 4 for only 3 of 61
true grade-4 images, calling most of them grade 3; and grade 1 was called
grade 2 more often than grade 1. Fitted cutpoints are the first remedy the
plan prescribes, an ordinal (CORAL) head the second (D6) - regression +
cutpoints first.

FITTED ON OUT-OF-FOLD PREDICTIONS ONLY (S7.2). The cutpoints are a model
choice, so they are chosen on the 425 out-of-fold dev predictions and then
FROZEN before the test set is touched.
"""

import numpy as np

from .metrics import quadratic_weighted_kappa

N_GRADES = 5
DEFAULT_CUTPOINTS = np.array([0.5, 1.5, 2.5, 3.5])   # naive rounding, the thing we are replacing


def apply_cutpoints(scores, cutpoints):
    """Continuous score -> integer grade 0..4."""
    return np.searchsorted(np.asarray(cutpoints, dtype=np.float64),
                           np.asarray(scores, dtype=np.float64), side="left")


def fit_cutpoints(scores, true_grades, n_starts=1, seed=0, max_passes=50):
    """Coordinate ascent on QWK over the four cutpoints.

    Each cutpoint is moved in turn to the midpoint between adjacent sorted
    score values that maximises QWK, holding the others fixed, repeating until
    nothing improves. Simple and deterministic; with 425 rows an exhaustive
    4-D search is unnecessary.

    Initialised from the score quantiles matching the TRUE grade distribution,
    which is a much better start than 0.5/1.5/2.5/3.5 when the regression is
    compressed toward the middle.
    """
    scores = np.asarray(scores, dtype=np.float64)
    true_grades = np.clip(np.rint(np.asarray(true_grades)).astype(int), 0, N_GRADES - 1)
    if len(scores) == 0:
        return DEFAULT_CUTPOINTS.copy()

    # quantile initialisation from the observed grade mix
    counts = np.bincount(true_grades, minlength=N_GRADES).astype(np.float64)
    cumulative = np.cumsum(counts)[:-1] / max(counts.sum(), 1.0)
    cutpoints = np.quantile(scores, np.clip(cumulative, 0.0, 1.0))
    cutpoints = np.sort(cutpoints)

    candidates = _candidate_positions(scores)
    best = quadratic_weighted_kappa(true_grades, apply_cutpoints(scores, cutpoints))

    for _ in range(max_passes):
        improved = False
        for k in range(len(cutpoints)):
            lower = cutpoints[k - 1] if k > 0 else -np.inf
            upper = cutpoints[k + 1] if k + 1 < len(cutpoints) else np.inf
            for position in candidates:
                if not (lower <= position <= upper):
                    continue
                trial = cutpoints.copy()
                trial[k] = position
                score = quadratic_weighted_kappa(true_grades, apply_cutpoints(scores, trial))
                if not np.isnan(score) and score > best + 1e-12:
                    best, cutpoints, improved = score, trial, True
        if not improved:
            break
    return cutpoints


def _candidate_positions(scores):
    """Midpoints between consecutive unique scores - the only places a cutpoint
    changes any assignment. Capped so a large dev set stays fast."""
    unique = np.unique(scores)
    if len(unique) < 2:
        return unique
    midpoints = (unique[:-1] + unique[1:]) / 2.0
    if len(midpoints) > 400:
        midpoints = np.quantile(midpoints, np.linspace(0, 1, 400))
    return midpoints

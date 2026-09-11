"""S7.1 evaluation metrics, plus the S4.3 within-resolution wrapper.

PLAIN ACCURACY IS FORBIDDEN (S7.1). A model predicting grade 0 for everything
scores 49% on APTOS's true mix. Per-class sensitivity is reported instead,
because it does not depend on prevalence - which matters here since the pilot
sample is balanced at 100 per grade and the true mix is 49/10/27/5/8 (S5.1).

EVERY METRIC MUST ALSO BE REPORTED WITHIN RESOLUTION STRATA (S4.3). Even the
Module 2 features alone identify the camera 66% of the time against a 16.7%
chance baseline, so a pooled figure partly measures the camera rather than the
disease. within_resolution() is the wrapper that enforces this.
"""

import numpy as np

N_GRADES = 5
REFERABLE_GRADE = 2
TARGET_SENSITIVITY = 0.90   # S7.2 / the problem statement


def quadratic_weighted_kappa(true_grades, pred_grades, n_classes=N_GRADES):
    """S7.1's model-selection metric: penalises errors by squared distance, so
    a 0->4 miss costs 16x a 0->1 miss."""
    true_grades = np.clip(np.rint(true_grades).astype(int), 0, n_classes - 1)
    pred_grades = np.clip(np.rint(pred_grades).astype(int), 0, n_classes - 1)
    if len(true_grades) == 0:
        return float("nan")

    observed = confusion_matrix(true_grades, pred_grades, n_classes).astype(np.float64)
    weights = np.zeros((n_classes, n_classes))
    for i in range(n_classes):
        for j in range(n_classes):
            weights[i, j] = ((i - j) ** 2) / ((n_classes - 1) ** 2)

    hist_true = np.bincount(true_grades, minlength=n_classes).astype(np.float64)
    hist_pred = np.bincount(pred_grades, minlength=n_classes).astype(np.float64)
    expected = np.outer(hist_true, hist_pred)

    obs_sum, exp_sum = observed.sum(), expected.sum()
    if obs_sum == 0 or exp_sum == 0:
        return float("nan")
    observed /= obs_sum
    expected /= exp_sum

    denominator = (weights * expected).sum()
    if denominator == 0:
        return float("nan")
    return float(1.0 - (weights * observed).sum() / denominator)


def confusion_matrix(true_grades, pred_grades, n_classes=N_GRADES):
    """S7.1: rows are the true grade, columns the prediction."""
    true_grades = np.clip(np.rint(true_grades).astype(int), 0, n_classes - 1)
    pred_grades = np.clip(np.rint(pred_grades).astype(int), 0, n_classes - 1)
    matrix = np.zeros((n_classes, n_classes), dtype=int)
    for t, p in zip(true_grades, pred_grades):
        matrix[t, p] += 1
    return matrix


def per_class_sensitivity(true_grades, pred_grades, n_classes=N_GRADES):
    """S7.1. Grade-4 recall is reported on its own line (S8): the previous
    model predicted it for only 3 of 61 true grade-4 images."""
    matrix = confusion_matrix(true_grades, pred_grades, n_classes)
    out = np.full(n_classes, np.nan)
    for c in range(n_classes):
        total = matrix[c].sum()
        if total > 0:
            out[c] = matrix[c, c] / total
    return out


def roc_auc(labels, scores):
    """Rank-based AUC (equivalent to the Mann-Whitney U statistic); ties get
    averaged ranks."""
    labels = np.asarray(labels).astype(int)
    scores = np.asarray(scores, dtype=np.float64)
    n_pos, n_neg = int((labels == 1).sum()), int((labels == 0).sum())
    if n_pos == 0 or n_neg == 0:
        return float("nan")
    order = np.argsort(scores, kind="mergesort")
    ranks = np.empty(len(scores), dtype=np.float64)
    sorted_scores = scores[order]
    i = 0
    while i < len(sorted_scores):
        j = i
        while j + 1 < len(sorted_scores) and sorted_scores[j + 1] == sorted_scores[i]:
            j += 1
        ranks[order[i:j + 1]] = 0.5 * (i + j) + 1.0
        i = j + 1
    return float((ranks[labels == 1].sum() - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg))


def sensitivity_specificity(labels, scores, threshold):
    labels = np.asarray(labels).astype(int)
    predicted = (np.asarray(scores) >= threshold).astype(int)
    tp = int(((predicted == 1) & (labels == 1)).sum())
    fn = int(((predicted == 0) & (labels == 1)).sum())
    tn = int(((predicted == 0) & (labels == 0)).sum())
    fp = int(((predicted == 1) & (labels == 0)).sum())
    sens = tp / (tp + fn) if (tp + fn) else float("nan")
    spec = tn / (tn + fp) if (tn + fp) else float("nan")
    return sens, spec


def operating_point(labels, scores, target_sensitivity=TARGET_SENSITIVITY):
    """S7.2: walk the ROC curve, find the threshold where referable sensitivity
    first reaches the target, and read off the specificity there.

    FREEZE the returned threshold and apply it to the test set exactly once.
    Choosing it on the test set is the most common accidental cheat in this
    field, which is why this function only ever sees out-of-fold predictions.
    """
    labels = np.asarray(labels).astype(int)
    scores = np.asarray(scores, dtype=np.float64)
    if len(scores) == 0 or labels.sum() == 0:
        return {"threshold": float("nan"), "sensitivity": float("nan"),
                "specificity": float("nan"), "reached_target": False}

    best = None
    for threshold in np.unique(scores)[::-1]:
        sens, spec = sensitivity_specificity(labels, scores, threshold)
        if sens >= target_sensitivity:
            # first threshold (highest, i.e. most specific) that clears the bar
            best = {"threshold": float(threshold), "sensitivity": float(sens),
                    "specificity": float(spec), "reached_target": True}
            break
    if best is None:
        threshold = float(np.min(scores))
        sens, spec = sensitivity_specificity(labels, scores, threshold)
        best = {"threshold": threshold, "sensitivity": float(sens),
                "specificity": float(spec), "reached_target": False}
    return best


def expected_calibration_error(labels, probabilities, n_bins=10):
    """S7.1's calibration check, reported before and after calibration."""
    labels = np.asarray(labels).astype(int)
    probabilities = np.asarray(probabilities, dtype=np.float64)
    if len(labels) == 0:
        return float("nan"), []
    edges = np.linspace(0.0, 1.0, n_bins + 1)
    total, ece, diagram = len(labels), 0.0, []
    for lo, hi in zip(edges[:-1], edges[1:]):
        in_bin = (probabilities >= lo) & (probabilities < hi if hi < 1.0 else probabilities <= hi)
        n = int(in_bin.sum())
        if n == 0:
            diagram.append({"lo": float(lo), "hi": float(hi), "n": 0,
                            "confidence": float("nan"), "accuracy": float("nan")})
            continue
        confidence = float(probabilities[in_bin].mean())
        accuracy = float(labels[in_bin].mean())
        ece += (n / total) * abs(accuracy - confidence)
        diagram.append({"lo": float(lo), "hi": float(hi), "n": n,
                        "confidence": confidence, "accuracy": accuracy})
    return float(ece), diagram


def within_resolution(metric_fn, resolutions, *arrays, min_rows=10):
    """S4.3: compute `metric_fn(*arrays)` inside one resolution at a time, then
    average across strata. Strata with fewer than `min_rows` rows are skipped
    and reported, rather than contributing a metric computed on noise.

    This is the honest number. The pooled equivalent rewards a model for
    learning which camera took the picture.
    """
    resolutions = np.asarray(resolutions)
    per_stratum, skipped = {}, {}
    for res in sorted(set(resolutions.tolist())):
        mask = resolutions == res
        n = int(mask.sum())
        if n < min_rows:
            skipped[res] = n
            continue
        value = metric_fn(*[np.asarray(a)[mask] for a in arrays])
        if value is not None and not (isinstance(value, float) and np.isnan(value)):
            per_stratum[res] = float(value)
    mean = float(np.mean(list(per_stratum.values()))) if per_stratum else float("nan")
    return {"mean": mean, "per_stratum": per_stratum, "skipped": skipped}


def bootstrap_ci(metric_fn, *arrays, n_boot=2000, alpha=0.05, seed=0):
    """S7.1: bootstrap 95% CI. 15 images per grade makes the test intervals
    wide - report them, don't hide them."""
    rng = np.random.default_rng(seed)
    arrays = [np.asarray(a) for a in arrays]
    n = len(arrays[0])
    if n == 0:
        return {"point": float("nan"), "lo": float("nan"), "hi": float("nan")}
    point = metric_fn(*arrays)
    samples = []
    for _ in range(n_boot):
        idx = rng.integers(0, n, n)
        value = metric_fn(*[a[idx] for a in arrays])
        if value is not None and not (isinstance(value, float) and np.isnan(value)):
            samples.append(value)
    if not samples:
        return {"point": float(point), "lo": float("nan"), "hi": float("nan")}
    lo, hi = np.percentile(samples, [100 * alpha / 2, 100 * (1 - alpha / 2)])
    return {"point": float(point), "lo": float(lo), "hi": float(hi), "n_boot": len(samples)}


def summarise(true_grades, pred_grades, scores, resolutions, threshold=None):
    """Everything in S7.1 for one set of predictions, pooled and within
    resolution strata."""
    true_grades = np.asarray(true_grades)
    referable = (true_grades >= REFERABLE_GRADE).astype(int)
    report = {
        "n": int(len(true_grades)),
        "qwk": quadratic_weighted_kappa(true_grades, pred_grades),
        "confusion": confusion_matrix(true_grades, pred_grades).tolist(),
        "per_class_sensitivity": per_class_sensitivity(true_grades, pred_grades).tolist(),
        "grade4_recall": float(per_class_sensitivity(true_grades, pred_grades)[4]),
        "referable_auc": roc_auc(referable, scores),
        "qwk_within_resolution": within_resolution(
            quadratic_weighted_kappa, resolutions, true_grades, pred_grades),
        "referable_auc_within_resolution": within_resolution(
            roc_auc, resolutions, referable, scores),
    }
    if threshold is not None:
        sens, spec = sensitivity_specificity(referable, scores, threshold)
        report["referable_sensitivity"] = float(sens)
        report["referable_specificity"] = float(spec)
        report["threshold"] = float(threshold)
    return report

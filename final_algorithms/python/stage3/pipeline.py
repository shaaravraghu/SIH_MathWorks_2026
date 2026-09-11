"""S6.1: the cross-validation loop, and the Phase 4-8 entry points.

    for each of the 5 dev folds:
        train rows = the other 4 folds
        1. fit every lesion candidate classifier on TRAIN rows only    (S4.1)
        2. extract lesion counts for TRAIN and the held-out fold with them
        3. fit z-score normalisation on TRAIN rows only
        4. train the network on TRAIN rows
        5. predict the held-out fold  ->  out-of-fold predictions
    after all folds:
        choose cutpoints, calibration and the referable operating point
        on the 425 out-of-fold predictions
    then, once:
        retrain on all 425 dev rows and evaluate on the 75 test rows

Steps 1 and 2 are the expensive ones and the reason this is not a plain
sklearn cross_val_score: candidate features are cached per image, but the
lesion classifiers are refitted five times so that no image is ever scored by
a classifier that trained on it (S4.1).

NOTHING HERE HAS BEEN RUN. The module is written to the plan; it needs the
Phase 2 extraction output before it can execute.
"""

import numpy as np

from . import calibration, columns as col, cutpoints as cut, metrics, models
from .fold_features import recompute_lesion_columns
from .lesion_classifiers import fit_fold_classifiers


def run_cross_validation(dataset, candidate_loader, feature_names,
                         refit_lesions=True, verbose=True):
    """S6.1 steps 1-5 over all five dev folds. Returns out-of-fold predictions
    aligned to the dev rows, plus the per-fold artefacts."""
    dev = dataset.dev()
    fold_ids = dev.folds()
    if not fold_ids:
        raise ValueError("no dev rows with a cv_fold - check module3_splits.csv")

    grades = {r["id_code"]: r["diagnosis"] for r in dataset.rows}
    oof_score = {}
    fold_artefacts = []

    for k in fold_ids:
        train, held = dev.not_fold(k), dev.fold(k)
        if verbose:
            print(f"  fold {k}: train {len(train)} | held-out {len(held)}")

        # --- step 1: lesion classifiers, TRAIN rows only (S4.1) --------------
        if refit_lesions:
            classifiers = fit_fold_classifiers(candidate_loader, train.ids(), grades,
                                               verbose=verbose)
            # --- step 2: recompute the classifier-dependent columns ----------
            train_over, _ = recompute_lesion_columns(
                candidate_loader, train.ids(), classifiers, verbose=verbose)
            held_over, _ = recompute_lesion_columns(
                candidate_loader, held.ids(), classifiers, verbose=verbose)
        else:
            # Knowingly-leaky fast path: reuses the placeholder-rule columns
            # already in the CSV. QC only - never report a metric from this.
            classifiers, train_over, held_over = None, {}, {}

        X_train = train.matrix(feature_names, overrides=train_over)
        X_held = held.matrix(feature_names, overrides=held_over)
        y_train, y_held = train.grades(), held.grades()

        # --- step 3: z-score on TRAIN rows only -----------------------------
        scaler = models.ZScore().fit(X_train)
        X_train, X_held = scaler.transform(X_train), scaler.transform(X_held)

        # --- step 4: train the network ---------------------------------------
        weights, _rounded = models.class_weights(y_train)
        if not models.weights_are_flat(weights) and verbose:
            print(f"    WARNING: class weights {np.round(weights, 2).tolist()} are outside "
                  f"0.9-1.1; S6.2.2 then wants a custom weighted-MSE training loop, "
                  f"which sklearn's MLPRegressor cannot express (see models.fit_mlp). "
                  f"The MATLAB implementation applies them.")
        model = models.fit_mlp(X_train, y_train)

        # --- step 5: predict the held-out fold -------------------------------
        for id_code, score in zip(held.ids(), model.predict(X_held)):
            oof_score[id_code] = float(score)

        fold_artefacts.append({"fold": k, "model": model, "scaler": scaler,
                               "classifiers": classifiers, "n_train": len(train),
                               "n_held": len(held)})

    ids = [r["id_code"] for r in dev.rows if r["id_code"] in oof_score]
    oof = np.array([oof_score[i] for i in ids])
    subset = dev.subset(ids)
    return {"ids": ids, "scores": oof, "grades": subset.grades(),
            "resolutions": subset.resolutions(), "dataset": subset,
            "folds": fold_artefacts}


def fit_decision_rules(oof, calibration_method="platt", verbose=True):
    """S7.2 + S6.2 + S6.4, all fitted on OUT-OF-FOLD predictions and then
    FROZEN before the test set is touched."""
    scores, grades = oof["scores"], oof["grades"]
    referable = (grades >= metrics.REFERABLE_GRADE).astype(int)

    cutpoints = cut.fit_cutpoints(scores, grades)
    predicted = cut.apply_cutpoints(scores, cutpoints)

    point = metrics.operating_point(referable, scores)
    borderline, enhanced = oof["dataset"].confidence_flags()
    calibrator, raw, routed = calibration.calibrate_and_route(
        scores, referable, borderline, enhanced, method=calibration_method)

    ece_before, _ = metrics.expected_calibration_error(referable, _minmax(scores))
    ece_after, diagram = metrics.expected_calibration_error(referable, raw)

    if verbose:
        print(f"  cutpoints:        {np.round(cutpoints, 3).tolist()}")
        print(f"  operating point:  threshold {point['threshold']:.4f} -> "
              f"sens {point['sensitivity']:.3f}, spec {point['specificity']:.3f}"
              f"{'' if point['reached_target'] else '   (TARGET 0.90 NOT REACHED)'}")
        print(f"  ECE:              {ece_before:.4f} raw -> {ece_after:.4f} calibrated")

    return {"cutpoints": cutpoints, "operating_point": point, "calibrator": calibrator,
            "calibration_method": calibration_method, "ece_before": ece_before,
            "ece_after": ece_after, "reliability": diagram,
            "oof_report": metrics.summarise(grades, predicted, scores,
                                            oof["resolutions"], point["threshold"])}


def evaluate_test(dataset, candidate_loader, feature_names, rules,
                  refit_lesions=True, verbose=True):
    """S6.1's final step and S8's Phase 8: retrain on ALL 425 dev rows, then
    evaluate the 75 test rows exactly once with the frozen cutpoints and
    threshold.

    The lesion classifiers are refitted on the dev rows only - no lesion
    classifier may ever touch a test image (S4.1).
    """
    dev, test = dataset.dev(), dataset.test()
    if len(test) == 0:
        raise ValueError("no test rows - check the split column")
    grades = {r["id_code"]: r["diagnosis"] for r in dataset.rows}

    if refit_lesions:
        classifiers = fit_fold_classifiers(candidate_loader, dev.ids(), grades, verbose=verbose)
        dev_over, _ = recompute_lesion_columns(candidate_loader, dev.ids(), classifiers, verbose=verbose)
        test_over, _ = recompute_lesion_columns(candidate_loader, test.ids(), classifiers, verbose=verbose)
    else:
        classifiers, dev_over, test_over = None, {}, {}

    X_dev = dev.matrix(feature_names, overrides=dev_over)
    X_test = test.matrix(feature_names, overrides=test_over)
    y_dev, y_test = dev.grades(), test.grades()

    scaler = models.ZScore().fit(X_dev)
    X_dev, X_test = scaler.transform(X_dev), scaler.transform(X_test)

    model = models.fit_mlp(X_dev, y_dev)

    scores = model.predict(X_test)
    predicted = cut.apply_cutpoints(scores, rules["cutpoints"])
    referable = (y_test >= metrics.REFERABLE_GRADE).astype(int)

    report = metrics.summarise(y_test, predicted, scores, test.resolutions(),
                               rules["operating_point"]["threshold"])

    # S7.1: bootstrap CIs - 15 images per grade makes these wide, report them
    report["qwk_ci"] = metrics.bootstrap_ci(metrics.quadratic_weighted_kappa, y_test, predicted)
    report["referable_auc_ci"] = metrics.bootstrap_ci(metrics.roc_auc, referable, scores)

    # S6.4: DME overrides the grade
    probabilities = rules["calibrator"].predict(scores)
    borderline, enhanced = test.confidence_flags()
    report["confidence"] = calibration.apply_confidence_routing(
        probabilities, borderline, enhanced).tolist()
    decision = scores >= rules["operating_point"]["threshold"]
    final, urgent = calibration.apply_dme_override(decision, test.dme_flags(test_over))
    report["dme_overrides"] = int(urgent.sum())
    report["referred_after_override"] = int(final.sum())
    return report


def run_ablation(dataset, candidate_loader, refit_lesions=True, verbose=True):
    """S8 Phase 6: add the feature blocks in order, keeping a block only if
    WITHIN-RESOLUTION out-of-fold QWK improves (S4.3 - the pooled figure partly
    measures the camera, so it must not be the deciding number)."""
    table, previous = [], None
    for name, _block in col.PHASE6_BLOCKS:
        feature_names = col.blocks_through(name)
        if verbose:
            print(f"\n[{name}] {len(feature_names)} features")
        oof = run_cross_validation(dataset, candidate_loader, feature_names,
                                   refit_lesions=refit_lesions, verbose=False)
        cutpoints = cut.fit_cutpoints(oof["scores"], oof["grades"])
        predicted = cut.apply_cutpoints(oof["scores"], cutpoints)
        within = metrics.within_resolution(metrics.quadratic_weighted_kappa,
                                           oof["resolutions"], oof["grades"], predicted)
        pooled = metrics.quadratic_weighted_kappa(oof["grades"], predicted)
        delta = None if previous is None else within["mean"] - previous
        keep = previous is None or (delta is not None and delta > 0)
        table.append({"block": name, "n_features": len(feature_names),
                      "qwk_pooled": pooled, "qwk_within": within["mean"],
                      "delta_within": delta, "keep": keep})
        if verbose:
            arrow = "" if delta is None else f"  (within {delta:+.4f}  ->  {'KEEP' if keep else 'DROP'})"
            print(f"  QWK pooled {pooled:.4f} | within resolution {within['mean']:.4f}{arrow}")
        previous = within["mean"] if keep else previous
    return table


def _minmax(values):
    values = np.asarray(values, dtype=np.float64)
    lo, hi = values.min(), values.max()
    return (values - lo) / max(hi - lo, 1e-9)

"""Stage 3 runner: Module3_Plan.md Phases 4-8.

    # Phase 5 - train the grading network, lesion classifiers refitted per fold
    python final_algorithms/python/run_module3.py

    # Phase 6 - feature-block ablation
    python final_algorithms/python/run_module3.py --ablation

    # Phases 7-8 - freeze the rules, then touch the test set ONCE
    python final_algorithms/python/run_module3.py --test

The model is the S6.2 ordinal-regression MLP. The RandomForest baseline of
S6.3/D4 has been REMOVED at the project owner's instruction - Module 3 grading
is neural-network only - so Phase 5's numbers have no baseline to be compared
against (see stage3/models.py).

Reads data/module3_dataset.csv and data/module3_candidates/*.pkl, both written
by extract_module3_features.py (Phase 2). Writes a JSON report to
data/module3_report_mlp.json.

The test set is evaluated only with --test, and only after the cutpoints,
calibration and operating point have been fitted on out-of-fold dev
predictions (S7.2). Choosing any of them on the test set is the most common
accidental cheat in this field.
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from stage3 import columns as col          # noqa: E402
from stage3.dataset import Module3Dataset  # noqa: E402
from stage3.fold_features import CandidateCache  # noqa: E402
from stage3 import pipeline                # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.join(REPO, "data"))
    ap.add_argument("--block", default="6a_measured_core",
                    help="Phase 6 block to run through (D5 starts at 6a)")
    ap.add_argument("--all-features", action="store_true",
                    help="use all 38 model inputs instead of a Phase 6 block (D5 advises against)")
    ap.add_argument("--ablation", action="store_true", help="Phase 6: walk every block in order")
    ap.add_argument("--test", action="store_true",
                    help="Phase 8: evaluate the held-out test set ONCE (S7.2)")
    ap.add_argument("--calibration", choices=["platt", "isotonic"], default="platt")
    ap.add_argument("--no-refit-lesions", action="store_true",
                    help="LEAKY. Reuse the placeholder-rule lesion columns instead of refitting "
                         "per fold. QC smoke runs only - never report a metric from this (S4.1)")
    args = ap.parse_args()

    dataset_path = os.path.join(args.data, "module3_dataset.csv")
    if not os.path.isfile(dataset_path):
        sys.exit(f"{dataset_path} not found - run the Phase 2 extraction first")
    dataset = Module3Dataset.from_csv(dataset_path)
    cache = CandidateCache(os.path.join(args.data, "module3_candidates"))

    refit = not args.no_refit_lesions
    if not refit:
        print("WARNING: --no-refit-lesions is LEAKY by construction (S4.1). QC only.\n")

    print(f"rows: {len(dataset)}  (dev {len(dataset.dev())}, test {len(dataset.test())})")
    cached = cache.available(dataset.ids())
    print(f"cached candidates: {len(cached)}/{len(dataset)}")
    if refit and len(cached) < len(dataset):
        print("  NOTE: ids without a cache keep their placeholder-rule lesion columns")

    if args.ablation:
        print("\n=== Phase 6: feature-block ablation ===")
        table = pipeline.run_ablation(dataset, cache, refit_lesions=refit)
        _write(args, {"phase": 6, "model": "mlp", "ablation": table})
        return

    feature_names = col.all_model_inputs() if args.all_features else col.model_inputs(args.block)
    print(f"\nfeatures: {len(feature_names)} "
          f"({'all model inputs' if args.all_features else args.block})")

    print("\n=== Cross-validation (MLP) ===")
    oof = pipeline.run_cross_validation(dataset, cache, feature_names,
                                        refit_lesions=refit)

    print("\n=== Decision rules, fitted on out-of-fold predictions ===")
    rules = pipeline.fit_decision_rules(oof, calibration_method=args.calibration)

    report = {"phase": 8 if args.test else 5, "model": "mlp",
              "features": feature_names, "n_features": len(feature_names),
              "refit_lesions": refit,
              "cutpoints": rules["cutpoints"].tolist(),
              "operating_point": rules["operating_point"],
              "ece_before": rules["ece_before"], "ece_after": rules["ece_after"],
              "out_of_fold": rules["oof_report"]}

    _print_report("out-of-fold (425 dev rows)", rules["oof_report"])

    if args.test:
        print("\n=== Phase 8: the held-out test set, evaluated ONCE ===")
        test_report = pipeline.evaluate_test(dataset, cache, feature_names, rules,
                                             refit_lesions=refit)
        report["test"] = test_report
        _print_report("test (75 rows)", test_report)
        print(f"  DME overrides:    {test_report['dme_overrides']} images referred "
              f"regardless of grade (S6.4)")

    _write(args, report)


def _print_report(title, report):
    print(f"\n--- {title} ---")
    print(f"  n                     {report['n']}")
    print(f"  QWK pooled            {report['qwk']:.4f}")
    within = report["qwk_within_resolution"]
    print(f"  QWK within resolution {within['mean']:.4f}   <- the honest number (S4.3)")
    for res, value in sorted(within["per_stratum"].items()):
        print(f"      {res:>12s} {value:.4f}")
    if within["skipped"]:
        print(f"      skipped (too few rows): {within['skipped']}")
    print(f"  referable AUC pooled  {report['referable_auc']:.4f}")
    print(f"  referable AUC within  {report['referable_auc_within_resolution']['mean']:.4f}")
    if "referable_sensitivity" in report:
        print(f"  referable sens/spec   {report['referable_sensitivity']:.3f} / "
              f"{report['referable_specificity']:.3f}")
    sens = report["per_class_sensitivity"]
    print("  per-class sensitivity " + "  ".join(
        f"g{c}={v:.2f}" if not np.isnan(v) else f"g{c}=--" for c, v in enumerate(sens)))
    print(f"  grade-4 recall        {report['grade4_recall']:.3f}   <- reported on its own line (S8)")
    if "qwk_ci" in report:
        ci = report["qwk_ci"]
        print(f"  QWK 95% CI            [{ci['lo']:.3f}, {ci['hi']:.3f}]")
    print("  confusion (rows = true grade):")
    for row in report["confusion"]:
        print("      " + "".join(f"{v:5d}" for v in row))


def _write(args, report):
    path = os.path.join(args.data, "module3_report_mlp.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, default=float)
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()

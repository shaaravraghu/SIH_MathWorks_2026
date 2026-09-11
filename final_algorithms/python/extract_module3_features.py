"""Batch Module 3 feature extraction over APTOS (Module3_Plan.md §5.2, Phase 2).

Writes, and never overwrites data/aptos_train_module1_features.csv:
  data/module3_stage1_features.csv   id_code + S1-01 .. S1-21
  data/module3_stage2_features.csv   id_code + S2-01 .. S2-45
  data/module3_dataset.csv           join on id_code, plus the §2.3 columns
  data/module3_candidates/<id>.pkl   Stage 2 candidates, no classifier applied

The lesion columns written here use the PLACEHOLDER classifier rule and are for
QC only. Module 3 must refit every lesion classifier inside each CV fold from the
cached candidates and score only the held-out fold (§4.1, §6.1). Training on these
counts leaks the grade into the features, which has already happened once.

Images Stage 1 rejects get a Stage 1 row (for the §4.4 per-grade rejection tally)
but no Stage 2 row and no dataset row: they never reach Module 3.

Usage:
  python final_algorithms/python/extract_module3_features.py --ids data/module3_ids.txt \
      --splits data/module3_splits.csv
"""

import argparse
import csv
import os
import pickle
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from stage1 import STAGE1_COLUMNS, extract_stage1_features  # noqa: E402
from stage1.pipeline import load_rgb  # noqa: E402
from stage2.features import (STAGE2_COLUMNS, extract_stage2_candidates,  # noqa: E402
                             stage2_features_from_candidates)

REPO = os.path.dirname(os.path.dirname(HERE))

# §2.3: carried in the CSV, never used as features. `resolution` is for
# stratification only; the network must never see it.
DATASET_COLUMNS = ["id_code", "diagnosis", "split", "cv_fold", "resolution", "sample_source"]


def read_labels(train_csv):
    with open(train_csv, newline="") as f:
        return {r["id_code"]: r["diagnosis"] for r in csv.DictReader(f)}


def read_ids(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def read_splits(path):
    if not path:
        return {}
    with open(path, newline="") as f:
        return {r["id_code"]: r for r in csv.DictReader(f)}


def open_writer(path, columns):
    f = open(path, "w", newline="")
    writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    return f, writer


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aptos", default=os.path.join(REPO, "aptos2019-blindness-detection"))
    ap.add_argument("--out", default=os.path.join(REPO, "data"))
    ap.add_argument("--ids", help="one id_code per line; default: data/module3_ids.txt if present, else all of train.csv")
    ap.add_argument("--splits", help="Phase 1 CSV with id_code, split, cv_fold, sample_source")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    # Phase 1 worklist (S5.1, S5.3). Default to the 500-image pilot sample when
    # it is present, so a bare run extracts the grade-balanced pilot set rather
    # than silently sweeping all 3,662 APTOS training images. Regenerate the
    # list with final_algorithms/python/select_module3_ids.py.
    if not args.ids:
        default_ids = os.path.join(args.out, "module3_ids.txt")
        if os.path.isfile(default_ids):
            args.ids = default_ids
    if not args.splits:
        default_splits = os.path.join(args.out, "module3_splits.csv")
        if os.path.isfile(default_splits):
            args.splits = default_splits

    labels = read_labels(os.path.join(args.aptos, "train.csv"))
    if args.ids:
        ids = read_ids(args.ids)
        print(f"worklist: {args.ids} ({len(ids)} images)")
    else:
        ids = list(labels)
        print(f"WARNING: no ids file - extracting ALL {len(ids)} images in train.csv, not the "
              f"500-image pilot sample. Run select_module3_ids.py first.")
    splits = read_splits(args.splits)
    if args.splits:
        print(f"splits:   {args.splits}")

    cache_dir = os.path.join(args.out, "module3_candidates")
    os.makedirs(cache_dir, exist_ok=True)

    f1, w1 = open_writer(os.path.join(args.out, "module3_stage1_features.csv"), ["id_code"] + STAGE1_COLUMNS)
    f2, w2 = open_writer(os.path.join(args.out, "module3_stage2_features.csv"), ["id_code"] + STAGE2_COLUMNS)
    f3, w3 = open_writer(os.path.join(args.out, "module3_dataset.csv"),
                         DATASET_COLUMNS + STAGE1_COLUMNS + STAGE2_COLUMNS)

    rejected_by_grade = {}
    try:
        for i, id_code in enumerate(ids, start=1):
            t0 = time.time()
            path = os.path.join(args.aptos, "train_images", id_code + ".png")
            try:
                image = load_rgb(path)
                s1 = extract_stage1_features(image, seed=args.seed)
                stage1_out = s1.pop("_stage1")
                w1.writerow({"id_code": id_code, **s1})
                f1.flush()

                if s1["stage1_verdict"] == "fail":
                    grade = labels.get(id_code, "?")
                    rejected_by_grade[grade] = rejected_by_grade.get(grade, 0) + 1
                    print(f"[{i}/{len(ids)}] {id_code} rejected by Stage 1")
                    continue

                candidates = extract_stage2_candidates(stage1_out["image"], stage1_out["fov_mask"])
                with open(os.path.join(cache_dir, id_code + ".pkl"), "wb") as fc:
                    pickle.dump(candidates, fc)
                s2 = stage2_features_from_candidates(candidates)
                w2.writerow({"id_code": id_code, **s2})
                f2.flush()

                height, width = image.shape[:2]
                split = splits.get(id_code, {})
                w3.writerow({
                    "id_code": id_code,
                    "diagnosis": labels.get(id_code, ""),
                    "split": split.get("split", ""),
                    "cv_fold": split.get("cv_fold", ""),
                    "resolution": f"{width}x{height}",
                    "sample_source": split.get("sample_source", ""),
                    **s1, **s2,
                })
                f3.flush()
                print(f"[{i}/{len(ids)}] {id_code} ok ({time.time() - t0:.1f}s)")
            except Exception as exc:  # one bad image must not stop a 500-image run
                print(f"[{i}/{len(ids)}] {id_code} ERROR {exc!r}", file=sys.stderr)
    finally:
        for f in (f1, f2, f3):
            f.close()

    print("Stage 1 rejections by grade (§4.4):", dict(sorted(rejected_by_grade.items())))


if __name__ == "__main__":
    main()

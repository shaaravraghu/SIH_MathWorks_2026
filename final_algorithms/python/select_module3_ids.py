"""Module 3 Phase 1: choose the 500-image pilot sample and assign splits/folds
(Module3_Plan.md S5.1, S5.3).

Writes the worklist the Stage 1 + Stage 2 extraction consumes:

    data/module3_ids.txt        the 500 id_codes, one per line
    data/module3_splits.csv     id_code, split, cv_fold, sample_source, grade, resolution
    data/module3_reserve.csv    seeded backfill list, used when Stage 1 rejects a pick

This step picks FILENAMES only - it computes no features, so running it in
Python does not affect the MATLAB feature values at all. The MATLAB batch run
consumes the id list:

    extractModule3Features(IdsFile="data/module3_ids.txt", ...
                           SplitsFile="data/module3_splits.csv")

INPUTS (both already in data/, no images needed):
  data/aptos_train_module1_features.csv   all 3,662 APTOS train ids, grade,
                                          width/height, and the previous
                                          implementation's sharpness metrics
  data/aptos_train_module2_features.csv   the 309 already-extracted ids

WHY THE SHARPNESS COLUMNS ARE THE OLD ONES. S5.1 draws the new ids "across
sharpness deciles" only to spread the sample over the focus range; the values
are used as a RANKING, never as a gate verdict or a feature. The finalized
Stage 1 has not been run over the full 3,662, so its verdicts do not exist yet
(see the gate caveat below).

THE STAGE 1 GATE CAVEAT. S5.1 quotes a gate-passed pool (1737/346/876/169/257)
that CANNOT be reproduced from these CSVs: `sharp_ok` is populated for only the
309 already-extracted rows, never for the other 3,353. So a pick here may still
be rejected by Stage 1 at extraction time. That is what module3_reserve.csv is
for: after extraction, replace any rejected id with the next reserve of the same
grade and re-run those ids. Grade 3 has the least slack (193 total ids).
"""

import argparse
import csv
import os
import random

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TARGET_PER_GRADE = 100   # S5.1: 100 per grade, balanced
TEST_PER_GRADE = 15      # S5.3: 75 test rows, 15 per grade
N_FOLDS = 5              # S5.3: 5-fold CV over the 425 dev rows
RESERVE_PER_GRADE = 40   # backfill depth for Stage-1-rejected picks
N_DECILES = 10           # S5.1: "across sharpness deciles"
GRADES = ["0", "1", "2", "3", "4"]

# S4.1 pins the split of the existing 309: the microaneurysm classifier was
# trained on 250 of them, and "the 59 unseen microaneurysm rows are the
# sharpest images". 250 + 59 = 309. No provenance column survives, so the 59
# are RECONSTRUCTED here as the 59 sharpest of the 309 by SHARPNESS_COLUMN.
# Documented inference, not a recovered record - flagged for review.
N_SHARPEST70 = 59
SHARPNESS_COLUMN = "varLapNorm"   # the previous implementation's primary focus metric


def read_rows(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def decile_stratified_draw(pool, n_wanted, rng):
    """Split `pool` (sorted by sharpness) into N_DECILES equal bands and draw
    round-robin across them, so the picks span the focus range instead of
    clustering in it (S5.1)."""
    if n_wanted <= 0:
        return [], list(pool)
    bands = [[] for _ in range(N_DECILES)]
    for i, row in enumerate(pool):
        bands[min(i * N_DECILES // max(len(pool), 1), N_DECILES - 1)].append(row)
    for band in bands:
        rng.shuffle(band)

    picked, band_idx = [], 0
    while len(picked) < n_wanted and any(bands):
        band = bands[band_idx % N_DECILES]
        if band:
            picked.append(band.pop())
        band_idx += 1
    chosen = {r["id_code"] for r in picked}
    return picked, [r for r in pool if r["id_code"] not in chosen]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.join(REPO, "data"))
    ap.add_argument("--seed", type=int, default=0, help="S5.1: fixed random seed")
    args = ap.parse_args()

    m1 = read_rows(os.path.join(args.data, "aptos_train_module1_features.csv"))
    m2 = read_rows(os.path.join(args.data, "aptos_train_module2_features.csv"))
    existing_ids = {r["id_code"] for r in m2}

    # Usable = has a grade, a sharpness value to rank on, and passed the FOV
    # gate. This is the only gate these CSVs can apply (see module docstring).
    usable = []
    for r in m1:
        sharp = to_float(r.get(SHARPNESS_COLUMN, ""))
        if r["diagnosis"] not in GRADES or sharp is None:
            continue
        if r.get("fov_ok", "1").strip() == "0":
            continue
        width, height = to_float(r.get("width")), to_float(r.get("height"))
        r["_sharp"] = sharp
        r["_resolution"] = f"{int(width)}x{int(height)}" if width and height else ""
        usable.append(r)

    dropped = len(m1) - len(usable)
    print(f"usable ids: {len(usable)} of {len(m1)}  (dropped {dropped}: missing grade/sharpness, or fov_ok=0)")

    # --- reconstruct sample_source for the existing 309 ----------------------
    existing_rows = [r for r in usable if r["id_code"] in existing_ids]
    by_sharp = sorted(existing_rows, key=lambda r: r["_sharp"], reverse=True)
    sharpest70 = {r["id_code"] for r in by_sharp[:N_SHARPEST70]}

    def source_tag(id_code):
        if id_code not in existing_ids:
            return "new"
        return "sharpest70" if id_code in sharpest70 else "gate_sample"

    rng = random.Random(args.seed)
    selected, reserve = [], []

    print("\nper-grade selection:")
    for grade in GRADES:
        in_grade = [r for r in usable if r["diagnosis"] == grade]
        keep = [r for r in in_grade if r["id_code"] in existing_ids]   # D3: keep and tag
        fresh = sorted((r for r in in_grade if r["id_code"] not in existing_ids),
                       key=lambda r: r["_sharp"])

        n_needed = max(TARGET_PER_GRADE - len(keep), 0)
        drawn, leftover = decile_stratified_draw(fresh, n_needed, rng)
        chosen = keep + drawn

        short = TARGET_PER_GRADE - len(chosen)
        flag = f"  SHORT BY {short}" if short > 0 else ""
        print(f"  grade {grade}: pool {len(in_grade):5d} | keep {len(keep):3d} "
              f"+ draw {len(drawn):3d} = {len(chosen):3d}{flag}")

        selected.extend(chosen)
        res_drawn, _ = decile_stratified_draw(leftover, RESERVE_PER_GRADE, rng)
        reserve.extend(res_drawn)

    # --- splits and folds (S5.3), stratified by grade ------------------------
    assignment = {}
    for grade in GRADES:
        rows = [r for r in selected if r["diagnosis"] == grade]
        rng.shuffle(rows)
        for i, row in enumerate(rows):
            if i < TEST_PER_GRADE:
                assignment[row["id_code"]] = ("test", "")
            else:
                fold = (i - TEST_PER_GRADE) % N_FOLDS
                assignment[row["id_code"]] = ("dev", str(fold))

    selected.sort(key=lambda r: (r["diagnosis"], r["id_code"]))

    ids_path = os.path.join(args.data, "module3_ids.txt")
    with open(ids_path, "w", encoding="utf-8") as fh:
        for row in selected:
            fh.write(row["id_code"] + "\n")

    splits_path = os.path.join(args.data, "module3_splits.csv")
    with open(splits_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["id_code", "split", "cv_fold", "sample_source", "grade", "resolution"])
        for row in selected:
            split, fold = assignment[row["id_code"]]
            writer.writerow([row["id_code"], split, fold, source_tag(row["id_code"]),
                             row["diagnosis"], row["_resolution"]])

    reserve_path = os.path.join(args.data, "module3_reserve.csv")
    with open(reserve_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["id_code", "grade", "resolution", "reserve_rank"])
        for grade in GRADES:
            ranked = [r for r in reserve if r["diagnosis"] == grade]
            for rank, row in enumerate(ranked, start=1):
                writer.writerow([row["id_code"], grade, row["_resolution"], rank])

    # --- report --------------------------------------------------------------
    print(f"\nwrote {ids_path}  ({len(selected)} ids)")
    print(f"wrote {splits_path}")
    print(f"wrote {reserve_path}  ({len(reserve)} backfill ids)")

    counts = {}
    for row in selected:
        split, _ = assignment[row["id_code"]]
        counts.setdefault(row["diagnosis"], {}).setdefault(split, 0)
        counts[row["diagnosis"]][split] += 1
    print("\nsplit by grade (S5.3 target: 15 test / 85 dev per grade):")
    for grade in GRADES:
        c = counts.get(grade, {})
        print(f"  grade {grade}: test {c.get('test', 0):3d} | dev {c.get('dev', 0):3d}")

    tags = {}
    for row in selected:
        tags[source_tag(row["id_code"])] = tags.get(source_tag(row["id_code"]), 0) + 1
    print(f"\nsample_source: {tags}")

    # S5.3: "Check that the resolution mix is similar across test and the dev
    # folds. If one camera sits mostly in test, the test result measures the
    # camera."
    res_split = {}
    for row in selected:
        split, _ = assignment[row["id_code"]]
        res_split.setdefault(row["_resolution"], {"test": 0, "dev": 0})[split] += 1
    print("\nresolution mix (S5.3 check - test share should track 15%):")
    for res, c in sorted(res_split.items(), key=lambda kv: -(kv[1]["test"] + kv[1]["dev"])):
        total = c["test"] + c["dev"]
        print(f"  {res:>12s}  test {c['test']:3d} | dev {c['dev']:3d} | "
              f"test share {100.0 * c['test'] / max(total, 1):5.1f}%")


if __name__ == "__main__":
    main()

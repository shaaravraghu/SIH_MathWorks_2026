"""Loads the Module 3 feature table and exposes the S5.3 splits/folds and the
S4.3 resolution strata.

The table is data/module3_dataset.csv, written by extract_module3_features.py
(Phase 2). Its lesion columns came from the PLACEHOLDER classifier and are QC
only - Stage 3 recomputes them per fold from the cached candidates
(see fold_features.py). Loading them here is deliberate: they are what the
Phase 3 QC report measures, and they are what `--no-refit` reuses when you
want a fast, knowingly-leaky smoke run.
"""

import csv
import math

import numpy as np

from . import columns as col


class Module3Dataset:
    def __init__(self, rows):
        self.rows = rows

    # --- construction --------------------------------------------------------

    @classmethod
    def from_csv(cls, path):
        with open(path, newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        if not rows:
            raise ValueError(f"{path} has no rows - run Phase 2 extraction first")
        for r in rows:
            r["diagnosis"] = int(float(r["diagnosis"]))
        return cls(rows)

    # --- selection -----------------------------------------------------------

    def subset(self, ids):
        wanted = set(ids)
        return Module3Dataset([r for r in self.rows if r["id_code"] in wanted])

    def ids(self):
        return [r["id_code"] for r in self.rows]

    def dev(self):
        return Module3Dataset([r for r in self.rows if r.get("split") == "dev"])

    def test(self):
        return Module3Dataset([r for r in self.rows if r.get("split") == "test"])

    def fold(self, k):
        return Module3Dataset([r for r in self.rows if str(r.get("cv_fold")) == str(k)])

    def not_fold(self, k):
        return Module3Dataset([r for r in self.rows
                               if r.get("split") == "dev" and str(r.get("cv_fold")) != str(k)])

    def folds(self):
        return sorted({str(r["cv_fold"]) for r in self.rows
                       if r.get("split") == "dev" and str(r.get("cv_fold")).strip() != ""})

    # --- matrices ------------------------------------------------------------

    def matrix(self, feature_names, overrides=None):
        """Feature matrix in `feature_names` order. `overrides` is an optional
        {id_code: {column: value}} map used to substitute the per-fold
        recomputed lesion columns (S6.1 step 2) without mutating the table."""
        overrides = overrides or {}
        out = np.zeros((len(self.rows), len(feature_names)), dtype=np.float64)
        for i, r in enumerate(self.rows):
            over = overrides.get(r["id_code"], {})
            for j, name in enumerate(feature_names):
                value = over[name] if name in over else r.get(name, "")
                out[i, j] = _to_float(value)
        return out

    def grades(self):
        return np.array([r["diagnosis"] for r in self.rows], dtype=np.float64)

    def referable(self):
        """S6.4: referable = grade >= 2."""
        return (self.grades() >= col.REFERABLE_THRESHOLD_GRADE).astype(int)

    def resolutions(self):
        """S4.3: every metric must also be reported within resolution strata."""
        return [r.get("resolution", "") for r in self.rows]

    def confidence_flags(self):
        """S6.4: (borderline, enhanced) per row, for confidence routing.
        These are CONF columns - never model inputs (D7)."""
        borderline, enhanced = [], []
        for r in self.rows:
            borderline.append(str(r.get("stage1_verdict", "")).strip().lower() == "borderline")
            enhanced.append(_to_float(r.get("enhancement_applied", 0)) > 0)
        return np.array(borderline), np.array(enhanced)

    def dme_flags(self, overrides=None):
        """S6.4: dme_flag OVERRIDES the grade - urgent referral regardless."""
        overrides = overrides or {}
        out = []
        for r in self.rows:
            over = overrides.get(r["id_code"], {})
            value = over.get(col.DME_OVERRIDE_COLUMN, r.get(col.DME_OVERRIDE_COLUMN, 0))
            out.append(_to_float(value) > 0)
        return np.array(out)

    def __len__(self):
        return len(self.rows)


def _to_float(value):
    if isinstance(value, (int, float)):
        return float(value) if not (isinstance(value, float) and math.isnan(value)) else 0.0
    text = str(value).strip()
    if text == "":
        return 0.0
    # Stage 1's verdict column is categorical; map it rather than crashing, so a
    # caller that accidentally requests it gets a number instead of an exception.
    if text.lower() in ("pass", "false", "no"):
        return 0.0
    if text.lower() in ("borderline", "true", "yes"):
        return 1.0
    if text.lower() == "fail":
        return 2.0
    try:
        value = float(text)
    except ValueError:
        return 0.0
    return 0.0 if math.isnan(value) or math.isinf(value) else value

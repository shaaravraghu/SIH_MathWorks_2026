"""S6.1 step 2: re-derive the classifier-dependent Stage 2 columns for every
image in a fold, using that fold's freshly-fitted lesion classifiers.

Only the ~20 lesion columns in columns.CLASSIFIER_DEPENDENT_COLUMNS change
between folds. Everything else in the Stage 2 row (vessels, calibre, NV, OD,
fovea) is classifier-free and identical across folds, which is exactly why
extract_stage2_candidates caches it once per image (S4.1).

The cache lives in data/module3_candidates/<id>.pkl (Python) or .mat (MATLAB),
written by the Phase 2 extraction run.
"""

import os
import pickle
import sys

from . import columns as col


def _stage2_features():
    """Imports stage2.features LAZILY, on first use.

    stage2 and stage3 are sibling top-level packages under
    final_algorithms/python (the layout extract_module3_features.py assumes),
    so this is an absolute import with the parent directory put on the path.

    It is deferred rather than done at module import because stage2 pulls in
    OpenCV, and Stage 3's metrics, cutpoints, calibration and model code need
    none of it. Only recompute_lesion_columns() actually re-derives Stage 2
    rows, so only that path requires opencv to be installed.
    """
    parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if parent not in sys.path:
        sys.path.insert(0, parent)
    try:
        from stage2 import features
    except ImportError as err:  # pragma: no cover - environment-dependent
        raise ImportError(
            "Recomputing lesion columns per fold needs stage2, which needs OpenCV "
            "(pip install opencv-python). Metrics-only use of stage3 does not."
        ) from err
    return features


class CandidateCache:
    """Lazily loads and memoises cached Stage2Candidates objects. One image's
    candidates are read once and reused across all five folds."""

    def __init__(self, cache_dir, max_cached=None):
        self.cache_dir = cache_dir
        self.max_cached = max_cached
        self._store = {}
        self.misses = []

    def __call__(self, id_code):
        if id_code in self._store:
            return self._store[id_code]
        path = os.path.join(self.cache_dir, f"{id_code}.pkl")
        if not os.path.isfile(path):
            if id_code not in self.misses:
                self.misses.append(id_code)
            return None
        with open(path, "rb") as fh:
            candidates = pickle.load(fh)
        if self.max_cached is None or len(self._store) < self.max_cached:
            self._store[id_code] = candidates
        return candidates

    def available(self, ids):
        return [i for i in ids if os.path.isfile(os.path.join(self.cache_dir, f"{i}.pkl"))]


def recompute_lesion_columns(candidate_loader, ids, classifiers, verbose=False):
    """Scores `ids` with one fold's classifiers and returns
    {id_code: {column: value}} for the classifier-dependent columns only.

    The returned map is passed to Module3Dataset.matrix(overrides=...), which
    substitutes these values and leaves every classifier-free column as
    extracted. An id with no cached candidates is omitted, so its original
    (placeholder-rule) row survives - fold_report() counts those.
    """
    overrides, missing = {}, []
    stage2_features = None
    for id_code in ids:
        candidates = candidate_loader(id_code)
        if candidates is None:
            missing.append(id_code)
            continue
        if stage2_features is None:
            stage2_features = _stage2_features()
        row = stage2_features.stage2_features_from_candidates(candidates, classifiers=classifiers)
        overrides[id_code] = {c: row[c] for c in col.CLASSIFIER_DEPENDENT_COLUMNS if c in row}
    if verbose and missing:
        print(f"    WARNING: {len(missing)} ids had no cached candidates and kept "
              f"their placeholder-rule lesion columns")
    return overrides, missing

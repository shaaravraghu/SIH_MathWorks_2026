"""S6.1 step 1 + S4.1: fit the lesion candidate classifiers INSIDE one
cross-validation fold, on training rows only.

WHY THIS MODULE EXISTS AT ALL. Each lesion counter contains a classifier
trained on weak labels taken from the image grade (grade 0 vs grades 3-4). If
that classifier is fitted on an image and then scores the same image, the
lesion count for that image already encodes its grade, and Module 3 learns the
answer rather than the disease. This has already happened once: the previous
implementation's microaneurysm classifier was trained on 250 images and all
250 sat inside the 309-row feature table (S4.1).

So: candidates are cached per image WITHOUT any classifier applied
(stage2.extract_stage2_candidates), and this module refits the keep/reject
step five times - once per fold - scoring only rows the fold's classifier
never trained on.

WEAK LABELS (S4.1). Positive = candidates from grade 3-4 images, negative =
candidates from grade 0 images. Grades 1 and 2 are DROPPED from classifier
training: they are the ambiguous middle, and the plan's weak-label definition
names only 0 against 3-4. Their images are still SCORED, just not trained on.

THRESHOLD SELECTION (S4.1, classifier.py). The criterion is fixed BEFORE
sweeping: "the lowest probability at which the grade-0 median count is 0".
Choosing a threshold to maximise a correlation and then reporting that
correlation is circular - the notes call this out explicitly.
"""

import numpy as np

from sklearn.ensemble import RandomForestClassifier

LESION_KEYS = ("ma", "haem", "hard_exudate", "cws")

WEAK_LABEL_NEGATIVE_GRADES = (0,)      # S4.1
WEAK_LABEL_POSITIVE_GRADES = (3, 4)    # S4.1

# RandomForest rather than a deeper model: candidate tables are small per fold
# and the forest is the plan's own baseline family (S6.3). Not tuned - the
# pilot's model comparison is at the IMAGE level, not here.
N_ESTIMATORS = 200
MIN_SAMPLES_LEAF = 5
RANDOM_STATE = 0

# Threshold sweep grid for the fixed criterion above.
THRESHOLD_GRID = np.round(np.arange(0.05, 0.96, 0.05), 2)
FALLBACK_THRESHOLD = 0.5   # classifier.py's THRESH_CLASSIFIER_KEEP_PROB

MIN_TRAINING_CANDIDATES = 30   # below this a fold's classifier is not fitted
MIN_MINORITY_CANDIDATES = 10   # ... nor if one class is near-absent


def build_weak_label_matrix(candidate_loader, train_ids, grades, lesion_key):
    """Stacks every candidate of every training image into one table with a
    weak label per candidate, inherited from its image's grade (S4.1).

    candidate_loader: callable id_code -> Stage2Candidates (see cache.py).
    grades: {id_code: int}.
    Returns (X, y, feature_names). Images at grades 1-2 contribute nothing.
    """
    features, labels, names = [], [], None
    for id_code in train_ids:
        grade = grades.get(id_code)
        if grade in WEAK_LABEL_NEGATIVE_GRADES:
            label = 0
        elif grade in WEAK_LABEL_POSITIVE_GRADES:
            label = 1
        else:
            continue   # grades 1-2: scored later, never trained on

        candidates = candidate_loader(id_code)
        if candidates is None:
            continue
        packed = candidates.lesion_candidates.get(lesion_key)
        if packed is None or len(packed["features"]) == 0:
            continue
        features.append(np.asarray(packed["features"], dtype=np.float64))
        labels.append(np.full(len(packed["features"]), label, dtype=int))
        names = names or list(packed["feature_names"])

    if not features:
        return np.zeros((0, 0)), np.zeros(0, dtype=int), names or []
    return np.vstack(features), np.concatenate(labels), names


def fit_one(candidate_loader, train_ids, grades, lesion_key):
    """Fits one lesion classifier on training rows only. Returns
    (model, threshold) or (None, FALLBACK_THRESHOLD) when there is not enough
    labelled candidate data, in which case stage2 falls back to its documented
    placeholder rule rather than silently skipping step 5."""
    X, y, _names = build_weak_label_matrix(candidate_loader, train_ids, grades, lesion_key)
    if len(y) < MIN_TRAINING_CANDIDATES or min(np.bincount(y, minlength=2)) < MIN_MINORITY_CANDIDATES:
        return None, FALLBACK_THRESHOLD

    model = RandomForestClassifier(
        n_estimators=N_ESTIMATORS, min_samples_leaf=MIN_SAMPLES_LEAF,
        class_weight="balanced", random_state=RANDOM_STATE, n_jobs=-1)
    model.fit(X, y)

    threshold = select_threshold(model, candidate_loader, train_ids, grades, lesion_key)
    return model, threshold


def select_threshold(model, candidate_loader, train_ids, grades, lesion_key):
    """S4.1's pre-declared criterion: the LOWEST probability at which the
    median per-image candidate count on GRADE-0 TRAINING images is 0.

    Computed on training images only - the held-out fold must not influence
    the threshold any more than it influences the weights. If no threshold in
    the grid achieves it, the strictest one is used and the caller should
    treat that lesion class as uncalibrated for this fold.
    """
    grade0_ids = [i for i in train_ids if grades.get(i) in WEAK_LABEL_NEGATIVE_GRADES]
    if not grade0_ids:
        return FALLBACK_THRESHOLD

    scores_per_image = []
    for id_code in grade0_ids:
        candidates = candidate_loader(id_code)
        if candidates is None:
            continue
        packed = candidates.lesion_candidates.get(lesion_key)
        if packed is None or len(packed["features"]) == 0:
            scores_per_image.append(np.zeros(0))
            continue
        scores_per_image.append(model.predict_proba(np.asarray(packed["features"]))[:, 1])

    if not scores_per_image:
        return FALLBACK_THRESHOLD

    for threshold in THRESHOLD_GRID:
        counts = [int((s >= threshold).sum()) for s in scores_per_image]
        if float(np.median(counts)) == 0.0:
            return float(threshold)
    return float(THRESHOLD_GRID[-1])


def fit_fold_classifiers(candidate_loader, train_ids, grades, keys=LESION_KEYS, verbose=True):
    """S6.1 step 1: every lesion classifier for one fold, fitted on TRAIN rows
    only. Returns a dict shaped for stage2.features.stage2_features_from_candidates:
    {"ma": (model, threshold), ...}. A key whose classifier could not be fitted
    maps to (None, FALLBACK_THRESHOLD) -> stage2's placeholder rule."""
    classifiers = {}
    for key in keys:
        model, threshold = fit_one(candidate_loader, train_ids, grades, key)
        classifiers[key] = (model, threshold)
        if verbose:
            state = "placeholder (too few labelled candidates)" if model is None \
                else f"fitted, keep>={threshold:.2f}"
            print(f"    lesion classifier {key:>13s}: {state}")
    return classifiers

"""S6.2 / S6.3: the two grading models, both trained as REGRESSION on the
ordinal grade and rounded later at fitted cutpoints (D6).

WHY REGRESSION, NOT 5-CLASS CLASSIFICATION (S6.2). Grades are ordered:
predicting 4 for a true 0 is far worse than predicting 1. A softmax over five
classes treats those errors as equally wrong. Regression + fitted cutpoints is
what the reference doc recommends and what most top APTOS solutions used.

WHY THE FOREST IS MANDATORY, NOT OPTIONAL (S6.3, D4). A neural network does
not automatically beat a tree model on 500 rows of tabular data. On the
previous implementation's 309 rows the forest won decisively WITHIN resolution
strata - referable AUC 0.879 vs the MLP's 0.813, QWK 0.779 vs 0.753 - even
though pooled AUC ranked them the other way round. Pooled AUC rewards learning
the camera (S4.3). The network is adopted only if it beats the forest on the
within-resolution metrics.

SIZE CHECK (S6.2.4). 38 inputs gives 1,793 trainable weights against ~340
training rows per fold, over five weights per example. Dropout, weight decay,
the decaying learning rate and early stopping are all REQUIRED here, not
optional extras.
"""

import numpy as np

from sklearn.ensemble import RandomForestRegressor
from sklearn.neural_network import MLPRegressor

RANDOM_STATE = 0

# --- S6.3 RandomForest baseline ---------------------------------------------
FOREST_N_ESTIMATORS = 500      # MATLAB equivalent: fitrensemble(..., Method="Bag")
FOREST_MIN_SAMPLES_LEAF = 3

# --- S6.2 MLP ----------------------------------------------------------------
MLP_HIDDEN = (32, 16)          # S6.2: two hidden layers, not one or three
MLP_DROPOUT = 0.3              # S6.2 (see the sklearn caveat below)
MLP_L2 = 1e-2                  # S6.2.2, justified by the S6.2.4 size check
MLP_LEARNING_RATE = 1e-3       # S6.2.2: Adam's usual default
MLP_BATCH_SIZE = 32            # S6.2.2: ~11 mini-batches per fold-epoch
MLP_MAX_EPOCHS = 200           # S6.2.2: an upper bound; early stopping ends it sooner
MLP_PATIENCE = 20              # S6.2.2
MLP_VALIDATION_FRACTION = 0.15  # inner validation split of the training folds (S6.1)


class ZScore:
    """S6.1 step 3: normalisation fitted on TRAINING rows only. Fitting it on
    the full table would leak the held-out fold's distribution into training."""

    def __init__(self):
        self.mean = None
        self.scale = None

    def fit(self, X):
        self.mean = X.mean(axis=0)
        scale = X.std(axis=0)
        # A constant column (e.g. dme_flag all-zero in a small fold) would
        # divide by zero; leave it at zero instead of producing inf.
        self.scale = np.where(scale > 1e-12, scale, 1.0)
        return self

    def transform(self, X):
        return (X - self.mean) / self.scale

    def fit_transform(self, X):
        return self.fit(X).transform(X)


def class_weights(grades):
    """S6.2.2: inverse-frequency weight per (rounded) grade, computed from the
    ACTUAL training-fold composition, normalised so the mean weight is 1.

        w_c = (N_train / 5) / n_c

    S6.2.2 also notes these land close to 1.0 for grade-stratified folds drawn
    from a 100-per-grade sample; weights_are_flat() below is the check it asks
    for before falling back to plain MSE.
    """
    grades = np.asarray(grades)
    rounded = np.clip(np.rint(grades).astype(int), 0, 4)
    counts = np.bincount(rounded, minlength=5).astype(np.float64)
    n_train = len(rounded)
    weights = np.ones(5, dtype=np.float64)
    for c in range(5):
        weights[c] = (n_train / 5.0) / counts[c] if counts[c] > 0 else 1.0
    return weights, rounded


def weights_are_flat(weights, low=0.9, high=1.1):
    """S6.2.2: 'use plain MSE only if they all fall within about 0.9-1.1'."""
    present = weights[(weights > 0)]
    return bool(np.all((present >= low) & (present <= high)))


def fit_forest(X, y, sample_weight=None):
    """S6.3's required baseline. MATLAB: fitrensemble(X, y, Method="Bag")."""
    model = RandomForestRegressor(
        n_estimators=FOREST_N_ESTIMATORS, min_samples_leaf=FOREST_MIN_SAMPLES_LEAF,
        random_state=RANDOM_STATE, n_jobs=-1)
    model.fit(X, y, sample_weight=sample_weight)
    return model


def fit_mlp(X, y, sample_weight=None):
    """S6.2's ordinal-regression MLP.

    TWO DOCUMENTED DEVIATIONS from S6.2, both forced by scikit-learn and both
    matched exactly in the MATLAB implementation instead:

    1. DROPOUT IS NOT AVAILABLE. sklearn's MLPRegressor has no dropout layer.
       Its `alpha` L2 penalty is the only regulariser, so MLP_L2 carries the
       regularisation that S6.2 splits between dropout 0.3 and weight decay
       1e-2. MATLAB's Deep Learning Toolbox implements S6.2 as written, with
       real dropoutLayer(0.3) - see matlab/stage3/fitGradingMlp.m. Expect the
       two to differ; the MATLAB one is the plan's architecture.
    2. PER-ROW CLASS WEIGHTS ARE NOT SUPPORTED. MLPRegressor.fit takes no
       sample_weight. S6.2.2 anticipates this and permits plain MSE when the
       weights are flat (0.9-1.1), which grade-stratified folds from a
       100-per-grade sample should give. The caller checks with
       weights_are_flat() and warns when they are not.

    He initialisation (S6.2.3) is also not selectable in sklearn; it uses
    Glorot throughout. MATLAB sets WeightsInitializer="he" as specified.
    """
    model = MLPRegressor(
        hidden_layer_sizes=MLP_HIDDEN, activation="relu", solver="adam",
        alpha=MLP_L2, batch_size=MLP_BATCH_SIZE,
        learning_rate_init=MLP_LEARNING_RATE, max_iter=MLP_MAX_EPOCHS,
        early_stopping=True, validation_fraction=MLP_VALIDATION_FRACTION,
        n_iter_no_change=MLP_PATIENCE, random_state=RANDOM_STATE)
    model.fit(X, y)
    return model


MODEL_BUILDERS = {"forest": fit_forest, "mlp": fit_mlp}

"""Stage 3: DR severity grading from the Stage 1 + Stage 2 feature table
(see notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md).

This is branch (b) of the reference doc's three grading branches - a
lesion-feature model, not an image CNN. No convolution happens here despite
the "CNN" in the note filenames; the model is a fully-connected network (an
MLP) over a tabular feature table.

    columns.py             which Stage 2 columns reach the model; Phase 6 blocks
    dataset.py             the feature table, splits, folds, resolution strata
    lesion_classifiers.py  S6.1 step 1: refit lesion classifiers per fold (S4.1)
    fold_features.py       S6.1 step 2: recompute lesion columns per fold
    models.py              the ordinal-regression MLP (S6.2); no forest baseline (see below)
    cutpoints.py           regression score -> 5-class grade, cutpoints fitted on dev
    calibration.py         Platt/isotonic, confidence routing, DME override (S6.4)
    metrics.py             QWK, per-class sensitivity, referable ROC, within-resolution
    pipeline.py            the S6.1 fold loop and the Phase 4-8 entry points

Two rules the plan will not bend on, both enforced in code rather than left to
the caller:

  * LESION CLASSIFIERS ARE REFITTED INSIDE EVERY FOLD (S4.1). Leakage has
    already happened once in this project.
  * EVERY METRIC IS ALSO REPORTED WITHIN RESOLUTION STRATA (S4.3). Pooled
    figures partly measure which camera took the picture.

One place the plan HAS been overridden, at the project owner's instruction:
grading is NEURAL-NETWORK ONLY. S6.3 and decision D4 make a RandomForest the
required baseline the network must beat within resolution strata; that baseline
has been removed. On the previous 309 rows the forest beat the MLP there (AUC
0.879 vs 0.813, QWK 0.779 vs 0.753), so Phase 5 now reports the network's
numbers with nothing to compare them against. The lesion CANDIDATE classifier
(lesion_classifiers.py) is a separate component and still uses a tree ensemble.
"""

from . import calibration, columns, cutpoints, dataset, fold_features
from . import lesion_classifiers, metrics, models, pipeline

__all__ = ["calibration", "columns", "cutpoints", "dataset", "fold_features",
           "lesion_classifiers", "metrics", "models", "pipeline"]

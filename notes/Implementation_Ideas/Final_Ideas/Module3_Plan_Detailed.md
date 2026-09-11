# Module 3 — DR Severity Grading: Pilot Plan (500 images)

**Scope.** Grade DR severity (ICDR 0–4) and the referable decision (grade ≥ 2)
with a **neural network trained on tabular features**. The features come from the
finalized [`Stage_1_CNN`](Stage_1_CNN) and [`Stage_2_CNN`](Stage_2_CNN)
algorithms, combined into one CSV. Pilot size: **500 APTOS images**.

**What this is, in the terms of /the reference doc.**
[DR_Pipeline_Techniques_and_Datasets.md](../napolean/docs/DR_Pipeline_Techniques_and_Datasets.md)
describes three grading branches: (a) an end-to-end image CNN, (b) a
lesion-feature classifier, and (c) fusion of the two. **This plan is branch (b)**,
built as a multilayer perceptron (MLP) rather than a tree model. The image CNN,
branch (a), is a separate piece of work. Fusion needs both.

> The folder calls these stages "CNN", but no convolution happens here. The
> model is a fully-connected network over a feature table.

**Status of the evidence.** The numbers below were measured on the **309 images**
already extracted with the *previous* Module 2 implementation. Where the finalized
algorithm matches that implementation, the evidence carries over. Where the
finalized algorithm is new, the feature is marked **unmeasured**. Nothing here
has been measured on the finalized algorithms yet, because they are not
implemented.

---

## 1. How many features

| | Count |
|---|---|
| Features emitted by finalized Stage 1 | **21** |
| Features emitted by finalized Stage 2 | **40** |
| **Total emitted** | **61** |
| Excluded as model inputs (camera confound, coordinates) | 8 |
| Quality-control / gating / confidence only | 20 |
| **Model inputs available from the finalized design** | **33** |
| &nbsp;&nbsp;— with a measured equivalent in the previous implementation | 12 |
| &nbsp;&nbsp;— new in the finalized design, unmeasured | 21 |
| Recommended addition: microaneurysm block (see §3) | +5 |
| **Model inputs if the recommendation is accepted** | **38** |

**Stage 1 contributes no model inputs.** Its outputs decide whether an image is
graded at all, and how far to trust the grade. They do not decide the grade itself.
§2.1 has the measurements behind this.

---

## 2. Feature catalogue

**Role legend**

| Role | Meaning |
|---|---|
| **MODEL** | input to the grading network |
| **QC** | quality control or gating; stored and checked, not fed to the network |
| **CONF** | confidence modifier; used to route the image, not fed to the network |
| **EXCLUDE** | never fed to the network — it identifies the camera or is a raw coordinate |

**Evidence legend.** "within ρ" is the rank correlation with grade, computed
**inside one image resolution at a time** and then averaged across resolutions.
The camera cannot help inside a single resolution, so this is the honest measure.
Figures come from the previous implementation (n = 309, 5 resolution strata).

### 2.1 Stage 1 — 21 features, 0 model inputs

| ID | Feature | Stage 1 § | Role | Evidence / reason |
|---|---|---|---|---|
| S1-01 | `megapixels` | #1 | EXCLUDE | Resolution alone predicts referable DR at AUC **0.809**. The gate stays as written; the value must not reach the network. |
| S1-02 | `aspect_ratio` | #2.2 | EXCLUDE | A property of the camera and the crop |
| S1-03 | `area_ratio_s1` | #2.1 | QC | Capture geometry, not disease |
| S1-04 | `area_ratio_s2` | #2.1 | QC | Capture geometry, not disease |
| S1-05 | `black_region_pct` | #2.2 | EXCLUDE | Crop style differs even at the same aspect ratio: medians of 17.5% and 52.7% at aspects 1.32 and 1.33 |
| S1-06 | `varLapNorm` | #3.1 | QC | within ρ **+0.043** |
| S1-07 | `specSlope` | #3.1 | QC | within ρ +0.093, same sign in only 3 of 5 strata |
| S1-08 | `brenner` | #3.2 | QC | within ρ +0.092 |
| S1-09 | `tenengradVar` | #3.3 | EXCLUDE | pooled ρ +0.352 but within ρ **+0.024**: the apparent correlation is the camera |
| S1-10 | `regionMin` | #3.4 | QC | within ρ **+0.002** |
| S1-11 | `region_centre` | #3.4 | QC | within ρ between −0.08 and +0.09 across the five regions |
| S1-12 | `region_q1` | #3.4 | QC | same |
| S1-13 | `region_q2` | #3.4 | QC | same |
| S1-14 | `region_q3` | #3.4 | QC | same |
| S1-15 | `region_q4` | #3.4 | QC | same |
| S1-16 | `illum_plane_tilt` | #4.1 | QC | illumination measure; not measured in this form |
| S1-17 | `illum_radial` | #4.1 | QC | illumination measure; not measured in this form |
| S1-18 | `local_contrast` | #4.2 | QC | Module 1 recorded ρ 0.250 against grade and ruled it out as a gate |
| S1-19 | `saturation_count` | #4.2 | QC | Module 1 recorded ρ 0.500 against grade and ruled it out as a gate |
| S1-20 | `stage1_verdict` (pass / borderline) | workflow | CONF | Lets Module 3 check whether borderline images are graded worse |
| S1-21 | `enhancement_applied` (flat-field / CLAHE) | #4 | CONF | CLAHE cost **20%** of microaneurysm detectability in Module 1 testing; this flag is how you detect that effect in Module 3 |

**Why Stage 1 feeds no model inputs.** Module 1 features on their own reached only
AUC **0.707** for referable DR. Adding them to the Module 2 features moved AUC from
0.910 to 0.915. When pooled and within-resolution correlations are compared, every
sharpness metric's apparent link to disease turns out to be the camera. Sicker
patients in APTOS were photographed on different equipment; their retinas are not
blurrier.

### 2.2 Stage 2 — 40 features, 33 model inputs

**Vessel-map statistics.** All are derived from the vessel map Stage 2 already
builds. None is listed by name in `Stage_2_CNN`, so each needs one line of code.

| ID | Feature | Role | within ρ (previous implementation) | Transfers? |
|---|---|---|---|---|
| S2-01 | `vessel_density_pct` | MODEL | **−0.406**, same sign 5/5 | approximately — the finalized vessel map uses matched filtering plus Frangi, so re-measure |
| S2-02 | `vessel_fragmentation` | MODEL | **+0.357**, 5/5 | approximately |
| S2-03 | `vessel_components` | MODEL | **+0.326**, 5/5 | approximately |
| S2-04 | `vessel_largest_tree_pct` | MODEL | **−0.322**, 5/5 | approximately |
| S2-05 | `vessel_length` | MODEL | **−0.349**, 5/5 | approximately |
| S2-06 | `vessel_orientation_coherence` | MODEL | −0.189, 4/5 | approximately |

**Vessel calibre classes** — finalized §VESSELS (b), where calibre comes from the scale σ

| ID | Feature | Role | Evidence |
|---|---|---|---|
| S2-07 | `major_vessel_pct` (label 1) | MODEL | unmeasured |
| S2-08 | `branch1_vessel_pct` (label 2) | MODEL | unmeasured |
| S2-09 | `minor_vessel_pct` (label 3) | MODEL | unmeasured |
| S2-10 | `venous_beading_pct` (label 0) | MODEL | unmeasured |
| S2-11 | `venous_beading_quadrants` (0–4) | MODEL | unmeasured; feeds the 4-2-1 rule |

**Neovascularization and IRMA** — finalized §VESSELS (c), fine-scale excess, reported as one class

| ID | Feature | Role | Evidence |
|---|---|---|---|
| S2-12 | `nv_score` | MODEL | **+0.355**, 5/5. Same algorithm as before, so this evidence transfers best |
| S2-13 | `nv_score_max` (1 DD window) | MODEL | **+0.296**, 5/5 |
| S2-14 | `nvd_score` (within 1 DD of the optic disc) | MODEL | unmeasured; a split of `nv_score` |
| S2-15 | `nve_score` (elsewhere) | MODEL | unmeasured |
| S2-16 | `nv_irma_quadrants` (0–4) | MODEL | unmeasured; feeds the 4-2-1 rule |

**Optic disc and fovea**

| ID | Feature | Role | Reason |
|---|---|---|---|
| S2-17 | `od_x` | EXCLUDE | a raw coordinate |
| S2-18 | `od_y` | EXCLUDE | a raw coordinate |
| S2-19 | `od_radius_pct` | QC | scale sanity check |
| S2-20 | `od_contrast` (centre-surround) | QC | within ρ +0.089, weak |
| S2-21 | `fovea_x` | EXCLUDE | a raw coordinate |
| S2-22 | `fovea_y` | EXCLUDE | a raw coordinate |
| S2-23 | `od_fovea_dist_dd` | QC | The search window bounds this value, so it cannot vary much and says nothing about disease (within ρ −0.036). Use it only to catch localisation failures. |

**Lesions** — each count is taken **after** the five-step candidate classifier in §THE FIVE-STEP LESION PIPELINE

| ID | Feature | Role | Evidence |
|---|---|---|---|
| S2-24 | `haem_count` | MODEL | **+0.257**, 5/5; see the leakage warning in §4 |
| S2-25 | `haem_q1` | MODEL | unmeasured; stored raw for the 4-2-1 rule |
| S2-26 | `haem_q2` | MODEL | unmeasured |
| S2-27 | `haem_q3` | MODEL | unmeasured |
| S2-28 | `haem_q4` | MODEL | unmeasured |
| S2-29 | `haem_q_min` | MODEL | **+0.221**, 5/5, but see the quadrant caveat in §4 |
| S2-30 | `haem_q_max` | MODEL | **+0.222**, 5/5, but see the quadrant caveat in §4 |
| S2-31 | `hard_exudate_count` | MODEL | unmeasured. The previous brightness-threshold detector was **inverted**: healthy eyes averaged 57 marks, diseased eyes 17–23. The finalized ratio-based detector is new and must be validated before this feature is trusted. |
| S2-32 | `hard_exudate_area_pct` | MODEL | unmeasured, same condition |
| S2-33 | `exudate_fovea_min_dist_dd` | MODEL | unmeasured. This is the DME measurement, and it was missing before. |
| S2-34 | `dme_flag` (exudate within 500 µm = 34 px of the fovea) | MODEL | unmeasured. It forces urgent referral **regardless of grade** (§6.4). |
| S2-35 | `cws_count` (nerve-fibre ischaemia) | MODEL | unmeasured, new |
| S2-36 | `cws_area_pct` | MODEL | unmeasured, new |

**4-2-1 rule**

| ID | Feature | Role | Evidence |
|---|---|---|---|
| S2-37 | `rule421_haem` (`haem_q_min` > 3) | MODEL | +0.165, 4/5 |
| S2-38 | `rule421_beading` (beading in ≥ 2 quadrants) | MODEL | unmeasured |
| S2-39 | `rule421_irma` (NV/IRMA in ≥ 1 quadrant) | MODEL | unmeasured; IRMA is combined with NV |
| S2-40 | `severe_npdr_flag` (any of the three) | MODEL | unmeasured; composite |

**Stage 2 totals:** 4 EXCLUDE + 3 QC + 12 measured MODEL + 21 unmeasured MODEL = **40**.

### 2.3 Columns carried in the CSV but never used as features

| Column | Purpose |
|---|---|
| `id_code` | join key |
| `diagnosis` | label |
| `split` | `dev` or `test` (§5) |
| `cv_fold` | 0–4 for dev rows, blank for test rows (§5) |
| `resolution` | **stratification only**; the network must never see it |
| `sample_source` | `gate_sample`, `sharpest70`, or `new` (§5.1) |

---

## 3. A gap in the finalized design: there is no microaneurysm detector

`Stage_2_CNN`'s feature-engineering sections cover **haemorrhage, nerve-fibre
ischaemia and hard exudates**. **Microaneurysms appear nowhere**. The only mention
is the evidence table inside the five-step pipeline section.

This gap matters for two reasons:

1. **Microaneurysms define grade 1.** The ICDR scale defines mild NPDR as
   *microaneurysms only*. Without an MA feature, the network cannot tell grade 0
   from grade 1 except through side effects.
2. **In the previous implementation, the microaneurysm count ranked first.**
   `ma_n` had within ρ **+0.478**, same sign in all 5 strata. It ranked first on
   every measure tried and carried RandomForest importance 0.140, the next
   feature being 0.064. That ranking is inflated by leakage (§4) and is
   provisional, but no other feature came close.

**Recommended addition — the microaneurysm block (5 features).** It uses the same
five-step pipeline, with the structuring element set to L = 15 as the finalized
document already specifies:

| ID | Feature | Role |
|---|---|---|
| S2-41 | `ma_count` | MODEL |
| S2-42 | `ma_q1` | MODEL |
| S2-43 | `ma_q2` | MODEL |
| S2-44 | `ma_q3` | MODEL |
| S2-45 | `ma_q4` | MODEL |

With the block, the design has **38 model inputs**. This is decision **D1** in §9.

---

## 4. Caveats that shape the plan

### 4.1 Leakage: lesion classifiers must never see Module 3's evaluation grades

Each lesion counter includes a classifier trained on **weak labels taken from the
image grade**: grade 0 against grades 3–4. If that classifier is fitted on an image
and then scores the same image, the lesion count for that image already contains
its grade. Module 3 would then learn the answer, not the disease.

This has **already happened** in the previous implementation:

| Classifier | Trained on | Of those, inside the 309-row table |
|---|---|---|
| Microaneurysm | 250 images | **250** |
| Haemorrhage | 42 images | **42** |

Splitting the table into rows each classifier had seen and rows it had not:

| | seen (in-sample) | unseen (out-of-sample) |
|---|---|---|
| `ma_n` pooled ρ | +0.730 (n = 250) | +0.291 (n = 59) |
| `hem_n` pooled ρ | +0.721 (n = 42) | +0.342 (n = 267) |
| reference `nv_fine` (involves no classifier) | +0.403 / −0.356 | −0.226 / +0.371 |
| reference `vessel_pct` (involves no classifier) | −0.493 / +0.226 | +0.061 / −0.447 |

The lesion counts fall sharply on unseen rows. **But the reference features, which
involve no classifier, swing just as much.** The seen and unseen groups differ in
grade mix: the 42 haemorrhage-training images contain no grade 1 or 2 at all. They
also differ in sharpness: the 59 unseen microaneurysm rows are the sharpest images.
So this split **proves the leakage exists but cannot measure its size.** Treat the
current feature ranking as provisional.

**Rule for the pilot:** every lesion candidate classifier is trained **inside the
cross-validation loop**, on training folds only, and scores only its held-out fold
(§6.1). No lesion classifier may ever touch a test image.

### 4.2 The quadrant features will not match the previous measurements

The quadrant counts are measured in a frame running from the optic disc to the
fovea. The finalized design finds both points differently from the implementation
that produced the numbers above:

- **Optic disc:** brightness first, avoiding regions where vessels were detected.
  Previously: mean over a disc-sized window on raw green, within r ≤ 0.6 R.
- **Fovea:** the darkest point within ±1.25× of the expected position, without a
  vessel-density term. Previously: darkness minus 3.0 × vessel density.

On 50 images, the darkness-only fovea landed **more than 0.5 disc diameters** from
the darkness-minus-vessels fovea in **74%** of cases (median shift 1.83 DD). Quadrant
assignments will therefore change, so **the ρ values for S2-29, S2-30 and S2-37 do
not transfer** and must be re-measured.

### 4.3 The camera leaks through Module 2 features too

Can a classifier predict an image's resolution from the feature set alone? That
accuracy measures how much camera identity the features carry.

| Feature set (previous implementation) | Inputs | Camera identified | Referable AUC, pooled | Referable AUC, within resolution |
|---|---|---|---|---|
| Everything numeric | 55 | **100%** | 0.931 | 0.881 |
| Camera and absolute-intensity columns removed | 37 | 86.2% | 0.915 | 0.879 |
| Core (\|within ρ\| ≥ 0.10) | 18 | 85.1% | 0.918 | **0.890** |
| Module 2 only | 20 | 65.9% | 0.909 | 0.864 |
| *chance* | | *16.7%* | | |

Two lessons for the pilot:

- Removing camera and absolute-intensity columns **cost almost nothing honest**:
  within-resolution AUC went from 0.881 to 0.879. Those columns had mostly carried
  camera identity.
- **Even the Module 2 features identify the camera 66% of the time.** A camera
  signal remains whatever is removed, so **every metric must also be reported
  within resolution strata**.

### 4.4 Images rejected by Stage 1 never reach Module 3

Stage 1 keeps a single global sharpness threshold for all cameras (decision M1 in
the Stage 1 review). On APTOS the current gate rejects **3.8%** of grade-0 images
and **12.9%** of grade-4. The pilot therefore trains on a population with fewer of
the hardest-to-image sick eyes. Record how many rejected images each grade loses.

---

## 5. Data: the combined CSV and the 500-image sample

### 5.1 Sample

**100 images per grade.** Grade-balanced, so the network has enough grade 3 and
grade 4 examples to learn from.

| Grade | Already extracted | Needed | Stage 1 gate-passed pool |
|---|---|---|---|
| 0 | 64 | 36 | 1,737 |
| 1 | 62 | 38 | 346 |
| 2 | 63 | 37 | 876 |
| 3 | 59 | 41 | 169 |
| 4 | 61 | 39 | 257 |
| **total** | **309** | **191** | |

- Draw the **191 new IDs across sharpness deciles** within each grade, with a
  fixed random seed. This dilutes the bias from the 59 "sharpest" images already
  in the set.
- Tag each row's `sample_source` (`gate_sample`, `sharpest70`, `new`), so that a
  sensitivity check can drop the `sharpest70` rows.
- **Re-extract all 500 images.** The existing 309 were computed with the previous
  algorithms, not the finalized ones. Keep their IDs; recompute every feature.

**Balanced sampling distorts prevalence.** APTOS's true grade mix is roughly
49 / 10 / 27 / 5 / 8 %, not 20% each. Positive predictive value, class priors and
any operating threshold chosen on balanced data are **not** what screening would
see. Report per-class sensitivity and specificity, which do not depend on
prevalence, and reweight to the true mix before quoting predictive values.

### 5.2 Files

**Do not overwrite** `data/aptos_train_module1_features.csv`. Write new files:

```
data/module3_stage1_features.csv   id_code + S1-01 .. S1-21
data/module3_stage2_features.csv   id_code + S2-01 .. S2-40 (+ S2-41 .. S2-45 if D1)
data/module3_dataset.csv           join on id_code, plus the §2.3 columns
data/module3_ids.txt               the 500 IDs, one per line
```

### 5.3 Split

| Set | Rows | Use |
|---|---|---|
| **test** | 75 (15 per grade) | Held out. **Touched once**, at the end. |
| **dev** | 425 (85 per grade) | 5-fold cross-validation: model selection, calibration and threshold choice, all from out-of-fold predictions |

Why not a separate 75-image validation set? At this size, choosing an operating
threshold on 15 images per grade is noise. Out-of-fold predictions on 425 images
give a stabler estimate. The test set still plays no part in any choice.

- Stratify **both** the test split and the cross-validation folds by grade.
- Check that the resolution mix is similar across test and the dev folds. If one
  camera sits mostly in test, the test result measures the camera.
- **Patient-level splitting is not possible.** APTOS filenames do not identify
  patients. State this limitation in the report.

---

## 6. Model

### 6.1 Training pipeline — one cross-validation fold

```
for each of the 5 dev folds:
    train rows = the other 4 folds
    1. fit every lesion candidate classifier on TRAIN rows only       (§4.1)
    2. extract lesion counts for TRAIN and the held-out fold with those classifiers
    3. fit z-score normalisation on TRAIN rows only
    4. train the network on TRAIN rows
    5. predict the held-out fold  ->  out-of-fold predictions
after all folds:
    choose threshold cutpoints, calibration and the referable operating point
    on the 425 out-of-fold predictions
then, once:
    retrain on all 425 dev rows and evaluate on the 75 test rows
```

Step 1 is the expensive one: candidate features are cached per image, but the
classifiers are refitted five times.

### 6.2 Network — ordinal regression MLP

Grades are ordered: predicting 4 for a true 0 is far worse than predicting 1.
Treat grading as **regression, then round with cutpoints fitted on the dev
data** — the approach the reference doc recommends and most top APTOS solutions
used.

```
inputs  (33, or 38 with D1), z-scored
  -> fullyConnected 32 -> ReLU -> dropout 0.3
  -> fullyConnected 16 -> ReLU -> dropout 0.3
  -> fullyConnected 1                      continuous grade score
loss: mean squared error, weighted per class (inverse frequency within the training folds)
L2 weight decay; early stopping on an inner validation split of the training folds
```

MATLAB (Deep Learning Toolbox) sketch:

```matlab
layers = [
    featureInputLayer(numFeatures, Normalization="zscore")
    fullyConnectedLayer(32)
    reluLayer
    dropoutLayer(0.3)
    fullyConnectedLayer(16)
    reluLayer
    dropoutLayer(0.3)
    fullyConnectedLayer(1)];
opts = trainingOptions("adam", L2Regularization=1e-2, ...
    ValidationData={Xval, Yval}, ValidationPatience=20, ...
    Shuffle="every-epoch", Verbose=false);
net = trainnet(Xtrain, Ytrain, layers, "mse", opts);
```

`Normalization="zscore"` computes its statistics from the data the network is
trained on, which satisfies step 3.

**Size check.** 38 inputs × 32 + 32 = 1,248; 32 × 16 + 16 = 528; 16 × 1 + 1 = 17.
That is **1,793 trainable weights against about 340 training rows per fold** —
over five weights per example. The network is deliberately small, and dropout,
weight decay and early stopping are all required, not optional.

### 6.3 Required baseline: RandomForest

A neural network will not automatically beat a tree model on 500 rows of tabular
data. **Train a RandomForest on the same folds and the same features**
(`fitrensemble` with `Method="Bag"` in MATLAB). The network is adopted only if it
beats the forest on the **within-resolution** metrics (decision D4).

Measured on the previous implementation at n = 309:

**Referable DR (binary AUC), 37 inputs with camera and absolute-intensity columns removed**

| Model | Pooled | Within resolution | Drop |
|---|---|---|---|
| RandomForest | 0.915 | **0.879** | −0.036 |
| MLP (64, 32) | 0.919 | 0.813 | −0.106 |
| HistGradientBoosting | **0.928** | 0.660 | −0.268 |
| MLP (32, 16), heavily regularised | 0.826 | 0.580 | −0.246 |

**Ranked by pooled AUC, gradient boosting or the network would win. Within
resolution strata, the forest wins by a wide margin.** Pooled AUC rewards
learning the camera.

These within-resolution models train on only 30–90 rows per stratum, which is
harsher on the network and on boosting than a 425-row dev set will be. The pilot
may narrow the gap — which is exactly what it should test.

**5-class quadratic weighted kappa (QWK), regression then rounding**

| Features | RandomForest | MLP (32, 16) | MLP (64, 32) |
|---|---|---|---|
| 37 inputs (camera and absolute-intensity columns removed) | 0.766 | 0.702 | 0.714 |
| 18 core inputs | **0.779** | 0.738 | 0.753 |

Reference points: top APTOS Kaggle solutions, all image CNNs, reached about 0.93;
0.88–0.91 counts as solid.

**Learning curve — referable AUC by training size**

| n | 100 | 150 | 200 | 250 | 303 |
|---|---|---|---|---|---|
| RandomForest | 0.910 | 0.916 | 0.922 | 0.931 | **0.940** |
| MLP (64, 32) | 0.909 | 0.862 | 0.888 | 0.917 | 0.920 |

The forest improves steadily with more data. The network is erratic (0.909 at 100,
0.862 at 150) and still trails at 303. Going from about 300 to 500 images is where
you find out whether the gap closes.

### 6.4 Outputs

| Output | How it is produced |
|---|---|
| 5-class grade | continuous score rounded at the fitted cutpoints |
| Referable (grade ≥ 2) | continuous score used directly for ROC, then calibrated (Platt or isotonic on out-of-fold predictions) |
| DME urgent flag | `dme_flag` (S2-34), which **overrides** the grade: urgent referral regardless of it |
| Confidence routing | calibrated probability, lowered for `stage1_verdict = borderline` and `enhancement_applied = 1` (S1-20, S1-21) |

---

## 7. Evaluation

### 7.1 Metrics

| Metric | Why |
|---|---|
| **Quadratic weighted kappa** | the reference doc's model-selection metric; it penalises errors by squared distance |
| Confusion matrix | to see *which* grades are confused |
| Per-class sensitivity | plain accuracy is forbidden: a model predicting grade 0 for everything scores 49% on the true mix |
| Referable sensitivity and specificity at the chosen threshold | the problem statement's targets: **≥ 90% sensitivity, ≥ 85% specificity** |
| All of the above **within resolution strata** | §4.3 |
| Reliability diagram and expected calibration error, before and after calibration | calibration check |
| Bootstrap 95% confidence intervals on the test metrics | 15 images per grade makes the intervals wide; report them, don't hide them |

### 7.2 Operating point

On the **425 out-of-fold predictions**: walk the ROC curve, find the threshold
where referable sensitivity reaches 0.90, and read off the specificity there.
**Freeze that threshold**, then apply it to the test set exactly once. Choosing it
on the test set is the most common accidental cheat in this field.

### 7.3 Weak points to watch

The best previous model (18 core inputs, RandomForest regression, QWK 0.779)
produced this confusion matrix. Rows are the true grade; columns the prediction.

```
         p0   p1   p2   p3   p4
true 0   50   12    2    0    0
true 1    1   23   32    6    0
true 2    0    7   36   20    0
true 3    0    2    9   44    4
true 4    0    1   11   46    3
```

- **Grade 4 was almost never predicted: 3 of 61 (5%).** Most true grade 4 images
  were called grade 3. The referable decision is unaffected, because 3 and 4 are
  both referable. For 5-class grading, proliferative DR detection is poor. The new
  NV split (S2-14, S2-15) and the 4-2-1 composite (S2-40) exist to fix this;
  **report grade-4 recall separately.**
- **Grade 1 was called grade 2 more often than grade 1: 32 against 23 of 62.** This
  is the mild-NPDR boundary, and it depends on microaneurysms (§3).
- Rounding a regression output pulls predictions toward the middle grades. Fitted
  cutpoints (§6.2) are the first remedy; an ordinal head (CORAL) is the second
  (decision D6).

---

## 8. Phased plan

| Phase | Work | Output | Exit criterion |
|---|---|---|---|
| **0** | Implement the finalized Stage 1 and Stage 2 feature extraction to the schema in §2 | extraction code | runs on 20 images; every column filled; values in range |
| **1** | Choose the 500 IDs (§5.1) and assign splits and folds (§5.3) | `module3_ids.txt`; split and fold columns | 100 per grade; 15 per grade in test; resolution mix checked |
| **2** | Extract Stage 1 features and **candidate-level** Stage 2 features for all 500. Lesion classifiers are **not** fitted yet. | stage CSVs, cached candidate features | no blanks; §4.4 rejection counts recorded |
| **3** | Data QC: value ranges; optic-disc failure rate; camera identifiability of the feature set; within-resolution ρ per feature | QC report | every MODEL feature has a measured within-resolution ρ; features with the wrong sign are flagged |
| **4** | RandomForest baseline, with lesion classifiers trained inside each fold (§6.1) | out-of-fold predictions, baseline metrics | pipeline leakage-free by construction |
| **5** | MLP (§6.2), same folds and features; small grid of width × dropout × weight decay | out-of-fold predictions | compared against the Phase 4 forest within resolution |
| **6** | Feature-block ablation (below) | ablation table | each block kept only if within-resolution out-of-fold QWK improves |
| **7** | Fit cutpoints and calibration; choose the operating point on out-of-fold predictions | frozen model and threshold | threshold fixed before any test access |
| **8** | Single evaluation on the 75 test images | final metrics with bootstrap CIs | reported whatever the result |

**Phase 6 feature blocks, added in this order:**

| Step | Block | Features | Question |
|---|---|---|---|
| 6a | Measured core | S2-01..06, 12, 13, 24, 29, 30, 37 (12) | the baseline the finalized design can already reproduce |
| 6b | + Microaneurysms (if D1) | S2-41..45 | does the MA block add grade-1 signal? |
| 6c | + Vessel calibre and beading | S2-07..11 | new, unmeasured |
| 6d | + NV split | S2-14..16 | does grade-4 recall improve? |
| 6e | + Exudate and DME | S2-31..34 | the detector was previously inverted — check the sign first |
| 6f | + Cotton-wool spots | S2-35, 36 | new |
| 6g | + Per-quadrant raw counts and the 4-2-1 composite | S2-25..28, 38..40 | spatial rule |

**Honest pilot targets — not deployment targets:**

- The network's within-resolution QWK is at least the forest's, or the forest is
  adopted instead (D4).
- Referable sensitivity of 0.90 is reached on out-of-fold predictions, with
  specificity **reported, whatever it is**. The 85% specificity target belongs to
  the full system (fusion with the image CNN) and may not be reached by features
  alone — the previous features reached **75.4%** specificity at 90% sensitivity.
- Grade-4 recall is reported on its own line.

---

## 9. Decisions for you

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| **D1** | Add a microaneurysm detector to Stage 2 | yes, S2-41..45 / no | **Yes.** Grade 1 is defined by microaneurysms, and it was the strongest feature measured (§3) |
| **D2** | Sampling | 100 per grade balanced / true prevalence | **Balanced** for a 500-image pilot; reweight when reporting |
| **D3** | Existing 309 IDs | keep, re-extract, tag source / resample all 500 | **Keep and tag.** Run a sensitivity check without `sharpest70` |
| **D4** | Adoption rule for the network | must beat RandomForest within resolution / adopt the network regardless | **Must beat the forest** |
| **D5** | Starting feature set | 12 measured (+5 with D1), then blocks / all 33–38 at once | **Start at 12 (17) and add blocks.** 38 inputs on about 340 rows overfits |
| **D6** | Ordinal method | regression + fitted cutpoints / CORAL head | **Regression + cutpoints** first; CORAL only if middle-grade collapse persists |
| **D7** | Stage 1 values as network inputs | no (QC and confidence only) / yes | **No.** Within-resolution evidence says they carry camera identity, not disease (§2.1) |

---

## 10. Summary

- **61 features** are emitted by the finalized algorithms: 21 from Stage 1 and 40
  from Stage 2. **33** are model inputs; **38** with the recommended microaneurysm
  block.
- **Stage 1 feeds no model inputs.** It gates images and adjusts confidence.
- Only **12** of the 33 have a measured equivalent. The other 21 are new and must
  be validated during the pilot — especially exudates, whose previous detector
  was inverted.
- **The finalized Stage 2 has no microaneurysm detector.** That is the largest gap
  for grading.
- **Lesion classifiers must be trained inside the cross-validation folds.** Leakage
  has already happened in the existing data.
- **A small network is plausible but not yet proven on this task.** On 309 rows it
  lost to RandomForest within resolution strata (0.813 against 0.879 AUC; QWK 0.753
  against 0.779). The pilot keeps the forest as a baseline the network has to beat.
- **Report every metric within resolution strata.** Pooled AUC here partly measures
  the camera.

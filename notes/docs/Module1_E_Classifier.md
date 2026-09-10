# Module 1, Stage [E] — The Gradability Classifier

Turns the ~34 features from [A]–[C] into a verdict **and a retake reason**.

Measured on APTOS 2019 (Ryzen 5 7535U, scikit-learn 1.8). All CV is
**GroupKFold by base image**, so the same eye never appears in train and test.

---

## The labelling problem, and how to get around it

**APTOS has no gradability labels.** There is no column saying "this image is too
blurry to read", so a supervised classifier cannot be trained on real data.

The way around it: take **clean** images (`gate_reject == 0`, top `varLapNorm`),
apply **controlled degradations of known severity**, and use the severity as the
label. Then apply the trained model to real images and verify it behaves.

```
55 clean base images  x  12 conditions  =  660 labelled samples
```

> **What this does and does not prove.** It proves the model detects *known*
> optical degradation. It does **not** prove it agrees with an ophthalmologist on
> real ungradable images — that still needs DRIMDB / DeepDRiD or hand labels.

---

## Algorithm comparison

First pass, well-separated severities (clean / blur σ≤1.2 vs blur σ≥4, etc.):

| Model | accuracy | AUC | sens | spec | fit ms |
|---|---|---|---|---|---|
| **RandomForest** | **0.986** | **1.000** | 1.000 | 0.967 | 917 |
| SVM (RBF) | 0.982 | 0.996 | 0.997 | 0.960 | 42 |
| HistGradBoost | 0.968 | 0.997 | 0.992 | 0.935 | 1404 |
| LogisticRegression | 0.962 | 0.978 | 0.979 | 0.938 | 38 |

> **AUC = 1.000 means the task was too easy, not that the model is perfect.**
> Distinguishing a clean image from σ=7 blur is trivial. The number below is the
> honest one.

### The harder task — severities straddling the boundary

Re-run with degradations placed either side of a plausible threshold
(blur σ 2.0 vs 2.8 vs 3.6; dark ×0.40 vs ×0.28; wash t 0.30 vs 0.42; …):

| Feature set | n | accuracy | AUC | sens | spec |
|---|---|---|---|---|---|
| **All features** | 34 | **0.959** | 0.991 | 0.964 | 0.955 |
| Drop 5 disease-correlated | 29 | 0.921 | 0.978 | 0.921 | 0.921 |
| Strict gate-safe only | 11 | 0.839 | 0.923 | 0.870 | 0.809 |

**RandomForest is the pick**: best accuracy, handles wildly different feature
scales without normalisation, gives feature importances for free, and trains on
660 samples in under a second. SVM is 20x faster to fit and nearly as good — use
it if fit time matters. Logistic regression is the floor.

---

## The safety-vs-accuracy trade-off — quantified

[C] flagged `localContrast` (rho 0.250) and `colorSat` (0.500) as **never-gate**,
and [B] flagged `specSlope` (0.130–0.336). But feature importance puts
`localContrastP10` **second** overall:

| Feature | Importance |
|---|---|
| `bgMean` | 0.0760 |
| **`localContrastP10`** | **0.0746** |
| `radius` | 0.0613 |
| `brenner` | 0.0607 |
| `offset` | 0.0607 |
| `tenengrad` | 0.0581 |
| **`localContrast`** | **0.0563** |
| `tenengradVar` | 0.0558 |
| `residual` | 0.0488 |
| `bgCV` | 0.0442 |

Note how **flat** this is — the top feature carries only 7.6%, and fourteen
features sit between 3% and 8%. No single feature dominates, which is good for
robustness but means dropping any one costs a little.

**The cost of safety, measured:**

```
drop the 5 disease-correlated features  ->  -3.8 accuracy points
use only the 11 strict gate-safe ones   ->  -12.0 accuracy points
```

**Recommendation: drop the 5.** 3.8 points is a fair price for removing features
that demonstrably track pathology. The strict-11 set costs too much.

---

## Multi-label heads — the design that produces a retake reason

Do **not** train one 3-class model. Train **one binary head per failure mode**:

| Head | positives | accuracy | AUC | sens | spec |
|---|---|---|---|---|---|
| `noise` | 55 | **1.000** | 1.000 | 1.000 | 1.000 |
| `blur` | 110 | 0.989 | 0.999 | 0.982 | 0.991 |
| `dark` | 55 | 0.988 | 0.998 | 0.945 | 0.992 |
| `wash` | 55 | 0.973 | 0.992 | **0.800** | 0.988 |
| `grad` | 55 | 0.971 | 0.993 | **0.836** | 0.983 |

### Reason attribution: 100% (330/330)

Of every ungradable image, the **highest-scoring head names the correct cause**:

| Cause | Correctly attributed |
|---|---|
| blur | 100.0% |
| dark | 100.0% |
| wash | 100.0% |
| noise | 100.0% |
| grad | 100.0% |

**The key implementation detail:** use **argmax across heads** for attribution,
not each head's own 0.5 threshold. The `wash` head only fires at 0.5 in 80% of
wash cases — but it is still the *highest* of the five heads 100% of the time.
Ranking is easier than absolute calibration.

Two reasons this beats a single 3-class model:

1. **An image can fail several ways at once** — dark *and* blurry is common (low
   light → long exposure → motion). A single-label model must pick one.
2. **The retake message falls out free.** The firing heads *are* the reason
   string. No feature-importance archaeology needed.

---

## The safety check: is the classifier disease-blind?

Train on synthetic degradation, then apply to **all 3,657 real APTOS images** and
correlate the predicted ungradable probability with DR grade, **within each
resolution stratum** (raw correlation would mostly measure the camera).

| Stratum | n | rho(p, grade) | reject g0 | reject g2+ |
|---|---|---|---|---|
| 1050×1050 | 974 | −0.055 | 0.1% | 0.0% |
| 2416×1736 | 638 | 0.137 | 0.0% | 1.9% |
| **2588×1958** | 531 | **−0.149** | **9.6%** | **14.3%** |
| 3216×2136 | 409 | −0.072 | 0.0% | 0.5% |
| 819×614 | 287 | 0.044 | 1.4% | 0.0% |

```
overall predicted-ungradable rate: 3.7%
max|rho| = 0.149  ->  GATE-SAFE (threshold 0.15)
```

**It passes — but by 0.001.** Two caveats worth carrying forward:

- **2588×1958 again.** That stratum rejects 9.6% of grade-0 and **14.3% of
  grade-2+** images. Same format behind the 29% [A] rejection rate and the 26
  blob-lock failures. It is the persistent weak point of the whole module.
- **The pass is narrow enough to be fragile.** Re-run this check after any
  feature or threshold change; do not assume it stays under 0.15.

The 3.7% overall rate is plausible but low for real-world screening (15–25%
typical) — APTOS is a curated competition dataset, not a field capture set.

---

## Recommended configuration

```
model      RandomForest, 300 trees
features   29  (all of [A]+[B]+[C] minus localContrast, localContrastP10,
                colorSat, specSlope, noiseSigma)
structure  5 binary heads: blur / dark / wash / noise / grad
verdict    any head >= threshold  -> ungradable
reason     argmax over heads
```

Expected on the harder synthetic task: **accuracy 0.921, AUC 0.978**, reason
attribution ~100%.

### Threshold asymmetry

A false "ungradable" costs ~20 s of retake. A false "gradable" costs a
potentially missed diagnosis. Bias toward rejection — but not blindly: the
retake rate feeds Module 5's throughput model, so sweep the threshold and plot
missed-bad-images against retake rate against patients/day, then pick the point
defensibly.

---

## What is still missing

| Gap | Why it matters |
|---|---|
| **Real ungradable labels** | everything above is synthetic; DRIMDB/DeepDRiD or ~300 hand-labelled APTOS images would fix it |
| **Calibration** | RandomForest probabilities are not calibrated; needs Platt/isotonic before the 0.5 threshold means anything |
| **Borderline class** | currently binary; the three-way verdict needs a second threshold, which needs real labels |
| **2588×1958** | 14.3% grade-2+ rejection is unresolved across [A] and [E] |

---

## Next

Stage [F] — adaptive enhancement for the *borderline* class, then re-scoring
through [A]–[C] and a second pass through [E].

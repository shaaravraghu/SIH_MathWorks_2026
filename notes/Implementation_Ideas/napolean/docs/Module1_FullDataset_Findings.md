# Module 1 — Full-Dataset Findings (3,662 APTOS images)

Results from running [A]+[B] over the **entire** APTOS 2019 training set.
Source data: [`data/aptos_train_module1_features.csv`](../../../../data/aptos_train_module1_features.csv),
schema in [Module1_CSV_Schema.md](Module1_CSV_Schema.md).

**These results supersede several conclusions drawn from the earlier
150-image sample.** Corrections are marked ⚠ below.

---

## Contents

- [Detection rate](#detection-rate)
- [⚠ The gate skew is an ACQUISITION artefact, not disease](#-the-gate-skew-is-an-acquisition-artefact-not-disease)
- [⚠ Every feature correlation collapses within format](#-every-feature-correlation-collapses-within-format)
- [Root cause: the 2588x1958 camera](#root-cause-the-2588x1958-camera)
- [What this means for Module 3](#what-this-means-for-module-3)
- [Open items](#open-items)

---

## Detection rate

| | Count |
|---|---|
| Images processed | 3,662 |
| `fov_ok = 1` | **3,660** |
| Failures | 2 — **both `MemoryError`, not algorithm failures** |

Excluding the two out-of-memory crashes, **detection succeeded on 3,660/3,660 =
100%** of images it was able to load.

| Diagnostic | Value |
|---|---|
| raggedness retry fired | 348 (9.5%) |
| red-degenerate fallback | 0 |
| fast-reject gate | 277 (7.6%) |
| mean processing time | 3,890 ms/image |

The two failures (`e868c3da340b`, `e8d1c6c07cf2`) died allocating 78.6 MB and
5.8 MB respectively on a machine at 97% memory utilisation. Re-running the
script will pick them up — it skips `id_code`s already present.

---

## ⚠ The gate skew is an ACQUISITION artefact, not disease

The 150-image sample showed all 10 gate rejections falling on grade >= 2, and
[Module1_A](Module1_A_FOV_Detection.md) flagged this as an unresolved
disease-blindness failure. The full dataset both **confirms the skew** and
**identifies its cause** — and the cause is not pathology.

### The skew, at scale

| Grade | n | Rejected | Rate |
|---|---|---|---|
| 0 | 1,805 | 68 | **3.8%** |
| 1 | 370 | 24 | 6.5% |
| 2 | 999 | 123 | **12.3%** |
| 3 | 193 | 24 | 12.4% |
| 4 | 295 | 38 | **12.9%** |

Referable (>= 2): **12.3%** rejected. Non-referable (0-1): **4.2%**.
**Referable patients are rejected 2.9x more often.**

254 of the 277 rejections are driven by `residual`.

### The cause: stratify by image format and the skew vanishes

| Format | n | median `residual` | Rejection rate |
|---|---|---|---|
| 1050x1050 | 974 | 0.0022 | **0.0%** |
| 2048x1536 | 351 | 0.0018 | 0.3% |
| 3388x2588 | 141 | 0.0268 | 0.7% |
| 3216x2136 | 409 | 0.0025 | 1.2% |
| 819x614 | 287 | 0.0028 | 1.4% |
| 2416x1736 | 638 | 0.0030 | 4.1% |
| **2588x1958** | **533** | **0.0403** | **29.1%** |

Within a single format, `residual` is **flat across grades**:

```
1050x1050   grade 0: 0.00222   1: 0.00223   2: 0.00222   3: 0.00228   4: 0.00228
            rejection rate 0.0% for EVERY grade
2416x1736   grade 0: 0.00303   1: 0.00299   2: 0.00302   3: 0.00298   4: 0.00301
```

And the formats are distributed very unevenly across grades:

| Grade | 1050x1050 | 2416x1736 | 2588x1958 | 3216x2136 |
|---|---|---|---|---|
| 0 | **49.9%** | 1.7% | 12.8% | 0.1% |
| 1 | 5.1% | 63.2% | 11.9% | 3.5% |
| 2 | 3.9% | 23.3% | 16.5% | 30.7% |
| 3 | 1.0% | 31.2% | 24.5% | 16.7% |
| 4 | 4.4% | 27.1% | 15.6% | 19.0% |

**Half of all grade-0 images come from the one camera that never fails
(1050x1050, 0.0% rejection), while grades 2-4 are concentrated in the formats
that do.** The gate is rejecting cameras, not patients.

---

## ⚠ Every feature correlation collapses within format

Spearman rho against DR grade, raw vs computed **within** each image format:

| Feature | rho raw | rho within-format | drop |
|---|---|---|---|
| `offset` | **0.610** | 0.067 | 0.543 |
| `radius` | **0.603** | −0.077 | 0.526 |
| `areaFrac` | −0.564 | 0.065 | 0.499 |
| `borderFrac` | 0.531 | −0.074 | 0.457 |
| `tenengradVar` | **0.508** | 0.011 | 0.497 |
| `specSlope` | 0.457 | **0.168** | 0.289 |
| `residual` | 0.433 | 0.085 | 0.348 |
| `sat_R` | −0.390 | −0.050 | 0.340 |
| `brenner` | −0.365 | 0.023 | 0.342 |
| `noiseSigma` | 0.347 | 0.004 | 0.343 |
| `varLapNorm` | −0.243 | −0.014 | 0.230 |
| `tenengrad` | 0.229 | 0.009 | 0.220 |
| `regionMin` | −0.059 | −0.004 | 0.055 |
| `regionCV` | 0.000 | −0.144 | −0.143 |

**No Module 1 feature genuinely tracks disease.** Every one of them tracks
acquisition, and the apparent disease correlation is entirely mediated by which
camera took the picture.

### Two corrections to earlier conclusions

⚠ **`specSlope` was demoted for the wrong reason.**
[Module1_Feature_Reference](Module1_Feature_Reference.md) put it in Tier 3 on the
strength of rho = 0.460 vs grade, calling it disease-correlated. Within format
it is **0.168**. It is format-sensitive, not disease-sensitive. It remains the
most format-sensitive of the focus metrics (highest residual within-format rho),
so caution is still warranted — but the stated reasoning was wrong.

⚠ **`tenengradVar` was promoted for the wrong reason.**
It scored rho = 0.067 on the 150-image sample and was called "excellent". On the
full dataset its raw rho is **0.508** — worse than `specSlope`. Within format it
is 0.011. The 150-image sample happened to be balanced in a way that hid the
confound.

**The lesson:** a raw correlation against grade in APTOS measures the acquisition
confound, not disease sensitivity. **Always stratify by `width`x`height` before
interpreting any correlation in this dataset.**

---

## Root cause: the 2588x1958 camera

One format accounts for nearly all the trouble. Measured against the others:

| Property | 2588x1958 | Others |
|---|---|---|
| background mean (outside FOV) | **0.0663** | 0.0033–0.0103 |
| background 99.9th pct | **0.1487** | 0.0151–0.0219 |
| raggedness retry fired | **63.2%** | 0.0–0.3% |
| median `raggedness` | **1.0795** | 0.910–0.917 |
| boundary radius, 2nd pct / median | **0.708** | 0.994–0.995 |
| boundary radius, 98th pct / median | **1.230** | 1.034–1.051 |
| mask holes (fraction of area) | 0.0098 | 0.0000 |

**These images do not have a black surround.** The background sits at ~0.066 with
tails to 0.149 — a veiling glow rather than a hard aperture. Consequently:

1. There is no sharp intensity step for the threshold to latch onto.
2. Otsu lands *inside* the retina — 48% of pixels fall below threshold on these
   images, against a true background fraction of ~17%.
3. The extracted boundary wanders: radius varies from **0.71x to 1.23x** the
   median, versus ±5% on every other format.
4. The circle fit is therefore poor (`residual` 13x higher), and the gate fires.

The ellipse axis ratio is 0.829 versus 0.804 for 2416x1736 — **not** meaningfully
different, so the aperture is not elliptical. The boundary is *irregular*, not a
different shape.

### A fix that did NOT work

Subtracting a robust background estimate (`percentile(Ir, 1)`) before Otsu
produced **byte-identical** results. The background elevation is not a uniform DC
offset — the darkest pixels really are near zero, and the glow is a spatial
gradient. Threshold-level correction cannot address it.

### The fix that should work (untested)

Stop finding the boundary by thresholding. Instead cast rays from the estimated
centre and locate, along each ray, the position of **maximum radial intensity
gradient**. That finds the edge of a soft transition robustly, then fit the
circle to those points. Alternatives: aggressive morphological closing before
boundary extraction, or RANSAC in place of the single reweight pass.

---

## What this means for Module 3

This is the finding with the largest downstream consequence.

**`radius` alone has rho = 0.603 with DR grade. `offset` has 0.610.**

Those are trivially learnable shortcuts. A CNN trained on APTOS will discover
that image geometry predicts grade and will exploit it, producing excellent
validation numbers and failing in deployment where the format-grade association
does not hold.

Mitigations, in order of importance:

1. **Radius-normalise and square-crop every image** — `normalizeFundus` already
   does this, and it removes `radius`, `offset` and `areaFrac` as usable signals.
2. **Stratify your train/val/test splits by `width`x`height`**, not just by grade.
3. **Report accuracy per format.** If grade-0 accuracy is high only on
   1050x1050, you have measured the confound.
4. **Adversarial check:** train a classifier to predict *format* from your CNN's
   penultimate features. If it succeeds easily, the representation encodes
   acquisition.

---

## Open items

| Item | Status |
|---|---|
| Fix 2588x1958 boundary extraction (gradient-ray method) | **untested proposal** |
| Re-run the 2 `MemoryError` images | pending — script is resumable |
| Re-derive gate thresholds *per format*, or make `residual` format-invariant | pending |
| Review rejected images by eye to confirm they are genuinely ungradable | pending |
| Extract the same features for `test.csv` (1,928 images) | not started |
| Verify any of this in MATLAB | **blocked** — Image Processing Toolbox not installed |

### On the 8x2.5% ring sampling

The extraction used the **full mask**, not the ring. The ring saves 21 ms/image
against a measured 3,890 ms/image total — **0.5% of runtime** — while costing 19%
median relative error. For a batch extraction producing a reference dataset that
trade is not worth taking; the ring is for the live edge capture loop.

Consequence: `region1`–`region5` in the CSV are **centre + 4 quadrants on frame
axes**, not the 8 ring patches, and `regionMin` is the 5-region variant.

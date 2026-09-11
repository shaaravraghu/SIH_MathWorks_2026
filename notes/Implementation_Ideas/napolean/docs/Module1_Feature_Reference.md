# Module 1 — Complete Feature Reference & Verdict

Every feature produced by [`[A] detectFOV`](../../../../code_testing/matlab/detectFOV.m) and
[`[B] focusMetrics`](../../../../code_testing/matlab/focusMetrics.m), with **measured** values and a
ranked recommendation.

**Evidence base:**

| Source | What it establishes |
|---|---|
| 150 APTOS images, 30 per DR grade | real-world distributions, disease correlation, code-path coverage |
| Controlled sweeps on one reference image | blur monotonicity, noise sensitivity, contrast invariance, partial blur |

Reproduce with [`benchmarkModule1.m`](../../../../code_testing/matlab/benchmarkModule1.m).

> **Status warning.** Every number below comes from a **Python reference
> implementation** of the same logic. The MATLAB `.m` files were not executable at
> the time of writing — see [MATLAB status](#matlab-status).

---

## Contents

- [The verdict](#the-verdict)
- [Why lab dynamic range misled me](#why-lab-dynamic-range-misled-me)
- [[A] geometry features](#a-geometry-features)
- [[B] focus features](#b-focus-features)
- [Disease correlation — the decisive test](#disease-correlation--the-decisive-test)
- [Controlled-sweep results](#controlled-sweep-results)
- [Code-path coverage](#code-path-coverage)
- [MATLAB status](#matlab-status)

---

## The verdict

### Tier 1 — use these, and gate on them

| Rank | Feature | Real spread (p95/p5) | Noise | Contrast-inv. | rho vs grade |
|---|---|---|---|---|---|
| 1 | **`varLapNorm`** | **47x** | 4.27x weak | **yes (1.000)** | 0.126 |
| 2 | **`regionMin`** | **48x** | — | — | 0.174 |
| 3 | **`tenengradVar`** | 7.3x | **0.91x best** | no | **0.067** |

These three cover each other's failure modes:

- `varLapNorm` has the best real-world spread and is immune to exposure changes,
  but is fooled by noise.
- `tenengradVar` is the only metric that noise cannot fool, covering exactly that
  gap.
- `regionMin` is the only one that sees **partial** blur — 4,100x more sensitive
  to one-sided defocus than any global metric.

All three have low disease correlation, so gating on them does not
systematically reject sick patients.

### Tier 2 — keep as classifier inputs, do not gate

| Feature | Why keep | Why not gate |
|---|---|---|
| `brenner` | rho = **-0.038**, cheapest to compute — ideal edge-device pre-check | real spread only 4x |
| `tenengrad` | rho = **0.000**, perfectly disease-blind | real spread only 6.9x |
| `varLap` | best lab range (38,731x) | redundant with `varLapNorm`; real spread only 9x |
| `sml` | scale-tunable via step `s` | rho = 0.233, spread 4.1x |
| `regionCV` | supports `regionMin` | 0.370 baseline on sharp images — needs calibration |
| `noiseSigma` | **essential** — lets the classifier separate "sharp" from "noisy" | rho = 0.354, but that is by design; it measures acquisition |

### Tier 3 — demoted

**`specSlope` — do NOT gate on this.** I previously recommended it as a primary
feature because it is contrast-invariant. Real data overruled that:

```
Spearman rho vs DR grade = 0.460     <-- the worst of any feature tested
```

It has the strongest disease/acquisition correlation of anything measured. Its
contrast invariance is real, but gating on it would reject referable-DR patients
preferentially. Keep it as one input among many; never let it decide.

> ### ⚠ CORRECTION — the rho values on this page are confounded
>
> The full 3,662-image run showed that **every** raw correlation against DR grade
> in APTOS is mediated by image format, not pathology. Stratified within format,
> all of them collapse toward zero:
>
> | Feature | rho raw | rho within-format |
> |---|---|---|
> | `tenengradVar` | 0.508 | **0.011** |
> | `specSlope` | 0.457 | **0.168** |
> | `varLapNorm` | −0.243 | **−0.014** |
> | `noiseSigma` | 0.347 | **0.004** |
>
> Two specific corrections to the tiering above:
>
> - **`specSlope` was demoted for the wrong reason.** It is format-sensitive, not
>   disease-sensitive. It is still the most format-sensitive focus metric, so
>   caution stands — but the stated justification was wrong.
> - **`tenengradVar` was promoted for the wrong reason.** Its rho = 0.067 came
>   from a 150-image sample that happened to be format-balanced. On the full
>   dataset the raw value is 0.508 — worse than `specSlope`.
>
> **Never interpret a raw correlation against grade in APTOS without stratifying
> by `width` x `height` first.** Full analysis:
> [Module1_FullDataset_Findings.md](Module1_FullDataset_Findings.md).

---

## Why lab dynamic range misled me

The single most useful thing the real-data run produced:

| Feature | Lab range (sharp / sigma=8) | **Real spread (p95/p5)** |
|---|---|---|
| `varLap` | **38,731x** | **9x** |
| `varLapNorm` | 22,547x | **47x** |
| `tenengradVar` | 202x | 7.3x |
| `regionMin` | — | **48x** |
| `brenner` | 198x | 4x |
| `sml` | 137x | 4.1x |

`varLap` won the lab test by two orders of magnitude and came **last but one** on
real images.

**Why:** the lab sweep varies only one thing — blur. Real images vary in blur
*and* exposure *and* contrast *and* noise. Because `varLap` scales as
contrast-squared, all that extra variation enters as **measurement noise**, not
signal. Normalising by `var(I)` removes it, which is why `varLapNorm` spreads 5x
wider on real data despite a smaller lab range.

**Lesson for the rest of the project:** a controlled sweep tells you a metric
*responds* to the thing you varied. Only real data tells you whether that
response survives everything else that varies at the same time. Do both.

---

## [A] geometry features

150 APTOS images. Detection rate **150/150 = 100%**.

| Feature | min | p25 | median | p75 | max | Use |
|---|---|---|---|---|---|---|
| `radius` | 207.2 | 628.8 | 1126.5 | 1292.1 | 1800.1 | scale normalisation |
| `residual` | 0.002 | 0.002 | 0.003 | 0.028 | 0.215 | **shape gate** |
| `raggedness` | 0.910 | 0.916 | 0.918 | 0.944 | 1.895 | threshold sanity / retry trigger |
| `circularity` | 0.258 | 0.970 | 1.045 | 1.099 | 1.213 | **unusable — see below** |
| `areaFrac` | 0.810 | 0.875 | 0.890 | 0.973 | 1.050 | clipping gate |
| `offset` | 0.003 | 0.021 | 0.034 | 0.080 | 0.386 | misalignment gate |
| `borderFrac` | 0.000 | 0.104 | 0.399 | 0.444 | 0.687 | fit reliability |

**`radius` spans 8.7x within one dataset** — the empirical case for
`normalizeFundus`.

**`residual` is cleanly bimodal**: median 0.003 (excellent fit) with a tail to
0.215. That separation is what makes it gateable.

**`circularity` is not.** `4*pi*A/P^2` needs a perimeter estimate; real masks have
slightly ragged boundaries; `P` is squared, so the metric collapses. A
`circularity < 0.70` gate fired on **17 of 150** images whose `areaFrac` was
0.87-1.04 — i.e. perfectly intact discs. Use `residual` instead.

### Recommended gate

```
residual   > 0.06     shape deviates from a circle
areaFrac   < 0.50     less than half the disc captured
offset     > 0.35     aperture truncated by the iris
borderFrac > 0.80     a strip, not a retina
```

Fires on **6.7%** of real images (the old circularity gate fired on 17.9%).

> **Unresolved:** all 10 rejections were grade >= 2, none grade 0 or 1. See
> [Module1_A](Module1_A_FOV_Detection.md#the-gate-skews-toward-sick-patients--unresolved).
> Do not ship this threshold until those images are reviewed by eye.

---

## [B] focus features

150 APTOS images, all normalised to R = 436 px.

| Feature | min | p5 | p25 | median | p75 | p95 | max |
|---|---|---|---|---|---|---|---|
| `varLap` | 0.0000 | 0.0001 | 0.0003 | 0.0005 | 0.0006 | 0.0009 | 0.0018 |
| `varLapNorm` | 0.0024 | 0.0097 | 0.0805 | 0.1448 | 0.2396 | 0.4536 | 0.5568 |
| `sml` | 0.0048 | 0.0062 | 0.0153 | 0.0184 | 0.0210 | 0.0256 | 0.0370 |
| `tenengrad` | 0.0007 | 0.0014 | 0.0028 | 0.0037 | 0.0054 | 0.0096 | 0.0195 |
| `tenengradVar` | 0.0002 | 0.0006 | 0.0011 | 0.0016 | 0.0025 | 0.0044 | 0.0120 |
| `brenner` | 0.0000 | 0.0001 | 0.0001 | 0.0002 | 0.0002 | 0.0004 | 0.0007 |
| `specSlope` | 0.918 | 1.736 | 2.259 | **2.741** | 3.113 | 3.634 | 8.341 |
| `noiseSigma` | 0.0001 | 0.0003 | 0.0021 | 0.0037 | 0.0045 | 0.0057 | 0.0087 |
| `regionMin` | 0.0019 | 0.0068 | 0.0461 | 0.0991 | 0.1593 | 0.3278 | 0.3875 |
| `regionCV` | 0.0542 | 0.3676 | 0.5120 | 0.6295 | 0.8011 | 1.0336 | 1.2402 |

No NaNs; no image had an empty region. `specSlope` and the region features ran
successfully on all 150.

**Calibration note:** the reference image scored `specSlope = 1.61` when sharp,
but the real-image **median is 2.74**. Real fundus photographs are meaningfully
softer than a textbook figure — so any threshold calibrated on the reference
image would reject most of the dataset. Always calibrate on real data.

---

## Disease correlation — the decisive test

Spearman rho between each feature and DR grade. A quality feature should measure
**optics**, not pathology. `|rho| > 0.3` means it is tracking disease or
acquisition, and gating on it will preferentially reject sick patients.

| Feature | rho | Verdict |
|---|---|---|
| `tenengrad` | **0.000** | perfectly disease-blind |
| `brenner` | -0.038 | excellent |
| `tenengradVar` | 0.067 | excellent |
| `varLapNorm` | 0.126 | good |
| `regionCV` | -0.155 | good |
| `regionMin` | 0.174 | good |
| `varLap` | 0.187 | acceptable |
| `sml` | 0.233 | marginal |
| `noiseSigma` | **0.354** | by design — measures acquisition; never gate |
| `specSlope` | **0.460** | **worst — do not gate** |

### Why the two outliers correlate

Both track the **APTOS acquisition confound**, not pathology:

- 48% of grade-0 images are 1050x1050 or 819x614, vs 3% of grades 2-4.
- Grade 0 median `noiseSigma` is 0.0019; every other grade is ~0.0040.

Grade-0 images largely come from a cleaner, different capture pipeline. Any
feature sensitive to acquisition will therefore correlate with grade in this
dataset.

**This matters far more for Module 3 than Module 1.** A CNN can read the format
and predict "no DR" without looking at the retina. Check that your grading
accuracy survives stratification by image dimensions.

---

## Controlled-sweep results

Reference image only; establishes *response*, not real-world discrimination.

### Blur monotonicity

| sigma | varLap | varLapNorm | SML | Tenengrad | TenengradVar | Brenner | specSlope |
|---|---|---|---|---|---|---|---|
| 0 | 4.75e-03 | 6.58e-01 | 3.30e-02 | 6.01e-02 | 5.08e-02 | 2.41e-03 | 1.61 |
| 0.5 | 1.96e-03 | 2.86e-01 | 2.15e-02 | 4.77e-02 | 4.04e-02 | 1.80e-03 | 1.73 |
| 1 | 3.34e-04 | 5.37e-02 | 7.79e-03 | 2.56e-02 | 2.13e-02 | 9.05e-04 | 2.21 |
| 2 | 3.59e-05 | 6.58e-03 | 2.78e-03 | 7.77e-03 | 5.99e-03 | 2.52e-04 | 4.01 |
| 4 | 1.88e-06 | 3.92e-04 | 8.00e-04 | 1.72e-03 | 1.17e-03 | 5.03e-05 | 10.55 |
| 8 | 1.23e-07 | 2.92e-05 | 2.40e-04 | 4.24e-04 | 2.51e-04 | 1.21e-05 | 11.71 |

All monotonic. **This is the acceptance test** — if any column is
non-monotonic, the mask was probably not eroded.

### Noise inflation (added sigma = 0.03; 1.00 = immune)

| varLap | varLapNorm | SML | Brenner | Tenengrad | **TenengradVar** |
|---|---|---|---|---|---|
| 4.72x | 4.27x | 3.86x | 1.69x | 1.31x | **0.91x** |

### Contrast invariance (image scaled to 50%)

| varLapNorm | specSlope | SML | varLap / Tenengrad / TenengradVar / Brenner |
|---|---|---|---|
| **1.000** | **1.000** | 0.500 (= c) | 0.250 (= c^2) |

### Partial blur (right half defocused)

| Measure | Sharp | Half-blurred | Change |
|---|---|---|---|
| global varLapNorm | 4.75e-03 | 3.10e-03 | **1.5x** — invisible |
| **regionMin** | 2.64e-03 | 6.42e-07 | **4,100x** |
| regionCV | 0.370 | 0.881 | 2.4x |

### Pre-smoothing is a strict trade (so don't)

| Pre-smooth sigma | Noise inflation | Dynamic range |
|---|---|---|
| 0.0 | 4.26x | 100x |
| 0.5 | 3.13x | 48x |
| 0.8 | 1.52x | 18x |
| 1.2 | 1.14x | 9x |

Roughly 1:1. Measure noise separately with `noiseSigma` instead.

### Immerkaer noise estimator accuracy

| True added noise | Estimated |
|---|---|
| 0.000 | 0.0053 |
| 0.010 | 0.0125 |
| 0.030 | 0.0312 |
| 0.060 | 0.0603 |

Near-linear. The 0.0053 floor is JPEG noise already in the source.

---

## Code-path coverage

Which branches of `detectFOV` actually executed across 150 images:

| Path | Times fired |
|---|---|
| `imopen` removed pixels | 331 |
| border points excluded from fit | 296 |
| outlier reweight dropped points | 203 |
| `imfill` filled holes | 175 |
| `bwareafilt` had >1 component | 139 |
| **raggedness retry triggered** | **29** |
| retry accepted (was better) | 26 |
| guard: R out of range | 4 |
| guard: mask > 98% of frame | 3 |
| retry: Otsu failed outright | 2 |

**Untested paths — no real image exercised these:**

- `fallback: red channel degenerate` (red-free / pre-processed input)
- `guard: circle fit exception`
- `guard: too few boundary points`
- `fallback: kept border points` (when <50 free arc points survive)
- `guard: empty after threshold`

These need **synthetic test cases**, not more real images — construct a red-free
image, a 10-pixel blob, an all-black frame, and assert `fov.ok == false` with no
crash.

**Notable:** the raggedness retry fired on **29/150 = 19%**. Otsu is unreliable on
roughly one real fundus image in five.

---

## MATLAB status

**BLOCKED — the required toolboxes are not installed.**

MATLAB R2026a is present at `C:\Program Files\MATLAB\R2026a`, but a directory
listing of `toolbox/` shows base MATLAB, Simulink, Coder and Compiler only:

| Toolbox | Directory | Status |
|---|---|---|
| Image Processing | `toolbox/images` | **MISSING** |
| Statistics and Machine Learning | `toolbox/stats` | **MISSING** |
| Computer Vision | `toolbox/vision` | **MISSING** |
| Deep Learning | `toolbox/nnet` | **MISSING** |
| Simulink | `toolbox/simulink` | present |

First execution attempt failed accordingly:

```
Undefined function 'graythresh' for input arguments of type 'double'.
Error in detectFOV (line 55)
```

### What this blocks

Essentially all of Modules 1-4. Functions used by the current code alone:
`graythresh`, `imfill`, `bwareafilt`, `imopen`, `strel`, `imerode`,
`imgradient`, `imgaussfilt`, `imfilter`, `fspecial`, `bwboundaries`,
`regionprops`, `imresize`, `padarray` — all Image Processing Toolbox.

Later stages additionally need Statistics and ML (`fitcensemble`, `perfcurve`,
`corr`, `prctile`), Deep Learning (`trainnet`, `gradCAM`, `imagePretrainedNetwork`)
and Computer Vision.

**Only Module 5 (Simulink) can proceed on the current installation** — and even
that wants SimEvents, which should be checked separately.

### How to install

In MATLAB: **Home tab -> Add-Ons -> Get Add-Ons**, then search and install each
toolbox. This requires a licence that covers them.

Check licence entitlement first:

```matlab
license('test','Image_Toolbox')       % 1 = licensed
license('test','Statistics_Toolbox')
license('test','Video_and_Image_Blockset')   % Computer Vision
license('test','Neural_Network_Toolbox')     % Deep Learning
```

A university Campus-Wide licence normally covers all of these. A Student or Home
licence may require them to be bought separately.

### Impact on the work so far

**None of the analysis is invalidated.** Every measurement in this document came
from a Python reference implementation running the identical algorithms, and the
150-image APTOS validation stands.

What is *not* verified is the **MATLAB transcription** — syntax, function-default
differences (`imgradient` method, `hann` vs `hanning`, `accumarray` semantics,
`bwboundaries` output shape). Expect to fix a handful of small errors on first
successful run.

Verify with, in order:

```matlab
test_module1          % smoke test + blur sweep, one image
benchmarkModule1(...) % full 150-image validation
```

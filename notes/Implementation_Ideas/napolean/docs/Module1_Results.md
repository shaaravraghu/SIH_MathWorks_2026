# Module 1 — Measured Results

What the features actually do, measured on the **full APTOS training set**
(3,662 images; `fov_ok` on 3,660 = 99.95%).

Source: [`data/aptos_train_module1_features.csv`](../../../../data/aptos_train_module1_features.csv).
Stage detail: [[A]](Module1_A_FOV_Detection.md) · [[B]](Module1_B_Focus_Metrics.md) · [[C]](Module1_C_Illumination.md)

> **[C] backfill complete.** All figures below are from the full 3,662 rows
> (`data/aptos_train_module1_features_conly.csv`, 3,659 with valid [C]).

---

## Read this first — the acquisition confound

APTOS images come in **18 resolutions, and resolution is confounded with grade**:

```
1050x1050   n=974   grades [901, 19, 39,  2, 13]   <- 92% grade 0
2416x1736   n=638   grades [ 31,234,233, 60, 80]   <-  5% grade 0
3216x2136   n=409   grades [  2, 13,306, 32, 56]   <-  0.5% grade 0
```

**Resolution alone predicts referable (grade >= 2) at 82.3% accuracy**, against a
59.4% base rate. Different cameras photographed different populations.

So a raw Spearman rho against `diagnosis` mostly measures *which camera took the
picture*. Every number below is therefore given twice: naive, and re-measured
**within a fixed resolution**. Only the second column is meaningful.

**Consequence:** the [A] gate is not inherently biased against sick patients —
it is biased against *the cameras that photographed sick patients*. Different bug,
different fix (stratify or normalise per acquisition), and much better news.

**This is a Module 3 problem too.** A CNN will happily learn image dimensions.

---

## [A] Field-of-view detection

| Algorithm | rho all | rho within-res | Verdict |
|---|---|---|---|
| **Kasa circle fit** → `radius` | 0.603 | 0.00–0.17 | **best in Module 1** |
| → `offset` | 0.610 | 0.04–0.14 | safe once stratified |
| → `areaFrac` | 0.564 | 0.00–0.15 | safe once stratified |
| → `borderFrac` | 0.531 | 0.01–0.19 | safe once stratified |
| → `residual` | 0.433 | 0.03–0.14 | safe; 41.9x spread |
| Otsu + largest-component + fill | — | — | 99.95% success |

**Why it wins:** one backslash, no iteration, no initial guess — and it worked on
3,660 of 3,662 images. Every downstream stage consumes its mask, and it
essentially never fails, because the FOV boundary is an *aperture*, not an optical
feature of the retina. Defocus, underexposure and cataract cannot remove it.

**The apparent disease bias is ~90% confound.** `offset` drops from 0.610 to 0.043
within a single resolution.

> `circularity` (rho 0.573, bimodal) is genuinely useless. `residual` replaced it
> as the shape feature.

---

## [B] Focus & sharpness

| Algorithm | rho all | rho within-res | Spread | Verdict |
|---|---|---|---|---|
| **`regionMin`** (per-region minimum) | 0.059 | **0.004–0.090** | 21.3x | **best feature** |
| **`varLapNorm`** (contrast-normalised) | 0.243 | 0.057–0.118 | 15.5x | safe, discriminative |
| `sml` (Modified Laplacian) | 0.051 | — | 4.4x | safe, low spread |
| `tenengradVar` | 0.508 | 0.013–0.167 | 10.6x | mostly confound; OK |
| `varLap` | 0.323 | — | 13.1x | redundant with `varLapNorm` |
| `brenner` | 0.365 | — | 5.4x | cheap pre-check only |
| `noiseSigma` | 0.347 | — | 12.2x | confounder input, never gate |
| **`specSlope`** | 0.457 | **0.130–0.336** | 2.3x | **never gate — see below** |
| `regionCV` | 0.000 | 0.051–0.250 | 4.3x | weaker than `regionMin` |

**Why `regionMin` wins:** the most consistently disease-blind number measured —
0.004 / 0.070 / 0.004 / 0.090 across four independent resolutions — with 21.3x
spread. It costs one line over the global mean and catches partial blur (camera
tilt, one-sided defocus) that every global metric is blind to.

### Two corrections to earlier drafts

**`regionCV`'s rho of 0.000 is a coincidence.** Within-resolution it is
0.051–0.250 — *worse* than `regionMin`. The overall zero came from cancellation
across strata. A stratified check would have caught it; an unstratified one did not.

**`specSlope` is genuinely disease-correlated, not merely confounded.** It stays
at 0.130–0.336 *within* a fixed camera — the only feature that survives
stratification with substantial correlation intact. It really is measuring
lesions, because a diseased retina has different frequency content. **Input only.**

---

## [C] Illumination, exposure & contrast

Recomputed on all 3,659 valid rows across **six** strata (n >= 150 each).
`max|rho|` is the worst single stratum — a feature is gate-safe only if it passes
**everywhere**, not on average.

| Algorithm | rho all | 1050² | 2416 | 2588 | 3216 | 819 | max\|rho\| | Verdict |
|---|---|---|---|---|---|---|---|---|
| **`bgRadial`** (vignetting) | −0.337 | −0.034 | −0.075 | 0.038 | 0.004 | 0.038 | **0.075** | **best in [C]** |
| **`bgTiltMag`** (LS plane fit) | −0.186 | 0.035 | 0.052 | −0.095 | −0.046 | −0.076 | **0.095** | safe; gives retake direction |
| **`bgSpread`** (field p95−p5) | −0.005 | 0.035 | 0.113 | −0.069 | 0.036 | −0.107 | **0.113** | safe |
| **`bgCV`** (median field) | 0.317 | 0.129 | 0.041 | −0.069 | 0.039 | 0.102 | **0.129** | safe |
| `localContrastP10` | −0.504 | −0.021 | −0.064 | 0.131 | 0.108 | −0.164 | 0.164 | caution |
| `bgMean` | −0.232 | −0.238 | 0.107 | −0.106 | −0.101 | −0.195 | 0.238 | caution |
| **`localContrast`** (`stdfilt`) | −0.107 | 0.038 | **0.250** | −0.164 | 0.067 | −0.051 | **0.250** | **never gate** |
| **`colorSat`** | −0.140 | 0.276 | −0.024 | **0.500** | 0.049 | 0.039 | **0.500** | **never gate** |
| **`sat_G`** (clipping count) | 0.294 | — | — | — | — | — | — | only irreversible-damage measure |
| `sat_R` | 0.390 | — | — | — | — | — | — | high is **normal** |

Cost: **median 409 ms/image**, p95 865 ms — comparable to [B]. [C] is not free.

**Why the background-field family wins:** `bgRadial`, `bgTiltMag`, `bgSpread` and
`bgCV` describe the *illumination field* rather than retinal content, so they are
close to disease-blind by construction. All four clear 0.15 in every stratum.
They are the safest gating candidates in Module 1.

### Two verdicts changed when the backfill completed

The 2,464-row draft had `localContrast` at 0.009–0.197 ("acceptable") and
`localContrastP10` at 0.026–0.132 ("OK"). On the full set:

- **`localContrast` → never gate.** It reaches **0.250** at 2416×1736. Local
  contrast responds to lesion texture — exudates have sharp edges, haemorrhages
  soft ones — so a diseased retina genuinely has different `stdfilt` statistics.
- **`localContrastP10` → caution.** 0.164 at 819×614, over the 0.15 line.

`colorSat` is confirmed as the worst: **0.276 / −0.024 / 0.500** across three
cameras. It is not measuring the same physical quantity in each — not merely
noisy, but inconsistent in sign and magnitude.

> `2048x1536` (n=351) is excluded from the stratified columns: it is ~99% grade 0,
> so within-stratum correlation is undefined. That is itself a symptom of the
> acquisition confound.

**Why per-channel saturation matters:** across 3,662 images, `sat_R` median is
**0.0086** while `sat_G` median is **exactly 0.0**. The fundus is red-dominant, so
red clips routinely and harmlessly — red is only used for FOV detection. Green
clipping destroys the lesion signal Module 2 depends on. A single grayscale
saturation feature cannot tell these apart. Predicted in the docs, confirmed at
scale.

---

## Ranking

| # | Algorithm | Stage | Reason |
|---|---|---|---|
| 1 | **Kasa circle fit** | [A] | 99.95% success, one backslash, everything depends on it |
| 2 | **`regionMin`** | [B] | most consistently disease-blind (0.004–0.090), 21.3x spread, one line |
| 3 | **Background field (median)** | [C] | `bgRadial` (max 0.075) / `bgTiltMag` (0.095) — disease-blind by construction |
| 4 | **`varLapNorm`** | [B] | contrast-invariant, 15.5x spread, safe |
| 5 | **Per-channel saturation** | [C] | trivially cheap; the only irreversible-damage measure |

## Never gate on

`colorSat` (0.500 worst stratum) · `localContrast` (0.250) · `specSlope`
(0.130–0.336 within-camera) · `noiseSigma` (confounder by design) ·
`circularity` (bimodal, useless)

## Gate-safe set (max\|rho\| < 0.15 in every stratum)

`bgRadial` 0.075 · `bgTiltMag` 0.095 · `regionMin` 0.090 · `bgSpread` 0.113 ·
`bgCV` 0.129 · `varLapNorm` 0.118 · `residual` 0.14

---

## From feature to retake message

The point of Module 1 is not a quality *score* — it is an **actionable
instruction**. "Bad image" is worthless to a technician; "too dark, increase
flash" is not. Every feature below maps to a specific physical cause and a
specific thing to do about it.

### Retake will fix it

| Condition | What physically happened | Tell the technician |
|---|---|---|
| `fov_ok = 0` | no retina found at all | *"No retina detected — is the lens cap off and the camera aimed at the eye?"* |
| `offset` > 0.35 | camera off-axis; retina displaced in frame | *"Recentre — the retina sits &lt;dir&gt; of centre."* `atan2` of the centre offset gives &lt;dir&gt; |
| `radius` < 0.15·min(W,H) | camera too far from the eye | *"Move closer."* |
| `areaFrac` < 0.50 | over half the disc is off-sensor | *"Retina partly out of frame — recentre and move back slightly."* |
| `residual` > 0.06 | rim deformed by an intrusion | *"Something is blocking the edge — check eyelid and lashes."* |
| `varLapNorm` low, `noiseSigma` low | genuine defocus | *"Out of focus — refocus."* |
| `regionMin` low, global normal | one-sided defocus from tilt | *"One side is soft — hold the camera square to the eye."* |
| `bgMean` low | underexposed | *"Too dark — increase flash."* |
| `sat_G` > 0.05 | green channel clipped | *"Too bright — reduce flash."* |
| `bgTiltMag` high | beam entering off-axis | *"Illumination uneven — shift the camera &lt;dir&gt;."* `bgTiltDir` gives &lt;dir&gt;; calibrate the sign once on your own rig |
| `bgCV` high | uneven lighting across the field | *"Lighting uneven — recentre and retake."* |
| `noiseSigma` high, `bgMean` low | too little light, sensor gain compensating | *"Grainy — increase illumination, don't just brighten."* |

### Retake will NOT fix it

| Condition | What physically happened | Tell the technician |
|---|---|---|
| `bgMean` normal/high **and** `localContrast` low **and** `colorSat` low | scattered light from media opacity | *"Media opacity suspected — may be ungradable regardless of technique. Refer for cataract assessment."* |
| `bgRadial` very steep | small pupil clipping the beam | *"Consider dilation."* — a patient factor, not a technique fault |
| `sat_G` high **and** already retaken | sensor/flash ceiling on a reflective fundus | escalate; reducing flash further will underexpose |

This distinction is the clinically important one. Telling a cataract patient to
retake five times wastes everyone's time and still produces an ungradable image.

### No instruction — classifier input only

`specSlope` · `noiseSigma` (alone) · `borderFrac` · `sat_R` · `localContrast` ·
`colorSat` · `bgSpread` · `circularity`

These either measure a confounder, describe fit *reliability* rather than image
quality, or are normal-but-informative. They contribute to [E]'s verdict; none of
them names a thing the technician can change.

> **`borderFrac` is the classic trap.** A perfectly ordinary 4:3 capture reads
> ~0.47 because the circle naturally touches top and bottom. It is a fit-
> reliability signal, not a fault.

---

## Speed — measured per stage

AMD Ryzen 5 7535U (6C/12T, 2.9 GHz), single-threaded, median of 5 images per format.

| Format | MP | decode | [A] @½ | exposure | normalise | [B] | **total** |
|---|---|---|---|---|---|---|---|
| 1050×1050 | 1.1 | 67 | 116 | 29 | 38 | **323** | 573 ms |
| 2416×1736 | 4.2 | 212 | 433 | 148 | 39 | 349 | 1,180 ms |
| 3216×2136 | 6.9 | 334 | **695** | 219 | 43 | 315 | 1,606 ms |
| 3388×2588 | 8.8 | 463 | **936** | 271 | 49 | 338 | 2,057 ms |

**[B] is constant at ~330 ms** — it runs on the normalised 872×872 image whatever
the source size. Everything else scales with megapixels.

So the bottleneck **flips with image size**: at 1.1 MP [B] is 56% of cost; at
8.8 MP [A] is 45% and [B] only 16%. Optimise accordingly — there is no single
hot spot.

Full-run figures over 3,660 images:

| | |
|---|---|
| median | **1,173 ms/image** |
| p95 | 2,523 ms |
| throughput | **0.85 img/s ≈ 3,070 images/hour** |
| total wall clock | 237 min |

> The 3,877 ms *mean* in the raw CSV is meaningless — one image logged 9,395 s
> because the machine stalled under memory pressure. **Always use the median.**

### Where [B]'s 330 ms actually goes

| Piece | ms |
|---|---|
| `ndi.laplace` | 12.9 |
| `sobel` ×2 | 17.8 |
| `specSlope` (FFT) | 25.1 |
| Immerkær convolve | 10.5 |
| 5-region masks + var | 31.5 |
| **sum of the above** | **~98** |

The components total ~98 ms but the stage takes 324 ms. The missing 226 ms is
**repeated boolean indexing** — every `J[M]` copies 573k floats and there are
~15 such reductions.

**The highest-value optimisation is to extract `J[M]` once and reuse it**, not to
sample fewer pixels. Five-line change, worth more than any sampling scheme.

### ⚠ Correction: ring sampling gives 1.21×, not 4.9×

Measured across all ten metrics on a normalised image:

```
full mask  573,589 px    324.4 ms
ring mask  119,504 px    267.5 ms      1.21x
```

The earlier 4.9× figure came from a benchmark that **cropped boxes and filtered
only inside them**. `focusMetrics.m` instead builds a mask and filters the whole
image (`laplace`, `sobel`, `convolve` all touch every pixel), so the mask saves
only the *reduction*, not the *filtering*.

**The MATLAB implementation as written cannot deliver the speedup its own
docstring claims.** Either rewrite it to crop-and-filter per patch, or drop the
claim. The earlier "saves 0.5% of runtime" estimate was also wrong — it used the
single-metric cost (26 ms) rather than the full stage cost (324 ms).

---

## CSV health

`data/aptos_train_module1_features.csv` — **usable, with 26 known-bad rows, all
correctly flagged.**

| | |
|---|---|
| Rows × columns | 3,662 × 53 (1.4 MB) |
| Duplicate `id_code` | 0 |
| Non-finite values | **none** |
| Missing | 1–2 rows per column — exactly the 2 `MemoryError` images |
| `gate_reason` blank | 3,385 — correct, those were not rejected |

### Sanity violations — all the same root cause

| Column | Range found | Violations |
|---|---|---|
| `offset` | 0.001 – **6.58** | 22 |
| `retina_pct` | **1.26** – 94.86 | 21 below 5% |
| `areaFrac` | **0.043** – 1.08 | 4 |
| `radius` | **44.4** – 1799.6 | 1 |

An `offset` of 6.58 places the fitted centre 6.6 radii from the frame centre —
nonsense. These are **26 catastrophic failures where a small bright blob was
picked instead of the retina**, and nearly all are the **2588×1958** format
(radius 141–208 px inside a 2588-px-wide image).

**All 26 carry `gate_reject = 1`.** The safety net works. But it shows the
2588×1958 problem is worse than elevated `residual`: on ~0.7% of images the
detector locks onto entirely the wrong object.

### Recommended filter

```python
clean = df[(df.fov_ok == 1) & (df.gate_reject == 0)]   # 3,383 rows
```

The two `MemoryError` images (`e868c3da340b`, `e8d1c6c07cf2`) failed allocating
78.6 MB and 5.8 MB on a machine at 97% utilisation — **not** algorithm failures.
The extractor is resumable; re-running picks them up.

---

## Before trusting any threshold

```python
# stratify — an unstratified rho is mostly measuring the camera
for res, grp in df.groupby(df.width.astype(str) + "x" + df.height.astype(str)):
    if len(grp) < 60: continue
    print(res, grp[FEATURES].corrwith(grp.diagnosis, method="spearman").abs().round(3))
```

A feature is only gate-safe if `|rho| < 0.15` in **every** stratum, not on average.
`regionCV` passes the average test and fails the per-stratum one.

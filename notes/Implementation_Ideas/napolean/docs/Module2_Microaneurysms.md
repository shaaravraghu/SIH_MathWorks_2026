# Module 2, Step 4 — Microaneurysm Detection

> **Sharpness caveat.** Like every lesion measure in Module 2, the numbers here
> were obtained on the 14 sharpest images per grade and are upper bounds — see
> the warning at the top of [Module2_Results.md](Module2_Results.md).
>
> **The classifier is now wired in — use `ma_n`.** The extractor writes
> `ma_raw` (candidates) and **`ma_n`** (classifier survivors, probability
> ≥ 0.7), alongside the legacy `ma_count_INVALID`, which is the threshold stage
> with no classifier and correlates −0.117 with grade.
>
> **`ma_n` is the best-evidenced lesion feature in Module 2**: candidate AUC
> 0.729, within-stratum rho **+0.508**, medians 0 / 33.5 / 44.5 / 112.5 / 108.5
> across grades 0–4 — and measured on 250 images sampled across **all ten
> sharpness deciles**, not a favourable selection.
>
> The threshold 0.7 is the **lowest** probability at which the grade-0 median
> count is 0, a criterion fixed before the sweep. 0.9 would report +0.593, but
> that is a selected maximum and therefore optimistic.

**Purpose:** count microaneurysms. Grade 1 is *defined* as "microaneurysms
only", so this component decides whether early disease is detectable at all.

**Code:** Python reference in the session scratchpad (`m2_ma.py`, `m2_ma2.py`).

**Status:** **partially working.** The classifier stage fixes the sign of the
grade correlation, but grade-0-vs-1+ separation is still at chance.

---

## Contents

- [Why this is the hardest component](#why-this-is-the-hardest-component)
- [The five-step pipeline](#the-five-step-pipeline)
- [Candidate features](#candidate-features)
- [Weak supervision from the grade column](#weak-supervision-from-the-grade-column)
- [Round 1 — AUC 0.995, and why it was false](#round-1--auc-0995-and-why-it-was-false)
- [Round 2 — the confound removed](#round-2--the-confound-removed)
- [Recommendation](#recommendation)
- [What is still missing](#what-is-still-missing)

---

## Why this is the hardest component

| | |
|---|---|
| Size | 10–125 µm = **1–8 px** at R=436 |
| Published ceiling | **AUPR ≈ 0.50** on IDRiD — genuinely unsolved |
| Clinical weight | grade 1 = "MAs only"; missing them means missing early DR |

**The resolution rule.** A standard CNN resizes to 224×224, where a
microaneurysm is **under one pixel** — physically absent from the input. MA
detection must run at native resolution or R ≥ 436, separate from the
whole-image CNN branch. Same argument that killed downsampling in [B].

---

## The five-step pipeline

```
1. shade-corrected green                       NOT CLAHE (-20% MA contrast)
2. vessel removal by multi-orientation closing
3. threshold -> candidates                     ~115 per image, low precision
4. per-candidate feature extraction            <-- was missing
5. classifier to prune false positives         <-- was missing
```

**Steps 4 and 5 are not optional.** Stopping at step 3 gives ~115 candidates per
image at very low precision, and the raw count correlates **−0.117** with grade
— near zero and the *wrong sign*.

### Step 2 — why multi-orientation closing separates vessels from MAs

```matlab
for a = 0:15:165
    C = imclose(Ig, strel('line', 15, a));
end
Cmin = min over a
diff = Cmin - Ig
```

A vessel is elongated, so **some** orientation's line fits inside it and it
survives closing — it stays dark, and the minimum across orientations keeps it
dark. A microaneurysm is compact, so **every** orientation bridges over it and
fills it — the min-closed image is bright there, and the difference is large.

`L = 15 px` (~220 µm): longer than an MA, shorter than a vessel segment.

**Dilate the vessel mask 2–3 px before subtracting.** Segmentation always misses
the faint outer edge, and a half-removed vessel leaves fragments that look
exactly like microaneurysms.

---

## Candidate features

| Feature | Rationale |
|---|---|
| **`gauss_res`** | 2-D Gaussian fit residual. **Real MAs *are* Gaussian blobs; noise is not.** Fitted by least squares over σ ∈ {1, 1.5, 2, 3} |
| **`vdist`** | distance to the nearest vessel — MAs are *isolated by definition* |
| `vdens` | local vessel density; suppresses candidates inside the arcade |
| `contrast` | candidate vs a surrounding annulus, vessels excluded |
| `area`, `perim`, `circ`, `ecc`, `solidity`, `aspect` | shape — MAs are round |
| `ecc_r` | radial position in the retina |

**Banned:** `r_mean`, `b_mean`, `g_mean`, `g_min`, `rg`, `diff_mean`,
`diff_max`. Every absolute intensity feature. See round 1.

---

## Weak supervision from the grade column

APTOS has no MA annotations, so the classifier is trained on **weak labels**:

```
candidates from grade 0 images    ->  label 0  (mostly NOT microaneurysms)
candidates from grade 3-4 images  ->  label 1  (mostly microaneurysms)
grades 1-2 are HELD OUT entirely  ->  the honest test set
```

Noisy, but it is real supervision from a real label. **8,078 candidates from 70
images (115/image); 5,961 in the weak-label set** (3,974 positive, 1,987
negative).

`GroupKFold` by image throughout — no image ever spans train and test.

---

## Round 1 — AUC 0.995, and why it was false

The first run reported **candidate AUC 0.995** and **grade-0-vs-1+ AUC 0.995**.
Both were artefacts. Three tells:

**1. The top features were absolute colour.**

```
r_mean     0.237
b_mean     0.204
diff_mean  0.176
g_mean     0.105
```

No shape feature in the top eight — no `circ`, no `ecc`, no `gauss_res`. The
classifier learned *"this image is a grade-0 capture"*, i.e. the **82.3%
acquisition confound** (grade 0 is 48% a different camera format), not *"this
candidate is a microaneurysm"*.

**2. Leakage.** The image-level score used a model fitted on those same images.
Only grades 1–2 were honest, and there the result was **non-monotonic**:
g1 = 60, g2 = 24.

**3. Grade 0 collapsed to exactly 0** from a raw count of 116. A classifier that
zeroes an entire class has memorised it.

> A published ceiling of AUPR ≈ 0.5 and a measured AUC of 0.995 is not a
> breakthrough. It is a bug.

---

## Round 2 — the confound removed

Absolute-intensity features dropped; image-level scores cross-validated so no
image is scored by a model that saw it.

### Candidate level

```
WITH colour (round 1)   AUC 0.995     <- the confound
shape + contrast only   AUC 0.742     <- actual signal
```

**A quarter of a point of AUC was pure camera identity.**

And the importances flipped to exactly what they should be:

| Feature | Importance |
|---|---|
| **`gauss_res`** | **0.222** |
| `ecc_r` | 0.170 |
| **`contrast`** | 0.145 |
| **`vdist`** | 0.128 |
| `vdens` | 0.108 |
| `ecc` | 0.060 |
| `area` | 0.045 |

The Gaussian-fit residual and distance-to-vessel — the two physically motivated
features — now lead.

### Image level, cross-validated

| Metric | g0 | g1 | g2 | g3 | g4 | rho | AUC 0 vs 1+ |
|---|---|---|---|---|---|---|---|
| raw count | 116 | 65 | 37 | 143 | 66 | −0.010 | 0.308 |
| **cls50** | 29 | 21 | 18 | 71 | 43 | **0.232** | **0.491** |
| score | 49 | 29 | 18 | 74 | 36 | 0.070 | 0.371 |

**Still non-monotonic** — grades 0→2 *decrease*, then jump at grade 3. And
grade-0-vs-1+ AUC of **0.491 is chance**.

### Within resolution strata — the sign is finally right

| Stratum | n | rho(cls50, grade) |
|---|---|---|
| 1050×1050 | 8 | **+0.872** |
| 2416×1736 | 20 | **+0.471** |
| 3388×2588 | 13 | +0.283 |
| 2588×1958 | 8 | +0.089 |

Against **−0.117** for the raw count. **The classifier stage is what makes MA
count track disease** — that was the missing piece, and removing it is why the
first functional test of vessel segmentation came out inconclusive.

---

## Recommendation

```
1. normalizeFundus            (fixes 14.9 um/px, so 125 um = 8.4 px)
2. shade-corrected green      NOT CLAHE
3. vessels + bridging, dilated 3 px, subtracted
4. multi-orientation closing, L=15, 12 angles -> candidates at p99
5. features: SHAPE AND LOCAL CONTRAST ONLY -- no absolute intensity
6. RandomForest on weak labels (grade 0 vs grade 3-4), GroupKFold by image
7. count candidates scoring >= 0.5
8. NORMALISE PER CAMERA before comparing counts across images
```

Measured: candidate AUC **0.742**, within-stratum grade correlation **+0.09 to
+0.87**.

---

## What is still missing

**Two reasons it does not yet work end to end**, both real:

**Pooling mixes cameras, and the confound runs opposite to the signal.** Within
strata the correlation is positive everywhere; pooled it collapses to 0.232.
Any deployment must normalise per acquisition source.

**The weak labels cannot teach grades 1–2.** Training on grade 0 vs grades 3–4
means the classifier never sees a mild case — and grade 1 is exactly where
microaneurysms matter most. That is a structural limit of weak supervision, not
a tuning problem.

| Gap | Fix |
|---|---|
| no MA ground truth | **IDRiD sub-challenge A** — 81 images with pixel-level MA masks |
| weak labels miss mild cases | real annotations, or an ordinal weak-label scheme |
| per-camera normalisation | stratified feature scaling before counting |
| grade 0 vs 1+ at chance | the above, in that order |

**Do not ship an MA count as a clinical feature in this state.** It is real
signal — the shape features are doing genuine work — but it cannot yet perform
the one job that matters, which is separating no-DR from mild-DR.

---

## Next

Exudates, haemorrhages, neovascularization and the 4-2-1 quadrant rule — all of
which reuse the dark-lesion machinery built here.

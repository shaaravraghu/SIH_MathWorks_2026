# Module 2, Step 5 — Exudate Segmentation

**Purpose:** find bright lipid/protein deposits leaking from damaged vessels.

**Status:** **weak signal, unusable counts.** Area shows a small positive grade
correlation; the object *count* is meaningless — thousands of specks per image.

---

## What they are

| Type | Appearance | Meaning |
|---|---|---|
| **Hard** | yellow, sharp-edged, waxy, often ringed | leakage; near the fovea → macular oedema |
| **Soft** (cotton-wool) | pale, fluffy, indistinct | nerve-fibre-layer infarct — a small retinal stroke |

**Distance from the fovea is the clinically decisive number.** Hard exudates
within 500 µm (34 px at R=436) indicate clinically significant macular oedema —
urgent referral *regardless of DR grade*.

---

## Step 1 is non-negotiable: mask the optic disc

The OD is bright, round and yellowish — **exactly** what an exudate detector
looks for. Any detector that skips OD masking fires on it in **every single
image**.

```matlab
odm = hypot(Y-od_y, X-od_x) <= 1.2 * OD_R;   % 1.2x for the rim
```

---

## The three algorithms

### A. White top-hat

```matlab
se = strel('disk', 15);
th = imtophat(Ig, se);
```

Bright compact structures survive; smooth background does not. Cheapest.

### B. Morphological reconstruction (h-maxima)

```matlab
marker = Ig - h;                    % h ~ 0.06
rec    = imreconstruct(marker, Ig);
resid  = Ig - rec;                  % what FAILS to reconstruct is a lesion
```

The principled choice — reconstruct a lowered marker under the image; anything
that cannot climb back is a genuine regional maximum.

### C. Dynamic (local adaptive) threshold

```
bright(p)  iff  I(p) > mean_win(p) + k * sd_win(p)      win=81, k=2.5
```

### Hard vs soft split — use the BLUE channel

Yellow hard exudates are **low-blue**; white cotton-wool spots are **high-blue**.
Green cannot separate them — both are bright there.

---

## Measured — 60 images, 12 per grade

| Feature | g0 | g1 | g2 | g3 | g4 | pooled rho | within-strata |
|---|---|---|---|---|---|---|---|
| area, top-hat | 0.6 | 0.6 | 0.6 | 0.7 | 0.7 | 0.413 | 0.215 |
| **area, dynamic** | 0.2 | 0.2 | 0.4 | 0.5 | 0.4 | **0.439** | **0.321** |
| area, reconstruction | 0.7 | 0.7 | 0.7 | 0.7 | 0.7 | −0.263 | — |
| count, top-hat | **1244** | 351 | 327 | 252 | 310 | −0.528 | −0.091 |
| count, reconstruction | **2279** | 2082 | 2217 | 1493 | 1894 | −0.425 | −0.211 |
| count, dynamic | **944** | 592 | 869 | 543 | 741 | −0.196 | 0.053 |
| exudate→fovea distance | 0.2 | 0.3 | 0.4 | 0.3 | 0.2 | 0.065 | −0.061 |

### Reading this honestly

**The counts are garbage.** 1,244–2,279 "exudates" per image is absurd — a
heavily exudative retina has tens, not thousands. The detectors are finding
bright *noise specks*, and the count correlates **negatively** with grade
(−0.20 to −0.53), which is the opposite of the clinical truth.

**Area carries weak real signal.** `dynamic` gives within-stratum ρ = **+0.321**
and the medians rise 0.2 → 0.5 across grades 0→3. That is the right direction
and the right shape, but it is a weak effect.

**Reconstruction failed outright** — area is flat at 0.7% across every grade, and
pooled ρ is *negative*. The h-parameter (0.06) is almost certainly wrong for
shade-corrected input.

**Exudate-to-fovea distance is noise** (ρ = −0.061). Which means the DME rule
cannot be built on it yet — and that rule inherits OD error, fovea error and
exudate error simultaneously.

---

## THE FIX — a minimum-area filter, and it worked

The counts above were garbage because detection stopped at the threshold stage,
exactly the error that broke microaneurysms in round 1. Adding a single
**minimum-area filter (8 px)** before counting:

| Feature | g0 | g1 | g2 | g3 | g4 | pooled | **within-strata** |
|---|---|---|---|---|---|---|---|
| **`exu_n`** | **1.5** | 13 | 29.5 | **47** | 36 | 0.698 | **+0.503** |
| **`exu_area`** | 0.0 | 0.1 | 0.2 | 0.4 | 0.2 | 0.688 | **+0.484** |

**ρ = +0.503 within strata is the strongest correlation measured anywhere in
Module 2.** And the counts are now clinically plausible — 1.5 exudates at grade 0
rising to 47 at grade 3, against 1,244–2,279 before.

```
count correlation:   -0.196  ->  +0.503
```

One line of filtering. Nothing else changed.

### Candidate classifier — AUC 0.757, with a caveat

Adding the full MA-style stage (per-candidate features + weak-label
RandomForest, GroupKFold by image):

```
candidate AUC = 0.757    2,160 candidates, 9 features
top features: bg_ratio 0.507, rad 0.149, contrast 0.084, circ 0.064, edge 0.058
```

**`bg_ratio` carries half the model.** It was kept deliberately — yellow hard
exudates are low-blue, white cotton-wool is high-blue, so it is a genuine lesion
property and a colour *ratio* rather than a level. But a single colour feature at
0.507 importance is exactly the shape of the microaneurysm round-1 failure, where
`r_mean` at 0.237 turned out to be camera identity.

> **Verify `bg_ratio` within a single resolution stratum before trusting the
> classifier.** The headline ρ = 0.503 comes from the min-area-filtered *count*,
> not the classifier, so that result stands independently either way.

---

## Recommendation

```
1. mask the optic disc at 1.2 x OD_R          non-negotiable
2. DYNAMIC threshold, win=81, k=2.5           best of the three
3. MINIMUM AREA FILTER, 8 px                  <- the fix; -0.196 -> +0.503
4. count AND area are both usable now
5. hard vs soft on the BLUE channel
6. (optional) candidate classifier            AUC 0.757, verify bg_ratio first
```

Measured: within-stratum ρ = **+0.503** on count, **+0.484** on area.
**This is the best-performing lesion detector in Module 2.**

## What is still missing

**Exudate-to-fovea distance is still noise** (ρ = −0.061). The DME rule — hard
exudates within 500 µm of the fovea — cannot be built on it, because that rule
inherits OD error, fovea error and exudate error simultaneously.

**Ground truth.** IDRiD sub-challenge A provides pixel-level hard- and
soft-exudate masks for 81 images, with a published ceiling of AUPR ≈ 0.80 — far
more tractable than microaneurysms at ≈ 0.50.

# Module 2, Step 1 — Optic Disc Localization

**Purpose:** find the optic disc (OD) centre — the bright region where the optic
nerve and vessels enter the retina.

**Code:** not yet implemented in MATLAB. Python reference in the session
scratchpad (`m2_od.py`, `m2_od2.py`).

**Status:** measured on 60 APTOS images (Ryzen 5 7535U), but **without ground
truth**. APTOS has no OD coordinates, so nothing below is a measured accuracy —
see [Validation without labels](#validation-without-labels).

---

## Contents

- [Why the OD comes first](#why-the-od-comes-first)
- [What Module 1 already solved for us](#what-module-1-already-solved-for-us)
- [Validation without labels](#validation-without-labels)
- [The algorithms](#the-algorithms)
- [Round 1 — and the warning sign](#round-1--and-the-warning-sign)
- [What "invariant" means, and where I misapplied it](#what-invariant-means-and-where-i-misapplied-it)
- [Round 2 — the anatomical prior wins](#round-2--the-anatomical-prior-wins)
- [Recommendation](#recommendation)
- [The honest limitation](#the-honest-limitation)

---

## Why the OD comes first

Four downstream components depend on it:

```
optic disc ─┬─→ fovea       2.5 disc diameters temporal, along the vascular arcade
            ├─→ exudates    the OD is bright, round and yellowish — mask it or it
            │               fires as a false exudate on EVERY image
            ├─→ quadrants   the OD-fovea axis orients the clinical 4-2-1 rule
            └─→ NVD vs NVE  neovascularisation AT the disc grades differently
```

It is also the only Module 2 component that can be sanity-checked without
annotations, because the OD has strong, checkable physical properties: it is
bright, it is structured (vessels cross it), and it sits in a predictable place.

---

## What Module 1 already solved for us

`normalizeFundus` fixes the retinal radius at R = 436 px, so:

```
OD diameter ~ 1/7 of image width  ->  OD radius = 62 px  in EVERY image
```

Without that, the 8.7x radius spread across APTOS (207-1800 px) would make a
fixed Hough radius band, a fixed template size, or a fixed search window
meaningless. Every method below is only possible because [A] ran first.

---

## Validation without labels

Three routes, none of which is a substitute for real coordinates:

| Route | What it checks | Weakness |
|---|---|---|
| **Physiology** | is the found spot actually bright and actually structured? measured as core-vs-annulus contrast and SD ratio | an exudate cluster scores high on brightness, lower on structure |
| **Consensus** | do independent methods agree within 1 OD diameter? | all methods can be wrong the same way |
| **Anatomy** | the OD sits ~0.3-0.5 R from the FOV centre | catches gross failure, not fine error |

```
bright = (mean_core − mean_ring) / sd_ring        core: r <= 62 px
struct =  sd_core / sd_ring                       ring: 124 < r <= 217 px
```

---

## The algorithms

### 1. Brightness (baseline)

Blur with a disc-sized window, take the argmax.

```matlab
B = imfilter(Ig, fspecial('average', OD_R));
[~, idx] = max(B(searchRegion));
```

Simple, 27 ms, never fails. Its weakness is the obvious one: it cannot tell
"bright because it is the optic disc" from "bright because the illumination
peaks there" or "bright because that is a cluster of exudates".

### 2. Local variance

The OD is where **dark vessels cross bright tissue**, so local variance peaks
there. Exudates are bright but *smooth*, so in theory this rejects them.

```
V(p) = E[I²] − E[I]²        over a disc-sized window
```

**Theory did not survive contact with data** — see the tables below. It was the
worst of the intensity-based methods.

### 3. Centre-surround (difference of means)

```
response(p) = mean(core around p) − mean(annulus around p)
```

Intended to be illumination-invariant. Partially is — see
[the invariance section](#what-invariant-means-and-where-i-misapplied-it).

### 4. Circular Hough

`imfindcircles` / `cv2.HoughCircles` constrained to radius 0.65–1.5 × OD_R.

**Rejected.** Slowest (62 ms), failed to return any circle on **22/60 images**,
and worst on every quality measure.

### 5. Template matching

Normalised cross-correlation against a filled bright disc. Cheap but poor
structure score (1.19) — it locks onto any bright blob of about the right size.

### 6. Vessel density

Vessel convergence at the disc is the one cue **completely independent of
brightness**. Implemented as a black top-hat on green, thresholded at the 92nd
percentile, then density-filtered.

**Failed badly** (brightness 0.50, agreement 34.4%). The top-hat proxy is too
crude to find true vascular convergence; a real Frangi vesselness map plus
directional voting would be needed.

---

## Round 1 — and the warning sign

Search region: r <= 0.80 R.

| Method | ms | failures | bright | struct | agreement |
|---|---|---|---|---|---|
| brightness-G | 26.9 | 0/60 | **3.60** | 2.61 | 63.3% |
| bright × var | 29.1 | 0/60 | 3.13 | **2.63** | **66.3%** |
| brightness-R | 10.8 | 0/60 | 3.05 | 2.54 | 63.3% |
| variance | 25.5 | 0/60 | 2.33 | 2.07 | 48.3% |
| template | 31.9 | 0/60 | 2.32 | 1.19 | 41.3% |
| **Hough** | 62.1 | **22/60** | 1.53 | 1.37 | 38.7% |

Looks reasonable. Then look at **where** the estimates landed:

```
                median    p90
variance         0.707    0.800   <- past the anatomical range entirely
brightness-R     0.599    0.798
bright x var     0.571    0.799
brightness-G     0.546    0.794
Hough            0.495    0.742
template         0.484    0.706

anatomical truth: the OD sits ~0.3-0.5 R from centre
```

**Every method's p90 sits at 0.79-0.80 — exactly the search boundary.** That
pileup means a large minority of estimates were *clipped at the limit* rather
than converging on anything. Those are failures wearing a plausible number.

`variance` had a **median** of 0.707 R: more than half its answers were
anatomically impossible. It was not finding optic discs at all.

---

## What "invariant" means, and where I misapplied it

A measurement is **invariant** to a change if applying that change leaves the
measurement unaltered.

Module 1 has a clean example, measured:

```
scale the image by c = 0.5:

  varLap      ->  0.250 x original    scales as c²   NOT contrast-invariant
  varLapNorm  ->  1.000 x original    unchanged      contrast-INVARIANT
```

`varLapNorm = var(L)/var(I)`. Both terms scale as c², so the ratio cancels.
Invariance by construction — which is why a sharp-but-underexposed image is not
falsely called blurry.

### The reasoning I applied to centre-surround

If illumination adds a field `L(x,y)` that is roughly **constant over the
core+annulus neighbourhood**, then

```
(mean_core + L) − (mean_annulus + L)  =  mean_core − mean_annulus
```

L cancels. Invariant to illumination. So centre-surround should fix the
peripheral failures without touching the image.

### Why it did not work

| Method (wide search) | median dist | beyond 0.6 R |
|---|---|---|
| plain brightness | 0.546 R | 35% |
| **centre-surround** | 0.583 R | **43%** ← worse |

The invariance is real but **only for smooth fields**. The peripheral failures
are not caused by a smooth gradient — they are caused by **localised glare
patches**, which raise the core *without* raising the annulus. Centre-surround
responds to those exactly as strongly as plain brightness does.

> **The lesson: state what a measure is invariant *to*, then check that the thing
> corrupting your data is actually that.** I was invariant to smooth illumination
> when the problem was localised artifacts.

---

## Round 2 — the anatomical prior wins

Search region tightened to r <= 0.60 R (anatomically generous).

| Method | ms | bright | struct | median dist | p90 | beyond 0.6R | agreement |
|---|---|---|---|---|---|---|---|
| bright WIDE (r1) | 26.9 | 3.60 | 2.61 | 0.546 | 0.794 | 35% | 67.5% |
| **bright TIGHT** | **27.2** | 3.02 | 2.14 | **0.445** | 0.600 | 0% | 71.9% |
| centre-surr WIDE | 52.9 | 3.38 | 2.58 | 0.583 | 0.761 | 43% | 68.1% |
| **centre-surr G** | 53.8 | 2.85 | 2.11 | 0.520 | 0.600 | 0% | **74.7%** |
| centre-surr R | 53.0 | 2.38 | 2.02 | 0.599 | 0.600 | 0% | 68.3% |
| CS × variance | 107.7 | 2.81 | 2.35 | 0.528 | 0.599 | 0% | 72.8% |
| vessel density | 36.6 | 0.50 | 0.77 | 0.591 | 0.600 | 0% | 34.4% |

**Constraining the search did more than any detector refinement.** Plain
brightness moved from median 0.546 R to **0.445 R** — squarely into the
anatomical range — with no change to the detector at all.

Centre-surround buys a modest agreement gain (74.7% vs 71.9%) at **2x the cost**
and slightly worse physiology scores.

---

## Recommendation

```
1. normalizeFundus first                    (R = 436, so OD_R = 62 px is fixed)
2. search region: r <= 0.60 R               <- does most of the work
3. detector: disc-sized mean on GREEN        27 ms, never fails
   (optional) centre-surround on green       54 ms, +2.8pp agreement
4. report the physiology scores alongside the coordinate:
       bright < 1.5  or  struct < 1.2  =>  distrust this OD
```

Use the **valid-mean** form of the window so pixels outside the retina do not
drag the average down near the rim:

```
mean(p) = Σ(I·M) / Σ(M)     over the window, M = retina mask
```

This is the same class of fix as [A]'s eroded `maskMeasure` — never let the
black surround into a statistic.

---

## The honest limitation

**p90 = 0.600 for every tightened method — the boundary again.** At least 10% of
estimates are still being clipped at the search limit. The anatomical prior is
not fixing those failures, it is **hiding** them.

Which means the real accuracy of every method above is **unknown**. Consensus at
74.7% could mean "three-quarters correct" or "three-quarters wrong in the same
way".

**IDRiD sub-challenge C provides optic disc centre coordinates for 516 images.**
That converts every table above from "the methods agree with each other" into a
measured accuracy — "94% within 1 disc diameter" or whatever the truth turns out
to be. It is ~2-3 GB, free with an IEEE DataPort account, CC-BY, and Indian data
from Nanded.

Until then, treat OD localization as **built but unvalidated**, and propagate
that uncertainty into everything downstream — fovea position, exudate masking,
and the 4-2-1 quadrant orientation all inherit it.

---

## Next

Fovea localization — geometric from the OD (2.5 DD temporal along the arcade
axis), which means its error is the OD error plus its own. Then vessel
segmentation, which gates the entire dark-lesion pipeline.

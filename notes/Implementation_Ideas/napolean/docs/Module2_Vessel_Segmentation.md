# Module 2, Step 2 — Vessel Segmentation

**Purpose:** produce a binary vessel mask. It gates half of Module 2 — vessels
are dark on green *exactly* like microaneurysms and haemorrhages, so without
subtracting them every vessel pixel becomes a false lesion.

**Code:** not yet in MATLAB. Python reference in the session scratchpad
(`m2_vessels.py` … `m2_vessels4.py`).

**Status:** four rounds measured on 8–10 APTOS images, **without ground truth**.
APTOS has no vessel masks, so nothing below is a measured sensitivity — see
[Validation without labels](#validation-without-labels).

---

## Contents

- [Why vessels come before lesions](#why-vessels-come-before-lesions)
- [What the scale table dictates](#what-the-scale-table-dictates)
- [Validation without labels](#validation-without-labels)
- [The algorithms](#the-algorithms)
- [Round 2 — three filters compared](#round-2--three-filters-compared)
- [Round 3 — thresholding, and a wrong turn](#round-3--thresholding-and-a-wrong-turn)
- [Round 4 — alternatives](#round-4--alternatives)
- [Recommendation](#recommendation)
- [The metric that is still broken](#the-metric-that-is-still-broken)

---

## Why vessels come before lesions

```
vessels ─┬─→ microaneurysms   subtract first, or every vessel pixel is a lesion
         ├─→ haemorrhages     same
         ├─→ fovea            avascularity is what distinguishes it from a shadow
         ├─→ optic disc       vessel convergence is a brightness-independent cue
         └─→ neovascularization  NV is *defined* in terms of abnormal vessels
```

**Dilate the vessel mask 2–3 px before subtracting.** Segmentation always misses
the faint outer edge, and a half-removed vessel leaves dark fragments that look
precisely like microaneurysms.

---

## What the scale table dictates

At `targetR = 436`, the optic disc is a fixed 124 px, and a standard disc is
1.85 mm:

```
1.85 mm / 124 px = 14.9 um per pixel
```

Which fixes the vessel width band:

| Vessel | Width | px |
|---|---|---|
| small | ~40 um | **2.7** |
| major arcade | ~150 um | **10.1** |

**This band bounds the filter scales.** Going finer does not find smaller
vessels — it finds noise. That is not a guess; see
[the wrong turn](#round-3--thresholding-and-a-wrong-turn).

---

## Validation without labels

| Check | Target | Why it is meaningful |
|---|---|---|
| **coverage** | 8–15% of retina | published vessel fraction for fundus |
| **component count** | low | a real vessel tree is *one* connected structure |
| **largest component %** | high | ditto — confetti scores low here |
| **width (via EDT)** | 2.7–10.1 px | from the scale table above |
| branchpoints | 200–600 | *confounded — see the last section* |
| **Dice between methods** | high | independent methods agreeing is evidence |

> **Do not calibrate the threshold to hit the coverage target and then report
> coverage as validation.** Round 1 did exactly that — thresholded at the 88th
> percentile, which *forces* ~12% coverage, then "verified" coverage was ~11%.
> Circular and worthless. Rounds 2+ use Otsu or a stated calibration, with
> topology as the discriminator.

---

## The algorithms

### 1. Frangi vesselness (multi-scale Hessian)

A tubular structure has one small eigenvalue (along the vessel) and one large
(across it). For each scale `s`, with `|λ1| ≤ |λ2|`:

```
R_b = |λ1| / |λ2|              blobness      (0 for an ideal line)
S   = sqrt(λ1² + λ2²)          structureness (low in flat background)

V(s) = 0                                       if λ2 < 0
V(s) = exp(−R_b²/2β²) · (1 − exp(−S²/2c²))     otherwise

V = max over s
```

`β ≈ 0.5`, `c ≈ half the max Hessian norm`. **Sign convention:** vessels are
*dark* on green — intensity valleys — so the second derivative *across* the
vessel is positive, and the condition is `λ2 > 0`.

```matlab
V = fibermetric(Ig, 3:2:11, 'ObjectPolarity','dark', 'StructureSensitivity',0.03);
```

### 2. Matched filtering (Chaudhuri)

A vessel cross-section is roughly Gaussian. Build a kernel Gaussian across and
constant along, rotate through 12 orientations, take the per-pixel max.

```
K(x,y) = −exp(−x² / 2σ²)   for |y| ≤ L/2 ,  then MEAN-SUBTRACTED
```

Mean subtraction is essential — it makes the filter respond to *contrast*, not
brightness, so it is invariant to the illumination field.

### 3. Morphological (linear structuring elements)

Black top-hat with **linear** SEs at 12 angles. Anything longer than L in some
direction survives; compact blobs do not.

### 4. Line detector (Ricci & Perfetti)

For each pixel, the max over 12 line orientations of the line mean, minus a
square-window mean, computed on **inverted** green so vessels are bright.

```
S(p) = max_theta [ mean along line_theta through p ] − mean over WxW window at p
```

Cheap, classical, and strongly published on DRIVE. **370 ms** — 3× faster than
Frangi.

### 5. Length filtering (post-process)

Drop connected components whose **skeleton** is short, not whose *area* is small.

```matlab
S    = bwskel(bw);
len  = accumarray(labels(S), 1);      % skeleton length per component
keep = len >= 25;
```

A 200-px blob and a 200-px vessel have the same area but very different length.
Area filtering cannot separate them; length filtering can. **This turned out to
be the single most valuable post-processing step.**

#### Length without thinning — a 160x speedup

Zhang-Suen thinning is 15 iterations × 2 passes × 8 array shifts on 872×872,
called ~12 times per image. That cost 8 s/image and made the functional test
unrunnable. Skeleton length is recoverable analytically instead:

```
for a tube of length L and width w:   area = L·w,   mean(EDT) ≈ w/4
so                                    w ≈ 4·mean(EDT)
and                                   L ≈ area / w
```

One distance transform plus two `bincount`s, vectorised over every component at
once — **~50 ms instead of ~8 s**.

```matlab
lab   = bwlabel(bw);
edt   = bwdist(~bw);
area  = accumarray(lab(bw), 1);
esum  = accumarray(lab(bw), edt(bw));
width = 4*esum ./ max(area,1);
len   = area ./ max(width,1e-6);
```

### 6. Threshold strategies

Three were tested; the choice matters less than the scale bank.

| Strategy | Behaviour |
|---|---|
| **Otsu on the response** | correct, but Frangi's response is skewed to zero so Otsu cuts too high (2.4% coverage) |
| **coverage calibration** | pick the percentile that yields a target coverage. Used for all comparisons so topology, not the threshold, discriminates |
| **hysteresis** | seed high, grow low, keep seeded components. **Rejected** — see round 3 |

> **Never calibrate to a coverage target and then report coverage as validation.**
> That is circular. Calibrate to equalise configs, then judge on topology.

### 7. Gap bridging

The retinal tree is anatomically **one connected structure** — everything
emanates from the disc. A largest-component share of 62–72% means the mask is
*severed* at faint points, not that the anatomy is fragmented.

```matlab
for a = 0:15:165
    add = max(add, imclose(bw, strel('line', 9, a)));
end
```

Measured: largest component **62.6% → 81.0%**. But component count went
**14 → 40**, because closing along every orientation also links noise into new
fragments. **The idea is validated; this implementation is not** — it needs to
add only pixels that genuinely connect two pre-existing components.

### 8. Ensemble voting

2-of-3 across line detector, Frangi and matched filter. Pairwise Dice was only
0.28–0.58, i.e. the methods fail *differently*, which is exactly when voting
should help. **It did not** — the vote landed between its members, not above
them.

### 9. CLAHE preprocessing

Standard in the vessel literature. **No measurable effect here** (53.4% vs 52.5%
largest component), consistent with what [F] found for enhancement generally.

---

## Round 2 — three filters compared

Otsu threshold, Frangi scales 1.5–7.0 px.

| Method | ms | vessel % | comps | largest % | width med/p95 | branchpoints |
|---|---|---|---|---|---|---|
| **Frangi** | 855 | **2.4%** ✗ | **10** ✓ | 49.6% | 6.0 / 12.6 ✓ | **195** ✓ |
| matched filter | 736 | 4.6% ✗ | 60 ✗ | 22.5% ✗ | 4.0 / 8.0 ✓ | 1,245 ✗ |
| morphological | **61** | 8.3% ✓ | 97 ✗ | 34.6% ✗ | 4.0 / 8.5 ✓ | 2,953 ✗ |
| *target* | | *8–15%* | *low* | *high* | *2.7–10.1* | *200–600* |

Dice: Frangi↔matched **0.523**, Frangi↔morphological **0.281**,
matched↔morphological **0.578**.

**Frangi has the right topology and the wrong amount.** Morphological has the
right amount and completely wrong topology. Low Dice means the methods fail
*differently* — which is what makes an ensemble worth trying (round 4).

---

## Round 3 — thresholding, and a wrong turn

**Hypothesis:** Frangi's response is heavily skewed toward zero, so Otsu cuts too
high and severs thin branches. Hysteresis — seed high, grow low, keep seeded
components — should recover them.

| Config | vessel % | comps | largest % | branchpoints |
|---|---|---|---|---|
| single p88 | 11.5% | 66 | 50.2% | 2,539 |
| single p80 | 18.6% | 104 | 57.7% | 3,770 |
| hyst 75/92 | 20.1% | 36 | 69.0% | 4,130 |
| hyst 70/90 | 23.6% | 49 | 70.9% | 5,070 |
| hyst 60/85 | 32.3% | 110 | 71.7% | 8,200 |

**Hysteresis failed.** Every setting overshot coverage *and* exploded
branchpoints. None of seven strategies met both criteria.

### The real finding: scale selection, not thresholding

Between rounds I added a **σ = 1.2 px** scale to the Frangi bank. At the same
coverage, branchpoints went **195 → 2,539**.

σ = 1.2 px is **18 µm** — well below the smallest real vessel (40 µm = 2.7 px).
That scale was responding to pixel noise and manufacturing thousands of spurious
branches.

> **Rule: bound the Frangi scale bank by the physical vessel width band from the
> scale table.** Going finer does not find smaller vessels; it finds noise.
> I introduced this bug by not consulting my own scale table.

---

## Round 4 — alternatives

Frangi scales bounded to σ = 1.3–5.0 px (i.e. widths 2.7–10 px). All configs
thresholded to ~11% coverage, so **topology is the discriminator**.

| Config | ms | vessel % | comps | largest % | w med | branchpoints |
|---|---|---|---|---|---|---|
| A Frangi bounded | 1132 | 10.4% | 79 | 52.5% | 4.0 | 2,632 |
| B line detector | **370** | 10.1% | 92 | 75.3% | 3.4 | 3,444 |
| C Frangi + CLAHE | 1125 | 10.2% | 90 | 53.4% | 4.0 | 2,762 |
| D vote 2-of-3 | 1518 | 9.6% | 92 | 72.4% | 4.0 | 2,832 |
| E Frangi + lenFilt | 1132 | 9.7% | **31** | 55.7% | 4.5 | 2,510 |
| **E line + lenFilt** | **370** | **9.3%** | **30** | **80.9%** | 4.0 | 3,294 |

Three things to read off this:

- **Length filtering is what works.** It cut components from 79 → 31 (Frangi) and
  92 → 30 (line detector), and raised largest-component share to 80.9%.
- **CLAHE made no difference** — 53.4% vs 52.5% largest. The vessel literature's
  habit of CLAHE-before-vesselness earns nothing here, consistent with what
  [F] measured.
- **The 2-of-3 vote did not beat its best member.** Despite low pairwise Dice
  suggesting complementary failures, voting landed between the components.

---

## Round 5 — the full sweep (896 evaluations)

**32 images × 7 filters × 4 post-processes.** Coverage calibrated to 11% for
every config, so topology discriminates. Branchpoints now computed after spur
removal. Two new unconfounded metrics added: **fragmentation** (components per
1000 px of skeleton — a scale-free component count) and **orientation
coherence** (structure-tensor anisotropy on vessel pixels — real vessels are
locally linear, noise is not).

| Config | ms | cov % | comps | largest % | w med | w sd | frag | coh |
|---|---|---|---|---|---|---|---|---|
| **line L21+len40** | 372 | 9.8 | **18** | **72.4** | 4.0 | 2.42 | **2.34** | 0.662 |
| line L21+len25 | 372 | 10.0 | 28 | 69.9 | 4.0 | 2.43 | 3.43 | 0.653 |
| line L21+len15 | 372 | 10.3 | 40 | 67.1 | 4.0 | 2.45 | 4.92 | 0.639 |
| line L21+raw | 372 | 10.5 | 54 | 65.6 | 4.0 | 2.45 | 6.61 | 0.632 |
| line L15+len40 | 366 | 8.9 | 24 | 57.2 | 4.0 | **1.96** | 2.91 | 0.665 |
| frangi wide+len40 | 1350 | 9.1 | 20 | 47.0 | 4.5 | 3.40 | 3.47 | 0.654 |
| frangi narrow+len40 | 1120 | 9.2 | 23 | 44.2 | 4.5 | 2.78 | 3.58 | 0.672 |
| line L11+len40 | **54** | 8.2 | 25 | 43.4 | 4.0 | 1.85 | 3.87 | 0.687 |
| matched+len40 | 686 | 8.6 | 27 | 41.7 | 4.0 | 1.69 | 4.04 | 0.689 |
| morpho+len40 | 55 | **5.4** ✗ | 22 | 30.1 | 4.0 | 2.40 | 6.34 | **0.721** |

Four results:

- **The top eight configs are all line detector.** Best Frangi is ninth at 47.0%
  largest, for 3.6× the cost.
- **`len40` is best for every one of the seven filters** — no exceptions. Longer
  minimum skeleton is strictly better across the board.
- **L21 beats L15 and L11 decisively.** A longer line kernel matches the arcades
  better; L11 is 7× faster but loses 29 points of largest-component share.
- **Morphological is eliminated** — all four variants failed the coverage sanity
  filter (5.4–6.8% against 8–15%) despite the *best* coherence scores. It finds
  something linear, just not enough of it.

> The formal equal-weight ranking put `line L15+len40` first (score 5.50 vs
> 5.75), but only because L15 edges L21 on **width-SD**, the weakest criterion.
> On the two metrics that describe tree structure — largest-component share and
> fragmentation — L21 wins decisively. **Take L21.**

---

## Round 6 — functional validation

Topology asks *"does this look like a vessel tree?"* None of the above asks
*"does it do its job?"* Vessels exist here to be **subtracted before dark-lesion
detection**. Three tests on 30 best-quality images (6 per grade).

### Test 1 — does subtraction improve MA-count → grade correlation? INCONCLUSIVE

| Config | rho (MA count vs grade) | delta vs control |
|---|---|---|
| none (control) | −0.117 | — |
| **line L21+len40** | **−0.104** | **+0.014** |
| line L15+len40 | −0.131 | −0.014 |
| frangi narrow+len40 | −0.158 | −0.041 |

**Every correlation is negative and near zero.** MA count should *rise* with
grade — grade 1 is defined as "microaneurysms only". Deltas of ±0.04 are noise
at n=30.

**The probe is broken, not the vessels.** The MA counter used here is the raw
candidate stage only — threshold, size filter, count. The classical pipeline has
a **fifth step that was skipped**: a classifier to prune false positives, because
the candidate stage yields 100+ per image at very low precision.

**Vessel segmentation cannot be functionally validated until MA detection works.**

### Test 2 — stability under degradation: FRANGI WINS

Re-segment a blurred and a noised copy, Dice against the original. Needs no
labels.

| Config | blur σ1.2 | noise σ0.02 | mean |
|---|---|---|---|
| **frangi narrow** | **0.972** | **0.706** | **0.839** |
| line L21+len40 | 0.893 | 0.679 | 0.786 |
| line L15+len40 | 0.832 | **0.514** | 0.673 |

**Frangi is the most reproducible**, despite losing the topology sweep. Line L15
is fragile under noise — half the mask changes.

This is a genuine counterweight. The sweep measured appearance on one pass; this
measures whether you get the same answer twice. For a screening system that
images the same eye repeatedly, reproducibility matters.

### Test 3 — gap bridging: idea validated, implementation is not

```
largest component :  62.6%  ->  81.0%     +18 points
components        :  14     ->  40        tripled
coverage          :  8.7%   ->   9.8%
```

The tree **is** severed and rejoining recovers 18 points — but closing along all
12 orientations also links noise into new fragments. Needs a version that adds
only pixels connecting two pre-existing components.

---

## Recommendation

```
1. normalizeFundus first                       (fixes 14.9 um/px)
2. green channel, shade-corrected               NOT CLAHE
3. LINE DETECTOR, 12 orientations, L=21, W=21   372 ms
4. threshold calibrated to ~10% coverage
5. LENGTH FILTER, min length 40 px              <- best for all 7 filters
6. dilate 2-3 px before subtracting for lesions
```

Measured: **9.8% coverage, 18 components, 72.4% in one tree, width 4.0 px,
fragmentation 2.34, 372 ms.** Best in the sweep on every structural metric.

**Second choice: Frangi narrow + len40** (1120 ms, 44.2% largest). Worth keeping
for two reasons — `fibermetric` is a one-call MATLAB built-in where the line
detector needs 12 hand-written rotated convolutions, and **it is measurably more
stable** (0.839 vs 0.786).

> This is now a **judgement call, not a measurement.** The topology sweep favours
> L21; the stability test favours Frangi; the functional tie-breaker could not
> run. If reproducibility across repeat visits matters more than tree structure,
> Frangi is defensible.

---

## The metric that is still broken

**Branchpoints survived three repair attempts and remain unusable.**

| Attempt | Result |
|---|---|
| counted on the unthinned mask | 58,360 — interior pixels counted as branches |
| Zhang-Suen thinning added | 2,500–3,400 vs a 200–600 target |
| **spur removal, 5 iterations** | **1,706–3,258 — still wrong** |

Five spur iterations are not enough for masks this ragged. Round 2's Frangi hit
195 branchpoints at 2.4% coverage, so the metric scales steeply with coverage and
the two targets cannot both be met.

**I would now stop trying.** Coverage, component count, largest-component share
and fragmentation are sufficient and unconfounded. Ignore every branchpoint
column above.

Same class of error as `circularity` in [A] — `4πA/P²` collapsed because
boundary raggedness inflated the perimeter, and it was replaced by `residual`.

### And the larger limitation

No vessel ground truth exists in APTOS. 9.8% coverage in one dominant tree is
*consistent with* a correct segmentation; it does not prove one. The mask could
be systematically missing every small vessel and still score well on all four
checks.

Two harder facts for calibration:

- **A correct tree should be >90% in one component.** At 72.4%, roughly a quarter
  of the mask is in fragments.
- **90% pixel sensitivity is not achievable by anyone.** On DRIVE, a second human
  observer scores 0.776; the best published methods reach 0.83–0.85. Any method
  claiming 90% is overfitting the first annotator.

**DRIVE is 30 MB** and provides 40 images with pixel-level masks plus two
independent observers — converting all of this from "physically plausible" into a
measured sensitivity with a human ceiling to compare against.

### And the larger limitation

No vessel ground truth exists in APTOS. Coverage of 9.3% and one dominant tree
are *consistent with* a correct segmentation; they do not prove one. The mask
could be systematically missing all small vessels and still score well on every
check above.

**DRIVE is 30 MB** and provides 40 images with pixel-level vessel masks plus two
independent human observers — turning all of this from "physically plausible"
into a measured sensitivity/specificity with a human ceiling to compare against.

---

## Next

Fovea localization — which needs this vessel map for the avascularity test, and
for the arcade axis that orients the search.

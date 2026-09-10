# Module 2 — Retinal Structure Segmentation

**Purpose:** find the clinically meaningful structures *inside* the retina —
vessels, optic disc, fovea, and the four lesion classes that define the ICDR
grade.

**Prerequisite:** every algorithm here assumes the image has already been through
[`[A]`](Module1_A_FOV_Detection.md) and radius-normalised. Nothing below works
without a fixed scale.

---

## Status — read this first

| Component | Type | Status |
|---|---|---|
| Optic disc | localization | **built, unvalidated** — see [Module2_OD_Localization.md](Module2_OD_Localization.md) |
| Fovea | localization | designed |
| Vessels | segmentation | designed |
| Microaneurysms | detection | designed |
| Exudates | segmentation | designed |
| Haemorrhages | segmentation + classification | designed |
| Neovascularization | detection | designed |

Unlike the Module 1 docs, **almost nothing here carries measured numbers.**
APTOS has no lesion masks, no vessel masks and no OD/fovea coordinates, so
parameters below come from the literature and from geometry, not from fitting to
your data. Every one needs calibration before it is trusted.

---

## Contents

- [Retina segmentation vs structure segmentation](#retina-segmentation-vs-structure-segmentation)
- [The scale table](#the-scale-table--everything-in-normalised-pixels)
- [Dependency order](#dependency-order--why-this-sequence-is-forced)
- [1. Vessel segmentation](#1-vessel-segmentation)
- [2. Optic disc](#2-optic-disc)
- [3. Fovea](#3-fovea)
- [4. Microaneurysms](#4-microaneurysms)
- [5. Exudates](#5-exudates)
- [6. Haemorrhages](#6-haemorrhages)
- [7. Neovascularization](#7-neovascularization)
- [8. Quadrants and the 4-2-1 rule](#8-quadrants-and-the-4-2-1-rule)
- [Validation with APTOS only](#validation-with-aptos-only)
- [Failure modes](#failure-modes)

---

## Retina segmentation vs structure segmentation

Two different things share the word.

| | Question | Where |
|---|---|---|
| **Retina segmentation** | which pixels are retina vs black surround? | **[A]** — done, 99.95% |
| **Retinal *structure* segmentation** | which pixels are vessel / lesion / disc? | **Module 2** — this doc |

And within Module 2, another distinction:

| | Output | Used for |
|---|---|---|
| **Localization** | a point `(x,y)` | optic disc, fovea |
| **Segmentation** | a label per pixel | vessels, exudates, haemorrhages |

For DR, the optic disc only needs **localization** — a centre plus the known
radius gives a circle, which is all that exudate masking and quadrant
orientation require. Full disc-boundary segmentation matters for cup-to-disc
ratio, which is a *glaucoma* metric and out of scope.

---

## The scale table — everything in normalised pixels

After `normalizeFundus` with `targetR = 436`, the optic disc is a fixed 124 px
across. A standard optic disc is **1.85 mm**, which fixes the scale:

```
1.85 mm / 124 px  =  14.9 um per pixel        (at R = 436)
```

Every size threshold in this document follows from that:

| Structure | Clinical size | px at R=436 | px at native (R≈1100) |
|---|---|---|---|
| Optic disc diameter | 1.85 mm | **124** | 314 |
| **MA / haemorrhage split** | **125 um** | **8.4** | 21 |
| Microaneurysm | 10–125 um | 1–8 | 2–21 |
| Dot/blot haemorrhage | 125–500 um | 8–34 | 21–85 |
| Major arcade vessel | ~150 um | ~10 | ~25 |
| Small vessel | ~40 um | ~3 | ~7 |
| OD → fovea distance | 2.5 disc diameters | **310** (= 0.71 R) | 785 |
| DME danger zone | 500 um from fovea | 34 | 85 |

> **Why this table is the most important thing in the document.** Every lesion
> rule in the ICDR scale is stated in microns. Without a fixed px/um scale, none
> of them can be implemented. This is the payoff from [A]'s radius
> normalization, and it is why the 8.7x radius spread in APTOS had to be removed
> first.

**Resolution implication:** at R=436 a microaneurysm is 1–8 px. That is workable
but tight. Run MA detection at **native resolution or R ≥ 436**, never lower —
the same argument that killed downsampling in [B].

---

## Dependency order — why this sequence is forced

```
        [A] mask + radius normalization
                 │
                 ▼
        1. VESSELS ────────────────┬──────────────┐
                 │                 │              │
                 ▼                 ▼              ▼
        2. OPTIC DISC        4. MICROANEURYSMS  6. HAEMORRHAGES
                 │                (vessel subtraction is mandatory)
        ┌────────┴────────┐
        ▼                 ▼
   3. FOVEA         5. EXUDATES
        │            (OD masking is mandatory)
        ▼
   8. QUADRANTS → the 4-2-1 rule
                 │
                 ▼
        7. NEOVASCULARIZATION (needs the vessel map + OD position)
```

Two of these arrows are non-negotiable:

- **Vessels before dark lesions.** Vessels are dark on green — *exactly* like
  microaneurysms and haemorrhages. Skip vessel subtraction and every vessel pixel
  becomes a false lesion.
- **Optic disc before exudates.** The OD is bright, round and yellowish. Every
  exudate detector that does not mask it fires on it, in **every single image**.

---

## 1. Vessel segmentation

**Why first:** it gates the entire dark-lesion pipeline, and it supplies the
biomarkers (tortuosity, calibre, venous beading) used later.

**Channel: green.** Haemoglobin absorbs green strongly, so vessels are darkest
there. Green is also the densest Bayer channel, hence the sharpest.

### Option A — Frangi vesselness (recommended)

Compute the Hessian at multiple scales. A tubular structure has one small
eigenvalue (along the vessel) and one large (across it).

For each scale `s`, with eigenvalues `|λ1| ≤ |λ2|`:

```
R_b = |λ1| / |λ2|                    blobness   (0 for an ideal line)
S   = sqrt(λ1² + λ2²)                structureness (low in flat background)

V(s) = 0                                          if λ2 < 0   (bright structure)
V(s) = exp(−R_b²/2β²) · (1 − exp(−S²/2c²))        otherwise

V = max over s
```

`β ≈ 0.5`, `c ≈ half the max Hessian norm`. **Sign convention:** vessels are
*dark* on green, i.e. intensity valleys, so require `λ2 > 0`.

```matlab
Ig = im2double(I(:,:,2));
V  = fibermetric(Ig, 3:2:13, 'ObjectPolarity','dark', 'StructureSensitivity',0.03);
bw = V > graythresh(V(fov.maskMeasure));
bw = bwareaopen(bw, 40);              % drop specks < ~40 px
```

Scale range `3:2:13` px covers ~45–190 um at R=436 — small vessels to major
arcades, per the scale table.

### Option B — Matched filtering (Chaudhuri)

A vessel cross-section is roughly Gaussian. Build a kernel that is Gaussian
across and constant along, rotate through 12 orientations at 15°, take the
per-pixel maximum.

```
K(x,y) = −exp(−x² / 2σ²)     for |y| ≤ L/2 ,  then mean-subtracted
```

Mean subtraction is essential — it makes the filter respond to *contrast*, not
brightness, so it is invariant to the illumination field.

```matlab
resp = -inf(size(Ig));
for th = 0:15:165
    K = imrotate(matchedKernel(sigma, L), th, 'bilinear', 'crop');
    resp = max(resp, imfilter(Ig, K, 'replicate'));
end
```

### Option C — Morphological

`imtophat` with **linear** structuring elements at 12 angles. Anything longer
than L in some direction survives; compact blobs do not. Cheapest, crudest.

### Which to use — MEASURED on 8–10 APTOS images

No vessel ground truth exists in APTOS, so the checks are physical plausibility:
coverage should be 8–15% of retina, a real tree is mostly **one** connected
component, widths should fall in 2.7–10.1 px (from the scale table), and an
arcade tree has **200–600 branchpoints**.

| Method | ms | vessel % | comps | largest % | width med/p95 | branchpoints |
|---|---|---|---|---|---|---|
| **Frangi** | 855 | **2.4%** ✗ | **10** ✓ | 49.6% | 6.0 / 12.6 ✓ | **195** ✓ |
| matched filter | 736 | 4.6% ✗ | 60 ✗ | 22.5% ✗ | 4.0 / 8.0 ✓ | 1,245 ✗ |
| morphological | **61** | 8.3% ✓ | 97 ✗ | 34.6% ✗ | 4.0 / 8.5 ✓ | 2,953 ✗ |
| *target* | | *8–15%* | *low* | *high* | *2.7–10.1* | *200–600* |

**Frangi has the right topology and the wrong amount.** 10 components, 195
branchpoints, correct widths — a proper vessel tree, but capturing only the major
arcades. Morphological has the right coverage with completely wrong topology
(2,953 branchpoints is confetti). Dice between methods is only **0.28–0.58**, so
there is no consensus to fall back on either.

**Recommendation: Frangi**, on topology. It needs no training data and
`fibermetric` is one call. But the threshold and scale set must be fixed first.

### Two things that did NOT work

**Hysteresis thresholding made it worse, not better.** Seeding high and growing
low is the standard fix for severed thin branches. Measured:

| Config | vessel % | comps | branchpoints |
|---|---|---|---|
| single p88 | 11.5% | 66 | 2,539 |
| hyst 75/92 | 20.1% | 36 | 4,130 |
| hyst 70/90 | 23.6% | 49 | 5,070 |
| hyst 60/85 | 32.3% | 110 | 8,200 |

Every hysteresis setting overshot coverage **and** exploded branchpoints. **None
of seven threshold strategies met both criteria.**

**The real lever is SCALE SELECTION, not thresholding.** Between rounds I added a
σ=1.2 px scale to the Frangi bank. Branchpoints went from **195 → 2,539** at
comparable coverage. At 14.9 µm/px, σ=1.2 px is **18 µm** — well below the
smallest real vessel (40 µm = 2.7 px). That scale was responding to pixel noise
and manufacturing thousands of spurious branches.

> **Rule: the Frangi scale bank must be bounded by the physical vessel width
> range from the scale table — roughly σ = 2.7 to 10 px at R=436. Going finer
> does not find smaller vessels; it finds noise.**

**Still unresolved:** the combination of round-2 scales (no σ<1.5) with a lower
threshold has not been measured. That is the obvious next experiment, and until
it runs, **vessel segmentation is not production-ready.**

Also untested: MATLAB's own `fibermetric`, which is now available. It may
normalise differently from this hand-rolled implementation, and the 2.4%-vs-11%
gap is large enough that the two should be compared before either is trusted.

### Post-processing

```matlab
bw = bwmorph(bw, 'clean');                  % isolated pixels
bw = bwareaopen(bw, 40);
skel = bwskel(bw);                          % for tortuosity / branch analysis
bp   = bwmorph(skel, 'branchpoints');
ep   = bwmorph(skel, 'endpoints');
```

### Dilate before subtracting

When removing vessels prior to lesion detection, **dilate the vessel mask by
2–3 px first**. Segmentation always misses the faint outer edge, and a
half-removed vessel leaves dark fragments that look exactly like microaneurysms.

---

## 2. Optic disc

Covered in detail in [Module2_OD_Localization.md](Module2_OD_Localization.md).
Summary of what was measured on 60 APTOS images:

```
detector : disc-sized mean on green,  window = OD_R = 62 px
search   : r <= 0.60 R              <- did more than any detector refinement
cost     : 27 ms
```

**Rejected:** Hough (22/60 failures), vessel-density (34.4% agreement), and local
variance (median 0.707 R — anatomically impossible for over half its answers).

**Unresolved:** p90 pins at the search boundary for every method, so the true
failure rate is unknown.

Always emit the physiology scores alongside the coordinate:

```
bright = (mean_core − mean_ring) / sd_ring        core: r ≤ 62 px
struct =  sd_core / sd_ring                       ring: 124 < r ≤ 217 px

bright < 1.5  or  struct < 1.2   =>  distrust this OD
```

---

## 3. Fovea

**What it is:** the avascular pit at the centre of the macula — where sharp
central vision lives. It is the darkest smooth region of the retina.

**Why it matters:** *distance from the fovea determines urgency.* Hard exudates
within 500 um (34 px) of the fovea indicate clinically significant macular
oedema — an urgent referral **regardless of the DR grade**.

### Algorithm — geometric, then refine

```
Step 1  Estimate the arcade axis from the vessel map:
        principal direction of vessel pixels within 2 DD of the OD

Step 2  Search region: an annulus 2.0-3.0 DD from the OD centre
        (248-372 px at R=436), within ±30° of the arcade axis

Step 3  Inside that region, find the darkest smooth spot:
            score = -mean(green in 40px disc) - λ · vesselDensity
        The vessel penalty matters: the fovea is AVASCULAR, so a dark
        patch full of vessels is a shadow, not the fovea.

Step 4  Sanity: |OD - fovea| should be 2.2-2.8 DD.  Outside that, flag.
```

**Temporal direction ambiguity:** the fovea is temporal to the disc, but which
side that is depends on left vs right eye. Resolve by picking whichever
candidate is **darker and more avascular** — do not assume a side.

### Error propagation

Fovea error = OD error **plus** its own. Since OD accuracy is currently unknown,
fovea accuracy is unknown-plus-more. Any DME rule built on exudate-to-fovea
distance inherits both.

---

## 4. Microaneurysms

**The hardest component, and the most important.** Grade 1 is *defined* as
"microaneurysms only", so early detection rests entirely here.

**What they look like:** small (< 125 um = 8.4 px), round, dark red, isolated,
and — crucially — **not connected to a visible vessel**.

### The classical pipeline (Frame / Spencer / Cree family)

```
Step 1  green channel, shade-corrected

Step 2  VESSEL REMOVAL by morphological closing with linear SEs
        for theta = 0:15:165
            C(theta) = imclose(Ig, strel('line', L, theta))
        end
        Cmin = min over theta

        A vessel is elongated -> SOME orientation's line fits inside it,
        so it survives closing.
        An MA is compact    -> EVERY orientation's line bridges over it,
        so it gets filled.

        Cmin - Ig  leaves MAs and removes vessels.

Step 3  threshold at multiple levels -> candidates
        (high recall, terrible precision: expect 100+ per image)

Step 4  per-candidate features
Step 5  classifier to prune false positives
```

`L` must exceed the MA diameter but stay under the vessel length — **L = 15 px**
at R=436 (~220 um).

### Candidate features for step 4

| Feature | Rationale |
|---|---|
| area, perimeter, eccentricity, circularity | MAs are round; vessel fragments are not |
| mean / max intensity, contrast to local background | real MAs are meaningfully darker |
| **2-D Gaussian fit residual** | real MAs *are* Gaussian blobs; noise is not |
| colour in R, G, B | MAs are red — dust and shadows are not |
| distance to nearest vessel pixel | MAs are isolated by definition |
| local vessel density | suppresses candidates inside the arcade |

### Alternatives

- Matched filtering with a Gaussian kernel sized to an MA
- Radon-transform based detection
- A small patch-CNN replacing steps 4–5 (needs labels)

### Calibrate your expectations

State-of-the-art AUPR on IDRiD MA segmentation is **≈ 0.50**. Microaneurysm
detection is genuinely unsolved. If your detector reaches 0.40 you are in
respectable territory — knowing this number protects you when a judge asks why
MA performance looks low.

> **The resolution rule.** A standard CNN resizes to 224×224, where an MA is
> **under one pixel** — physically absent from the input. That is why MA
> detection must run at native resolution, separate from the whole-image CNN
> branch. Same argument as [B]'s downsampling result.

---

## 5. Exudates

Bright lipid/protein deposits leaking from damaged vessels.

| Type | Appearance | Meaning |
|---|---|---|
| **Hard** | yellow, sharp-edged, waxy, often ringed | leakage; near fovea → macular oedema |
| **Soft** (cotton-wool) | pale, fluffy, indistinct | nerve-fibre-layer infarct — a small retinal stroke |

### Algorithm

```
Step 1  MASK THE OPTIC DISC.  Non-negotiable.
        mask a disc of radius 1.2 * OD_R around the OD centre.

Step 2  candidate detection on the shade-corrected green channel
        morphological reconstruction:
            marker = Ig - h                      (h ≈ 0.05)
            rec    = imreconstruct(marker, Ig)
            cand   = (Ig - rec) > t
        anything that fails to reconstruct is a bright lesion.

Step 3  refine boundaries — region growing or watershed

Step 4  classify hard vs soft:
            edge sharpness  = mean |gradient| on the boundary
            texture entropy inside
            colour saturation      (hard = yellow, soft = whitish)
        The BLUE channel separates them: yellow is low-blue, white is high-blue.

Step 5  distance to fovea, in disc diameters — the reportable number
```

`imextendedmax` is a usable one-call alternative to steps 2–3.

---

## 6. Haemorrhages

Dark red, larger and more irregular than MAs. **The size split is the
125 um / 8.4 px line from the scale table.**

| Subtype | Appearance | Origin | Grading weight |
|---|---|---|---|
| **Dot / blot** | round, well-defined, deep | deep capillary plexus | count per quadrant drives the 4-2-1 rule |
| **Flame / splinter** | feathery, spreads along nerve fibres | superficial NFL | often hypertensive rather than diabetic |
| **Preretinal / vitreous** | large, may show a fluid level | — | **means proliferative disease (grade 4)** |

### Algorithm

Reuse the MA dark-lesion pipeline (green → vessel subtraction → thresholding),
then split:

```
area < 8.4 px diameter  -> microaneurysm
area >= 8.4 px          -> haemorrhage
```

Subtype classification from shape:

| Descriptor | Dot/blot | Flame |
|---|---|---|
| `Eccentricity` | low (round) | high (elongated) |
| `Solidity` | high | lower (feathery) |
| boundary smoothness | smooth | ragged |
| orientation vs local vessel direction | random | **aligned** with nerve fibres |

That last one is the discriminator worth building — flame haemorrhages spread
along the nerve fibre layer, so they align with the local vessel direction, which
the vessel map already gives you.

---

## 7. Neovascularization

New, fragile vessels growing in response to ischaemia. **This is what makes DR
proliferative (grade 4)** and it is the sight-threatening endpoint.

| | Location |
|---|---|
| **NVD** | at or within 1 DD of the optic disc |
| **NVE** | elsewhere |

### What distinguishes them from normal vessels

- fine calibre
- high tortuosity, convoluted loops
- irregular branching that ignores the normal dichotomous arcade pattern
- abnormally high local vessel density

### Algorithm

```
Step 1  vessel map from component 1
Step 2  slide a window (~1 DD = 124 px) over the vessel map
Step 3  per window compute:
            vessel density
            branchpoint count       bwmorph(skel,'branchpoints')
            endpoint count          bwmorph(skel,'endpoints')
            tortuosity = arc length / chord length, per segment
            calibre variance along each segment
            fractal dimension (box-counting)
            orientation entropy
Step 4  classify each window
Step 5  NVD if the window centre is within 1 DD of the OD, else NVE
```

**This is the component APTOS can least support.** There are no NV annotations
anywhere in the dataset, and grade-4 images are only 295 of 3,662. Weak
supervision from the grade column is the only available signal — see below.

---

## 8. Quadrants and the 4-2-1 rule

Severe NPDR (grade 3) is defined by the **4-2-1 rule** — any of:

- \> 20 intraretinal haemorrhages in **each of 4** quadrants, **or**
- definite venous beading in **2**+ quadrants, **or**
- prominent IRMA in **1**+ quadrant

This is **spatial and quantitative**, so it needs per-quadrant counts oriented
correctly.

```matlab
axis  = atan2(fovea(2)-od(2), fovea(1)-od(1));   % OD -> fovea
ang   = mod(atan2(yy-cy, xx-cx) - axis, 2*pi);   % rotate into that frame
quad  = floor(ang / (pi/2)) + 1;                 % 1..4
```

> Note this differs from [B]'s `splitRegions`, which uses **frame axes** because
> [B] runs before any anatomy is known. For clinical counting the quadrants must
> be anchored to the **OD–fovea axis** — superior/inferior × temporal/nasal.

**Venous beading** — calibre variance along venous segments — has no ground
truth anywhere. Compute it, report it, and label it explicitly as unvalidated.

---

## Validation with APTOS only

No lesion masks exist, but **the grade column is a real label**, and each
detector makes a testable prediction:

| Detector | Prediction from the grade column |
|---|---|
| Microaneurysms | grade 1 is *defined* as "MAs only" — MA count must separate 0 from 1+ |
| Haemorrhages | count rises monotonically with grade |
| Exudates | area correlates with grade ≥ 2 |
| Neovascularization | fires almost only on grade 4 |
| Vessels | removing them should *improve* dark-lesion → grade correlation |

**If a detector's output predicts grade above chance, it is finding real
pathology. If it does not, it is finding noise.**

Two conditions:

1. **Measure within resolution strata.** Raw correlation would re-measure the
   82.3% acquisition confound, not the detector.
2. It validates *"detects something disease-related"*, **not** *"93% pixel-level
   sensitivity"*. Weaker claim, but honest and defensible.

The 4-2-1 rule gives a second, harder test: reconstruct grade 3 from per-quadrant
haemorrhage counts and see whether it agrees with the label.

---

## Algorithm analysis — all 8 components

One table per component: the candidates, the trade-off that decides between them,
and the verdict. **`M` = measured on APTOS. `R` = reasoned from literature or
geometry, not yet tested.**

### 1. Vessels

| Candidate | Cost | Strength | Weakness | |
|---|---|---|---|---|
| **Frangi (multi-scale Hessian)** | 855 ms | correct topology; no training data | severe under-segmentation at Otsu | **M** |
| Matched filter (12 orientations) | 736 ms | good widths | fragments badly (60 comps) | **M** |
| Morphological (linear SEs) | **61 ms** | right coverage, 14× faster | 2,953 branchpoints — confetti | **M** |
| U-Net | fast inference | AUC 0.98 vs 0.92 | **needs labels — unavailable** | R |

**Verdict: Frangi**, with the scale bank bounded to 2.7–10 px. Threshold still
unresolved; hysteresis was tested and rejected.

### 2. Optic disc

| Candidate | Cost | Result | |
|---|---|---|---|
| **disc-sized mean on green** | **27 ms** | best physiology (bright 3.02, struct 2.14) | **M** |
| centre-surround | 54 ms | +2.8pp agreement, 2× cost, worse physiology | **M** |
| local variance | 26 ms | median 0.707 R — anatomically impossible | **M** |
| Hough | 62 ms | **failed on 22/60** | **M** |
| template match | 32 ms | struct 1.19 — locks onto any bright blob | **M** |

**Verdict: disc-sized mean on green, search ≤ 0.6 R.** The search region did more
than any detector refinement (median 0.546 → 0.445 R).

### 3. Fovea

| Candidate | Strength | Weakness | |
|---|---|---|---|
| **geometric from OD + vessel penalty** | needs no training; uses existing outputs | inherits all OD error | R |
| darkest-region search alone | trivial | picks vessel shadows and the macula edge | R |
| template matching | robust to noise | fovea has no consistent template | R |
| CNN regression | best published | needs coordinates — unavailable | R |

**Verdict: geometric, with the avascularity penalty.** The fovea is *avascular*,
so a dark patch full of vessels is a shadow — penalising vessel density is what
separates the two. Sanity-check OD–fovea distance at 2.2–2.8 DD.

### 4. Microaneurysms

| Candidate | Strength | Weakness | |
|---|---|---|---|
| **morphological closing, 12 linear SEs** | no training data; exploits shape directly | ~100+ candidates/image, needs a classifier | R |
| matched Gaussian filter | cheap | fires on any dark blob | R |
| Radon / wavelet | scale-selective | more parameters, no clear gain | R |
| patch-CNN | best published | needs labels — unavailable | R |

**Verdict: morphological closing + candidate classifier.** The vessel/MA
discrimination is geometric — a vessel survives closing along its own direction,
a compact MA is filled by every orientation. **Must run at native resolution.**

### 5. Exudates

| Candidate | Strength | Weakness | |
|---|---|---|---|
| **morphological reconstruction** | clean bright-lesion isolation | needs OD masked first | R |
| dynamic/adaptive threshold | one call | fires on the OD and on glare | R |
| `imextendedmax` | one call, close to reconstruction | less control over `h` | R |
| U-Net | AUPR ≈ 0.80 published | needs labels | R |

**Verdict: reconstruction, after OD masking.** Hard-vs-soft split on the **blue
channel** — yellow hard exudates are low-blue, white cotton-wool is high-blue.

### 6. Haemorrhages

| Candidate | Strength | Weakness | |
|---|---|---|---|
| **reuse the MA dark-lesion pipeline, split at 8.4 px** | free — same machinery | inherits every MA false positive | R |
| independent region growing | better boundaries | duplicates work | R |

**Verdict: reuse the MA pipeline.** Subtype (flame vs dot/blot) from
**alignment with the local vessel direction** — flame haemorrhages spread along
the nerve fibre layer, and the vessel map already supplies that orientation.

### 7. Neovascularization

| Candidate | Strength | Weakness | |
|---|---|---|---|
| **vessel-map texture in sliding windows** | reuses the vessel map | vessel map is not yet reliable | R |
| tortuosity/fractal descriptors | physically motivated | no threshold available | R |
| CNN on vessel patches | best published | needs labels; only 295 grade-4 images | R |

**Verdict: build it, do not trust it.** This is the component APTOS supports
least — no NV annotations exist anywhere in the dataset. Report it as
unvalidated.

### 8. Quadrants / 4-2-1 rule

| Candidate | | |
|---|---|---|
| **OD–fovea axis** | clinically correct orientation | R |
| frame axes | wrong — but what [B] uses, because it runs before anatomy | **M** |

**Verdict: OD–fovea axis**, once both localisers are trusted. Note this
deliberately differs from [B]'s `splitRegions`.

### Summary — confidence by component

| Component | Verdict | Confidence |
|---|---|---|
| Optic disc | disc-mean on green, r ≤ 0.6 R | **measured**, but failure rate unknown |
| Vessels | Frangi, scales 2.7–10 px | **measured as not-yet-working** |
| Fovea | geometric + avascularity | reasoned |
| Microaneurysms | morphological closing + classifier | reasoned |
| Exudates | reconstruction after OD mask | reasoned |
| Haemorrhages | MA pipeline + size split | reasoned |
| Neovascularization | vessel texture | reasoned, weakest |
| Quadrants | OD–fovea axis | reasoned |

**Two of eight are measured. Six are designed.** Nothing in Module 2 is
production-ready, and vessels — which gate half the pipeline — are actively
known to be broken at present settings.

---

## Failure modes

| Component | Failure | Symptom | Guard |
|---|---|---|---|
| Vessels | threshold too low | background speckle becomes "vessels" | `bwareaopen(bw,40)`; check total vessel fraction is 8–15% of retina |
| Vessels | under-segmentation at faint edges | half-removed vessels look like MAs | **dilate the vessel mask 2–3 px before subtracting** |
| Optic disc | glare patch instead of the disc | low `struct` score | search region ≤ 0.6 R; check `bright`/`struct` |
| Fovea | picks a vessel shadow | dark but vascular | penalise vessel density in the score |
| Fovea | wrong side (nasal not temporal) | OD–fovea distance still ~2.5 DD | pick the darker, more avascular candidate |
| MAs | vessel fragments survive | count correlates with vessel density, not grade | longer linear SE; increase vessel dilation |
| MAs | denoising upstream | recall collapses silently | never denoise before MA detection — [F] |
| Exudates | **optic disc not masked** | a false exudate in every image | mask 1.2 × OD_R — non-negotiable |
| Exudates | CLAHE applied upstream | 20% contrast loss | [F]: measurement stream gets no CLAHE |
| Haemorrhages | size split miscalibrated | MAs and haemorrhages swap | recheck px/um after any change to `targetR` |
| All | image not radius-normalised | every size threshold is wrong | run [A] first, always |

---

## Next

Implementation order, given APTOS-only:

1. **Vessels (Frangi)** — no training data needed, gates everything else,
   validated by "does removing them improve the lesion→grade signal?"
2. **Fovea** — cheap once vessels exist, and completes the OD–fovea axis
3. **Microaneurysms** — the long pole; budget the most time
4. **Exudates**, then **haemorrhages** — reuse the machinery from 1 and 3
5. **Neovascularization** — last, and least supportable on APTOS

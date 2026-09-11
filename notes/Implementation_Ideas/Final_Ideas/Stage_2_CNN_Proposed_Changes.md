# Stage 2 — Proposed Changes

**Companion to `Stage_2_CNN`. That file is unchanged — this one is written in
parallel so both can be compared side by side.**

Claims are checked against our built-and-measured Module 2 implementation
(`code_testing/python/extract_module2_features.py`, 309 images extracted) and
against the 3,662-image APTOS feature table.

**Nothing here is applied. These are proposals for you to accept or reject.**

| Severity | Meaning |
|---|---|
| 🔴 **FATAL** | measured to fail; will produce camera-identity or wrong-signed results |
| 🟠 **MAJOR** | conceptual error, or omits a term we measured as essential |
| 🟡 **MINOR** | specification gap or sequencing detail |

---

## Summary

| ID | Section | Severity | Change | Decision |
|---|---|---|---|---|
| F1 | Pre-Feature Eng. | 🔴 FATAL | Replace absolute RGB ranges with **ratios + local contrast** | ☐ |
| M1 | Vessels (b) | 🟠 MAJOR | Calibre comes from **scale σ**, not Frangi `rb` | ☐ |
| M2 | Vessels (b) | 🟠 MAJOR | Venous beading = **calibre variance along a segment** | ☐ |
| M3 | Optic Disc | 🟠 MAJOR | Vessels **converge at** the disc — don't exclude them | ☐ |
| M4 | Fovea | 🟠 MAJOR | Add the **avascularity penalty**; darkness alone fails | ☐ |
| M5 | Vessels (c) | 🟠 MAJOR | NV by **fine-scale excess**, not density | ☐ |
| M6 | Feature Eng. | 🟠 MAJOR | Make the **classifier stage explicit** (proven 4×) | ☐ |
| m1 | Optic Disc | 🟡 MINOR | Run OD on **raw** green, never shade-corrected | ☐ |
| m2 | Segmentation | 🟡 MINOR | Tie the `m × m` label grid to the scale table | ☐ |
| m3 | Quadrants | 🟡 MINOR | Recalibrate the 4-2-1 constant; 20 fires on nothing | ☐ |
| m4 | ordering | 🟡 MINOR | Insert a sharpness gate before lesion counting | ☐ |

---

# 🔴 FATAL

## F1 — absolute colour ranges will learn the camera, not the disease

**Current:**

> "first find spots of expected colour range in retina area … with heamorrage
> (R: a-b, G: c-d, B: e-f), Hard Exudates (R: a-b, …), Nerve Fibre Ischemia (R:
> a-b, …)"

**This is the one change I would argue hardest for.** We have already run this
experiment, unintentionally.

**What happened.** Our first microaneurysm classifier included absolute colour
features and reported **AUC 0.995**. It was false. The top features were
`r_mean` (0.237) and `b_mean` (0.204) — **it had learned camera identity**.
Banning absolute-intensity features dropped it to an honest **0.742**, and the
top features became shape and contrast (`gauss_res` 0.222, `ecc_r` 0.170,
`contrast` 0.145).

**Why fixed RGB windows cannot work across cameras:**

```
Module 2 features already predict image RESOLUTION at 67.8% (chance 17%)
Resolution ALONE predicts referable DR at AUC 0.809
```

APTOS spans multiple camera models, years and operators. White balance, flash
intensity and exposure all shift the absolute RGB of the *same lesion* between
images. A window `(R: a-b, G: c-d, B: e-f)` tuned on one camera selects
background on another.

**Proposed replacement — same information, camera-invariant:**

```
INSTEAD OF                        USE
absolute R, G, B windows    ->    b_over_g = mean(B)/mean(G)     <- key
                                  r_over_g = mean(R)/mean(G)
                                  saturation (HSV S)
absolute brightness         ->    local_contrast = candidate vs 12-24 px annulus
                                  bg_ratio      = candidate mean / local background
"expected colour range"     ->    gradient_mag_rim  (edge sharpness)
```

**These separate the three target classes on physics, not on levels:**

| Lesion | `b_over_g` | Edge | Where |
|---|---|---|---|
| Haemorrhage | low (dark, red) | moderate | anywhere, off-vessel |
| Hard exudate | low–mid, **saturated yellow** | **sharp** | often clustered/ring |
| Nerve-fibre ischaemia (cotton-wool) | **high — pale/white** | **gradual** | along nerve fibres |

The yellow-vs-white distinction between hard exudate and cotton-wool spot is
exactly a **blue/green ratio** question — which is why the blue channel exists in
this pipeline at all. An absolute-range spec throws that away.

> ⚠ This matters more than usual for you specifically: our exudate detector is
> currently **inverted** (healthy eyes get 57 marks, diseased eyes 17–23),
> almost certainly because a brightness threshold cannot tell a hard exudate from
> the **specular reflex** in young glossy retinas. `b_over_g` plus edge sharpness
> is the most likely fix. See `workneed.md`.

**Cost:** none — these are the same per-candidate measurements, expressed as
ratios.

---

# 🟠 MAJOR

## M1 — Frangi `rb` does not measure vessel calibre

**Current:**

```
(b) Use FRANGI ... -> venous beading (super high rb) -> 0
                   -> major vessel (big rb)          -> 1
                   -> 1st branch (small rb)          -> 2
                   -> minor vessel (super small rb)  -> 3
```

**The error.** In Frangi's formulation `rb = |λ₁| / |λ₂|` is a **blobness**
ratio — it distinguishes *tube-like* from *blob-like* structure. It is
deliberately constructed to be **scale-invariant**, so it carries almost no
information about how thick a vessel is.

**Calibre comes from the scale σ at which the multi-scale response peaks:**

```
for sigma in sigmas:            # sigma ~ vessel_radius / sqrt(2)
    V[sigma] = frangi_response(I, sigma)
V_final(x)   = max over sigma of V[sigma](x)
calibre(x)   = argmax over sigma   <- THIS is the width estimate
```

**We confirmed scale is the operative lever.** Adding σ = 1.2 px (= 18 µm, below
the smallest real vessel at 40 µm) changed measured branchpoints from 195 to
**2,539** — a 13× swing from a scale change alone.

**Proposed:** keep the 4-level calibre tiering, but derive it from `argmax σ`,
and anchor the boundaries to the scale table:

```
vessel width band 40-150 um  =  2.7-10.1 px   (at 14.9 um/px)
  major arcade    >  7 px
  1st branch      4-7 px
  minor vessel    2.7-4 px
  below 2.7 px    -> not a vessel, reject
```

**Bonus:** our production path uses an analytic width, `w ≈ 4 × mean(EDT)`, with
`L ≈ area / w` — **160× faster than skeleton thinning** (which cost 10.4 s/image).
Worth considering if Frangi's multi-scale pass proves expensive.

---

## M2 — venous beading is a variance along a segment, not a value at a point

**Current:** "venous beading (super high rb) -> 0", i.e. detected as a per-pixel
Frangi response.

**The error.** Beading is *sausage-like calibre variation along a vein*. It is
defined by how width **changes** along the centreline. No per-pixel measure can
express it, because a single point has no variation.

**Proposed:**

```
1. skeletonise the vessel map
2. split the skeleton at branchpoints into segments
3. per segment, walk the centreline sampling width w(s) = 2 * EDT(s)
4. beading score = std(w) / mean(w)          # coefficient of variation
5. flag a segment if CV > threshold AND it is venous (veins are darker
   and wider than the neighbouring artery)
6. 4-2-1 criterion: beading present in 2+ quadrants
```

**Honest caveat:** venous beading is annotated in essentially **no** public
dataset, so this can be built but not validated. Report it as an unvalidated
feature. That is still worth doing — it is one of the three pathways to grade 3,
and we currently implement only one of them.

---

## M3 — the optic disc is where vessels converge, so don't exclude them

**Current:**

> "Use brightness data as the only primary algorithm. **-> Avoid regions with
> blood vessel detected** (to avoid confusion)."

**The error.** All major retinal vessels **enter the eye through the optic
disc**. Vessel density is *maximal* at the disc, not minimal. Excluding
vessel-dense regions pushes the search **away from the correct answer**.

Vessel convergence is a standard OD **localization cue** — fit the directions of
the major vessels and find where they intersect.

**Proposed:**

```
INSTEAD OF:  score = brightness, masked to exclude vessel regions
USE:         score = disc-sized mean brightness            (primary)
             + centre-surround confirm                     (yours, correct)
             + vessel convergence as a TIE-BREAKER         (attracts, not repels)
             search restricted to r <= 0.6 R
```

**Measured on our implementation:** disc-mean on raw green with `r ≤ 0.6R` gives
`od_bright` median **3.02** at **27 ms/image**. The `r ≤ 0.6R` restriction is
what suppresses the peripheral-glare false positive — that, not vessel exclusion,
is the guard you want.

**Your centre-surround confirmation step is correct and should stay** — it is the
algorithm we selected.

---

## M4 — the fovea needs the avascularity term, not just darkness

**Current:** travel from OD centre ±1.5× expected location, ±25° tilt, "choose
the spot which is the most darkest", then confirm brightness rises radially.

**The gap.** Darkness alone does **not** find the fovea — it finds **vessel
shadows**, which are darker than the foveal pit and far more numerous. We
measured this directly; the search was unusable until the vessel term was added.

**Proposed:**

```
score(x,y) = centre_surround_darkness(x,y) - 3.0 * local_vessel_density(x,y)
search annulus: 2.1 - 2.9 DD from the OD centre
```

The `−3.0 ×` weight is the measured value. The fovea is the **avascular** zone —
that is its defining anatomical property, and it is a stronger discriminator than
darkness.

Your "brightness increases radially" test is the centre-surround half and is
correct; it just needs the avascularity half alongside it.

**Two cautions from our implementation:**

1. **±1.5× is very wide.** If the expected location is 2.5 DD, ±1.5× spans
   1.25–3.75 DD, which will admit the OD's own dark rim at the near end. We use
   2.1–2.9 DD.
2. **A result inside the search annulus is not a validation.** Our
   `fovea_od_dd` is "100% within 2.1–2.9 DD" — but that is the *constraint*, and
   it can never report anything else. We made this circular-validation error
   earlier in the project; worth not repeating.

---

## M5 — neovascularization by density is measured wrong-signed

**Current:** "neovascularisation (high density) -> 1, IRMA (low density) -> 2".

**Measured:** we implemented exactly this and it failed.

| Approach | within-stratum ρ |
|---|---|
| density extreme (p99.5) | **−0.391** — wrong-signed |
| density × orientation incoherence | −0.307 … +0.279 — incoherent |
| **fine-scale excess** | **+0.438** ✓ |

**What worked, and why.** Neovascular vessels are **thin**. Detect at a fine and
a coarse scale separately; NV is what responds to fine but *not* coarse:

```
fine   = line_detector(green, L=9,  W=11)
coarse = line_detector(green, L=31, W=31)
excess = (fine > p92) AND NOT dilate(coarse > p92, 5x5)
nv_fine = 100 * |excess| / |FOV|
```

This is the most robust feature in our Module 2 — ρ +0.314…+0.409 across **every**
sharpness band, where the dark-lesion features collapse.

**On IRMA vs NV:** they are not separable by density. IRMA are **intraretinal**
(within the retinal layers, non-leaking); NV are **preretinal** (growing forward
into the vitreous). The distinction is depth and leakage, not local density —
which is why fluorescein angiography is the clinical discriminator. On colour
fundus alone, treat "IRMA vs NV" as a single abnormal-vessel class unless you
obtain FGADR, which annotates both.

**Blunt caveat:** `nv_fine` correlates with *grade*, and has **never been
compared to actual neovascularization**, because APTOS has no NV annotations.
~50 hand-annotated grade-4 images would settle whether it detects anything real.

---

## M6 — make the classifier stage explicit in the workflow

**Current:** the document has "Pre-Feature Engineering" and "Feature Engineering"
headings, but the **classifier** is not drawn as a step.

**Why it matters — this is the single most transferable result from our Module 2
work.** Four separate components followed the same arc:

| Component | Threshold only | + per-candidate features & classifier |
|---|---|---|
| Microaneurysms | ρ **−0.117** | ρ **+0.508** |
| Haemorrhages | ρ **0.036** | ρ **+0.553** |
| Exudates | ρ −0.196 | *(never applied — still broken)* |
| 4-2-1 quadrants | fired 2/70, wrong images | fires only at grades 3–4 |

**Every component that stopped at thresholding failed. Every one that added
features + a classifier worked.**

**Proposed — state the five steps explicitly:**

```
1 preprocess (green, shade-correct)
2 subtract vessels (dilate the mask 2-3 px first)
3 threshold -> CANDIDATES (high recall, terrible precision, 100+ per image)
4 per-candidate FEATURES  (ratios/shape/contrast/context - never absolute level)
5 CLASSIFIER -> keep/reject       <- the step that is currently implicit
```

Two implementation notes we paid for:

- **Scale-matched structuring elements.** One SE cannot serve both an 8 px
  microaneurysm and a 30 px haemorrhage — closing only fills what the line
  *bridges*. Use L=15 for MA and **L=41** for haemorrhage. This alone took
  haemorrhage counts from a median of 0 to 79–118.
- **Choose the classifier threshold on a criterion fixed in advance**, e.g.
  "the lowest probability at which the grade-0 median count is 0". Choosing it to
  maximise ρ, then reporting that ρ, is circular — we caught ourselves doing it.

---

# 🟡 MINOR

## m1 — run optic-disc detection on raw green

Not stated in the current document, and it cost us real accuracy. If the green
channel is shade-corrected before OD detection, the background estimate
(σ ≈ 60 px) is **smaller than the disc** (124 px), so the disc is divided out of
its own image.

```
od_bright fell 2.99 -> 1.87 on EVERY image; one detection moved 465 px
```

**Vessels want shade-corrected green; the optic disc wants raw green.** Worth
stating explicitly since the pipeline computes both.

## m2 — tie the `m × m` label grid to the scale table

"Segmentation: a label per (m x m) pixels (except vessel)" leaves `m` undefined.
Since the scale table fixes 14.9 µm/px, `m` should be expressed in microns so it
survives resizing:

```
m = 4 px = ~60 um   ->  one cell per typical microaneurysm
m = 8 px = ~120 um  ->  one cell per MA/haemorrhage boundary lesion
```

Anything coarser than ~8 px cannot represent a microaneurysm at all.

## m3 — the 4-2-1 constant does not transfer

"Apply count function to verify with 4-2-1 rule!" — as written the rule is
*>20 haemorrhages in each of four quadrants*. Measured:

```
threshold >20 : fires on 0/70 images at EVERY grade, including grade 3
threshold >3  : 93% specificity (g0-2), 64% sensitivity (g3-4)
```

The constant 20 assumes a clinician on a **dilated seven-field** examination. A
detector on a single 45° field sees a different sample of retina. **Re-derive the
constant against your own detector** and store the raw per-quadrant counts
unthresholded so it can be refitted without re-extracting.

## m4 — insert a sharpness gate before lesion counting

Module 1's gate decides whether an image is worth *keeping*. Lesion counting
needs a **stricter, separate** bar. Measured, within-stratum ρ above the cut:

| Cut | keeps | `hem_n` | `q_max` | `nv_fine` |
|---|---|---|---|---|
| none | 100% | 0.157 | 0.041 | **0.394** |
| **median varLapNorm** | 50% | **0.387** | **0.335** | 0.312 |
| 70th pctile | 30% | 0.569 | 0.556 | 0.035 |

There is a **step change**, not a gradient — so a cut is the right shape of fix.

**But it must be per-feature:** the gate roughly triples `hem_n` and **halves
`nv_fine`**. Write it as a flag, not a filter, and let each feature use the
population it works on.

---

# Confirmed correct — no change proposed

| Section | Item | Why it is right |
|---|---|---|
| **SCALE TABLE** | "percentage-wise radius & area per element" | **Exactly right, and the foundation everything rests on.** Without radius normalisation, "125 µm = 8.4 px" is false and every size threshold is meaningless |
| Localization | output `(x, y, r)` | correct, and `r` "irrespective of circularity" is the right call — the fit radius is robust where circularity is not |
| Vessels (a) | matched filtering for main + 1st branch | sound; Chaudhuri matched filters are the classic method and cheap |
| Vessels (a)+(b) | two-pass: fixed-width first, then unrestricted | good structure — a reliable backbone then a sensitive pass |
| Optic Disc | centre-surround confirmation | this is the algorithm we selected |
| Fovea | no radius in output, fovea not macula | correct — the fovea is a point, the macula is a region |
| Pre-Feature Eng. | exclude fovea, OD and vessels before lesion search | **correct and non-negotiable** — OD masking alone prevents a false exudate on every single image |
| Quadrants | draw quadrants, then count, then 4-2-1 | right order, and the OD–fovea axis is the correct frame |

---

# If you only take two

1. **F1** — replace absolute RGB ranges with ratios. We have already measured
   what absolute colour does: a false AUC of 0.995 that was reading camera
   identity. This will happen again, and it will look like success.
2. **M6** — draw the classifier as an explicit step. Four components, four times,
   the same result: thresholding alone fails, features + classifier works.

M1–M5 are each a contained fix to one component. F1 and M6 are structural and
affect everything downstream.

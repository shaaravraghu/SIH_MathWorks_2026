# Stage 1 — Proposed Changes

**Companion to `Stage_1_CNN`. That file is unchanged — this one is written in
parallel so both can be compared side by side.**

Every claim below is checked against the 3,662-image APTOS set via
`data/aptos_train_module1_features.csv`. Section numbers (#1, #2.1, …) refer to
the original document.

**Nothing here is applied. These are proposals for you to accept or reject.**

| Severity | Meaning |
|---|---|
| 🔴 **FATAL** | will misbehave on correctly-captured images as specified |
| 🟠 **MAJOR** | works, but leaves significant accuracy or safety on the table |
| 🟡 **MINOR** | polish, typo, or small efficiency correction |

---

## Summary

| ID | § | Severity | Change | Decision |
|---|---|---|---|---|
| F1 | #2.2 | 🔴 FATAL | Make the black-region gate aspect-aware, or replace with `areaFrac` | ☐ |
| F2 | #2.1 | 🔴 FATAL | Disambiguate "circularity" — do **not** use 4πA/P² | ☐ |
| M1 | #3 | 🟠 MAJOR | Set sharpness thresholds **per camera**, not globally | ☐ |
| M2 | #3 | 🟠 MAJOR | Remove `specSlope` from the gate (keep as a feature) | ☐ |
| M3 | #3 | 🟠 MAJOR | Keep `regionMin` — do not drop it | ☐ |
| M4 | #1 | 🟠 MAJOR | Gate on **retinal diameter in px**, not megapixels | ☐ |
| m1 | #2.2 | 🟡 MINOR | Black is RGB (0,0,0), not (255,255,255) | ☐ |
| m2 | #3.1–3.3 | 🟡 MINOR | Crop patches; masking a full-image filter saves nothing | ☐ |
| m3 | #3.2/3.3 | 🟡 MINOR | Identical text in two different sections | ☐ |
| m4 | #4.2 | 🟡 MINOR | "blood vessels with high R value" is inverted | ☐ |
| m5 | #4.2 | 🟡 MINOR | Route CLAHE output to the display stream only | ☐ |

---

# 🔴 FATAL

## F1 — #2.2 the black-region gate rejects correct framing

**Current:** black region must be 15–35% (or 40%). Premise: "ratio of circle
circumscribed by square is 78.5%".

**Measured consequence:**

```
gate 15-35%  ->  rejects 25.1% of ALL images
                 by grade: g0=36%  g1=9%  g2=14%  g3=27%  g4=15%
```

**Why it fails.** The 78.5% figure only holds for a **square** frame. Only 974 of
3,662 APTOS images are 1:1.

| Aspect ratio | Count | Inscribed circle | Black region | vs gate |
|---|---|---|---|---|
| 1.00 | 974 | 78.5% | 21.5% | ✓ passes |
| **1.33** | 680 | 59.1% | **40.9%** | ✗ **fails** |
| **1.39** | 638 | ~56% | **~44%** | ✗ **fails** |
| **1.51** | 489 | 52.4% | **47.6%** | ✗ **fails** |

A **perfectly captured** 4:3 image has ~41% black and is rejected. The gate is
measuring aspect ratio, not quality.

**Proposed — pick one:**

**Option A (minimal change).** Make the bound a function of aspect ratio `a`:

```
expected_black(a) = 1 - pi / (4*a)        for a >= 1
accept if  |black_measured - expected_black(a)|  <  0.12
```

**Option B (recommended).** Drop the black-region test and use **`areaFrac`** —
captured retinal area / πR², already computed in Module 1. It is
aspect-independent by construction, because it compares the retina to its own
fitted circle rather than to the frame.

```
areaFrac  ~0.89 typical,  < 0.50 reject
```

**Why B is better:** it answers the question you actually care about — *is part
of the retina missing?* — instead of *what shape is the file?*

---

## F2 — #2.1 "circularity" is ambiguous, and one reading is broken

**Current:** circularity 0.85–1.15, with a stated compute shortcut of
`(radius_v − radius_h) / mean_radius`.

**The problem:** "circularity" conventionally means `4πA/P²`, and that metric is
unusable here:

```
measured 4*pi*A/P^2 :  p5 0.627   median 1.071   p95 1.212
outside 0.85-1.15   :  53.5% of all images
... among images whose circle-fit residual says they are FINE (<0.02): 53.0%
```

**It fires on more than half of demonstrably good images.** The cause is that a
ragged boundary inflates the perimeter, and P is **squared** in the denominator —
so boundary noise dominates the measurement. We hit this exact failure earlier in
the project and abandoned the metric.

**The good news:** your own shortcut formula is a **different and much better
measure**. `(radius_v − radius_h)/mean_radius` is an aspect/eccentricity ratio
that never touches the perimeter, so boundary raggedness cannot corrupt it.

**Proposed:** state explicitly that the metric is the **radius-ratio**, not
4πA/P². Optionally add the fit residual as the shape test:

```
residual = mean| dist(boundary_point, centre) - R | / R
           < 0.01  good      > 0.06  reject
```

**Cost:** wording change if you keep the radius-ratio. The residual is already
computed.

---

# 🟠 MAJOR

## M1 — #3 sharpness thresholds must be per-camera

**This is the most consequential item in the document.**

**Current:** single global thresholds on Brenner, varLapNorm, TenengradVar.

**The measured problem:** a global sharpness floor rejects **sick patients 3.4×
more often than healthy ones**:

```
gate_reject rate by grade
  grade 0: 3.8%    grade 2: 12.3%    grade 4: 12.9%
```

**Why — and this is the non-obvious part.** It looks like diseased retinas are
blurrier. They are not. Comparing pooled correlation against correlation computed
**within a single camera**:

| Metric | pooled ρ | **within-camera ρ** |
|---|---|---|
| varLapNorm | −0.243 | **−0.022** |
| tenengradVar | +0.508 | **+0.012** |
| brenner | −0.365 | **+0.040** |
| noiseSigma | +0.347 | **+0.010** |

**Within a camera, sharpness does not track disease at all.** The entire apparent
correlation is that sicker patients were photographed on different equipment. A
single global threshold therefore acts as a *camera filter*, and because camera
correlates with grade, it silently filters by disease.

**Proposed:**

```
threshold(metric) = percentile_p( metric | images of the same resolution )
```

i.e. calibrate each cut-off within its resolution stratum rather than once
globally. Resolution is known at gate time, so this costs nothing at inference —
only a per-stratum table computed once offline.

**Expected gain:** removes most of the 3.4× skew. This also reconciles the
document with `Module1_Results.md`, whose ρ 0.067 for TenengradVar was a
within-stratum figure and is essentially correct.

**Also recommended regardless:** never *discard* a rejected image. Route it to a
human. A screening system that refuses to read the patients most likely to need
referral is a clinical hazard even when the refusal is individually justified.

---

## M2 — #3 remove `specSlope` from the gate

**Current:** "SpecSlope can cleanly identify blood vessels (so crucial)."

**The problem:** `specSlope` is the **one** focus metric that retains real
disease correlation after stratification:

| Metric | within-camera ρ |
|---|---|
| varLapNorm | −0.022 |
| tenengradVar | +0.012 |
| brenner | +0.040 |
| **specSlope** | **+0.171** |

Per-stratum it runs +0.13, +0.11, +0.28, +0.34, +0.23, +0.03, +0.08 — positive
in all seven. Median by grade: 2.12 → 2.46 → 2.85 → 3.04 → 2.76.

Gating on a disease-correlated metric means **rejecting images because the
patient is sick**.

**Proposed:** keep `specSlope` as an input *feature* to the quality classifier,
but never as a standalone rejection threshold. This is the same rule already
recorded in `Module1_Results.md`: *any feature with |ρ| > 0.3 must not be a
rejection gate.*

---

## M3 — #3 keep `regionMin`

**Current:** "Region Min can be avoided since a focused shot with medical grade
cameras is unlikely to [fail]".

**Two objections:**

1. **The premise contradicts the problem statement.** The deployment scenario is
   portable cameras operated by technicians with two days' training in a PHC —
   explicitly *not* medical-grade conditions. The techniques doc estimates
   15–25% garbage capture rate.
2. **`regionMin` is the only Tier-1 metric that catches *partial* blur.** It is
   the minimum across five retinal regions, with measured **4,100× partial-blur
   sensitivity**. Global metrics average a locally-blurred region away — an image
   sharp everywhere except the macula passes every global test and is clinically
   useless.

**Proposed:** retain `regionMin` in the cascade. It is cheap (five region means
over an already-computed Laplacian).

---

## M4 — #1 gate on retinal diameter, not megapixels

**Current:** reject < 0.3 MP, borderline 0.3–1 MP, pass > 1 MP.

**The problem:** megapixels describe the **file**, not the retina. A tightly
cropped 0.8 MP image can resolve more retinal detail than a 4 MP image where the
retina occupies a third of the frame. What actually matters is **how many pixels
span the retina**, because that is what decides whether a lesion exists in the
data at all.

**Proposed replacement**, derived from the project scale table (retina spans
~13 mm; a typical microaneurysm is 60 µm):

```
retinal diameter D px   ->   um/px = 13000 / D   ->   MA size = 60*D/13000 px

REJECT      D < 432 px    (MA under 2 px - not recoverable)
BORDERLINE  432-648 px    (MA 2-3 px - detectable, unreliable)
PASS        D > 648 px    (MA over 3 px)
```

**Measured behaviour on APTOS:**

| Gate | rejected/borderline | g0 | g1 | g2 | g3 | g4 | spread |
|---|---|---|---|---|---|---|---|
| megapixels (#1) | 9.1% | 15.5% | 1.9% | 3.5% | 2.6% | 1.7% | 13.8 pts |
| **retinal diameter** | 5.6% | 8.6% | 0.5% | 3.5% | 3.1% | 2.4% | **8.1 pts** |

The diameter gate flags fewer images and is **~40% less disease-skewed**.

**Honest caveat:** neither gate is flat across grades. Both over-flag grade 0,
which is the *safe* direction — flagging a healthy patient costs a retake,
missing a sick one costs sight. But "safe direction" is not "unbiased", and the
residual skew should be reported.

**Note on the ChatGPT ">8 MP" conflict recorded in #1:** your reasoning for
rejecting it is sound. 8 MP is a property of expensive hardware, not of
gradability, and would reject most of the dataset. The diameter gate is the
principled version of the same instinct.

---

# 🟡 MINOR

## m1 — #2.2 colour typo

"Black-region of image: 15-35/40%; **RGB: (255,255,255)**" — (255,255,255) is
white. Black is (0,0,0). Worth fixing since it is a spec someone will implement.

## m2 — #3.1–#3.3 the sampling speedup will underdeliver as written

We implemented this exact optimisation — sample regions instead of the whole
image — **claimed 4.9× and measured 1.21×**. The cause: the implementation
*masked* a full-image filter rather than *cropping* the patches. Masking does not
skip the convolution; it only discards the result.

**Proposed:** crop each patch to its own small array and filter that. Also note
that estimating a **variance** from a 10% random sample is noisy, and blur is
often spatially local, so random sampling can miss exactly the defect
`regionMin` exists to catch. Prefer fixed regions (centre + four quadrants) over
random ones.

## m3 — #3.2 and #3.3 carry identical text

Both say "pick any random 8 sets of squares … perform the 2 functions on this!",
but #3.2 is Brenner and #3.3 is TenengradVar. Likely a copy-paste; worth
confirming the intended sampling differs (or stating deliberately that it is
shared).

## m4 — #4.2 "apply to certain elements (like blood vessels with high R value)"

Inverted on two counts: vessels are **dark**, not bright, and they are darkest on
**green**, not red. High R is the background retina. If the intent is "enhance
vessel contrast", the target is the green channel and the vessels are the dark
structures within it.

## m5 — #4.2 CLAHE output should not reach the measurement stream

CLAHE cost **20% MA detectability** in our measurements. Restricting it to
borderline images limits the damage, but any CLAHE'd image should go to the
**display/CNN** stream, with lesion detection run on the un-CLAHE'd version.
This is the two-stream split recommended in `Module1_F_Enhancement.md`.

---

# Confirmed correct — no change proposed

Worth recording explicitly, because two of these are **better than the standard
textbook advice** and should survive review:

| § | Item | Why it is right |
|---|---|---|
| **#4.1** | "Only apply at places with severely low/high illumination" | **Matches our measurement exactly.** Blanket enhancement scored *negative* on average; conditional illumination correction on illumination-failures scored **+0.65**. Your instinct beat the generic "always flat-field" advice |
| **#4.1** | Risk note: background estimation may suppress microaneurysms | Correct, and the reason denoising is banned entirely |
| **#4.1** | Estimate the field at reduced resolution, apply at full | Correct — the illumination field is low-frequency by definition, so downsampling costs nothing |
| #4 | "Plane and Radial Fit may fail because of features contradicting uniform ascent/descent" | Correct; this is why our gate-safe illumination features are `bgRadial`/`bgTiltMag`/`bgSpread`/`bgCV` rather than a single fit |
| #2 | "Not worried about offset" | Agreed — offset is misalignment, not quality, as long as the FOV is complete |
| — | Cascade structure with early exits, cheap tests first | Right shape and right ordering |
| #4.2 | Revert-on-failure logic | Correct, and rarely implemented |

---

# If you only take three

1. **F1** — the black-region gate rejects 25% of images including correctly
   framed 4:3 captures. Replace with `areaFrac`.
2. **M1** — per-camera sharpness thresholds. Removes most of the 3.4×
   sick-patient rejection skew, at no inference cost.
3. **F2** — confirm "circularity" means the radius-ratio, not 4πA/P².

F1 and F2 are wording/threshold changes. M1 is a one-off offline calibration
table. None require new algorithms.

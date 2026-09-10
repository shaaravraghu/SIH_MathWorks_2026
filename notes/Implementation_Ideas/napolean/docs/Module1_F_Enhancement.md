# Module 1, Stage [F] — Adaptive Enhancement

**Status: MEASURED.** This document replaces the earlier design spec. Every
number below comes from a run on APTOS 2019 (Ryzen 5 7535U); the spec's
recommended configuration did **not** survive testing.

---

## The verdict

> **Do not enhance blindly. [F] is only worth running on illumination failures,
> and only with a pure illumination corrector. Everything else makes the image
> measurably worse.**

| Old spec | Measured outcome |
|---|---|
| CLAHE + flat-field as the default path | **Worse than either alone** (−0.581 vs −0.103 / −0.275) |
| Denoising is the microaneurysm threat | **False — CLAHE is.** Denoising is neutral |
| Ben Graham "worth A/B testing" | **Worst of all 10 variants** (−1.118). Rejected |
| Re-score with [E] after enhancing | **Broken as written** — needs [E] retrained on enhanced images |

---

## How [F] was evaluated

Scoring [F] with [E] is **circular**: enhancement partially undoes the synthetic
degradation [E] was trained to detect, so [E] rewards it by construction. The
first run did exactly this and produced a meaningless 95.3% false-rescue rate.

The primary metric is therefore classifier-free — does enhancement move the
feature vector back toward **the clean original of the same eye**?

```
recovery = 1 − ‖z(enhanced) − z(clean)‖ / ‖z(degraded) − z(clean)‖

   +1.0 = fully restored     0 = no change     < 0 = made it worse
```

14 base images × 4 degradation types × 11 variants, 29-feature safe set.

---

## The recovery matrix — the central result

| Variant | blur σ2.6 | dark ×0.34 | **grad 0.85** | wash t0.40 | MEAN |
|---|---|---|---|---|---|
| none | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| gray-world | −0.328 | **+0.142** | −0.185 | **+0.092** | −0.070 |
| **CLAHE** | **+0.157** | −0.159 | +0.048 | −0.456 | −0.103 |
| **homomorphic** | −0.669 | −0.403 | **+0.650** | −0.499 | −0.230 |
| **flatfield** | −0.749 | −0.468 | **+0.647** | −0.528 | −0.275 |
| bg-subtract | −0.699 | −0.482 | **+0.613** | −0.626 | −0.299 |
| CLAHE+ff+NLM3 | −0.751 | −0.475 | +0.539 | −0.673 | −0.340 |
| CLAHE+ff+bilat.02 | −0.666 | −0.654 | +0.494 | −0.810 | −0.409 |
| CLAHE+flatfield | −0.642 | −1.178 | +0.467 | −0.971 | −0.581 |
| CLAHE+bgsub | −0.601 | −1.110 | +0.426 | −1.049 | −0.583 |
| **BenGraham** | −1.189 | −1.269 | −0.277 | −1.738 | **−1.118** |

**Every mean is negative.** No technique helps on average — blanket enhancement
is a net harm.

But the columns tell the real story: **each technique only helps the failure it
was designed for.**

- **Illumination gradient** → homomorphic **+0.650**, flat-field **+0.647**,
  bg-subtract **+0.613**. Strongly positive. An illumination corrector fixing an
  illumination problem.
- **Blur** → only CLAHE is positive (+0.157). Everything else is sharply
  negative, because **you cannot restore lost high frequencies** — dividing out
  an illumination field just adds distortion on top of a soft image.
- **Dark** → only gray-world (+0.142). CLAHE actively hurts (−0.159).
- **Wash** → nothing meaningfully helps (gray-world +0.092). Information
  destroyed by veiling does not come back.

### Combining techniques makes things worse

```
CLAHE alone        −0.103
flat-field alone   −0.275
CLAHE + flat-field −0.581      <- worse than either component
```

The spec's default path is the third-worst configuration tested. Stacking two
corrections compounds their distortions rather than their benefits.

### Ben Graham is rejected

−1.118 mean, and **negative even on the gradient column** (−0.277) where every
other illumination method scores > +0.6. It transforms the image so aggressively
that it is unrecognisable in quality-feature space.

This settles the spec's open question. Ben Graham may still belong in **Module
3's CNN input pipeline** — a CNN learns whatever representation it is handed, and
cross-camera normalisation is genuinely valuable there. It does **not** belong in
a stage whose output is re-scored by quality features or shown to a clinician.

---

## CLAHE is the microaneurysm threat — not the denoiser

The spec's central warning was about denoising deleting microaneurysms. Measured
with 110 injected 3–5 px dots per image:

| Variant | MA SNR | Retained |
|---|---|---|
| BenGraham | 9.227 | 107.7% |
| bg-subtract | 8.699 | 101.5% |
| homomorphic / flatfield | 8.650 | **100.9%** |
| *none* | 8.571 | 100.0% |
| CLAHE+ff+bilateral 0.02 | 7.174 | 83.7% |
| CLAHE+ff+NLM3 | 7.048 | 82.2% |
| CLAHE+bgsub | 6.950 | 81.1% |
| CLAHE+flatfield | 6.907 | 80.6% |
| **CLAHE alone** | 6.883 | **80.3%** |

**Every CLAHE-containing variant loses ~20% of MA detectability. Every
illumination-only corrector is free (100.9–101.5%).**

And adding a denoiser on top of CLAHE *improved* retention slightly (80.6% →
83.7% with bilateral) — because bilateral filtering cleans the surrounding
annulus, raising the contrast ratio.

> **The spec had this backwards.** Denoising is neutral-to-mildly-helpful at low
> strength. CLAHE is what costs you grade-1 findings, by amplifying local
> contrast in a way that flattens the small dark blobs against their background.

A separate strength sweep confirms the denoiser is safe up to **bilateral
σ_color ≈ 0.05** (retention 102.7%), degrading to 80.6% by 0.35.

> `gray-world` shows 1049% retention — an **artifact**. It rescales channels to a
> fixed mean, changing the absolute intensity scale, so its SNR is not comparable
> to the others. Ignore that row.

---

## The re-score step: broken as specified, and the fix

The spec's Step 5 — "feed the enhanced image back through [A]–[C] and hand the
vector to [E]" — cannot work as written.

| [E] training set | Tested on | AUC |
|---|---|---|
| plain only | plain | 0.998 |
| **plain only** | **enhanced** | **0.714** ← broken |
| plain + enhanced | plain | 1.000 |
| **plain + enhanced** | **enhanced** | **0.998** ← fixed |

Enhancement shifts the feature distribution — median |z| = 0.75 across the 29
features, with `bgCV` (1.27), `bgTiltDir` (1.16) and `bgSpread` (1.03) moving
most, exactly the [C] features flat-field targets. [E] has never seen that
region of feature space, so its output degrades to near-noise.

**Fix: train [E] on both plain and enhanced versions of every training image.**
Cost is one extra feature extraction per training sample; AUC on enhanced images
recovers from 0.714 to 0.998.

With [E] correctly trained, the rescue numbers become sane:

| Band | n | p before | p after | now passes |
|---|---|---|---|---|
| clear-pass | 155 | 0.074 | 0.066 | 100.0% |
| **BORDERLINE** | 17 | 0.493 | 0.307 | **76.5%** |
| **clear-fail** | 168 | 0.936 | 0.925 | **0.6%** |

**76.5% rescue, 0.6% false rescue** — against 100% / 95.3% from the broken
version. Clear-pass images are left essentially untouched (0.074 → 0.066), which
is the correct behaviour.

---

## Cost

| Step | ms |
|---|---|
| CLAHE | 30.5 |
| flat-field (1/8-scale estimate) | 119.2 |
| homomorphic | 146.6 |
| bg-subtract | 231.8 |
| BenGraham | 264.7 |
| NLM denoise | 1032.6 |
| re-extract features | 458.6 |

### A 9x speedup, already applied

Estimating the illumination field at full resolution (three σ=60 Gaussians on
872×872) cost **1642.8 ms**. Estimating it at **1/8 scale** costs **183.2 ms** —
the field is smooth by definition, so nothing is lost. Same trick [C]'s
`field_metrics` already uses.

**Avoid NLM** — 1032.6 ms for no measurable benefit over bilateral at 194.0 ms.

---

## Recommended configuration

[E]'s multi-label heads already identify the failure mode with **100% attribution
accuracy**, so routing is free — use it:

```
[E] head       action                              measured recovery
------------   ---------------------------------   -----------------
grad           flat-field  (or homomorphic)              +0.65
blur           DO NOT ENHANCE -- reject                  (-0.75 if you try)
dark           DO NOT ENHANCE -- reject                  (-0.47)
wash           DO NOT ENHANCE -- reject                  (-0.53)
noise          bilateral <= 0.05 only                    (neutral)
```

```matlab
% pseudocode
switch reason                       % argmax over [E]'s heads
  case 'grad'
      J = flatField(I, 'scale', 1/8);      % ~120 ms, MA-neutral
      rescore(J);                          % [E] MUST be trained on enhanced too
  otherwise
      reject(reason);                      % enhancement cannot help
end
```

**Total cost when it fires: ~580 ms** (120 ms flat-field + 459 ms re-extract),
and it only fires on the illumination-failure slice.

### Why not CLAHE

It is the cheapest technique (30.5 ms) and the only one that helps blurred images
(+0.157) — but it costs **20% of microaneurysm detectability** on every image it
touches, and grade 1 is defined as "microaneurysms only". Paying that on an
image whose blur is already borderline is a bad trade.

---

## What flat-field correction actually is

The one technique that earned a place in the measurement path, so it is worth
understanding rather than treating as a library call.

### The model

Illumination corruption is **multiplicative** — a gain that varies across the
frame:

```
observed(x,y)  =  true_retina(x,y)  x  illumination_field(x,y)
```

So the correction is a division:

```
corrected = observed / field * mean(field)
```

The `* mean(field)` restores the original overall brightness, so the image gets
*flatter*, not darker.

### Estimating a field you never measured

Blur the image heavily. Retinal structure — vessels, lesions, the disc — is
**high-frequency** and averages away. Illumination is **low-frequency** and
survives. So a heavily blurred copy *is* the illumination field.

```matlab
filled = I;  filled(~fov.mask) = mean(I(fov.mask));   % see gotcha below
bg = imgaussfilt(filled, 60);                         % ~7% of image width
J  = I ./ max(bg, 1e-3) * mean(bg(fov.mask));
```

The name comes from astronomy and microscopy: photograph a uniformly-lit blank
card — a "flat field" — to capture the instrument's response, then divide every
real image by it. Here there is no blank card, so the field is estimated from the
image itself.

### Worked in numbers

Two patches of **identical** retinal tissue, one central, one peripheral:

| | true tissue | illumination | observed | after ÷ field |
|---|---|---|---|---|
| centre | 0.50 | 1.0 | 0.50 | **0.50** |
| edge | 0.50 | 0.6 | 0.30 | **0.50** |

### Why it is microaneurysm-neutral (100.9%)

This is why flat-field is the only technique allowed near Module 2. Take a
microaneurysm in that dim peripheral region, 20% darker than its surroundings:

| | tissue | MA | observed pair | after ÷ 0.6 | contrast |
|---|---|---|---|---|---|
| edge | 0.50 | 0.40 | 0.30 / 0.24 | **0.50 / 0.40** | **still 20%** |

A microaneurysm and its immediate background are a few pixels apart, so the
smooth field assigns them **the same gain**. Dividing both by the same number
leaves their *ratio* — the contrast — untouched.

> **Flat-field is a local gain adjustment. CLAHE is a local histogram rewrite.**
> One preserves contrast ratios by construction; the other alters them by design.
> That single difference is the whole 100.9% vs 80.3% gap.

### Implementation gotcha

Fill outside the FOV mask with the interior mean **before** blurring. Leave the
black surround near 0 and the blur drags the estimated field down at the rim,
manufacturing a falloff that is not optical — then you divide by a too-small
number and blow out the periphery.

Estimate at **1/8 scale**: the field is smooth by definition, nothing is lost,
and the cost drops from 1,643 ms to 183 ms.

---

## Three consumers, three different amounts of enhancement

[F] is **not** primarily for Module 2 — Module 2 is the consumer that gets the
**least**.

| Consumer | Works at | Gets | Why |
|---|---|---|---|
| **[E] re-score** (inside Module 1) | R=436 | flat-field, **only** on `grad` | 76.5% rescue at 0.6% false rescue |
| **Module 2** lesion detectors | native res | **raw / almost nothing** | MAs are 3-5 px and *are* the signal |
| **Module 3** CNN + clinician | 512x512 | CLAHE ± BenGraham | MAs are sub-pixel there anyway |

The rule that generates all three rows:

> **Enhancement is lossy. Give each consumer only as much as it can afford to
> lose.**

Module 2 can afford to lose almost nothing — a microaneurysm at native
resolution is the entire difference between grade 0 and grade 1. Module 3 can
afford to lose a lot, because at 512x512 it cannot resolve one regardless (the
same sub-pixel argument established in [A]).

**Corollary on consistency:** for a *learned* model, what matters is that the
transform is applied identically at train and inference time — the CNN adapts to
whatever representation it is handed. For a *hand-built* detector, what matters
is information preservation, because no amount of consistency recovers detail
that was destroyed. Different requirements, different answers.

---

## Does enhancement normalise across cameras? — NO

The motivating hypothesis: resolution alone predicts referable DR at 82.3%, so if
CLAHE / Ben Graham made different devices look statistically alike, they would
attack that leak directly and be worth their MA cost in the CNN stream.

**Tested and rejected.** 136 images, 34 from each of four formats, all
radius-normalised to R=436 first so raw size is not a cue. Question: can a
classifier still tell which camera took the picture?

| Variant | format accuracy | vs plain | grade accuracy | vs plain |
|---|---|---|---|---|
| plain | **97.1%** | — | 58.1% | — |
| CLAHE | 97.8% | **+0.7** | 63.9% | +5.8 |
| flatfield | 95.6% | −1.5 | 67.7% | +9.5 |
| BenGraham | 95.6% | −1.6 | 68.3% | +10.2 |
| gray-world | 97.1% | −0.0 | 58.8% | +0.7 |
| **CLAHE+BenGraham** | 95.6% | **−1.6** | **72.8%** | **+14.7** |

Chance level 25%. Referable base rate 57.4%.

**The camera fingerprint survives everything.** Best case is 97.1% → 95.6%, a
1.6-point dent in a signal sitting 72 points above chance. CLAHE actually made it
*slightly worse*. No enhancement tested comes close to normalising acquisition.

> **Consequence:** the 82.3% acquisition confound **cannot be preprocessed away.**
> It has to be handled by stratified validation, per-camera normalisation of the
> features themselves, or explicit domain adaptation in Module 3. Do not expect
> [F] to fix it.

### The unexpected finding: enhancement surfaces disease signal

Note the right-hand column. On this deliberately grade-balanced sample (the
confound is broken by construction, which is why plain sits at 58.1% against a
57.4% base rate — the quality features carry almost no genuine grade signal),
enhancement **raises** grade predictability substantially:

```
plain              58.1%   (+0.7 over base rate -- essentially nothing)
CLAHE+BenGraham    72.8%   (+15.4 over base rate)
```

This cuts two ways, and the direction depends on the consumer:

- **For [E] / the measurement stream — this is bad.** Quality features are
  supposed to be disease-blind. A transform that makes them *more* predictive of
  grade will make [E] *more* biased against sick patients, not less. Another
  reason enhancement must not touch the copy [E] scores unless [E] is retrained
  and re-checked for disease-blindness afterwards.
- **For Module 3's CNN — this is mildly encouraging.** It suggests CLAHE and
  Ben Graham genuinely make lesions more separable, rather than merely
  redistributing contrast.

**Caveats:** 136 images is a small sample, and this measures a RandomForest over
34 hand-crafted quality features, not a CNN over pixels. It is suggestive that
the CNN stream would benefit, not proof.

---

## What is still unmeasured

| Gap | Why it matters |
|---|---|
| **Real ungradable labels** | all degradation is synthetic; real cataract/motion/lash failures may respond differently |
| **Real MA detector recall** | the injected-dot SNR is a proxy; the true test is Module 2's detector on IDRiD before/after |
| **Borderline band definition** | the 0.35–0.65 band is arbitrary and rests on an uncalibrated RandomForest |
| **Per-mode rescue rates** | the 76.5% is pooled; it is *consistent with* gradient failures being the rescuable ones, but that was not measured directly |

---

## Next

Module 2 — retinal structure segmentation. [F]'s output should feed Module 3's
CNN branch and the clinician's view; Module 2's lesion detectors should read the
**lightly-processed or original** image, per the CLAHE finding above.

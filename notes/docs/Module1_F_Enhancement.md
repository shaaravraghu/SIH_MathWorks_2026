# Module 1, Stage [F] — Adaptive Enhancement

**Purpose:** for images [E] calls **borderline** — not clean enough to pass
through untouched, not bad enough to reject — apply targeted, reversible
enhancement, then send the image back through the quality features so [E] can
re-score it.

**Code:** not yet implemented. Planned: `matlab/enhanceFundus.m`, consuming the
verdict struct from [E] and `fov.maskMeasure` from [A].

**Status:** design spec, written ahead of implementation. Unlike [A]-[C], there
is no worked example or measured benchmark here yet — those get added once
`enhanceFundus.m` exists and has run against a labelled set. Do not read the
numbers in this doc as measured; there are none yet, by design.

---

## Contents

- [What [F] does and does not do](#what-f-does-and-does-not-do)
- [Why enhancement is scoped to borderline only](#why-enhancement-is-scoped-to-borderline-only)
- [The algorithm](#the-algorithm)
  - [Step 1 — colour handling](#step-1--colour-handling)
  - [Step 2 — CLAHE](#step-2--clahe)
  - [Step 3 — illumination normalization](#step-3--illumination-normalization)
  - [Step 4 — denoising (careful)](#step-4--denoising-careful)
  - [Step 5 — re-score](#step-5--re-score)
- [The gotcha that matters more than any of the above](#the-gotcha-that-matters-more-than-any-of-the-above)
- [Decision flow](#decision-flow)
- [Open questions / not yet decided](#open-questions--not-yet-decided)
- [Next](#next)

---

## What [F] does and does not do

| Does | Does not |
|---|---|
| Improve contrast, illumination, and noise on **borderline** images | Touch images [E] already marked gradable |
| Feed a cleaned image back into the [A]-[C] feature pipeline for re-scoring | Decide gradable/borderline/ungradable itself — that's [E]'s job, twice |
| Preserve fine structure (microaneurysms) as the hard constraint | Replace lesion-detection-specific preprocessing in Module 2 |
| Produce one enhanced image for re-scoring and (optionally) for human viewing | Guarantee a borderline image becomes gradable — it can still fail the second [E] pass |

[F] exists because the alternative — rejecting everything [E] is unsure about —
throws away images that a technician spent time capturing and a patient spent
time waiting for, when a few milliseconds of contrast correction would have
made them usable.

---

## Why enhancement is scoped to borderline only

Three-way split from [E]:

| [E] verdict | [F] action |
|---|---|
| Gradable | skip [F] entirely — pass through unchanged |
| Borderline | run [F], **re-run [E]'s features**, let [E] decide again |
| Ungradable | skip [F] — reject with the specific reason from [B]/[C], don't waste time enhancing an unrecoverable image |

Running enhancement on already-gradable images is pure downside: it changes
pixel values on an image that was working fine, for no measurable gain, and
every enhancement step below has a failure mode (see the denoising gotcha).
Running it on ungradable images is pure waste: an image rejected for `areaFrac
< 0.5` (half the retina missing) or gross defocus is not fixable by contrast or
denoising — those failures are geometric or optical, not tonal.

---

## The algorithm

### Step 1 — colour handling

Enhancement operates on **lightness only**, never on R/G/B independently.

```matlab
lab = rgb2lab(I);
L   = lab(:,:,1);
```

Independently equalizing R, G, B stretches each channel by a different amount
and shifts colour — which is exactly the yellow-vs-red distinction that
separates exudates from haemorrhages. Doing contrast work in L\*a\*b\* and
leaving a/b untouched avoids this by construction. (Green-channel extraction
for lesion detection is a **separate**, Module-2-side concern — see
[DR_Pipeline_Techniques_and_Datasets.md](DR_Pipeline_Techniques_and_Datasets.md#green-channel-extraction).
[F] is about making the image gradable, not about preparing it for a specific
detector.)

### Step 2 — CLAHE

```matlab
lab(:,:,1) = adapthisteq(L, 'NumTiles',[8 8], 'ClipLimit',0.01, 'Distribution','rayleigh');
I_clahe = lab2rgb(lab);
```

Tile the image (e.g. 8x8), equalize each tile's histogram independently,
blend across tile boundaries bilinearly. Fixes the common case where the
[C]-stage illumination features flagged the image as unevenly lit — one bright
patch and one dark patch that a single global stretch can't fix.

`ClipLimit` caps how far each tile's histogram gets stretched. Skipping it
amplifies sensor noise in flat regions (sky-dark background, smooth macula)
into visible grain — which then becomes a second problem for step 4 to clean
up.

### Step 3 — illumination normalization

Pick one, in order of how much you need:

- **Flat-field correction** — `imflatfield(I, sigma)`. Estimates the smooth
  illumination field with a wide Gaussian and divides it out. Default choice —
  one call, handles the [C]-stage `bgRadial`/`bgTiltMag` failures (vignetting,
  off-axis capture) directly.
- **Background subtraction** — heavy median filter for the background
  estimate, then `I - background + mean(I)`. More controllable than flat-field
  when the illumination gradient is sharp rather than smooth.
- **Homomorphic filtering** — `log`, high-pass in the frequency domain, `exp`.
  Reach for this only if flat-field measurably fails, since it has more
  parameters to get wrong.

Run this **inside `fov.maskMeasure`**, same reason as every [B]/[C] metric: the
black surround is not part of the illumination field and will bias whatever
background estimate you compute across the full frame.

### Step 4 — denoising (careful)

`imbilatfilt` or `imnlmfilt` at **low strength only**. See the gotcha below
before touching this step.

### Step 5 — re-score

Feed the enhanced image back through [A] (to refresh `fov.maskMeasure` if
geometry moved — it shouldn't, since [F] doesn't crop or resize) and then
[B]/[C], and hand the refreshed feature vector to [E] a second time.

```
borderline --[F]--> enhanced image --[A]-[C] recompute--> [E] second pass --> gradable | still borderline | ungradable
```

An image that is still borderline after one [F] pass should not loop through
[F] again — enhancement is not iterative refinement, it's one shot. If [E]
still can't clear it, reject with the reason from the second pass.

---

## The gotcha that matters more than any of the above

A microaneurysm is 3-5 pixels wide at native resolution. Denoising filters —
non-local means, bilateral, wavelet, DnCNN — are explicitly designed to remove
small, low-contrast, isolated structures, because that's what sensor noise
looks like. **A microaneurysm looks like sensor noise to a denoiser.** Grade 1
(mild NPDR) is defined as "microaneurysms only" — so aggressive denoising here
doesn't just blur an image, it can silently delete the one finding that
separates grade 0 from grade 1.

This is why [F] must never be treated as a single "clean up the image" black
box:

- Denoise at the **lowest strength that measurably helps the [E] re-score**,
  not the strength that looks best to the eye.
- If Module 2's microaneurysm detector's recall drops after [F] runs on a set
  of images with known MA counts, the denoiser is too strong — turn it down
  before touching anything else in the pipeline.
- Prefer running Module 2's lesion detection on the **lightly-processed** (or
  original) image, and reserve [F]'s output for the whole-image CNN branch and
  for the technician's/ophthalmologist's own viewing. This mirrors the same
  split [A] already makes between the measurement mask and the display image —
  don't measure on a version of the image you've smoothed for looks.

---

## Decision flow

```
              +-- [E] gradable ----------------------> skip [F], pass through
[E] verdict --+-- [E] borderline --> [F] enhance --> [A]-[C] recompute --> [E] again --+-- gradable ------> pass through (enhanced)
              |                                                                        +-- still borderline -> reject, reason = second-pass reason
              +-- [E] ungradable --------------------> skip [F], reject with [B]/[C] reason
```

The second [E] pass is not guaranteed to succeed. An image that was borderline
because of geometry ([A] `residual`/`offset`) rather than tone will not improve
from CLAHE or flat-fielding — [F] only touches contrast, illumination, and
noise. If [E]'s decision was driven by [A]-side features, [F] is very unlikely
to change the outcome, and that's expected, not a bug.

---

## Open questions / not yet decided

These need real data before [F] can be implemented the way [A]-[C] were
(measured thresholds, a worked example, a failure-mode table with numbers):

- **What re-triggers [F]?** Exact borderline band from [E]'s classifier output
  (e.g. a probability range, not just a single "borderline" label) is not yet
  defined — depends on how [E] is built.
- **Denoising strength.** No labelled set yet to measure MA-recall-vs-strength
  on. This is the single most important number in this whole stage and it does
  not exist yet — see [Gap 1 in the datasets doc](DR_Pipeline_Techniques_and_Datasets.md#gap-1--image-quality-labels-module-1-has-no-ground-truth)
  for where borderline/enhancement labels could come from (DeepDRiD, DRIMDB,
  or a hand-labelled subset).
- **Whether to keep Ben Graham preprocessing (`4*I - 4*blur(I) + 0.5`) as a
  separate path.** It's a strong, well-known normalizer across camera models,
  but it changes the image more aggressively than CLAHE + flat-field and may
  belong in Module 2/3's CNN-input pipeline rather than here — needs a decision
  once [F] has something to A/B test against.
- **Cost.** [B] costs ~330 ms, [C] ~409 ms (see
  [Module1_Results.md](Module1_Results.md#where-bs-330-ms-actually-goes)); [F]
  adds CLAHE + a flat-field call + a denoiser + a **second** [A]-[C] pass. This
  is the most expensive stage in Module 1 and it only runs on the borderline
  slice — worth measuring what fraction of real traffic that actually is before
  optimizing it.

---

## Next

Module 2 — retinal structure segmentation. [F]'s enhanced output feeds the
whole-image CNN branch in Module 3; Module 2's lesion detectors should
generally prefer the lightly-processed or original image per the gotcha above.

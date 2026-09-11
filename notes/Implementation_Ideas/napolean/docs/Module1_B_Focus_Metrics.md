# Module 1, Stage [B] — Focus & Sharpness

**Purpose:** decide whether the image is in focus, and if not, *where* and *how badly*.

**Code:** [`matlab/focusMetrics.m`](../../../../code_testing/matlab/focusMetrics.m)

**Depends on:** [`[A]` FOV detection](Module1_A_FOV_Detection.md) — every metric
here is computed inside `fov.maskMeasure`.

All numbers below are **measured**, on
`notes/Diabetic_Retinopathy_Concept/Fovea_&_Optic_Disk.jpg` (969 x 916) — the
annotated reference image showing the optic disc, macula, fovea and vascular
arcade. Anatomy references throughout point at that image.

---

## Contents

- [The one-sentence version](#the-one-sentence-version)
- [The physics](#the-physics)
- [The metrics at a glance](#the-metrics-at-a-glance)
- [The metrics](#the-metrics)
- [Experiment 1 — monotonicity vs defocus](#experiment-1--monotonicity-vs-defocus)
- [Experiment 2 — noise sensitivity](#experiment-2--noise-sensitivity)
- [Experiment 3 — contrast invariance](#experiment-3--contrast-invariance)
- [Experiment 4 — partial blur](#experiment-4--partial-blur)
- [Experiment 5 — can pre-smoothing fix noise?](#experiment-5--can-pre-smoothing-fix-noise)
- [Experiment 6 — measuring noise directly](#experiment-6--measuring-noise-directly)
- [The verdict](#the-verdict)
- [Thresholds](#thresholds)
- [Failure modes](#failure-modes)

---

## The one-sentence version

**Sharp images contain fine detail; blur erases it; every metric here is a
different way of asking "how much fine detail survived?"**

On the reference image, the "fine detail" is concrete and nameable: the crisp
edges of the blood vessels, the sharp rim of the optic disc, the texture of the
retinal surface. Defocus smears all of it. The metrics differ only in *how* they
measure the smearing, and in *what fools them.*

The reason there are eleven features and not one: every individual metric can be
fooled by a realistic field image — a dark one, a grainy one, or one that is
sharp on one side and soft on the other. Their weaknesses are different, so
together they are not fooled. Stage [E] learns the combination.

---

## The physics

Defocus is, to a good approximation, **convolution with a disc** — the circle of
confusion, whose radius grows with focus error. Convolution with a disc is a
**low-pass filter**.

In plain terms: an out-of-focus lens spreads each point of the retina into a
small blob. Neighbouring blobs overlap and average together, and the fine
structure — a 3-px vessel edge, the speckle of retinal texture — averages away
first. Big smooth things (the overall brightness of the macula, the broad glow
of the optic disc) survive. Small sharp things do not.

So every metric below is, underneath, a measure of high-frequency energy. They
differ in three ways that matter:

1. how much they **amplify noise** (noise is high-frequency too),
2. whether they are **invariant to contrast**,
3. what they **cancel** (some structures read as zero when they shouldn't).

**Prerequisite:** run [`normalizeFundus`](../../../../code_testing/matlab/normalizeFundus.m) first.
Every metric here is scale-dependent — a "sharp" gradient at R=1400 px is a
different number from the same eye at R=436 px. Cross-image comparison is only
meaningful once the retinal radius is fixed.

---

## The metrics at a glance

Read this table first; the sections below give the mathematics.

| Metric | The simple idea | What it catches on the reference image |
|---|---|---|
| `varLap` | Run an "edges in every direction" filter, measure how much its output varies. Sharp = varies a lot. | Vessel edges and the optic disc rim light up the filter. Blur them and the number collapses. |
| `varLapNorm` | Same, but divided by the image's own contrast — so a *dim* image isn't mistaken for a *blurry* one. | The macula is naturally dark and low-contrast; this stops that from reading as defocus. |
| `sml` | Plain Laplacian can cancel itself to zero where structure crosses at a saddle. SML takes absolute values first so it can't. | Vessel *crossings* near the optic disc are exactly that saddle case. |
| `tenengrad` | Measure edge **strength** directly (first derivative) rather than curvature (second). | Same vessel edges, but measured in a way that noise inflates only linearly. |
| `tenengradVar` | The *spread* of edge strengths, not their average. Noise raises the average but barely moves the spread. | The most noise-immune number in the stage — trustworthy on grainy PHC captures. |
| `brenner` | Compare each pixel to the one 2 px away. Crude, directional, nearly free. | A cheap "is this worth analysing at all?" pre-check on the edge device. |
| `specSlope` | Sharp natural images have a known frequency falloff rate. Blur steepens it. Because it is a *slope*, brightness and contrast cannot move it. | Measured on a rectangular patch from the retinal interior — never the whole circle. |
| `noiseSigma` | A filter that cancels real image structure and leaves only sensor grain. | Tells the classifier when a "sharp" reading is actually just noise. |
| `regionMin` | Split the retina into regions, report the **worst** one instead of the average. | If the macula half went soft from camera tilt while the optic disc half stayed sharp, only this notices. |
| `regionCV` | How unevenly sharpness is distributed across those regions. | Corroborates `regionMin`; has a non-zero floor because retinal structure is genuinely uneven. |

Two of these deserve emphasis before the detail:

- **`regionMin` is the most valuable feature in the stage.** A global average is
  almost blind to one-sided blur; see [Experiment 4](#experiment-4--partial-blur).
- **`noiseSigma` is not a focus metric at all.** It is a *confounder* measurement
  — it exists so the classifier can tell "sharp" apart from "noisy," which the
  Laplacian family cannot do on its own.

---

## The metrics

### Variance of the Laplacian

**In simple terms:** the Laplacian filter responds wherever intensity changes
direction — at edges. Slide it over the image and you get a map of edge response.
A sharp image produces a map with strong peaks and deep troughs; a blurred one
produces a nearly flat map. "Variance" is just how much that map varies, which is
how much edge content exists.

The Laplacian is the isotropic second derivative:

```
        [ 0  1  0 ]
grad^2 =[ 1 -4  1 ]      var_lap = var( L(x,y) )  over the mask
        [ 0  1  0 ]
```

Why **variance** and not mean? The kernel sums to zero, so the mean response is
~0 by construction. Variance is therefore just the energy.

```matlab
L = imfilter(Ig, fspecial('laplacian',0), 'replicate');
f.varLap = var(L(M));
```

**Weakness:** the second derivative amplifies high frequencies *quadratically*,
and sensor noise is high frequency. A grainy image looks "sharp" to it.
Quantified in [Experiment 2](#experiment-2--noise-sensitivity).

### Contrast-normalised Laplacian variance

**In simple terms:** divide the edge energy by the image's own contrast. If you
halve the brightness range of a photo, every edge gets weaker by the same factor
— but the *lens* never changed. Dividing cancels that out, so an underexposed but
perfectly focused image is no longer accused of being blurry.

```
varLapNorm = var(L) / var(I)
```

Both numerator and denominator scale as `c^2` when the image is scaled by `c`, so
the ratio is **contrast-invariant**. This is what stops a *sharp but
underexposed* image being called blurry. See [Experiment 3](#experiment-3--contrast-invariance).

### Modified Laplacian / SML (Nayar & Nakagawa)

**In simple terms:** the plain Laplacian adds up the horizontal and vertical
curvature. Where those two have opposite signs — a saddle, like the point where
one vessel crosses over another — they cancel, and genuinely sharp structure
reports as zero. SML takes the absolute value of each direction *before* adding,
so nothing can cancel.

The plain Laplacian has a real defect: at a saddle point, `Ixx` and `Iyy` have
opposite signs and **cancel**, so genuinely sharp structure reads as zero.
Modified Laplacian takes absolute values *before* summing:

```
ML(x,y) = |2I(x,y) - I(x-s,y) - I(x+s,y)| + |2I(x,y) - I(x,y-s) - I(x,y+s)|
```

The step `s` selects the spatial scale you are sensitive to. Set `s` to roughly
the vessel width in your normalised images and you are measuring focus **on the
structures you care about** — the vascular arcade rather than JPEG texture.

### Tenengrad and Tenengrad variance

**In simple terms:** instead of asking how sharply the intensity *curves*
(second derivative), ask how steeply it *slopes* (first derivative). A slope is a
gentler operation, so random grain inflates it much less. `tenengrad` averages
the slope energy; `tenengradVar` measures how much the slope varies from place to
place.

```matlab
Gmag = imgradient(Ig, 'sobel');
f.tenengrad    = mean(Gmag(M).^2);   % gradient energy
f.tenengradVar = var(Gmag(M));       % gradient variance
```

First-derivative based, so noise is amplified **linearly** rather than
quadratically — much more stable.

`tenengradVar` is the more robust of the two, and it turns out to be the
**single most noise-immune metric tested**. The reason, intuitively: sprinkling
i.i.d. noise over the image lifts the gradient magnitude almost *everywhere by a
similar amount*, so the average rises — but the spread around that average barely
moves. Variance sees through the noise; the mean does not.

### Brenner gradient

**In simple terms:** the crudest possible sharpness test — compare each pixel to
the one two positions away and square the difference. If the image is sharp,
neighbours differ; if it is blurred, they have been averaged together and are
nearly equal.

```
brenner = mean( (I(x+2,y) - I(x,y))^2 )
```

Ancient (1971, microscopy autofocus), directional, but extremely fast. A good
candidate for the "is this even worth analysing" pre-check on the edge device.

### Spectral slope

**In simple terms:** decompose the image into frequencies. Real photographs have
a characteristic recipe — lots of coarse structure, progressively less fine
structure, following a power law. Blur removes the fine end, which makes the
falloff steeper. The *steepness itself* is the blur measure. Because it is a
slope rather than a magnitude, making the image brighter or dimmer does not move
it at all.

Natural images follow a power law:

```
P(f) ~ f^-alpha        with alpha ~ 2 for natural scenes
```

Blur steepens the falloff, so **alpha itself is the blur measure**. Because it
is a *slope*, it is invariant to contrast and brightness — unlike every
energy-based measure above.

> **Critical implementation detail:** you cannot FFT a circularly-masked image.
> The mask boundary is a hard step edge whose broadband spectrum swamps
> everything. Take a **rectangular crop from the retinal interior**, subtract the
> mean, and apply a **Hann window** so it tapers to zero. Then fit the slope over
> a mid-frequency band (skip DC and the lowest bins; stop before Nyquist).
>
> A patch centred between the optic disc and the macula works well — it contains
> vessels (real high-frequency content) without clipping the aperture rim.

---

## Experiment 1 — monotonicity vs defocus

Progressive Gaussian blur, aperture edge kept hard.

| sigma | varLap | varLapNorm | SML | Tenengrad | TenengradVar | Brenner | specSlope |
|---|---|---|---|---|---|---|---|
| 0 | 4.75e-03 | 6.58e-01 | 3.30e-02 | 6.01e-02 | 5.08e-02 | 2.41e-03 | 1.61 |
| 0.5 | 1.96e-03 | 2.86e-01 | 2.15e-02 | 4.77e-02 | 4.04e-02 | 1.80e-03 | 1.73 |
| 1 | 3.34e-04 | 5.37e-02 | 7.79e-03 | 2.56e-02 | 2.13e-02 | 9.05e-04 | 2.21 |
| 2 | 3.59e-05 | 6.58e-03 | 2.78e-03 | 7.77e-03 | 5.99e-03 | 2.52e-04 | 4.01 |
| 4 | 1.88e-06 | 3.92e-04 | 8.00e-04 | 1.72e-03 | 1.17e-03 | 5.03e-05 | 10.55 |
| 8 | 1.23e-07 | 2.92e-05 | 2.40e-04 | 4.24e-04 | 2.51e-04 | 1.21e-05 | 11.71 |

**All monotonic** — that is the first thing to verify, and it confirms the mask
erosion from [A] is working. (Without erosion the curve flattens after sigma=2;
see [the erosion proof](Module1_A_FOV_Detection.md#step-6--the-measurement-mask).)

Monotonic matters because a quality score that does not move consistently with
blur cannot be thresholded at all. Every feature must fall (or, for `specSlope`,
rise) every single step.

**Dynamic range** (sharp / sigma=8) — higher is more discriminative:

| Metric | Range |
|---|---|
| **varLap** | **38,731x** |
| varLapNorm | 22,547x |
| TenengradVar | 202x |
| Brenner | 198x |
| Tenengrad | 142x |
| SML | 137x |
| specSlope | +10.1 (absolute change in alpha) |

The Laplacian family wins on raw range by two orders of magnitude — because the
second derivative squares the frequency response. But read on.

---

## Experiment 2 — noise sensitivity

Sharp image, plus additive Gaussian noise. **A good focus metric should not rise
when noise is added.**

| noise sigma | varLap | varLapNorm | SML | Tenengrad | TenengradVar | Brenner |
|---|---|---|---|---|---|---|
| 0.00 | 4.75e-03 | 6.58e-01 | 3.30e-02 | 6.01e-02 | 5.08e-02 | 2.41e-03 |
| 0.01 | 6.70e-03 | 9.19e-01 | 5.63e-02 | 6.16e-02 | 4.90e-02 | 2.57e-03 |
| 0.03 | 2.24e-02 | 2.81e+00 | 1.27e-01 | 7.86e-02 | 4.63e-02 | 4.08e-03 |
| 0.06 | 7.56e-02 | 7.19e+00 | 2.40e-01 | 1.40e-01 | 5.11e-02 | 9.29e-03 |

**Inflation at noise sigma = 0.03** (1.00 = immune):

| Metric | Inflation |
|---|---|
| varLap | **4.72x** |
| varLapNorm | 4.27x |
| SML | 3.86x |
| Brenner | 1.69x |
| Tenengrad | 1.31x |
| **TenengradVar** | **0.91x** — immune |

This is the trap. A **dark, noisy, out-of-focus** image scores *higher* on
`varLap` than a clean sharp one. In a rural PHC with poor lighting and a
low-cost sensor, that is not a corner case — it is Tuesday.

`tenengradVar` is essentially immune, and slightly *decreases*, which is exactly
the right direction.

---

## Experiment 3 — contrast invariance

Sharp image, scaled to 50% contrast. **An underexposed but sharp image must not
be called blurry.**

| Metric | Full contrast | 50% contrast | Ratio |
|---|---|---|---|
| varLap | 4.75e-03 | 1.19e-03 | **0.250** = c^2 |
| Tenengrad | 6.01e-02 | 1.50e-02 | 0.250 = c^2 |
| TenengradVar | 5.08e-02 | 1.27e-02 | 0.250 = c^2 |
| Brenner | 2.41e-03 | 6.01e-04 | 0.250 = c^2 |
| SML | 3.30e-02 | 1.65e-02 | 0.500 = c |
| **varLapNorm** | 6.58e-01 | 6.58e-01 | **1.000** — invariant |
| **specSlope** | 1.61 | 1.61 | **1.000** — invariant |

A sharp image at half contrast scores **4x lower** on `varLap` — exactly as if it
had been blurred to sigma ~0.7. The optics never changed. This produces false
"out of focus" rejections on dark images, and the technician is told to refocus
a camera that was already focused.

**Only `varLapNorm` and `specSlope` are contrast-invariant.** They are worth
their place in the feature vector for this reason alone.

---

## Experiment 4 — partial blur

Right half defocused (sigma=4), left half sharp — simulating camera tilt or eye
movement. On the reference image this is the realistic failure: the optic disc
side stays sharp while the macula side goes soft, or vice versa.

| Region | All sharp | Right half blurred |
|---|---|---|
| centre | 6.59e-03 | 3.29e-03 |
| sup-temporal | 2.66e-03 | **6.42e-07** |
| sup-nasal | 6.15e-03 | 6.15e-03 |
| inf-nasal | 6.07e-03 | 6.07e-03 |
| inf-temporal | 2.64e-03 | **6.73e-07** |
| **GLOBAL** | 4.75e-03 | 3.10e-03 |
| **min across regions** | 2.64e-03 | **6.42e-07** |
| **CV across regions** | 0.370 | 0.881 |

Read the bottom three rows:

- **Global mean:** moved **1.5x**. Indistinguishable from normal image-to-image
  variation. Half the retina is unreadable and the global metric shrugs.
- **min across regions:** moved **4,100x**.
- **CV across regions:** 0.370 -> 0.881, a 2.4x rise.

**`regionMin` is ~2,700x more sensitive to partial blur than the global mean.**
It is the single most valuable feature in stage [B], and it costs one extra line.

Why it matters clinically, not just numerically: the temporal regions contain the
**macula and fovea**. An image whose fovea is defocused is ungradable for macular
oedema no matter how crisp the optic disc looks — and the global mean would have
passed it.

Note the CV baseline of **0.370 even on a perfectly sharp image** — the retina
genuinely has uneven structure density (the macula is smooth and avascular, the
arcades around the optic disc are busy). So CV has a non-zero floor and needs
calibrating; `regionMin` is cleaner to threshold.

---

## Experiment 5 — can pre-smoothing fix noise?

The textbook advice is to pre-smooth before the Laplacian. It works, but it is a
**strict trade**:

| Pre-smooth sigma | Noise inflation | Dynamic range |
|---|---|---|
| 0.0 | 4.26x | 100x |
| 0.5 | 3.13x | 48x |
| 0.8 | 1.52x | 18x |
| 1.2 | 1.14x | 9x |

Roughly 1:1 — every factor of noise immunity costs a factor of discrimination.
You cannot have both. (Which stands to reason: pre-smoothing *is* blurring, and
you are trying to measure blur.)

**So do not pre-smooth.** Measure the noise separately instead.

---

## Experiment 6 — measuring noise directly

**In simple terms:** rather than fighting noise, measure it and hand the number
to the classifier as a separate feature. This kernel is built so that any flat,
linear, or gently curved patch of real image cancels to zero — whatever survives
is grain.

Immerkaer's estimator convolves with

```
[  1 -2  1 ]
[ -2  4 -2 ]      sigma_n = sqrt(pi/2) * mean(|I * K|) / 6
[  1 -2  1 ]
```

This kernel is designed to null constant, linear and quadratic image content,
leaving only noise.

| True added noise | Estimated sigma |
|---|---|
| 0.000 | 0.0053 |
| 0.010 | 0.0125 |
| 0.030 | 0.0312 |
| 0.060 | 0.0603 |

Near-linear and accurate. (The 0.0053 floor is the JPEG noise already present in
the source image.)

**This is the right answer to the noise problem.** Rather than crippling a metric
to make it robust, hand the classifier `varLapNorm` *and* `noiseSigma` and let it
learn the correction: *high varLap **and** high noiseSigma = noisy, not sharp.*

---

## The verdict

| Metric | Range | Noise | Contrast-inv. | Keep? |
|---|---|---|---|---|
| varLap | 38,731x | 4.72x | no | yes — best range |
| **varLapNorm** | 22,547x | 4.27x | **yes** | **yes — primary** |
| SML | 137x | 3.86x | no (c^1) | optional |
| Tenengrad | 142x | 1.31x | no | optional |
| **TenengradVar** | 202x | **0.91x** | no | **yes — noise-proof** |
| Brenner | 198x | 1.69x | no | yes — cheap pre-check |
| **specSlope** | +10.1 | mild | **yes** | **yes — independent** |
| **noiseSigma** | — | — | — | **yes — confounder** |
| **regionMin** | 4,100x* | — | — | **yes — partial blur** |
| regionCV | 2.4x* | — | — | yes |

\* for partial blur specifically

**No single metric wins.** `varLapNorm` and `tenengradVar` have *complementary*
weaknesses — one is contrast-invariant but noise-fooled, the other noise-proof
but contrast-dependent. `specSlope` fails differently again.

Stated as a table of who-rescues-whom:

| Failure a real image throws at you | Fooled | Rescued by |
|---|---|---|
| Dark but perfectly focused | `varLap`, `tenengrad`, `brenner` | `varLapNorm`, `specSlope` |
| Grainy low-cost sensor | `varLap`, `varLapNorm`, `SML` | `tenengradVar`, `noiseSigma` |
| Sharp on one side only | every global metric | `regionMin`, `regionCV` |

That complementarity is precisely why you feed the classifier all of them plus
the confounders (`noiseSigma` from here, exposure and contrast from [C]). Any one
of them alone is fooled by a realistic field image; together they are not.

**~11 features out of stage [B]:**

```
varLap  varLapNorm  sml  tenengrad  tenengradVar  brenner
specSlope  noiseSigma  regionMin  regionCV  regionVals(5)
```

---

## Thresholds

**Do not hand-pick these.** Two reasons:

1. The absolute values depend on `targetR` from `normalizeFundus`, on the camera,
   and on JPEG quality.
2. The whole point of stage [E] is to learn the boundary jointly across ~25
   features. A single-feature threshold throws that away.

**What to do instead — the synthetic sweep.** You already have everything needed:

```matlab
for s = [0 0.5 1 2 4 8]
    Ib = imgaussfilt(I, s);
    f(end+1) = focusMetrics(Ib, fov);
end
```

Plot each feature against sigma. The curve **must be monotonic** — if it is not,
something is broken (usually the mask erosion). Then find the sigma at which
human graders start calling images ungradable, and read the feature value there.

That gives you a *calibrated, defensible* statement — **"our system rejects
images below sigma_blur = 3.2"** — instead of an arbitrary number. It is also a
presentable result in its own right.

### Do NOT gate on `specSlope` — corrected

An earlier draft of this document recommended `specSlope` as the safest single
fast-reject feature, on the grounds that it is contrast-invariant and
dimensionless. **Measured data on APTOS overturned that.**

From [`Module1_CSV_Schema.md`](Module1_CSV_Schema.md): `specSlope` has Spearman
**rho = 0.460 against `diagnosis`** — by far the highest of any [B] feature. It
is not measuring optics; it is substantially measuring *disease*. A diseased
retina has different frequency content because it is covered in lesions.

Gate on it and you build a system that preferentially refuses to screen the
patients who most need referral. Keep it as a classifier **input**; never as a
gate.

For reference, the disease correlations actually measured:

| Feature | rho vs `diagnosis` | Verdict |
|---|---|---|
| `tenengrad` | **0.000** | perfectly disease-blind |
| `brenner` | -0.038 | safe |
| `tenengradVar` | 0.067 | safe |
| `varLapNorm` | 0.126 | safe — **the one to gate on if you must** |
| `noiseSigma` | 0.354 | input only |
| `specSlope` | **0.460** | **input only — never gate** |

**If you need a hard gate,** use `varLapNorm` or `regionMin`, and re-measure rho
on your own data first. The threshold still comes from the synthetic sweep above,
not from a hand-picked number.

---

## Failure modes

| Cause | Symptom | Guard |
|---|---|---|
| Mask not eroded | metric flat across blur levels | use `fov.maskMeasure`, never `fov.mask` |
| Image not radius-normalised | values incomparable between images | run `normalizeFundus` first |
| Noisy dark image | `varLap` says "sharp" | include `noiseSigma`; cross-check `tenengradVar` |
| Underexposed but sharp | `varLap`/`tenengrad` say "blurry" | include `varLapNorm` and `specSlope` |
| Camera tilt / one-sided defocus | global metrics normal | `regionMin`, `regionCV` |
| FFT on the masked circle | `specSlope` meaningless | interior rectangular crop + Hann window |
| Burned-in text or annotations | inflates every metric | crop them out, or mask them |
| Big bright lesions | slightly inflate gradient measures | acceptable — but see the disease-blindness check below |

### The disease-blindness check

Repeating it from [the module overview](DR_Pipeline_Techniques_and_Datasets.md)
because stage [B] is where it usually breaks: exudates have sharp edges and
haemorrhages have soft ones, so a diseased retina genuinely has *different*
gradient statistics from a healthy one.

If your quality model learns that, it will reject sick patients — the exact
population the system exists to find.

```matlab
for g = 0:4
    rate(g+1) = mean(verdict(grade == g) == "ungradable");
end
bar(0:4, rate)      % MUST be flat
```

Run this the moment you have a quality classifier. A rising bar chart means the
model learned disease instead of optics.

---

## Next

Stage [C] — illumination and exposure: background field estimation via
downsample-median-upsample, per-channel saturation (why `sat_R` high is normal
and `sat_G` high is fatal), local contrast via `stdfilt`, and the cataract/haze
signature.

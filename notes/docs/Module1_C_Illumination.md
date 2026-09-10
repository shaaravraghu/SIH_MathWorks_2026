# Module 1, Stage [C] — Illumination, Exposure & Contrast

**Purpose:** decide whether there was enough light, delivered evenly, to record
the retina — and whether what was lost is recoverable.

**Code:** [`matlab/illuminationMetrics.m`](../matlab/illuminationMetrics.m),
[`python/extract_module1_features.py`](../../python/extract_module1_features.py)

**Depends on:** [`[A]` FOV detection](Module1_A_FOV_Detection.md) — every metric
here is computed inside `fov.maskMeasure`.

All numbers below are **measured**, on
`notes/Diabetic_Retinopathy_Concept/Fovea_&_Optic_Disk.jpg` (969 x 916).

---

## Contents

- [The one-sentence version](#the-one-sentence-version)
- [Why enhancement does not remove the need for this](#why-enhancement-does-not-remove-the-need-for-this)
- [The physics](#the-physics)
- [The algorithms at a glance](#the-algorithms-at-a-glance)
- [Algorithm 1 — background field estimation](#algorithm-1--background-field-estimation)
- [Algorithm 2 — plane and radial fits](#algorithm-2--plane-and-radial-fits)
- [Algorithm 3 — saturation counting](#algorithm-3--saturation-counting)
- [Algorithm 4 — local contrast](#algorithm-4--local-contrast)
- [Algorithm 5 — colour and the haze signature](#algorithm-5--colour-and-the-haze-signature)
- [Worked example — full trace](#worked-example--full-trace)
- [The features](#the-features)
- [Thresholds](#thresholds)
- [Failure modes](#failure-modes)

---

## The one-sentence version

**[B] asks whether the optics resolved the detail; [C] asks whether there was
enough light, evenly delivered, to record it — and whether the loss is
reversible.**

These fail independently. An image can be perfectly focused and still ungradable
because it is black, blown out, or veiled by haze.

There is one specific blind spot that makes [C] mandatory rather than optional:
**`varLapNorm` is contrast-invariant by design.** That was its selling point in
[B] — it stops a dark-but-sharp image being called blurry. But contrast-
invariance means it *structurally cannot see* a contrast problem. A cataract-hazed
image has its dynamic range crushed, and the metric built to ignore contrast
changes will shrug. Something has to catch that, and it is not [B].

---

## Why enhancement does not remove the need for this

The obvious objection: `imflatfield` divides out the illumination field in one
line, CLAHE fixes local contrast, Ben Graham preprocessing removes colour cast
and slow illumination variation simultaneously. Why measure at all?

**Because enhancement redistributes information. It cannot create it.**

### Three things enhancement genuinely cannot fix

**1. Clipping — the irreversible one.**

Three adjacent pixels on an exudate with true values `0.95, 1.30, 1.10`. The
sensor ceiling is 1.0, so it records `0.95, 1.00, 1.00`. Now flat-field divides
that region by 1.25:

```
0.76,  0.80,  0.80
              ^^^^  still identical
```

Two genuinely different pixels are now permanently the same. The texture is gone,
because it was never written to the file. `sat_G` measures damage that is
*definitionally* beyond enhancement.

**2. Signal-to-noise ratio.** A dark region is dim *and* noisy. Brighten it 4x
and you brighten the noise 4x. It now looks correctly exposed and contains
exactly as little information as before.

**3. Scattered light.** Cataract haze is *additive* light carrying no image
information — photons that bounced off the lens opacity, not the retina. The
scatter already mixed signal between neighbouring locations at capture time.
Subtracting a background makes contrast *look* restored while amplifying a signal
that was compressed before it reached the sensor.

### [C] is enhancement's controller, not its competitor

- **[C] computes enhancement's input.** `imflatfield` needs an illumination field.
  [Algorithm 1](#algorithm-1--background-field-estimation) *is* that field.
  `bgMean` and `bgCV` are byproducts of a computation you were already doing.
- **[C] decides whether to enhance at all.** The three-way verdict — pass /
  enhance-and-rescore / reject — has no middle branch without a measurement to
  route on, and no "rescore" step without the metrics.
- **Enhancement is itself destructive.** A microaneurysm is 3-5 px. CLAHE
  amplifies flat-region noise into grain; Ben Graham subtracts a heavy local blur.
  Run it unconditionally and you damage the good images to rescue the bad ones.

### And the clinical case

Enhancement makes a hazed image *look* better while the eye remains
un-photographable — producing a confident wrong grade, the exact failure the
refusal path exists to prevent. Two messages, and only [C] separates them:

> *"Too dark — increase flash and retake."* → capture fault, fixable.
> *"Media opacity suspected — may be ungradable regardless of technique."* →
> patient finding, retaking will not help.

---

## The physics

Fundus imaging is **retro-illumination**: flash goes in through the pupil,
reflects off the retina, comes back out through the same pupil. Four consequences:

1. **Vignetting is built in.** The illumination cone is centred, so the periphery
   receives less light *and* returns less. Even a perfect capture is brighter in
   the middle. Measured on the reference image: **-8.5% centre to rim.**
2. **Misalignment makes a crescent.** Off-axis camera → the iris clips part of the
   beam → bright arc on one side, dark on the other.
3. **The cornea can reflect the flash straight back** → lens flare, blown arcs.
4. **Media opacity scatters.** Cataract, vitreous haze → a veiling glare that adds
   brightness everywhere and compresses contrast.

The key exploitable fact: **illumination is low-frequency, anatomy is
high-frequency.** Lighting varies smoothly across the whole retina; vessels and
lesions vary over a few pixels. That separation is what makes the stage possible,
and it is the same insight underlying homomorphic filtering and Ben Graham
preprocessing.

---

## The algorithms at a glance

[C] is **algorithmically simpler than [B]**, and that is not a gap in the design.

[B] needs eight metrics because sharpness is *not directly measurable* — you can
only probe it indirectly, every probe is fooled by something different, and you
triangulate. [C]'s quantities *are* directly measurable. "How bright is it?" —
take the mean. "How many pixels are clipped?" — count them. There is no ambiguity
to triangulate around.

Two genuine filtering operations, plus a least-squares fit, a count, and a colour
conversion.

| # | Algorithm | MATLAB | Produces |
|---|---|---|---|
| 1 | Multi-scale median filter | `imresize` + `medfilt2` | `bgMean`, `bgCV`, `bgSpread` |
| 2 | LS plane + radial fit | `\` | `bgTiltMag`, `bgTiltDir`, `bgRadial` |
| 3 | Threshold counting | `>` + `mean` | `sat_R/G/B`, `dark_frac` |
| 4 | Local std filter | `stdfilt` | `localContrast`, `localContrastP10` |
| 5 | Colour ratios | `rgb2hsv` | `colorSat`, `ratio_RG`, `ratio_BG` |

---

## Algorithm 1 — background field estimation

**Simple idea:** blur away all the anatomy so hard that only the smooth lighting
gradient survives. What is left *is* the illumination field.

```matlab
F     = 16;                                   % downsample factor
small = imresize(Ig, 1/F, 'bilinear');
small(~msmall) = median(small(msmall));       % hold outside at interior median
med   = medfilt2(small, [11 11]);             % 11 px here = 176 px full-scale
L     = imresize(med, size(Ig), 'bicubic');
```

### Why downsample first

A median filter with a 176-px window makes every pixel sort ~24,000 neighbours —
enormously slow. But the illumination field is smooth *by definition*, so
downsampling 16x loses none of it. Same answer, ~250x cheaper.

### Why median and not Gaussian — measured

The optic disc is a large bright blob. A Gaussian estimate averages its brightness
into the "illumination." Measured over a box on the optic disc of the reference
image:

```
median-field   0.3814
gaussian-field 0.3979      <- a 4.3% bump sitting on the optic disc
```

Flat-field with the Gaussian estimate and you dim the optic disc by 4.3% relative
to its surroundings — distorting a real anatomical structure whose brightness and
margin matter for cup-to-disc ratio and NVD assessment. The median rejects it
because the disc occupies less than half the window.

**Window sizing rule:** the optic disc is ~1/7 of image width. The median window
must be **comfortably larger** than that, or the disc survives into the field.

### Why the outside must be held, not zeroed

The black surround is at ~0. Let it into the filter and it drags the field down
near the rim, manufacturing a falloff that is not optical. Replacing it with the
interior median before filtering keeps the estimate honest at the edge.

---

## Algorithm 2 — plane and radial fits

Two different faults hide in the same field, and they need separating.

**Symmetric falloff** is normal optics — vignetting from the illumination cone.
**Asymmetric tilt** is a fault — the camera was off-axis.

```matlab
X = (xx - fov.centre(1)) / fov.radius;        % scale-free coordinates
Y = (yy - fov.centre(2)) / fov.radius;
sol = [X, Y, ones(numel(X),1)] \ L(M);
c.bgTiltMag = hypot(sol(1), sol(2));          % intensity change per radius
c.bgTiltDir = atan2d(sol(2), sol(1));
```

Same one-backslash operation as the Kasa circle fit in [A]. Dividing by `radius`
makes the tilt scale-free, so it means the same thing at R=400 and R=1800.

`bgTiltDir` produces an **actionable retake message** — "illumination falling off
to the left, shift the camera right" — the same class of unambiguous geometric
feedback as [A]'s `offset`.

### It cross-checks [A], and on the reference image they disagree

[A] reports `offset = 0.0066` — essentially perfectly centred. [C] reports a
**19.8% brightness change per retinal radius.** Two readings:

1. **Real off-axis illumination** — the beam entered slightly off-centre without
   the iris clipping the aperture. Detectable only by [C].
2. **Optic disc contamination** — the tilt points directly at the optic disc,
   which is a large, genuinely bright structure sitting off-centre.

Here (2) is the likelier explanation, and it is a **known bias worth writing
down**: `bgTiltDir` is systematically pulled toward the optic disc. Because the
disc is always nasal and always off-centre, the bias is *consistent* rather than
random, so a classifier can learn around it — but never read a single image's tilt
as proof of misalignment without cross-checking [A]'s `offset`.

---

## Algorithm 3 — saturation counting

**Simple idea:** count pixels pinned at the ends of the scale. One line.

```matlab
c.sat_R     = mean(R(M) >= 250/255);
c.dark_frac = mean(G(M) <=   5/255);
```

Count within an epsilon, not exactly 255/0 — JPEG shifts values slightly. These
thresholds match [`Module1_CSV_Schema.md`](Module1_CSV_Schema.md); keep them
aligned or the CSV columns stop meaning the same thing.

### The `sat_R` / `sat_G` asymmetry, demonstrated

Measured on the reference image:

```
        satHi(>0.99)   satLo(<0.01)
  R        0.01174        0.00042
  G        0.00000        0.01510
  B        0.00000        0.02044

  R  p99 = 0.9922   max = 1.0000   <- pushed hard against the ceiling
  G  p99 = 0.6510   max = 1.0000   <- 35% of headroom unused
  B  p99 = 0.2510   max = 0.6902
```

**1.17% of the retina is clipped in red. Zero percent is clipped in green.**

This is the entire case for per-channel measurement. A single grayscale
"saturation" would have read ~1% and might have triggered a warning. Split by
channel it is obviously harmless — the destroyed information is in the channel
nobody reads lesions from.

`sat_R` **high is normal.** The fundus is red-dominant (measured channel means
inside the mask: R=0.577, G=0.324, B=0.124), so red sits closest to the ceiling
and clips routinely. Red is used only for FOV detection, which needs nothing more
than "bright vs black," and tolerates clipping completely. On APTOS, `sat_R` up to
**0.70** has been observed on images that are perfectly gradable.

`sat_G` **high is fatal.** Green carries the lesion contrast — haemoglobin absorbs
green strongly, so vessels and haemorrhages are dark and exudates bright. Clipping
green destroys exactly the signal Module 2 needs: a hard exudate, a lens flare and
a cotton-wool spot all become `1.0`. Low-end green clipping is equally bad — it
crushes dark haemorrhages into the floor.

### Where the clipping is

| region | `satHi_R` |
|---|---|
| upper-left | **0.02812** |
| lower-left | **0.01882** |
| upper-right | 0.00000 |
| lower-right | 0.00000 |

All of it is on the **left half — where the optic disc is.** The optic disc is the
brightest structure in a healthy fundus, so it blows out first, and in red only.

---

## Algorithm 4 — local contrast

**Simple idea:** slide a window over the image and take the standard deviation of
the pixels inside it. That is local contrast.

```matlab
S = stdfilt(Ig, true(15));
c.localContrast    = mean(S(M));
c.localContrastP10 = prctile(S(M), 10);
```

**How this differs from [B]:** [B] measures how *sharply* edges transition; this
measures how *large* the intensity differences are. A hazed image can be perfectly
in focus but have every edge flattened — sharpness normal, contrast dead. And
`varLapNorm`, being contrast-invariant, cannot see it.

### It is dominated by anatomy, not quality — calibrate accordingly

Measured on the reference image:

```
localContrast     : 0.02924
localContrastP10  : 0.00744        P90 : 0.08654     <- 12x spread
globalStd(G)      : 0.08482
```

| region | `localContrast` |
|---|---|
| upper-left | 0.03538 |
| lower-left | 0.03437 |
| upper-right | 0.02429 |
| lower-right | 0.02291 |

The left half reads ~50% higher than the right — because the left has the optic
disc and dense vascular arcades while the right has the smooth avascular macula.
**Both halves are perfectly exposed.**

This is the same non-zero-floor problem as `regionCV = 0.370` in [B]:
`localContrastP10` has an *anatomical* floor and must be calibrated against real
distributions before it can be thresholded.

---

## Algorithm 5 — colour and the haze signature

```matlab
hsv = rgb2hsv(I);
c.colorSat = mean(sat(M));          % HSV S channel
c.ratio_RG = mean(R(M)) / mean(G(M));
```

Haze is not a single metric — it is a **pattern**:

```
                  high contrast          low contrast
   bright   |      GOOD            |   HAZE / CATARACT
   dark     |    (rare)            |    UNDEREXPOSED
```

Underexposure and haze both produce low contrast, so contrast alone cannot
separate them. **Brightness does:** haze is bright with low contrast;
underexposure is dark with low contrast. Scattered light *adds* brightness while
compressing the range.

Colour corroborates — haze washes the image toward grey-yellow, dropping
`colorSat`. Measured on the reference image:

```
colorSat : 0.7868      R/G : 1.781      B/G : 0.382
```

Vivid and strongly red-dominant — a healthy fundus with no haze signature. (APTOS
typical `ratio_RG` is ~1.87.) A cataract image would show `colorSat` substantially
lower with `bgMean` normal or high.

---

## Worked example — full trace

`notes/Diabetic_Retinopathy_Concept/Fovea_&_Optic_Disk.jpg`, 969 x 916.
Stage [A] first, reproduced to confirm the mask:

```
1. threshold      : 593708 px  (0.6689 of frame)   Otsu t = 0.2988
2. components     : 31  -> largest = 571686 px
3. fill holes     : 571686 -> 600439 px  (+28753)
4. open(disk 5)   : 600439 -> 600088 px  (-351)
5. boundary pts   : 2534   on image border: 0 (0.00%)
6. Kasa fit       : centre=(482.9, 455.7)  R=436.2   (dropped 66 outliers)
   maskMeasure    : erode 9 px -> 575605 px (95.9% of mask)

--- STAGE [C] ---

1. BACKGROUND FIELD (median, ~176 px window)
   bgMean            : 0.3212
   bgCV              : 0.1280
   bgP95 - bgP5      : 0.1294        (p5=0.2667  p95=0.3961)
   median vs gauss   : 0.3814 vs 0.3979 at the optic disc  (+4.3% bump)

2. PLANE / RADIAL FIT
   bgTiltMag         : 0.0636 per radius = 19.8% of mean brightness
   bgTiltDir         : 158.7 deg   -> brightest toward lower-left
   bgRadial          : -8.5% centre->rim   (normal vignetting)

3. SATURATION
           satHi(>0.99)   satLo(<0.01)
     R        0.01174        0.00042
     G        0.00000        0.01510
     B        0.00000        0.02044

4. LOCAL CONTRAST
   localContrast     : 0.02924
   localContrastP10  : 0.00744       P90 : 0.08654

5. COLOUR
   colorSat          : 0.7868   R/G : 1.781   B/G : 0.382

--- REGIONAL ---
region            bgMean   localCon   satHi_R   darkFrac
upper-left        0.3386    0.03538   0.02812    0.02299
upper-right       0.2794    0.02429   0.00000    0.02833
lower-left        0.3630    0.03437   0.01882    0.01888
lower-right       0.3039    0.02291   0.00000    0.02275
centre(r<0.3)     0.3262    0.03318   0.00000    0.03518

VERDICT: well exposed, no irreversible damage, no haze -> continue to [D]
```

### Caveat — this image is an annotated diagram, not a clean capture

**13,376 pixels (2.32% of the retina) are near-black** — the burned-in "Blood
Vessel" / "Optic Disc" / "Fovea" labels, the arrows, and the drawn circles. They
contaminate two features:

- **`dark_frac`** — a chunk of the apparent dark-end clipping is text, not crushed
  shadows.
- **`localContrast`** — pure black text on bright orange retina is the
  maximum-contrast structure in the image. The centre region has the highest
  `darkFrac` (3.5%) because that is where most labels sit.

The [B] doc flags this in its failure-mode table, and it applies at least as
strongly here. This image is excellent for demonstrating [A] and [B]; its
`localContrast` and `dark_frac` numbers are **not** representative of a clinical
capture. Calibrate on APTOS, not on this.

---

## The features

| Feature | Simple idea | Catches | In CSV? |
|---|---|---|---|
| `bgMean` | mean of the smooth lighting field | under / over-exposure | **new** |
| `bgCV` | how much that field varies | uneven illumination | **new** |
| `bgSpread` | `p95 - p5` of the field | robust alternative to CV | **new** |
| `bgTiltMag` | magnitude of the fitted lighting plane | off-axis illumination | **new** |
| `bgTiltDir` | direction of that plane | the retake direction | **new** |
| `bgRadial` | symmetric centre-to-rim falloff | vignetting severity | **new** |
| `sat_R/G/B` | fraction pinned at max | blown highlights — fatal in G, normal in R | yes |
| `dark_frac` | fraction of green at min | crushed shadows, lost haemorrhages | yes |
| `localContrast` | mean `stdfilt` response | overall contrast health | **new** |
| `localContrastP10` | worst-region contrast | localised haze or a shadowed sector | **new** |
| `colorSat` | mean colour saturation | the wash-out signature of cataract | **new** |
| `ratio_RG`, `ratio_BG` | colour cast | white balance, media yellowing | yes |
| `mean_R/G/B`, `std_R/G/B` | per-channel statistics | baseline exposure | yes |

Six columns already exist in `aptos_train_module1_features.csv`; nine are new.
Adding them requires a schema bump in
[`Module1_CSV_Schema.md`](Module1_CSV_Schema.md) and a re-run — the extractor is
resumable but **will not backfill new columns onto existing rows.**

---

## Thresholds

**Do not hand-pick these**, for the same two reasons as [B]: absolute values
depend on the camera and JPEG quality, and stage [E] learns the boundary jointly.

### The one hard gate worth having

`sat_G` is the only [C] feature that measures *irreversible* damage, which makes
it the only one with a principled claim to being a hard reject:

```
sat_G > 0.05   ->   the signal channel is clipped; no enhancement recovers it
```

Calibrate the number on your own data. Everything else goes to the classifier.

### Check disease correlation before gating on ANY of these

This is not optional advice — it is a live, unresolved problem in this project.
Measured on the current 905-row extraction:

```
gate_reject rate by grade
  grade 0:  4.8%       grade 3: 10.2%
  grade 1:  6.2%       grade 4: 18.4%    <- 3.8x grade 0
  grade 2: 13.3%
```

**That bar chart must be flat and is not.** The existing [A] gate already
preferentially rejects sick patients. Every [C] feature must be checked before it
is allowed anywhere near a gate:

```python
df.corr(numeric_only=True, method="spearman")["diagnosis"].abs().sort_values()
```

Any feature with `|rho| > 0.3` is measuring disease, not optics. In [B] this
disqualified `specSlope` (rho 0.460) and `noiseSigma` (rho 0.354) from gating.

The [C] features most likely to fail this test, and why:

- **`localContrast`** — extensive haemorrhage lowers it, large exudate clusters
  raise it. Prime suspect.
- **`colorSat`** — pale ischaemic retina and dense exudation both shift colour.
- **`dark_frac`** — large haemorrhages *are* dark pixels.

`bgMean`, `bgCV` and `bgTilt*` should be near-disease-blind, since they describe
the illumination field rather than retinal content. That makes them the safest
candidates for gating — verify rather than assume.

---

## Failure modes

| Parameter | Failure | Symptom | Guard |
|---|---|---|---|
| median window | smaller than the optic disc | disc survives into the field; flat-fielding dims it | window > 1/7 image width; compare against a Gaussian estimate |
| outside-mask fill | black surround left at 0 | manufactured falloff near the rim | hold at interior median before filtering |
| plane fit | optic disc pulls the tilt | `bgTiltMag` high on a well-aligned image | cross-check [A]'s `offset`; treat as a systematic bias |
| `sat_*` threshold | counting exactly 255 | JPEG shifts values; undercounts | use `>= 250/255`, matching the CSV schema |
| grayscale saturation | channels merged | `sat_R` 0.70 looks catastrophic when it is normal | always per-channel |
| `stdfilt` window | too large | blends macula and arcade statistics | 15 px at R=436; scale with radius |
| burned-in text | inflates `localContrast`, `dark_frac` | annotated or branded images score oddly | crop or mask annotations |
| erosion | too aggressive | hides genuine peripheral falloff | the 2% from [A] removes the aperture transition, not physiological vignetting |
| no mask | black surround included | `bgMean` and `bgCV` meaningless | always `fov.maskMeasure` |

### The disease-blindness check

Same as [B], repeated because [C] is at least as vulnerable — a diseased retina
genuinely has different colour and contrast statistics than a healthy one.

```matlab
for g = 0:4
    rate(g+1) = mean(verdict(grade == g) == "ungradable");
end
bar(0:4, rate)      % MUST be flat
```

**It is currently not flat.** See the numbers above.

---

## Next

Stage [D] — artifacts and no-reference IQA: `brisque` / `niqe` / `piqe`, dust and
flare detection, and `fitbrisque` retrained on fundus images. Then [E], which
weighs all ~35 features jointly and produces the three-way verdict.

# Module 1, Stage [A] — Field-of-View Detection

**Purpose:** find the circular retinal region in a fundus image, and produce the
mask that every downstream measurement depends on.

**Code:** [`matlab/detectFOV.m`](../matlab/detectFOV.m),
[`matlab/normalizeFundus.m`](../matlab/normalizeFundus.m)

**Worked example throughout:** `notes/Diabetic_Retinopathy_Concept/Fovea_&_Optic_Disk.jpg`
(969 x 916 px)

---

## Contents

- [What [A] does and does not do](#what-a-does-and-does-not-do)
- [What a mask is](#what-a-mask-is)
- [The algorithm](#the-algorithm)
  - [Step 1 — channel selection](#step-1--channel-selection)
  - [Step 2 — Otsu threshold](#step-2--otsu-threshold)
  - [Step 3 — cleanup (order matters)](#step-3--cleanup-order-matters)
  - [Step 4 — boundary extraction](#step-4--boundary-extraction)
  - [Step 5 — Kasa circle fit](#step-5--kasa-circle-fit)
  - [Step 6 — the measurement mask](#step-6--the-measurement-mask)
- [The five output features](#the-five-output-features)
- [Thresholds](#thresholds)
- [Worked example — full trace](#worked-example--full-trace)
- [Failure modes](#failure-modes)
- [Exit logic — reject or continue?](#exit-logic--reject-or-continue)
- [Radius normalization](#radius-normalization)

---

## What [A] does and does not do

| Does | Does not |
|---|---|
| Find the outer circle of the retina | Find the optic disc |
| Produce a pixel mask | Find the fovea |
| Report 5 geometry numbers | Find vessels or lesions |
| Detect gross framing failures | Judge focus or illumination |

[A] is **blind to anatomy by design.** It has to work on the images where
everything else fails — badly defocused, underexposed, hazed. It can, because
the FOV boundary is not an optical feature of the retina; it is an **aperture**.
Outside it, no light path exists at all. Defocus does not remove it,
underexposure does not remove it, cataract does not remove it.

That is why [A] is the one stage that essentially never fails, and therefore the
right thing to build the pipeline on.

---

## What a mask is

A **stencil**: a logical array, the same height and width as the image, holding
`true` where a pixel counts and `false` where it does not.

```
image Ig            mask                Ig(mask)
+---------+        +---------+
| 3  9  2 |        | F  T  F |
| 7  1  8 |   +    | T  T  T |    ->    [7 4 9 1 8]
| 4  6  5 |        | T  F  F |
+---------+        +---------+
```

`Ig(mask)` is MATLAB **logical indexing** — it returns a plain list of the
selected values in column-major order. Everything `false` is simply absent.

```matlab
mean(Ig(:))     % 5.0  -- averages all 9 pixels
mean(Ig(mask))  % 5.8  -- averages only the 5 selected
```

### Why it is not optional

Measured on the example image, both ways:

| | whole frame | inside mask |
|---|---|---|
| pixels | 887,604 | **600,439** (67.6%) |
| `mean(G)` | 0.2273 | **0.3238** |
| `std(G)` | 0.1732 | **0.0833** |

The black surround is 32% of the frame at ~zero intensity. It pulls the mean
down by a third and **doubles the standard deviation**, because the largest
intensity jump in the picture is retina-to-black — which is not retina at all.

Every metric in [B], [C], [D] is wrong without the mask.

```matlab
brightness = mean(Ig(fov.maskMeasure));   % correct
brightness = mean(Ig(:));                 % measuring the black border too
```

---

## The algorithm

### Step 1 — channel selection

**Use the red channel.**

Haemoglobin absorbs strongly below ~600 nm and barely at all above it. So the
retina returns red light almost uniformly, and appears as a **flat bright disc
on black** — the ideal input for thresholding. The green channel carries the
lesion contrast, which is exactly why it is the wrong choice here: vessels and
the fovea would fall below threshold and punch holes in the mask.

Measured on the example:

```
channel means : R=0.396  G=0.227  B=0.093
channel std   : R=0.284  G=0.173  B=0.093
```

Red has the **highest whole-frame variance** precisely because it has the
largest retina-vs-background gap. That is the silhouette argument, quantified.

```matlab
I  = im2double(I);       % ALWAYS. uint8 arithmetic saturates silently.
Ir = I(:,:,1);
```

**Fallback:** if `std(Ir) < 0.01` (red-free capture, or an already-processed
image), use `max(I,[],3)` instead.

---

### Step 2 — Otsu threshold

Otsu searches every candidate threshold *t* and picks the one that maximises
**between-class variance**:

```
sigma_b^2(t) = w0(t) * w1(t) * [ mu0(t) - mu1(t) ]^2
```

| Symbol | Meaning |
|---|---|
| `w0(t)`, `w1(t)` | fraction of pixels below / above *t* |
| `mu0(t)`, `mu1(t)` | mean intensity of those two groups |

Maximising the separation *between* the two groups is equivalent to minimising
the variance *within* them. One pass over a 256-bin histogram — O(256), free.

```matlab
bw = Ir > graythresh(Ir);
```

#### The sanity check that must accompany it

Otsu assumes a **bimodal** histogram. That assumption breaks when the retina
fills nearly the whole frame (common in tightly cropped APTOS images) — there is
barely a background mode, and Otsu picks a threshold *inside* the retina,
cutting the disc in half.

```matlab
areaFrac = nnz(bw)/numel(bw);
if areaFrac < 0.15 || areaFrac > 0.97
    bw = Ir > 0.5 * mean(Ir(Ir > 0.02));   % robust relative fallback
end
```

**Cross-check:** you know what fraction of the frame a disc of radius `R` should
occupy. If the mask area and the fitted radius disagree by more than ~10%,
something upstream went wrong. This single check catches most threshold failures
automatically.

---

### Step 3 — cleanup (order matters)

```matlab
bw = bwareafilt(bw, 1);              % 1. largest component  <-- MUST BE FIRST
bw = imfill(bw, 'holes');            % 2. restore interior
bw = imopen(bw, strel('disk', 5));   % 3. shave thin intrusions
bw = imfill(bw, 'holes');
```

#### Why `bwareafilt` must come before `imfill`

If the image has a **bright frame around its outer edge** — a camera-drawn
border, a burned-in annotation strip, or a 1-px rule from a figure export — then
that frame *encircles* the black surround.

The surround is then no longer connected to the array border, so
`imfill(...,'holes')` correctly identifies it as a hole and **floods the entire
frame.** The mask silently becomes the whole image, `borderFrac` goes to 1.0,
and the circle fit is garbage.

This is not hypothetical. It occurred on the example image, whose outer 1-2 px
ring is pure white:

```
top row    : 969/969 px above threshold
bottom row : 969/969
left col   : 916/916
right col  : 916/916
corner patches: max = 1.0000   <- pure white frame

=> imfill flooded +293,896 px; mask became the entire 969x916 frame
```

Selecting the largest component first discards the frame (it is a **separate**
connected component from the retina — they are separated by the black annulus),
which makes `imfill` safe.

**Guard:** if the mask still exceeds 98% of the frame after cleanup, re-threshold
with the relative fallback.

#### What `imfill` legitimately does

On the example, after the reorder: **+28,753 px filled.** That is the interior
content falling below threshold — the black annotation text, the dark vessels,
the fovea, and the darker macula. All genuinely inside the disc, all correctly
restored.

`imopen(disk 5)` then removed 351 px of thin protrusions (eyelashes, lash
shadows). Scale the disk radius with image size: `round(0.01*R)`.

---

### Step 4 — boundary extraction

```matlab
B = bwboundaries(bw, 'noholes');
p = B{1};          % [row col] pairs
y = p(:,1);  x = p(:,2);
```

Then **discard points lying on the image edge**:

```matlab
free = y > 2 & y < h-1 & x > 2 & x < w-1;
```

Those points sit on a straight sensor edge, not on the circle. Including them
drags the fit badly on any clipped image. The surviving side arcs fully
determine the circle.

---

### Step 5 — Kasa circle fit

A circle is

```
(x - cx)^2 + (y - cy)^2 = R^2
```

Expand it:

```
x^2 + y^2 = 2*cx*x + 2*cy*y + (R^2 - cx^2 - cy^2)
                                \_______________/
                                       = c
```

The right-hand side is **linear** in the three unknowns `[cx, cy, c]`. So it is
an ordinary least-squares problem:

```matlab
A   = [2*x, 2*y, ones(numel(x),1)];
sol = A \ (x.^2 + y.^2);
cx  = sol(1);
cy  = sol(2);
R   = sqrt(sol(3) + cx^2 + cy^2);      % recover R from c
```

**One backslash.** No iteration, no initial guess, no optimiser. That is the
entire "hard" part of stage [A].

#### Why not `regionprops` `EquivDiameter`

`EquivDiameter` is derived from **area** (`2*sqrt(A/pi)`). Most fundus images are
clipped top and bottom by the sensor aspect ratio, so area is missing — and
`EquivDiameter` therefore **under-estimates the radius**, breaking every
downstream size normalisation.

The circle fit recovers the true radius from the unclipped arcs, even when 40%
of the disc is off-sensor.

#### Outlier rejection (second pass)

Notches in the aperture, eyelid intrusions and lash shadows pull boundary points
off the true circle. One reweight removes them:

```matlab
res  = abs(hypot(x-cx, y-cy) - R);
keep = res < max(5, 3*median(res));
[cx, cy, R] = kasa(x(keep), y(keep));
```

Cheap insurance. On a clean image it moves the answer by ~1 px.

**When to upgrade:** Kasa is biased when less than ~30% of the circumference is
visible. If `borderFrac > 0.6`, switch to a **Taubin** fit, which is unbiased on
short arcs.

---

### Step 6 — the measurement mask

```matlab
fov.maskMeasure = imerode(bw, strel('disk', max(3, round(0.02*R))));
```

**This one line is the difference between a focus metric that works and one that
does not.**

The FOV boundary is a near-vertical intensity cliff from ~200 to 0. Left in, it
is the strongest edge in the picture, and it dominates every gradient- and
Laplacian-based measure.

#### Proof — variance of the Laplacian vs blur

Example image, progressively blurred, aperture edge kept hard:

| Blur sigma | full mask | **eroded mask** | ratio |
|---|---|---|---|
| 0 (sharp) | 5.19e-03 | 4.75e-03 | 1.09x |
| 2 | 4.02e-04 | 3.59e-05 | 11x |
| 4 | 3.15e-04 | 1.88e-06 | 168x |
| 8 | 2.81e-04 | 1.23e-07 | 2,293x |
| 16 | 2.65e-04 | 1.22e-08 | 21,761x |

Read the two middle columns downward:

- **Without erosion:** the metric falls from 4.0e-4 to 2.6e-4 across sigma 2->16 —
  a factor of **1.5**. It hits a floor and stops moving. The rim *is* that floor.
  A catastrophically blurred image scores the same as a mildly soft one, and the
  focus feature is **useless**.
- **With erosion:** it falls from 3.6e-5 to 1.2e-8 — a factor of **~3,000**,
  roughly 10x per blur step. Monotonic, huge dynamic range, trivially
  thresholdable.

The erosion does not matter on sharp images. It matters **exactly on the images
you need it for.**

Erode by 2% of R (9 px on the example, keeping 95.5% of the mask). Raise to 4%
if the camera has a soft, heavily vignetted rim.

---

## The five output features

| Name | Formula | Detects |
|---|---|---|
| `radius` | from the fit | wrong distance / wrong zoom |
| `circularity` | `4*pi*A / P^2` | deformed outline (eyelid, occlusion) |
| `offset` | `norm(centre - frameCentre) / R` | optical misalignment |
| `areaFrac` | `A / (pi*R^2)` | how much of the disc was captured |
| `borderFrac` | `#(boundary px on image edge) / #(boundary px)` | sensor clipping |

### `circularity` = 4*pi*A / P^2

For a **perfect circle**, `A = pi*R^2` and `P = 2*pi*R`:

```
4*pi*(pi*R^2) / (2*pi*R)^2  =  4*pi^2*R^2 / (4*pi^2*R^2)  =  1
```

Any other shape scores lower, because a circle encloses the most area for a
given perimeter. A square gives `pi/4 ~= 0.785`. A ragged, eyelid-bitten blob
gives ~0.6.

> **Implementation note:** a naive boundary-*pixel-count* perimeter
> **under-estimates** true perimeter (diagonal steps are sqrt(2) long, not 1) and
> can return values above 1.0. MATLAB `regionprops` uses a proper chain-code
> estimate. **Calibrate thresholds against MATLAB's number, not a hand-rolled one.**

### `offset` — scale-free misalignment

Distance from the disc centre to the frame centre, **divided by R**. The
division makes it scale-free: 0.3 means the same misalignment whether the retina
is 400 px or 1800 px across.

Physically, the FOV aperture is a **fixed** part of the camera optics, so a raw
image should have `offset ~= 0`. A non-zero value means the beam was truncated —
the camera was off-axis and the iris clipped the light path. That is genuine
optical misalignment, and it arrives together with reduced `circularity` and
`areaFrac`.

### `areaFrac` — how much retina survived

Actual mask area divided by the area of the fitted circle. `1.0` = whole disc
captured. `0.6` = 40% missing.

Values slightly **above** 1.0 mean the outline bulges beyond the fitted circle —
a notch or protrusion on the rim.

### `borderFrac` — sensor clipping

```
borderFrac = 0                borderFrac ~ 0.35
+---------------+             +---------------+
|    .-------.  |             |###############|  <- rim runs along
|   /         \ |             |/             \|     the image edge
|  |           ||             ||             ||
|   \         / |             |\             /|
|    '-------'  |             |###############|  <-
+---------------+             +---------------+
 circle floats free            top & bottom clipped
 inside the frame              by the sensor
```

It serves **two** purposes:

1. **Fit correction** — those points lie on a straight sensor edge, not the
   circle, so they are discarded before fitting.
2. **Fit-reliability indicator** — high value means fewer arc points survived, so
   trust `R` less and consider switching to a Taubin fit.

**It is NOT primarily a quality gate.** See below.

---

## Thresholds

### The correction that matters

Simulated clipping (synthetic circle, sensor cropping top and bottom):

| d/R | `borderFrac` | `areaFrac` | Case |
|---|---|---|---|
| 1.00 | 0.05 | 1.00 | full circle, black on all sides |
| 0.95 | 0.23 | 0.99 | slight clip |
| 0.85 | 0.38 | 0.93 | moderate clip |
| **0.75** | **0.47** | **0.86** | **4:3 sensor, circle spans full width — NORMAL** |
| 0.65 | 0.54 | 0.77 | heavy clip |
| 0.55 | 0.61 | 0.66 | severe |
| 0.45 | 0.67 | 0.55 | only a band left |

A perfectly ordinary fundus capture has **`borderFrac ~ 0.47`.** Rejecting on
`borderFrac > 0.5` would discard a large fraction of Messidor-2 and IDRiD.

**Use `areaFrac` as the gate. Use `borderFrac` as a fit-reliability signal.**

### Fast-reject values

For the short-circuit only — gross failures, to save the technician's time.

| Feature | Fast reject | Why |
|---|---|---|
| `areaFrac` | **< 0.50** | less than half the disc — cannot guarantee optic disc *and* macula are both present |
| `offset` | **> 0.35** | aperture truncated by the iris — real optical misalignment |
| `residual` | **> 0.06** | outline deviates from a circle (eyelid, lash, occlusion) |
| `borderFrac` | **> 0.80** | almost the entire rim is sensor edge — a strip, not a retina |
| `radius` | `< 0.15*min(W,H)` | camera far too far from the eye |

### DO NOT gate on `circularity` — measured on 150 APTOS images

`circularity = 4*pi*A/P^2` needs a perimeter estimate, and on real fundus images
the mask boundary is slightly ragged. That inflates `P`, and since `P` is
**squared**, circularity collapses. Observed over 145 successful detections:

```
          min      p5     p25  median     p75     p95     max
circ    0.150   0.280   1.021   1.046   1.103   1.202   1.213
```

Bimodal and unusable. A `circularity < 0.70` gate fired on **17.9%** of real
images — nearly all with `areaFrac` between 0.87 and 1.04, i.e. perfectly intact
discs. It was measuring boundary raggedness, not shape.

**Use `residual` instead** — mean `|dist - R| / R` against the fitted circle. No
perimeter estimate, so no confound. Good masks measure < 0.01; genuinely
malformed ones measured 0.04-0.22.

### The raggedness retry (why detection went 96.7% -> 100%)

Otsu can pick a threshold **inside** the retina on bright or washed-out images.
The mask still has a plausible *area*, so the area-fraction guard misses it — but
the boundary comes out speckled. Detect it by comparing observed boundary length
to the fitted circumference:

```
raggedness = (boundary pixels) / (2*pi*R)      ~1.0-1.3 clean, >1.5 broken
```

Measured on the 5 APTOS detection failures plus 7 false-rejects — Otsu vs the
relative-threshold fallback on the same images:

| | Otsu raggedness | Otsu residual | Fallback raggedness | Fallback residual |
|---|---|---|---|---|
| range across 12 images | 1.49 – 2.54 | 0.037 – 0.215 | 0.90 – 1.37 | 0.002 – 0.044 |

The fallback fixed **all 12**. `detectFOV` now retries automatically whenever
`raggedness > 1.4`.

### Measured distributions (145 APTOS images, stratified by grade)

```
   feature       min       p5      p25   median      p75      p95      max
         R   224.076  274.724  730.714 1084.574 1127.156 1501.657 1800.146
  areaFrac     0.851    0.867    0.875    0.894    0.999    1.005    1.146
    offset     0.003    0.004    0.024    0.038    0.086    0.307    0.519
borderFrac     0.000    0.000    0.102    0.279    0.435    0.446    0.493
```

Two things to read off this:

- **`R` spans 224 to 1800 px — an 8x range** within one dataset. This is the
  empirical justification for `normalizeFundus`.
- **`borderFrac` maxes at 0.493**, exactly as the synthetic clipping table
  predicted. The original `> 0.5` gate would have rejected the worst-clipped real
  images for no good reason; `> 0.80` never fires, which is correct for a
  fast-reject guard.

### Two caveats that matter more than the numbers

1. **These are deliberately loose.** They exist only to skip ~800 ms of focus
   analysis on hopeless images. Everything that passes goes to [E], which weighs
   all ~25 features jointly. A borderline image must **never** be rejected here.

2. **Calibrate on your own data before trusting them.** Run `detectFOV` over a
   few hundred APTOS images, histogram each feature, and read the thresholds off
   *your* distributions. The table above is synthetic circles; real cameras will
   surprise you.

---

## Worked example — full trace

`notes/Diabetic_Retinopathy_Concept/Fovea_&_Optic_Disk.jpg`, 969 x 916.

```
1. threshold      :  593708 px  (0.6689 of frame)     Otsu t = 0.2988
                    sanity: circle R=436 in 969x916 -> 67.3%   AGREES

2. components     : 31  -> largest = 571686 px
                         comp   2:  571686 px   <- retina
                         comp  18:   13675 px   <- white frame fragments
                         comp   1:    6561 px

3. fill holes     : 571686 -> 600439 px  (+28753 = text, vessels, fovea)
4. open(disk 5)   : 600439 -> 600088 px  (-351)

5. boundary pts   : 2534   on image border: 0 (0.00%)

6. Kasa fit       : centre=(482.1, 455.0)  R=436.6
   residual       : mean 1.25 px   p95 2.2 px   max 21.6 px
   worst point    : (141,149)  dev=+21.6px  at 138 deg   <- the notch on the rim
   pts >10px off  : 58 of 2534 (2.3%)
   refit w/o them : centre=(482.8, 455.6)  R=436.2   (shift 1.0px, dR=-0.5)

--- FEATURES ---
radius            : 436.2 px       (frame 969x916)
circularity       : ~0.97          (MATLAB regionprops)
offset            : 0.0066         frame centre is (484.5, 458)
areaFrac          : 1.0040         slightly >1 because of the notch
borderFrac        : 0.0000         circle fully inside the frame
maskMeasure       : erode 9 px -> 95.5% of mask kept

VERDICT: exit 3 -> continue to [B]
```

Two things worth noticing:

- **The fit found the notch without being told.** The visible tab on the
  upper-left rim shows up as the single worst residual, located at 138 degrees.
- **Least-squares was robust to it.** With 97.7% of points on a true circle, 58
  outliers moved the centre by 1.0 px. Outlier rejection is insurance, not a
  necessity, at this contamination level.

---

## Failure modes

| Parameter | Failure | Symptom | Guard |
|---|---|---|---|
| Otsu threshold | histogram not bimodal (retina fills frame, or very dark) | mask is a fragment or the whole frame | area-fraction check 0.15-0.97 -> relative fallback |
| `imfill` order | bright border frame encloses the surround | mask = whole frame, `borderFrac = 1.0` | `bwareafilt` **first**, plus >98% guard |
| `bwareafilt(bw,1)` | retina split by a deep shadow band | you keep only the larger half | `areaFrac` drops to ~0.5 — caught by the gate |
| `strel('disk',5)` | too large on small images | erodes genuine boundary detail | scale it: `round(0.01*R)` |
| Kasa fit | biased when <~30% of circumference visible | `R` systematically off | switch to Taubin when `borderFrac > 0.6` |
| erosion 2% of R | soft / heavily vignetted rim | rim still leaks into metrics | raise to 4%, or erode until the radial gradient flattens |
| red channel | red-free or pre-processed image | `std(Ir) ~ 0` | fall back to `max(I,[],3)` |

---

## Exit logic — reject or continue?

Three exits. The key distinction is between **[A] failing** and **[A] succeeding
but reporting bad geometry** — those are different things.

```
       +-- mask broken? ------------> REJECT  "no retina detected"
[A] ---+-- geometry grossly bad? ---> REJECT  "recentre / move back"
       +-- otherwise ---------------> [B] [C] [D] -> [E] decides
```

### Exit 1 — hard failure, skip [B]-[E]

```
mask empty  |  mask > 98% of frame  |  R absurd (<5% or >200% of frame)
|  boundary < 50 px  |  circle fit degenerate / NaN
```

Stop immediately — not because the image is necessarily bad, but because
**there is no mask, so no downstream metric is computable.** [B], [C] and [D] all
take `maskMeasure` as input. Running them on a broken mask produces confident
numbers about nothing.

> *"No retina detected — is the camera aimed at the eye and the lens cap off?"*

### Exit 2 — gross geometry failure, skip [B]-[E]

Mask is valid but the geometry is unrecoverable (see the fast-reject table).
Short-circuit purely as an **optimisation** — no point spending ~800 ms on focus
analysis for an image that is 60% out of frame.

> *"Retina partly out of frame — recentre and move slightly back."*

These are the **best retake messages in the whole system**, because they are
purely geometric and unambiguous. `atan2` of the centre offset even tells the
technician which way to move.

### Exit 3 — everything else, continue to [B]

Mild geometry problems are **features, not verdicts.** `circularity`, `offset`,
`areaFrac` and `borderFrac` go into the classifier alongside the focus and
illumination features, and [E] weighs them jointly.

An image can be noticeably off-centre and still perfectly gradable, as long as
the optic disc and macula are visible. Conversely a perfectly centred image can
be useless because it is out of focus. **Geometry is one input among ~25, not a
gate.**

---

## Radius normalization

The payoff of [A]. See [`matlab/normalizeFundus.m`](../matlab/normalizeFundus.m).

```matlab
s = targetR / fov.radius;
J = imresize(I, s);
J = cropCentred(J, fov.centre*s, targetR);
```

APTOS retinal radii range from ~400 to ~1800 px. IDRiD is ~1400 px. DRIVE is
~270 px. Without normalisation, "a microaneurysm is under 125 um" cannot be
turned into a pixel threshold, and **no size-based rule generalises across
datasets.**

After this call, one pixel means the same physical distance in every image from
every camera. Suggested `targetR = 540` (a 1080 px retinal diameter) for the
lesion-detection stream; downsample separately for the CNN stream.

This is the single highest-leverage step in the entire preprocessing chain.

---

## Next

Stage [B] — focus and sharpness metrics: `imgradient`, variance of the
Laplacian, SML, spectral slope, and the per-quadrant trick. All of them consume
`fov.maskMeasure` from this stage.

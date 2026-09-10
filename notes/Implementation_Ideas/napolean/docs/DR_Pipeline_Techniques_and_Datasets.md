# Automated DR Screening — Techniques & Datasets Reference

A working reference for the SIH MathWorks 2026 problem statement: a MATLAB-based
retinal image analysis pipeline for automated Diabetic Retinopathy screening.

For each technique: what it actually is, why this problem needs it, the MATLAB
function that does it, and the gotcha that separates a working demo from a broken one.

---

## Table of contents

- [The big picture](#the-big-picture)
- [Module 1 — Image Quality Assessment & Enhancement](#module-1--image-quality-assessment--enhancement)
- [Module 2 — Retinal Structure Segmentation](#module-2--retinal-structure-segmentation)
- [Module 3 — DR Severity Grading](#module-3--dr-severity-grading)
- [Module 4 — Explainability](#module-4--explainability)
- [Module 5 — Simulink Workflow Simulation](#module-5--simulink-workflow-simulation)
- [How the modules interlock](#how-the-modules-interlock)
- [What actually wins points](#what-actually-wins-points)
- [Datasets](#datasets)
- [The split protocol](#the-split-protocol-i-would-commit-to)
- [Practical ingestion notes](#practical-ingestion-notes)

---

# The big picture

The pipeline is five stages that feed each other:

```
Fundus image
    |
[1] Quality gate --reject--> "recapture, too blurry"
    | (pass or enhance)
[2] Structure & lesion segmentation
    | (lesion counts, locations, types)
[3] Severity grading (0-4)  <-- CNN + lesion features fused
    |
[4] Explanation (heatmap + lesion evidence + confidence)
    |
[5] Simulink: how does this scale to 100k patients/year?
```

The single most important design idea: **stage 2 and stage 3 must reinforce each
other.** A pure CNN gets good accuracy but explains nothing. A pure lesion-counter
is explainable but brittle. The problem statement explicitly asks you to beat
"any single technique approach" — that means fusion, and that's your whole
novelty pitch.

---

# Module 1 — Image Quality Assessment & Enhancement

## Why this exists

A portable fundus camera in a PHC, operated by a technician with two days of
training, produces garbage maybe 15-25% of the time. If you feed garbage to the
classifier, it confidently outputs "No DR" and someone goes blind. So the first
thing your system must be able to say is **"I can't read this, take it again."**
That refusal is a feature, not a failure.

## The quality metrics

### Focus / sharpness

A blurred image has no high-frequency energy.

- **Variance of Laplacian** — run a Laplacian kernel over the image, take the
  variance of the result. Sharp image → high variance.
  `var(imfilter(I, fspecial('laplacian')), 0, 'all')`
- **Tenengrad** — sum of squared Sobel gradient magnitudes. `imgradient` gives
  you the magnitude directly.
- **Spectral ratio** — `fft2`, then measure the fraction of energy above a
  cutoff radius.

> **Gotcha:** a completely dark image is also "smooth" and scores low. Always
> compute these **inside the retinal disc only**, never on the black surround.

### Illumination adequacy

Fundus images suffer uneven illumination — the centre is bright, the periphery
falls off, and a badly aligned camera creates a bright crescent on one side.

- Estimate the background: heavy median filter or morphological opening with a
  large disk. What remains is the illumination field.
- Check its mean (under/over-exposed?) and its coefficient of variation (uneven?).
- Check saturation: fraction of pixels at 0 or 255. Lens flare and overexposure
  both blow out detail permanently.

### Field of view

The retina appears as a bright circle on black.

- Threshold the red channel (retina is red-dominant) → largest connected
  component → that's your FOV mask.
- `regionprops` gives you `Circularity`, `Centroid`, `EquivDiameter`. Low
  circularity → the eye was partially out of frame. Centroid far from image
  centre → misaligned.
- Clinically you need both the **optic disc and the macula visible** — that's the
  minimum for a gradable field.

### No-reference IQA

Image Processing Toolbox ships `brisque`, `niqe`, `piqe` — generic perceptual
quality scores. They're trained on natural photographs, so they don't understand
retinas, but they're cheap extra features. Better: retrain BRISQUE on your own
fundus images with `fitbrisque`.

## Turning metrics into a decision

Don't hand-tune thresholds. Collect ~15 of these features per image, label a few
hundred images as gradable/borderline/ungradable, and train a classifier:

```matlab
mdl = fitcensemble(featureTable, labels, 'Method','Bag');
% or fitcsvm / fitcecoc  (Statistics and Machine Learning Toolbox)
```

Three-way output:

| Verdict | Action |
|---|---|
| Gradable | pass through unchanged |
| Borderline | run enhancement, re-score, then pass |
| Ungradable | reject with a **specific** reason: "out of focus", "underexposed", "eye not centred" |

That specific reason is what makes recapture feedback useful to the technician.
"Bad image" is worthless; "too dark — increase flash" is actionable.

## The enhancement techniques

### Green channel extraction

Not glamorous but essential. Haemoglobin absorbs green light strongly. So in the
green channel, vessels and haemorrhages are darkest, exudates are brightest —
maximum lesion contrast. The red channel is saturated and washed out, the blue is
noisy. Almost every classical fundus algorithm runs on green.

### CLAHE — Contrast Limited Adaptive Histogram Equalization

`adapthisteq`

Plain histogram equalization stretches contrast globally, which fails when one
corner is dark and another is bright. CLAHE divides the image into tiles (say
8x8), equalizes each tile independently, and bilinearly interpolates between them
so you don't get tile seams. The "contrast limited" part clips the histogram at a
`ClipLimit` before equalizing and redistributes the clipped mass — without this,
flat regions get their noise amplified into visible grain.

```matlab
Ieq = adapthisteq(Igreen, 'NumTiles',[8 8], 'ClipLimit',0.01, 'Distribution','rayleigh');
```

> **Gotcha:** **never apply CLAHE to R, G, B independently** — the channels
> stretch by different amounts and the colour shifts, which destroys the
> yellow-vs-red distinction between exudates and haemorrhages. Convert to
> L\*a\*b\*, apply CLAHE to L only, convert back.

### Illumination normalization

- **Flat-field correction** — `imflatfield(I, sigma)` estimates a smooth
  illumination field via a wide Gaussian and divides it out. One line, works well.
- **Background subtraction** — estimate background with a large median filter,
  then `I - background + mean`. Slightly more controllable.
- **Homomorphic filtering** — take `log`, high-pass in the frequency domain
  (illumination is low-frequency, reflectance is high-frequency), then `exp`.
  More principled, more parameters.

### Ben Graham preprocessing

The trick that won the 2015 Kaggle DR competition, and still a strong baseline:

```matlab
Ip = 4*im2double(I) - 4*imgaussfilt(im2double(I), sigma) + 0.5;
```

Subtracting a heavy local blur removes all slow illumination variation and colour
cast simultaneously, leaving pure local structure. Combine with circle-cropping
and resizing so every image has the same retinal radius. This normalizes across
camera models — critical for the "variable image quality from portable cameras"
requirement.

### Denoising

`imnlmfilt` (non-local means), `imbilatfilt` (bilateral), `wdenoise2` (wavelet),
or `denoiseImage` with a pretrained DnCNN.

> **The biggest trap in the entire project lives here.** A microaneurysm is
> 10-100 um — often **3-5 pixels wide**. Aggressive denoising deletes
> microaneurysms. If your mild-DR sensitivity mysteriously collapses, this is why.
> Use only edge-preserving filters at low strength, and always validate that your
> MA detector's recall doesn't drop after enhancement. Ideally: run lesion
> detection on the *lightly* processed image, and reserve heavy enhancement for
> the CNN branch and for human viewing.

---

# Module 2 — Retinal Structure Segmentation

## Optic disc localization

The optic disc (OD) is the bright circular region where the optic nerve and
vessels enter. Roughly 1/7 of image width in diameter.

**Why you must find it:** the OD is bright, round, and yellowish — exactly like a
cluster of hard exudates. Every exudate detector that skips OD masking produces a
giant false positive on every single image. Finding the OD is also how you find
the fovea, and NVD (new vessels *at the disc*) is graded separately from NVE.

Methods, easiest to best:

1. Brightest-region search after median filtering. Fails when there are large exudates.
2. **Maximum local intensity variance** — the OD is where dark vessels cross
   bright tissue, so variance peaks there. More robust than brightness alone.
3. `imfindcircles` (Circular Hough Transform) constrained to the expected radius range.
4. **Vessel convergence** — all major vessels radiate from the OD; fit their
   directions and find the convergence point.
5. A small CNN regressing the (x, y) centre, or a U-Net segmenting the disc. Best
   accuracy; IDRiD provides OD masks.

## Fovea localization

The fovea is the dark avascular pit at the centre of the macula — where sharp
central vision lives. It sits roughly **2.5 optic disc diameters temporal to the
OD**, on the axis of the main vascular arcade.

Practical method: define a search region 2-3 DD from the OD along the arcade
axis, then find the darkest smooth blob with no vessels. Or template-match.

**Why it matters clinically:** distance from the fovea determines urgency. Hard
exudates within 500 um of the fovea = clinically significant macular oedema =
urgent referral, *regardless of the DR grade*. A system that reports "exudates
present" but not "exudates 400 um from fovea" is missing the clinically decisive
fact.

## Vessel segmentation

### Classical approaches

- **Matched filtering** — vessels have a roughly Gaussian intensity
  cross-section. Build a 2D kernel that is Gaussian across and constant along,
  rotate it through 12-15 orientations, convolve, take the max response per pixel.
  Threshold. (Chaudhuri et al., the classic method.)
- **Frangi vesselness** — compute the Hessian at multiple scales; a tubular
  structure has one small eigenvalue (along the vessel) and one large (across it).
  Combine the eigenvalue ratio into a "vesselness" score. Multi-scale handles both
  thick arcades and thin capillaries. `fibermetric` is MATLAB's built-in version.
- **Morphological** — top-hat with **linear** structuring elements at many angles:
  `imtophat(I, strel('line', L, theta))`. Anything longer than L in some direction
  survives; compact blobs don't.

### Deep approach

U-Net trained on DRIVE, STARE, CHASE_DB1, or HRF — all have manual vessel
annotations. Encoder-decoder with skip connections; build it with `unetLayers`
in Deep Learning Toolbox. Gets ~0.96 AUC vs ~0.92 for classical. Small datasets,
so patch-based training + heavy augmentation.

### Three separate reasons you need the vessel map

1. **Subtraction.** Vessels are dark on green — exactly like haemorrhages and
   microaneurysms. Every dark-lesion detector must first remove the vessel tree,
   or every vessel pixel becomes a false lesion.
2. **Biomarkers.** Vessel tortuosity, arteriolar-to-venular ratio (AVR), fractal
   dimension, and **venous beading** (sausage-like calibre variation) are
   themselves DR signs — venous beading in 2+ quadrants is a defining criterion
   for *severe* NPDR.
3. **Neovascularization** is defined entirely in terms of abnormal vessels.

## Microaneurysm detection — the hard one

MAs are the **earliest visible sign of DR**. Tiny outpouchings of capillary walls:
small (<125 um), round, dark red, isolated, and — crucially — **not connected to a
visible vessel**. Level 1 (mild NPDR) is literally defined as "microaneurysms
only," so your entire ability to detect early disease rests on this.

The classical pipeline, which still works well:

1. Green channel, shade-corrected.
2. **Vessel removal by morphological closing with linear SEs.** Close the image
   with a line SE at ~12 orientations and take the minimum across orientations. A
   vessel is elongated, so *some* orientation's line fits inside it and it
   survives closing. An MA is compact, so *every* orientation's line bridges over
   it and it gets filled. Subtract: `closed - original` leaves MAs and removes
   vessels. Elegant, and the core of the Frame/Spencer/Cree family of methods.
3. Threshold at multiple levels to get candidate regions (high recall, terrible
   precision — expect 100+ candidates per image).
4. Extract features per candidate: area, perimeter, eccentricity, circularity,
   mean/max intensity, contrast to local background, **residual of a 2D Gaussian
   fit** (real MAs are Gaussian blobs; noise isn't), colour in all three channels,
   distance to nearest vessel.
5. Train a classifier (`fitcensemble`, `fitcsvm`) to prune false positives.

Alternatives: matched filtering with a small Gaussian kernel sized to an MA; the
Radon transform; wavelet-based detection; or a small patch-CNN over candidates
(steps 4-5 replaced by learning).

> **"Sub-pixel microaneurysm detection" is the phrase in the problem statement
> that dictates your architecture.** Standard CNN classification resizes images to
> 224x224 or 512x512. At 224x224, a microaneurysm is **under one pixel**. It is
> physically not in the input. This is why a naive ResNet on resized images
> plateaus on mild DR — and why your pipeline must run lesion detection at or near
> **native resolution** (1500-2000 px wide, or tiled patches), separately from the
> whole-image CNN. Say this in your presentation; it shows you understand the
> problem rather than just plugging in a classifier.

## Exudate segmentation

Exudates are bright lipid/protein deposits leaking from damaged vessels.

- **Hard exudates** — yellow, sharply defined, waxy, often in rings or clusters.
  Indicate leakage; near the fovea → macular oedema.
- **Soft exudates / cotton-wool spots** — pale, fluffy, indistinct borders. These
  are nerve-fibre-layer infarcts — small strokes in the retina. Different meaning,
  so classify them separately.

Approach:

1. **Mask out the optic disc first.** Non-negotiable.
2. Candidate detection: morphological reconstruction (reconstruct a
   heavily-eroded marker under the original image; what fails to reconstruct is a
   bright lesion), or dynamic/adaptive thresholding on the shade-corrected green
   channel, or `imextendedmax`.
3. Refine boundaries with region growing or watershed.
4. Features: area, mean intensity, **edge sharpness** (hard = sharp gradient,
   soft = gradual), colour saturation, texture entropy. Classify hard vs soft.
5. Compute **distance from fovea in disc-diameter units** — this is the
   clinically-reportable number.

Or: U-Net trained on IDRiD / e-ophtha-EX, which come with pixel-level exudate masks.

## Haemorrhage detection and classification

Haemorrhages are dark red like MAs but larger and irregular (>125 um is the
conventional MA/haemorrhage boundary). The subtypes carry different information:

- **Dot/blot** — deep intraretinal, round, well-defined. From the deep capillary
  plexus. Their *count per quadrant* drives the severe-NPDR rule.
- **Flame-shaped / splinter** — superficial, in the nerve fibre layer, so they
  spread along the fibre direction and look feathery. Often hypertensive rather
  than purely diabetic.
- **Preretinal / vitreous** — large, may show a fluid level. These mean
  **proliferative disease (level 4)**.

Detection reuses the dark-lesion pipeline from MAs (green channel, vessel removal,
thresholding), then splits on size. Subtype classification uses shape
descriptors: eccentricity, solidity, boundary smoothness, orientation relative to
the local vessel direction, and area.

## Neovascularization detection

New, fragile, abnormal vessels growing in response to retinal ischaemia. **This is
what makes DR proliferative (level 4)** and it is the sight-threatening endpoint —
these vessels bleed into the vitreous and cause tractional retinal detachment.

- **NVD** — neovascularization at/near the optic disc (within 1 DD).
- **NVE** — elsewhere in the retina.

They look different from normal vessels: fine calibre, highly tortuous, convoluted
loops, irregular branching that doesn't follow the normal dichotomous arcade
pattern, and abnormally high vessel density in a local patch.

Approach: segment vessels → slide a window over the vessel map → per window
compute density, number of branch/end points (`bwmorph` with `'branchpoints'`,
`'endpoints'`), tortuosity (arc-length / chord-length per segment), calibre
variance, fractal dimension, orientation entropy → classify each window. Or a CNN
on vessel-map patches.

This is the rarest class and the hardest to get data for. Be honest about it in
your validation — a low PDR sample count with wide confidence intervals, reported
clearly, reads as rigour. Hiding it reads as naivety.

---

# Module 3 — DR Severity Grading

## The scale you must implement

**International Clinical Diabetic Retinopathy (ICDR) severity scale:**

| Level | Name | Defining findings |
|---|---|---|
| 0 | No apparent DR | No abnormalities |
| 1 | Mild NPDR | **Microaneurysms only** |
| 2 | Moderate NPDR | More than MAs, but less than severe |
| 3 | Severe NPDR | **The 4-2-1 rule** (below), and no proliferative signs |
| 4 | Proliferative DR | Neovascularization **and/or** vitreous / preretinal haemorrhage |

**The 4-2-1 rule** — severe NPDR if *any* of:

- \>20 intraretinal haemorrhages in **each of 4** quadrants, **or**
- definite venous beading in **2**+ quadrants, **or**
- prominent IRMA (intraretinal microvascular abnormalities) in **1**+ quadrant.

Notice that this rule is **spatial and quantitative** — it needs per-quadrant
lesion counts. That's a direct architectural requirement: your lesion detector
must divide the retina into four quadrants (using the OD-fovea axis to orient
them) and count within each. Very few student projects do this. Doing it is an
easy differentiator.

**Referable DR = level >= 2** (plus any DME). That's the binary decision the whole
>90% sensitivity / >85% specificity requirement is about. Levels 0-1 get
re-screened in a year; level 2+ sees an ophthalmologist.

## Three ways to grade, and why you should do all three

### (a) End-to-end CNN

Fine-tune a pretrained backbone. Deep Learning Toolbox:

```matlab
net = imagePretrainedNetwork("resnet50", NumClasses=5);
% or efficientnetb0, inceptionresnetv2, convnext
net = trainnet(imds, net, "crossentropy", options);
```

Use `imageDatastore` + `augmentedImageDatastore` for rotation/flip/scale/brightness
augmentation (fundus images are rotation-tolerant — free augmentation). Strong
overall accuracy, near-zero interpretability, and weak on level 1 because of the
resolution problem above.

### (b) Lesion-feature classifier

Feed the counts and locations from Module 2 into a classifier, or directly into
the ICDR rules. Fully interpretable, maps 1:1 onto clinical criteria, degrades
gracefully — but it inherits every error from the lesion detectors.

### (c) Hybrid fusion — your actual contribution

Concatenate the CNN's penultimate-layer embedding with the hand-crafted lesion
feature vector (per-quadrant MA count, haemorrhage count, exudate area,
exudate-fovea distance, NV score, vessel tortuosity) and train a gradient-boosted
ensemble or SVM on the combination. Or stack: use CNN probability + lesion
features as inputs to a meta-learner.

The ablation table — **CNN alone / lesions alone / fused** — with sensitivity and
specificity for each is **literally the "outperforms any single technique"
evidence the problem statement asks for.** Build that table early; it's your
headline slide.

## Things that will bite you

**Ordinality.** The grades are ordered. Predicting 4 for a true 0 is catastrophic;
predicting 1 is minor. Plain cross-entropy treats these identically. Fixes: train
as **regression** and threshold the continuous output (what most top Kaggle
solutions did), or use an ordinal loss (CORAL/CORN), or use **quadratic weighted
kappa** as your selection metric — it penalizes by squared distance and is the
standard metric in this field.

**Class imbalance.** Roughly 70-75% of screening images are level 0; PDR is 2-3%.
An untouched model will predict "0" for everything and report 73% accuracy. Fixes:
class weights in the loss, focal loss, oversampling minorities, undersampling
level 0, and — most importantly — **never report plain accuracy.** Report
per-class sensitivity, confusion matrix, and quadratic weighted kappa.

**Hitting the sensitivity/specificity targets.** These are not properties of the
model, they're properties of the **operating point**. Train the model, then:

```matlab
[X, Y, T, AUC] = perfcurve(trueLabels, scores, 'referable');
```

Walk the ROC curve, find the threshold where sensitivity >= 0.90, read off the
specificity there, and check it's >= 0.85. Then **report bootstrap confidence
intervals** on both, and fix the threshold on a validation set before touching the
test set. Choosing the threshold on the test set is the single most common way
student projects accidentally cheat.

**External validation.** Train on one dataset, test on a different one from a
different population and camera. See the [Datasets](#datasets) section.

---

# Module 4 — Explainability

## Grad-CAM

**What it does mechanically:** take the score for the predicted class, compute its
gradient with respect to the feature maps of the last convolutional layer,
global-average-pool those gradients per channel to get an importance weight per
channel, take the weighted sum of feature maps, apply ReLU (keep only evidence
*for* the class), and upsample to image size. Result: a heatmap of "where the
network looked."

MATLAB has it built in:

```matlab
map = gradCAM(net, img, classLabel);
imshow(img); hold on; imagesc(map, 'AlphaData', 0.5); colormap jet
```

Also available: `occlusionSensitivity` (slide a grey patch, see where the score
drops — slower but model-agnostic and often crisper) and `imageLIME`
(superpixel-based local surrogate model).

> **The honest limitation, which you should address head-on:** the last conv layer
> of ResNet-50 on a 512x512 input is 16x16. Upsampled, each Grad-CAM "pixel"
> covers a 32x32 image region. A microaneurysm is 3 pixels. **Grad-CAM physically
> cannot point at a microaneurysm.** It will show a warm blob over "roughly this
> quadrant," which an ophthalmologist will find useless.

Mitigations: hook an earlier, higher-resolution conv layer
(`gradCAM(..., 'FeatureLayer', ...)`); use Grad-CAM++ or Score-CAM; or — best —
**overlay your Module 2 lesion detections as the primary explanation and use
Grad-CAM as a secondary sanity check.** That reframing is a genuine insight and
gives you something to say when a judge asks "isn't Grad-CAM known to be
unreliable?"

## Lesion-level evidence — the explanation that actually matters

This is where the hybrid architecture pays off. Instead of a vague heatmap, you
output:

> **Grade 2 — Moderate NPDR. Referable.**
> Evidence: 17 microaneurysms (7 superior-temporal, 4 inferior-temporal, 6 nasal);
> 5 dot haemorrhages; 3 hard exudate clusters, nearest **0.9 DD from fovea**; no
> venous beading; no neovascularization.
> Criterion met: more than microaneurysms alone, 4-2-1 rule not satisfied → Level 2.
> Confidence: 0.87 (calibrated).

That's checkable in about ten seconds. The ophthalmologist glances at the
annotated image, confirms the lesions are really there, and clicks agree.
**That's the 30-second review target** — and it's achievable only because the
explanation is in clinical vocabulary, not in colormap.

## Calibrated confidence

A neural network's softmax output is *not* a probability. Modern deep nets are
badly overconfident — a network that says "0.95" is right maybe 80% of the time.
If you route cases to humans based on an uncalibrated score, your triage is
silently broken.

**Calibration methods:**

- **Temperature scaling** — learn a single scalar T on a validation set, output
  `softmax(logits/T)`. One parameter, remarkably effective, doesn't change the
  ranking (so accuracy and AUC are untouched, only the probabilities move).
- **Platt scaling** — fit a logistic regression on the scores. `fitPosterior`
  does this for SVMs in Statistics and ML Toolbox.
- **Isotonic regression** — non-parametric, more flexible, needs more data.

**How to measure it:** a **reliability diagram** — bin predictions by confidence,
plot bin-mean-confidence against bin-accuracy. Perfect calibration is the
diagonal. Summarize with **Expected Calibration Error (ECE)** = weighted mean gap
between the two. A before/after reliability diagram is a strong, uncommon slide.

**Uncertainty (distinct from calibration):** MC-dropout (keep dropout on at
inference, run 30 forward passes, take the variance) or a deep ensemble (train 5
models, measure disagreement). High variance = the model is out of its depth.
Route those to a human regardless of the predicted class. This is what makes it a
genuine *human-in-the-loop* system rather than an autonomous one.

## Automated reports

MATLAB Report Generator, or programmatic figure composition and `exportgraphics`
to PDF. Design for the 30-second constraint: one page, image-first, annotated
overlays in distinct colours per lesion type, grade and confidence large at the
top, criteria checklist beside it, and a single prominent **Agree / Override**
affordance. Log every override — that's your active-learning data and your
post-deployment monitoring signal.

---

# Module 5 — Simulink Workflow Simulation

## What kind of model this is

Not signal processing. This is a **discrete-event / queueing simulation**, and the
right tool is **SimEvents** (the discrete-event add-on for Simulink). Entities are
patients and images; blocks are generators, queues, servers, gates, and routers.

## The system to model

```
Patient arrives at PHC  ->  Camera capture  ->  Quality check
                                                    | fail (retake)
                                                    |____^
                                                pass
                                                  |
                            Compress -> Upload over rural link (bandwidth-limited queue)
                                                  |
                                      District server: AI inference (throughput-limited)
                                                  |
                                Triage: non-referable & confident -> auto-report
                                        referable OR low-confidence -> ophthalmologist queue
                                                  |
                                      Ophthalmologist review (~30 s each)
                                                  |
                                            Referral / recall
```

## Parameters to put in

- **Arrival rate.** 100,000/year / ~250 working days = **~400 patients/day** across
  the district. Split across N screening centres. Model as a Poisson process; add
  a time-of-day profile if you want realism (morning rush).
- **Capture time** per patient, plus a **retake probability** — and here's the
  nice part: *that probability comes from your Module 1 rejection rate.* Module 1
  and Module 5 are coupled. Improving image quality assessment reduces retakes,
  which reduces per-patient time, which increases throughput. You can quantify that.
- **Bandwidth.** Image size / uplink rate, with contention when several centres
  upload simultaneously. Rural links might be 1-5 Mbps and intermittent. Model
  outages as a random gate.
- **Compression trade-off.** JPEG at quality 60 uploads 4x faster — and destroys
  microaneurysms. You can *measure* the accuracy loss vs compression level offline
  and put that curve into the Simulink model. Now the simulation optimizes a
  genuine accuracy-vs-latency trade-off rather than an invented one.
- **Inference throughput.** Images/second on your target hardware. Batch or serial.
- **Review capacity.** Number of ophthalmologists x hours x 3600/30 s. This is the
  scarce resource — the entire problem premise is that there aren't enough of them.

## Outputs and the optimization

Measure: queue lengths, waiting times, end-to-end latency distribution, resource
utilization per stage, and where the bottleneck sits under each configuration.

Then **sweep parameters** — number of cameras, number of centres, bandwidth,
compression level, staffing, and the AI confidence threshold — and find the
configuration that clears 100k/year within the available review capacity.

Sanity-check with **Little's Law**: `L = lambda * W` (average number in system =
arrival rate x average time in system). If your simulation violates it, you have a
modelling bug.

## The insight that makes this module impressive

**The AI's decision threshold is a resource-allocation control knob.**

- Raise the sensitivity target → more false positives → more cases sent to the
  ophthalmologist → review queue overflows.
- Lower it → fewer referrals, less human workload → but you miss real disease.

So the ROC curve from Module 3 and the queueing model in Module 5 are **the same
optimization problem seen from two directions.** You can plot: for each operating
point on the ROC curve, the resulting ophthalmologist workload and mean patient
wait — and identify the point that achieves >90% sensitivity *while staying within
the district's actual review capacity.*

Almost nobody makes this connection. It converts Module 5 from "we also made a
Simulink diagram because they asked" into the piece that ties the whole system
together. Lead with it.

---

# How the modules interlock

| Producer | Consumer | What flows |
|---|---|---|
| M1 quality score | M3 grading | low quality → widen confidence bounds, lower auto-report threshold |
| M1 rejection rate | M5 Simulink | retake probability → throughput |
| M2 vessel map | M2 lesion detectors | vessel subtraction before dark-lesion detection |
| M2 optic disc | M2 exudates | OD masking prevents the dominant false positive |
| M2 OD + fovea | M3 grading | quadrant definition for the 4-2-1 rule; exudate-fovea distance for DME |
| M2 lesion features | M3 grading | the fusion input that beats CNN-alone |
| M2 lesion map | M4 explanation | the actual clinical evidence, better than Grad-CAM |
| M3 confidence | M5 Simulink | triage threshold → review queue load |
| M4 overrides | M3 retraining | active learning loop |

---

# What actually wins points

1. **The refusal path.** Most teams build a classifier. Very few build a system
   that says "I can't read this." Demo a deliberately blurred image being rejected
   with a specific, actionable reason.
2. **The ablation table.** CNN / lesions / fused, with sensitivity + specificity +
   kappa and confidence intervals. This is the literal deliverable: "outperforms
   any single technique."
3. **Native-resolution lesion detection.** Explain out loud why 224x224 cannot
   contain a microaneurysm. It shows you understand the physics, not just the API.
4. **Calibration curves.** Before/after temperature scaling. Rare, cheap, and
   reads as clinical seriousness.
5. **The 4-2-1 rule implemented literally**, with per-quadrant counts. Ties your
   CV output to the actual clinical standard.
6. **Threshold ↔ staffing coupling** in the Simulink model.
7. **External validation** on a dataset you didn't train on, benchmarked against
   published numbers.
8. **Honest failure analysis.** Show where it breaks — cataract-clouded images,
   PDR under-representation, media opacity. Judges trust teams that know their
   limits far more than teams that claim 99%.

**Suggested build order:** Module 3 (a plain fine-tuned CNN) first, in a weekend —
it gives you an end-to-end baseline and a number. Then Module 1, because it's the
highest value per hour and it de-risks everything downstream. Then Module 2 lesion
detection — that's the long pole, budget the most time there. Modules 4 and 5 are
fast once 2 and 3 exist.

---

# Datasets

## Links

| Dataset | URL |
|---|---|
| APTOS 2019 Blindness Detection | https://www.kaggle.com/c/aptos2019-blindness-detection |
| IDRiD (Indian Diabetic Retinopathy Image Dataset) | https://ieeedataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid |
| DRIVE (Vessel Extraction) | https://drive.grand-challenge.org/ |
| Messidor-2 | https://www.adcis.net/en/third-party/messidor2/ |

## Coverage matrix

| Module | Needs | Covered by |
|---|---|---|
| M1 Quality assessment | gradable/ungradable labels | **none of these** |
| M2 Vessels | pixel vessel masks | DRIVE |
| M2 Optic disc / fovea | centre coordinates + OD mask | IDRiD (both) |
| M2 MA / HE / EX / SE | pixel lesion masks | IDRiD (81 images) |
| M2 Neovascularization | NV masks | **none of these** |
| M3 Grading (train) | image-level 0-4 | APTOS |
| M3 Grading (external test) | image-level 0-4, different population | Messidor-2, IDRiD-B |
| M3 DME | macular oedema risk grade | IDRiD (0-2) |
| M4 Explainability | lesion masks to validate heatmaps against | IDRiD |
| M5 Simulink | throughput/timing params | synthesize from literature |

Two real holes: **image quality labels** and **neovascularization**. Covered below.

---

## APTOS 2019 — your grading training set

**What's in it:** 3,662 training images with ICDR grades 0-4. The 1,928 test
images have **no public labels** (competition holdout), so treat the 3,662 as your
entire usable set and make your own splits.

**Rough class distribution (train):**

| Grade | ~Count | Share |
|---|---|---|
| 0 No DR | ~1,805 | 49% |
| 1 Mild | ~370 | 10% |
| 2 Moderate | ~999 | 27% |
| 3 Severe | ~193 | 5% |
| 4 PDR | ~295 | 8% |

Grade 3 has **under 200 images**. Any per-class metric for severe NPDR will have
wide confidence intervals. Say so rather than hiding it.

**Why it's the right training set:** collected at **Aravind Eye Hospital, Tamil
Nadu**, by technicians travelling to rural sites — exactly your deployment
scenario. Multiple camera models, multiple years, genuinely variable quality.
Images come pre-cropped inconsistently: some are tight circles, some have big
black bars, some are square-cropped with the retina clipped top and bottom.
Aspect ratios and resolutions vary a lot.

**Gotchas:**

- **Normalize the retinal circle before anything else.** Detect the FOV, crop to
  the bounding box of the disc, resize so the retinal *radius* is constant across
  all images. Without this, "lesion size in pixels" means something different in
  every image and your MA size thresholds are meaningless.
- The variable quality is a **feature** — it's realistic, and it's why a model
  trained here transfers to PHC conditions better than one trained on clean
  Messidor images.
- Metric was **quadratic weighted kappa**. Top private-leaderboard solutions
  landed around **0.93**. A solid student result is 0.88-0.91. Use QWK as your
  model-selection metric, not accuracy.
- Kaggle competition rules restrict use — fine for a prototype/competition entry,
  but read them if you ever talk about deployment.

---

## IDRiD — the most valuable of the four

This is the one that makes Module 2 possible at all. From an eye clinic in
**Nanded, Maharashtra**. Three sub-parts:

**A. Segmentation — 81 images, 54 train / 27 test.** Pixel-level binary masks for:

- Microaneurysms (MA)
- Haemorrhages (HE)
- Hard exudates (EX)
- Soft exudates / cotton wool spots (SE)
- Optic disc (OD)

**B. Disease Grading — 516 images, 413 train / 103 test.** DR grade 0-4 **and**
DME risk grade 0-2.

**C. Localization — 516 images.** Optic disc centre and **fovea centre** coordinates.

**Resolution: 4288 x 2848**, Kowa VX-10a, 50 deg FOV, JPG. This matters
enormously — remember the sub-pixel MA problem? At 4288 px wide, a microaneurysm
is genuinely resolvable, maybe 8-15 px. **IDRiD is where you train and validate
the native-resolution lesion detectors.** You cannot do this on APTOS, which has
no lesion masks.

**Gotchas:**

- **81 images is tiny.** You will not train a large segmentation network on it
  directly. Work in **patches**: tile each 4288x2848 image into ~512x512 patches
  with overlap, which turns 54 images into thousands of patches. Heavy
  augmentation (rotation is free on fundus images, flips, elastic deformation,
  colour jitter).
- **Severe class imbalance at pixel level.** MA pixels are maybe 0.01% of the
  image. Plain cross-entropy will predict "background" everywhere and hit 99.99%
  pixel accuracy. Use **Dice loss, focal loss, or Tversky loss**, and evaluate
  with **AUPR (area under precision-recall)**, never pixel accuracy or ROC-AUC.
- **Calibrate your expectations.** State-of-the-art AUPR on IDRiD segmentation is
  roughly: EX ~0.80, SE ~0.70, HE ~0.65, **MA ~0.50**. Microaneurysm segmentation
  is genuinely unsolved. If you get MA AUPR of 0.40 you're in respectable
  territory, not failing. Knowing this number and citing it protects you when a
  judge asks why MA performance looks low.
- Sub-part B (516 graded images) is a good **second external test set** for
  grading — different camera and city from APTOS.
- Licensing is CC BY (open access via IEEE DataPort); free account needed.

**Use IDRiD-C (fovea coordinates) to train/validate your fovea localizer**, then
use fovea position to compute exudate-fovea distance for DME — and IDRiD-B's DME
grades give you ground truth for that whole chain. That's a complete,
self-contained, clinically meaningful sub-result you can demo.

---

## DRIVE — vessels only

40 images, 565 x 584, from a **Dutch** DR screening programme. 20 train / 20 test.
Ships with manual vessel segmentations (the test set has **two independent
observers**, giving you a human performance ceiling) and FOV masks. 7 of the 40
show mild early DR; the rest are normal.

**Benchmarks to compare against:**

- Second human observer: accuracy ~0.947, sensitivity ~0.776
- U-Net-class methods: AUC ~0.975-0.982, accuracy ~0.955, sensitivity ~0.78-0.83

If your vessel network hits AUC ~0.97 you're at published-method level. An easy,
credible "we match the literature" claim.

**The gotcha that will actually bite you:** DRIVE is **565 px wide**, Dutch
population, Canon CR5 camera, 45 deg FOV. Your target images are 4288 px, Indian
population, different cameras. A model trained on DRIVE and applied to IDRiD
**will underperform badly** unless you handle the domain shift:

- Match the **vessel width in pixels**, not the image size. Resize IDRiD images
  down (or work in patches) so vessel calibre in pixels roughly matches DRIVE's.
- Normalize illumination and colour (CLAHE on green + flat-field) on both, which
  removes much of the camera difference.
- Consider adding **STARE**, **CHASE_DB1**, or **HRF**. HRF in particular is
  high-resolution (3504x2336) and includes DR eyes, a much better match for IDRiD
  than DRIVE alone.

**Recommendation: train on DRIVE + HRF if you can get HRF. DRIVE alone is a
resolution trap.**

Also state plainly in your report: DRIVE has **no lesions annotated and almost no
DR**. It gives you a vessel extractor, nothing more. Its job in your pipeline is
to produce the vessel mask that gets *subtracted* before dark-lesion detection.

---

## Messidor-2 — your external validation set, and nothing else

1,748 images (874 examinations, both eyes per patient), from three French centres.
Resolutions 1440x960, 2240x1488, 2304x1536.

**Treat this as sacred.** Never train on it, never tune a threshold on it, never
look at per-image results until your model is frozen. It is your evidence of
generalization to a population and camera set you never saw. That single
discipline is most of what "clinical validation rigor" means in practice.

**The gotcha everyone hits:** the ADCIS distribution gives you **images, not DR
grades**. The grades come separately — the University of Iowa reference standard,
and the **adjudicated** grades published alongside Krause et al. (2018). Get the
grade CSV before you plan around this dataset, and record *which* reference
standard you used, because they differ and the reported numbers differ with them.

Also note: original **Messidor-1** used a different scale (R0-R3, defined by MA
and haemorrhage counts, plus a separate macular-oedema risk) that does **not** map
cleanly onto ICDR 0-4. Don't mix the two. Messidor-2 with an ICDR-style
adjudicated reference is what you want.

**Published referable-DR results on Messidor-2 to benchmark against** — verify the
exact figures from the papers before putting them on a slide:

| System | Sensitivity | Specificity |
|---|---|---|
| Abramoff et al. 2016 (IDx-DR X2.1) | ~96.8% | ~87.0% |
| Gulshan et al. 2016 (JAMA) — high-specificity point | ~87.0% | ~98.5% |
| Gulshan et al. 2016 — high-sensitivity point | ~96.1% | ~93.9% |

Your targets (>90% sens, >85% spec) sit comfortably *below* these — good news. It
means the bar is achievable and there's a well-documented comparison set. Put your
operating point on the same ROC axes as these published points. **That chart is
the "validation against published benchmarks" deliverable.**

---

## Gap 1 — image quality labels (Module 1 has no ground truth)

None of these four label gradability. Options, best first:

- **DeepDRiD** (ISBI 2020 challenge) — ~2,000 fundus images **with image quality
  scores** covering overall quality, artefacts, clarity, and field definition. The
  natural fit for Module 1 and the one to chase.
- **DRIMDB** — ~216 images labelled good / bad / outlier. Small but free and easy.
- **Bootstrap your own.** Take 300 APTOS images, have your team label them
  gradable / borderline / ungradable against a written rubric, measure inter-rater
  agreement (Cohen's kappa), and report it. This is *more* impressive than using
  someone else's labels, because it demonstrates you understand annotation
  protocol — and kappa between your own annotators is a genuine rigour metric.
- **Synthetic degradation.** Take clean images, apply calibrated Gaussian blur /
  defocus, illumination gradients, and simulated glare at known severities. Gives
  unlimited labelled data with a *known* degradation axis, perfect for showing
  "quality score tracks blur radius monotonically." Use this to *supplement*,
  never to replace, real labels — synthetic blur doesn't look like real defocus.

Do all three: DRIMDB or DeepDRiD for real labels, your own 300 for the rubric,
synthetic for the sensitivity curve.

## Gap 2 — neovascularization (Module 2's PDR detector has no supervision)

No pixel-level NV anywhere in these four. And NV is what defines grade 4, the most
sight-threatening state.

- **FGADR** (Fine-Grained Annotated DR dataset) — ~2,842 images with pixel-level
  masks for six lesion types **including neovascularization and IRMA**. The one
  dataset that plugs both this hole and the IRMA half of the 4-2-1 rule. Requires
  an application/agreement, so start that early if you want it.
- **Weak supervision fallback.** Use APTOS grade-4 images as image-level positives
  for "NV present somewhere" and train a patch classifier with multiple-instance
  learning. Weaker, but honest and reportable.
- **Hand-annotate a small set.** ~50 grade-4 images with rough NV bounding boxes
  gets you a validation set even if not a training set.

**Venous beading** (the second 4-2-1 criterion) is annotated essentially nowhere.
You can derive it geometrically from your vessel segmentation — measure calibre
variance along each venous segment — but you'll have no ground truth. State that
as a known limitation and report it as an unvalidated feature. That kind of
explicit honesty scores well.

---

# The split protocol I would commit to

Write this down before you train anything, and don't deviate:

```
GRADING (Module 3)
  Train         : APTOS 3,662  ->  70% stratified by grade
  Validation    : APTOS         ->  15%   (model selection, ROC threshold picked HERE)
  Internal test : APTOS         ->  15%
  External #1   : IDRiD-B 516      (different city, camera)      <- touch once
  External #2   : Messidor-2 1,748 (different country)           <- touch once, at the very end

LESIONS (Module 2)
  Train : IDRiD-A 54 images, patch-based
  Test  : IDRiD-A 27 images
  Extra : e-ophtha (MA + EX only) if you want more MA data

VESSELS (Module 2)
  Train : DRIVE 20 (+ HRF / CHASE_DB1 if obtainable)
  Test  : DRIVE 20, compare to 2nd observer

QUALITY (Module 1)
  Train : DRIMDB / DeepDRiD + your own 300 labelled APTOS
  Test  : held out, plus synthetic degradation sweep
```

Two rules that matter more than the split itself:

1. **Split by patient, not by image.** Messidor-2 has both eyes per patient; if
   left and right eye land on opposite sides of the split, you leak. APTOS
   filenames don't expose patient identity, so you can't do this there — mention
   the limitation.
2. **Pick your operating threshold on the validation set, then freeze it.**
   Reporting sensitivity/specificity at a threshold chosen on the test set is the
   most common accidental cheat in this field and a knowledgeable judge will ask.

---

# Practical ingestion notes

**Storage/size:** APTOS ~10 GB, Messidor-2 several GB, IDRiD a few GB (those
4288x2848 JPEGs are big), DRIVE ~30 MB.

**Don't decode 4288x2848 JPEGs repeatedly in your training loop.** Preprocess
once — FOV-crop, radius-normalize, resize to your working resolutions — and cache
to disk. Keep **two** cached versions:

- a low-res one (e.g. 512x512) for the whole-image CNN
- a high-res or patch-tiled one for lesion detection

That two-resolution cache is the concrete expression of the "sub-pixel MA"
architectural point.

**In MATLAB:**

| Need | Tool |
|---|---|
| Image loading + per-image preprocessing | `imageDatastore` with a custom `ReadFcn` |
| Segmentation masks (IDRiD, DRIVE) | `pixelLabelDatastore` |
| Pairing images with masks | `combine` |
| Patch-based segmentation training | `randomPatchExtractionDatastore` |
| Augmentation | `transform` / `augmentedImageDatastore` |
| Labels from CSV | `readtable` |
| Stratified splits | `splitEachLabel` |

**Consistency check to run on day one:** load 20 images from each of the four
datasets, apply your preprocessing, and view them in a grid. If APTOS and IDRiD
images don't look comparable in colour, brightness, and retinal radius after
preprocessing, your cross-dataset generalization is dead before you start. Fix
preprocessing until they do.

---

## Toolboxes used

Image Processing Toolbox · Computer Vision Toolbox · Deep Learning Toolbox ·
Medical Imaging Toolbox · Simulink + SimEvents · Statistics and Machine Learning
Toolbox · MATLAB Report Generator

# Module 2 — Measured Results

What actually works, measured on APTOS (Ryzen 5 7535U).

Component detail: [Vessels](Module2_Vessel_Segmentation.md) ·
[OD](Module2_OD_Localization.md) · [Fovea](Module2_Fovea_Localization.md) ·
[Microaneurysms](Module2_Microaneurysms.md) · [Exudates](Module2_Exudates.md) ·
[Haemorrhages/NV/Quadrants](Module2_Haemorrhages_NV_Quadrants.md) ·
[All algorithms](Module2_Algorithms.md) ·
**[CSV schema](Module2_CSV_Schema.md)**

---

---

## ⚠ READ THIS FIRST — the numbers below are a SHARP-IMAGE result

Every correlation in this document was measured on the **14 sharpest images per
grade** (top `varLapNorm`). Re-running the identical pipeline on a **random**
gate-passed sample collapses it, and in two cases reverses the sign:

| Feature | sharpest-14/grade | random sample | change |
|---|---|---|---|
| `q_max` (quadrant max) | **+0.594** | **−0.139** | **sign flip** |
| `q_min` (gates the 4-2-1 rule) | **+0.451** | **−0.325** | **sign flip** |
| `hem_n` (classified haemorrhages) | **+0.553** | +0.248 | halved |
| `exu_n` (exudates) | **+0.503** | +0.200 | halved |
| `nv_fine` (neovascularization) | +0.356 | **+0.319** | **holds** |

Median sharpness: random **0.074** vs sharpest-14 **0.177**.

### Confirmed by a direct sweep, not inferred

Three bands of 50 images each, `varLapNorm` terciles taken **within grade** so
the bands are not confounded with severity (severe images are systematically
sharper in APTOS):

| Feature | sharp (0.202) | mid (0.074) | blurry (0.051) |
|---|---|---|---|
| `hem_n` | **+0.455** | −0.038 | +0.300 |
| `q_max` | **+0.528** | −0.064 | +0.211 |
| `q_min` | +0.298 | +0.198 | +0.035 |
| `exu_n` | +0.102 | +0.344 | +0.202 |
| `nv_fine` | +0.338 | **+0.409** | +0.314 |

*(within-stratum rho; n=50 per band, so individual cells are noisy — the
pattern across rows is the signal, not any single number)*

**Three conclusions, and they revise the headline table below:**

1. **The haemorrhage and quadrant features only work on sharp images.** They
   reach +0.45…+0.53 in the sharp band and fall to roughly zero otherwise. On a
   random sample the 4-2-1 rule fires on **4/12 grade-0** images and **7/12
   grade-2** images — it is not usable as written.
2. **The exudate result does not reproduce.** `exu_n` measured +0.503 on the
   sharpest images and **+0.102 to +0.344** everywhere else. Calling it "best in
   Module 2" was premature.
3. **`nv_fine` is the only feature stable across sharpness** (+0.314…+0.409,
   and positive in all four resolution strata). The component labelled "broken"
   for most of this work is the most robust one measured.

**Why this happened.** The sharpest-14 selection was made to give each algorithm
its best chance during development. That is reasonable for *tuning* and invalid
for *reporting* — it is the same class of error as the circular validations
recorded further down this document: the sample was chosen to make the method
look good, then used to measure how good the method is.

**What it means for the pipeline.** Module 1's quality gate passes all of these
images. Module 2 evidently needs **sharper input than the Module 1 gate
demands**. The actionable fix is a second, stricter `varLapNorm` threshold
before the lesion detectors run — accepting an image for storage and accepting
it for lesion counting are different decisions. That threshold has not been
derived yet.

**Status: no Module 2 number should be quoted without its sharpness band.**

---

## MEASURED ON THE CSV — 309 images, all features, one pipeline

Everything above was measured in scratch experiments. This is the **shipped
extractor** run end to end over the 309 images tested during development
(250 sharpness-stratified + the 70 sharpest-per-grade + overlap), merged into
`data/aptos_train_module1_features.csv` → **3,662 rows × 84 columns, 309
filled**.

Median by grade, and within-stratum rho on all filled rows vs only those passing
the new `sharp_ok` gate:

| Feature | g0 | g1 | g2 | g3 | g4 | rho (all) | rho (`sharp_ok`) | monotone |
|---|---|---|---|---|---|---|---|---|
| **`ma_n`** | **0** | 23 | 35 | **106** | 94 | **0.462** | **0.525** | g0→g3 |
| `hem_n` | 63.5 | 68.5 | 73 | 97 | 99 | 0.178 | **0.487** | **yes** |
| `q_max` | 32.5 | 35.5 | 40 | 47 | 49 | 0.100 | **0.491** | **yes** |
| `q_min` | 0 | 2 | 2 | 5 | 4 | 0.213 | 0.304 | g0→g3 |
| **`nv_fine`** | 1.9 | 2.1 | 2.4 | 2.5 | 2.5 | **0.438** | 0.217 | g0→g3 |
| `exu_n` | **59.5** | 12 | 14 | 18 | 13 | 0.150 | 0.267 | **no** |

**The gate is confirmed on data it was not fitted to.** `hem_n` 0.178 → **0.487**
and `q_max` 0.100 → **0.491** — the sharpness cut roughly triples and
quintuples them. And `nv_fine` moves the other way, 0.438 → 0.217, exactly as
the sweep predicted. That opposite movement is the strongest evidence the gate
is real rather than a fitting artefact: a spurious filter would not help four
features and hurt the fifth in the direction predicted in advance.

**`exu_n` is broken, confirmed a fourth time.** Grade 0 has the *highest* median
(59.5 vs 12–18 for every diseased grade). It is detecting something that is more
common in healthy eyes — most likely reflective artefact in the young, glossy
retinas that dominate grade 0. The min-area filter fixed the count and never
fixed the measurement.

**`ma_n` is the single best feature in Module 2.** 0 → 23 → 35 → 106 across
grades 0–3, rho 0.462 ungated and 0.525 gated, and a grade-0 median of exactly
**0**, which is the clinically correct answer. Grade 4 (94) dipping below grade 3
(106) is expected — proliferative eyes are often previously treated, and laser
scars destroy microaneurysms.

### The 4-2-1 rule still is not specific enough

Among `sharp_ok` images:

```
grade 0:  7/45  (16%)      grade 3: 16/24  (67%)   <- should fire
grade 1:  3/35  ( 9%)      grade 4: 14/31  (45%)
grade 2:  9/30  (30%)
```

The gradient is right — 67% at grade 3 against 9–16% at grades 0–1 — but **16%
false-positive on healthy eyes is too high for a severe-NPDR alarm**, and the
30% at grade 2 blurs the boundary the rule exists to draw. `q_min > 3` was
fitted on 70 sharp images; refit it on the full dataset before using it.

### Two columns that are checks, not features

| Column | Reading | Meaning |
|---|---|---|
| `fovea_od_dd` | **100%** inside 2.1–2.9 DD | This is the **search annulus**, so it is the constraint, not a validation. It can only ever be 100%. |
| `fovea_vdens` | non-zero on **1/309** | Now a mislocalisation flag rather than a constant 0.0. It fires on 0.3% of images. |

`ma_count_INVALID` correlates only **0.400** with `ma_n` — the classifier changes
which candidates survive, not merely how many. That is the four-times-proven
rule in one number.

**Cost: 3.53 s/image** → ~3.6 h for the remaining 3,353 images.

---

## THE SHARPNESS GATE — derived, and it is not global

The warning above said Module 2 needs a stricter quality gate than Module 1.
Here it is, derived on **250 images sampled across all 10 sharpness deciles × 5
grades** — not the sharpest-per-grade selection that caused the original problem.

Within-stratum rho computed on the images **above** each cut:

| cut (`varLapNorm`) | pctile | keeps | `hem_n` | `q_min` | `q_max` | `exu_n` | `nv_fine` |
|---|---|---|---|---|---|---|---|
| 0.002 | 0% | 100% | 0.157 | 0.193 | 0.041 | 0.146 | **0.394** |
| 0.035 | 10% | 90% | 0.102 | 0.183 | −0.001 | 0.090 | 0.377 |
| 0.049 | 20% | 80% | 0.115 | 0.142 | 0.062 | 0.015 | 0.326 |
| 0.058 | 30% | 70% | 0.161 | 0.167 | 0.112 | −0.007 | 0.326 |
| 0.069 | 40% | 60% | 0.194 | 0.195 | 0.131 | −0.036 | 0.217 |
| **0.082** | **50%** | **50%** | **0.387** | 0.228 | **0.335** | 0.081 | 0.312 |
| 0.097 | 60% | 40% | 0.437 | 0.254 | 0.404 | 0.013 | 0.262 |
| 0.113 | 70% | 30% | 0.569 | 0.282 | 0.556 | −0.176 | 0.035 |

**`SHARP_MIN = 0.082`** — the median `varLapNorm` of the gate-passed set.

**Why a cut is the right shape of fix.** Between the 40th and 50th percentile
`hem_n` jumps 0.194 → 0.387 and `q_max` 0.131 → 0.335. That is a **step change,
not a gradient** — there is a sharpness below which the dark-lesion detectors
stop working, rather than a smooth degradation. Half the dataset is a real price,
but it buys roughly double the signal, and a stricter cut buys little more.

### The gate is per-feature, and this is the part that matters

| Feature | Effect of the gate |
|---|---|
| `hem_n`, `q_max` | **doubles** the correlation — apply it |
| `q_min` | mild, monotone improvement (0.193 → 0.282) |
| `exu_n` | **no effect at any cut** — ~0 everywhere. Exudates is not a sharpness problem |
| `nv_fine` | **actively harmed**: 0.394 on all images → 0.035 above the 70th percentile |

So there is no single "Module 2 quality threshold". Gating `nv_fine` on sharpness
**throws away its signal**, and gating `exu_n` buys nothing. `sharp_ok` is
written to the CSV as a flag, deliberately **not** applied as a filter, so each
feature can be used on the population it actually works on.

**`exu_n` should now be considered not working.** It measured +0.503 on the
sharpest images, +0.200 on a random sample, and **−0.036…+0.146 at every cut
here**. Three independent samples, one of them favourable. The min-area filter
fixed the *count* (1,244–2,279 → 1.5–47 specks) without fixing the *correlation*.

**Caveat that applies to this table too.** The cut was chosen on the same 250
images used to measure the rho values above it. The step change is structural
enough to be convincing, but the exact figure 0.387 is optimistic; refit on the
full 3,662 before quoting it.

## THE ANSWER — best algorithm per category, all 8 tested

*Measured on the sharpest 14 images/grade — see the warning above; these are upper bounds, not expected performance.*

| # | Component | Best algorithm | Measured | Verdict |
|---|---|---|---|---|
| 1 | **Vessels** | line detector L=21/W=21 → 11% coverage → length filter 40 → **gap bridging** | 80.7% in one tree, 8 comps, ~400 ms | **works** |
| 2 | **Optic disc** | disc-sized mean on **RAW green**, r ≤ 0.60 R | bright 3.02, median 0.445 R, 27 ms | **works**, ~10% hidden failures |
| 3 | **Fovea** | centre-surround darkness **− 3.0 × vessel density**, annulus 2.1–2.9 DD | median 2.58 DD, vd 3.8% vs 14.5% | **partial**, ~20% hidden failures |
| 4 | **Microaneurysms** | closing L=15 → **candidate classifier @ 0.7** | AUC 0.729; within-stratum rho **+0.508** on 250 sharpness-stratified images | **works** — now the best-evidenced lesion feature |
| 5 | **Exudates** | OD mask → dynamic threshold → **minimum-area filter 8 px** | +0.503 sharp, **+0.10…+0.34 otherwise** | **partial** — does not reproduce off-sample |
| 6 | **Haemorrhages** | scale-matched SE L=41 → **shape-only candidate classifier**, threshold 0.8 | candidate AUC **0.827**; +0.553 sharp, **+0.25 random** | **sharp images only** |
| 7 | **Neovascularization** | **fine-scale vessel excess** (fine response minus dilated coarse response) | **+0.31…+0.41 at every sharpness**, same sign in 4/4 strata | **most robust feature in Module 2** |
| 8 | **4-2-1 quadrants** | OD–fovea axis on **classified** haemorrhages, threshold recalibrated to >3 | sharp: 93% spec / 64% sens. **Random: fires 4/12 at grade 0** | **sharp images only** |

**On sharp images: 5 work, 2 partial, 1 broken. On a random sample: 1 holds.**

The pipeline stages (vessels, optic disc, fovea) are geometric and were never
sharpness-gated, so they are unaffected. It is the four *lesion* measures that
degrade.

### The rule, proven four times

Every component that **stops at the threshold stage** fails. Every one that adds
**per-candidate features + a classifier** works.

| Component | Threshold only | + candidate filter / classifier |
|---|---|---|
| Microaneurysms | rho **−0.117** | rho **+0.09…+0.87** |
| Exudates | rho **−0.196**, 1,244–2,279 specks/image | rho **+0.503**, 1.5–47/image |
| Haemorrhages | rho **0.036**, 80 lesions on a *normal* retina | rho **+0.553**, 0 → 80 across grades |
| 4-2-1 quadrants | fired **2/70**, wrong images | fires **0** below grade 3, **7/28** at grades 3–4 |

The haemorrhage classifier keeps **39%** of candidates and is what turns "80
dark specks" into "6.5 lesions on a normal eye, 64 on a severe one".

The classical pipeline is **five** steps: preprocess → subtract vessels →
threshold → **per-candidate features** → **classifier**. Steps 4–5 are not
polish. They are the difference between a pile of specks and a lesion count.

### Two mechanism fixes worth carrying forward

**Scale-matched structuring elements.** Closing fills a structure only if the
line SE *bridges* it. L=15 fills lesions up to ~15 px, so a 30 px haemorrhage
survives closing and never enters the difference image at all. One SE cannot
serve both an 8 px microaneurysm and a 30 px haemorrhage — use L=15 and L=41.

**Minimum-area filtering.** A single 8 px area floor took exudate counts from
1,244–2,279 per image down to 1.5–47, and the grade correlation from −0.196 to
**+0.503**. Nothing else changed.

**Recalibrate clinical thresholds to the detector, not to the textbook.** The
4-2-1 rule says *>20 haemorrhages in each of four quadrants*. At **>20** it fired
on **0/70** images — including every grade-3 eye. At **>5** it fires on 0/42 at
grades 0–2 and 7/28 at grades 3–4. The number 20 assumes a human counting on a
dilated 7-field exam; a detector on a single 45° field sees a different sample,
so the constant has to be re-derived rather than copied.

**A sign flip between pooled and within-stratum rho is a confound signature, not
a discovery.** `nv_fine` measures pooled **−0.163** and within **+0.356**. The
per-stratum breakdown settles which is real — it is positive in **all four**
strata (+0.136, +0.319, +0.367, +0.604), so the pooled negative is Simpson's
reversal driven by image resolution. The same table would have exposed a feature
that flipped sign *between* strata as noise. Always print the per-stratum
medians before believing a mean rank correlation.

### The confound bites every single component

Pooled correlations disagree with within-stratum ones throughout, and sometimes
reverse sign:

| Feature | pooled rho | within-strata rho |
|---|---|---|
| `exu_n_tophat` | −0.528 | −0.091 |
| `ma_n` | 0.028 | **+0.395** |
| `nv_mean` | +0.092 | **−0.334** |

**Never quote a pooled correlation for this dataset.** Resolution predicts
referable DR at 82.3%, so a pooled number is mostly measuring which camera took
the picture.

### The three things that mattered most

**Length filtering + gap bridging** (vessels). Length filter took components
92 → 30; bridging then took 18 → **8** and largest-component share 72.4% →
**80.7%**. Neither is a filter change — both are post-processing.

**Search-region priors** (OD, fovea). Constraining the OD search from 0.80 R to
0.60 R moved the median from 0.546 R to 0.445 R with **no detector change at
all** — more than any refinement achieved. But priors *hide* failures as well as
fix them; see the confidence column.

**The avascularity penalty** (fovea). Vessel density at the found spot: **3.0%
with** the penalty, **16.8% without** — a 5.6× difference. Without it the
detector lands on vessels, because vessels are the darkest thing in the retina.

### Channel discipline — measured, and easy to get wrong

| Component | Channel | Why |
|---|---|---|
| Vessels | **shade-corrected green** | vessels are 3–10 px, far below the 60 px background window |
| **Optic disc** | **RAW green** | the OD is 124 px — comparable to the window, so shade correction *divides it out* |
| Fovea | shade-corrected green | centre-surround handles the residual field |

Measured: running OD detection on shade-corrected green drops `od_bright` from
**2.99 → 1.87** on every image, and moved one detection **465 px**.

> **Read this first.** Unlike [Module 1](Module1_Results.md), which was measured
> on all 3,662 images against real grade labels, **Module 2 has no ground truth
> at all.** APTOS carries no lesion masks, no vessel masks and no OD/fovea
> coordinates. Every number below is *physical plausibility* or *inter-method
> consensus* — never a measured sensitivity.

---

## Status — all 8 components built and tested

| # | Component | Type | Status |
|---|---|---|---|
| 1 | **Vessels** | segmentation | **works** — 896 evaluations + functional tests |
| 2 | **Optic disc** | localization | **works** — 2 rounds, 60 images, 7 methods |
| 3 | **Fovea** | localization | **partial** — 2 rounds, 40 images, ~20% hidden failures |
| 4 | **Microaneurysms** | detection | **partial** — classifier fixes the sign, grade 0 vs 1+ still chance |
| 5 | **Exudates** | segmentation | **partial** — +0.503 sharp, +0.10…+0.34 off-sample |
| 6 | **Haemorrhages** | segmentation | **sharp images only** — +0.553 sharp, +0.248 random |
| 7 | **Neovascularization** | detection | **most robust** — +0.31…+0.41 at every sharpness; still unvalidatable on APTOS |
| 8 | **Quadrants / 4-2-1** | geometry | **sharp images only** — reverses sign on a random sample |

**Nothing in Module 2 is production-ready.** Vessels, optic disc, exudates,
haemorrhages and the 4-2-1 quadrant rule have chosen algorithms with plausible
numbers and unmeasured true error rates. Fovea, microaneurysms and
neovascularization carry real but weak signal.

The two features with the best evidence behind them are **`ma_n` (+0.508)** and
**`nv_fine` (+0.394)**, because both were measured on a sharpness-stratified
sample rather than a favourable one. `hem_n` and `q_max` reach +0.39/+0.34 once
the sharpness gate is applied. **`exu_n` does not work** — it has now failed on
three samples.

Note `ma_n` and `nv_fine` want *opposite* populations: `ma_n` improves with
sharpness, `nv_fine` degrades. Module 3 should consume them with their own
masks, not a single filtered table.

**And no component has been measured against ground truth**, because APTOS has
none. Every number is a correlation with DR grade — a proxy, not an accuracy.

### Fix order

```
6 haemorrhages  ->  DONE.  Candidate classifier @0.8: rho 0.036 -> +0.553.
8 quadrants     ->  DONE.  Unblocked by 6, threshold recalibrated 20 -> 3.
                    But it REVERSES SIGN on a random sample -- sharp images only.
5 exudates      ->  DONE.  Min-area filter: rho -0.196 -> +0.503.
7 NV            ->  Fine-scale excess, rho +0.31..+0.41 at EVERY sharpness --
                    the only stable feature in the module.  Still cannot be
                    validated on APTOS: no NV annotations exist.

NEXT, and it outranks everything above:
  Derive a STRICTER varLapNorm gate for the lesion detectors.  Module 1's gate
  passes images on which haemorrhage and quadrant features reverse sign.  Two
  thresholds are needed: one to accept an image, a higher one to count lesions
  on it.  Everything in this document is an upper bound until that exists.
4 microaneurysms->  per-camera normalisation + labels that include mild cases
7 neovascular   ->  DEFER: no NV annotations exist in APTOS, so a working
                    detector still could not be measured
```

---

## The scale table — everything downstream depends on it

`normalizeFundus` fixes the retinal radius at R = 436, so the optic disc is a
constant 124 px. A standard disc is 1.85 mm:

```
1.85 mm / 124 px  =  14.9 um per pixel
```

| Structure | Clinical size | px at R=436 |
|---|---|---|
| Optic disc diameter | 1.85 mm | **124** |
| **MA / haemorrhage split** | **125 um** | **8.4** |
| Vessel width band | 40–150 um | **2.7–10.1** |
| OD → fovea | 2.5 disc diameters | **310** (= 0.71 R) |
| DME danger zone | 500 um | 34 |

Every ICDR rule is stated in microns; without this scale none is implementable.
This is the payoff from removing APTOS's 8.7× radius spread in [A] — and
**ignoring it caused the largest error in Module 2 so far** (see vessels).

---

## 1. Vessels

**896 evaluations** — 32 images × 7 filters × 4 post-processes, coverage
calibrated to 11% for every config so **topology discriminates**.

| Config | ms | cov % | comps | largest % | width | frag | coh | Verdict |
|---|---|---|---|---|---|---|---|---|
| **line L21 + len40** | **372** | 9.8 | **18** | **72.4** | 4.0 | **2.34** | 0.662 | **best** |
| line L21 + len25 | 372 | 10.0 | 28 | 69.9 | 4.0 | 3.43 | 0.653 | |
| line L15 + len40 | 366 | 8.9 | 24 | 57.2 | 4.0 | 2.91 | 0.665 | |
| frangi wide + len40 | 1350 | 9.1 | 20 | 47.0 | 4.5 | 3.47 | 0.654 | |
| frangi narrow + len40 | 1120 | 9.2 | 23 | 44.2 | 4.5 | 3.58 | 0.672 | **most stable** |
| line L11 + len40 | **54** | 8.2 | 25 | 43.4 | 4.0 | 3.87 | 0.687 | 7× faster, −29pp |
| matched + len40 | 686 | 8.6 | 27 | 41.7 | 4.0 | 4.04 | 0.689 | |
| morpho + len40 | 55 | **5.4** ✗ | 22 | 30.1 | 4.0 | 6.34 | **0.721** | **rejected** |
| *target* | | *8–15* | *low* | *high* | *2.7–10.1* | *low* | *high* | |

**Winner: line detector L=21 + length filter 40.** Best on every structural
metric, 3.6× faster than Frangi.

### Four findings worth carrying forward

**The top eight configs are all line detector.** Best Frangi ranks ninth.

**`len40` is best for all seven filters — no exceptions.** Length filtering is
the highest-value single step: it drops components whose *skeleton* is short, and
a 200-px blob and a 200-px vessel have identical area but very different length.

**Scale selection beats thresholding.** Adding a σ = 1.2 px scale to the Frangi
bank took branchpoints from **195 → 2,539** at the same coverage. σ = 1.2 px is
18 µm — below the smallest real vessel (40 µm = 2.7 px). It was detecting noise.

**Morphological is eliminated** despite the *best* coherence score — all four
variants failed the coverage filter (5.4–6.8% vs 8–15%). It finds something
linear, just not enough of it.

### Functional validation — 30 best-quality images

| Test | Result |
|---|---|
| **MA-count → grade correlation** | **INCONCLUSIVE** — control −0.117, best config −0.104. All near zero and negative |
| **Stability** (Dice after blur/noise) | **frangi 0.839** > line L21 0.786 > line L15 0.673 |
| **Gap bridging** | largest 62.6% → **81.0%**, but components 14 → 40 |

**Test 1 failed because the probe is broken, not the vessels.** MA count should
*rise* with grade — grade 1 is defined as "microaneurysms only". The counter used
here is the raw candidate stage only; the classical pipeline has a **classifier
step that was skipped**, and the candidate stage is known to yield 100+ per image
at very low precision. **Vessels cannot be functionally validated until MA
detection works.**

**Test 2 is a genuine counterweight to the sweep.** Frangi is the most
reproducible even though its topology is worse. The sweep measured appearance on
one pass; stability measures whether you get the same answer twice — which
matters for a screening system that images the same eye repeatedly.

> **The vessel choice is now a judgement call, not a measurement.** Topology
> favours line L21; stability favours Frangi; the functional tie-breaker could
> not run.

### Rejected

| Method | Why |
|---|---|
| morphological (linear SEs) | 5.4–6.8% coverage — fails the sanity filter |
| matched filter | 41.7% largest at 686 ms — beaten on both axes |
| CLAHE preprocessing | 53.4% vs 52.5% largest — no measurable effect |
| 2-of-3 ensemble vote | landed *between* its members despite low pairwise Dice |
| hysteresis thresholding | all settings overshot coverage and branchpoints |

---

## 2. Optic disc

Search region **r ≤ 0.60 R**, 60 images.

| Method | ms | bright | struct | median dist | agreement | Verdict |
|---|---|---|---|---|---|---|
| **disc-mean on green** | **27** | 3.02 | 2.14 | **0.445 R** | 71.9% | **best** |
| centre-surround green | 54 | 2.85 | 2.11 | 0.520 R | **74.7%** | 2× cost, +2.8pp |
| CS × variance | 108 | 2.81 | 2.35 | 0.528 R | 72.8% | |
| centre-surround red | 53 | 2.38 | 2.02 | 0.599 R | 68.3% | |
| local variance | 26 | 2.33 | 2.07 | 0.707 R | 48.3% | **rejected** |
| template match | 32 | 2.32 | 1.19 | 0.484 R | 41.3% | **rejected** |
| Hough | 62 | 1.53 | 1.37 | 0.495 R | 38.7% | **rejected — 22/60 failures** |
| vessel density | 37 | 0.50 | 0.77 | 0.591 R | 34.4% | **rejected** |

**The anatomical prior did more than any detector refinement.** Constraining the
search from 0.80 R to 0.60 R moved plain brightness from median 0.546 R to
**0.445 R** — into the anatomical range — with no change to the detector.

### Two theories that failed on contact with data

**Local variance was supposed to win.** The OD is where dark vessels cross bright
tissue, so variance should peak there while smooth exudates are rejected. Measured
median: **0.707 R** — more than half its answers anatomically impossible.

**Centre-surround was supposed to fix peripheral failures** by being
illumination-invariant. It was *worse* (43% beyond 0.6 R vs 35% for plain
brightness). The invariance is real but only for **smooth** fields; the actual
corruption is **localised glare**, which raises the core without raising the
annulus.

> **Lesson: state what a measure is invariant *to*, then verify that is what is
> corrupting your data.**

---

## 3. Fovea

40 best-quality images. Full detail in
[Module2_Fovea_Localization.md](Module2_Fovea_Localization.md).

| Variant | med DD | in 2.2–2.8 | at boundary | vd core % |
|---|---|---|---|---|
| absolute darkness, 2.0–3.0 | 2.79 | 38% | **28%** | 3.0 |
| centre-surround, 2.0–3.0 | 2.66 | 35% | 18% | 8.6 |
| **centre-surround, 2.1–2.9** | **2.58** | **48%** | 22% | 3.8 |
| ~~centre-surround, 2.2–2.8~~ | 2.51 | ~~100%~~ | 20% | 3.2 |

**The avascularity penalty is the strongest single result in Module 2.**

| | vessel density at the found spot |
|---|---|
| with penalty | **3.0%** |
| without penalty | **16.8%** |

A 5.6× difference. Without it the detector lands squarely on vessels, because
vessels are the darkest structures in the retina. Darkness alone is not enough —
the fovea is dark **and** avascular, and only the second property is unique to it.

**Centre-surround fixed part of the outward bias** — median 2.79 → 2.66, boundary
pileup 28% → 18%. Here the invariance argument *held*, because peripheral
darkening genuinely is a smooth field. Contrast the optic disc, where the same
construction failed because localised glare does not cancel.

> **Ignore the 100% row.** The search region *is* 2.2–2.8, so every answer
> necessarily falls inside it. The automatic ranking picked it as best and was
> wrong. **A constraint is not a result.**

---

## Ranking

| # | Algorithm | Component | Reason |
|---|---|---|---|
| 1 | **Line detector L=21 + len40** | vessels | best on every structural metric across 896 evaluations, 372 ms |
| 2 | **Disc-mean on green, r ≤ 0.6 R** | optic disc | 27 ms, never fails, best physiology |
| 3 | **Length filtering (len40)** | post-process | best for all 7 filters, no exceptions; the highest-value single step |
| 4 | **Length-without-thinning** | implementation | `L ≈ area / (4·mean(EDT))` — 160× faster than Zhang-Suen, made the functional test runnable |
| 5 | Frangi narrow + len40 | vessels | fallback — one `fibermetric` call, and **more stable** (0.839 vs 0.786) |

## Rejected outright

Hough circles (22/60 failures) · local variance for OD (0.707 R median) ·
vessel density for OD (34.4% agreement) · morphological vessels (2,953
branchpoints) · CLAHE before vesselness (no effect) · hysteresis thresholding ·
2-of-3 ensemble voting

---

## Metrics that turned out to be broken

Three measurement errors were made and corrected during this work. All three are
the same failure: **a metric confounded by something other than what it claims to
measure.**

| Metric | Problem | Status |
|---|---|---|
| **coverage %** (round 1) | thresholded at the 88th percentile, which *forces* 12% coverage, then "validated" that coverage was 11% — circular | **fixed** — Otsu or stated calibration |
| **fovea "100% in range"** | the search annulus *was* 2.2–2.8, so every answer fell inside 2.2–2.8. The auto-ranker declared it best | **caught** — use 2.1–2.9 and read 48% |
| **branchpoints** (1st) | counted on the *unthinned* mask when `cv2.ximgproc` was absent, so interior pixels counted as branches — 58,360 of them | fixed — Zhang-Suen thinning added |
| **branchpoints** (2nd) | even thinned, a ragged mask edge produces skeleton *spurs*, each a false branchpoint — 2,500–3,400 vs a 200–600 target | spur removal added |
| **branchpoints** (3rd) | **with 5 spur iterations: still 1,706–3,258.** Not enough for masks this ragged | **ABANDONED** |

**Branchpoints survived three repair attempts. I have stopped trying.** Coverage,
component count, largest-component share and fragmentation are sufficient and
unconfounded — ignore every branchpoint column.

A fourth error, caught before it produced numbers: **`s.cov` on a pandas Series
returns the `.cov()` method**, not the column named `cov`. The round-5 report
crashed rather than printing wrong values, but the same collision silently
returns a method for `.mean`, `.max`, `.count` and others. Use `s["cov"]`.

This is the same class of error as `circularity` in [Module 1](Module1_Results.md)
— `4πA/P²` collapsed because boundary raggedness inflated the perimeter, and it
was replaced by `residual`.

---

## The honest limitation

**No ground truth exists for any of this.**

For the optic disc: p90 of the distance-from-centre pins at exactly the search
boundary for every method, meaning at least 10% of estimates are being *clipped*
rather than converging. The anatomical prior is not fixing those failures — it is
hiding them. 74.7% consensus could mean "three-quarters correct" or
"three-quarters wrong in the same way".

For vessels: 9.3% coverage in one dominant tree is *consistent with* a correct
segmentation. It does not prove one. The mask could be systematically missing
every small vessel and still score well on all four checks.

Two small downloads would convert all of the above from plausibility into
measured accuracy:

| Dataset | Size | Gives |
|---|---|---|
| **DRIVE** | **30 MB** | 40 images, pixel-level vessel masks, **two independent human observers** |
| **IDRiD sub-challenge C** | ~2–3 GB | **516 OD + fovea coordinates**, Indian data (Nanded) |

Until then, treat both components as **built but unvalidated**, and propagate
that uncertainty downstream — fovea, exudate masking and the 4-2-1 quadrant
orientation all inherit it.

---

## What APTOS *can* still validate

The grade column is a real label, and each detector makes a testable prediction:

| Detector | Prediction |
|---|---|
| Microaneurysms | grade 1 is *defined* as "MAs only" — count must separate 0 from 1+ |
| Haemorrhages | count rises monotonically with grade |
| Exudates | area correlates with grade ≥ 2 |
| Vessels | removing them should **improve** the dark-lesion → grade correlation |

**Measured within resolution strata**, or it re-measures the 82.3% acquisition
confound rather than the detector. This validates *"detects something
disease-related"*, not pixel-level sensitivity — weaker, but honest.

---

## Next

Fovea localization. It needs the vessel map (for the avascularity test and the
arcade axis) and the OD position, so it is the natural next component now that
both exist.

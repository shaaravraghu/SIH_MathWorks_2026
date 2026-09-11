# Module 2, Steps 6–8 — Haemorrhages, Neovascularization, 4-2-1 Quadrants

**Status: 6 and 8 WORK; 7 is partial.** The history below is kept so the failure
modes are recorded rather than rediscovered — skip to
[THE FIXES](#the-fixes--attempted-and-what-happened) for the final algorithms.

These three are grouped because they run as a chain: the 4-2-1 rule needs
haemorrhage counts per quadrant, so 8 could not work until 6 did.

| # | Final state | Sharpest-14/grade | Random sample |
|---|---|---|---|
| 6 Haemorrhages | **sharp images only** | +0.553 | +0.248 |
| 7 Neovascularization | **most robust in Module 2** | +0.356 | **+0.319** |
| 8 4-2-1 quadrants | **sharp images only** | `q_max` +0.594 | **−0.139** |

⚠ **The headline numbers are a sharp-image result.** See
[Module2_Results.md](Module2_Results.md) — on a random gate-passed sample the
quadrant features reverse sign and the 4-2-1 rule fires on 4/12 grade-0 images.
The irony is that component 7, labelled broken for most of this work, is the
only one that survives.

---

## 6. Haemorrhages

### What they are

Dark red, larger and more irregular than microaneurysms. **The size split is the
125 µm / 8.4 px line** from the scale table.

| Subtype | Appearance | Grading weight |
|---|---|---|
| **Dot / blot** | round, well-defined, deep | count per quadrant drives the 4-2-1 rule |
| **Flame / splinter** | feathery, spreads along nerve fibres | often hypertensive rather than diabetic |
| **Preretinal / vitreous** | large, may show a fluid level | **means grade 4** |

### The algorithm

Reuse the [microaneurysm](Module2_Microaneurysms.md) dark-lesion stage — green,
vessel subtraction, multi-orientation closing, threshold — then split:

```
area <= 55 px  (125 um diameter)  ->  microaneurysm
area >  55 px                     ->  haemorrhage
```

Subtype from shape:

```
ecc > 0.90  AND  solidity < 0.55   ->  flame
otherwise                          ->  dot/blot
```

The discriminator worth building is **alignment with the local vessel
direction** — flame haemorrhages spread along the nerve fibre layer, so they
align with it, and the vessel map already supplies that orientation. Not
implemented.

### Measured — and it does not work

| Feature | g0 | g1 | g2 | g3 | g4 | pooled | within-strata |
|---|---|---|---|---|---|---|---|
| `hem_total` | **0** | **0** | **0** | **0** | **0** | 0.382 | 0.444 |
| `hem_dot` | 0 | 0 | 0 | 0 | 0 | 0.382 | 0.444 |
| `hem_flame` | 0 | 0 | 0 | 0 | 0 | — | — |
| `ma_n` (below the split) | 113 | 66 | 25 | 104 | 84 | 0.028 | 0.395 |

**Median haemorrhage count is zero at every grade**, including grade 4. The
within-stratum ρ of 0.444 is driven by a handful of non-zero images and is not
meaningful when the median is zero everywhere.

**Diagnosis:** the p99 threshold on the dark-lesion difference selects small
isolated specks. Essentially every detected object falls *below* the 55 px
split, so `ma_n` absorbs everything and the haemorrhage bin stays empty. A real
blot haemorrhage is 8–34 px across (≈50–900 px area) but is not surviving as a
single connected region at that threshold.

**What would fix it:** haemorrhages need their **own** threshold and a region-
growing step, not the MA threshold. They are larger and lower-contrast at the
edges; a cut tuned for 3-px blobs fragments them.

---

## 7. Neovascularization

### What it is

New, fragile vessels growing in response to ischaemia. **This defines grade 4**
and is the sight-threatening endpoint.

| | Location |
|---|---|
| **NVD** | at or within 1 DD of the optic disc |
| **NVE** | elsewhere |

Distinguished from normal vessels by: fine calibre, high tortuosity, convoluted
loops, irregular branching that ignores the normal arcade pattern, and
abnormally high local vessel density.

### The algorithm

```
1. vessel map (from component 1)
2. slide a 1 DD window (124 px)
3. per window: density, branchpoints, endpoints, tortuosity
               (arc length / chord length), calibre variance,
               fractal dimension, orientation entropy
4. classify each window
5. NVD if within 1 DD of the OD, else NVE
```

### Measured — broken

| Feature | g0 | g1 | g2 | g3 | g4 | pooled | within-strata |
|---|---|---|---|---|---|---|---|
| `nvd` | 0 | 0 | 0 | 0 | 0 | 0.122 | **−0.280** |
| `nve` | 0 | 0 | 0 | 0 | 0 | 0.280 | 0.052 |
| `nv_mean` | 0 | 0 | 0 | 0 | 0 | 0.092 | **−0.334** |

All medians zero, correlations incoherent and partly **negative** — NV should
fire on grade 4, not anti-correlate with grade.

**Diagnosis:** the tortuosity proxy (`skeleton length / area` per component,
smoothed) collapses to ~0 almost everywhere. It is not measuring tortuosity.

### This component is unvalidatable on APTOS regardless

There are **no neovascularization annotations anywhere in APTOS**, and only
~295 grade-4 images in the whole training set. Even a working detector could not
be measured. **FGADR** provides pixel-level NV and IRMA masks and is the only
route to a real number.

---

## 8. Quadrants and the 4-2-1 rule

### The clinical rule

Severe NPDR (**grade 3**) if **any** of:

- \> 20 intraretinal haemorrhages in **each of 4** quadrants, **or**
- definite venous beading in **2**+ quadrants, **or**
- prominent IRMA in **1**+ quadrant

**Spatial and quantitative** — it needs per-quadrant counts, correctly oriented.

### Quadrant orientation

```matlab
axis = atan2(fovea_y - od_y, fovea_x - od_x);   % OD -> fovea
ang  = mod(atan2(yy-od_y, xx-od_x) - axis, 2*pi);
quad = floor(ang / (pi/2)) + 1;                 % 1..4
```

Anchored to the **OD–fovea axis** (superior/inferior × temporal/nasal), *not*
frame axes. [B]'s `splitRegions` uses frame axes only because it runs before any
anatomy is known.

### Measured — blocked upstream

```
images flagged by the rule: 0 / 60

grade 0: 0/12   median q_min = 0
grade 1: 0/12   median q_min = 0
grade 2: 0/12   median q_min = 0
grade 3: 0/12   median q_min = 0     <- should fire here
grade 4: 0/12   median q_min = 0
```

**The rule fired on nothing.** It requires >20 haemorrhages in the *weakest*
quadrant, and haemorrhage detection returns ~0 per image. `q_min` — the weakest
quadrant, which gates the rule — is 0 at every grade.

This is not a defect in the quadrant code. **It is entirely blocked by component
6.** The geometry is correct and cheap; it has nothing to count.

### Two of the three criteria have no ground truth anywhere

**Venous beading** (calibre variance along venous segments) and **IRMA** are
annotated in essentially no public dataset. FGADR has IRMA. Beading can be
derived geometrically from the vessel map, but with nothing to validate against.

So even a working haemorrhage counter reconstructs only **one of three**
pathways to grade 3.

---

---

## THE FIXES — attempted, and what happened

### 6. Haemorrhages — FIXED, in two stages

**Stage 1: scale-matched structuring elements.** Morphological closing fills a
structure only if the line SE **bridges** it. An L=15 line fills lesions up to
~15 px, so a 30 px haemorrhage *survives* closing and never appears in the
difference image at all.

```
microaneurysms   L=15,  threshold p99,  area   3-55 px
haemorrhages     L=41,  threshold p96,  area  55-908 px   + binary closing
```

This made it **detect** — median count 0 → 79–118 — but not discriminate:

| Feature | g0 | g1 | g2 | g3 | g4 | within |
|---|---|---|---|---|---|---|
| `hem_total` | 79.5 | 98.5 | 71.5 | 98.0 | 118.0 | **0.036** |
| `hem_flame` | 32.5 | 45.0 | 37.0 | 38.0 | 52.0 | **−0.111** |

**79 haemorrhages on a grade-0 retina is nonsense** — a no-DR eye has zero. The
detector was finding dark *texture*.

**Stage 2: the candidate classifier.** The same step that fixed microaneurysms
and exudates. Twelve per-candidate features, **no absolute intensity** (that is
what let the microaneurysm classifier learn camera identity in round 1 and
report a false AUC of 0.995):

```
shape       area, perim, circularity, eccentricity, solidity, aspect
contrast    local contrast (core vs 12-24 px ring), diff_rel
colour      rg = mean(R)/mean(G) over the candidate   <- RATIO, never a level
context     vdist (distance to nearest vessel), vdens, rad (eccentricity in FOV)
```

RandomForest, 300 trees, `min_samples_leaf=5`, weak labels **grade 0 vs grades
3–4**, `GroupKFold(5)` by image so no image ever scores itself.

**Measured on 70 images / 6,836 candidates — candidate AUC 0.827**, at
probability threshold **0.5**:

| | g0 | g1 | g2 | g3 | g4 | pooled | within |
|---|---|---|---|---|---|---|---|
| raw count | 80 | 98 | 72 | 98 | 118 | — | 0.036 |
| classified @ 0.5 | 6.5 | 31.5 | 18 | 64 | 49 | 0.545 | +0.427 |

Top features: `diff_rel` 0.369, `contrast` 0.123, `rg` 0.123, `rad` 0.087 — all
relative quantities, which is what the ban on absolute intensity was for.

#### The deployed threshold is 0.8, not 0.5

A forest fitted on **every** candidate memorises its training images. Deployed
at 0.5 it kept ~100% of candidates on unseen images and fired the 4-2-1 rule on
a **grade-0 retina**. The weak-label set is 70.7% positive, so 0.5 sits on the
wrong side of a skewed posterior.

| threshold | keeps | g0 | g1 | g2 | g3 | g4 | within |
|---|---|---|---|---|---|---|---|
| 0.5 | 75% | 6.5 | 89.0 | 49.5 | 98.0 | 117.0 | +0.343 |
| 0.6 | 68% | 3.0 | 79.0 | 46.5 | 96.0 | 116.5 | +0.441 |
| 0.7 | 60% | 1.0 | 68.5 | 28.0 | 93.0 | 102.5 | +0.517 |
| **0.8** | **49%** | **0.0** | **46.5** | **23.5** | **80.5** | **76.0** | **+0.553** |

**0.8 was chosen because the grade-0 median reaches zero** — a no-DR eye has no
haemorrhages — **not** because it maximises rho. It does also maximise rho over
the 20 configurations swept, which is exactly why that cannot be the stated
reason: selecting a configuration by a metric and then reporting that metric is
the circular validation recorded elsewhere in these docs. **+0.553 is a selected
maximum and is optimistic; +0.427 is the pre-selection number.**

Grades 1 and 2 are never used for training (weak labels are grade 0 vs grades
3–4), so their counts are a genuine held-out check — and they land between the
two trained classes at every threshold.

**Alternative front end tested and rejected.** An h-minima candidate generator
(morphological reconstruction with a raised marker, the dual of the exudate
h-maxima) gave a similar candidate AUC (0.812) but collapsed at image level —
classified medians 4/0/1/0/0, within-stratum rho +0.282 and *pooled* −0.179.
It produced only 3,147 candidates against closing's 6,836 and missed the
low-contrast lesions entirely. **Closing wins.**

### 7. Neovascularization — four alternatives tested, one partial success

Two earlier attempts failed: a skeleton-length tortuosity proxy (collapsed to
~0 everywhere) and vessel density × orientation incoherence (rho −0.307…+0.279,
incoherent). Four genuinely different mechanisms were then tried.

| Idea | Feature | within-stratum rho | Verdict |
|---|---|---|---|
| **Fine-scale excess** — NV vessels are thin, so detect at fine and coarse scale and keep what responds *only* to fine | `nv_fine` | **+0.356** | **best** |
| Branchpoints per unit skeleton length, max over a 1 DD window | `nv_branch_max` | +0.349 | close second |
| Density extreme (p99.5) rather than mean | `nv_dens99` | −0.391 | **wrong sign** |
| Vessel density far from the arcade (>2 DD from the OD) | `nv_far` | +0.210 | weak |

```
fine   = line_detector(green, L=9,  W=11)     # ~9 px vessels
coarse = line_detector(green, L=31, W=31)     # arcade calibre
excess = (fine > p92) AND NOT dilate(coarse > p92, 5x5)
nv_fine = 100 * |excess| / |FOV|
```

**Why the per-stratum table mattered here.** `nv_fine` measures pooled
**−0.163** but within-stratum **+0.356** — a sign flip, which is the acquisition
confound's signature and normally a reason to discard a feature. The breakdown
shows it is genuine:

| stratum | n | g0 | g1 | g2 | g3 | g4 | rho |
|---|---|---|---|---|---|---|---|
| 1050×1050 | 8 | 3.90 | 2.40 | 1.78 | 2.86 | 2.88 | +0.136 |
| 2416×1736 | 20 | — | 2.47 | 3.09 | 2.86 | 3.24 | +0.367 |
| 2588×1958 | 8 | — | 1.98 | 2.64 | 2.23 | 2.37 | +0.319 |
| 3388×2588 | 13 | — | 2.15 | 2.36 | 2.72 | 3.13 | **+0.604** |

Positive in **all four** strata, so the pooled negative is Simpson's reversal.
Compare `nv_branch_max`, which flips to **−0.383** in one stratum — a mean rho
of +0.349 hiding an inconsistency.

**It is not just re-detecting haemorrhages.** A dark-line filter responds to dark
blobs, so `nv_fine` could have been a redundant lesion proxy. Against the
classified haemorrhage count it measures −0.540, −0.515, −0.293, −0.083,
+0.443 across strata — mostly *negative*. It carries independent information.

**Why it is still only partial.** Grade 0 appears in exactly one stratum
(1050×1050, n=8) and `nv_fine` is *highest* there. So the feature separates
grade 1 from grade 4 but there is **no evidence it separates no-DR from DR** —
the distinction that matters most.

**But it is the only feature that survives off-sample.** Across sharpness bands
it measures +0.338 / +0.409 / +0.314 (sharp / mid / blurry) and +0.319 on a
random sample, where `hem_n` halves and the quadrant features reverse sign.
Whatever `nv_fine` is measuring, it is not an artefact of image quality — which
is more than can be said for the components that were declared working.

**And this component remains unvalidatable on APTOS.** There are no
neovascularization annotations anywhere in the dataset and only ~295 grade-4
images. `nv_fine` correlates with grade; whether it detects *neovascularization*
is untested and untestable here. **FGADR** provides pixel-level NV and IRMA
masks and is the only route to a real number.

### 8. The 4-2-1 rule — FIXED by unblocking 6, then recalibrating

With classified haemorrhage centroids assigned to quadrants on the OD–fovea
axis:

Using the **deployed** classifier (threshold 0.8):

| | g0 | g1 | g2 | g3 | g4 | within |
|---|---|---|---|---|---|---|
| `hem_n` total | **0.0** | 46.5 | 23.5 | 80.5 | 76.0 | +0.553 |
| **`q_min`** (gates the rule) | **0.0** | 2.0 | 0.5 | **5.0** | 4.0 | +0.451 |
| `q_max` | 0.0 | 20.0 | 11.5 | 39.5 | 50.0 | **+0.594** |

On this sample `q_max` (+0.594) and `q_min` (+0.451) are the strongest features
in Module 2 — but both **reverse sign on a random sample** (−0.139 and −0.325).
They are the least robust measures in the module, not the best.

**The textbook threshold does not transfer.** The rule as written is *>20
haemorrhages in each of four quadrants*:

```
threshold >20 (as written):   0/14 at every grade, including grade 3
threshold >3  (recalibrated): g0 0/14   g1 2/14   g2 1/14   g3 10/14  g4 8/14
                              -> 93% specificity (grades 0-2)
                                 64% sensitivity (grades 3-4)

full sweep, fires when q_min > T:
   T     g0      g1      g2      g3      g4     spec    sens
   0    0/14   11/14    7/14   13/14   14/14     57%     96%
   2    0/14    4/14    1/14   12/14   10/14     88%     79%
   3    0/14    2/14    1/14   10/14    8/14     93%     64%
   5    0/14    1/14    0/14    6/14    6/14     98%     43%
  20    0/14    0/14    0/14    0/14    0/14    100%      0%

grade 0 fires 0/14 at EVERY threshold, including T=0.
```

Re-derived against the deployed classifier (threshold 0.8), **>3** gives 93%
specificity at grades 0–2 and 64% sensitivity at grades 3–4 — the correct
*shape* for a severe-NPDR flag, which should be a high-precision alarm rather
than a screening test.

**On a random sample it fires on 4/12 grade-0 and 7/12 grade-2 images.** The
operating point above holds only on the sharpest images. `q_min` and `q_max` are
written to the CSV unthresholded so the constant can be refitted without
re-extracting.

The constant 20 assumes a clinician counting on a dilated seven-field
examination. A detector working on a single 45° field sees a different sample of
the retina, so the constant must be **re-derived against the detector**, not
copied from the textbook. This is a calibration to redo on the full 3,662-image
run — 5 is fitted on 70 images.

---

## Summary

| # | Component | State | Key number |
|---|---|---|---|
| 6 | Haemorrhages | **sharp images only** | AUC 0.827; rho **+0.553** sharp, **+0.248** random |
| 7 | Neovascularization | **most robust in Module 2** | `nv_fine` **+0.31…+0.41 at every sharpness** |
| 8 | 4-2-1 quadrants | **sharp images only** | `q_max` +0.594 sharp, **−0.139 random** |

**The rule is now proven four times.** Every component that stops at the
threshold stage fails; every one that adds per-candidate features plus a
classifier works. Microaneurysms −0.117 → +0.87, exudates −0.196 → +0.503,
haemorrhages 0.036 → +0.553, and the 4-2-1 rule went from firing on the wrong
2 images to firing only at grades 3–4.

**Remaining honest caveats:**

- **No ground truth.** Every number here is a correlation with DR grade, not an
  accuracy. APTOS has no lesion annotations.
- **70 images.** All of the above is measured on 14 per grade, chosen as the
  sharpest by `varLapNorm`. The full 3,662-image run is still pending.
- **Grade 0 vs grade 1 is untested for NV** and weak for microaneurysms.
- **Two of the three 4-2-1 criteria are still missing.** Venous beading and IRMA
  are annotated in essentially no public dataset, so even a working haemorrhage
  counter reconstructs only **one of three** pathways to grade 3.

# Work Needed — components 5, 6, 7

**Question:** will feature engineering fix exudates, haemorrhages and
neovascularization?

**Answer:** it is the right fix for **one** of them, a partial fix for another,
and the wrong diagnosis for the third. They look similar — "the detector doesn't
work" — but they fail at three different stages of the pipeline, and a fix aimed
at the wrong stage does nothing.

| # | Component | Failing stage | Will feature engineering help? |
|---|---|---|---|
| 5 | Exudates | **candidate features — absent entirely** | **Yes. Highest priority.** |
| 6 | Haemorrhages | candidate *generation* + label noise | **Partly** — already done once; diminishing returns |
| 7 | Neovascularization | **measurement — no ground truth** | **No.** Not a feature problem |

Related: [Module 2 results](Module2_Results.md) ·
[Module 2 CSV schema](Module2_CSV_Schema.md) ·
[Module 3 grading](Module3_Severity_Grading.md)

---

## The five-step pipeline, and where each component stops

Every working lesion detector in this project follows the same five steps:

```
1 preprocess  ->  2 subtract vessels  ->  3 threshold
                                   ->  4 per-candidate features
                                   ->  5 classifier
```

Steps 4–5 are not polish. **Four times now, a component that stopped at step 3
failed, and adding steps 4–5 fixed it:**

| Component | Threshold only | + features & classifier |
|---|---|---|
| Microaneurysms | ρ −0.117 | ρ **+0.508** |
| Exudates | ρ −0.196 | *(min-area filter only — steps 4–5 never added)* |
| Haemorrhages | ρ 0.036 | ρ **+0.553** |
| 4-2-1 quadrants | fired 2/70, wrong images | fires only at grades 3–4 |

**Exudates is the one component that never got steps 4–5.** That is the whole
answer to the question for component 5.

---

## 5. Exudates — YES, and this is the highest-value work available

### Current state

```
threshold -> 8 px minimum-area filter -> count
```

No per-candidate features. No classifier. It is a **step-3 detector**.

### Why it is worse than "weak" — it is inverted

| | g0 | g1 | g2 | g3 | g4 |
|---|---|---|---|---|---|
| mean `exu_n` | **57.2** | 17.2 | 22.6 | 23.4 | 17.8 |

Healthy eyes get **more** marks than diseased ones. Excess-over-baseline
precision is **negative at every grade**, and **0%** of grade-0 images come back
clean. It has failed on four independent samples.

### The likely mechanism

A dark-adapted young retina — which dominates grade 0 in APTOS — has a strong
**specular reflex**: bright, bluish-white, diffuse patches along the arcades and
over the macula. A brightness threshold cannot tell that from a hard exudate.
Diabetic retinas are older, hazier, and reflect less — so the artefact is
*anti-correlated* with disease, which is exactly the inversion observed.

**This is good news.** The confusion is between two classes that differ in
colour, edge profile and location — all things a per-candidate classifier can
learn. That is precisely what features are for.

### Features to extract per candidate

```
COLOUR  (ratios only -- never absolute intensity, see the ban below)
  b_over_g          reflex is bluish-white, hard exudate is yellow  <- key
  r_over_g
  saturation        exudates are saturated yellow; reflex is desaturated

EDGE
  gradient_mag_rim  hard exudate = sharp border; reflex and cotton-wool = gradual
  edge_sharpness    ratio of rim gradient to interior gradient       <- key
  boundary_smooth   perimeter^2 / area

SHAPE
  area, eccentricity, solidity, circularity
  cluster_n         hard exudates come in rings and clusters

LOCATION
  dist_od_dd        in disc diameters -- catches residual OD leakage
  dist_fovea_dd     doubles as the DME feature we are missing anyway
  vessel_dist       reflex hugs the arcades; exudates need not
  rad               eccentricity within the FOV

CONTEXT
  local_contrast    candidate vs a 12-24 px annulus
  bg_ratio          candidate mean / local background mean
```

The two marked `<- key` are the ones that should separate reflex from exudate on
physics: **blue/green ratio** and **edge sharpness**.

> ⚠ **`bg_ratio` needs a within-stratum check before it is trusted.** In an
> earlier exudate experiment it carried 0.507 importance — the same shape as the
> microaneurysm round-1 failure, where the top features turned out to be camera
> identity. Verify it survives stratification by resolution.

### Expected outcome

The other three components moved from ρ ≈ 0 (or wrong-signed) to ρ 0.5+ with
this exact step. A similar result here is plausible but **not** guaranteed — the
inversion is more severe than what the others started from.

**Success criterion, fixed in advance:** grade-0 median reaches **0** and the
grade ordering becomes monotone. Not "ρ improves" — ρ can improve while the
detector still marks every healthy eye.

---

## 6. Haemorrhages — PARTLY, and more features is not the main lever

### Current state

Already has steps 4–5: 12 per-candidate features, RandomForest at threshold 0.8,
candidate AUC 0.827. **Feature engineering already happened, and it worked** —
ρ 0.036 → 0.553.

### What is still wrong

```
64 haemorrhages on a MEDIAN healthy retina
only 20% of grade-0 images come back clean
proxy precision 24% (g2), 43% (g3), 40% (g4)
```

### Why more features will not fix it

Two ceilings, neither of which is feature-shaped:

**1. Candidate generation.** A classifier can only re-rank what step 3 produced.
`hem_raw` is ~100 candidates on a healthy eye — the threshold is admitting dark
*texture* (choroidal pattern, pigment, shadowing). If real haemorrhages and
texture are not separable at the candidate level, no feature added at step 4
recovers it.

**2. Label noise, and this is the harder one.** The classifier trains on
**image-level weak labels** — every candidate on a grade-3 image is labelled
positive. On an image with 100 candidates of which 30 are real, **70% of the
positive labels are wrong.** Better features cannot fix systematically wrong
labels; they can only fit the noise more confidently.

### What would actually help, in order

| Lever | Why |
|---|---|
| **1. Tighten candidate generation** | percentile is fixed at p96 — sweep it against grade-0 count, not against ρ |
| **2. Enforce `sharp_ok`** | ρ is already 0.487 under the gate vs 0.178 without. The gate is computed and **never applied** |
| **3. Multiple-instance learning** | the honest formulation for image-level labels: a bag is positive if *any* candidate is, which is exactly our situation |
| **4. Real labels (IDRiD)** | 81 images with HE masks ends the label-noise problem outright |
| 5. More features | last, and expect little |

**Note the cheapest item is #2 — it is already computed and simply not used.**

---

## 7. Neovascularization — NO. This is a measurement problem

### Current state

`nv_fine` — fine-scale vessel response minus dilated coarse response.
ρ **+0.438**, stable across every sharpness band (+0.314…+0.409) and positive in
all four resolution strata. **The most robust number in Module 2.**

### Why feature engineering is the wrong tool

We have **no idea whether it detects neovascularization.** It correlates with
*grade*. Grade 4 eyes differ from grade 0 eyes in many ways — more lesions,
older patients, hazier media, more previous treatment. Any of those could drive
ρ 0.438.

Adding features to a detector you cannot measure produces **different numbers
you also cannot measure.** You would not know whether you had improved it.

Worse: the one stratum containing grade-0 images has `nv_fine` **highest** at
grade 0. So there is no evidence it separates no-DR from DR at all — the
distinction that matters most.

### What is actually needed

| Option | Cost | Gives |
|---|---|---|
| **FGADR** — pixel-level NV + IRMA masks | application/agreement, start early | a real number; also unblocks the IRMA arm of 4-2-1 |
| **Hand-annotate ~50 grade-4 images** with rough NV boxes | a day of work | a validation set (not a training set) — enough to know if it works |
| Multiple-instance learning on grade-4 images | moderate | weak but honest and reportable |

**Recommendation: hand-annotate 50 images.** It is the cheapest path to knowing
whether `nv_fine` measures anything real, and it does not require relaxing the
APTOS-only constraint for training — only for validation.

Until then, `nv_fine` should be reported as **an unvalidated feature that
correlates with grade**, never as a neovascularization detector.

---

## The ban that applies to all three

**No absolute-intensity features. Ratios, shapes, gradients and distances only.**

Feeding absolute colour to the microaneurysm classifier produced a false AUC of
**0.995**. Its top features were `r_mean` (0.237) and `b_mean` (0.204) — it had
learned **camera identity**, not disease. Banning absolute intensity dropped it
to an honest 0.742.

The confound is not hypothetical here: Module 2 features already predict image
resolution at **67.8%** accuracy (chance 17%), and resolution alone predicts
referable DR at AUC **0.809**.

**Every new feature must be checked within resolution strata before it is
believed.**

---

## Priority order

| Rank | Work | Effort | Expected gain |
|---|---|---|---|
| **1** | **Enforce `sharp_ok` on the dark-lesion columns** | ~1 hour | `hem_n` ρ 0.178 → 0.487, already measured |
| **2** | **Exudate candidate features + classifier** | ~1 day | the proven fix, never applied here |
| **3** | Finish the Module 2 extraction (3,353 rows) | 3.3 h unattended | removes the grade-balanced sampling bias |
| **4** | Haemorrhage candidate-threshold sweep vs grade-0 count | ~half a day | attacks the real ceiling |
| 5 | Hand-annotate 50 grade-4 images for NV | ~1 day | the only way to know if `nv_fine` is real |
| 6 | MIL formulation for haemorrhages | ~2 days | addresses label noise properly |
| 7 | More haemorrhage features | ~1 day | little — the ceiling is elsewhere |

**Item 1 is free.** The gate is already computed and written to the CSV; it is
simply never applied. That is the single best return in the project right now.

---

## Honest summary

| Claim | Verdict |
|---|---|
| Feature engineering will fix exudates | **Probably** — it is the one untried proven fix, but the inversion is severe |
| Feature engineering will fix haemorrhages | **Partly** — already applied once; the remaining ceiling is candidate generation and label noise |
| Feature engineering will fix NV | **No** — it is unmeasurable, not under-engineered |
| Any of this can be validated on APTOS | **No** — no lesion masks exist. Precision and recall are unmeasurable in principle here |

**The thing to internalise:** three components look identically broken from the
correlation table, and they need three different fixes. Applying "add more
features" to all three would improve one, waste effort on another, and produce
unmeasurable noise on the third.

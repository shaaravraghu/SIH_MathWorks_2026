# Module 3 — DR Severity Grading

Architecture, and what the measured Module 2 data can actually support.

Related: [Module 1 results](Module1_Results.md) ·
[Module 2 results](Module2_Results.md) ·
[Module 2 CSV schema](Module2_CSV_Schema.md) ·
[Techniques & datasets](DR_Pipeline_Techniques_and_Datasets.md)

---

## The question this document answers first

> **Do we grade severity from Module 2 data alone?**

**No.** Two reasons, one architectural and one measured.

**Architecturally**, Module 3 has three branches, and Module-2-only is just one
of them:

| Branch | Input | Property |
|---|---|---|
| (a) End-to-end CNN | the image | strong overall, no interpretability, **weak on grade 1** |
| (b) Lesion-feature classifier | **Module 2 only** | interpretable, maps 1:1 onto ICDR, inherits every Module 2 error |
| (c) **Hybrid fusion** | CNN embedding + lesion vector | the actual contribution |

The ablation table — **CNN / lesions / fused**, with sensitivity, specificity and
kappa — is *literally* the "outperforms any single technique approach" evidence
the problem statement asks for. Grading from Module 2 alone builds branch (b) and
discards the deliverable.

**Measured**, branch (b) does not reach the target on its own. See below.

---

## Branch (b) measured — how far Module 2 actually gets

5-fold CV on the **309 populated rows** of
`data/aptos_train_module1_features.csv`, predicting referable DR (grade ≥ 2).

**Target: ≥90% sensitivity AND ≥85% specificity.**

| Input | AUC | spec @ 90% sens | QWK |
|---|---|---|---|
| Module 2 features only | 0.910 | **75.4%** | 0.764 |
| Module 1 features only | 0.707 | 42.9% | 0.354 |
| Module 1 + Module 2 | 0.915 | 76.2% | 0.781 |

**Module 2 alone reaches 75% specificity against an 85% target.** Module 1's
quality features add almost nothing to *grading* (0.910 → 0.915) — expected, and
not their job. See [Does Module 3 need Module 1?](#does-module-3-need-module-1) for what
they are actually for — including the confidence-widening claim being **disproved**.

Feature importances for branch (b):

```
ma_n           0.174      <- the strongest, as the lesion physics predicts
exu_area       0.087
vessel_frag    0.082
vessel_pct     0.073
nv_fine        0.071
vessel_largest_pct 0.065
nv_fine_max    0.064
hem_n          0.054
```

### The pooled AUC is inflated by the acquisition confound

The same confound documented in [Module 1](Module1_Results.md) reaches Module 3.

```
Module 2 features predict image RESOLUTION:  67.8% accuracy (6 classes, chance 17%)
Resolution ALONE predicts referable DR:      AUC 0.809
```

The feature vector encodes the camera. Computing the same AUC **within**
resolution strata, where the confound cannot help:

| stratum | n | AUC |
|---|---|---|
| 1050×1050 | 44 | 0.932 |
| 2416×1736 | 88 | 0.860 |
| 2588×1958 | 37 | 0.806 |
| **weighted mean** | | **0.867** (vs 0.910 pooled) |

**0.867 is the honest number for branch (b).** There is real signal — the
features are not merely a camera fingerprint — but it is below the pooled figure
and below target.

> ### A number that was discarded
>
> A first pass reported **AUC 0.980 for grade 0 vs grade 1**. That was rejected,
> not published. Mild NPDR is *microaneurysms only* and is the hardest call on
> the scale; 0.98 is not credible. No single resolution stratum held enough of
> both classes to recompute it, so the figure was **entirely cross-stratum** —
> pure confound.
>
> **Consequence: we currently cannot measure performance on grade 0 vs 1 at
> all.** That is the clinically important early-detection case, and it is an open
> hole, not a solved problem.

---

## Why the CNN and lesion branches are complementary by construction

This is the sharpest architectural point available, and it should lead the
presentation:

> At 224×224, a microaneurysm is **under one pixel. It is physically not in the
> input.**

Worked from the project's own scale anchor: `normalizeFundus` sets R=436, the
optic disc measures 124 px, and a standard disc is 1.85 mm → **14.92 µm/px** at
872 px width → the image spans **13.0 mm** of retina (right for a 45° field).

Microaneurysms are **10–100 µm**; 125 µm is the MA/haemorrhage *boundary*, not a
typical MA.

| Image width | µm/px | small MA (30 µm) | typical MA (60 µm) | boundary (125 µm) |
|---|---|---|---|---|
| ~2400 (native APTOS) | 5.4 | 5.5 px | 11.1 px | 23.1 px |
| 872 (our normalised) | 14.9 | 2.0 px | 4.0 px | 8.4 px |
| 512 × 512 | 25.4 | 1.2 px | 2.4 px | 4.9 px |
| **224 × 224** | **58.1** | **0.5 px — gone** | **1.0 px** | 2.2 px |

At 224×224 one pixel is **58 µm**, so any MA below that is literally sub-pixel —
true for small and typical MAs. Even the 125 µm boundary case is 2.2 px, which no
CNN can separate from sensor noise.

So the CNN branch, which resizes, **cannot reliably see the lesion that defines
grade 1**. The lesion branch runs at native resolution and its single strongest
feature is `ma_n`.

> Stated precisely, because the loose version ("a microaneurysm is under one
> pixel at 224") is true for typical MAs but false for the 125 µm boundary case,
> and a judge who checks the arithmetic will find that out.

Fusion is therefore not ensembling for a few points of AUC — **each branch covers
a blind spot the other has by design.** That is also the answer when a judge asks
"why not just use a CNN?"

---

## What feeds Module 3 (not only Module 2)

From the interlock table in
[DR_Pipeline_Techniques_and_Datasets.md](DR_Pipeline_Techniques_and_Datasets.md#how-the-modules-interlock):

| Producer | What flows into M3 |
|---|---|
| M1 quality score | ⚠ the *widen confidence bounds* use is **disproved below** (rho 0.036 vs model error). Real uses: `normalizeFundus`, the refusal path, Module 2's `sharp_ok` gate |
| M2 OD + fovea | quadrant definition for 4-2-1; **exudate–fovea distance** for DME |
| M2 lesion features | the fusion input that beats CNN-alone |
| the image itself | the CNN branch |

M3 then emits **confidence → Module 5's triage queue load**, and its lesion
evidence → Module 4's explanation.

### Gap: exudate–fovea distance is not computed

We store `fovea_x`, `fovea_y`, `exu_n` and `exu_area` but **never the distance
between them**. The reference doc calls this the clinically decisive fact:

> Hard exudates within 500 µm of the fovea = clinically significant macular
> oedema = **urgent referral, regardless of the DR grade**.

500 µm = **34 px** at our scale. This is a separate output from the 0–4 grade and
is cheap to add — both positions already exist. It is currently missing.

---

## Does Module 3 need Module 1?

Yes — but **not** as a feature source, and **not** for the reason this project
previously assumed.

Module 1's features reach only **AUC 0.707** for referable DR, and adding them to
the Module 2 vector moves it 0.910 → 0.915. They are not grading features. That
was never their job.

### The abstention hypothesis — tested, and it failed

The interlock table claims *low quality → widen confidence bounds*. That is a
testable claim, so it was tested: does image quality predict **model error**?

| sharpness quartile | n | error rate | mean confidence |
|---|---|---|---|
| worst | 78 | 14.1% | 0.628 |
| low | 77 | 24.7% | 0.597 |
| mid | 77 | 10.4% | 0.573 |
| best | 77 | 22.1% | 0.538 |

**ρ(`varLapNorm`, error) = +0.036 — nothing.** Abstaining on the blurriest
quartile makes accuracy *worse*: 19.0% error on the retained 75%, against 17.8%
on everything.

**Do not route images to a human on quality score alone.** It does not identify
the cases the model gets wrong.

**Why this actually supports Module 1 rather than undermining it.** The test ran
on `gate_reject == 0` rows only — Module 1 had already removed the genuinely
unreadable images. What remains has too narrow a quality range to predict
anything. The gate did its job; the residual variation is noise. The correct
conclusion is "the gate works", not "quality does not matter".

### Module 1's four real jobs

1. **`normalizeFundus` — R = 436.** Everything downstream depends on it. Without
   a constant retinal radius, "125 µm = 8.4 px" is false and **every Module 2
   size threshold is meaningless**. This alone makes Module 1 non-optional.
2. **The refusal path** — "I can't read this, take it again", with a specific
   reason. Listed as the single highest-value differentiator in
   [the techniques doc](DR_Pipeline_Techniques_and_Datasets.md#what-actually-wins-points).
3. **`varLapNorm` feeds Module 2's `sharp_ok` gate** — the second, stricter gate
   that takes `hem_n` from ρ 0.178 to 0.487.
4. **Rejection rate → Module 5** retake probability and throughput.

### ⚠ Safety bug: the gate rejects sick patients preferentially

Measured across all 3,662 images:

```
gate_reject rate by grade
  grade 0:   3.8%   (n=1805)
  grade 1:   6.5%   (n= 370)
  grade 2:  12.3%   (n= 999)
  grade 3:  12.4%   (n= 193)
  grade 4:  12.9%   (n= 295)
```

**Sick patients are rejected 3.4× more often than healthy ones.** This was
flagged earlier on a 150-image sample; it is now confirmed on the full set.

Part of it is real — diseased eyes are genuinely harder to image, because
cataract and media opacity travel with diabetes. That does not make the
behaviour safe. **A screening system that preferentially refuses to read the
patients who need referral is a clinical hazard.** Rejected images must be
routed to a human, never silently dropped, and the rejection rate must be
reported per grade in any validation.

---

## The scale to implement

**ICDR severity scale:**

| Level | Name | Defining findings |
|---|---|---|
| 0 | No apparent DR | No abnormalities |
| 1 | Mild NPDR | **Microaneurysms only** |
| 2 | Moderate NPDR | More than MAs, less than severe |
| 3 | Severe NPDR | **4-2-1 rule**, no proliferative signs |
| 4 | Proliferative DR | Neovascularization and/or vitreous/preretinal haemorrhage |

**Referable DR = level ≥ 2.** That is the binary the >90% sens / >85% spec
requirement refers to. Levels 0–1 re-screen in a year; level 2+ sees an
ophthalmologist.

### How our Module 2 maps onto it

| ICDR criterion | Our column | State |
|---|---|---|
| Microaneurysms (level 1) | `ma_n` | **works** — ρ +0.462/+0.525, grade-0 median 0 |
| Haemorrhages | `hem_n` | works **under `sharp_ok` only** (ρ 0.178 → 0.487) |
| >20 HE in 4 quadrants | `q_min`, `rule421` | fires 67% at grade 3, but **16% at grade 0** |
| Venous beading, 2+ quadrants | — | **not implemented**, no ground truth anywhere |
| IRMA, 1+ quadrant | — | **not implemented**, needs FGADR |
| Neovascularization (level 4) | `nv_fine` | ρ +0.438, **never validated against real NV** |
| Hard exudates | `exu_n` | **broken** — grade 0 has the highest median |

**Two of the three pathways to level 3 do not exist**, so even a perfect
haemorrhage counter reconstructs only one of them. Say this out loud rather than
implying the 4-2-1 rule is fully implemented.

---

## Feature engineering for the CNN branch

**No hand-crafted features.** That is what branch (b) is for, and duplicating it
inside branch (a) defeats the ablation. The engineering for the CNN lives
entirely in **preprocessing, resolution and augmentation**.

### Our measurements contradict the standard advice

Every one of these was tested in [Module 1 [F]](Module1_F_Enhancement.md):

| Standard advice | Measured here |
|---|---|
| Apply CLAHE | **costs 20% MA detectability** |
| Ben Graham preprocessing (won Kaggle 2015) | **rejected, −1.118** |
| Enhancement normalises across cameras | **false** — camera identifiability only 97.1% → 95.6% |
| Denoise to clean up sensor noise | **never** — deletes microaneurysms outright |

The only enhancement that helped was **conditional**: illumination correction
applied *only* to images that failed on illumination (+0.65). Blanket
enhancement made things worse on average.

**Implication for the CNN branch: preprocess minimally.** FOV crop, radius
normalisation, and nothing else by default.

### The decisions that do matter

| Decision | Guidance |
|---|---|
| **Working resolution** | the dominant one — at 224×224 one pixel is 58 µm and typical MAs vanish. **512 minimum**; consider a second head on native-resolution tiles |
| FOV crop + radius normalisation | from Module 1, non-negotiable |
| Augmentation | rotation is **free** (fundus images have no canonical orientation); flips, mild scale and brightness jitter |
| Loss | regression-with-thresholds or an ordinal head, **not** plain softmax |
| Imbalance | class weights or focal loss; select on QWK |

### The one feature-engineering rule that is not optional

For the **fusion** vector: **ratios and shapes, never absolute intensity.**

Feeding absolute colour to the microaneurysm classifier produced a false AUC of
**0.995** — it had learned camera identity, not disease. Banning absolute-
intensity features dropped it to an honest 0.742. The same trap applies to any
feature reaching the fusion layer.

---

## Things that will bite you

**Ordinality.** Grades are ordered — predicting 4 for a true 0 is catastrophic,
predicting 1 is minor, and plain cross-entropy treats these identically. Train as
**regression and threshold**, or use an ordinal head (CORAL/CORN), and select on
**quadratic weighted kappa**. Top APTOS solutions landed ~0.93 QWK; 0.88–0.91 is
a solid result.

**Class imbalance.** The true distribution is 49 / 10 / 27 / 5 / 8 %. A model
left alone predicts 0 for everything and reports ~49% accuracy. **Never report
plain accuracy** — report per-class sensitivity, the confusion matrix, and QWK.

**Our 309 rows are grade-balanced (~20% each), not 49/10/27/5/8.** Anything
prevalence-dependent fitted on them — PPV, a decision threshold, a class prior —
will be wrong. Finish the extraction before fitting branch (b) for real.

**The operating point is not a model property.** Train, then walk the ROC:

```matlab
[X, Y, T, AUC] = perfcurve(trueLabels, scores, 'referable');
```

Find the threshold where sensitivity ≥ 0.90, read the specificity there, and
**fix the threshold on validation before touching test**. Choosing it on the test
set is the most common accidental cheat in this field.

**Calibrate the binary separately from the 5-class head.** Don't threshold the
argmax — compute `P(referable) = P(2) + P(3) + P(4)` from calibrated
probabilities, then tune the threshold on that aggregate. Softmax outputs are
badly overconfident; apply Platt scaling or isotonic regression on a held-out
calibration set first.

**Stratify every metric by resolution.** Otherwise you will report 0.910 when the
real number is 0.867.

---

## Generating the clinical report

**This is why branch (b) earns its place despite being less accurate than a
CNN.** A CNN outputs a grade and a heatmap. It cannot say *17 microaneurysms,
6 nasal*. The report is assembled from Module 2 columns, not from the network.

### What it can already emit — real rows, real numbers

```
--- 857230f64a2e  (true grade 4) ---
Predicted referable: YES  (p=0.91, confidence 0.83)
Image quality      : varLapNorm 0.033, FAILS the lesion-counting gate
Microaneurysms     : 247  (377 candidates, 66% kept)
Haemorrhages       : 70   (weakest quadrant 4, strongest 36)
4-2-1 rule         : MET  (needs >3 in all four quadrants)
Retinal area       : vessels 8.9% of field, exudate area 0.98%
Geometry           : OD-fovea 2.46 DD, OD brightness ratio 5.44
```

Every line traces to a CSV column, so a clinician can verify it against the
annotated image in seconds — the 30-second review target. Percentage-style
statements come from `exu_area` and `vessel_pct` (% of field) and from the
candidate-retention rate (`ma_n / ma_raw`).

| Report line | Source columns |
|---|---|
| referable + confidence | branch (b) probability, calibrated |
| image quality verdict | `varLapNorm`, `sharp_ok`, `gate_reason` |
| microaneurysm count | `ma_n`, `ma_raw` |
| haemorrhages + quadrants | `hem_n`, `q_min`, `q_max` |
| 4-2-1 criterion | `rule421` |
| area percentages | `exu_area`, `vessel_pct` |
| geometry sanity | `fovea_od_dd`, `od_bright` |

### Running it immediately exposed two bugs

Which is the *other* reason to build the report early — it is a consistency
check on the whole pipeline.

1. **A grade-0 image reports 121 haemorrhages.** `hem_n`'s grade-0 median is 0
   only on the sharp subset; on ordinary images it still counts dark texture.
   The report makes the failure obvious in a way a correlation coefficient does
   not.
2. **The grade-4 image failed the sharpness gate and was graded anyway.**
   `sharp_ok` is written as a flag and never enforced, so the report contradicts
   itself in adjacent lines.

### Still missing before it is clinically usable

- **Per-quadrant named counts** — "7 superior-temporal, 4 inferior-temporal, 6
  nasal". We store only `q_min` and `q_max`, not the four labelled values.
  The quadrant geometry already exists; only the labelling and storage is absent.
- **Exudate–fovea distance** — the DME trigger, and clinically decisive
  independent of grade. See [the gap noted above](#gap-exudatefovea-distance-is-not-computed).
- **Calibrated probabilities.** The `p` above is a raw RandomForest score. It
  must be Platt- or isotonic-scaled before being shown as a confidence.

---

## Build order

1. **Branch (a), a plain fine-tuned CNN on all 3,662 images.** Do this first. It
   is unblocked by Module 2's state, gives an end-to-end number in a weekend, and
   establishes the baseline the ablation table needs.
2. **Finish the Module 2 extraction** (~3.3 h, 3,353 rows remaining). This removes
   the sampling bias that currently makes branch (b) untrainable.
3. **Branch (b) properly**, on the full table, stratified by resolution.
4. **Branch (c) fusion**, then the ablation table.
5. **Calibration + operating point**, on validation only.

### Prerequisites currently unmet

**Blocking — data**

- [ ] Full Module 2 extraction (309/3,662 populated, ~3.3 h)
- [ ] Grade 0 vs grade 1 measurable at all — currently impossible, and it is the
      early-detection case the whole system exists for

**Blocking — correctness**

- [ ] **The quality gate rejects grade-4 patients 3.4× more often than grade-0.**
      A safety issue, not a tuning issue. Route rejects to a human; never drop
      them silently
- [ ] `sharp_ok` is written but **never enforced** — a grade-4 image failed the
      gate and was graded anyway, and the report says both things on adjacent
      lines
- [ ] `hem_n` still returns **121 haemorrhages on a grade-0 retina** off the sharp
      subset
- [ ] `od_ok` flag — 14 of 309 rows have `od_bright` outside 0.5–8.0, i.e. optic
      disc localisation failed, and `q_min`/`q_max` depend on that OD position
- [ ] `exu_n` re-derived or dropped (grade 0 has the highest median)

**Needed for the report / Module 4**

- [ ] Per-quadrant **named** counts — only `q_min`/`q_max` are stored
- [ ] Exudate–fovea distance (the DME path, decisive independent of grade)
- [ ] Calibrated probabilities — raw forest scores are not confidences

**Known limitation, not fixable here**

- [ ] A patient-level split — APTOS filenames do not expose patient identity, so
      this **cannot** be done. State it rather than implying image-level splits
      are equivalent.

---

## Honest summary

| Claim | Status |
|---|---|
| Module 2 alone suffices for grading | **No** — 0.867 within-stratum AUC, 75% spec at 90% sens vs 85% target |
| Module 2 features carry real signal | **Yes** — 0.867 is well above the 0.809 obtainable from resolution alone |
| We can detect mild NPDR (grade 1) | **Unmeasured** — the one figure we had was confound |
| The 4-2-1 rule is implemented | **One of three pathways**, and it fires on 16% of grade-0 eyes |
| Any of this is validated against lesion ground truth | **No** — APTOS has none; every number is a correlation with grade |
| Module 1 is needed | **Yes** — but for `normalizeFundus`, the refusal path and `sharp_ok`, **not** as grading features (AUC 0.707) |
| Quality score can drive abstention | **No** — rho +0.036 against model error; abstaining on the blurriest quartile makes accuracy worse |
| The quality gate is safe to ship | **No** — it rejects grade-4 patients 3.4× more often than grade-0 |
| The CNN branch needs hand-crafted features | **No** — the engineering is resolution, crop and augmentation; CLAHE and Ben Graham both measured *worse* here |
| A clinical report can be generated today | **Yes, mechanically** — every line traces to a CSV column, but it currently reports 121 haemorrhages on a healthy eye |

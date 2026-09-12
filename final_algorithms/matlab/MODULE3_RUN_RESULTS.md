# Module 3 — first end-to-end run on the 500-image pilot sample

Stage 1 → Stage 2 → Stage 3, MATLAB **R2026a**, Windows, APTOS 2019 train set.
Run date 2026-09-12. This file records what was executed, what had to be
changed to make it execute, what came out, and what is still wrong.

Companion to [`RUNNING_IN_MATLAB.md`](RUNNING_IN_MATLAB.md) (the runbook) and
[`Module3_Plan.md`](../../notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md)
(the plan). Section numbers below refer to the plan.

---

## 1. Headline

The pipeline runs end to end and fills every feature column, so **Phase 0's exit
criterion is met**. The grading itself is weak, and the reason is measured
rather than guessed: outside of `nv_score`, the Stage 2 lesion features carry no
within-camera signal.

| | |
|---|---|
| Images extracted | **464 of 500** (36 rejected by Stage 1) |
| Dataset | 464 rows × 72 columns, no blank feature cells |
| Out-of-fold QWK (pooled) | 0.5235 |
| **Out-of-fold QWK (within resolution)** | **0.2607** — the honest number (§4.3) |
| Referable AUC (pooled / within) | 0.7995 / 0.7650 |
| Referable sens / spec | 0.903 / 0.447 (target 0.90 / 0.85) |
| Grade-4 recall | 0.269 |
| Held-out test set | **NOT touched** — Phase 8 is still unspent |

Wall time on this machine (5.7 GB RAM, one MATLAB process): Stage 1 → Stage 2
**64.7 min** for 500 images; Stage 3 **35–45 min** per configuration.

---

## 2. Stage 1 rejected every image as specified — four gates had to change

The first smoke test rejected **20 of 20** images, and a 40-image sample across
all five grades rejected **40 of 40**. Four separate defects, each one a faithful
implementation of a spec that does not survive contact with the data.

### 2.1 #2.2 black region — geometrically impossible (🔴 F1 in the Stage 1 review)

The band (15–45% black for aspect 1.33) is a **whole-image** expectation, but the
compute shortcut applies it **per sampled row** and requires ≥80% of rows to sit
inside it. A round retina's rows run from ~20% black through the middle to ~100%
at the poles, so at most ~68% of rows can ever qualify. Every 1:1 and 4:3 image
failed, including correctly framed ones.

**Replaced with `areaFracCheck`** (the review's own option B): captured FOV area
÷ π R², reject below 0.50. Aspect-independent by construction.
New file: [`stage1/areaFracCheck.m`](stage1/areaFracCheck.m).
`blackRegionCheck.m` is now unused; `black_region_pct` is still recorded.

### 2.2 #2.1 area ratio — rejected whole cameras

Two failure modes, both rejecting anatomically complete retinas:

- **Frame clipping.** Cameras that crop the retina at the top and bottom
  (2416×1736, 2588×1958, 3216×2136) gave s1 ≈ 1.28 against a 0.85–1.15 band.
  These cameras took most of the grade 1–4 images, so the gate was rejecting by
  disease.
- **Elliptical FOV.** The 2896×1944 camera stores a complete retina ~16% wider
  than tall (non-square pixels), failing the band on 17 of its 18 images —
  11 of them grade 3, the grade with the least backfill.

**Fixed** in [`stage1/areaRatioCheck.m`](stage1/areaRatioCheck.m): a clipped axis
skips the shape test (how much retina is missing is `areaFracCheck`'s job), and a
FOV that fills its own ellipse (`nnz/(π·rH·rV) ≥ 0.85`) is accepted. Notched,
fragmented or irregular masks still fail.
[`stage1/buildFovMask.m`](stage1/buildFovMask.m) now reports
`clipped_horizontal` / `clipped_vertical`.

### 2.3 #3 sharpness thresholds — placeholders that reject everything

`THRESH_BRENNER_FAIL = 50` against measured scores of 2–40. The other three
thresholds were placeholders too, and a single global threshold is a **camera
filter** (review item M1: a global floor rejects grade-2/4 images 3.4× more often
than grade-0).

**Replaced with per-resolution percentiles**, calibrated from the sample itself
with no grade labels: fail below **p2**, borderline below **p10**. Strata with
fewer than 20 images use a pooled row.

- New: [`calibrateStage1Thresholds.m`](calibrateStage1Thresholds.m) — writes
  `stage1/stage1_sharpness_thresholds.csv` (**required**; without it the four
  gates fall back to the placeholders and reject everything).
- New: [`stage1/stage1SharpnessThresholds.m`](stage1/stage1SharpnessThresholds.m)
  — the lookup the four gate functions call.

p5/p15 was tried first and rejected 16% of the sample (four cascaded gates
compound); p2/p10 lands at 7.2%, inside the 4–13% the review measured.

### 2.4 #4.2 CLAHE — a noise check that can never pass

Every borderline image was rejected at enhancement. CLAHE is a local gain, so
high-frequency energy scales with the contrast it adds: the mildest setting
raised contrast 2.3–2.7× and HF energy 2.9–3.2×, against a limit of "HF ratio
≤ 1.5" that sits alongside a requirement that contrast increase. The two
conditions are mutually exclusive.

**Fixed** in [`stage1/claheEnhancement.m`](stage1/claheEnhancement.m): the noise
ratio is now divided by the contrast gain, so the test catches noise amplified
*beyond* the signal (these images measure 1.16–1.24 against the 1.5 limit).

### 2.5 Result

| | Images |
|---|---|
| Pass | 391 |
| Borderline → enhanced → pass | 73 |
| Rejected | 36 (7.2%) |

Rejections by grade — **8 / 3 / 12 / 4 / 9** for grades 0–4, matching the
calibration projection exactly, and with no disease skew. One rejection is a
474×358 image that genuinely fails the 0.3 MP floor.

Both extraction runs produced the identical tally, as expected once Stage 1 was
frozen.

---

## 3. Stage 2 — optic disc and fovea were collapsed

The first extraction completed, but its output showed `od_radius_pct` **constant
at 2.8486 on all 464 images** and `od_fovea_dist_dd` between 0.24 and 0.60 disc
diameters where anatomy says 1.2–3.0.

**Two linked defects:**

1. [`stage2/locateOpticDisc.m`](stage2/locateOpticDisc.m) ranked its five
   candidate radii by mean brightness. A smaller averaging window always reaches
   a higher maximum, so the smallest radius won every time — and, sitting below
   the 5% plausibility floor, `confirmed` was never true.
2. [`stage2/locateFovea.m`](stage2/locateFovea.m) then took one disc diameter as
   `2 × that radius` (~25 px instead of the pinned `DD_PX` = 124 px) and searched
   30–75 px from the disc instead of ~300, so the fovea always landed beside the
   disc.

This was not cosmetic: the OD→fovea axis defines the quadrant map, so the
per-quadrant counts and the 4-2-1 features that Stage 3 consumes were being
computed in the wrong frame.

**Fixed**, and the 500 images re-extracted:

| | Before | After |
|---|---|---|
| `od_radius_pct` | 2.8486 on every image | 5.70 / 8.55 / 11.39, inside the 5–12% band |
| `confirmed` | never | true on the probe set |
| `od_fovea_dist_dd` | 0.24–0.60 DD | 1.20–3.00 DD |

The radius is now chosen by centre-surround contrast among radii inside the
anatomical band. Contrast alone reverses the old bias (a wider annulus reaches
further into dark retina), so the band restriction is what keeps it honest.

---

## 4. Stage 3 — grading

Cross-validated on the 397 dev rows, 5 grade-stratified folds, lesion
classifiers refit inside every fold (§4.1). The ordinal-regression MLP of §6.2;
the RandomForest baseline has been removed from the codebase.

### 4.1 Block 6a (`6a_measured_core`, 12 features) — the kept configuration

```
QWK pooled            0.5235
QWK within resolution 0.2607   <- the honest number
referable AUC         0.7995 pooled / 0.7650 within
referable sens/spec   0.903 / 0.447
per-class sens        g0 0.47  g1 0.39  g2 0.13  g3 0.36  g4 0.27
grade-4 recall        0.269
ECE                   0.2438 raw -> 0.0358 calibrated
cutpoints             [0.993 1.365 1.618 2.249]
```

Two resolution strata score exactly 0.000. Calibration works well; the ranking
underneath it does not.

### 4.2 Block 6b (+ microaneurysms, 17 features) — REJECTED

| Metric | 6a | 6b |
|---|---|---|
| QWK within resolution | **0.2607** | 0.2554 |
| QWK pooled | 0.5235 | 0.5051 |
| Referable AUC within | 0.7650 | 0.6886 |
| Grade-4 recall | 0.269 | 0.167 |

§8 keeps a block only if the within-resolution number improves. It did not, so
6b is rejected and 6a stands. Grade-3 sensitivity rose (0.36 → 0.59) only
because the model pushed more cases into grade 3, at the expense of grades 1
and 4.

This contradicts decision D1, which expects microaneurysm counts to be the
strongest single feature. §5 explains why.

---

## 5. Why the grading is weak — measured, not speculated

Within-stratum Spearman ρ against grade:

| Feature | 2416×1736 | 2588×1958 | 3216×2136 | 1050×1050 | 3388×2588 | Pooled |
|---|---|---|---|---|---|---|
| `ma_count` | −0.009 | +0.004 | −0.09 | −0.164 | −0.344 | **−0.401** |
| `haem_count` | +0.19 | +0.065 | −0.041 | +0.077 | −0.068 | +0.078 |
| `nv_score` | **+0.378** | **+0.319** | **+0.348** | **+0.310** | **+0.324** | +0.306 |

**`ma_count` is not inverted — it is empty.** The pooled −0.401 looks like an
inverted detector, but within any single camera the correlation is ≈ 0. The
apparent signal is camera identity: median `ma_count` is 127 on the 1050×1050
camera against 19 on 2416×1736, and grade 0 holds 46 of the 59 1050×1050 images.
This is exactly the confound §4.3 exists to catch.

**Likely mechanism.** Every image is resampled to the 872 px working grid, so a
1050×1050 original is barely downsampled while a 2416×1736 is halved. Heavy
downsampling smooths away the fine noise the top-hat detector counts as
candidates; light downsampling leaves it. The count tracks the resampling
factor, not the retina. The area filters are scale-normalised, but the noise is
not.

For comparison, the previous implementation measured MA within-ρ **+0.478** —
the number decision D1 rests on. The finalized detector is a large regression
against it, and that is the finding this run exists to surface.

**`nv_score` is the exception**: +0.31 to +0.38, same sign in all five strata,
matching the Stage 2 review's claim that fine-scale excess is its most robust
feature. It is the only Stage 2 feature currently earning its place.

---

## 6. Known limitations

- **The lesion features do not work within camera.** Microaneurysms ≈ 0,
  haemorrhages ≤ +0.19. Fixing this is a Stage 2 detection redesign (the
  review's F1 ratio-based candidate features, and noise matched across
  cameras), not a threshold tweak.
- **`rule421_haem` is constant 0**, and it is one of the 12 features in use.
  Not a threshold problem: the constant is already the re-derived `>3`, but
  `haem_q_min` is 0 on 450 of 464 images and never exceeds 3, so the rule cannot
  fire. `severe_npdr_flag` is constant 1 for the mirror-image reason (beading
  and IRMA quadrant tests fire everywhere).
- **`od_fovea_dist_dd` landing in 1.2–3.0 DD is not independent validation** —
  the fovea search annulus bounds it. The Stage 2 review (M4) warns about this
  exact circularity.
- **`od_radius_pct` takes only 3 values**, since only 3 of the 5 search radii
  fall inside the anatomical band. It is a QC column, not a model input.
- **The Stage 2 review's M3/M4/m1 are still unapplied**: vessels are excluded
  from the OD search (they converge there), the fovea score has no avascularity
  term, and OD detection runs on shade-corrected rather than raw green.
- **MATLAB and Python have diverged.** All fixes above are MATLAB-only. Never
  mix rows extracted by the two implementations (runbook §7).
- **36 rejected images were not backfilled** from `data/module3_reserve.csv`,
  so grades hold 88–97 rows rather than 100.

---

## 7. Reproducing this run

```matlab
cd 'C:\Pranav\college\sih\SIH_MathWorks_2026'
addpath('final_algorithms/matlab')

calibrateStage1Thresholds()        % ~4 min -> stage1/stage1_sharpness_thresholds.csv
extractModule3Features()           % ~65 min -> the three CSVs + candidate cache
runModule3()                       % ~35-45 min -> metrics + predictions
```

`calibrateStage1Thresholds` must run first on any new dataset. Without its
output table the four #3 gates fall back to the placeholder constants and reject
every image.

The test set stays untouched until the feature set is settled: `runModule3(Test=true)`
spends Phase 8, and it can only be spent once (§7.2).

### Output

| File | Contents |
|---|---|
| `data/module3_stage1_features.csv` | 500 rows × 21 Stage 1 columns |
| `data/module3_stage2_features.csv` | 464 rows × 45 Stage 2 columns |
| `data/module3_dataset.csv` | 464 × 72, joined, plus split/fold/resolution |
| `data/module3_stage3_predictions.csv` | 397 dev rows, out-of-fold predictions |
| `data/module3_stage1_calibration_scores.csv` | per-image sharpness scores |
| `data/module3_candidates/<id>.mat` | 464 cached candidate sets |

The lesion columns in the CSVs come from the **placeholder rule** and are QC
only. Stage 3 recomputes them per fold from the cache.

---

## 8. If the work continues

1. **Fix the microaneurysm detector**, measuring within-stratum ρ rather than
   pooled ρ. Pooled numbers on this dataset read camera identity and will look
   like success (the review's F1 records a false AUC of 0.995 from exactly this).
2. **Try block 6d (NV split)** — `nvd_score` / `nve_score` /
   `nv_irma_quadrants`. It is the only family with signal, and §8 expects it to
   be what lifts grade-4 recall.
3. **Backfill the 36 rejected images** from `data/module3_reserve.csv`.
4. **Leave the test set alone** until the features are settled.

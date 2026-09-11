# Module 2 Feature CSV — Data Dictionary

**Generator:** [`python/extract_module2_features.py`](../../../../code_testing/python/extract_module2_features.py)
**Consumed by:** [Module 3 grading](Module3_Severity_Grading.md)
**Merges into:** `data/aptos_train_module1_features.csv` (the existing Module 1
CSV — Module 2 adds columns, it does not create a second file)

```bash
python code_testing/python/extract_module2_features.py \
       aptos2019-blindness-detection data/aptos_train_module2_features.csv --all
```

The run is **resumable** — rows are flushed as computed and re-running skips
`id_code`s already present. It reads the Module 1 CSV from the same directory as
its output path and processes only rows with `fov_ok == 1 & gate_reject == 0`.

**Currently populated for 309 of 3,662 rows** — the images tested during
development. `m2_ok == 1` marks them; the rest are blank.

**Throughput: 3.53 s/image measured** on a Ryzen 5 7535U → **~3.3 h** for the full
training set. Dominated by the haemorrhage stage (40%), vessel segmentation
(27%) and `nv_fine` (17%).

---

> ## ⚠ Read `sharp_ok` before using any lesion column
>
> Measured on the 309 populated rows — within-stratum rho vs grade, on all rows
> against only those passing the `sharp_ok` gate:
>
> | Column | g0 | g1 | g2 | g3 | g4 | rho (all) | rho (`sharp_ok`) |
> |---|---|---|---|---|---|---|---|
> | **`ma_n`** | **0** | 23 | 35 | **106** | 94 | **0.462** | **0.525** |
> | `hem_n` | 63.5 | 68.5 | 73 | 97 | 99 | 0.178 | **0.487** |
> | `q_max` | 32.5 | 35.5 | 40 | 47 | 49 | 0.100 | **0.491** |
> | `q_min` | 0 | 2 | 2 | 5 | 4 | 0.213 | 0.304 |
> | **`nv_fine`** | 1.9 | 2.1 | 2.4 | 2.5 | 2.5 | **0.438** | 0.217 |
> | `exu_n` | **59.5** | 12 | 14 | 18 | 13 | 0.150 | 0.267 |
>
> **The gate is per-feature.** It roughly triples `hem_n` and quintuples
> `q_max`, and it **halves `nv_fine`** — use `nv_fine` on *all* rows and the
> dark-lesion columns on `sharp_ok == 1` only. **`exu_n` does not work at all**:
> grade 0 has the highest median.
>
> These are still correlations with *grade*, not accuracies. APTOS has no lesion
> ground truth.

---

## Vessels — component 1

| Column | Meaning | Typical |
|---|---|---|
| `vessel_pct` | % of FOV classified as vessel | ~11% by construction |
| `vessel_comps` | connected components after gap bridging | ~8 |
| `vessel_largest_pct` | % of vessel pixels in the largest component | 80.7% median |
| `vessel_width_med` | median width, `4 × mean(EDT)` | 2.7–10.1 px is the physical band |
| `vessel_skel_len` | total length, `area / width` | analytic, 160× faster than thinning |
| `vessel_frag` | fragmentation, `comps / length` | — |
| `vessel_coh` | structure-tensor orientation coherence | — |

`vessel_pct` is **fixed at ~11% by the threshold**, so it is not evidence the
segmentation is correct. `vessel_largest_pct` is the honest quality measure.

## Optic disc — component 2

| Column | Meaning |
|---|---|
| `od_x`, `od_y` | disc centre, normalised-image pixels (R = 436) |
| `od_bright` | disc-mean brightness ratio vs retina, median 3.02 |
| `od_struct` | local structure score |

Computed on **raw** green, never shade-corrected: the background estimate
(σ = 60 px) is smaller than the disc (124 px), so flat-fielding divides the disc
out. `od_bright` fell 2.99 → 1.87 on every image when this was got wrong.

## Fovea — component 3

| Column | Meaning |
|---|---|
| `fovea_x`, `fovea_y` | fovea centre |
| `fovea_od_dd` | OD→fovea distance in disc diameters — **sanity check, expect ~2.5** |
| `fovea_vdens` | vessel density over the foveal avascular zone, % — **a mislocalisation flag, not a feature** |

> `fovea_vdens` used to report density *at the chosen pixel*, which the search
> penalty forces to exactly 0.0 on every image. It now measures the foveal
> avascular zone (500 µm = 34 px radius). A healthy FAZ genuinely has no
> vessels, so the median is still 0 — it is non-zero on **1 of 309** images.
> Use it as a **mislocalisation flag** (non-zero = the fovea landed somewhere
> vascular, i.e. probably wrong), never as a graded feature.

Note `fovea_od_dd` is constrained to 2.1–2.9 by the search annulus, so a value
in that range **is not validation** — it is the constraint. This was a genuine
circular-validation error earlier in the project.

## Exudates — component 5

| Column | Meaning |
|---|---|
| `exu_n` | bright lesions after the 8 px minimum-area filter |
| `exu_area` | % of FOV covered by them |

The min-area filter fixed the *count* — without it, 1,244–2,279 specks per image
— but never fixed the measurement.

> **`exu_n` does not work.** Grade 0 has the **highest** median (59.5, against
> 12–18 for every diseased grade). It has now failed on four samples: +0.503 on
> the sharpest images, +0.200 on a random sample, −0.036…+0.146 at every
> sharpness cut, and wrong-signed medians on the CSV. It is most likely
> detecting reflective artefact, which is commonest in the young glossy retinas
> that dominate grade 0. **Do not use it without re-deriving the detector.**

## Microaneurysms — component 4

| Column | Meaning |
|---|---|
| `ma_raw` | candidates from closing at L=15, area 3–55 px, before classification |
| `ma_n` | candidates the classifier kept — **this is the count to use** |

`models/ma_candidate_rf.joblib` at **threshold 0.7** — the *lowest* probability
at which the grade-0 median count is 0, a criterion fixed before the sweep.
(0.9 would report rho +0.593, but that is a selected maximum and optimistic.)

**The best-evidenced feature in Module 2.** Candidate AUC 0.729; medians
**0 / 23 / 35 / 106 / 94** across grades 0–4, rho **0.462** ungated and **0.525**
gated. The grade-0 median of exactly **0** is the clinically correct answer.

Grade 4 (94) sitting below grade 3 (106) is expected, not a defect —
proliferative eyes are often previously treated, and laser scars destroy
microaneurysms.

## Haemorrhages — component 6

| Column | Meaning |
|---|---|
| `hem_raw` | candidates from scale-matched closing (L=41), before classification |
| `hem_n` | candidates the classifier kept — **this is the count to use** |

`hem_raw` is **not a lesion count**: it returns ~80 on a normal retina, which is
dark texture, not haemorrhages. `hem_n` applies
`models/hem_candidate_rf.joblib` at **threshold 0.8**, not 0.5 — the forest is
fitted on a 70.7%-positive weak-label set, and 0.8 is where the grade-0 median
reaches zero, which is the clinically correct value for a no-DR eye.

Candidate AUC 0.827. On the CSV: medians 63.5 / 68.5 / 73 / 97 / 99 across
grades — **monotone** — with rho **0.178 on all rows and 0.487 under
`sharp_ok`**. The grade-0 median of 63.5 is still far too high for a no-DR eye,
so `hem_n` remains a relative measure, not a lesion count.

## Quadrants / 4-2-1 — component 8

| Column | Meaning |
|---|---|
| `q_min` | classified haemorrhages in the **weakest** quadrant — gates the rule |
| `q_max` | the strongest quadrant |
| `rule421` | 1 if `q_min > 3` |

Quadrants are anchored to the **OD–fovea axis**, not frame axes. The textbook
constant is >20 per quadrant; on a single 45° field that fires on nothing at any
grade, so it was re-derived against this detector (93% specificity at grades
0–2, 64% sensitivity at 3–4 — **on sharp images only**).

`q_min` and `q_max` are stored **unthresholded** so the constant can be refitted
on the full dataset without re-extracting. `rule421` is a convenience column and
should be recomputed after any recalibration.

## Neovascularization — component 7

| Column | Meaning |
|---|---|
| `nv_fine` | % of FOV responding to a fine line detector but **not** a coarse one |
| `nv_fine_max` | max of `nv_fine` over a sliding 1 DD window |

Neovascular vessels are thin, so they respond at L=9/W=11 but not at L=31/W=31.
Medians **1.9 / 2.1 / 2.4 / 2.5 / 2.5** across grades, rho **0.438** on all rows.

**Do not apply `sharp_ok` to this column.** It is the one feature the sharpness
gate *harms* — 0.438 ungated falls to 0.217 gated, and to 0.035 above the 70th
percentile. It is the most robust feature across image quality (+0.314…+0.409 at
every sharpness band), which is exactly why restricting it to sharp images only
removes range.

Two caveats that do not go away: it is **not validated against real NV** (APTOS
has no NV annotations and only ~295 grade-4 images), and grade 0 appears in only
one resolution stratum, where `nv_fine` is *highest* — so there is no evidence
it separates no-DR from DR.

## Deliberately invalid

| Column | Meaning |
|---|---|
| `ma_count_INVALID` | raw microaneurysm candidates, **no classifier applied** |

Named to be unusable by accident. It correlates **−0.117** with grade — near
zero and wrong-signed — and only **0.400** with `ma_n`, which is the point: the
classifier changes *which* candidates survive, not merely how many. That is the
four-times-proven rule in a single number. **Use `ma_n`. Do not feed this column
to a model.**

## Status

| Column | Meaning |
|---|---|
| `sharp_ok` | 1 = `varLapNorm >= 0.082`, the **second** quality gate |
| `m2_ok` | 1 = all components ran |
| `m2_reason` | `ok`, `fov_failed`, or `ExceptionType:message` |
| `m2_ms` | wall-clock per image |

`sharp_ok` passes **53%** of images. It is written as a flag and deliberately
**not** applied as a filter, because the right population differs per feature
(see the table at the top). Module 1's `gate_reject` decides whether an image is
worth keeping; `sharp_ok` decides whether it is sharp enough to count lesions
on.

---

## The one analysis to run first

```python
import pandas as pd, numpy as np
df = pd.read_csv("data/aptos_train_module1_features.csv")
d  = df[(df.fov_ok == 1) & (df.gate_reject == 0)].copy()
d["res"] = d.width.astype(int).astype(str) + "x" + d.height.astype(int).astype(str)

# split by sharpness WITHIN grade, so the bands are not confounded with severity
d["band"] = d.groupby("diagnosis").varLapNorm.transform(
    lambda s: pd.qcut(s, 3, labels=["blurry", "mid", "sharp"]))

for col in ["hem_n", "q_min", "q_max", "exu_n", "nv_fine"]:
    for band, g in d.groupby("band", observed=True):
        rho = np.nanmean([
            gg[col].rank().corr(gg.diagnosis.rank())
            for _, gg in g.groupby("res") if len(gg) >= 8 and gg.diagnosis.nunique() >= 3])
        print(f"{col:>9} {band:>7} {rho:+.3f}")
```

If a column's ρ is strong in the sharp band and collapses elsewhere, it is
measuring image quality as much as disease. That is currently true of `hem_n`,
`q_min`, `q_max` and `exu_n`, and **not** true of `nv_fine`.

**The open task this implies:** Module 1's gate passes images on which these
columns reverse sign. Module 2 needs a **second, stricter `varLapNorm`
threshold** before the lesion detectors run — accepting an image for storage and
accepting it for lesion counting are different decisions. That threshold has not
been derived.

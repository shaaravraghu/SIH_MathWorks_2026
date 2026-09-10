# APTOS Module 1 Feature CSV — Data Dictionary

**File:** `data/aptos_train_module1_features.csv`
**Generator:** [`python/extract_module1_features.py`](../../python/extract_module1_features.py)
**Rows:** one per APTOS training image (3,662), `train.csv` duplicated with 51 extra columns.

```bash
python python/extract_module1_features.py aptos2019-blindness-detection \
       data/aptos_train_module1_features.csv
# optional: --split test --limit N --scale 0.5
```

The run is **resumable** — rows are flushed as computed, and re-running skips
`id_code`s already present.

**Throughput:** 1.4 s/image on a Ryzen 5 7535U (FOV detection at 1/2 scale).
~85 min for the full training set.

---

## Identity

| Column | Meaning |
|---|---|
| `id_code` | APTOS image id (joins to `train.csv`) |
| `diagnosis` | ICDR grade 0-4, copied from `train.csv` |

## Raw image

| Column | Meaning |
|---|---|
| `width`, `height` | pixels |
| `megapixels` | `width*height/1e6` |
| `aspect` | `width/height` |
| `file_kb` | PNG size on disk |

> `width`/`height` are **not** neutral metadata. 48% of grade-0 images are
> 1050x1050 or 819x614 vs 3% of grades 2-4 — a strong acquisition confound. Use
> these columns to stratify and confirm your Module 3 accuracy survives it.

## [A] detection status

| Column | Meaning |
|---|---|
| `fov_ok` | 1 = geometry found. **Not a quality verdict** — check `residual` too |
| `fov_reason` | `ok`, or why it failed (`empty_after_thresh`, `mask_gt_98pct`, `R_out_of_range`, `too_few_boundary`, ...) |
| `red_degenerate` | 1 = red channel was flat, fell back to `max(R,G,B)` |
| `raggedness_retry` | 1 = Otsu produced a ragged mask, relative-threshold fallback used |

## [A] geometry — full-resolution pixels

| Column | Meaning | Healthy range |
|---|---|---|
| `centre_x`, `centre_y` | fitted disc centre | — |
| `radius` | fitted disc radius | 207-1800 (8.7x spread!) |
| `residual` | mean &#124;dist−R&#124; / R — **the shape feature** | < 0.01 good, > 0.06 reject |
| `raggedness` | boundary px / (2πR) — threshold sanity | 1.0-1.3 clean, > 1.5 broken |
| `circularity` | 4πA/P² — **unreliable, do not gate** | bimodal, useless |
| `areaFrac` | captured area / πR² | ~0.89 typical, < 0.50 reject |
| `offset` | ‖centre − frame centre‖ / R | < 0.1 typical, > 0.35 reject |
| `borderFrac` | fraction of boundary on the image edge | ~0.47 is **normal** for 4:3 |

## Coverage

| Column | Meaning |
|---|---|
| `retina_px` | mask pixel count |
| `retina_pct` | 100 × retina / frame |
| `black_bg_pct` | 100 − `retina_pct` — the black surround |

## Exposure and colour — measured **inside the mask**

| Column | Meaning |
|---|---|
| `mean_R/G/B`, `std_R/G/B` | per-channel statistics over retina only |
| `sat_R`, `sat_G`, `sat_B` | fraction of pixels >= 250/255 |
| `dark_frac` | fraction of green pixels <= 5/255 |
| `ratio_RG`, `ratio_BG` | colour cast (R/G ~ 1.87 typical) |

> **Per-channel saturation matters.** Observed `sat_R` up to 0.70 while `sat_G`
> stayed under 0.04. High `sat_R` is **normal** — the fundus is red-dominant.
> High `sat_G` means the signal channel is clipped and the image is dead. A
> single grayscale saturation feature cannot tell these apart.

## [B] focus — on the radius-normalised image (R=436)

Computed at **full resolution** after normalisation. Never downsampled:
downsampling is a low-pass filter and would destroy the signal.

| Column | Tier | Note |
|---|---|---|
| `varLapNorm` | **1** | contrast-invariant, best real spread (47x), rho vs grade 0.126 |
| `regionMin` | **1** | min of `region1..5`; 4,100x partial-blur sensitivity |
| `tenengradVar` | **1** | noise-immune (0.91x), rho 0.067 |
| `brenner` | 2 | cheapest; rho −0.038 |
| `tenengrad` | 2 | rho **0.000** — perfectly disease-blind |
| `varLap` | 2 | redundant with `varLapNorm` |
| `sml` | 2 | scale-tunable Modified Laplacian |
| `regionCV` | 2 | dispersion across regions; 0.37 baseline on sharp images |
| `noiseSigma` | 2 | Immerkaer estimate; **input only, never gate** (rho 0.354) |
| `specSlope` | **3** | contrast-invariant but rho **0.460** — **do not gate** |
| `region1..region5` | — | centre + 4 quadrants (frame axes, not OD-fovea axis) |

## Verdict

| Column | Meaning |
|---|---|
| `gate_reject` | 1 if any fast-reject rule fired |
| `gate_reason` | pipe-joined: `residual`, `areaFrac`, `offset`, `borderFrac` |
| `proc_ms` | wall-clock per image |

Gate rules:

```
residual > 0.06  |  areaFrac < 0.50  |  offset > 0.35  |  borderFrac > 0.80
```

> **Known issue.** On a 150-image stratified sample all 10 gate rejections were
> grade >= 2, none grade 0 or 1. Review those images by eye before shipping any
> threshold — see
> [Module1_A](Module1_A_FOV_Detection.md#the-gate-skews-toward-sick-patients--unresolved).

---

## Suggested first analyses

```python
import pandas as pd
df = pd.read_csv("data/aptos_train_module1_features.csv")

# 1. does the gate skew by grade?  (this MUST be flat)
df.groupby("diagnosis").gate_reject.mean()

# 2. the acquisition confound
pd.crosstab(df.diagnosis, df.width.astype(str)+"x"+df.height.astype(str))

# 3. which features track disease rather than optics?
df.corr(numeric_only=True, method="spearman")["diagnosis"].abs().sort_values()

# 4. calibrate thresholds from YOUR distribution, not my defaults
df[["residual","areaFrac","offset","varLapNorm","regionMin"]].describe(
    percentiles=[.01,.05,.25,.5,.75,.95,.99])
```

Analysis 3 is the important one: **any feature with |rho| > 0.3 must not be used
as a rejection gate**, or the system will preferentially refuse to screen
patients who need referral.

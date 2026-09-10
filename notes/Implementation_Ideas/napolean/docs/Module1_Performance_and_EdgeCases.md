# Module 1 — Performance, Sampling & Edge Cases

Measured on **AMD Ryzen 5 7535U** (6C/12T, 2.9 GHz base), Windows 11, 5.7 GB RAM.
Single-threaded scipy. Timings are for the Python reference implementation;
MATLAB will differ in absolute terms but the *ratios* transfer.

---

## Contents

- [Headline recommendation](#headline-recommendation)
- [The key asymmetry: [A] can be downsampled, [B] cannot](#the-key-asymmetry-a-can-be-downsampled-b-cannot)
- [Speed vs image size](#speed-vs-image-size)
- [Sampling strategies for [B]](#sampling-strategies-for-b)
- [Why downsampling destroys focus metrics](#why-downsampling-destroys-focus-metrics)
- [Where is the structure? (a wrong hypothesis)](#where-is-the-structure-a-wrong-hypothesis)
- [Edge cases](#edge-cases)
- [Memory](#memory)

---

## Headline recommendation

| Stage | Strategy | Speedup | Cost |
|---|---|---|---|
| **[A] FOV** | detect at **1/2 scale**, rescale geometry | **4.4x** | median R error 0.83 px, p95 1.94 px |
| **[B] focus** | **8 patches of 2.5% area on a ring at 0.80R** | **4.9x** | rho = 0.985 vs full mask |

**Combined budget for a typical 4.2 MP APTOS image: ~1,200 ms -> ~300 ms.**
That clears the <1 s edge-device requirement with room to spare.

Do **not** downsample for [B]. Do **not** sample the central retina for [B].
Both explained below.

---

## The key asymmetry: [A] can be downsampled, [B] cannot

This is the single most useful result here, and it follows from what each stage
measures.

**[A] measures geometry.** The FOV boundary is an *aperture* — a huge, purely
low-frequency intensity step. Downsampling preserves it perfectly.

**[B] measures high-frequency energy.** Downsampling *is* a low-pass filter, so it
destroys exactly the signal being measured.

### [A] under downsampling — 12 random APTOS images

`R` and centre rescaled back to full-resolution pixels before comparison.

| Scale | ms | Speedup | median &#124;dR&#124; | p95 &#124;dR&#124; | median &#124;dCentre&#124; | Failures |
|---|---|---|---|---|---|---|
| 1x | 936 | 1.00x | — | — | — | 0 |
| **1/2x** | **214** | **4.37x** | **0.83 px** | **1.94 px** | **0.74 px** | 0 |
| 1/4x | 52 | 18.0x | 2.47 px | **59.46 px** | 2.23 px | 0 |
| 1/8x | 16 | 60.3x | 5.76 px | 68.30 px | 5.39 px | 0 |

**1/2 scale is free** — sub-2-pixel error at p95 on a ~1100 px radius is 0.2%.

**1/4 scale is not safe**: the median is fine (2.5 px) but p95 blows out to 59 px.
One or two images in twelve fail badly. If you want 18x, detect at 1/4 to get an
approximate circle, then refine the boundary at full resolution inside a narrow
annulus around the estimate.

---

## Speed vs image size

`[A] detectFOV` at full resolution, synthetic fundus at each size:

| Size | MP | detectFOV | Peak RAM |
|---|---|---|---|
| 819 x 614 | 0.5 | 133 ms | 6 MB |
| 1050 x 1050 | 1.1 | 287 ms | 14 MB |
| 2416 x 1736 | 4.2 | 1,176 ms | 52 MB |
| 2588 x 1958 | 5.1 | 1,470 ms | 63 MB |
| 3216 x 2136 | 6.9 | 1,883 ms | 85 MB |
| **4288 x 2848** | **12.2** | **3,669 ms** | **151 MB** |

**Roughly linear at ~300 ms per megapixel.**

The bottom row is the IDRiD native resolution. **3.7 seconds for FOV detection
alone** is unusable in a capture loop — hence the 1/2-scale recommendation, which
brings it to ~840 ms, and 1/4-scale-plus-refine which would bring it under 300 ms.

---

## Sampling strategies for [B]

All measured on 40 normalised images (872x872, R=436) x 4 blur levels = 160
samples. `rho` is Spearman rank correlation against the full-mask value — if
rho ~ 1.0, the subsample ranks images identically, so any threshold behaves the
same.

| Strategy | % of retina | ms | Speedup | rho | median rel. err |
|---|---|---|---|---|---|
| full mask | 100% | 26.4 | 1.00x | 1.0000 | 0% |
| central r<0.40R | 16.7% | 3.8 | 6.86x | 0.9445 | **146%** |
| central 40% area | 41.6% | 11.3 | 2.33x | 0.9612 | 87% |
| annulus 0.4–0.85R | 58.6% | 18.8 | 1.40x | 0.9842 | 55% |
| 8 x 2.5% ring @0.50R | 20.8% | 5.3 | 4.95x | 0.9552 | 86% |
| 8 x 2.5% ring @0.65R | 20.8% | 5.5 | 4.83x | 0.9732 | 78% |
| **8 x 2.5% ring @0.80R** | **20.8%** | **5.4** | **4.88x** | **0.9851** | **19%** |
| 4 x 2.5% ring @0.65R | 10.4% | 2.2 | **12.2x** | 0.9613 | 63% |
| 16 x 1.25% ring @0.65R | 20.8% | 6.8 | 3.89x | 0.9601 | 84% |
| 8 x 5% ring @0.65R | 41.6% | 11.5 | 2.29x | 0.9895 | 47% |

### Your 8 x 2.5% idea works — but the ring radius decides everything

At **identical pixel cost** (20.8%, ~5.4 ms), moving the ring from 0.50R to 0.80R
takes median relative error from **86% down to 19%** and rho from 0.955 to 0.985.

**Why:** the full-mask value is area-weighted, and area grows as r^2 — most of the
retina's pixels live near the rim. A ring at 0.80R samples where the pixels
actually are. Sampling the centre measures a small, unrepresentative minority.

That also explains why `central r<0.40R` is the worst option tested despite being
the fastest: 16.7% of pixels, 146% median error, rho 0.944.

### Bonus: the 8 patches give you `regionMin` and `regionCV` for free

The ring layout is already 8 spatially separated regions. Compute the metric per
patch and you get the regional breakdown — the **4,100x partial-blur detector** —
at no additional cost. A single central disc cannot do this at all.

### Recommendation

```
8 patches, 2.5% of retinal area each, centres on a ring at 0.80R
-> 4.9x faster, rho = 0.985, 19% median error, regional breakdown included
```

If you need more speed, `4 x 2.5% @0.65R` gives **12.2x** at rho = 0.961 — but
with only 4 regions the partial-blur resolution drops.

---

## Why downsampling destroys focus metrics

`varLapNorm` on the same image at three resolutions:

| Blur sigma | full-res | 2x down | 4x down |
|---|---|---|---|
| 0 | 0.06346 | 0.09411 | 0.25919 |
| 0.5 | 0.02544 | 0.06958 | 0.22575 |
| 1 | 0.00368 | 0.03140 | 0.15716 |
| 2 | 0.00057 | 0.00752 | 0.07123 |
| 4 | 0.00007 | 0.00106 | 0.01448 |
| **dynamic range** | **907x** | **89x** | **18x** |

Two failures at once:

1. **The values inflate** — at sigma=4, 4x-downsampling reports 0.0145 where the
   truth is 0.00007, a **208x** overestimate. A badly blurred image reads as
   moderately sharp.
2. **The dynamic range collapses** from 907x to 18x. Downsampling by 4 throws away
   **98% of the discriminative power.**

Downsampling is a low-pass filter, and blur is a low-pass filter. You cannot
measure one through the other.

**Spatial subsetting (patches) is safe; resolution reduction is not.** Cropping
preserves the frequency content of what remains.

---

## Where is the structure? (a wrong hypothesis)

I predicted the fovea would be structure-poor — it is avascular and smooth — and
therefore a bad place to sample. Measured mean `|Laplacian|` by radial band over
40 images:

| Band | mean &#124;Lap&#124; | Relative |
|---|---|---|
| 0.0–0.2 R | 0.01555 | 0.96 |
| 0.2–0.4 R | 0.01552 | 0.96 |
| 0.4–0.6 R | 0.01579 | 0.97 |
| 0.6–0.8 R | 0.01625 | **1.00** |
| 0.8–1.0 R | 0.01410 | 0.87 |

**Essentially flat.** Structure density varies by less than 15% across the whole
retina, and the centre is not meaningfully poorer.

So the hypothesis was wrong, and the real reason central sampling underperforms is
purely the **area weighting** described above — not a shortage of edges. Worth
recording, because it means you should choose sample locations by *pixel
population*, not by anatomical intuition.

---

## Edge cases

18 synthetic cases. **Zero crashes.** Six correctly rejected, twelve detected.

| Case | Accepted? | Reason / result |
|---|---|---|
| all black | **NO** | `empty_after_thresh` |
| all white | **NO** | `mask_gt_98pct` |
| uniform mid-grey | **NO** | `mask_gt_98pct` |
| pure noise | **NO** | `R_out_of_range` |
| 10x10 px image | **NO** | `empty_after_thresh` |
| tiny blob (R=6) in frame | **NO** | `too_few_boundary` |
| 50x50 px image | yes | R=19.5, residual 0.015 |
| normal synthetic | yes | R=179.5, residual 0.0013 |
| red-free (green only) | yes | red-degenerate fallback fired correctly |
| single-channel 2-D input | yes | identical result to 3-channel |
| **retina fills frame** | yes* | R=182 (true 400), residual **0.166**, raggedness 2.77 |
| extreme aspect 800x60 | yes | R=27.5 |
| off-centre disc | yes | R=119.5, areaFrac 0.862 |
| very dark (val 0.05) | yes | identical geometry to normal |
| saturated (val 1.5) | yes | identical geometry to normal |
| heavy noise (sigma 0.25) | yes | R=179.4, residual 0.0020 |
| bright 1 px frame | yes | the `bwareafilt`-before-`imfill` fix holds |
| **two equal discs** | yes* | picks one, residual **0.371** |

\* Both starred cases produce a **wrong** circle but flag it with a high
`residual` (0.166 and 0.371, against a gate of 0.06). They are caught downstream
rather than at detection — acceptable, but note that `fov.ok == true` does **not**
mean the geometry is trustworthy. **Always check `residual` as well as `ok`.**

### Code-path coverage now complete

These paths were unreachable with real images and are now exercised:

| Path | Triggered by |
|---|---|
| `empty_after_thresh` | all black, 10x10 px |
| `mask_gt_98pct` | all white, uniform grey |
| `R_out_of_range` | pure noise |
| `too_few_boundary` | tiny blob |
| `red_degenerate` fallback | red-free image, all black/white/grey |

Still unexercised: `fit_exception` (the guards catch everything before the solver
throws) and `kept_border_pts` (needs an image where fewer than 50 free arc points
survive).

---

## Memory

Peak allocation scales linearly: **~12 MB per megapixel** for `detectFOV`.

| Image | Peak |
|---|---|
| 4.2 MP (APTOS typical) | 52 MB |
| 12.2 MP (IDRiD native) | 151 MB |

**This machine has 5.7 GB total and was at 97.4% utilisation during testing** — an
`ndi.sum` call requesting 38.7 MB failed outright with `_ArrayMemoryError`.

Practical consequences:

- Use `float32`, not `float64`, wherever precision permits — halves peak memory.
- Prefer `np.bincount` over `ndi.sum` for component sizing (the original failure).
- Process one image at a time; do not batch-load.
- **IDRiD lesion work at 4288x2848 will be tight.** Patch-based tiling is a memory
  requirement here, not just a training-data trick.
- Close the browser before long runs.

---

## Reproduce

```matlab
test_module1                % smoke test + blur sweep
benchmarkModule1(aptosRoot) % 150-image validation
```

Python reference harnesses used to produce this document live in the session
scratchpad: `cache.py`, `sampling.py`, `edge.py`.

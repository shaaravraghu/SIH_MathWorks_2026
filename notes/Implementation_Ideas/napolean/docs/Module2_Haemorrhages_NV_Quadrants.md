# Module 2, Steps 6–8 — Haemorrhages, Neovascularization, 4-2-1 Quadrants

**Status: all three are BROKEN.** Documented here so the failure modes are
recorded rather than rediscovered.

These three are grouped because they fail as a chain: the 4-2-1 rule needs
haemorrhage counts per quadrant, and haemorrhage detection currently returns
zero.

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

### 6. Scale-matched structuring elements — mechanically right, still not working

**The diagnosis was correct.** Morphological closing fills a structure only if
the line SE **bridges** it. An L=15 line fills lesions up to ~15 px, so a 30 px
haemorrhage *survives* closing and never appears in the difference at all.

```
microaneurysms   L=15,  threshold p99,  area   3-55 px
haemorrhages     L=41,  threshold p96,  area  55-908 px   + binary closing
```

| Feature | g0 | g1 | g2 | g3 | g4 | pooled | within |
|---|---|---|---|---|---|---|---|
| `hem_total` | 79.5 | 98.5 | 71.5 | 98.0 | 118.0 | 0.190 | **0.036** |
| `hem_dot` | 47.5 | 57.5 | 32.5 | 59.0 | 68.0 | 0.182 | 0.049 |
| `hem_flame` | 32.5 | 45.0 | 37.0 | 38.0 | 52.0 | 0.138 | **−0.111** |

**It now detects (median 0 → 79–118) but does not discriminate.**
Within-stratum ρ = **0.036** is noise, and `hem_flame` is wrong-signed.

**79 haemorrhages on a grade-0 retina is nonsense** — a no-DR eye has zero. The
detector is finding dark *texture*, not haemorrhages.

**What it still needs:** the candidate classifier. That single step took
microaneurysms from ρ = −0.117 to +0.09…+0.87, and exudates from −0.196 to
**+0.503**. Haemorrhages is the third component to prove the same rule and the
only one that has not yet had the fix applied.

### 7. Orientation incoherence — did not rescue it

Replaced the collapsed tortuosity proxy with a physical property:

```
normal arcades  = locally PARALLEL  -> anisotropic structure tensor
neovascular     = a TANGLE          -> locally isotropic

nv = local vessel density x (1 - local orientation coherence)
```

| Feature | pooled | within |
|---|---|---|
| `nvd` | 0.147 | **−0.307** |
| `nve` | 0.501 | 0.279 |
| `nv_p99` | 0.355 | −0.119 |

Medians still ~0; within-stratum correlations span **−0.307 to +0.279** —
incoherent and partly wrong-signed. **Still broken.**

### 8. The rule now fires — on the wrong images

```
4-2-1 fired on 2/70 images:  one grade 2, one grade 3

           q_min median    q_max median    flagged
grade 0         0              57            0/14
grade 1         6              50            0/14
grade 2         1              41            1/14
grade 3         5              48            1/14      <- should fire here
grade 4         5              64            0/14
```

`q_min` — the weakest quadrant, which gates the rule — shows no pattern across
grades. **The geometry is correct; the haemorrhage counts feeding it are not.**

---

## Summary

| # | Component | State | Next step |
|---|---|---|---|
| 6 | Haemorrhages | **detects, does not discriminate** (within ρ 0.036) | **add the candidate classifier** — the step that fixed MA and exudates |
| 7 | Neovascularization | **broken** (ρ −0.307…+0.279) | defer — unvalidatable on APTOS regardless |
| 8 | 4-2-1 quadrants | **fires on 2/70, wrong images** | blocked by 6 |

**Fix order: 6 → 8.** The pattern is now unambiguous three times over — every
component that stops at the threshold stage fails, and every one that adds
per-candidate features plus a classifier works. Haemorrhages is the remaining
application.

**Neovascularization should be deferred, not fixed.** There are no NV
annotations in APTOS and only ~295 grade-4 images, so even a working detector
could not be measured. FGADR provides pixel-level NV and IRMA masks and is the
only route to a real number.

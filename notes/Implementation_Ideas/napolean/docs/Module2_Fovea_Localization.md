# Module 2, Step 3 — Fovea Localization

> ## `fovea_vdens` — fixed, but it is a failure flag, not a feature
>
> **The bug.** It reported vessel density *at the chosen pixel*. The search
> maximises `centre-surround darkness − 3.0 × vessel density`, so the argmax
> always lands on a strictly zero-vessel pixel and the column was **identically
> 0.0 on every image** — structurally guaranteed, not measured.
>
> **The fix.** It now measures vessel fraction over the **foveal avascular zone**
> (500 µm = 34 px radius), which does not depend on the search penalty.
>
> **What it does now:** median **0.00**, max **27.97**, and under 0.5% of images
> are non-zero. A healthy FAZ genuinely has no vessels, so ~0 is the *correct*
> answer almost everywhere — but that makes the column near-constant and
> **useless as a graded feature**. Its real value is as a **mislocalisation
> flag**: `fovea_vdens > 0` means the localiser put the fovea somewhere
> vascular, i.e. probably wrong. Use it that way and nothing else.
>
> The earlier "vd 3.8% vs 14.5%" figure was measured on a *candidate region*,
> not at the final point — it does not describe this column.
>
> `fovea_od_dd` is the other check — but note it is constrained to 2.1–2.9 by the
> search annulus, so a value in range **is the constraint, not a validation**.

**Purpose:** find the fovea — the avascular pit at the centre of the macula.

**Code:** Python reference in the session scratchpad (`m2_fovea.py`,
`m2_fovea2.py`). Not yet in MATLAB.

**Status:** two rounds on 40 best-quality APTOS images. **Partially working** —
the avascularity test is strongly validated, the position is not.

---

## Contents

- [Why the fovea matters clinically](#why-the-fovea-matters-clinically)
- [What it inherits](#what-it-inherits)
- [The algorithm](#the-algorithm)
- [Validation without labels](#validation-without-labels)
- [Round 1 — the vessel penalty works, the position does not](#round-1--the-vessel-penalty-works-the-position-does-not)
- [Round 2 — centre-surround, and a circular result](#round-2--centre-surround-and-a-circular-result)
- [Recommendation](#recommendation)
- [The honest limitation](#the-honest-limitation)

---

## Why the fovea matters clinically

**Distance from the fovea sets urgency, independently of DR grade.**

Hard exudates within **500 µm (34 px at R=436)** of the fovea indicate
clinically significant macular oedema — an urgent referral even when the DR
grade itself is only moderate. A system that reports "exudates present" without
"exudates 0.4 DD from the fovea" is missing the decisive fact.

It also supplies the **OD–fovea axis**, which orients the quadrants for the
clinical 4-2-1 rule. [B]'s `splitRegions` uses frame axes as a stand-in because
it runs before any anatomy is known; clinical counting needs the anatomical axis.

---

## What it inherits

```
optic disc ──┬──► fovea position   (2.5 DD temporal, along the arcade)
vessels ─────┘         │
                       ├──► exudate-to-fovea distance  -> DME urgency
                       └──► OD-fovea axis -> quadrants -> 4-2-1 rule
```

**Fovea error = OD error + its own.** The OD currently has ~10% of estimates
pinned at its search boundary, so that uncertainty propagates here before the
fovea detector does anything at all.

---

## The algorithm

```
1. arcade axis   principal direction (PCA) of vessel pixels within 2 DD of the OD
2. search region annulus 2.1-2.9 DD from the OD centre,
                 within +/-40 deg of that axis
3. score         centre-surround darkness  -  lambda * vessel density
4. pick          argmax of the score inside the region
5. sanity        OD-fovea distance should be 2.2-2.8 DD
```

### Step 3 is the whole trick

```
score(p) = [ mean(annulus at p) - mean(core at p) ]  -  3.0 * vesselDensity(p)
           \_______________________________________/     \__________________/
                      centre-surround darkness              avascularity
```

The fovea is **dark** *and* **avascular**. Chasing darkness alone lands on
vessels, because vessels are the darkest things in the retina. The penalty term
is what separates "fovea" from "vessel shadow", and it is the single most
strongly validated part of this component — see round 1.

`lambda = 3.0`; core radius 40 px, surround 140 px.

### Why centre-surround rather than absolute darkness

Absolute darkness biases the search outward, because the retina genuinely
darkens toward the periphery. Centre-surround subtracts the local background,
so a smooth peripheral falloff adds nearly the same amount to both terms and
cancels.

> This is the **same construction that failed for the optic disc**. There the
> corruption was *localised glare*, which raises the core without raising the
> annulus, so it does not cancel. Here the corruption *is* a smooth field, so the
> invariance argument holds. **State what a measure is invariant to, then check
> that is what is actually corrupting your data.**

### Left/right eye ambiguity

The fovea is *temporal* to the disc, but which side that is depends on whether
the image is a left or right eye. **Do not assume a side** — search both
directions along the arcade axis and take whichever candidate is darker and more
avascular. The `±40°` cone is applied to the undirected axis, so both lobes are
searched.

---

## Validation without labels

APTOS has no fovea coordinates. Three checks:

| Check | Target | Why it is meaningful |
|---|---|---|
| **OD–fovea distance** | clusters at **2.5 DD** | anatomically fixed, so the distribution is a real test |
| **darkness** | > 0 | `(ring_mean − core_mean) / ring_sd` — is the spot actually dark? |
| **avascularity** | core ≪ ring | the fovea is avascular by definition |
| boundary pileup | ~0% | estimates at the search limit are clipped, not converged |

---

## Round 1 — the vessel penalty works, the position does not

40 best-quality images, absolute darkness, annulus 2.0–3.0 DD.

| Variant | med dist (DD) | in 2.2–2.8 | darkness | **vd core %** | vd ring % |
|---|---|---|---|---|---|
| **with vessel penalty** | 2.79 | 38% | 0.65 | **3.0** | 14.5 |
| no vessel penalty | 2.80 | 30% | 1.38 | **16.8** | 11.3 |

**The avascularity penalty is decisively validated.** Vessel density at the
found spot is **3.0% with** the penalty versus **16.8% without** — a 5.6×
difference. Without it the detector lands squarely on vessels.

Note the trade: darkness is *worse* with the penalty (0.65 vs 1.38), exactly as
expected, because the darkest spots available *are* vessels.

**But the position is wrong.** Median 2.79 DD against an anatomical 2.5, only
38% inside 2.2–2.8, and **28% sitting within 0.03 DD of the outer search
boundary** — the same clipping signature that hides ~10% of OD failures.

---

## Round 2 — centre-surround, and a circular result

| Variant | med DD | in 2.2–2.8 | at boundary | vd core % |
|---|---|---|---|---|
| R1 absolute, 2.0–3.0 | 2.79 | 38% | **28%** | 3.0 |
| CS, 2.0–3.0 | 2.66 | 35% | **18%** | 8.6 |
| **CS, 2.1–2.9** | **2.58** | **48%** | 22% | 3.8 |
| ~~CS, 2.2–2.8~~ | 2.51 | ~~100%~~ | 20% | 3.2 |
| CS, 2.0–3.0, ±25° | 2.70 | 35% | 15% | 7.9 |

**Centre-surround helped**: median moved 2.79 → 2.66 (toward the anatomical
2.5) and boundary pileup dropped 28% → 18%. The invariance argument held.

### The circular result — do not be fooled by it

`CS, 2.2–2.8` scores **100% inside 2.2–2.8**. That is meaningless: the search
region *is* 2.2–2.8, so every answer necessarily falls inside it. The automatic
ranking picked it as "BEST by anatomical agreement" and was wrong.

> This is the **third** circularity error in Module 2 — after calibrating vessel
> coverage to 11% then "validating" that coverage was 11%. **A constraint is not
> a result.** If the search region enforces the property you are testing for, the
> test measures nothing.

---

## Recommendation

```
1. optic disc first                              (r <= 0.60 R, RAW green)
2. vessels                                       (line L21 + len40 + bridging)
3. arcade axis = PCA of vessels within 2 DD of the OD
4. search: annulus 2.1-2.9 DD, +/-40 deg of the axis, BOTH lobes
5. score = centre-surround darkness - 3.0 * vessel density
6. report OD-fovea distance alongside the coordinate:
       outside 2.2-2.8 DD  =>  distrust this fovea
```

Measured: **median 2.58 DD, 48% inside 2.2–2.8, vessel density 3.8% at the
found spot** (against 14.5% in the surrounding ring).

---

## The honest limitation

**~20% of estimates still pin at the search boundary in every variant.** For a
fifth of images the score optimum lies outside the plausible annulus, which means
the detector is not finding the fovea on those — the anatomical prior is hiding
the failure rather than fixing it.

And only **48%** land inside the anatomical 2.2–2.8 DD window on a
non-circular measurement. That is not good enough to build DME urgency rules on.

**What would fix it:**

- **IDRiD sub-challenge C** provides fovea centre coordinates for **516 images**,
  turning every number above into a measured accuracy.
- Failing that, hand-marking ~60 APTOS foveae is an afternoon and would do the
  same job at smaller scale.

Until then, treat the fovea as **built but unreliable**, and do not ship a DME
rule based on exudate-to-fovea distance — that rule inherits the OD error, the
fovea error, and the exudate error simultaneously.

---

## Next

Microaneurysms — the long pole, and the component that unblocks functional
validation for vessels retroactively.

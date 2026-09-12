# Demonstration sets — six left/right pairs across the severity range

Six sets, each a left-eye and a right-eye fundus image, spanning ICDR grades 0-4
(set six is a second grade-4 pair). Images are copies of APTOS 2019 training
images; `sets_manifest.csv` records every id, grade, eye and the numbers the eye
call was made from.

| Set | Grade | Severity | Left eye | Right eye |
|---|---|---|---|---|
| one | 0 | No DR | `f02956bd7c50` | `e47770a2e5d1` |
| two | 1 | Mild NPDR | `19722bff5a09` | `77a9538b8362` |
| three | 2 | Moderate NPDR | `115e42dd6a81` | `61c2fbd16e38` |
| four | 3 | Severe NPDR | `4c60b10a3a6a` | `237c078d00fc` |
| five | 4 | Proliferative DR | `0243404e8a00` | `4dc2211a1c31` |
| six | 4 | Proliferative DR | `9e3510963315` | `c3d12a23f451` |

## Two things to be honest about

**The pairs are not real patients.** APTOS 2019 ships `id_code` and `diagnosis`
and nothing else — no patient identifier, and no way to tell which images belong
to the same person. Each set here pairs one left-eye and one right-eye image
*of the same grade* from different, unrelated patients. Do not present a set as
one patient's two eyes. (The 2015 EyePACS set does carry `<patient>_left` /
`<patient>_right` filenames, if genuine pairs are needed later.)

**The eye side is inferred, not labelled.** The optic disc sits nasal to the
fovea, so a disc to the right of the fovea means a right eye and to the left
means a left eye. Side was taken from this pipeline's own `od_x` vs `fovea_x`
(on the 872 px working grid), which reduces to which half of the frame the disc
falls in.

Every image chosen passed Stage 1 and has 200-357 px between disc and fovea, so
none is a marginal call. `one_grade0_left_f02956bd7c50` and
`one_grade0_right_e47770a2e5d1` were additionally confirmed by eye: the disc is
plainly left of the fovea in the first and right of it in the second. The other
ten were selected by the same rule but not individually inspected.

The disc localisation behind those coordinates is imperfect — see
[`MODULE3_RUN_RESULTS.md`](../../final_algorithms/matlab/MODULE3_RUN_RESULTS.md)
§3 — so re-check a set before putting it in front of a clinician.

## Files

```
sets/
  sets_manifest.csv          set, grade, eye, id_code, file, resolution, od_x, fovea_x, od_contrast
  one/   one_grade0_left_<id>.png     one_grade0_right_<id>.png
  two/   ... through six/
```

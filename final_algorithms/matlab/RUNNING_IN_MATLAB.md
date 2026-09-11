# Running the Stage 1 / Stage 2 pipeline in MATLAB

Command-by-command runbook for the MATLAB implementation in
[`final_algorithms/matlab/`](.), driven from VS Code with the **MATLAB extension
for Visual Studio Code** (MathWorks).

> **Nothing in this pipeline has been executed yet.** The code was written to
> spec and passed static checks only. Phase 0's exit criterion in
> [`Module3_Plan.md`](../../notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md)
> — *"runs on 20 images; every column filled; values in range"* — is what §4
> below is for. Expect to fix real errors on the first run.

---

## 0. Prerequisites

### 0.1 MATLAB release

**R2022a or newer.** The port calls `prctile(x, p, "Method", "inclusive")` to
match numpy's default percentile interpolation; the `"Method"` argument was
added in R2022a. On an older release every percentile threshold silently shifts.

Check:

```matlab
version('-release')
```

### 0.2 Required toolboxes

| Toolbox | Used for | Fails without it |
|---|---|---|
| **Image Processing Toolbox** | `imgaussfilt`, `imboxfilt`, `imfilter`, `imresize`, `imrotate`, `imdilate`, `strel`, `regionprops`, `bwconncomp`, `bwdist`, `labelmatrix`, `adapthisteq`, `fspecial` | everything |
| **Statistics and Machine Learning Toolbox** | `prctile` (every candidate threshold), `TreeBagger`/`predict` (step-5 lesion classifiers) | everything |
| **Deep Learning Toolbox** | Module 3's MLP (§6.2 of the plan) — *not yet implemented* | nothing yet |

Check what you have:

```matlab
ver
% or, specifically:
license('test', 'Image_Toolbox')
license('test', 'Statistics_Toolbox')
```

### 0.3 VS Code setup

1. Install the **MATLAB** extension by MathWorks from the Extensions panel.
2. Point it at your install if it doesn't autodetect — Settings → `MATLAB: Install Path`,
   e.g. `C:\Program Files\MATLAB\R2024b`.
3. Open the **repo root** as the workspace folder (`SIH_MathWorks_2026`), not a
   subfolder — the paths below are relative to it.
4. Open a MATLAB terminal: Command Palette (`Ctrl+Shift+P`) → **MATLAB: Open Command Window**.

All commands below are typed into that MATLAB command window.

### 0.4 The APTOS dataset (not in the repo)

The images are **not in the repo** — `data/` holds the two CSVs from the previous
implementation plus the Phase 1 worklist (§3.2), but no pixels. Download
*APTOS 2019 Blindness Detection* from Kaggle and unpack it so the layout is:

```
SIH_MathWorks_2026/
  aptos2019-blindness-detection/
    train.csv              # id_code, diagnosis
    train_images/
      000c1434d8d7.png
      ...
```

That exact folder name is the default both batch scripts expect. A different
location is fine — pass `AptosDir=` explicitly (§3).

> **Do not overwrite `data/aptos_train_module1_features.csv`.** It is the
> previous implementation's output and the batch script is written never to
> touch it.

---

## 1. Put the code on the MATLAB path

From the repo root:

```matlab
cd 'C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'
addpath('final_algorithms/matlab')
addpath('final_algorithms/matlab/stage1')
addpath('final_algorithms/matlab/stage2')
```

`extractModule3Features` adds `stage1/` and `stage2/` itself, so for the batch
run only the first `addpath` is strictly needed. Add all three when calling the
stage functions directly.

Verify the entry points resolve and nothing is shadowed:

```matlab
which extractStage1Features extractStage2Candidates stage2FeaturesFromCandidates -all
which stage2Columns runStage2 extractModule3Features
```

Each name must resolve to **exactly one** file. `stage1/` and `stage2/` sit on
the path together and share no filenames by design — if `-all` shows two hits
for any name, stop and resolve it before running anything.

To make this permanent across MATLAB sessions:

```matlab
savepath
```

---

## 2. Smoke-test on a single image

Do this before any batch run. It is the cheapest way to surface a typo.

### 2.1 Stage 1 alone

```matlab
imgPath = fullfile('aptos2019-blindness-detection', 'train_images', '000c1434d8d7.png');

[s1row, stage1Out] = extractStage1Features(imgPath, 0);

disp(s1row)                    % the 21 S1-01..S1-21 values
disp(stage1Out.status)         % "pass" | "fail"
size(stage1Out.image)          % Stage 1's output image (enhanced if borderline)
nnz(stage1Out.fov_mask)        % FOV pixel count
```

Sanity checks on the row: `megapixels` should match the file, `area_ratio_s1`
and `area_ratio_s2` should sit near 1.0, `black_region_pct` in the 15–50% band,
and `stage1_verdict` should be `"pass"` or `"borderline"`.

### 2.2 Stage 2 on Stage 1's output

`extractStage2Candidates` takes Stage 1's image and FOV mask — that is how the
batch script chains them.

```matlab
candidates = extractStage2Candidates(stage1Out.image, stage1Out.fov_mask);

disp(candidates.optic_disc)            % center_x, center_y, radius, contrast, confirmed
disp(candidates.fovea)                 % x, y, darkness_score, radial_brightness_increasing
disp(candidates.image_features)        % the 23 classifier-free S2 columns

% candidate counts per lesion class
structfun(@(c) size(c.features, 1), candidates.lesion_candidates)
```

Then turn candidates into the 45-column row (placeholder classifier, see the
warning in §3.1):

```matlab
s2row = stage2FeaturesFromCandidates(candidates);
disp(s2row)

cols = stage2Columns();
numel(cols)                            % must be 45
isequal(fieldnames(s2row)', cols)      % must be true (names AND order)
```

### 2.3 Coordinate sanity

`od_x/od_y/fovea_x/fovea_y` are reported in **0-based** pixel coordinates on the
872×872 working grid, so the MATLAB CSV lines up with the Python one. Both
points must land inside the retina:

```matlab
c = stage2Constants();
hypot(s2row.od_x - c.TARGET_R, s2row.od_y - c.TARGET_R) / c.TARGET_R     % < 0.95
hypot(s2row.fovea_x - c.TARGET_R, s2row.fovea_y - c.TARGET_R) / c.TARGET_R
s2row.od_fovea_dist_dd                  % expect roughly 1.2 - 3.0 disc diameters
```

If you index into a MATLAB array with these, add 1.

### 2.4 The standalone demonstration path

`runStage2` is the `Stage_2_CNN` demo entry point — it classifies inline and
returns the full report including vessel maps. It is **not** what Module 3 uses
(no CV-fold safety), but it is the quickest way to see everything at once:

```matlab
report = runStage2(stage1Out.image, stage1Out.fov_mask);

report.nv_score                        % fine-scale-excess neovascularisation score
report.quadrant_axis_deg               % OD->fovea axis
report.quadrants.counts                % raw per-quadrant haemorrhage counts
report.quadrants.four_two_one          % the re-derived 4-2-1 flag (>3, not >20)
report.nvd_nve.nvd_count
report.nvd_nve.nve_count

imshow(report.vessels.matched_filter_mask)
```

---

## 3. The batch run (Module 3, Phase 2)

`extractModule3Features` is the whole pipeline over the dataset. It chains
Stage 1 → Stage 2, writes the CSVs, and caches candidates for cross-validation.

### 3.1 Read this before running it

The lesion columns it writes (`haem_count`, `ma_count`, `hard_exudate_count`,
`cws_count` and everything derived from them) use the **placeholder classifier
rule**, not a fitted model. They are for QC only.

Module 3 must refit every lesion classifier **inside each CV fold** from the
cached `.mat` candidates and score only the held-out fold (`Module3_Plan.md`
§4.1, §6.1). Training on the counts in this CSV leaks the grade into the
features — that has already happened once in the previous implementation.

### 3.2 The 500-image worklist (Phase 1 — wired in by default)

`extractModule3Features` **picks up the pilot worklist automatically.** If
`data/module3_ids.txt` and `data/module3_splits.csv` exist, they are used with no
arguments; both are already generated, so this is enough:

```matlab
extractModule3Features()
```

It prints what it picked up, so you can confirm before it starts:

```
worklist: .../data/module3_ids.txt (500 images)
splits:   .../data/module3_splits.csv
```

If the ids file is ever missing, the run **warns** and falls back to all 3,662
images in `train.csv` — that warning is the signal to regenerate the list, not
something to ignore.

**The selection** ([full list](../MODULE3_500_IMAGE_LIST.md), CSV
[here](../module3_500_images.csv)), from
[`select_module3_ids.py`](../python/select_module3_ids.py):

| Grade | Severity | Images |
|---|---|---|
| 0 | No DR | 100 |
| 1 | Mild NPDR | 100 |
| 2 | Moderate NPDR | 100 |
| 3 | Severe NPDR | 100 |
| 4 | Proliferative DR | 100 |

- **Grade-balanced on purpose** (§5.1, D2) — at APTOS's true prevalence
  (49/10/27/5/8%) a 500-image draw would yield only ~26 severe and ~40
  proliferative cases, too few to learn grades 3 and 4.
- All 309 previously-extracted ids kept and tagged (`gate_sample` 250 /
  `sharpest70` 59, D3); the other 191 drawn `new` across sharpness deciles,
  seed 0.
- **75 test / 425 dev** — 15 and 85 per grade, with 5 grade-stratified folds of
  17 (§5.3).

That script picks filenames only and computes no features, so running it in
Python has no effect on the MATLAB feature values. Regenerate with a different
seed if you need to:

```powershell
python final_algorithms/python/select_module3_ids.py --seed 0
```

Overriding the default is still just a name-value argument (§3.5) — useful for
the smoke test below, or for a backfill re-run.

### 3.3 Start with 20 images

This is Phase 0's exit criterion — run it before committing to all 500. Take the
first 20 of the real worklist so the smoke test exercises the same images:

```matlab
ids = readlines(fullfile('data', 'module3_ids.txt'));
ids = ids(ids ~= "");
writelines(ids(1:20), fullfile('data', 'smoke_ids.txt'));

extractModule3Features(IdsFile="data/smoke_ids.txt")
```

Progress prints per image (`[i/n] <id> ok (1.2s)`), rejections print as
`rejected by Stage 1`, and errors print to stderr without stopping the run —
one bad image must not kill a 500-image job.

### 3.4 Check the output

```matlab
s2 = readtable(fullfile('data', 'module3_stage2_features.csv'));
head(s2)
sum(ismissing(s2), 1)          % must be all zeros - "no blanks" is the exit criterion
summary(s2)                     % check every column's range is plausible
```

Expect these files:

```
data/module3_stage1_features.csv    id_code + S1-01..S1-21
data/module3_stage2_features.csv    id_code + S2-01..S2-45
data/module3_dataset.csv            joined, plus the §2.3 carry columns
data/module3_candidates/<id>.mat    cached candidates, no classifier applied
```

### 3.5 The full run

The worklist is wired in (§3.2), so the pilot run over all 500 is just:

```matlab
extractModule3Features()
```

Options, all name-value:

| Option | Default | Purpose |
|---|---|---|
| `AptosDir` | `<repo>/aptos2019-blindness-detection` | dataset location |
| `OutDir` | `<repo>/data` | where the CSVs and candidate cache go |
| `IdsFile` | `<OutDir>/module3_ids.txt` if present, else all of `train.csv` | one `id_code` per line |
| `SplitsFile` | `<OutDir>/module3_splits.csv` if present, else none | `id_code, split, cv_fold, sample_source` |
| `Seed` | `0` | seeds Stage 1's random sampling (#3.1/#3.2 use random patches) |

Equivalent to the bare call, written out explicitly:

```matlab
extractModule3Features( ...
    IdsFile    = "data/module3_ids.txt", ...
    SplitsFile = "data/module3_splits.csv", ...
    Seed       = 0)
```

Run it in the background from VS Code's own terminal (not the MATLAB window) if
you want to keep working:

```powershell
matlab -batch "cd('C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'); addpath('final_algorithms/matlab'); extractModule3Features(IdsFile='data/module3_ids.txt')"
```

### 3.6 Stage 1 rejection tally

The run prints it at the end — record it, it is required by §4.4 of the plan:

```
Stage 1 rejections by grade (§4.4):
  grade 0: 4
  grade 4: 13
```

Rejected images get a Stage 1 row (so the tally is possible) but no Stage 2 row
and no dataset row.

### 3.7 Backfilling rejected images

A rejection means that grade no longer has its full 100. The Stage 1 gate could
not be pre-applied when the list was drawn — `sharp_ok` exists only for the old
309 rows — so some rejections are expected, and `data/module3_reserve.csv` holds
40 seeded replacements per grade, ranked.

Find what's short, take that many reserves of the same grade, and re-run only
those ids into the same output files:

```matlab
splits   = readtable(fullfile('data','module3_splits.csv'), TextType="string");
extracted = readtable(fullfile('data','module3_stage2_features.csv'), TextType="string");
rejected = setdiff(splits.id_code, extracted.id_code);

reserve = readtable(fullfile('data','module3_reserve.csv'), TextType="string");
for g = ["0" "1" "2" "3" "4"]
    nShort = sum(splits.grade(ismember(splits.id_code, rejected)) == g);
    fprintf('grade %s: %d short\n', g, nShort);
end
```

Then append the chosen reserve ids to `module3_splits.csv` (grade, split and
fold assigned to match what was lost), write them to a small ids file, and run
`extractModule3Features(IdsFile="data/backfill_ids.txt")`.

> **Grade 3 is the one to watch.** Only 192 usable ids exist for 100 picks, so
> if its rejection rate is high you may not reach 100 even after the reserve is
> exhausted. Report the shortfall rather than rebalancing the other grades down
> to match.

---

## 4. Using the cached candidates in a CV fold

This is the leakage-safe path Module 3 must use. `extractStage2Candidates` is
classifier-free, so the `.mat` cache is computed **once per image** and reused
in every fold; only step 5 is refitted.

```matlab
% --- inside one CV fold ---
% 1. fit lesion classifiers on TRAINING rows only
%    (features come from the cached candidates of training images)
maModel = TreeBagger(100, Xtrain_ma, Ytrain_ma, Method="classification");

% 2. score the HELD-OUT fold with them
clf = struct();
clf.ma          = struct('model', maModel,   'threshold', 0.5);
clf.haem        = struct('model', haemModel, 'threshold', 0.5);
% hard_exudate / cws omitted -> placeholder rule for those two

for i = 1:numel(heldOutIds)
    S = load(fullfile('data','module3_candidates', heldOutIds(i) + ".mat"));
    row = stage2FeaturesFromCandidates(S.candidates, clf);
    % ... collect row
end
```

`classifiers` is a struct with optional fields `ma`, `haem`, `hard_exudate`,
`cws`. Each is either a fitted model or a `struct('model', m, 'threshold', t)`.
Models are scored with `[~, score] = predict(model, X)`, **positive class in
column 2** — so `TreeBagger`, `fitcensemble` and `fitctree` all work. Any field
you leave out falls back to the placeholder rule.

### Column roles

Never feed EXCLUDE or QC columns to the grading network:

```matlab
[cols, roles] = stage2Columns();
modelInputs = cols(cellfun(@(c) strcmp(roles(c), 'MODEL'), cols));

[s1cols, s1roles] = stage1Columns();   % Stage 1 contributes NO model inputs (decision D7)
```

---

## 5. Troubleshooting

| Symptom | Cause |
|---|---|
| `Unrecognized function 'prctile'` | Statistics and Machine Learning Toolbox missing |
| `Too many input arguments` on `prctile` | MATLAB older than R2022a — `"Method","inclusive"` unsupported |
| `Undefined function 'imboxfilt'` | Image Processing Toolbox missing |
| `which -all` shows two hits for one name | a stray copy on the path shadowing `stage1/` or `stage2/` |
| `Cannot open ... for writing` | `data/` doesn't exist, or a CSV is open in Excel |
| Warning: *extracting ALL 3662 images* | `data/module3_ids.txt` missing — run `select_module3_ids.py` (§3.2). Stop the run; it is not the pilot sample |
| Run covers fewer than 500 images | Stage 1 rejected some — backfill from the reserve (§3.7) |
| Every image `rejected by Stage 1` | `fovMask` empty — usually a wrong `AptosDir` or non-fundus images |
| `od_fovea_dist_dd` implausible on most images | optic-disc localisation failing; it is a QC column for exactly this |

---

## 6. What this MATLAB run is, and is not

It is a faithful implementation of the algorithm specified in
[`Stage_1_CNN`](../../notes/Implementation_Ideas/Final_Ideas/Stage_1_CNN) and
[`Stage_2_CNN`](../../notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN) —
every formula, constant, threshold and decision rule matches the Python.

It is **not** a bit-reproduction of the Python program. MATLAB's Image
Processing Toolbox and OpenCV/scipy differ in the primitives underneath:
Frangi's Hessian derivatives, `regionprops` vs cv2 contour shape measures, disc
rasterization, and border padding. Consequences:

- **Pick one language and extract all 500 images with it.** Never mix
  MATLAB-extracted and Python-extracted rows in the same table.
- **A correlation measured on one does not transfer to the other.** Re-measure.

Module3_Plan.md §4.3 already requires every feature's within-resolution ρ to be
re-measured against the finalized algorithms, so this is work the plan expects
regardless of language.

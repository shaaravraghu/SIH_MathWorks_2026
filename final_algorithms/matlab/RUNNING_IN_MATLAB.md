# Running the Stage 1 / Stage 2 / Stage 3 pipeline in MATLAB

Command-by-command runbook for the MATLAB implementation in
[`final_algorithms/matlab/`](.), driven from VS Code with the **MATLAB extension
for Visual Studio Code** (MathWorks).

| Stage | What it does | Entry point |
|---|---|---|
| **1** | image-quality gate and enhancement → 21 QC/confidence columns | `extractStage1Features` |
| **2** | vessels, optic disc, fovea, lesions → 45 feature columns | `extractStage2Candidates` |
| **3** | DR grading (ICDR 0–4) and the referable decision | `runModule3` |
| — | batch Stage 1 → Stage 2 over the 500-image sample | `extractModule3Features` |

> **Execution status.** Verified on R2024a: every Stage 3 function runs, both
> Stage 3 training paths train, and Stage 2's filter/percentile path runs on a
> synthetic image. Stage 1 has been run end-to-end on one synthetic fundus.
> **Not yet run on real APTOS images** — the dataset isn't downloaded, so
> Phase 0's exit criterion in
> [`Module3_Plan.md`](../../notes/Implementation_Ideas/Final_Ideas/Module3_Plan.md)
> (*"runs on 20 images; every column filled; values in range"*) is still open;
> §3.3 is for that. Expect to fix some real errors on the first image run.

---

## 0. Prerequisites

### 0.1 MATLAB release

**R2021a or newer** for Stages 1–2 (`name=value` call syntax and `arguments`
blocks). **R2024a or newer** for Stage 3, which uses `trainnet`.

Verified working on **R2024a** — Stage 2's filter/percentile path and every
Stage 3 function have been executed on this machine.

```matlab
version('-release')
```

> **Percentiles do not use `prctile`.** Every percentile threshold goes through
> [`percentileLinear.m`](stage2/percentileLinear.m), which reproduces
> `numpy.percentile`'s default interpolation to ~5e-15. MATLAB's own `prctile`
> places the i-th of n sorted values at `100*(i-0.5)/n` while numpy uses
> `100*(i-1)/(n-1)`; on a 1,000-sample vector that is a 0.034 difference at the
> tails, which is exactly where these thresholds sit (p90/p92/p95/p96/p99).
> Don't "simplify" it back to `prctile`.

### 0.2 Required toolboxes

| Toolbox | Used for | Fails without it |
|---|---|---|
| **Image Processing Toolbox** | `imgaussfilt`, `imboxfilt`, `imfilter`, `imresize`, `imrotate`, `imdilate`, `strel`, `regionprops`, `bwconncomp`, `bwdist`, `labelmatrix`, `adapthisteq`, `fspecial` | Stage 1, Stage 2 |
| **Statistics and Machine Learning Toolbox** | `prctile` (every candidate threshold), `fitcensemble`/`fitrensemble`/`predict`, `tiedrank`, `fitglm` | Stage 1, Stage 2, Stage 3 |
| **Deep Learning Toolbox** | Stage 3's grading network (§6.2): `trainnet`, `dlnetwork`, `dlfeval`, `adamupdate` | **all of Stage 3** — grading is neural-network only, no tree fallback |

Check what you have:

```matlab
ver
% or, specifically:
license('test', 'Image_Toolbox')
license('test', 'Statistics_Toolbox')
```

### 0.3 VS Code setup

1. Install the **MATLAB** extension by MathWorks from the Extensions panel.
2. Point it at your install if it doesn't autodetect — Settings → `MATLAB: Install Path`:

   | OS | Typical path |
   |---|---|
   | Windows | `C:\Program Files\MATLAB\R2024b` |
   | Linux | `/usr/local/MATLAB/R2024b` |
   | macOS | `/Applications/MATLAB_R2024b.app` |

   On Linux, `readlink -f $(which matlab)` gives the real location if MATLAB is
   already on your `PATH` (strip the trailing `/bin/matlab`).
3. Open the **repo root** as the workspace folder (`SIH_MathWorks_2026`), not a
   subfolder — the paths below are relative to it.
4. Open a MATLAB terminal: Command Palette (`Ctrl+Shift+P`) → **MATLAB: Open Command Window**.

All commands below are typed into that MATLAB command window, except the shell
blocks marked **bash** / **PowerShell**.

### 0.3.0 Which MATLAB — desktop, CLI, VS Code, or Online

The `matlab` binary is the same in every case; only where you type matters.

| Way in | How | Best for |
|---|---|---|
| **Desktop app** | launch MATLAB, use its Command Window | interactive work, `imshow`, debugging |
| **CLI, interactive** | `matlab -nodesktop` (Windows) / `matlab -nodisplay` (Linux) | a terminal REPL with no GUI overhead |
| **CLI, one-shot** | `matlab -batch "…"` | the batch runs; headless, exits with a real status code |
| **VS Code terminal** | the same `matlab` commands | identical to the CLI — VS Code's terminal is just a terminal |
| **VS Code extension** | Command Palette → *MATLAB: Open Command Window* | Command Window without leaving the editor |
| **MATLAB Online** | matlab.mathworks.com | Stage 3 only — see the note below |

There is **no difference** between "the CLI" and "the CLI from VS Code". Pick
whichever terminal you like.

**For long runs prefer a `.m` file over a long `-batch` string.** Shell quoting
mangles nested quotes differently on PowerShell and bash, and a stripped quote
turns `stage3Columns("all")` into `stage3Columns(all)` — which fails with a
confusing `Not enough input arguments` from the builtin `all`. Writing the
commands to a script and calling `matlab -batch "run('myscript.m')"` sidesteps
it entirely. Note that `run` changes the working directory to the script's
folder, so use absolute paths inside the script or `cd` first.

**MATLAB Online**: the code runs, but the APTOS images (~9 GB) generally exceed
the free MATLAB Drive quota, and sessions idle-timeout during a 500-image
extraction. The practical split is **extract locally, grade online** — Stage 3
never touches a pixel, needing only `module3_dataset.csv` plus the candidate
cache (a few hundred MB). Upload a single zip and unzip it in MATLAB rather
than syncing thousands of files, and check what your licence gives you for
Drive space and compute hours before planning around it.

### 0.3.1 Linux specifics

Everything in this runbook works on Linux unchanged except where a shell block
gives both forms. Four things differ in practice:

- **The filesystem is case-sensitive.** MATLAB resolves a function by filename,
  so `stage2Columns.m` answers to `stage2Columns` but *not* `stage2columns`.
  On Windows the wrong case silently works, then breaks once the repo is cloned
  to Linux. All 130 `.m` files here were checked — every filename matches its
  `function` declaration and every cross-file call uses the exact case, so the
  tree is Linux-safe as written. This is a hazard to respect when **editing**,
  and the first thing to check if a function is "undefined" on Linux but fine
  on Windows.
- **Use forward slashes.** `fullfile` normalises them on both platforms, so
  every path in this document is already portable; only the absolute `cd` at
  §1 needs changing.
- **`matlab -batch` needs no display.** It runs headless by default, so no
  `xvfb` wrapper is needed for the batch runs. Only `imshow` (§2.4) wants a
  display — skip it over SSH, or save with `imwrite` instead.
- **`python` may not exist as a command.** Most distributions ship only
  `python3`. The shell blocks below use `python3` in the bash form.

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

With the Kaggle CLI, from the repo root:

```bash
# Linux / macOS
pip install kaggle                      # needs ~/.kaggle/kaggle.json
kaggle competitions download -c aptos2019-blindness-detection
unzip -q aptos2019-blindness-detection.zip -d aptos2019-blindness-detection
ls aptos2019-blindness-detection/train_images | wc -l     # expect 3662
```

```powershell
# Windows (PowerShell)
pip install kaggle
kaggle competitions download -c aptos2019-blindness-detection
Expand-Archive aptos2019-blindness-detection.zip -DestinationPath aptos2019-blindness-detection
(Get-ChildItem aptos2019-blindness-detection\train_images).Count   # expect 3662
```

> **Do not overwrite `data/aptos_train_module1_features.csv`.** It is the
> previous implementation's output and the batch script is written never to
> touch it.

---

## 1. Put the code on the MATLAB path

From the repo root — only the `cd` differs by platform:

```matlab
% Windows
cd 'C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'

% Linux / macOS
cd '~/SIH_MathWorks_2026'

% either platform, once you are in the right place:
addpath('final_algorithms/matlab')
addpath('final_algorithms/matlab/stage1')
addpath('final_algorithms/matlab/stage2')
addpath('final_algorithms/matlab/stage3')
```

`extractModule3Features` adds `stage1/` and `stage2/` itself and `runModule3`
adds `stage3/`, so for the batch runs only the first `addpath` is strictly
needed. Add all four when calling the stage functions directly.

If you started MATLAB from the repo root already, `cd` is unnecessary —
`pwd` will confirm.

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

imshow(report.vessels.matched_filter_mask)          % needs a display
imwrite(report.vessels.matched_filter_mask, 'vessels.png')   % headless / over SSH
```

`imshow` is the only command in this runbook that wants a graphical display.
Over SSH or under `matlab -batch`, use the `imwrite` line instead and copy the
file back (`scp`).

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
# Windows (PowerShell)
python final_algorithms\python\select_module3_ids.py --seed 0
```

```bash
# Linux / macOS
python3 final_algorithms/python/select_module3_ids.py --seed 0
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

Run it headless from VS Code's own terminal (not the MATLAB window) if you want
to keep working. `matlab -batch` needs no display on either platform:

```powershell
# Windows (PowerShell)
matlab -batch "cd('C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'); addpath('final_algorithms/matlab'); extractModule3Features()"

# ... and detached, with a log:
Start-Process matlab -ArgumentList '-batch', "cd('C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'); addpath('final_algorithms/matlab'); extractModule3Features()" -RedirectStandardOutput extract.log -NoNewWindow
```

```bash
# Linux / macOS
cd ~/SIH_MathWorks_2026
matlab -batch "addpath('final_algorithms/matlab'); extractModule3Features()"

# ... and detached, surviving logout, with a log:
nohup matlab -batch "addpath('final_algorithms/matlab'); extractModule3Features()" > extract.log 2>&1 &
tail -f extract.log          # watch progress
```

A 500-image run is long. On Linux, `tmux new -s extract` (or `screen`) before
launching is more robust than `nohup` if you are on SSH and want to reattach.

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

## 5. Stage 3 — grading (Module 3, Phases 4–8)

Stage 3 lives in [`stage3/`](stage3/) and turns the feature table into a DR
grade. Add it to the path (`runModule3` does this itself):

```matlab
addpath('final_algorithms/matlab/stage3')
```

### 5.1 What it needs first

`data/module3_dataset.csv` **and** `data/module3_candidates/*.mat`, both from
the §3 batch run. The candidate cache is not optional: Stage 3 refits the
lesion classifiers inside every fold, and that needs the per-candidate
features, not the summary row.

### 5.2 The runs

```matlab
runModule3()                % Phase 5: train the grading network (§6.2)
runModule3(Ablation=true)   % Phase 6: feature-block walk (§8)
runModule3(Test=true)       % Phases 7-8: freeze rules, then test ONCE
```

> **Grading is neural-network only.** The §6.3 RandomForest baseline has been
> removed at the project owner's instruction, overriding decision D4. See §5.5.

Headless, from a shell. The ablation refits five folds per block across seven
blocks, so it is the one worth detaching:

```bash
# Linux / macOS
cd ~/SIH_MathWorks_2026
matlab -batch "addpath('final_algorithms/matlab/stage3'); runModule3()"

nohup matlab -batch "addpath('final_algorithms/matlab/stage3'); runModule3(Ablation=true)" \
      > ablation.log 2>&1 &
tail -f ablation.log
```

```powershell
# Windows (PowerShell)
matlab -batch "cd('C:\Users\Sowjanya\Desktop\SIH_MathWorks_2026'); addpath('final_algorithms/matlab/stage3'); runModule3()"
```

> When you pass a string option (`Block`, `Calibration`), quoting differs
> between shells: bash needs `\"` inside the double-quoted `-batch` string,
> PowerShell needs `""`. Single quotes — `Block='6d_nv_split'` — sidestep it on
> both, since MATLAB accepts a char vector wherever `arguments` declares a
> string.

The Python equivalents (same plan, see §5.5 for where they differ):

```bash
python3 final_algorithms/python/run_module3.py
python3 final_algorithms/python/run_module3.py --ablation
python3 final_algorithms/python/run_module3.py --test
```

Options:

| Option | Default | Purpose |
|---|---|---|
| `Block` | `"6a_measured_core"` | Phase 6 block to run through; D5 starts at 6a |
| `AllFeatures` | `false` | all 38 inputs at once — D5 advises against |
| `Ablation` | `false` | walk every block in order |
| `Test` | `false` | evaluate the held-out 75 — **once** |
| `Calibration` | `"platt"` | or `"isotonic"` |
| `RefitLesions` | `true` | `false` is **leaky**; QC smoke runs only |

### 5.3 The two rules the code enforces for you

**Lesion classifiers are refitted inside every fold (§4.1).** They train on
weak labels taken from the image grade, so a classifier that scores an image it
trained on puts that image's grade into its own features. This already happened
once here — the previous microaneurysm classifier trained on 250 images and all
250 sat inside the 309-row table. `RefitLesions=false` skips the refit and is
leaky by construction; it prints a warning and exists only for fast smoke runs.

**Every metric is also reported within resolution strata (§4.3).** Pooled
figures partly measure which camera took the picture — even the Module 2
features alone identify the camera 66% of the time against a 16.7% chance
baseline. `runModule3` prints the within-resolution number and marks it as the
honest one; the Phase 6 ablation keeps a block only if *that* number improves.

### 5.4 Reading the output

```
  QWK pooled            0.7821
  QWK within resolution 0.7503   <- the honest number (§4.3)
  referable sens/spec   0.902 / 0.741
  grade-4 recall        0.267   <- reported on its own line (§8)
```

Three things the plan tells you to expect rather than treat as bugs:

- **Grade-4 recall will likely be poor.** The previous model predicted grade 4
  for 3 of 61 true grade-4 images. The NV split (S2-14/15) and the 4-2-1
  composite (S2-40) exist to fix that — report it on its own line either way.
- **Specificity at 90% sensitivity may miss the 85% target.** That target
  belongs to the fused system; features alone previously reached 75.4%.
- **There is no baseline to compare against.** The forest D4 made the network
  beat has been removed, so a QWK of 0.75 cannot be judged good or bad from
  inside this pipeline. On 309 rows the forest scored 0.779 within resolution
  strata against the MLP's 0.753 — an informal reference point worth keeping.

### 5.5 The network, and the removed baseline

**Grading is neural-network only.** §6.3 and decision D4 make a RandomForest the
required baseline the network has to beat within resolution strata; that
baseline has been **removed at the project owner's instruction**. The plan
document still says otherwise — this runbook is the current decision.

What it costs, plainly: on the previous implementation's 309 rows the forest beat
the MLP within resolution strata (referable AUC **0.879 vs 0.813**, QWK **0.779
vs 0.753**), even though pooled AUC ranked them the other way round. Phase 5 now
produces the network's numbers with nothing to judge them against.

The removal covers the **grading model only**. The lesion *candidate* classifier
— step 5 of Stage 2's five-step pipeline, in
[`fitLesionClassifiers.m`](stage3/fitLesionClassifiers.m) — still uses a bagged
tree ensemble. That is a separate component, the notes specify no neural network
for it, and removing it would break lesion detection entirely.

**The MATLAB network is the plan's architecture; the Python one is not.**
[`fitGradingMlp.m`](stage3/fitGradingMlp.m) implements §6.2 as written — dropout
0.3 on both hidden layers, He initialisation, and the §6.2.2 class-weighted MSE
via a custom `dlnetwork` loop when the weights aren't flat (both paths verified
to run, with the custom loop triggering correctly on an uneven class mix).
scikit-learn's `MLPRegressor` has no dropout layer, no He initialiser and no
per-row sample weights, so the Python version documents all three as deviations.
With the forest gone there is no longer a model that matches closely across the
two languages — prefer the MATLAB one for any reported result.

---

## 6. Troubleshooting

| Symptom | Cause |
|---|---|
| `Unrecognized function 'percentileLinear'` | `stage2/` not on the path — Stage 3 needs it too (§0.1) |
| `Method must be 'exact' or 'approximate'` | something reintroduced `prctile(...,"Method","inclusive")`, which is not valid MATLAB — use `percentileLinear` (§0.1) |
| `Undefined function 'imboxfilt'` | Image Processing Toolbox missing |
| `Not enough input arguments` from a builtin like `all` | shell quoting ate the quotes around a `-batch` string argument — use single quotes inside, or put the commands in a `.m` file and `run` it (§3.5) |
| `Undefined function 'trainnet'` | Deep Learning Toolbox missing, or MATLAB older than R2024a. Stage 3 has no tree fallback — it cannot run without it |
| `which -all` shows two hits for one name | a stray copy on the path shadowing `stage1/`, `stage2/` or `stage3/` |
| `Cannot open ... for writing` | `data/` doesn't exist, or a CSV is open in Excel |
| Warning: *extracting ALL 3662 images* | `data/module3_ids.txt` missing — run `select_module3_ids.py` (§3.2). Stop the run; it is not the pilot sample |
| Run covers fewer than 500 images | Stage 1 rejected some — backfill from the reserve (§3.7) |
| Every image `rejected by Stage 1` | `fovMask` empty — usually a wrong `AptosDir` or non-fundus images |
| `od_fovea_dist_dd` implausible on most images | optic-disc localisation failing; it is a QC column for exactly this |

**Linux-specific**

| Symptom | Cause |
|---|---|
| `Undefined function` on Linux for something that works on Windows | **filename case.** The Linux filesystem is case-sensitive; MATLAB resolves functions by exact filename (§0.3.1) |
| `python: command not found` | use `python3` — most distributions ship no bare `python` |
| `matlab: command not found` | not on `PATH`. Use the full path, or `sudo ln -s /usr/local/MATLAB/R2024b/bin/matlab /usr/local/bin/matlab` |
| `imshow` errors or hangs over SSH | no display. Skip §2.4's `imshow`, or write the image with `imwrite` and copy it back |
| Background run dies at logout | use `nohup ... &`, or `tmux`/`screen` (§3.5) |
| `Error using load ... not found` in Stage 3 | candidate cache path case, or the Phase 2 run wrote to a different `OutDir` |
| `Permission denied` writing to `data/` | repo cloned as root, or a read-only mount — `chown -R $USER:$USER .` |

---

## 7. What this MATLAB run is, and is not

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

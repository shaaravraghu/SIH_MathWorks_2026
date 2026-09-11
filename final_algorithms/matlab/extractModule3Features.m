function extractModule3Features(options)
%EXTRACTMODULE3FEATURES Batch Module 3 feature extraction over APTOS (Module3_Plan.md §5.2, Phase 2).
%
% Writes, and never overwrites data/aptos_train_module1_features.csv:
%   data/module3_stage1_features.csv   id_code + S1-01 .. S1-21
%   data/module3_stage2_features.csv   id_code + S2-01 .. S2-45
%   data/module3_dataset.csv           join on id_code, plus the §2.3 columns
%   data/module3_candidates/<id>.mat   Stage 2 candidates, no classifier applied
%
% The lesion columns written here use the PLACEHOLDER classifier rule and are
% for QC only. Module 3 must refit every lesion classifier inside each CV fold
% from the cached candidates and score only the held-out fold (§4.1, §6.1).
% Training on these counts leaks the grade into the features.
%
% Images Stage 1 rejects get a Stage 1 row (for the §4.4 per-grade rejection
% tally) but no Stage 2 row and no dataset row.
%
% Example:
%   extractModule3Features(IdsFile="data/module3_ids.txt", SplitsFile="data/module3_splits.csv")

arguments
    options.AptosDir (1,1) string = ""
    options.OutDir (1,1) string = ""
    options.IdsFile (1,1) string = ""
    options.SplitsFile (1,1) string = ""
    options.Seed (1,1) double = 0
end

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'stage1'), fullfile(here, 'stage2'));
repo = fileparts(fileparts(here));
if options.AptosDir == "", options.AptosDir = fullfile(repo, "aptos2019-blindness-detection"); end
if options.OutDir == "", options.OutDir = fullfile(repo, "data"); end

% Phase 1 worklist (§5.1, §5.3). Default to the 500-image pilot sample when it
% is present, so a bare extractModule3Features() extracts the grade-balanced
% pilot set rather than silently sweeping all 3,662 APTOS training images.
% Regenerate the list with final_algorithms/python/select_module3_ids.py.
if options.IdsFile == ""
    defaultIds = fullfile(options.OutDir, "module3_ids.txt");
    if isfile(defaultIds), options.IdsFile = defaultIds; end
end
if options.SplitsFile == ""
    defaultSplits = fullfile(options.OutDir, "module3_splits.csv");
    if isfile(defaultSplits), options.SplitsFile = defaultSplits; end
end

% §2.3: carried in the CSV, never used as features. `resolution` is for
% stratification only; the network must never see it.
DATASET_COLUMNS = {'id_code', 'diagnosis', 'split', 'cv_fold', 'resolution', 'sample_source'};
s1Cols = stage1Columns();
s2Cols = stage2Columns();

trainCsv = fullfile(options.AptosDir, "train.csv");
importOpts = detectImportOptions(trainCsv);
% Some APTOS ids (e.g. "1e3...") would otherwise parse as numbers.
importOpts = setvartype(importOpts, 'id_code', 'string');
train = readtable(trainCsv, importOpts);
labels = containers.Map(cellstr(train.id_code), num2cell(train.diagnosis));

if options.IdsFile ~= ""
    ids = strtrim(readlines(options.IdsFile));
    ids = ids(ids ~= "");
    fprintf('worklist: %s (%d images)\n', options.IdsFile, numel(ids));
else
    ids = train.id_code;
    warning('extractModule3Features:noWorklist', ...
        ['No ids file and no %s -- extracting ALL %d images in train.csv, not the ' ...
         '500-image pilot sample. Run final_algorithms/python/select_module3_ids.py first.'], ...
        fullfile(options.OutDir, "module3_ids.txt"), numel(ids));
end
splits = readSplits(options.SplitsFile);
if options.SplitsFile ~= ""
    fprintf('splits:   %s\n', options.SplitsFile);
end

cacheDir = fullfile(options.OutDir, "module3_candidates");
if ~isfolder(cacheDir), mkdir(cacheDir); end

f1 = openCsv(fullfile(options.OutDir, "module3_stage1_features.csv"), [{'id_code'}, s1Cols]);
f2 = openCsv(fullfile(options.OutDir, "module3_stage2_features.csv"), [{'id_code'}, s2Cols]);
f3 = openCsv(fullfile(options.OutDir, "module3_dataset.csv"), [DATASET_COLUMNS, s1Cols, s2Cols]);
closer = onCleanup(@() cellfun(@fclose, {f1, f2, f3}));

rejectedByGrade = containers.Map('KeyType', 'char', 'ValueType', 'double');
n = numel(ids);
for i = 1:n
    idCode = char(ids(i));
    t0 = tic;
    try
        image = loadRgb(fullfile(options.AptosDir, "train_images", [idCode '.png']));
        [s1, stage1Out] = extractStage1Features(image, options.Seed);
        writeRow(f1, {idCode}, s1, s1Cols);

        if strcmp(string(s1.stage1_verdict), "fail")
            grade = gradeKey(labels, idCode);
            if isKey(rejectedByGrade, grade)
                rejectedByGrade(grade) = rejectedByGrade(grade) + 1;
            else
                rejectedByGrade(grade) = 1;
            end
            fprintf('[%d/%d] %s rejected by Stage 1\n', i, n, idCode);
            continue
        end

        candidates = extractStage2Candidates(stage1Out.image, stage1Out.fov_mask);
        save(fullfile(cacheDir, [idCode '.mat']), 'candidates');
        s2 = stage2FeaturesFromCandidates(candidates);
        writeRow(f2, {idCode}, s2, s2Cols);

        split = struct('split', "", 'cv_fold', "", 'sample_source', "");
        if isKey(splits, idCode), split = splits(idCode); end
        lead = {idCode, gradeKey(labels, idCode), char(split.split), char(split.cv_fold), ...
                sprintf('%dx%d', size(image, 2), size(image, 1)), char(split.sample_source)};
        writeRow(f3, lead, mergeStructs(s1, s2), [s1Cols, s2Cols]);
        fprintf('[%d/%d] %s ok (%.1fs)\n', i, n, idCode, toc(t0));
    catch err  % one bad image must not stop a 500-image run
        fprintf(2, '[%d/%d] %s ERROR %s\n', i, n, idCode, err.message);
    end
end

fprintf('Stage 1 rejections by grade (§4.4):\n');
grades = keys(rejectedByGrade);
for k = 1:numel(grades)
    fprintf('  grade %s: %d\n', grades{k}, rejectedByGrade(grades{k}));
end
end


function fid = openCsv(path, columns)
fid = fopen(path, 'w');
if fid < 0
    error('extractModule3Features:open', 'Cannot open %s for writing.', path);
end
fprintf(fid, '%s\n', strjoin(columns, ','));
end


function writeRow(fid, lead, row, columns)
values = cellfun(@(c) formatValue(row.(c)), columns, 'UniformOutput', false);
fprintf(fid, '%s\n', strjoin([lead, values], ','));
end


function txt = formatValue(v)
if ischar(v) || isstring(v)
    txt = char(v);
elseif isempty(v)
    txt = '';
elseif islogical(v)
    txt = sprintf('%d', v);
else
    txt = sprintf('%.10g', v);
end
end


function out = mergeStructs(a, b)
out = a;
names = fieldnames(b);
for k = 1:numel(names)
    out.(names{k}) = b.(names{k});
end
end


function key = gradeKey(labels, idCode)
if isKey(labels, idCode)
    key = sprintf('%d', labels(idCode));
else
    key = '?';
end
end


function splits = readSplits(path)
splits = containers.Map('KeyType', 'char', 'ValueType', 'any');
if path == ""
    return
end
importOpts = detectImportOptions(path);
importOpts = setvartype(importOpts, importOpts.VariableNames, 'string');
t = readtable(path, importOpts);
for k = 1:height(t)
    splits(char(t.id_code(k))) = struct('split', t.split(k), 'cv_fold', t.cv_fold(k), ...
                                        'sample_source', t.sample_source(k));
end
end

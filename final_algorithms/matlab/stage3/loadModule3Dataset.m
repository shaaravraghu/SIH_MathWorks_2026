function data = loadModule3Dataset(path)
%LOADMODULE3DATASET Loads data/module3_dataset.csv (Phase 2 output) and
%   exposes the §5.3 splits/folds and the §4.3 resolution strata.
%
%   The lesion columns in that CSV came from the PLACEHOLDER classifier and
%   are QC only -- Stage 3 recomputes them per fold from the cached
%   candidates (see recomputeLesionColumns.m). They are loaded anyway
%   because they are what the Phase 3 QC report measures, and what a
%   knowingly-leaky RefitLesions=false smoke run reuses.
%
%   data: struct with fields
%     table        - the full table
%     ids          - string array of id_code
%     grades       - double vector (diagnosis)
%     split        - string array ("dev" | "test")
%     cv_fold      - string array ("0".."4", "" for test rows)
%     resolution   - string array (§4.3 strata; NEVER a feature)

if ~isfile(path)
    error('loadModule3Dataset:notFound', ...
        '%s not found -- run the Phase 2 extraction first.', path);
end

opts = detectImportOptions(path);
% APTOS ids like "1e3..." would otherwise parse as numbers.
textCols = intersect({'id_code', 'split', 'cv_fold', 'resolution', 'sample_source', ...
                      'stage1_verdict'}, opts.VariableNames);
opts = setvartype(opts, textCols, 'string');
t = readtable(path, opts);

data = struct();
data.table = t;
data.ids = string(t.id_code);
data.grades = double(t.diagnosis);
data.split = string(t.split);
data.cv_fold = string(t.cv_fold);
if ismember('resolution', t.Properties.VariableNames)
    data.resolution = string(t.resolution);
else
    data.resolution = repmat("", height(t), 1);
end
end

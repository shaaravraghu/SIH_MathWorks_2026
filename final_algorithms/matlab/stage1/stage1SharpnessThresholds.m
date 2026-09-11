function t = stage1SharpnessThresholds(imageSize)
%STAGE1SHARPNESSTHRESHOLDS #3 fail/borderline thresholds for one image resolution.
%   The notes pin no numeric thresholds for #3.1-#3.4, and a single global
%   cut-off acts as a camera filter: within one camera sharpness does not
%   track DR grade, but camera does, so a global floor rejects sick patients
%   more often (Stage_1_CNN_Proposed_Changes.md M1). The thresholds are
%   therefore per-resolution percentiles, read from
%   stage1_sharpness_thresholds.csv (written by calibrateStage1Thresholds).
%   A resolution absent from the table uses its "pooled" row; with no table
%   at all the original placeholder constants apply.
%
%   imageSize: size(gray), i.e. [height, width, ...].

persistent cache cacheStamp

PLACEHOLDERS = struct( ...
    'brenner_fail', 50.0, ...
    'lap_fail', 0.0015, 'lap_borderline', 0.0030, ...
    'tenengrad_fail', 0.02, 'tenengrad_borderline', 0.05, ...
    'region_min_fail', 0.0010, 'region_min_borderline', 0.0020);

path = fullfile(fileparts(mfilename('fullpath')), 'stage1_sharpness_thresholds.csv');
info = dir(path);
if isempty(info)
    t = PLACEHOLDERS;
    return;
end
if isempty(cache) || cacheStamp ~= info.datenum
    opts = detectImportOptions(path);
    opts = setvartype(opts, 'resolution', 'string');
    cache = readtable(path, opts);
    cacheStamp = info.datenum;
end

key = sprintf('%dx%d', imageSize(2), imageSize(1));
idx = find(cache.resolution == key, 1);
if isempty(idx)
    idx = find(cache.resolution == "pooled", 1);
end
if isempty(idx)
    t = PLACEHOLDERS;
    return;
end

names = fieldnames(PLACEHOLDERS);
t = struct();
for k = 1:numel(names)
    t.(names{k}) = cache.(names{k})(idx);
end
end

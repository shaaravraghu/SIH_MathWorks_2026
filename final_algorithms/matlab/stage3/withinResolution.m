function result = withinResolution(metricFn, resolutions, arrays, minRows)
%WITHINRESOLUTION §4.3: compute a metric INSIDE one resolution at a time,
%   then average across strata. This is the honest number.
%
%   The pooled equivalent rewards a model for learning which camera took the
%   picture: even the Module 2 features alone identify the camera 66% of the
%   time against a 16.7% chance baseline, and pooled referable AUC 0.931 fell
%   to 0.881 within strata on the previous implementation.
%
%   metricFn: function handle taking the same number of vectors as numel(arrays)
%   arrays:   cell array of column vectors, all the same length
%   minRows:  strata smaller than this are SKIPPED and reported, rather than
%             contributing a metric computed on noise (default 10)
%
%   result: struct with mean, per_stratum (containers.Map), skipped (Map).

if nargin < 4 || isempty(minRows), minRows = 10; end

resolutions = string(resolutions(:));
strata = unique(resolutions);

perStratum = containers.Map('KeyType', 'char', 'ValueType', 'double');
skipped = containers.Map('KeyType', 'char', 'ValueType', 'double');

for k = 1:numel(strata)
    mask = resolutions == strata(k);
    n = sum(mask);
    if n < minRows
        skipped(char(strata(k))) = n;
        continue;
    end
    subset = cell(size(arrays));
    for a = 1:numel(arrays)
        column = arrays{a};
        subset{a} = column(mask);
    end
    value = metricFn(subset{:});
    if ~isempty(value) && ~isnan(value)
        perStratum(char(strata(k))) = value;
    end
end

if perStratum.Count > 0
    meanValue = mean(cell2mat(values(perStratum)));
else
    meanValue = NaN;
end
result = struct('mean', meanValue, 'per_stratum', perStratum, 'skipped', skipped);
end

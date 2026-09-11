function X = datasetMatrix(data, rowMask, featureNames, overrides)
%DATASETMATRIX Feature matrix in featureNames order for the selected rows.
%
%   overrides: optional containers.Map from id_code to a struct of column
%   values, used to substitute the per-fold recomputed lesion columns (§6.1
%   step 2) WITHOUT mutating the loaded table. An id absent from the map
%   keeps its extracted value.

if nargin < 4, overrides = containers.Map('KeyType', 'char', 'ValueType', 'any'); end

idx = find(rowMask);
X = zeros(numel(idx), numel(featureNames));
ids = data.ids;

for r = 1:numel(idx)
    row = idx(r);
    idCode = char(ids(row));
    hasOverride = isKey(overrides, idCode);
    if hasOverride, over = overrides(idCode); end
    for c = 1:numel(featureNames)
        name = featureNames{c};
        if hasOverride && isfield(over, name)
            X(r, c) = toNumeric(over.(name));
        elseif ismember(name, data.table.Properties.VariableNames)
            X(r, c) = toNumeric(data.table.(name)(row));
        else
            X(r, c) = 0;
        end
    end
end
end


function v = toNumeric(value)
if isnumeric(value) || islogical(value)
    v = double(value);
elseif isstring(value) || ischar(value)
    text = lower(strtrim(string(value)));
    if text == "" || ismissing(text), v = 0;
    elseif ismember(text, ["pass", "false", "no"]), v = 0;
    elseif ismember(text, ["borderline", "true", "yes"]), v = 1;
    elseif text == "fail", v = 2;
    else
        v = str2double(text);
    end
else
    v = 0;
end
if isnan(v) || isinf(v), v = 0; end
end

function [overrides, missing] = recomputeLesionColumns(cacheDir, ids, classifiers, verbose)
%RECOMPUTELESIONCOLUMNS §6.1 step 2: re-derive the classifier-dependent
%   Stage 2 columns for every image in a fold, using THAT fold's freshly
%   fitted lesion classifiers.
%
%   Only the ~20 lesion columns change between folds. Everything else in the
%   Stage 2 row (vessels, calibre, NV, OD, fovea) is classifier-free and
%   identical across folds, which is exactly why extractStage2Candidates
%   caches it once per image (§4.1).
%
%   overrides: containers.Map from id_code to a struct of recomputed column
%   values, for datasetMatrix(). An id with no cached candidates is omitted,
%   so its original (placeholder-rule) row survives -- `missing` lists those.

if nargin < 4 || isempty(verbose), verbose = false; end

overrides = containers.Map('KeyType', 'char', 'ValueType', 'any');
missing = strings(0, 1);

for i = 1:numel(ids)
    idCode = char(ids(i));
    candidates = loadCandidates(cacheDir, idCode);
    if isempty(candidates)
        missing(end+1, 1) = string(idCode); %#ok<AGROW>
        continue;
    end
    overrides(idCode) = stage2FeaturesFromCandidates(candidates, classifiers);
end

if verbose && ~isempty(missing)
    fprintf(['    WARNING: %d ids had no cached candidates and kept their ' ...
             'placeholder-rule lesion columns\n'], numel(missing));
end
end

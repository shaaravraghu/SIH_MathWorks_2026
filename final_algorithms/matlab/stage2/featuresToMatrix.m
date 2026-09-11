function [matrix, names] = featuresToMatrix(featureStructs)
%FEATURESTOMATRIX Stacks a cell array of per-candidate feature structs (as
%   returned by extractCandidateFeatures) into an N x F double matrix, in
%   lesionFeatureOrder() column order. NaN/+-Inf are replaced with 0, as in
%   Python's np.nan_to_num. Mirrors lesion_features.py features_to_matrix.

names = lesionFeatureOrder();
n = numel(featureStructs);
f = numel(names);
matrix = zeros(n, f);
for i = 1:n
    fd = featureStructs{i};
    for j = 1:f
        name = names{j};
        if isfield(fd, name)
            v = fd.(name);
        else
            v = NaN;
        end
        if isnan(v) || isinf(v)
            v = 0.0;
        end
        matrix(i, j) = v;
    end
end
end

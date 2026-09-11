function packed = featuresForCandidates(candidates, workRgbU8, green255, vesselMask, opticDisc, fovea, vesselDistTransform)
%FEATURESFORCANDIDATES Runs extractCandidateFeatures over a candidate list
%   and packs the result into the cacheable {features, feature_names,
%   centroids, areas} form used by Stage2Candidates.lesion_candidates.
%   Mirrors features.py _features_for_candidates.

m = stage2Masks();
n = numel(candidates);
feats = cell(1, n);
for i = 1:n
    feats{i} = extractCandidateFeatures(workRgbU8, green255, candidates{i}, vesselMask, ...
        opticDisc, fovea, m.MEASUREMENT_MASK, vesselDistTransform);
end
if n > 0
    [matrix, names] = featuresToMatrix(feats);
else
    names = lesionFeatureOrder();
    matrix = zeros(0, numel(names));
end

centroids = zeros(n, 2);
areas = zeros(n, 1);
for i = 1:n
    centroids(i, :) = candidates{i}.centroid;
    areas(i) = candidates{i}.area_px;
end

packed = struct('features', matrix, 'feature_names', {names}, 'centroids', centroids, 'areas', areas);
end

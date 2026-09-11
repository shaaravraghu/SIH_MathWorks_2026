function model = fitGradingForest(X, y, weights)
%FITGRADINGFOREST §6.3's REQUIRED baseline: a bagged regression ensemble.
%
%   A neural network does not automatically beat a tree model on 500 rows of
%   tabular data. On the previous implementation's 309 rows the forest won
%   decisively WITHIN resolution strata -- referable AUC 0.879 vs the MLP's
%   0.813, QWK 0.779 vs 0.753 -- even though pooled AUC ranked them the other
%   way round. Pooled AUC rewards learning the camera (§4.3).
%
%   The network is adopted ONLY if it beats this within resolution (D4).
%
%   Trained as REGRESSION on the ordinal grade, rounded later at fitted
%   cutpoints (D6), not as 5-class classification: a softmax treats a 0->4
%   miss as no worse than 0->1.

FOREST_N_LEARNERS = 500;
FOREST_MIN_LEAF = 3;

if nargin < 3 || isempty(weights)
    weights = ones(size(y(:)));
end

template = templateTree('MinLeafSize', FOREST_MIN_LEAF);
model = fitrensemble(X, y(:), 'Method', 'Bag', ...
    'NumLearningCycles', FOREST_N_LEARNERS, 'Learners', template, ...
    'Weights', weights(:));
end

function kappa = quadraticWeightedKappa(trueGrades, predGrades, nClasses)
%QUADRATICWEIGHTEDKAPPA §7.1's model-selection metric.
%   Penalises errors by SQUARED distance, so a 0->4 miss costs 16x a 0->1
%   miss. This is the right metric for an ordinal scale: predicting 4 for a
%   true 0 is far worse than predicting 1.

if nargin < 3 || isempty(nClasses), nClasses = 5; end

t = min(max(round(trueGrades(:)), 0), nClasses - 1);
p = min(max(round(predGrades(:)), 0), nClasses - 1);
if isempty(t), kappa = NaN; return; end

observed = double(gradeConfusionMatrix(t, p, nClasses));

weights = zeros(nClasses);
for i = 1:nClasses
    for j = 1:nClasses
        weights(i, j) = ((i - j) ^ 2) / ((nClasses - 1) ^ 2);
    end
end

histTrue = accumarray(t + 1, 1, [nClasses, 1]);
histPred = accumarray(p + 1, 1, [nClasses, 1]);
expected = histTrue * histPred';

obsSum = sum(observed(:)); expSum = sum(expected(:));
if obsSum == 0 || expSum == 0, kappa = NaN; return; end
observed = observed / obsSum;
expected = expected / expSum;

denominator = sum(sum(weights .* expected));
if denominator == 0, kappa = NaN; return; end
kappa = 1 - sum(sum(weights .* observed)) / denominator;
end

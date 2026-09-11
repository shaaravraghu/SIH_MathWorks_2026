function point = findOperatingPoint(labels, scores, targetSensitivity)
%FINDOPERATINGPOINT §7.2: walk the ROC curve, find the threshold where
%   referable sensitivity first reaches the target, and read off the
%   specificity there.
%
%   FREEZE the returned threshold and apply it to the test set exactly ONCE.
%   Choosing it on the test set is the most common accidental cheat in this
%   field, which is why this function only ever sees out-of-fold predictions.
%
%   point: struct with threshold, sensitivity, specificity, reached_target.
%   §8's honest target is 0.90 sensitivity with specificity REPORTED WHATEVER
%   IT IS -- the 85% specificity goal belongs to the fused system, and the
%   previous features reached only 75.4%.

if nargin < 3 || isempty(targetSensitivity), targetSensitivity = 0.90; end

labels = double(labels(:) > 0);
scores = double(scores(:));
point = struct('threshold', NaN, 'sensitivity', NaN, 'specificity', NaN, ...
               'reached_target', false);
if isempty(scores) || sum(labels) == 0
    return;
end

% Descending: the first threshold that clears the bar is the most specific one.
candidates = sort(unique(scores), 'descend');
for k = 1:numel(candidates)
    [sens, spec] = sensitivitySpecificity(labels, scores, candidates(k));
    if sens >= targetSensitivity
        point = struct('threshold', candidates(k), 'sensitivity', sens, ...
                       'specificity', spec, 'reached_target', true);
        return;
    end
end

threshold = min(scores);
[sens, spec] = sensitivitySpecificity(labels, scores, threshold);
point = struct('threshold', threshold, 'sensitivity', sens, ...
               'specificity', spec, 'reached_target', false);
end

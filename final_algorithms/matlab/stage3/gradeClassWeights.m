function [weights, rounded, isFlat] = gradeClassWeights(grades)
%GRADECLASSWEIGHTS §6.2.2: inverse-frequency weight per (rounded) grade,
%   computed from the ACTUAL training-fold composition, normalised so the
%   mean weight is 1:
%
%       w_c = (N_train / 5) / n_c
%       loss = (1/N) * sum_i w_{grade(i)} * (score_i - grade_i)^2
%
%   n_c comes from what the fold actually contains, NOT hard-coded to 85 --
%   grade-stratified folds should land near 68 per grade, but the weights
%   must track reality.
%
%   isFlat: §6.2.2's check -- plain MSE is permitted only when every weight
%   falls within about 0.9-1.1, which a 100-per-grade balanced sample should
%   give. When it is false the weighted loss is required.

rounded = min(max(round(double(grades(:))), 0), 4);
counts = accumarray(rounded + 1, 1, [5, 1]);
nTrain = numel(rounded);

weights = ones(5, 1);
for c = 1:5
    if counts(c) > 0
        weights(c) = (nTrain / 5) / counts(c);
    end
end

present = weights(counts > 0);
isFlat = all(present >= 0.9 & present <= 1.1);
end

function [keep, scores] = classifyCandidates(featureMatrix, model, threshold)
%CLASSIFYCANDIDATES #5 CLASSIFIER step of the five-step lesion pipeline (see
%   notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "THE FIVE-STEP
%   LESION PIPELINE" and "Feature Engineering" sections). Thin, swappable
%   keep/reject interface only - this function does NOT implement a
%   training loop. Mirrors classifier.py classify_candidates.
%
%   Intended training protocol (not implemented here, per Module3_Plan.md
%   S4.1/S6.1): weak labels (grade 0 vs grades 3-4) with GroupKFold BY IMAGE
%   so no image scores itself, and every lesion classifier fitted INSIDE
%   each cross-validation fold on training rows only - leakage has already
%   happened once in the previous implementation. Classifier threshold: fix
%   the selection criterion BEFORE sweeping - choosing the threshold to
%   maximise a correlation, then reporting that correlation, is circular.
%
%   model: optional fitted MATLAB classifier (TreeBagger / fitcensemble /
%   fitctree, or anything exposing [~, score] = predict(model, X)), scored
%   via predict() with the positive ("keep") class in score column 2. With
%   model = [] (no model supplied), falls back to a documented placeholder
%   rule so step 5 is never a silent no-op.
%
%   Returns (keep: logical column, scores: double column).

if nargin < 3 || isempty(threshold)
    threshold = classifierDefaultThreshold();
end

if isempty(featureMatrix)
    keep = false(0, 1);
    scores = zeros(0, 1);
    return;
end

if ~isempty(model)
    [~, scoreMatrix] = predict(model, featureMatrix);
    scores = scoreMatrix(:, 2);
else
    scores = placeholderScore(featureMatrix);
end

keep = scores >= threshold;
end


function scores = placeholderScore(featureMatrix)
% Private helper (Python _placeholder_score): fallback scoring when no
% fitted model is supplied - per-column min-max normalisation, averaged
% into a single 0-1 score. This is NOT a trained classifier - it exists
% only so the pipeline's step 5 always runs code (steps 4-5 are
% structurally mandatory, per the notes' measured result that thresholding
% alone always fails). Replace with a real fitted model before drawing
% conclusions from kept candidates.
colMin = min(featureMatrix, [], 1);
colMax = max(featureMatrix, [], 1);
span = max(colMax - colMin, 1e-6);
normed = (featureMatrix - colMin) ./ span;
scores = mean(normed, 2);
end

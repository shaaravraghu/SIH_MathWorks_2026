function [model, threshold] = resolveClassifier(entry)
%RESOLVECLASSIFIER Normalises one entry of the `classifiers` struct passed
%   to stage2FeaturesFromCandidates into a (model, threshold) pair. entry
%   may be []; a fitted MATLAB classifier (scored via predict(model, X)
%   with the positive class in score column 2); or a struct with fields
%   model and (optionally) threshold. Mirrors features.py _resolve_classifier.

if isempty(entry)
    model = [];
    threshold = classifierDefaultThreshold();
    return;
end
if isstruct(entry) && isfield(entry, 'model')
    model = entry.model;
    if isfield(entry, 'threshold') && ~isempty(entry.threshold)
        threshold = entry.threshold;
    else
        threshold = classifierDefaultThreshold();
    end
else
    model = entry;
    threshold = classifierDefaultThreshold();
end
end

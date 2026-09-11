function report = summariseGradingMetrics(trueGrades, predGrades, scores, resolutions, threshold)
%SUMMARISEGRADINGMETRICS Everything in §7.1 for one set of predictions, both
%   pooled and WITHIN RESOLUTION STRATA (§4.3).

if nargin < 5, threshold = []; end

trueGrades = double(trueGrades(:));
predGrades = double(predGrades(:));
scores = double(scores(:));
referable = double(trueGrades >= 2);   % §6.4: referable = grade >= 2

sens = perClassSensitivity(trueGrades, predGrades);

report = struct();
report.n = numel(trueGrades);
report.qwk = quadraticWeightedKappa(trueGrades, predGrades);
report.confusion = gradeConfusionMatrix(trueGrades, predGrades);
report.per_class_sensitivity = sens;
report.grade4_recall = sens(5);                       % §8: reported on its own line
report.referable_auc = rocAuc(referable, scores);
report.qwk_within_resolution = withinResolution( ...
    @(t, p) quadraticWeightedKappa(t, p), resolutions, {trueGrades, predGrades});
report.referable_auc_within_resolution = withinResolution( ...
    @(l, s) rocAuc(l, s), resolutions, {referable, scores});

if ~isempty(threshold) && ~isnan(threshold)
    [s, p] = sensitivitySpecificity(referable, scores, threshold);
    report.referable_sensitivity = s;
    report.referable_specificity = p;
    report.threshold = threshold;
end
end

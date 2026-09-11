function rules = fitDecisionRules(data, oof, options)
%FITDECISIONRULES §7.2 + §6.2 + §6.4: the cutpoints, calibration and
%   referable operating point, ALL fitted on out-of-fold predictions and then
%   FROZEN before the test set is touched.
%
%   Choosing any of them on the test set is the most common accidental cheat
%   in this field, which is why this function only ever sees out-of-fold
%   scores (§7.2).

arguments
    data struct
    oof struct
    options.Calibration (1,1) string = "platt"   % "platt" | "isotonic"
    options.Verbose (1,1) logical = true
end

scores = oof.scores;
grades = oof.grades;
referable = double(grades >= 2);          % §6.4: referable = grade >= 2

cutpoints = fitCutpoints(scores, grades);
predicted = applyCutpoints(scores, cutpoints);
point = findOperatingPoint(referable, scores);

if options.Calibration == "isotonic"
    calibrator = fitIsotonicCalibrator(scores, referable);
else
    calibrator = fitPlattCalibrator(scores, referable);
end
raw = applyCalibrator(calibrator, scores);

% ECE before calibration is measured on the min-max-scaled raw score, which
% is the only way to read it as a probability at all (§7.1).
span = max(max(scores) - min(scores), eps);
eceBefore = expectedCalibrationError(referable, (scores - min(scores)) / span);
[eceAfter, diagram] = expectedCalibrationError(referable, raw);

rules = struct();
rules.cutpoints = cutpoints;
rules.operating_point = point;
rules.calibrator = calibrator;
rules.ece_before = eceBefore;
rules.ece_after = eceAfter;
rules.reliability = diagram;
rules.oof_report = summariseGradingMetrics(grades, predicted, scores, ...
    oof.resolutions, point.threshold);

if options.Verbose
    fprintf('  cutpoints:        [%s]\n', strjoin(compose('%.3f', cutpoints), ' '));
    if point.reached_target
        note = '';
    else
        note = '   (TARGET 0.90 NOT REACHED)';
    end
    fprintf('  operating point:  threshold %.4f -> sens %.3f, spec %.3f%s\n', ...
        point.threshold, point.sensitivity, point.specificity, note);
    fprintf('  ECE:              %.4f raw -> %.4f calibrated\n', eceBefore, eceAfter);
end
end

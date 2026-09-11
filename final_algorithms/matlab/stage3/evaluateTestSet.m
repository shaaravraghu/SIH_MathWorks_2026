function report = evaluateTestSet(data, cacheDir, featureNames, rules, options)
%EVALUATETESTSET §6.1's final step and §8's Phase 8: retrain on ALL 425 dev
%   rows, then evaluate the 75 test rows EXACTLY ONCE with the frozen
%   cutpoints and threshold.
%
%   The lesion classifiers are refitted on the dev rows only -- no lesion
%   classifier may ever touch a test image (§4.1).

arguments
    data struct
    cacheDir (1,1) string
    featureNames cell
    rules struct
    options.Model (1,1) string = "forest"
    options.RefitLesions (1,1) logical = true
    options.Verbose (1,1) logical = true
end

devMask = data.split == "dev";
testMask = data.split == "test";
if ~any(testMask)
    error('evaluateTestSet:noTestRows', 'No test rows -- check the split column.');
end

gradeMap = containers.Map(cellstr(data.ids), num2cell(data.grades));

if options.RefitLesions
    classifiers = fitLesionClassifiers(cacheDir, data.ids(devMask), gradeMap, options.Verbose);
    devOver = recomputeLesionColumns(cacheDir, data.ids(devMask), classifiers, options.Verbose);
    testOver = recomputeLesionColumns(cacheDir, data.ids(testMask), classifiers, options.Verbose);
else
    devOver = containers.Map('KeyType', 'char', 'ValueType', 'any');
    testOver = containers.Map('KeyType', 'char', 'ValueType', 'any');
end

Xdev = datasetMatrix(data, devMask, featureNames, devOver);
Xtest = datasetMatrix(data, testMask, featureNames, testOver);
ydev = data.grades(devMask);
ytest = data.grades(testMask);

scaler = zscoreFit(Xdev);
Xdev = zscoreApply(scaler, Xdev);
Xtest = zscoreApply(scaler, Xtest);

[classWeights, rounded] = gradeClassWeights(ydev);
if options.Model == "forest"
    model = fitGradingForest(Xdev, ydev, classWeights(rounded + 1));
else
    model = fitGradingMlp(Xdev, ydev);
end

scores = predictGradingModel(model, Xtest);
predicted = applyCutpoints(scores, rules.cutpoints);
referable = double(ytest >= 2);

report = summariseGradingMetrics(ytest, predicted, scores, ...
    data.resolution(testMask), rules.operating_point.threshold);

% §7.1: bootstrap CIs -- 15 images per grade makes these wide, report them
report.qwk_ci = bootstrapCi(@(t, p) quadraticWeightedKappa(t, p), {ytest, predicted});
report.referable_auc_ci = bootstrapCi(@(l, s) rocAuc(l, s), {referable, scores});

% §6.4: confidence routing and the DME override
probabilities = applyCalibrator(rules.calibrator, scores);
[borderline, enhanced] = confidenceFlags(data, testMask);
report.confidence = applyConfidenceRouting(probabilities, borderline, enhanced);

decision = scores >= rules.operating_point.threshold;
[final, urgent] = applyDmeOverride(decision, dmeFlags(data, testMask, testOver));
report.dme_overrides = sum(urgent);
report.referred_after_override = sum(final);
end


function [borderline, enhanced] = confidenceFlags(data, mask)
% §6.4. These are CONF columns -- never model inputs (D7).
t = data.table;
n = sum(mask);
borderline = false(n, 1);
enhanced = false(n, 1);
if ismember('stage1_verdict', t.Properties.VariableNames)
    verdict = string(t.stage1_verdict(mask));
    borderline = lower(strtrim(verdict)) == "borderline";
end
if ismember('enhancement_applied', t.Properties.VariableNames)
    value = t.enhancement_applied(mask);
    if isnumeric(value)
        enhanced = value > 0;
    else
        enhanced = str2double(string(value)) > 0;
    end
end
end


function flags = dmeFlags(data, mask, overrides)
% §6.4: dme_flag (S2-34) overrides the grade. Read from the per-fold
% overrides when present, since it is a classifier-dependent column.
idx = find(mask);
flags = false(numel(idx), 1);
t = data.table;
hasColumn = ismember('dme_flag', t.Properties.VariableNames);
for r = 1:numel(idx)
    idCode = char(data.ids(idx(r)));
    if isKey(overrides, idCode)
        over = overrides(idCode);
        if isfield(over, 'dme_flag')
            flags(r) = double(over.dme_flag) > 0;
            continue;
        end
    end
    if hasColumn
        flags(r) = double(t.dme_flag(idx(r))) > 0;
    end
end
end

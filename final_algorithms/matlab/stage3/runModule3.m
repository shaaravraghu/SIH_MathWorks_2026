function report = runModule3(options)
%RUNMODULE3 Stage 3 runner: Module3_Plan.md Phases 4-8.
%
%   % Phase 4 -- RandomForest baseline, lesion classifiers refitted per fold
%   runModule3()
%
%   % Phase 5 -- the MLP on the same folds and features
%   runModule3(Model="mlp")
%
%   % Phase 6 -- feature-block ablation
%   runModule3(Ablation=true)
%
%   % Phases 7-8 -- freeze the rules, then touch the test set ONCE
%   runModule3(Model="forest", Test=true)
%
%   Reads data/module3_dataset.csv and data/module3_candidates/*.mat, both
%   written by extractModule3Features (Phase 2).
%
%   The test set is evaluated only with Test=true, and only after the
%   cutpoints, calibration and operating point have been fitted on
%   out-of-fold dev predictions (§7.2).
%
%   NOTHING HERE HAS BEEN RUN. It is written to the plan and needs the
%   Phase 2 extraction output before it can execute.

arguments
    options.DataDir (1,1) string = ""
    options.Model (1,1) string = "forest"          % "forest" (§6.3) | "mlp" (§6.2)
    options.Block (1,1) string = "6a_measured_core" % D5 starts at 6a
    options.AllFeatures (1,1) logical = false      % all 38 inputs (D5 advises against)
    options.Ablation (1,1) logical = false         % Phase 6
    options.Test (1,1) logical = false             % Phase 8 -- ONCE (§7.2)
    options.Calibration (1,1) string = "platt"
    options.RefitLesions (1,1) logical = true      % false is LEAKY -- QC only (§4.1)
end

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(here), 'stage1'), fullfile(fileparts(here), 'stage2'));
repo = fileparts(fileparts(fileparts(here)));
if options.DataDir == "", options.DataDir = fullfile(repo, "data"); end

datasetPath = fullfile(options.DataDir, "module3_dataset.csv");
cacheDir = fullfile(options.DataDir, "module3_candidates");

data = loadModule3Dataset(datasetPath);
if ~options.RefitLesions
    fprintf(2, 'WARNING: RefitLesions=false is LEAKY by construction (§4.1). QC only.\n\n');
end

fprintf('rows: %d  (dev %d, test %d)\n', numel(data.ids), ...
    sum(data.split == "dev"), sum(data.split == "test"));
cached = sum(arrayfun(@(i) isfile(fullfile(cacheDir, char(i) + ".mat")), data.ids));
fprintf('cached candidates: %d/%d\n', cached, numel(data.ids));
if options.RefitLesions && cached < numel(data.ids)
    fprintf('  NOTE: ids without a cache keep their placeholder-rule lesion columns\n');
end

if options.Ablation
    fprintf('\n=== Phase 6: feature-block ablation ===\n');
    report = runAblation(data, cacheDir, Model=options.Model, ...
        RefitLesions=options.RefitLesions);
    return;
end

if options.AllFeatures
    featureNames = stage3Columns("all");
    label = "all model inputs";
else
    featureNames = stage3Columns(options.Block);
    label = options.Block;
end
fprintf('\nfeatures: %d (%s)\n', numel(featureNames), label);

fprintf('\n=== Cross-validation (%s) ===\n', options.Model);
oof = runCrossValidation(data, cacheDir, featureNames, ...
    Model=options.Model, RefitLesions=options.RefitLesions);

fprintf('\n=== Decision rules, fitted on out-of-fold predictions ===\n');
rules = fitDecisionRules(data, oof, Calibration=options.Calibration);

report = struct();
report.model = options.Model;
report.features = {featureNames};
report.n_features = numel(featureNames);
report.refit_lesions = options.RefitLesions;
report.cutpoints = rules.cutpoints;
report.operating_point = rules.operating_point;
report.ece_before = rules.ece_before;
report.ece_after = rules.ece_after;
report.out_of_fold = rules.oof_report;

printGradingReport('out-of-fold (dev rows)', rules.oof_report);

if options.Test
    fprintf('\n=== Phase 8: the held-out test set, evaluated ONCE ===\n');
    testReport = evaluateTestSet(data, cacheDir, featureNames, rules, ...
        Model=options.Model, RefitLesions=options.RefitLesions);
    report.test = testReport;
    printGradingReport('test rows', testReport);
    fprintf('  DME overrides:    %d images referred regardless of grade (§6.4)\n', ...
        testReport.dme_overrides);
end
end


function printGradingReport(title, report)
fprintf('\n--- %s ---\n', title);
fprintf('  n                     %d\n', report.n);
fprintf('  QWK pooled            %.4f\n', report.qwk);
within = report.qwk_within_resolution;
fprintf('  QWK within resolution %.4f   <- the honest number (§4.3)\n', within.mean);
strata = keys(within.per_stratum);
for k = 1:numel(strata)
    fprintf('      %12s %.4f\n', strata{k}, within.per_stratum(strata{k}));
end
if within.skipped.Count > 0
    skippedKeys = keys(within.skipped);
    parts = cell(1, numel(skippedKeys));
    for k = 1:numel(skippedKeys)
        parts{k} = sprintf('%s=%d', skippedKeys{k}, within.skipped(skippedKeys{k}));
    end
    fprintf('      skipped (too few rows): %s\n', strjoin(parts, ', '));
end
fprintf('  referable AUC pooled  %.4f\n', report.referable_auc);
fprintf('  referable AUC within  %.4f\n', report.referable_auc_within_resolution.mean);
if isfield(report, 'referable_sensitivity')
    fprintf('  referable sens/spec   %.3f / %.3f\n', ...
        report.referable_sensitivity, report.referable_specificity);
end
sens = report.per_class_sensitivity;
parts = cell(1, numel(sens));
for c = 1:numel(sens)
    if isnan(sens(c))
        parts{c} = sprintf('g%d=--', c - 1);
    else
        parts{c} = sprintf('g%d=%.2f', c - 1, sens(c));
    end
end
fprintf('  per-class sensitivity %s\n', strjoin(parts, '  '));
fprintf('  grade-4 recall        %.3f   <- reported on its own line (§8)\n', report.grade4_recall);
if isfield(report, 'qwk_ci')
    fprintf('  QWK 95%% CI            [%.3f, %.3f]\n', report.qwk_ci.lo, report.qwk_ci.hi);
end
fprintf('  confusion (rows = true grade):\n');
for r = 1:size(report.confusion, 1)
    fprintf('      %s\n', sprintf('%5d', report.confusion(r, :)));
end
end

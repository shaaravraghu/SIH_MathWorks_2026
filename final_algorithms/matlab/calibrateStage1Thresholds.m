function calibrateStage1Thresholds(options)
%CALIBRATESTAGE1THRESHOLDS Per-resolution #3 sharpness thresholds (Stage_1_CNN_Proposed_Changes.md M1).
%
% The notes pin no numeric thresholds for #3, and the placeholders reject
% every APTOS image (Brenner scores run ~2-40 against a floor of 50). A
% global floor would also act as a camera filter, so each threshold is a
% percentile of that metric WITHIN one resolution stratum:
%
%   fail       = FailPercentile       (default p2)
%   borderline = BorderlinePercentile (default p10; Brenner has no borderline)
%
% The four #3 gates cascade, so their rejections compound: p5 on each rejected
% 16% of the Module 3 sample, above the 4-13% the notes measured; p2 keeps the
% union near the low end of that range.
%
% Strata with fewer than MinStratum images share a "pooled" row computed over
% every image, which also serves resolutions never seen here. Grade labels are
% never read, so the table carries no label information.
%
% Scores are computed exactly as runStage1 computes them: same seeded
% RandStream, consumed in cascade order, on images that pass #1 and #2.
%
% Writes:
%   stage1/stage1_sharpness_thresholds.csv          read by stage1SharpnessThresholds
%   <OutDir>/module3_stage1_calibration_scores.csv  per-image scores, for review
%
% Run it before extractModule3Features:
%   calibrateStage1Thresholds()

arguments
    options.AptosDir (1,1) string = ""
    options.OutDir (1,1) string = ""
    options.IdsFile (1,1) string = ""
    options.Seed (1,1) double = 0
    options.FailPercentile (1,1) double = 2
    options.BorderlinePercentile (1,1) double = 10
    options.MinStratum (1,1) double = 20
end

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'stage1'), fullfile(here, 'stage2'));
repo = fileparts(fileparts(here));
if options.AptosDir == "", options.AptosDir = fullfile(repo, "aptos2019-blindness-detection"); end
if options.OutDir == "", options.OutDir = fullfile(repo, "data"); end
if options.IdsFile == "", options.IdsFile = fullfile(options.OutDir, "module3_ids.txt"); end

ids = strtrim(readlines(options.IdsFile));
ids = ids(ids ~= "");
n = numel(ids);
fprintf('calibrating on %s (%d images)\n', options.IdsFile, n);

resolution = strings(n, 1);
fovStage = strings(n, 1);
scores = nan(n, 4);  % brenner, lap, tenengrad, region_min
for i = 1:n
    idCode = char(ids(i));
    t0 = tic;
    try
        image = loadRgb(fullfile(options.AptosDir, "train_images", [idCode '.png']));
        resolution(i) = sprintf('%dx%d', size(image, 2), size(image, 1));

        pixel = checkPixelDimensionImage(image);
        if pixel.status == "fail"
            fovStage(i) = "pixel_dimension";
            continue
        end
        rngStream = RandStream('mt19937ar', 'Seed', options.Seed);
        fov = fovDetection(image, rngStream);
        if fov.status == "fail"
            fovStage(i) = "fov_" + fov.stage;
            fprintf('[%d/%d] %s %s\n', i, n, idCode, fovStage(i));
            continue
        end
        fovStage(i) = "pass";

        gray = toGray(image);
        brenner = brennerGradientGate(gray, rngStream);
        lapSpec = laplacianAndSpecSlopeGate(gray, rngStream);
        tenengrad = tenengradVarGate(gray, rngStream);
        rMin = regionMin(gray, lapSpec.laplacian, fov.fov.mask);
        scores(i, :) = [brenner.score, lapSpec.laplacian.score, tenengrad.score, rMin.score];
        fprintf('[%d/%d] %s %s (%.1fs)\n', i, n, idCode, resolution(i), toc(t0));
    catch err  % one bad image must not stop the calibration
        fovStage(i) = "error";
        fprintf(2, '[%d/%d] %s ERROR %s\n', i, n, idCode, err.message);
    end
end

scoreTable = table(ids, resolution, fovStage, scores(:, 1), scores(:, 2), scores(:, 3), scores(:, 4), ...
    'VariableNames', {'id_code', 'resolution', 'fov_stage', 'brenner', 'varLapNorm', 'tenengradVar', 'regionMin'});
writetable(scoreTable, fullfile(options.OutDir, "module3_stage1_calibration_scores.csv"));

ok = fovStage == "pass";
strata = unique(resolution(ok));
counts = arrayfun(@(s) sum(ok & resolution == s), strata);
strata = [strata(counts >= options.MinStratum); "pooled"];

rows = cell(numel(strata), 1);
for k = 1:numel(strata)
    if strata(k) == "pooled"
        in = ok;
    else
        in = ok & resolution == strata(k);
    end
    s = scores(in, :);
    pf = options.FailPercentile;
    pb = options.BorderlinePercentile;
    rows{k} = {strata(k), sum(in), ...
        percentileLinear(s(:, 1), pf), ...
        percentileLinear(s(:, 2), pf), percentileLinear(s(:, 2), pb), ...
        percentileLinear(s(:, 3), pf), percentileLinear(s(:, 3), pb), ...
        percentileLinear(s(:, 4), pf), percentileLinear(s(:, 4), pb)};
end
thresholds = cell2table(vertcat(rows{:}), 'VariableNames', {'resolution', 'n', 'brenner_fail', ...
    'lap_fail', 'lap_borderline', 'tenengrad_fail', 'tenengrad_borderline', ...
    'region_min_fail', 'region_min_borderline'});
tablePath = fullfile(here, 'stage1', 'stage1_sharpness_thresholds.csv');
writetable(thresholds, tablePath);

fprintf('\n#1/#2 outcome: %s\n', strjoin(compose('%s=%d', unique(fovStage), ...
    arrayfun(@(s) sum(fovStage == s), unique(fovStage))), '  '));
fprintf('wrote %s\n', tablePath);
disp(thresholds)
end

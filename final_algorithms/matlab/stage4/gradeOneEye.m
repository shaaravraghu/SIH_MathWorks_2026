function eye = gradeOneEye(imagePath, options)
%GRADEONEEYE Stage 4: run one fundus image through Stages 1-3 and return
%   everything the report and the overlays need.
%
%   eye: struct with fields
%     id, path, side              - identity
%     stage1                      - the 21 S1 columns (quality + verdict)
%     image_work                  - 872x872 uint8 working-resolution RGB
%     stage2                      - the runStage2 report (masks, OD, fovea,
%                                   lesions, quadrants)
%     features                    - the 45 S2 columns, lesion columns scored
%                                   by the SAVED classifiers, not the placeholder
%     grade, grade_score          - ICDR 0-4 and the continuous score
%     referable, referable_probability
%     evidence_map                - lesionEvidenceMap output
%
%   Stage 2 runs twice by design: extractStage2Candidates produces the
%   classifier-free candidates Stage 3 scores, and runStage2 produces the
%   masks the overlays draw. Roughly 25 s per eye; this is a report path, not
%   a batch path.

arguments
    imagePath (1,1) string
    options.ModelFile (1,1) string = ""
    options.Side (1,1) string = ""
    options.Seed (1,1) double = 0
end

here = fileparts(fileparts(mfilename('fullpath')));
addpath(here, fullfile(here, 'stage1'), fullfile(here, 'stage2'), fullfile(here, 'stage3'), ...
        fullfile(here, 'stage4'));
repo = fileparts(fileparts(here));
if options.ModelFile == "", options.ModelFile = fullfile(repo, "data", "module3_model.mat"); end

[~, idOnly] = fileparts(imagePath);
eye = struct('id', string(idOnly), 'path', imagePath, 'side', options.Side);

% --- Stage 1: quality gate and enhancement ---------------------------------
image = loadRgb(char(imagePath));
[s1row, s1out] = extractStage1Features(image, options.Seed);
eye.stage1 = s1row;
eye.stage1_status = string(s1out.status);

% --- Stage 2: candidates (for grading) and masks (for drawing) -------------
candidates = extractStage2Candidates(s1out.image, s1out.fov_mask);
eye.stage2 = runStage2(s1out.image, s1out.fov_mask);
eye.image_work = uint8(round(min(max(resample2WorkingResolution(s1out.image, s1out.fov_mask), 0), 1) * 255));

% --- Stage 3: grade, cutpoints, calibrated referable probability -----------
S = load(options.ModelFile);
bundle = S.bundle;
eye.features = stage2FeaturesFromCandidates(candidates, bundle.lesion_classifiers);

% Everything the report draws and counts comes from THIS candidate set, scored
% by the saved classifiers. runStage2 runs its own lesion pipeline with
% different thresholds, so its candidates are a different population entirely
% (measured: 106 kept microaneurysms there against 0 here on one eye) -- using
% one for the picture and the other for the table made the report disagree
% with itself. runStage2 is still the source for vessels, disc, fovea and
% quadrants, which that discrepancy does not touch.
eye.detections = computeDetections(candidates, bundle.lesion_classifiers);

featureNames = bundle.features{1};
x = zeros(1, numel(featureNames));
for k = 1:numel(featureNames)
    x(k) = double(eye.features.(featureNames{k}));
end
score = predictGradingModel(bundle.grading_model, zscoreApply(bundle.scaler, x));

eye.grade_score = score;
eye.grade = applyCutpoints(score, bundle.cutpoints);
eye.referable = score >= bundle.operating_point.threshold;
eye.referable_probability = applyCalibrator(bundle.calibrator, score);
eye.operating_point = bundle.operating_point;

% --- Stage 4: the evidence map ---------------------------------------------
eye.evidence_map = lesionEvidenceMap(eye);
end


function detections = computeDetections(candidates, classifiers)
% Step 5 of the lesion pipeline over the cached candidates: which ones the
% saved classifiers keep, with the centroid and area each was measured at.
% This is the single source for the panels, the evidence map and the counts.
fields = {'ma', 'haem', 'hard_exudate', 'cws'};

detections = struct();
for k = 1:numel(fields)
    field = fields{k};
    lesion = candidates.lesion_candidates.(field);
    n = size(lesion.features, 1);

    entry = [];
    if isstruct(classifiers) && isfield(classifiers, field)
        entry = classifiers.(field);
    end
    [model, threshold] = resolveClassifier(entry);

    if n > 0
        keep = classifyCandidates(lesion.features, model, threshold);
        keep = logical(keep(:));
    else
        keep = false(0, 1);
    end

    detections.(field) = struct( ...
        'centroids', lesion.centroids(keep, :), ...
        'areas', lesion.areas(keep), ...
        'n_candidates', n, ...
        'n_kept', sum(keep));
end
end

function result = runLesionPipeline(imageRgb, lesionClass, vesselMask, fovMask, opticDisc, fovea, model, classify)
%RUNLESIONPIPELINE #THE FIVE-STEP LESION PIPELINE (applies to every lesion
%   class): preprocess -> subtract vessels -> threshold to candidates ->
%   per-candidate features -> classifier keep/reject (see
%   notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "THE FIVE-STEP
%   LESION PIPELINE" section). Mirrors lesion_pipeline.py run_lesion_pipeline.
%
%   Steps 4 and 5 are made structurally mandatory here, not optional hooks:
%   measured across four components, EVERY one that stopped at step 3
%   (threshold only) failed, and every one that added steps 4-5 worked.
%
%   classify=false is the one deliberate exception, added for
%   Module3_Plan.md's CV-fold-safe extraction requirement (S4.1/S6.1): a
%   lesion classifier must be fitted per cross-validation fold on training
%   rows only, so candidate extraction (steps 1-4) has to be separable from
%   classification (step 5). classify=false stops after step 4 and returns
%   candidates without a keep/reject decision - callers MUST still run
%   them through classifyCandidates() before treating anything as a final
%   result; step 5 is deferred, not skipped.
%
%   fovMask/opticDisc/fovea/model may be [] to skip those refinements.
%   classify defaults to true.
%
%   result: scalar struct with fields lesion_class, candidate_mask,
%   candidates (1xN cell array of structs, each with .features added),
%   kept (1xM cell array, [] when classify=false), n_candidates, n_kept.

if nargin < 7
    model = [];
end
if nargin < 8 || isempty(classify)
    classify = true;
end

green = imageRgb(:, :, 2);
if ~isempty(fovMask)
    workingMask = fovMask;
else
    workingMask = true(size(green));
end

if ~isempty(opticDisc)
    odMask = circleMask(size(green), opticDisc.center_x, opticDisc.center_y, max(round(opticDisc.radius * 1.2), 1));
    workingMask = workingMask & ~odMask;
end

if ~isempty(fovea)
    if ~isempty(opticDisc)
        foveaRadiusPx = 0.5 * (2.0 * opticDisc.radius);
    else
        foveaRadiusPx = 10;
    end
    foveaMask = circleMask(size(green), fovea.x, fovea.y, max(round(foveaRadiusPx), 1));
    workingMask = workingMask & ~foveaMask;
end

% step 1
corrected = shadeCorrect(green, workingMask);
% step 2
workingMask = subtractVessels(workingMask, vesselMask);
% step 3
candidateMask = thresholdCandidates(imageRgb, corrected, workingMask, lesionClass);
components = candidateComponents(candidateMask);

% step 4 (mandatory): per-candidate features, always computed
if ~isempty(vesselMask)
    vesselDistTransform = bwdist(vesselMask); % distance_transform_edt(~vessel_mask) -> bwdist(vessel_mask)
else
    vesselDistTransform = [];
end
candidates = cell(1, numel(components));
for i = 1:numel(components)
    comp = components{i};
    comp.features = extractCandidateFeatures(imageRgb, corrected, comp, vesselMask, opticDisc, fovea, fovMask, vesselDistTransform);
    candidates{i} = comp;
end

if ~classify
    result = struct('lesion_class', lesionClass, 'candidate_mask', candidateMask, ...
        'candidates', {candidates}, 'kept', [], ...
        'n_candidates', numel(candidates), 'n_kept', []);
    return;
end

% step 5 (mandatory): classifier keep/reject
if ~isempty(candidates)
    featStructs = cellfun(@(c) c.features, candidates, 'UniformOutput', false);
    featureMatrix = featuresToMatrix(featStructs);
    [keep, scores] = classifyCandidates(featureMatrix, model, classifierDefaultThreshold());
else
    keep = false(0, 1);
    scores = zeros(0, 1);
end

for i = 1:numel(candidates)
    candidates{i}.keep = logical(keep(i));
    candidates{i}.score = scores(i);
end
kept = candidates(keep);

result = struct('lesion_class', lesionClass, 'candidate_mask', candidateMask, ...
    'candidates', {candidates}, 'kept', {kept}, ...
    'n_candidates', numel(candidates), 'n_kept', numel(kept));
end

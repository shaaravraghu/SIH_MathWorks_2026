function report = runStage2(image, fovMask, model)
%RUNSTAGE2 Stage 2 workflow: resample to the working resolution (see
%   resample2WorkingResolution.m - every pixel constant in Stage_2_CNN
%   assumes it), build the vessel map (matched filtering + Frangi calibre
%   bands + fine-scale-excess abnormal-vessel labelling), locate the optic
%   disc, locate the fovea, derive the OD-fovea quadrant axis, run the
%   five-step lesion pipeline per lesion class, and bucket haemorrhage
%   candidates into OD-fovea-anchored quadrants for the re-derived 4-2-1
%   count. Mirrors pipeline.py run_stage2.
%
%   See notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN for the full
%   spec. This is the standalone Stage_2_CNN demonstration entry point
%   (steps 4-5 of the lesion pipeline always classify inline, falling back
%   to the placeholder rule with model=[]); the CV-fold-safe Module 3
%   feature schema (S2-01..S2-45) is extractStage2Candidates.m /
%   stage2FeaturesFromCandidates.m instead.
%
%   image: file path (char/string) or RGB uint8 array. fovMask: boolean
%   mask at the ORIGINAL image resolution (recommended: stage1's
%   buildFovMask output); if omitted a minimal non-black mask is derived
%   here. model: optional shared MATLAB classifier passed to every lesion
%   class's step-5 classifier (see classifyCandidates.m).
%
%   report: scalar struct (Stage2Report) with fields vessels, optic_disc,
%   fovea, quadrant_axis_deg, lesions (struct with one field per lesion
%   class), nv_score, nvd_nve, quadrants.

LESION_CLASSES = {'microaneurysm', 'haemorrhage', 'hard_exudate', 'nerve_fibre_ischemia'};

if ischar(image) || isstring(image)
    image = loadRgb(char(image));
end
if nargin < 2 || isempty(fovMask)
    fovMask = fovMaskFromImage(image);
end
if nargin < 3
    model = [];
end

work01 = resample2WorkingResolution(image, fovMask);
workU8 = uint8(round(min(max(work01, 0), 1) * 255));
workingFovMask = stage2Masks().RETINA_MASK;

vesselsResult = buildVesselMap(workU8, workingFovMask);

% Optic disc: brightness search masks out vessel-detected pixels first,
% per the notes ("avoid regions with blood vessel detected").
opticDisc = locateOpticDisc(workU8, vesselsResult.matched_filter_mask, workingFovMask);
fovea = locateFovea(workU8, opticDisc, workingFovMask);

quadrantAxisDeg = atan2d(fovea.y - opticDisc.center_y, fovea.x - opticDisc.center_x);

lesions = struct();
for i = 1:numel(LESION_CLASSES)
    lc = LESION_CLASSES{i};
    lesions.(lc) = runLesionPipeline(workU8, lc, vesselsResult.matched_filter_mask, workingFovMask, ...
        opticDisc, fovea, model, true);
end

nvdNve = splitNvdNve(vesselsResult.excess_mask, opticDisc);

haemKept = lesions.haemorrhage.kept;
haemPoints = zeros(numel(haemKept), 2);
for i = 1:numel(haemKept)
    haemPoints(i, :) = haemKept{i}.centroid;
end
odCenter = [opticDisc.center_x, opticDisc.center_y];
foveaPoint = [fovea.x, fovea.y];
quadrants = countQuadrants(haemPoints, odCenter, foveaPoint);

report = struct( ...
    'vessels', vesselsResult, 'optic_disc', opticDisc, 'fovea', fovea, ...
    'quadrant_axis_deg', quadrantAxisDeg, 'lesions', lesions, ...
    'nv_score', vesselsResult.nv_score, 'nvd_nve', nvdNve, 'quadrants', quadrants);
end


function mask = fovMaskFromImage(image)
% Private helper (Python _fov_mask_from_image): minimal FOV mask
% (non-black region), matching stage1's approach, so Stage 2 can run
% standalone. Pass an explicit fovMask (e.g. stage1's buildFovMask output)
% to reuse Stage 1's FOV detection instead.
BLACK_THRESH = 10;
if ndims(image) == 3
    isBlack = all(image <= BLACK_THRESH, 3);
else
    isBlack = image <= BLACK_THRESH;
end
mask = ~isBlack;
end

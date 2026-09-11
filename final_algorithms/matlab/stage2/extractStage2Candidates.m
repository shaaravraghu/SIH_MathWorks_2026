function candidates = extractStage2Candidates(image, fovMask)
%EXTRACTSTAGE2CANDIDATES Image-derived-only extraction (Module3_Plan.md
%   S4.1/S6.1): contains nothing from a fitted classifier, so it is safe to
%   cache once per image (save()) and reuse across every cross-validation
%   fold. Mirrors features.py extract_stage2_candidates.
%
%   image: file path (char/string) or RGB uint8 array. fovMask: logical FOV
%   mask at the ORIGINAL image resolution (e.g. stage1's buildFovMask
%   output).
%
%   candidates: scalar struct (Stage2Candidates) with fields:
%     image_features   - scalar struct, every classifier-independent S2
%                         column (vessels, calibre, NV, OD, fovea)
%     optic_disc        - struct from locateOpticDisc
%     fovea              - struct from locateFovea
%     lesion_candidates  - struct with fields ma/haem/hard_exudate/cws, each
%                          a struct with fields features (NxF double),
%                          feature_names (cellstr), centroids (Nx2 [x y]),
%                          areas (Nx1); hard_exudate also has dme_touch (Nx1
%                          logical).
%
%   Holds only scalars and per-candidate arrays, never full-resolution
%   images: 872x872 arrays would cost ~15 MB per image if cached, and this
%   struct is saved once per image and reloaded in every CV fold.

% --- microaneurysm / haemorrhage candidate finding ---------------------------
% Reused from the previous implementation's min_close/ma_candidates/
% hem_candidates, per the coordinator's spec - these numbers are pinned,
% not placeholders.
MA_STRUCTURING_ELEMENT_LENGTH_PX = 15;
MA_CANDIDATE_PERCENTILE = 99.0;
MA_MIN_AREA_PX = 3;

HAEM_STRUCTURING_ELEMENT_LENGTH_PX = 41;
HAEM_CANDIDATE_PERCENTILE = 96.0;
HAEM_MAX_AREA_PX = pi * 17.0 ^ 2;

if ischar(image) || isstring(image)
    image = loadRgb(char(image));
end

work01 = resample2WorkingResolution(image, fovMask);
workU8 = uint8(round(min(max(work01, 0), 1) * 255));
green01 = prepGreen(work01);
green255 = green01 * 255.0;

m = stage2Masks();
vc = vesselConstants();
c = stage2Constants();

vesselsResult = buildVesselMap(workU8, m.RETINA_MASK);
% "The vessel map is the finalized one: matched filtering (a) OR Frangi
% calibre labels 1-3 (b)" - per the coordinator's spec.
vesselMask = vesselsResult.matched_filter_mask | ...
    ismember(vesselsResult.calibre, [vc.CALIBRE_MAJOR, vc.CALIBRE_FIRST_BRANCH, vc.CALIBRE_MINOR]);

opticDisc = locateOpticDisc(workU8, vesselMask, m.RETINA_MASK);
fovea = locateFovea(workU8, opticDisc, m.RETINA_MASK);
foveaPoint = [fovea.x, fovea.y];

vesselDistTransform = bwdist(vesselMask); % distance_transform_edt(~vessel_mask) -> bwdist(vessel_mask)

imageFeatures = imageFeaturesLocal(vesselMask, vesselsResult.calibre, green01, opticDisc, fovea);

lesionCandidates = struct();

maMaxAreaPx = pi * (125.0 / c.UM_PER_PX / 2.0) ^ 2; % 125 um lesion diameter
maRaw = smallLesionCandidates(green01, vesselMask, MA_STRUCTURING_ELEMENT_LENGTH_PX, ...
    MA_CANDIDATE_PERCENTILE, MA_MIN_AREA_PX, maMaxAreaPx);
lesionCandidates.ma = featuresForCandidates(maRaw, workU8, green255, vesselMask, opticDisc, fovea, vesselDistTransform);

% Lower area bound for haemorrhage candidates is not restated by the
% coordinator, but the reference extractor rejects anything below
% maMaxAreaPx so the two lesion classes don't double-count the same blobs
% - reused here for continuity (documented judgment call).
haemMinAreaPx = maMaxAreaPx;
haemRaw = smallLesionCandidates(green01, vesselMask, HAEM_STRUCTURING_ELEMENT_LENGTH_PX, ...
    HAEM_CANDIDATE_PERCENTILE, haemMinAreaPx, HAEM_MAX_AREA_PX);
lesionCandidates.haem = featuresForCandidates(haemRaw, workU8, green255, vesselMask, opticDisc, fovea, vesselDistTransform);

lesionKeys = {'hard_exudate', 'cws'};
lesionClasses = {'hard_exudate', 'nerve_fibre_ischemia'};
for k = 1:2
    key = lesionKeys{k};
    lesionClass = lesionClasses{k};
    result = runLesionPipeline(workU8, lesionClass, vesselMask, m.MEASUREMENT_MASK, opticDisc, fovea, [], false);
    cands = result.candidates;
    n = numel(cands);
    if n > 0
        feats = cellfun(@(cc) cc.features, cands, 'UniformOutput', false);
        [matrix, names] = featuresToMatrix(feats);
    else
        names = lesionFeatureOrder();
        matrix = zeros(0, numel(names));
    end
    centroids = zeros(n, 2);
    areas = zeros(n, 1);
    for i = 1:n
        centroids(i, :) = cands{i}.centroid;
        areas(i) = cands{i}.area_px;
    end
    packed = struct('features', matrix, 'feature_names', {names}, 'centroids', centroids, 'areas', areas);
    if strcmp(key, 'hard_exudate')
        packed.dme_touch = dmeTouch(centroids, areas, foveaPoint);
    end
    lesionCandidates.(key) = packed;
end

candidates = struct('image_features', imageFeatures, 'optic_disc', opticDisc, 'fovea', fovea, ...
    'lesion_candidates', lesionCandidates);
end


function row = imageFeaturesLocal(vesselMask, calibre, green01, opticDisc, fovea)
% Private helper (Python _image_features): every S2 column no lesion
% classifier touches, computed once per image so CV folds never re-run the
% vessel and line-detector filters.
VENOUS_BEADING_MIN_QUADRANT_PIXELS = 10; % placeholder: not pinned by the coordinator
NV_IRMA_MIN_QUADRANT_PIXELS = 10;        % placeholder: not pinned by the coordinator

m = stage2Masks();
c = stage2Constants();
vc = vesselConstants();

row = vesselTopologyStats(vesselMask, green01);
row = mergeInto(row, calibrePct(calibre));

odCenter = [opticDisc.center_x, opticDisc.center_y];
foveaPoint = [fovea.x, fovea.y];
quadrantMap = pixelQuadrantMap(odCenter, foveaPoint, size(green01));

beadingMask = (calibre == vc.CALIBRE_BEADING) & m.MEASUREMENT_MASK;
[~, row.venous_beading_quadrants] = quadrantsHolding(quadrantMap, beadingMask, VENOUS_BEADING_MIN_QUADRANT_PIXELS);

[nvStats, excess] = nvScores(green01, opticDisc);
row = mergeInto(row, nvStats);
[~, row.nv_irma_quadrants] = quadrantsHolding(quadrantMap, excess & m.MEASUREMENT_MASK, NV_IRMA_MIN_QUADRANT_PIXELS);

row.od_x = opticDisc.center_x;
row.od_y = opticDisc.center_y;
row.od_radius_pct = 100.0 * opticDisc.radius / c.TARGET_R;
row.od_contrast = opticDisc.centre_surround_contrast;
row.fovea_x = fovea.x;
row.fovea_y = fovea.y;
row.od_fovea_dist_dd = hypot(fovea.x - opticDisc.center_x, fovea.y - opticDisc.center_y) / c.DD_PX;
end


function merged = mergeInto(base, extra)
merged = base;
fn = fieldnames(extra);
for i = 1:numel(fn)
    merged.(fn{i}) = extra.(fn{i});
end
end

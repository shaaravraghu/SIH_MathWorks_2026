function [row, stage1Out] = extractStage1Features(image, seed)
%EXTRACTSTAGE1FEATURES One S1-01 .. S1-21 row (Module3_Plan.md S2.1).
%   image: file path (char/string) or RGB uint8 array.
%
%   The cascade short-circuits on its first fail, but the CSV needs every
%   column for every image (Phase 2 exit criterion: no blanks; S4.4
%   records rejections per grade). Metrics a failed cascade skipped are
%   computed here anyway; metrics the cascade did compute are reused so
%   the row agrees with the verdict.
%
%   row: scalar struct with the 21 STAGE1_COLUMNS fields, in column order.
%   stage1Out (second output; Python's row["_stage1"]): scalar struct
%   with fields image (final Stage 1 image, enhanced if the enhancement
%   branch ran), fov_mask (logical FOV mask) and status ("pass"|"fail"),
%   which Stage 2 consumes.

if nargin < 2 || isempty(seed)
    seed = 0;
end

if ischar(image) || isstring(image)
    image = loadRgb(char(image));
end

result = runStage1(image, seed);
% Fresh, independently-seeded stream for recomputing whichever metrics
% the (possibly short-circuited) cascade above did not already compute --
% mirrors Python's separate `rng = np.random.default_rng(seed)` here,
% distinct from the RandStream created inside runStage1 itself.
rngStream = RandStream('mt19937ar', 'Seed', seed);

height = size(image, 1);
width = size(image, 2);
gray = toGray(image);
green = image(:, :, 2);

if isfield(result, 'fov_detection')
    fov = result.fov_detection.fov;
    area = result.fov_detection.area_ratio;
else
    fov = buildFovMask(image);
    area = areaRatioCheck(fov);
end

if isfield(result, 'sharpness_contrast')
    sharp = result.sharpness_contrast;
else
    sharp = [];
end

if ~isempty(sharp) && ~isempty(fieldnames(sharp.brenner))
    brenner = sharp.brenner;
else
    brenner = brennerGradientGate(gray, rngStream);
end

if ~isempty(sharp) && ~isempty(fieldnames(sharp.laplacian_spec))
    lap = sharp.laplacian_spec.laplacian;
    spec = sharp.laplacian_spec.spec_slope;
else
    lap = varianceOfLaplacianNormed(gray, rngStream);
    spec = specSlopeGate(gray, rngStream);
end

if ~isempty(sharp) && ~isempty(fieldnames(sharp.tenengrad))
    tenengrad = sharp.tenengrad;
else
    tenengrad = tenengradVarGate(gray, rngStream);
end

if ~isempty(sharp) && ~isempty(fieldnames(sharp.region_min))
    regions = sharp.region_min;
else
    regions = regionMin(gray, lap, fov.mask);
end

[tilt, radial] = illuminationFit(green, fov.mask);

verdict = stage1Verdict(result);

% enhancement_applied is a bit field: 1 = flat-field applied,
% 2 = CLAHE applied, 3 = both, 0 = neither.
ENHANCED_FLAT_FIELD = 1;
ENHANCED_CLAHE = 2;
applied = 0;
if verdict == "borderline" && isfield(result, 'enhancement')
    enhancement = result.enhancement;
    if isfield(enhancement.ffc, 'applied') && enhancement.ffc.applied
        applied = bitor(applied, ENHANCED_FLAT_FIELD);
    end
    if enhancement.clahe.status == "pass"
        applied = bitor(applied, ENHANCED_CLAHE);
    end
end

row = struct();
row.megapixels = width * height / 1e6;
row.aspect_ratio = width / height;
row.area_ratio_s1 = area.s1;
row.area_ratio_s2 = area.s2;
% Whole-image value; the #2.2 gate itself only samples 10% of rows.
row.black_region_pct = 100.0 * mean(~fov.mask(:));
row.varLapNorm = lap.score;
row.specSlope = spec.score;
row.brenner = brenner.score;
row.tenengradVar = tenengrad.score;
row.regionMin = regions.score;
row.region_centre = regions.region_scores.centre;
% Counter-clockwise from top-right, the usual mathematical quadrant order.
row.region_q1 = regions.region_scores.top_right;
row.region_q2 = regions.region_scores.top_left;
row.region_q3 = regions.region_scores.bottom_left;
row.region_q4 = regions.region_scores.bottom_right;
row.illum_plane_tilt = tilt;
row.illum_radial = radial;
% Measured on the ORIGINAL image for every row, in [0, 1] units like Module 1.
row.local_contrast = localContrast(green, fov.mask) / 255.0;
% Stored as a percentage of FOV pixels: a raw count scales with
% megapixels, which is camera identity.
row.saturation_count = 100.0 * saturationFraction(green, fov.mask);
row.stage1_verdict = verdict;
row.enhancement_applied = applied;

stage1Out = struct('image', result.image, 'fov_mask', fov.mask, 'status', result.status);
end


function v = stage1Verdict(result)
% Private helper (Python _verdict).
if result.status == "fail"
    v = "fail";
elseif isfield(result, 'borderline') && result.borderline
    v = "borderline";
else
    v = "pass";
end
end

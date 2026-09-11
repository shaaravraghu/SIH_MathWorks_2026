function result = runStage1(image, seed)
%RUNSTAGE1 Stage 1 workflow:
%   Start -> Pixel Dimension (#1) -> FOV Detection (#2) ->
%   Sharpness/Contrast (#3) -> PASS
%   Borderline -> Enhancement (#4: Flat Field Correction, CLAHE) ->
%   Image Updation -> PASS
%
%   Fail at any gate exits immediately. Borderline results are recorded
%   and the cascade CONTINUES (so a later fail still rejects); if
%   anything was borderline at the end, the image goes through the
%   enhancement branch.
%
%   image: file path (char/string) or RGB uint8 array.
%   Returns a scalar struct with field status ("pass"|"fail"), image,
%   plus stage-specific report fields, mirroring Python's run_stage1 dict.

if nargin < 2
    seed = [];
end

if ischar(image) || isstring(image)
    image = loadRgb(char(image));
end

if isempty(seed)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
else
    rngStream = RandStream('mt19937ar', 'Seed', seed);
end

report = struct('borderline_sources', {{}});

% #1 Pixel Dimension
pixel = checkPixelDimensionImage(image);
report.pixel_dimension = pixel;
if pixel.status == "fail"
    result = mergeStruct(struct('status', "fail", 'stage', "pixel_dimension", 'image', image), report);
    return;
end
if pixel.status == "borderline"
    report.borderline_sources{end + 1} = "pixel_dimension";
end

% #2 FOV Detection
fov = fovDetection(image, rngStream);
report.fov_detection = fov;
if fov.status == "fail"
    result = mergeStruct(struct('status', "fail", 'stage', "fov_" + fov.stage, 'image', image), report);
    return;
end
fovMask = fov.fov.mask;

% #3 Sharpness / Contrast
sharp = sharpnessContrastCascade(image, fovMask, rngStream);
report.sharpness_contrast = sharp;
if sharp.status == "fail"
    result = mergeStruct(struct('status', "fail", 'stage', "sharpness_contrast", 'image', image), report);
    return;
end
if sharp.status == "borderline"
    report.borderline_sources{end + 1} = "sharpness_contrast";
end

if isempty(report.borderline_sources)
    result = mergeStruct(struct('status', "pass", 'borderline', false, 'image', image, 'fov_mask', fovMask), report);
    return;
end

% #4 Enhancement for Borderline images
enhanced = enhanceBorderline(image, fovMask);
report.enhancement = enhanced;
if enhanced.status == "fail"
    result = mergeStruct(struct('status', "fail", 'stage', "enhancement_" + enhanced.stage, 'image', image), report);
    return;
end

% Image Updation
result = mergeStruct(struct('status', "pass", 'borderline', true, 'image', enhanced.image, 'fov_mask', fovMask), report);
end


function merged = mergeStruct(base, extra)
% Merge two scalar structs, with fields of `extra` added after `base`'s
% (mirrors Python's {"status": ..., **report} dict merge in pipeline.py).
merged = base;
fn = fieldnames(extra);
for i = 1:numel(fn)
    merged.(fn{i}) = extra.(fn{i});
end
end

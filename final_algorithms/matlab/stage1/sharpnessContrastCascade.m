function result = sharpnessContrastCascade(image, fovMask, rngStream)
%SHARPNESSCONTRASTCASCADE #3 Sharpness/Contrast cascade.
%   Order (per workflow diagram): Brenner Gradient (#3.2) -> Variance of
%   Laplacian (NORMED) + SpecSlope (#3.1) -> TenengradVar (#3.3) ->
%   Region Min (#3.4). Runs #3 in cascade order, short-circuiting on the
%   first fail.
%
%   result is a scalar struct with fields status, brenner, laplacian_spec,
%   tenengrad, region_min -- mirrors Python's SharpnessResult dataclass
%   (unreached stages are left as empty structs, matching Python's {}).

if nargin < 2
    fovMask = [];
end
if nargin < 3 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

gray = toGray(image);

brenner = brennerGradientGate(gray, rngStream);
if brenner.status == "fail"
    result = struct('status', "fail", 'brenner', brenner, 'laplacian_spec', struct(), ...
        'tenengrad', struct(), 'region_min', struct());
    return;
end

lapSpec = laplacianAndSpecSlopeGate(gray, rngStream);
if lapSpec.status == "fail"
    result = struct('status', "fail", 'brenner', brenner, 'laplacian_spec', lapSpec, ...
        'tenengrad', struct(), 'region_min', struct());
    return;
end

tenengrad = tenengradVarGate(gray, rngStream);
if tenengrad.status == "fail"
    result = struct('status', "fail", 'brenner', brenner, 'laplacian_spec', lapSpec, ...
        'tenengrad', tenengrad, 'region_min', struct());
    return;
end

rMin = regionMin(gray, lapSpec.laplacian, fovMask);
if rMin.status == "fail"
    result = struct('status', "fail", 'brenner', brenner, 'laplacian_spec', lapSpec, ...
        'tenengrad', tenengrad, 'region_min', rMin);
    return;
end

statuses = [lapSpec.status, tenengrad.status, rMin.status];
if any(statuses == "borderline")
    overall = "borderline";
else
    overall = "pass";
end

result = struct('status', overall, 'brenner', brenner, 'laplacian_spec', lapSpec, ...
    'tenengrad', tenengrad, 'region_min', rMin);
end

function result = fovDetection(image, rngStream)
%FOVDETECTION #2 FOV Detection: runs Area Ratio (#2.1) then Black Region (#2.2).
%   Not worried about offset (misalignment doesn't change quality of the
%   interested section of the image). AreaFrac, BorderFrac and Radius are
%   a function of the black region of the image.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

fov = buildFovMask(image);
areaResult = areaRatioCheck(fov);

if ~areaResult.pass
    result = struct('status', "fail", 'stage', "area_ratio", 'fov', fov, 'area_ratio', areaResult);
    return;
end

blackResult = blackRegionCheck(image, rngStream);

if ~blackResult.pass
    result = struct('status', "fail", 'stage', "black_region", 'fov', fov, ...
        'area_ratio', areaResult, 'black_region', blackResult);
    return;
end

result = struct('status', "pass", 'fov', fov, 'area_ratio', areaResult, 'black_region', blackResult);
end

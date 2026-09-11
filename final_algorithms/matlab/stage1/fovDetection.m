function result = fovDetection(image, rngStream) %#ok<INUSD>
%FOVDETECTION #2 FOV Detection: runs Area Ratio (#2.1) then Area Fraction (#2.2).
%   Not worried about offset (misalignment doesn't change quality of the
%   interested section of the image). AreaFrac, BorderFrac and Radius are
%   a function of the black region of the image.
%
%   #2.2 uses areaFracCheck, not blackRegionCheck: the black-region band
%   rejected every image of the Module 3 sample (see areaFracCheck).
%   rngStream is kept in the signature for callers; neither gate samples.

fov = buildFovMask(image);
areaResult = areaRatioCheck(fov);

if ~areaResult.pass
    result = struct('status', "fail", 'stage', "area_ratio", 'fov', fov, 'area_ratio', areaResult);
    return;
end

fracResult = areaFracCheck(fov);

if ~fracResult.pass
    result = struct('status', "fail", 'stage', "area_frac", 'fov', fov, ...
        'area_ratio', areaResult, 'area_frac', fracResult);
    return;
end

result = struct('status', "pass", 'fov', fov, 'area_ratio', areaResult, 'area_frac', fracResult);
end

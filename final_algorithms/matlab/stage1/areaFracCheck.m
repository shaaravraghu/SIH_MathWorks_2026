function result = areaFracCheck(fov)
%AREAFRACCHECK #2.2 retinal-area gate, replacing the black-region band.
%   areaFrac = captured FOV area / (pi * R^2), with R the larger of the
%   horizontal and vertical radii (a frame-clipped extent can only be
%   shorter than the true one). Reject below 0.50: more than half of the
%   retina's own fitted disc is missing (Stage_1_CNN_Proposed_Changes.md F1,
%   option B).
%
%   Why not the black-region band: its per-row shortcut compares each
%   sampled row's black fraction with a band derived for the WHOLE image.
%   A round retina's rows range from ~20% black through the middle to ~100%
%   at the poles, so fewer than 80% of rows can ever sit in band -- on the
%   Module 3 sample it rejected every 1:1 and 4:3 image. And black fraction
%   measures crop style, not missing retina: medians of 17.5% and 52.7%
%   at aspects 1.32 and 1.33. areaFrac compares the retina with its own
%   circle, so it is aspect-independent by construction.

AREA_FRAC_FAIL = 0.50;

radius = max(fov.horizontal_radius, fov.vertical_radius);
if radius == 0
    result = struct('area_frac', 0.0, 'pass', false);
    return;
end

areaFrac = nnz(fov.mask) / (pi * radius ^ 2);
result = struct('area_frac', areaFrac, 'pass', areaFrac >= AREA_FRAC_FAIL);
end

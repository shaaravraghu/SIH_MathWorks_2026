function result = areaRatioCheck(fov)
%AREARATIOCHECK #2.1 Area Ratio gate (replaces perimeter-based circularity).
%   Compares the area implied by the horizontal/vertical radii against the
%   area implied by their mean radius (area ~ r^2, so no pi factor is
%   needed since it cancels in the ratio).
%
%   Why area and not perimeter: the conventional circularity 4*pi*A/P^2
%   squares the perimeter, so a ragged FOV boundary inflates P and
%   collapses the score. Measured on APTOS: 53.5% of all images fall
%   outside 0.85-1.15, including 53.0% of images whose circle-fit residual
%   (<0.02) says the FOV is intact -- perimeter-based circularity is
%   therefore not usable as a gate (notes #2.1).
%   Why area and not radius: area scales as r^2, so the same 0.85-1.15
%   bounds are roughly twice as strict as they would be on radius directly
%   (a radius ratio of 0.92-1.07 maps to an area ratio of 0.85-1.15) --
%   this is a deliberate tightening.

AREA_RATIO_LOW = 0.85;
AREA_RATIO_HIGH = 1.15;

rH = fov.horizontal_radius;
rV = fov.vertical_radius;
rMean = (rH + rV) / 2.0;

if rMean == 0
    result = struct('s1', 0.0, 's2', 0.0, 'pass', false);
    return;
end

s1 = (rH ^ 2) / (rMean ^ 2);
s2 = (rV ^ 2) / (rMean ^ 2);

passed = (AREA_RATIO_LOW < s1 && s1 < AREA_RATIO_HIGH) && (AREA_RATIO_LOW < s2 && s2 < AREA_RATIO_HIGH);

result = struct('s1', s1, 's2', s2, 'pass', passed);
end

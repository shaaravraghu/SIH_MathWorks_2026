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
%   Frame clipping: many APTOS cameras crop the top and bottom of the
%   retina (2416x1736, 2588x1958, 3216x2136 all give s1 ~1.28). There the
%   frame, not the retina, sets the vertical extent, so the ratio measures
%   the crop rather than the FOV shape -- and those cameras are the ones
%   that photographed most grade 1-4 patients, so gating on it rejects by
%   disease. A clipped axis therefore skips the shape test; how much retina
%   is missing is judged by areaFracCheck (#2.2) instead.
%   Elliptical FOV: the 2896x1944 camera stores a complete retina about 16%
%   wider than tall (non-square pixels; s1 ~1.165 on every image), and 17
%   of its 18 images in the Module 3 sample -- 11 of them grade 3 -- failed
%   the band. A FOV that fills its own ellipse, nnz(mask) / (pi*rH*rV) >=
%   ELLIPSE_FILL_MIN, is therefore accepted: a notched, fragmented or
%   irregular mask still falls short of it, a clean oval does not.

AREA_RATIO_LOW = 0.85;
AREA_RATIO_HIGH = 1.15;
ELLIPSE_FILL_MIN = 0.85;

rH = fov.horizontal_radius;
rV = fov.vertical_radius;
rMean = (rH + rV) / 2.0;

if rMean == 0 || rH == 0 || rV == 0
    result = struct('s1', 0.0, 's2', 0.0, 'clipped', false, 'ellipse_fill', 0.0, 'pass', false);
    return;
end

s1 = (rH ^ 2) / (rMean ^ 2);
s2 = (rV ^ 2) / (rMean ^ 2);

clipped = fov.clipped_horizontal || fov.clipped_vertical;
ellipseFill = nnz(fov.mask) / (pi * rH * rV);
inBand = (AREA_RATIO_LOW < s1 && s1 < AREA_RATIO_HIGH) && (AREA_RATIO_LOW < s2 && s2 < AREA_RATIO_HIGH);
passed = inBand || clipped || ellipseFill >= ELLIPSE_FILL_MIN;

result = struct('s1', s1, 's2', s2, 'clipped', clipped, 'ellipse_fill', ellipseFill, 'pass', passed);
end

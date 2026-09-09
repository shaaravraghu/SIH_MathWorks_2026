function [J, fovJ] = normalizeFundus(I, fov, targetR)
%NORMALIZEFUNDUS  Rescale and crop so the retinal radius is always targetR.
%
%   [J, fovJ] = normalizeFundus(I, fov, targetR)
%
%   This is the highest-leverage step in the whole preprocessing chain.
%   APTOS retinal radii range from ~400 to ~1800 px; IDRiD is ~1400 px.
%   Without this, "a microaneurysm is under 125 um" cannot be turned into a
%   pixel threshold, and no size-based rule generalises across datasets.
%
%   After this call, one pixel means the same physical distance in every
%   image from every camera.

if nargin < 3
    targetR = 540;                      % -> 1080 px retinal diameter
end

s = targetR / fov.radius;
J = imresize(im2double(I), s);
c = fov.centre * s;

half = round(targetR);
J    = cropCentred(J, c(1), c(2), half);

% Re-derive geometry on the normalised image (cheap, and keeps the struct
% self-consistent for anything downstream).
%
% The crop is tight -- the disc is inscribed in a 2*targetR square -- so
% re-detection occasionally fails where the original succeeded.  Fall back
% to transforming the known geometry rather than losing the image.
fovJ = detectFOV(J);

if ~fovJ.ok
    fovJ             = fov;
    fovJ.centre      = [half, half];
    fovJ.radius      = targetR;
    fovJ.mask        = false(2*half, 2*half);
    [xx, yy]         = meshgrid(1:2*half, 1:2*half);
    fovJ.mask        = hypot(xx-half, yy-half) <= targetR;
    fovJ.maskMeasure = imerode(fovJ.mask, ...
                               strel('disk', max(3, round(0.02*targetR))));
    fovJ.ok          = true;
end

end

% =======================================================================
function J = cropCentred(I, cx, cy, half)
%CROPCENTRED  Square crop about (cx,cy), zero-padding where it overruns.

pad = half + 10;
Ip  = padarray(I, [pad pad], 0, 'both');

r0 = round(cy + pad) - half;
c0 = round(cx + pad) - half;
J  = Ip(r0:r0+2*half-1, c0:c0+2*half-1, :);

end

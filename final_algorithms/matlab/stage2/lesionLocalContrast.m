function [contrast, candidateMean, annulusMean] = lesionLocalContrast(gray, mask, innerPx, outerPx)
%LESIONLOCALCONTRAST candidate mean vs a 12-24 px surrounding annulus
%   (pinned range). gray/mask should already be a small patch padded by
%   >= outerPx around the candidate, not the full image, for performance.
%   Named distinctly from stage1's localContrast.m (a different, unrelated
%   FOV-wide local-std metric) to avoid a same-name path-shadowing clash -
%   see the stage2 port's name-clash note. Mirrors lesion_features.py
%   local_contrast.

if nargin < 3 || isempty(innerPx)
    innerPx = 12; % pinned: "12-24 px surrounding annulus"
end
if nargin < 4 || isempty(outerPx)
    outerPx = 24; % pinned
end

innerSe = ellipseStrel(2 * innerPx + 1);
outerSe = ellipseStrel(2 * outerPx + 1);
innerDilated = imdilate(mask, innerSe);
outerDilated = imdilate(mask, outerSe);
annulus = outerDilated & ~innerDilated;

if any(mask(:))
    candidateMean = mean(gray(mask));
else
    candidateMean = 0.0;
end
if any(annulus(:))
    annulusMean = mean(gray(annulus));
else
    annulusMean = candidateMean;
end
contrast = candidateMean - annulusMean;
end

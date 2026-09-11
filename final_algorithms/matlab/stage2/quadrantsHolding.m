function [counts, nQuadrants] = quadrantsHolding(quadrantMap, mask, minPixels)
%QUADRANTSHOLDING Per-quadrant pixel counts of mask & (quadrantMap==q), and
%   the number of quadrants whose count exceeds minPixels. Mirrors
%   features.py _quadrants_holding.

counts = zeros(1, 4);
for q = 0:3
    counts(q + 1) = sum(mask(:) & (quadrantMap(:) == q));
end
nQuadrants = sum(counts > minPixels);
end

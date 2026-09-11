function counts = lesionQuadrantCounts(pointsXy, odCenter, foveaPoint)
%LESIONQUADRANTCOUNTS Per-quadrant candidate counts (1x4, index 1 = quadrant
%   0), same convention as lesionQuadrantIndex. Mirrors features.py
%   _quadrant_counts.

idx = lesionQuadrantIndex(pointsXy, odCenter, foveaPoint);
counts = zeros(1, 4);
for q = 0:3
    counts(q + 1) = sum(idx == q);
end
end

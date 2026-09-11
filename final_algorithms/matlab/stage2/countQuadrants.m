function result = countQuadrants(points, odCenter, foveaPoint)
%COUNTQUADRANTS Buckets already-classified lesion candidate points (e.g.
%   haemorrhage centroids) into the four OD-fovea-anchored quadrants and
%   applies the re-derived 4-2-1-style count threshold. Raw counts are
%   always returned alongside the thresholded flag so the constant can be
%   refit later without re-extraction. Mirrors quadrants.py count_quadrants.
%
%   points: N x 2 [x y] array (may be empty, N=0).
%
%   result: scalar struct (QuadrantResult) with fields axis_angle_deg,
%   counts (1x4), flags (1x4 logical), four_two_one (logical).

axisDeg = quadrantAxisAngle(odCenter, foveaPoint);
counts = zeros(1, 4);
for i = 1:size(points, 1)
    q = assignQuadrant(points(i, :), odCenter, axisDeg);
    counts(q + 1) = counts(q + 1) + 1;
end
thresh = quadrantCountThreshold();
flags = counts > thresh;
result = struct('axis_angle_deg', axisDeg, 'counts', counts, 'flags', flags, 'four_two_one', all(flags));
end

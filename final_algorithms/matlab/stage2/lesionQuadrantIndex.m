function idx = lesionQuadrantIndex(pointsXy, odCenter, foveaPoint)
%LESIONQUADRANTINDEX ax = atan2(fovea_y-od_y, fovea_x-od_x);
%   ang = mod(atan2(cy-od_y, cx-od_x) - ax, 2*pi);
%   quadrant = clip(floor(ang/(pi/2)), 0, 3).
%   Reused verbatim from the previous implementation's quadrant convention
%   (coordinator's spec) so haem/ma/beading/NV quadrants stay comparable.
%   Mirrors features.py _quadrant_index. Returns a 0-based column vector
%   (empty when pointsXy is empty).

if isempty(pointsXy)
    idx = zeros(0, 1);
    return;
end
ax = quadrantAxisRad(odCenter, foveaPoint);
ang = mod(atan2(pointsXy(:, 2) - odCenter(2), pointsXy(:, 1) - odCenter(1)) - ax, 2 * pi);
idx = min(max(floor(ang / (pi / 2)), 0), 3);
end

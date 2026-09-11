function boundaries = quadrantBoundaries(odCenter, foveaPoint)
%QUADRANTBOUNDARIES Four quadrant angular boundaries (degrees, absolute
%   frame), anchored to the OD-fovea axis rather than the frame's own axes.
%   Mirrors quadrants.py quadrant_boundaries.

axisDeg = quadrantAxisAngle(odCenter, foveaPoint);
boundaries = mod(axisDeg + 90.0 * (0:3), 360.0);
end

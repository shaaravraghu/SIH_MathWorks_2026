function ax = quadrantAxisRad(odCenter, foveaPoint)
%QUADRANTAXISRAD Radians version of the OD-fovea axis angle, used by the
%   features.py-internal quadrant convention (mixed with quadrantAxisAngle,
%   the degrees version used by the public quadrants.py-equivalent API).
%   Mirrors features.py _quadrant_axis.

ax = atan2(foveaPoint(2) - odCenter(2), foveaPoint(1) - odCenter(1));
end

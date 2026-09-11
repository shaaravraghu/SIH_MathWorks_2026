function angleDeg = quadrantAxisAngle(odCenter, foveaPoint)
%QUADRANTAXISANGLE Degrees, absolute frame, of the OD-fovea axis (used to
%   anchor quadrant boundaries, never the frame's own horizontal/vertical
%   axes). Mirrors quadrants.py quadrant_axis_angle.

dx = foveaPoint(1) - odCenter(1);
dy = foveaPoint(2) - odCenter(2);
angleDeg = atan2d(dy, dx);
end

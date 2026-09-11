function q = assignQuadrant(point, odCenter, axisAngleDeg)
%ASSIGNQUADRANT Quadrant index 0-3, boundaries at axisAngleDeg +
%   {0, 90, 180, 270} deg. Mirrors quadrants.py assign_quadrant.

dx = point(1) - odCenter(1);
dy = point(2) - odCenter(2);
angle = atan2d(dy, dx) - axisAngleDeg;
angle = mod(angle, 360.0);
q = mod(floor(angle / 90.0), 4);
end

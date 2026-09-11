function result = locateFovea(imageRgb, opticDisc, fovMask)
%LOCATEFOVEA #FOVEA: search along the OD-fovea axis, up to 1.25x the
%   expected fovea distance with a +-25 degree axis tilt allowed; the
%   darkest candidate wins, confirmed with a radial-brightness-increase
%   sanity check (see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN,
%   "FOVEA" section). Output is (x, y) only - no radius is needed since only
%   the fovea point (not macula extent) matters. Mirrors fovea.py locate_fovea.
%
%   opticDisc: struct from locateOpticDisc (0-based center_x/center_y).
%   fovMask may be [] to skip masking. Output x/y are 0-based pixel
%   coordinates.
%
%   result: scalar struct (FoveaResult) with fields x, y, darkness_score,
%   radial_brightness_increasing.

FOVEA_SEARCH_MAX_FACTOR = 1.25;   % pinned: "+- 1.25X of expected fovea location"
FOVEA_AXIS_TILT_DEG = 25.0;       % pinned: "+-25 degree axis tilt allowed"

% Expected OD-fovea distance is not pinned to a number in the notes ->
% placeholder (anatomical rule of thumb for a 45 degree fundus field is
% roughly 2.4-2.5 disc diameters temporal to the disc; calibrate before use).
EXPECTED_FOVEA_DISTANCE_DD = 2.4;
FOVEA_SEARCH_MIN_FACTOR = 0.5;    % placeholder: avoids sampling on the OD's own dark rim at the near end

FOVEA_DARKNESS_PATCH_RADIUS_PX = 6;        % placeholder: window used to score "darkest" at a candidate point
FOVEA_RADIAL_CHECK_STEPS_DD = [0.15, 0.3]; % placeholder radii (in DD) for the brightness-increase sanity check
FOVEA_SEARCH_RADIAL_STEPS = 20;  % placeholder: sampling density along the search radius
FOVEA_SEARCH_ANGULAR_STEPS = 11; % placeholder: sampling density across the +-25 degree tilt

brightness = toGray(imageRgb); % reuse stage1's toGray - identical Rec.601 luma formula
[h, w, ~] = size(brightness);
odCenter = [opticDisc.center_x, opticDisc.center_y];
% One disc diameter comes from the pinned working-resolution constant, NOT
% from the localised radius. Images are resampled so the retina radius is
% exactly TARGET_R, which is what fixes DD_PX at 124 px; every other pixel
% constant in Stage 2 is anchored the same way. Deriving it from
% opticDisc.radius instead made the search collapse: that radius is the
% smallest of the candidates tried, ~12 px, so ddPx came out ~25 px and the
% fovea was searched 30-75 px from the disc rather than ~300. Every image in
% the Module 3 sample then reported 0.24-0.60 DD against an expected 1.2-3.0,
% which also tilted the OD-fovea axis the quadrant map is built on.
ddPx = stage2Constants().DD_PX;

axisDeg = axisAngleDeg(odCenter, h, w, fovMask);
expectedDistPx = EXPECTED_FOVEA_DISTANCE_DD * ddPx;
maxDistPx = FOVEA_SEARCH_MAX_FACTOR * expectedDistPx;
minDistPx = FOVEA_SEARCH_MIN_FACTOR * expectedDistPx;

angles = linspace(axisDeg - FOVEA_AXIS_TILT_DEG, axisDeg + FOVEA_AXIS_TILT_DEG, FOVEA_SEARCH_ANGULAR_STEPS);
radii = linspace(minDistPx, maxDistPx, FOVEA_SEARCH_RADIAL_STEPS);

best = [];
for theta = angles
    rad = deg2rad(theta);
    for r = radii
        x = odCenter(1) + r * cos(rad);
        y = odCenter(2) + r * sin(rad);
        if ~(x >= 0 && x < w && y >= 0 && y < h)
            continue;
        end
        if ~isempty(fovMask) && ~fovMask(fix(y) + 1, fix(x) + 1)
            continue;
        end
        score = meanPatch(brightness, x, y, FOVEA_DARKNESS_PATCH_RADIUS_PX, h, w);
        if isempty(best) || score < best.score
            best = struct('score', score, 'x', x, 'y', y);
        end
    end
end

if isempty(best)
    % No valid candidate in the search fan (e.g. it falls entirely outside
    % the FOV) - fall back to the raw expected-distance point.
    result = struct('x', odCenter(1) + expectedDistPx, 'y', odCenter(2), ...
        'darkness_score', NaN, 'radial_brightness_increasing', false);
    return;
end

fx = best.x; fy = best.y;
centerScore = best.score;

% radial-brightness-increase sanity check: brightness should rise moving
% outward from a true fovea (a vessel shadow, by contrast, stays dark).
radialDir = atan2(fy - odCenter(2), fx - odCenter(1));
outwardScores = [];
for stepDd = FOVEA_RADIAL_CHECK_STEPS_DD
    stepPx = stepDd * ddPx;
    ox = fx + stepPx * cos(radialDir);
    oy = fy + stepPx * sin(radialDir);
    if ox >= 0 && ox < w && oy >= 0 && oy < h
        outwardScores(end + 1) = meanPatch(brightness, ox, oy, FOVEA_DARKNESS_PATCH_RADIUS_PX, h, w); %#ok<AGROW>
    end
end
increasing = ~isempty(outwardScores) && all(outwardScores > centerScore);

result = struct('x', fx, 'y', fy, 'darkness_score', centerScore, 'radial_brightness_increasing', increasing);
end


function angleDeg = axisAngleDeg(odCenter, h, w, fovMask)
% Private helper (Python _axis_angle_deg). Direction of the OD-fovea axis:
% points from the OD centre toward the FOV centroid - documented judgment
% call (left/right eye is not known here), see fovea.py module docstring.
if ~isempty(fovMask) && any(fovMask(:))
    [ys, xs] = find(fovMask);
    centre = [mean(double(xs) - 1), mean(double(ys) - 1)]; % 0-based
else
    centre = [w / 2.0, h / 2.0];
end
dx = centre(1) - odCenter(1);
dy = centre(2) - odCenter(2);
if dx == 0 && dy == 0
    angleDeg = 0.0;
else
    angleDeg = atan2d(dy, dx);
end
end


function val = meanPatch(brightness, x, y, radius, h, w)
% Private helper (Python _mean_patch). x/y are 0-based float coordinates;
% fix() truncates toward zero, matching Python's int() on non-negative
% floats (unlike MATLAB's floor/round).
x0 = max(0, fix(x - radius)); x1 = min(w, fix(x + radius) + 1);
y0 = max(0, fix(y - radius)); y1 = min(h, fix(y + radius) + 1);
if x1 <= x0 || y1 <= y0
    yy = min(max(round(y), 0), h - 1);
    xx = min(max(round(x), 0), w - 1);
    val = brightness(yy + 1, xx + 1);
else
    patch = brightness(y0 + 1:y1, x0 + 1:x1);
    val = mean(patch(:));
end
end

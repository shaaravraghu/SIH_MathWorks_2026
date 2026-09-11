function m = stage2Masks()
%STAGE2MASKS Constant working-resolution pixel grid and FOV masks
%   (resample.py RETINA_MASK/MEASUREMENT_MASK/PIXEL_X/PIXEL_Y).
%   These never change (they depend only on stage2Constants().TARGET_R), so
%   they are built once and cached in a persistent variable rather than
%   rebuilt on every call.
%
%   m is a scalar struct with fields:
%     PIXEL_X, PIXEL_Y     - 0-based pixel coordinate grids (872x872 double),
%                             matching numpy's np.mgrid[0:2*half, 0:2*half]
%                             convention (used for every distance/angle
%                             calculation downstream, e.g. quadrant maths).
%     RETINA_MASK           - logical, r <= 0.95*TARGET_R  (RET)
%     MEASUREMENT_MASK       - logical, r <= 0.92*TARGET_R  (MM) - every
%                             "% of FOV" feature divides by this.

persistent cached
if ~isempty(cached)
    m = cached;
    return;
end

c = stage2Constants();
half = c.TARGET_R;
[pixelX, pixelY] = meshgrid(0:(2 * half - 1), 0:(2 * half - 1));
radiusFromCentre = hypot(pixelY - half, pixelX - half);

m = struct();
m.PIXEL_X = pixelX;
m.PIXEL_Y = pixelY;
m.RETINA_MASK = radiusFromCentre <= c.TARGET_R * 0.95;
m.MEASUREMENT_MASK = radiusFromCentre <= c.TARGET_R * 0.92;

cached = m;
end

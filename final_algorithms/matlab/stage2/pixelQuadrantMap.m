function qMap = pixelQuadrantMap(odCenter, foveaPoint, sz)
%PIXELQUADRANTMAP Quadrant index (0-3) for every pixel on the working-
%   resolution grid (stage2Masks().PIXEL_X/PIXEL_Y), same convention as
%   lesionQuadrantIndex - used for pixel-mass features (venous beading,
%   NV/IRMA quadrants) that have no discrete candidate centroid. Mirrors
%   features.py _pixel_quadrant_map. sz is unused (kept for signature
%   parity with the Python version, which also ignores its shape arg since
%   PIXEL_X/PIXEL_Y are fixed-size).

m = stage2Masks();
ax = quadrantAxisRad(odCenter, foveaPoint);
ang = mod(atan2(m.PIXEL_Y - odCenter(2), m.PIXEL_X - odCenter(1)) - ax, 2 * pi);
qMap = min(max(floor(ang / (pi / 2)), 0), 3);
end

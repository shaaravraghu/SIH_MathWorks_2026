function mask = circleMask(sz, cx, cy, radius)
%CIRCLEMASK Filled-disc boolean mask of size sz=[h w], centred at (cx, cy)
%   (0-based pixel coordinates, as in the Python working-resolution grid)
%   with the given radius. Approximates cv2.circle(..., thickness=-1) via a
%   plain Euclidean-distance test rather than OpenCV's own polygon-based
%   circle rasteriser - documented approximation, sub-pixel boundary
%   differences only.

[xs, ys] = meshgrid(0:(sz(2) - 1), 0:(sz(1) - 1));
mask = (xs - cx) .^ 2 + (ys - cy) .^ 2 <= radius ^ 2;
end

function [rows, cols] = samplePointsInDisk(imageSize, nPoints, center, rngStream)
%SAMPLEPOINTSINDISK #3.1 sampling: random points within the
%   0.75*height-diameter disk centred at the image midpoint, each paired
%   with its (Right, Left, Up, Down) neighbours by the caller. Reduces
%   compute / increases speed (notes #3.1).

POINT_SAMPLE_FRACTION = 0.10; % #3.1

if nargin < 3
    center = [];
end
if nargin < 4 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

[c, radius] = retinaCenterAndRadius(imageSize, center);
cy = c(1);
cx = c(2);

if nargin < 2 || isempty(nPoints)
    nPoints = max(1, round(pi * radius ^ 2 * POINT_SAMPLE_FRACTION));
end

theta = 2 * pi * rand(rngStream, 1, nPoints * 3);
r = radius * sqrt(rand(rngStream, 1, nPoints * 3));
rowsAll = floor(cy + r .* sin(theta));
colsAll = floor(cx + r .* cos(theta));

h = imageSize(1);
w = imageSize(2);
% Margin of 2 pixels from every edge (1-based equivalent of the Python
% 0-based bounds rows>=2 & rows<h-2) so the 5-point Laplacian stencil
% never reads out of bounds.
valid = (rowsAll >= 3) & (rowsAll <= h - 2) & (colsAll >= 3) & (colsAll <= w - 2);
rowsAll = rowsAll(valid);
colsAll = colsAll(valid);

nKeep = min(nPoints, numel(rowsAll));
rows = rowsAll(1:nKeep);
cols = colsAll(1:nKeep);
rows = rows(:);
cols = cols(:);
end

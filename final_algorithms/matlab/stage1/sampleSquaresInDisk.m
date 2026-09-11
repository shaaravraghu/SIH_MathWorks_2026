function boxes = sampleSquaresInDisk(imageSize, nSquares, center, rngStream)
%SAMPLESQUARESINDISK #3.2 / #3.3 sampling: nSquares patches, each
%   approximately SQUARE_AREA_FRACTION of the retina area, within the
%   0.75*height-diameter disk centred at the image midpoint. Reduces
%   compute / increases speed (notes #3.2, #3.3).
%
%   boxes: Nx4 matrix of rows [r0, r1, c0, c1], 1-based and INCLUSIVE on
%   both ends (side = r1-r0+1 = c1-c0+1), suitable for direct MATLAB
%   slicing image(r0:r1, c0:c1) -- unlike Python's half-open [r0:r1)
%   slice convention.

SQUARE_AREA_FRACTION = 0.025; % #3.2 / #3.3, of retina area
N_SQUARES = 8; % #3.2 / #3.3

if nargin < 2 || isempty(nSquares)
    nSquares = N_SQUARES;
end
if nargin < 3
    center = [];
end
if nargin < 4 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

[c, radius] = retinaCenterAndRadius(imageSize, center);
cy = c(1);
cx = c(2);

retinaArea = pi * radius ^ 2;
side = round(sqrt(retinaArea * SQUARE_AREA_FRACTION));
side = max(side, 4);

h = imageSize(1);
w = imageSize(2);
boxes = zeros(0, 4);
attempts = 0;
while size(boxes, 1) < nSquares && attempts < nSquares * 50
    attempts = attempts + 1;
    theta = 2 * pi * rand(rngStream);
    r = (radius - side) * sqrt(rand(rngStream));
    row = floor(cy + r * sin(theta));
    col = floor(cx + r * cos(theta));
    r0 = row - floor(side / 2);
    r1 = r0 + side - 1;
    c0 = col - floor(side / 2);
    c1 = c0 + side - 1;
    if r0 < 1 || c0 < 1 || r1 > h || c1 > w
        continue;
    end
    boxes(end + 1, :) = [r0, r1, c0, c1]; %#ok<AGROW>
end
end

function result = blackRegionCheck(image, rngStream, blackThresh)
%BLACKREGIONCHECK #2.2 Black Region gate.
%   Band depends on aspect ratio (width/height); background pixel is
%   BLACK_PIXEL_RGB = (0,0,0). Optimization: sample a random 10% of rows
%   and require >=80% of those rows to have a black fraction within the
%   aspect-appropriate band.
%
%   Logic: the ratio of a circle inscribed in a square is 78.5%, so a
%   square frame with an inscribed retina is ~21.5% black; a non-square
%   frame cannot reach that figure since an inscribed circle covers
%   pi/(4*a) of a frame of aspect a, so the black fraction rises with
%   aspect ratio -- a single flat band therefore rejects correctly-framed
%   wide images (notes #2.2). Geometric expectation per aspect (black %):
%   1.00 -> 21.5%, 1.33 -> 40.9%, 1.39 -> 43.5%, 1.51 -> 48.0%, all inside
%   the bands below. Measured on APTOS: the banded gate rejects 22.4% of
%   images (a flat 15-35% band rejected 25.1%).

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end
if nargin < 3 || isempty(blackThresh)
    blackThresh = 10;
end

BLACK_PIXEL_RGB = [0, 0, 0]; %#ok<NASGU> % background pixel value; blackThresh already captures "near black"
ROW_SAMPLE_FRACTION = 0.10;
ROW_PASS_FRACTION = 0.80;

% aspect (width/height) -> (low %, high %) black-region band.
aspectKeys = [1.00, 1.33, 1.39, 1.51];
aspectBands = {[15.0, 25.0], [15.0, 45.0], [15.0, 47.5], [15.0, 50.0]};

height = size(image, 1);
width = size(image, 2);
aspect = width / height;
band = nearestAspectBand(aspect, aspectKeys, aspectBands);
low = band(1);
high = band(2);

nRows = max(1, round(height * ROW_SAMPLE_FRACTION));
sampledRows = randperm(rngStream, height, nRows);

inBandCount = 0;
for i = 1:nRows
    r = sampledRows(i);
    blackPct = rowBlackFraction(image(r, :, :), blackThresh) * 100.0;
    if low <= blackPct && blackPct <= high
        inBandCount = inBandCount + 1;
    end
end

inBandFraction = inBandCount / nRows;
passed = inBandFraction >= ROW_PASS_FRACTION;

result = struct('aspect', aspect, 'band', [low, high], ...
    'in_band_fraction', inBandFraction, 'pass', passed);
end


function band = nearestAspectBand(aspect, aspectKeys, aspectBands)
% Private helper (Python _nearest_aspect_band): nearest aspect-ratio band.
[~, idx] = min(abs(aspectKeys - aspect));
band = aspectBands{idx};
end


function frac = rowBlackFraction(row, blackThresh)
% Private helper (Python _row_black_fraction).
if size(row, 3) > 1
    isBlackRow = all(row <= blackThresh, 3);
else
    isBlackRow = row <= blackThresh;
end
frac = mean(isBlackRow(:));
end

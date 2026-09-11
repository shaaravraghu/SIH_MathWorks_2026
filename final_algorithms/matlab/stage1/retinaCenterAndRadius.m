function [center, radius] = retinaCenterAndRadius(imageSize, center)
%RETINACENTERANDRADIUS Shared helper for the #3.1/#3.2/#3.3 sampling functions.
%   Private in Python (_retina_center_and_radius), used by both
%   samplePointsInDisk (#3.1) and sampleSquaresInDisk (#3.2/#3.3), which
%   live in separate files under the one-public-function-per-file MATLAB
%   rule -- so it gets its own small file here.
%   center: [row, col], 1-based, defaults to the image midpoint.
%   radius: DIAMETER_FRACTION * height / 2.

DIAMETER_FRACTION = 0.75; % of image height, centered at image midpoint

h = imageSize(1);
w = imageSize(2);

if nargin < 2 || isempty(center)
    center = [floor(h / 2) + 1, floor(w / 2) + 1];
end

radius = (DIAMETER_FRACTION * h) / 2.0;
end

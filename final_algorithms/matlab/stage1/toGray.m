function gray = toGray(image)
%TOGRAY Rec. 601 luma conversion, input for the #3 Sharpness/Contrast cascade.
%   Kept as a manual elementwise formula (rather than MATLAB's rgb2gray,
%   which uses different weights) to match the Python implementation
%   exactly rather than silently changing the algorithm.

if ndims(image) == 2
    gray = double(image);
    return;
end

r = double(image(:, :, 1));
g = double(image(:, :, 2));
b = double(image(:, :, 3));
gray = 0.299 * r + 0.587 * g + 0.114 * b;
end

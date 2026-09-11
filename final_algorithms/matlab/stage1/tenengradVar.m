function score = tenengradVar(patch)
%TENENGRADVAR #3.3 TenengradVar metric, a confirmation for the #3.1
%   Variance of Laplacian (NORMED) process (notes #3).

patch = double(patch);

% scipy.ndimage.sobel(axis=1) differentiates along columns (x) with
% smoothing along rows; scipy.ndimage.sobel(axis=0) differentiates along
% rows (y) with smoothing along columns. fspecial('sobel') is MATLAB's
% row-differencing ([1 2 1;0 0 0;-1 -2 -1]) kernel, i.e. the axis=0
% convention; its transpose gives the axis=1 (column-differencing)
% convention. imfilter's default is correlation (no kernel flip), which
% matches scipy's correlate-based sobel, so no 'conv' flag is used. Sign
% conventions between the two implementations may differ, but that does
% not matter here since only gx.^2 + gy.^2 is used. Boundary handling
% differs slightly (MATLAB 'replicate' here vs. scipy's default
% 'reflect'); negligible for this patch-level metric.
sobelAxis1 = fspecial('sobel')'; % d/dx (columns) -- scipy axis=1
sobelAxis0 = fspecial('sobel');  % d/dy (rows)    -- scipy axis=0

gx = imfilter(patch, sobelAxis1, 'replicate', 'same');
gy = imfilter(patch, sobelAxis0, 'replicate', 'same');

gradientMagnitudeSq = gx .^ 2 + gy .^ 2;
score = var(gradientMagnitudeSq(:), 1) / (mean(patch(:)) + 1e-6) ^ 2;
end

function best = matchedFilterResponse(green)
%MATCHEDFILTERRESPONSE #VESSELS (a) matched filtering: bank of oriented
%   Chaudhuri-style Gaussian-cross-section kernels, max response over
%   orientation. Mirrors vessels.py matched_filter_response.
%
%   cv2.filter2D performs CORRELATION (not convolution); imfilter's default
%   mode is also correlation, so no 'conv' flag is passed here. Border is
%   approximated with 'replicate' (cv2's default is BORDER_REFLECT_101,
%   which MATLAB's imfilter cannot reproduce exactly) - documented
%   approximation, consistent with stage1's localContrast.m.

vc = vesselConstants();
green = double(green);
best = [];
for k = 0:(vc.MATCHED_FILTER_N_ORIENTATIONS - 1)
    theta = 180.0 * k / vc.MATCHED_FILTER_N_ORIENTATIONS;
    kernel = orientedMatchedKernel(theta, vc.MATCHED_FILTER_SIGMA_PX, vc.MATCHED_FILTER_LENGTH_PX);
    resp = imfilter(green, kernel, 'replicate', 'same');
    if isempty(best)
        best = resp;
    else
        best = max(best, resp);
    end
end
end


function kernel = orientedMatchedKernel(thetaDeg, sigma, len)
% Private helper (Python _oriented_matched_kernel).
half = floor(len / 2);
[xs, ys] = meshgrid(-half:half, -half:half);
theta = deg2rad(thetaDeg);
xAlong = xs * cos(theta) + ys * sin(theta);
yAcross = -xs * sin(theta) + ys * cos(theta);
kernel = -exp(-(yAcross .^ 2) / (2 * sigma ^ 2));
kernel(abs(xAlong) > len / 2.0) = 0.0;
nonzero = kernel(kernel ~= 0);
if ~isempty(nonzero)
    kernel = kernel - mean(nonzero);
end
end

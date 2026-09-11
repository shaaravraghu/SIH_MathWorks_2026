function out = lineDetector(gray01, len, width, nOrientations)
%LINEDETECTOR Reused VERBATIM (not approximated) from the previous Module 2
%   implementation (code_testing/python/extract_module2_features.py::
%   line_detector), per the Module3_Plan.md feature-schema spec, so the
%   measured nv_score evidence transfers unchanged. gray01 must be
%   [0, 1]-scaled - it inverts internally (dark ridges respond high) and
%   box-blur-subtracts the local mean. Mirrors vessels.py line_detector.
%
%   For each of nOrientations angles a length-len line kernel rotated about
%   its centre (built with imrotate('bilinear','crop'), approximating
%   cv2.warpAffine) is normalised to sum 1 and applied with CORRELATION
%   (imfilter's default mode); the max over angles minus a width x width
%   box mean gives the excess response.

if nargin < 4 || isempty(nOrientations)
    vc = vesselConstants();
    nOrientations = vc.LINE_DETECTOR_N_ORIENTATIONS;
end

inv = 1.0 - gray01;
% cv2.blur is a normalized box filter, default border BORDER_REFLECT_101;
% imboxfilt with 'Padding','symmetric' approximates it (scipy's own
% uniform_filter default mode is 'reflect', per the library-mapping note).
box = imboxfilt(inv, [width, width], 'Padding', 'symmetric');

best = -inf(size(gray01));
for a = 0:(nOrientations - 1)
    se = rotatedLineKernel(len, a * 180.0 / nOrientations);
    kernel = se / max(sum(se(:)), 1e-6);
    resp = imfilter(inv, kernel, 'replicate', 'same');
    best = max(best, resp);
end
out = best - box;
end


function se = rotatedLineKernel(len, deg)
% Private helper (Python _line_se), float variant for the normalised line
% kernel. A centre-row line is rotated about the kernel centre with
% imrotate('bilinear','crop'), approximating cv2.warpAffine +
% getRotationMatrix2D at the same centre/angle - documented approximation
% (imrotate's interpolation/centring convention is not bit-identical to
% OpenCV's affine warp, but is the closest built-in MATLAB equivalent).
se = zeros(len, len);
se(floor(len / 2) + 1, :) = 1.0;
se = imrotate(se, deg, 'bilinear', 'crop');
end

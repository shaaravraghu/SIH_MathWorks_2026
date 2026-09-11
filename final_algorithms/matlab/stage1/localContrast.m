function score = localContrast(channel, mask, ksize)
%LOCALCONTRAST Mean local standard deviation inside the FOV (#4 helper,
%   used by both Flat Field Correction (#4.1) and CLAHE (#4.2): "Local
%   Contrast and Saturation Counting are additions that can be used for
%   CLAHE (for fail cases)", notes #4).

if nargin < 3 || isempty(ksize)
    ksize = 15;
end

channel = double(channel);
kernel = ones(ksize, ksize) / (ksize * ksize);

% cv2.blur -> normalized box filter via imfilter; 'replicate' padding
% approximates OpenCV's default border handling closely enough for a
% smoothing box filter of this size.
localMean = imfilter(channel, kernel, 'replicate', 'same');
localSqMean = imfilter(channel .^ 2, kernel, 'replicate', 'same');
localVar = max(localSqMean - localMean .^ 2, 0);
localStd = sqrt(localVar);

if any(mask(:))
    score = mean(localStd(mask));
else
    score = 0.0;
end
end

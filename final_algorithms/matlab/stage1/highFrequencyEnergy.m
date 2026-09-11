function energy = highFrequencyEnergy(channel, mask)
%HIGHFREQUENCYENERGY Mean absolute Laplacian inside the FOV (#4.2 CLAHE
%   helper -- proxy for noise amplification: "Excessive CLAHE can amplify
%   noise/artifacts or suppress/distort subtle DR features", notes #4.2).
%   cv2.Laplacian(..., ksize=1) (OpenCV's default) applies the fixed 3x3
%   kernel [[0,1,0],[1,-4,1],[0,1,0]]; reproduced directly here via
%   imfilter rather than a MATLAB built-in with a different scale
%   convention (e.g. del2, which divides by 4).

kernel = [0 1 0; 1 -4 1; 0 1 0];
lap = imfilter(double(channel), kernel, 'replicate', 'same');

if any(mask(:))
    energy = mean(abs(lap(mask)));
else
    energy = 0.0;
end
end

function [tilt, radial] = illuminationFit(green, mask)
%ILLUMINATIONFIT S1-16 / S1-17: plane tilt magnitude and radial slope of
%   the background illumination field (#4.1).
%   Symmetric falloff is normal vignetting; asymmetric tilt is a fault,
%   and separating them needs two fits. Coordinates are in units of the
%   retinal radius and intensities in [0, 1], so both values mean the
%   same thing at every resolution. A negative radial slope is the
%   normal centre-bright field.

ILLUM_DOWNSCALE = 0.125;
% Window must comfortably exceed the optic disc (~0.29 R across), or the
% disc survives into the "illumination" field.
ILLUM_WINDOW_FRAC_OF_R = 0.4;

[ys, xs] = find(mask);
if numel(ys) < 10
    tilt = NaN;
    radial = NaN;
    return;
end
cy = mean(ys);
cx = mean(xs);
radius = max(sqrt(numel(ys) / pi), 1.0);

[h, w] = size(green);
smallW = max(8, floor(w * ILLUM_DOWNSCALE));
smallH = max(8, floor(h * ILLUM_DOWNSCALE));
scale = w / smallW;

% cv2.resize(..., INTER_AREA) has no exact MATLAB equivalent; imresize's
% antialiasing filter approximates area-averaging downsampling closely
% but not bit-exactly (same deviation as estimateIlluminationField.m).
small = imresize(double(green) / 255.0, [smallH, smallW], 'bilinear', 'Antialiasing', true);
smallMask = imresize(mask, [smallH, smallW], 'nearest') > 0;
if nnz(smallMask) < 10
    tilt = NaN;
    radial = NaN;
    return;
end

% Black surround near 0 would drag the field down at the rim and fake a falloff.
filled = small;
filled(~smallMask) = median(small(smallMask));

win = max(5, 2 * round(0.5 * ILLUM_WINDOW_FRAC_OF_R * radius / scale) + 1);

% scipy.ndimage.median_filter(..., mode="nearest") replicates edge values
% at the boundary; MATLAB's medfilt2 only supports 'zeros'/'symmetric'
% padding, so the "nearest" boundary is emulated by replicate-padding the
% input by the filter's half-window before filtering, then cropping back.
pad = floor(win / 2);
paddedFilled = padarray(filled, [pad, pad], 'replicate', 'both');
backgroundPadded = medfilt2(paddedFilled, [win, win], 'zeros');
background = backgroundPadded(pad + 1:pad + smallH, pad + 1:pad + smallW);

[sy, sx] = find(smallMask);
x = (sx * scale - cx) / radius;
y = (sy * scale - cy) / radius;
values = background(smallMask);

planeCoeffs = [x(:), y(:), ones(numel(x), 1)] \ values(:);
r = hypot(x, y);
radialCoeffs = [r(:), ones(numel(r), 1)] \ values(:);

tilt = hypot(planeCoeffs(1), planeCoeffs(2));
radial = radialCoeffs(1);
end

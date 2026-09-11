function result = flatFieldCorrection(image, mask)
%FLATFIELDCORRECTION #4.1 Flat Field Correction.
%   Normalises the image against its estimated illumination field, but
%   only where illumination is severely low/high. Fails (exit) if the
%   WHOLE image is severely low/high illuminated. Retains the original if
%   correction significantly reduces local contrast (notes #4.1).

FFC_SEVERE_LOW = 0.35; % background / global-median below this = severely dark
FFC_SEVERE_HIGH = 1.8; % background / global-median above this = severely bright
FFC_WHOLE_IMAGE_SEVERE_FRAC = 0.9;
FFC_MAX_CONTRAST_LOSS = 0.25; % >25% drop in local contrast -> retain original

img = double(image);
green = img(:, :, 2);

field = estimateIlluminationField(green, mask);
if any(mask(:))
    globalMedian = median(green(mask));
else
    globalMedian = 1.0;
end
relative = field / (globalMedian + 1e-6);

severe = ((relative < FFC_SEVERE_LOW) | (relative > FFC_SEVERE_HIGH)) & mask;
severeFrac = nnz(severe) / max(nnz(mask), 1);

if severeFrac >= FFC_WHOLE_IMAGE_SEVERE_FRAC
    result = struct('status', "fail", 'reason', "whole_image_severe_illumination", ...
        'image', image, 'severe_fraction', severeFrac);
    return;
end

if ~any(severe(:))
    result = struct('status', "pass", 'applied', false, 'image', image, 'severe_fraction', severeFrac);
    return;
end

gain = globalMedian ./ max(field, 1e-6);
% Feather the correction so only severely-lit regions are adjusted.
% cv2.GaussianBlur(..., ksize=(0,0), sigmaX=...) auto-sizes the kernel
% from sigma; imgaussfilt does the same, so this maps directly.
sigma = max(size(image, 1), size(image, 2)) / 50;
weight = imgaussfilt(double(severe), sigma);
weight = min(max(weight / (max(weight(:)) + 1e-6), 0), 1);
blendedGain = 1.0 + weight .* (gain - 1.0);

corrected = img .* blendedGain;
for c = 1:size(img, 3)
    ch = corrected(:, :, c);
    origCh = img(:, :, c);
    ch(~mask) = origCh(~mask);
    corrected(:, :, c) = ch;
end
corrected = uint8(min(max(corrected, 0), 255));

before = localContrast(green, mask);
after = localContrast(double(corrected(:, :, 2)), mask);
if before > 0 && (before - after) / before > FFC_MAX_CONTRAST_LOSS
    result = struct('status', "pass", 'applied', false, 'reason', "contrast_loss_retain_original", ...
        'image', image, 'severe_fraction', severeFrac);
    return;
end

result = struct('status', "pass", 'applied', true, 'image', corrected, 'severe_fraction', severeFrac);
end

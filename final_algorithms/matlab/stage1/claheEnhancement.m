function result = claheEnhancement(image, mask)
%CLAHEENHANCEMENT #4.2 CLAHE (Contrast Limited Adaptive Histogram
%   Equalization). Tries progressively milder CLAHE parameters and
%   accepts the first that improves local contrast without a significant
%   increase in saturation or noise; otherwise exits (fail).
%   Colour approach: green (G) channel only -- strong retinal-detail
%   baseline (notes #4.2).
%
%   NOTE on CLAHE_CLIP_LIMITS: OpenCV's clipLimit is an absolute
%   histogram-bin-count clip threshold, whereas MATLAB's adapthisteq
%   'ClipLimit' is normalized to [0,1] (a fraction of the tile's maximum
%   possible bin count) -- there is no exact unit conversion between the
%   two scales. CLAHE_CLIP_LIMITS_NORM below rescales the OpenCV-scale
%   values by /100, which lands the mildest step (1.0 -> 0.01) on
%   adapthisteq's own default ClipLimit and preserves the 2:1.5:1
%   progressively-milder progression of the original three steps; this is
%   a documented judgment call, not a literal port of the OpenCV numbers.

CLAHE_CLIP_LIMITS = [2.0, 1.5, 1.0]; % OpenCV-scale values; try progressively milder parameters
CLAHE_CLIP_LIMITS_NORM = CLAHE_CLIP_LIMITS / 100; % rescaled into adapthisteq's [0,1] ClipLimit range
CLAHE_TILE_GRID = [8, 8];
CLAHE_MAX_SATURATION_INCREASE = 0.02; % absolute increase in saturated-pixel fraction
CLAHE_MAX_NOISE_INCREASE = 1.5; % ratio of high-frequency energy after/before

green = image(:, :, 2);
baseContrast = localContrast(green, mask);
baseSaturation = saturationFraction(green, mask);
baseNoise = highFrequencyEnergy(green, mask);

attempts = struct('clip_limit', {}, 'local_contrast', {}, 'saturation', {}, 'noise_ratio', {});

for i = 1:numel(CLAHE_CLIP_LIMITS)
    clip = CLAHE_CLIP_LIMITS(i);
    clipNorm = CLAHE_CLIP_LIMITS_NORM(i);
    candidate = applyClaheGreen(image, mask, clipNorm, CLAHE_TILE_GRID);
    g = candidate(:, :, 2);
    contrast = localContrast(g, mask);
    saturation = saturationFraction(g, mask);
    noise = highFrequencyEnergy(g, mask);

    metrics = struct('clip_limit', clip, 'local_contrast', contrast, ...
        'saturation', saturation, 'noise_ratio', noise / (baseNoise + 1e-6));
    attempts(end + 1) = metrics; %#ok<AGROW>

    contrastOk = contrast > baseContrast;
    saturationOk = (saturation - baseSaturation) <= CLAHE_MAX_SATURATION_INCREASE;
    noiseOk = metrics.noise_ratio <= CLAHE_MAX_NOISE_INCREASE;

    if contrastOk && saturationOk && noiseOk
        result = struct('status', "pass", 'image', candidate, 'chosen', metrics, 'attempts', attempts);
        return;
    end
end

result = struct('status', "fail", 'reason', "clahe_degrades_image", 'image', image, 'attempts', attempts);
end


function out = applyClaheGreen(image, mask, clipLimitNorm, tileGrid)
% Private helper (Python _apply_clahe_green): CLAHE on the green
% (retinal-detail) channel, restricted to the FOV.
green = image(:, :, 2);
enhanced = adapthisteq(green, 'ClipLimit', clipLimitNorm, 'NumTiles', tileGrid);
out = image;
outGreen = green;
outGreen(mask) = enhanced(mask);
out(:, :, 2) = outGreen;
end

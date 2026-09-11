function out = prepGreen(workRgb)
%PREPGREEN Shade-corrected green at working resolution: green / (background
%   estimated by a sigma=7.5 Gaussian at 1/8 scale) * mean background. NOT
%   CLAHE (Module3_Plan.md S2.1, S1-21). Returns a [0, 1] array. Mirrors
%   resample.py prep_green.

m = stage2Masks();
g = double(workRgb(:, :, 2));
if any(m.RETINA_MASK(:))
    fillValue = mean(g(m.RETINA_MASK));
else
    fillValue = 0.0;
end
filled = g;
filled(~m.RETINA_MASK) = fillValue;

% ndimage.zoom(order=1) -> imresize('bilinear','Antialiasing',false), both
% down- and up-sampling here, per the library-mapping note.
small = imresize(filled, 1 / 8, 'bilinear', 'Antialiasing', false);
smallBlurred = imgaussfilt(small, 7.5, 'Padding', 'symmetric');
bg = imresize(smallBlurred, 8, 'bilinear', 'Antialiasing', false);
bg = bg(1:min(size(bg, 1), size(g, 1)), 1:min(size(bg, 2), size(g, 2)));
if ~isequal(size(bg), size(g))
    padRows = size(g, 1) - size(bg, 1);
    padCols = size(g, 2) - size(bg, 2);
    bg = padarray(bg, [max(padRows, 0), max(padCols, 0)], 'replicate', 'post');
    bg = bg(1:size(g, 1), 1:size(g, 2));
end

if any(m.RETINA_MASK(:))
    bgMean = max(mean(bg(m.RETINA_MASK)), 1e-3);
else
    bgMean = 1e-3;
end
out = min(max(g ./ max(bg, 1e-3) * bgMean, 0), 1);
if any(m.RETINA_MASK(:))
    out(~m.RETINA_MASK) = mean(out(m.RETINA_MASK));
else
    out(~m.RETINA_MASK) = 0.0;
end
end

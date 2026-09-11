function cropped = resample2WorkingResolution(imageRgb, fovMask)
%RESAMPLE2WORKINGRESOLUTION Rescales imageRgb so the FOV radius (derived
%   from fovMask, e.g. stage1's buildFovMask) equals stage2Constants().TARGET_R,
%   then crops 2*TARGET_R x 2*TARGET_R centred on the FOV, with everything
%   outside RETINA_MASK zeroed. Returns a double [0, 1] RGB array of shape
%   (2*TARGET_R, 2*TARGET_R, 3). Mirrors resample.py resample_to_working_resolution.
%
%   scipy.ndimage.zoom(order=1) is mapped to imresize('bilinear',
%   'Antialiasing', false) throughout (library-mapping note): zoom order=1
%   is plain bilinear interpolation with no anti-alias pre-filter, matching
%   imresize with antialiasing disabled.

if isempty(fovMask)
    error('resample2WorkingResolution:MissingFovMask', ...
        'fovMask is required - reuse Stage 1''s buildFovMask output.');
end

c = stage2Constants();
half = c.TARGET_R;
m = stage2Masks();

[ys, xs] = find(fovMask);
if isempty(ys)
    [h, w] = size(fovMask);
    cy = h / 2.0; cx = w / 2.0; % 0-based-equivalent centre of a symmetric frame
    radius = min(h, w) / 2.0;
else
    % Convert MATLAB's 1-based find() indices to Python's 0-based
    % convention so cy/cx land on the same physical pixel.
    ys0 = double(ys) - 1;
    xs0 = double(xs) - 1;
    cy = mean(ys0);
    cx = mean(xs0);
    rH = (double(max(xs0)) - double(min(xs0))) / 2.0;
    rV = (double(max(ys0)) - double(min(ys0))) / 2.0;
    radius = (rH + rV) / 2.0;
    if radius <= 0
        radius = min(size(fovMask, 1), size(fovMask, 2)) / 2.0;
    end
end

scale = c.TARGET_R / radius;
img = double(imageRgb) / 255.0;
zoomed = imresize(img, scale, 'bilinear', 'Antialiasing', false);

pad = half + 10;
padded = zeros(size(zoomed, 1) + 2 * pad, size(zoomed, 2) + 2 * pad, 3);
padded(pad + 1:pad + size(zoomed, 1), pad + 1:pad + size(zoomed, 2), :) = zoomed;

r0 = round(cy * scale + pad) - half; % 0-based row offset into padded
c0 = round(cx * scale + pad) - half; % 0-based col offset into padded
r0 = min(max(r0, 0), max(size(padded, 1) - 2 * half, 0));
c0 = min(max(c0, 0), max(size(padded, 2) - 2 * half, 0));

cropped = padded(r0 + 1:r0 + 2 * half, c0 + 1:c0 + 2 * half, :);
if size(cropped, 1) ~= 2 * half || size(cropped, 2) ~= 2 * half
    % Degenerate FOV (e.g. near image edge) - pad out to the expected size.
    fixShape = zeros(2 * half, 2 * half, 3);
    fixShape(1:size(cropped, 1), 1:size(cropped, 2), :) = cropped;
    cropped = fixShape;
end

retinaMask3 = repmat(m.RETINA_MASK, 1, 1, 3);
cropped(~retinaMask3) = 0;
end

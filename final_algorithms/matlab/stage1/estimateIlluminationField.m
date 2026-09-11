function field = estimateIlluminationField(channel, mask)
%ESTIMATEILLUMINATIONFIELD #4.1 Flat Field Correction: estimate the
%   smooth illumination field at reduced resolution, then upsample to
%   full size. Plane and radial models are combined by taking whichever
%   explains the low-res background with lower residual.
%   Risk: background estimation may incorrectly suppress low-contrast
%   retinal features -> potential loss of microaneurysms, vessels,
%   hemorrhages, etc. Optimisation: estimate the illumination field at
%   reduced resolution and apply correction to the original image; only
%   apply at places with severely low/high illumination (notes #4, #4.1).

FFC_DOWNSCALE = 0.125; % estimate illumination at reduced resolution

[h, w] = size(channel);
smallW = max(8, round(w * FFC_DOWNSCALE));
smallH = max(8, round(h * FFC_DOWNSCALE));

% cv2.resize(..., INTER_AREA) has no exact MATLAB equivalent; imresize's
% antialiasing filter approximates area-averaging downsampling closely
% but not bit-exactly.
small = imresize(double(channel), [smallH, smallW], 'bilinear', 'Antialiasing', true);
smallMask = imresize(mask, [smallH, smallW], 'nearest') > 0;

if nnz(smallMask) < 10
    if any(mask(:))
        fillVal = mean(channel(mask));
    else
        fillVal = 1.0;
    end
    field = fillVal * ones(size(channel));
    return;
end

% Median filter suppresses vessels/lesions before fitting the background.
ksize = max(3, bitor(floor(min(smallW, smallH) / 8), 1));
% cv2.medianBlur's border handling has no user-selectable MATLAB
% equivalent; 'symmetric' padding is used here as a close approximation.
background = double(medfilt2(single(small), [ksize, ksize], 'symmetric'));

plane = fitPlane(background, smallMask);
radial = fitRadial(background, smallMask);

planeResid = mean((background(smallMask) - plane(smallMask)) .^ 2);
radialResid = mean((background(smallMask) - radial(smallMask)) .^ 2);

if planeResid <= radialResid
    fieldSmall = plane;
else
    fieldSmall = radial;
end

field = imresize(fieldSmall, [h, w], 'bilinear');
end


function planeField = fitPlane(background, mask)
% Private helper (Python _fit_plane): plane fit a*x + b*y + c, models
% directional brightness variation (notes #4.1).
[h, w] = size(background);
[xx, yy] = meshgrid(1:w, 1:h);
xM = xx(mask);
yM = yy(mask);
A = [xM(:), yM(:), ones(numel(xM), 1)];
coeffs = A \ background(mask);
planeField = coeffs(1) * xx + coeffs(2) * yy + coeffs(3);
end


function radialField = fitRadial(background, mask, degree)
% Private helper (Python _fit_radial): radial fit, polynomial in distance
% from the FOV centre, models vignetting (notes #4.1).
if nargin < 3 || isempty(degree)
    degree = 2;
end
[h, w] = size(background);
[xx, yy] = meshgrid(1:w, 1:h);
[ys, xs] = find(mask);
cy = mean(ys);
cx = mean(xs);
r = sqrt((yy - cy) .^ 2 + (xx - cx) .^ 2);
rNorm = r / (max(r(mask)) + 1e-6);
coeffs = polyfit(rNorm(mask), background(mask), degree);
radialField = polyval(coeffs, rNorm);
end

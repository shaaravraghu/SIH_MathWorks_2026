function features = extractCandidateFeatures(imageRgb, shadeCorrectedGreen, candidate, vesselMask, ...
    opticDisc, fovea, fovMask, vesselDistanceTransform)
%EXTRACTCANDIDATEFEATURES Step 4 (mandatory): the full per-candidate feature
%   vector - colour, edge, shape, location, context (see
%   notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN, "Feature
%   Engineering" section). NEVER absolute intensity - see lesionFeatures
%   module docstring. Mirrors lesion_features.py extract_candidate_features.
%
%   candidate: struct with bbox=[x y w h] (0-based), mask_local (logical
%   mask cropped to bbox) and centroid=[cx cy] (0-based, full-image coords).
%   opticDisc/fovea/fovMask may be [] to skip those features.
%   vesselDistanceTransform: optional precomputed bwdist(vesselMask) (the
%   MATLAB equivalent of Python's
%   scipy.ndimage.distance_transform_edt(~vessel_mask), per the library-
%   mapping note: distance_transform_edt(bw) -> bwdist(~bw)), passed in so
%   it is computed once per image rather than once per candidate.
%
%   Shape features use regionprops (Area, Perimeter, Eccentricity,
%   Solidity, ConvexHull) rather than cv2 contour moments / ellipse fit:
%   documented equivalent, not bit-identical (regionprops' Perimeter/
%   Eccentricity estimators use a different algorithm than cv2.arcLength/
%   cv2.fitEllipse) - judgment call per the library-mapping note.

LOCAL_CONTRAST_ANNULUS_INNER_PX = 12; % pinned: "12-24 px surrounding annulus"
LOCAL_CONTRAST_ANNULUS_OUTER_PX = 24; % pinned

x = candidate.bbox(1); y = candidate.bbox(2); w = candidate.bbox(3); h = candidate.bbox(4);
maskLocal = candidate.mask_local;
cx = candidate.centroid(1); cy = candidate.centroid(2);

pad = LOCAL_CONTRAST_ANNULUS_OUTER_PX;
[rgbCrop, offset] = cropWithPad(imageRgb, [x, y, w, h], pad);
ox = offset(1); oy = offset(2);
[greenCrop, ~] = cropWithPad(shadeCorrectedGreen, [x, y, w, h], pad);

maskFullCrop = false(size(rgbCrop, 1), size(rgbCrop, 2));
rowStart = (y - oy) + 1; colStart = (x - ox) + 1;
maskFullCrop(rowStart:rowStart + h - 1, colStart:colStart + w - 1) = maskLocal;

% colour (ratios only)
rC = rgbCrop(:, :, 1); gC = rgbCrop(:, :, 2); bC = rgbCrop(:, :, 3);
candidatePixels = [rC(maskFullCrop), gC(maskFullCrop), bC(maskFullCrop)];
colour = struct( ...
    'b_over_g', bOverG(candidatePixels), ...
    'r_over_g', rOverG(candidatePixels), ...
    'saturation', meanSaturation(candidatePixels));

% edge
grayCrop = toGray(rgbCrop); % reuse stage1's toGray, same Rec.601 weights as cv2.cvtColor(RGB2GRAY)
% ndimage.sobel / cv2.Sobel mapping: fspecial('sobel') is MATLAB's
% y-derivative-oriented kernel; its transpose gives the x-derivative. Only
% hypot(gx,gy) is used below, so the overall sign convention is immaterial.
gx = imfilter(grayCrop, fspecial('sobel')', 'replicate', 'same');
gy = imfilter(grayCrop, fspecial('sobel'), 'replicate', 'same');
gradMag = hypot(gx, gy);
rim = imdilate(maskFullCrop, ones(3, 3)) & ~maskFullCrop;
if any(rim(:))
    gradAtRim = mean(gradMag(rim));
else
    gradAtRim = 0.0;
end
edgeSharpness = radialEdgeSharpness(grayCrop, cx - ox, cy - oy);

[perimeter, eccentricity, solidity, hullPerimeter, hasRegion] = shapeStats(maskFullCrop);
if perimeter > 0
    boundarySmoothness = hullPerimeter / perimeter;
else
    boundarySmoothness = 0.0;
end
if ~hasRegion
    eccentricity = 0.0;
end

edge = struct('grad_mag_rim', gradAtRim, 'edge_sharpness', edgeSharpness, ...
    'boundary_smoothness', boundarySmoothness);

% shape
areaPx = sum(maskFullCrop(:));
if perimeter > 0
    circularity = 4 * pi * double(areaPx) / (perimeter ^ 2);
else
    circularity = 0.0;
end

shape = struct('area_px', double(areaPx), 'perimeter_px', perimeter, 'circularity', circularity, ...
    'eccentricity', eccentricity, 'solidity', solidity);

% location
if ~isempty(opticDisc)
    ddPx = 2.0 * opticDisc.radius;
else
    ddPx = [];
end
if ~isempty(opticDisc) && ~isempty(ddPx) && ddPx ~= 0
    distOd = hypot(cx - opticDisc.center_x, cy - opticDisc.center_y) / ddPx;
else
    distOd = NaN;
end
if ~isempty(fovea) && ~isempty(ddPx) && ddPx ~= 0
    distFovea = hypot(cx - fovea.x, cy - fovea.y) / ddPx;
else
    distFovea = NaN;
end

if ~isempty(vesselDistanceTransform)
    distTransform = vesselDistanceTransform;
elseif ~isempty(vesselMask) && any(vesselMask(:))
    distTransform = bwdist(vesselMask); % distance_transform_edt(~vessel_mask) -> bwdist(vessel_mask)
else
    distTransform = [];
end
if ~isempty(distTransform)
    yi = min(max(round(cy), 0), size(distTransform, 1) - 1);
    xi = min(max(round(cx), 0), size(distTransform, 2) - 1);
    distVesselPx = distTransform(yi + 1, xi + 1);
else
    distVesselPx = NaN;
end

location = struct('dist_od_dd', distOd, 'dist_fovea_dd', distFovea, 'dist_vessel_px', distVesselPx);

% context
[contrast, candMean, bgMean] = lesionLocalContrast(greenCrop, maskFullCrop, ...
    LOCAL_CONTRAST_ANNULUS_INNER_PX, LOCAL_CONTRAST_ANNULUS_OUTER_PX);
if bgMean ~= 0
    bgRatio = candMean / bgMean;
else
    bgRatio = NaN;
end
context = struct('local_contrast', contrast, 'bg_ratio', bgRatio);

features = colour;
features = mergeInto(features, edge);
features = mergeInto(features, shape);
features = mergeInto(features, location);
features = mergeInto(features, context);
end


function merged = mergeInto(base, extra)
merged = base;
fn = fieldnames(extra);
for i = 1:numel(fn)
    merged.(fn{i}) = extra.(fn{i});
end
end


function [crop, offset] = cropWithPad(image, bbox, pad)
% Private helper (Python _crop_with_pad). bbox=[x y w h], 0-based.
x = bbox(1); y = bbox(2); w = bbox(3); h = bbox(4);
H = size(image, 1); W = size(image, 2);
x0 = max(0, x - pad); y0 = max(0, y - pad);
x1 = min(W, x + w + pad); y1 = min(H, y + h + pad);
if ndims(image) == 3
    crop = image(y0 + 1:y1, x0 + 1:x1, :);
else
    crop = image(y0 + 1:y1, x0 + 1:x1);
end
offset = [x0, y0];
end


function [perimeter, eccentricity, solidity, hullPerimeter, hasRegion] = shapeStats(maskFullCrop)
% Private helper: largest-region shape descriptors, standing in for
% Python's "largest contour by area" (cv2.contourArea) selection.
stats = regionprops(maskFullCrop, 'Area', 'Perimeter', 'Eccentricity', 'Solidity', 'ConvexHull');
if isempty(stats)
    perimeter = 0.0; eccentricity = 0.0; solidity = 0.0; hullPerimeter = 0.0; hasRegion = false;
    return;
end
[~, idx] = max([stats.Area]);
s = stats(idx);
perimeter = s.Perimeter;
eccentricity = s.Eccentricity;
solidity = s.Solidity;
hullPerimeter = polygonPerimeter(s.ConvexHull);
hasRegion = true;
end


function p = polygonPerimeter(pts)
% Private helper: closed-polygon perimeter of a convex-hull vertex list,
% standing in for cv2.arcLength(cv2.convexHull(contour), True).
if size(pts, 1) < 2
    p = 0.0;
    return;
end
closedPts = [pts; pts(1, :)];
d = diff(closedPts, 1, 1);
p = sum(hypot(d(:, 1), d(:, 2)));
end


function val = radialEdgeSharpness(gray, cx, cy, maxRadiusPx, nSamples)
% Private helper (Python _radial_edge_sharpness): steepness of the
% intensity transition across the candidate boundary, averaged over
% several outward rays from the centroid - documented approximation, the
% notes describe sharp-vs-gradual qualitatively but do not pin a formula.
if nargin < 4 || isempty(maxRadiusPx), maxRadiusPx = 15; end
if nargin < 5 || isempty(nSamples), nSamples = 16; end

[h, w] = size(gray);
profiles = {};
for k = 0:(nSamples - 1)
    theta = 2 * pi * k / nSamples;
    dx = cos(theta); dy = sin(theta);
    vals = [];
    for r = 0:(maxRadiusPx - 1)
        px = round(cx + r * dx); py = round(cy + r * dy);
        if px >= 0 && px < w && py >= 0 && py < h
            vals(end + 1) = gray(py + 1, px + 1); %#ok<AGROW>
        else
            break;
        end
    end
    if numel(vals) >= 2
        profiles{end + 1} = vals; %#ok<AGROW>
    end
end
if isempty(profiles)
    val = 0.0;
    return;
end
minLen = min(cellfun(@numel, profiles));
if minLen < 2
    val = 0.0;
    return;
end
stacked = cellfun(@(p) p(1:minLen), profiles, 'UniformOutput', false);
stacked = vertcat(stacked{:});
profileMean = mean(stacked, 1);
grad = gradient(profileMean);
val = max(abs(grad));
end

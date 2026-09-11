function candidates = smallLesionCandidates(green01, vesselMask, seLengthPx, percentile, minArea, maxArea, vesselDilateIters)
%SMALLLESIONCANDIDATES Steps 1-3 for microaneurysms/haemorrhages:
%   scale-matched closing minus the image, vessel-masked (dilated 3x3 x
%   vesselDilateIters), percentile-thresholded inside MEASUREMENT_MASK,
%   area-filtered (reused from the previous implementation, per
%   Module3_Plan.md's spec - these numbers are pinned, not placeholders).
%   Mirrors features.py _small_lesion_candidates.
%
%   Returns a 1xN cell array of structs with fields label_id, centroid
%   ([cx cy], 0-based), area_px, bbox ([x y w h], 0-based), mask_local.

if nargin < 7 || isempty(vesselDilateIters)
    vesselDilateIters = 3; % pinned: "vessel mask dilated 3x3 for 3 iterations"
end
SMALL_LESION_N_ORIENTATIONS = 12; % pinned

m = stage2Masks();
u8 = uint8(round(min(max(green01, 0), 1) * 255));
closed = minClose(u8, seLengthPx, SMALL_LESION_N_ORIENTATIONS);
diffImg = (double(closed) - double(u8)) / 255.0;

% binary_dilation with np.ones((3,3)) and N iterations -> imdilate with
% ones(3), repeated N times (per the library-mapping note).
dilatedVessel = vesselMask;
for it = 1:vesselDilateIters
    dilatedVessel = imdilate(dilatedVessel, ones(3, 3));
end
diffImg(dilatedVessel) = 0;
diffImg(~m.MEASUREMENT_MASK) = 0;

candidates = {};
if ~any(diffImg(:) > 0)
    return;
end
% numpy's default percentile interpolation is linear; prctile's
% "inclusive" method matches it (R2022a+).
thresh = max(prctile(diffImg(m.MEASUREMENT_MASK), percentile, "Method", "inclusive"), 1e-4);
bw = diffImg > thresh;

% scipy.ndimage.label's default structure is 4-connectivity (a cross, no
% diagonals) in 2D - bwconncomp(bw, 4) matches, unlike the 8-connectivity
% used for cv2.connectedComponentsWithStats ports elsewhere.
cc = bwconncomp(bw, 4);
n = cc.NumObjects;
if n == 0
    return;
end
labels = labelmatrix(cc);
stats = regionprops(cc, 'BoundingBox');

for i = 1:n
    area = numel(cc.PixelIdxList{i});
    if area < minArea || area > maxArea
        continue;
    end
    bb = stats(i).BoundingBox;
    x0 = round(bb(1) - 0.5); y0 = round(bb(2) - 0.5);
    w = round(bb(3)); h = round(bb(4));
    maskLocal = labels(y0 + 1:y0 + h, x0 + 1:x0 + w) == i;
    [ysLocal, xsLocal] = find(maskLocal);
    cy = y0 + mean(double(ysLocal) - 1);
    cx = x0 + mean(double(xsLocal) - 1);
    candidates{end + 1} = struct('label_id', i, 'centroid', [cx, cy], ...  %#ok<AGROW>
        'area_px', area, 'bbox', [x0, y0, w, h], 'mask_local', maskLocal);
end
end


function closedMin = minClose(u8Img, len, nOrientations)
% Private helper (Python _min_close): minimum over closings by line
% structuring elements at nOrientations - a structure is filled only if
% some single line BRIDGES it (reused verbatim from the previous
% implementation's min_close: L=15 for microaneurysms, L=41 for
% haemorrhages).
closedMin = [];
for a = 0:(nOrientations - 1)
    maskLine = lineStrelBinaryMask(len, a * 180.0 / nOrientations);
    % Per the fidelity note: build the exact binary rotated-line mask (via
    % imrotate, approximating cv2.warpAffine, thresholded > 0) and pass it
    % to strel('arbitrary', ...), NOT strel('line', ...), whose pixel
    % pattern differs from a rasterised rotated line.
    se = strel('arbitrary', maskLine);
    closed = imclose(u8Img, se);
    if isempty(closedMin)
        closedMin = closed;
    else
        closedMin = min(closedMin, closed);
    end
end
end


function mask = lineStrelBinaryMask(len, deg)
% Private helper (Python _line_se, binary variant): centre-row line
% rotated about the kernel centre via imrotate('bilinear','crop')
% (approximating cv2.warpAffine + getRotationMatrix2D), thresholded > 0.
se = zeros(len, len);
se(floor(len / 2) + 1, :) = 1;
rotated = imrotate(se, deg, 'bilinear', 'crop');
mask = rotated > 0;
end

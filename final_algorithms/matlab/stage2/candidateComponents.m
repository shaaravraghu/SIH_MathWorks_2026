function components = candidateComponents(candidateMask, minAreaPx)
%CANDIDATECOMPONENTS Connected-component candidate list from a binary
%   candidate mask: bbox=[x y w h] (0-based), mask_local (logical, cropped
%   to bbox), centroid=[cx cy] (0-based), area_px. Mirrors
%   lesion_pipeline.py _candidate_components (cv2.connectedComponentsWithStats
%   -> bwconncomp/regionprops, per the library-mapping note).
%
%   Returns a 1xN cell array of structs (N may be 0).

if nargin < 2 || isempty(minAreaPx)
    minAreaPx = 3; % placeholder: drop single/near-single-pixel noise before feature extraction
end

cc = bwconncomp(candidateMask, 8);
stats = regionprops(cc, 'Area', 'BoundingBox', 'Centroid');
labels = labelmatrix(cc);

components = {};
for i = 1:numel(stats)
    area = round(stats(i).Area);
    if area < minAreaPx
        continue;
    end
    bb = stats(i).BoundingBox; % regionprops convention: [x y w h], x/y at pixel-corner (n - 0.5)
    x0 = round(bb(1) - 0.5); y0 = round(bb(2) - 0.5); % -> 0-based pixel index, matching cv2's CC_STAT_LEFT/TOP
    w = round(bb(3)); h = round(bb(4));
    maskLocal = labels(y0 + 1:y0 + h, x0 + 1:x0 + w) == i;
    centroid1 = stats(i).Centroid; % 1-based pixel-centre [x y]
    components{end + 1} = struct( ...  %#ok<AGROW>
        'label_id', i, 'centroid', [centroid1(1) - 1, centroid1(2) - 1], ...
        'area_px', area, 'bbox', [x0, y0, w, h], 'mask_local', maskLocal);
end
end

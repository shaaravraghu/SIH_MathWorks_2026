function fov = buildFovMask(image, blackThresh)
%BUILDFOVMASK #2 FOV Detection: binary mask of the retinal FOV vs. the
%   black surround.
%   A pixel is considered "black" (background) if all channels are below
%   blackThresh. The FOV mask extents (not a traced boundary) are used to
%   derive horizontal/vertical radii, per the compute-reduction note in #2.1.
%
%   fov is a scalar struct with fields mask (logical), center_row,
%   center_col, horizontal_radius, vertical_radius -- mirrors Python's
%   FOVMask dataclass. Coordinates are 1-based (MATLAB convention) rather
%   than Python's 0-based, but all downstream quantities are extents and
%   ratios so the shift cancels out.

if nargin < 2 || isempty(blackThresh)
    blackThresh = 10;
end

if ndims(image) == 3
    isBlack = all(image <= blackThresh, 3);
else
    isBlack = image <= blackThresh;
end

mask = ~isBlack;

[ys, xs] = find(mask);
if isempty(ys)
    [h, w] = size(mask);
    fov = struct('mask', mask, 'center_row', floor(h / 2) + 1, 'center_col', floor(w / 2) + 1, ...
        'horizontal_radius', 0.0, 'vertical_radius', 0.0);
    return;
end

centerRow = round(mean(ys));
centerCol = round(mean(xs));

% Horizontal radius: half of the mask extent along the row through the centroid.
rowPixels = find(mask(centerRow, :));
if isempty(rowPixels)
    horizontalExtent = 0;
else
    horizontalExtent = max(rowPixels) - min(rowPixels) + 1;
end
horizontalRadius = horizontalExtent / 2.0;

% Vertical radius: half of the mask extent along the column through the centroid.
colPixels = find(mask(:, centerCol));
if isempty(colPixels)
    verticalExtent = 0;
else
    verticalExtent = max(colPixels) - min(colPixels) + 1;
end
verticalRadius = verticalExtent / 2.0;

fov = struct('mask', mask, 'center_row', centerRow, 'center_col', centerCol, ...
    'horizontal_radius', horizontalRadius, 'vertical_radius', verticalRadius);
end

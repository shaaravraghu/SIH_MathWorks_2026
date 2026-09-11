function [lengths, labels, n, area] = componentLengths(bw)
%COMPONENTLENGTHS Skeleton length without thinning: w ~ 4*mean(EDT),
%   L ~ area/w (reused verbatim from the previous implementation - ~160x
%   faster than thinning, vectorised over all components). Mirrors
%   features.py _component_lengths.
%
%   scipy.ndimage.label's default structure is 4-connectivity (a cross, no
%   diagonals) in 2D, NOT 8-connectivity - bwconncomp(bw, 4) is used here to
%   match, unlike the 8-connectivity used elsewhere for
%   cv2.connectedComponentsWithStats ports.

cc = bwconncomp(bw, 4);
n = cc.NumObjects;
labels = labelmatrix(cc);
if n == 0
    lengths = zeros(0, 1);
    area = zeros(0, 1);
    return;
end

area = cellfun(@numel, cc.PixelIdxList)';
edt = bwdist(~bw); % distance_transform_edt(bw) -> bwdist(~bw), per the library-mapping note
esum = cellfun(@(idx) sum(edt(idx)), cc.PixelIdxList)';
width = 4.0 * esum ./ max(area, 1);
lengths = area ./ max(width, 1e-6);
end

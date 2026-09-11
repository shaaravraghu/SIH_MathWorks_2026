function se = ellipseStrel(ksize)
%ELLIPSESTREL Rasterised elliptical structuring element for a square
%   ksize x ksize kernel, replicating OpenCV's own
%   cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksize, ksize)) row-scan
%   rasterisation algorithm exactly, rather than MATLAB's strel('disk', ...)
%   (which approximates a disk with a different, line-based algorithm and
%   would give a visibly different pixel pattern). Returns a
%   strel('arbitrary', ...) object.

r = floor(ksize / 2);
mask = false(ksize, ksize);
for i = 0:(ksize - 1)
    dy = i - r;
    if abs(dy) <= r
        if r > 0
            dx = round(r * sqrt((r * r - dy * dy) / (r * r)));
        else
            dx = 0;
        end
        lo = max(r - dx, 0);
        hi = min(r + dx, ksize - 1);
        mask(i + 1, lo + 1:hi + 1) = true;
    end
end
se = strel('arbitrary', mask);
end

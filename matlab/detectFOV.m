function fov = detectFOV(I)
%DETECTFOV  Locate the circular retinal field of view in a fundus image.
%
%   fov = detectFOV(I) takes an RGB fundus image and returns a struct with
%   the retinal disc geometry plus the quality features derived from it.
%
%   Channel choice: we threshold the RED channel.  Haemoglobin barely
%   absorbs above 600 nm, so the retina returns red light almost uniformly
%   and appears as a flat bright disc on black -- ideal for thresholding.
%   The green channel is the one with lesion contrast, which is exactly why
%   it is the wrong choice here (vessels would punch holes in the mask).
%
%   Output fields:
%     mask         logical retinal mask
%     maskMeasure  mask eroded by 2% of R -- USE THIS for every metric
%     centre       [cx cy] disc centre in pixels
%     radius       fitted disc radius in pixels
%     residual     mean |dist-R| / R  -- SHAPE FEATURE, prefer over circularity
%     raggedness   observed boundary px / (2*pi*R)  -- threshold sanity
%     circularity  4*pi*A/P^2  (unreliable on real data -- see notes)
%     areaFrac     captured area / pi*R^2  (low => badly clipped)
%     offset       |centre - image centre| / R  (camera misalignment)
%     borderFrac   fraction of the disc boundary touching the image edge
%     ok           false if detection failed -- CHECK THIS FIRST
%
%   Validated on 150 stratified APTOS 2019 images: 100% detection after the
%   raggedness retry below (96.7% without it).

% ---- 0. normalise type ------------------------------------------------
% im2double once, at the top.  uint8 arithmetic SATURATES in MATLAB, so any
% subtraction downstream would silently clamp negatives to zero.
I = im2double(I);

if size(I,3) == 3
    Ir = I(:,:,1);                      % red = silhouette channel
else
    Ir = I;
end

% Degenerate red channel (red-free capture, or an already-processed image).
if size(I,3) == 3 && std(Ir(:)) < 0.01
    Ir = max(I, [], 3);
end

% ---- 1. threshold, with a raggedness retry ----------------------------
% Otsu assumes a bimodal histogram.  On bright or washed-out fundus images
% that assumption fails and Otsu picks a threshold INSIDE the retina.  The
% resulting mask still has a plausible AREA -- so an area-fraction guard
% alone does not catch it -- but its boundary is speckled and ragged.
%
% Measured on 5 APTOS failures: Otsu gave raggedness 1.67-2.12 and fit
% residual 0.07-0.22.  The relative-threshold fallback gave 0.90-1.37 and
% 0.002-0.042 on the same images.  So: detect raggedness, then retry.

fov = tryThreshold(Ir, graythresh(Ir));

needRetry = ~fov.ok || fov.raggedness > 1.4 || ...
            fov.areaFrac < 0.15 || fov.areaFrac > 1.6;

if needRetry
    pos = Ir(Ir > 0.02);
    if ~isempty(pos)
        alt = tryThreshold(Ir, 0.5 * mean(pos));
        if alt.ok && (~fov.ok || alt.raggedness < fov.raggedness)
            fov = alt;
        end
    end
end

if ~fov.ok
    return                              % caller must check fov.ok
end

% ---- 2. finish up -----------------------------------------------------
[h, w] = size(Ir);
fov.offset = hypot(fov.centre(1) - w/2, fov.centre(2) - h/2) / fov.radius;

% The FOV rim is a ~200-level intensity cliff.  Left in, it dominates every
% gradient- and Laplacian-based focus measure, and a totally blurred image
% still scores "sharp".  Erode by 2% of R before measuring anything.
fov.maskMeasure = imerode(fov.mask, ...
                          strel('disk', max(3, round(0.02*fov.radius))));

end

% =======================================================================
function f = tryThreshold(Ir, t)
%TRYTHRESHOLD  Build a mask and circle fit from one threshold value.

f = struct('ok', false, 'mask', [], 'maskMeasure', [], 'centre', [NaN NaN], ...
           'radius', NaN, 'residual', NaN, 'raggedness', NaN, ...
           'circularity', NaN, 'areaFrac', NaN, 'offset', NaN, 'borderFrac', NaN);

bw = Ir > t;
if nnz(bw) < 100, return, end

% ORDER MATTERS.  bwareafilt MUST come before imfill.
%
% If the image has a bright frame around its edge -- a camera border, a
% burned-in annotation strip, or a 1-px rule from a figure export -- that
% frame encircles the black surround.  The surround is then no longer
% connected to the array border, so imfill treats it as a HOLE and floods
% the entire frame.  Selecting the largest component first discards the
% frame and makes imfill safe.
bw = bwareafilt(bw, 1);
bw = imfill(bw, 'holes');
bw = imopen(bw, strel('disk', 5));
bw = imfill(bw, 'holes');

if mean(bw(:)) > 0.98 || nnz(bw) < 100, return, end

[h, w] = size(bw);
B = bwboundaries(bw, 'noholes');
if isempty(B), return, end
p = B{1};
y = p(:,1);  x = p(:,2);
if numel(y) < 50, return, end

onEdge = y <= 2 | y >= h-1 | x <= 2 | x >= w-1;

% Points on a straight sensor edge are not on the circle -- drop them.
if nnz(~onEdge) > 50
    fx = x(~onEdge);  fy = y(~onEdge);
else
    fx = x;  fy = y;
end

[cx, cy, R] = kasa(fx, fy);
if ~isfinite(R) || R < 0.05*min(h,w) || R > 3*max(h,w), return, end

% One reweight pass: notches, eyelid intrusions and lash shadows pull
% boundary points off the true circle.
res  = abs(hypot(fx - cx, fy - cy) - R);
keep = res < max(5, 3*median(res));
if nnz(keep) > 50
    [cx, cy, R] = kasa(fx(keep), fy(keep));
end
if ~isfinite(R) || R < 0.05*min(h,w) || R > 3*max(h,w), return, end

A = nnz(bw);
P = numel(y);

f.ok          = true;
f.mask        = bw;
f.centre      = [cx, cy];
f.radius      = R;
% Mean radial deviation, normalised by R.  This is the SHAPE feature to
% use: it needs no perimeter estimate, so it is not confounded by boundary
% raggedness the way 4*pi*A/P^2 is.  Good masks measure < 0.01.
f.residual    = mean(abs(hypot(fx - cx, fy - cy) - R)) / R;
% Observed boundary length vs the fitted circumference.  ~1.0-1.3 for a
% clean circle; > 1.5 means the threshold landed inside the retina.
f.raggedness  = P / (2*pi*R);
f.circularity = 4*pi*A / P^2;           % kept for reference; see notes
f.areaFrac    = A / (pi*R^2);
f.borderFrac  = mean(onEdge);

end

% =======================================================================
function [cx, cy, R] = kasa(x, y)
%KASA  Algebraic circle fit.
%   Expand (x-cx)^2 + (y-cy)^2 = R^2 to
%       x^2 + y^2 = 2*cx*x + 2*cy*y + (R^2 - cx^2 - cy^2)
%   which is LINEAR in [cx, cy, c].  One backslash.
A   = [2*x, 2*y, ones(numel(x),1)];
sol = A \ (x.^2 + y.^2);
cx  = sol(1);
cy  = sol(2);
R   = sqrt(sol(3) + cx^2 + cy^2);
end

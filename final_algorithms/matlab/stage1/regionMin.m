function result = regionMin(gray, lapResult, fovMask)
%REGIONMIN #3.4 Region Min, final stage of the #3 cascade.
%   #3 Region Min is RETAINED: it is the only metric in this cascade that
%   detects PARTIAL blur. Global metrics average a locally-blurred region
%   away, so an image that is sharp everywhere except the macula passes
%   every other test and is still clinically useless. Measured
%   partial-blur sensitivity is ~4,100x. The deployment scenario is
%   portable cameras operated by technicians with short training, not
%   medical-grade capture, so partial defocus and local motion blur must
%   be assumed (notes #3).
%
%   Split the retinal area into 5 regions (centre + 4 quadrants), compute
%   the focus metric (variance-of-Laplacian, NORMED) per region, and take
%   the MINIMUM across them -- a single weak region is enough to fail the
%   image, and the minimum surfaces it where a whole-image mean would hide
%   it (notes #3.4). Reuses the Laplacian samples already computed in
%   #3.1 (lapResult), so this is only 5 grouped statistics over an
%   existing array -- negligible added cost.
%   The per-resolution calibrated thresholds come from
%   stage1SharpnessThresholds.

if nargin < 3
    fovMask = [];
end

thresholds = stage1SharpnessThresholds(size(gray));
THRESH_REGION_MIN_FAIL = thresholds.region_min_fail;
THRESH_REGION_MIN_BORDERLINE = thresholds.region_min_borderline;

h = size(gray, 1);
w = size(gray, 2);
rows = lapResult.rows;
cols = lapResult.cols;
lapVals = lapResult.lap_vals;

if ~isempty(fovMask) && any(fovMask(:))
    [ys, xs] = find(fovMask);
    r0 = min(ys); r1 = max(ys);
    c0 = min(xs); c1 = max(xs);
else
    r0 = 1; r1 = h; c0 = 1; c1 = w;
end

cy = floor((r0 + r1) / 2);
cx = floor((c0 + c1) / 2);
qh = floor((r1 - r0) / 4); % quarter spans for the centre region
qw = floor((c1 - c0) / 4);

regionNames = {"top_left", "top_right", "bottom_left", "bottom_right", "centre"};
regionBounds = {
    [r0, cy, c0, cx]
    [r0, cy, cx, c1]
    [cy, r1, c0, cx]
    [cy, r1, cx, c1]
    [max(r0, cy - qh), min(r1, cy + qh), max(c0, cx - qw), min(c1, cx + qw)]
    };

regionScores = struct();
scoreVals = zeros(1, 5);
for i = 1:5
    b = regionBounds{i};
    rr0 = b(1); rr1 = b(2); cc0 = b(3); cc1 = b(4);
    inRegion = (rows >= rr0) & (rows < rr1) & (cols >= cc0) & (cols < cc1);
    if sum(inRegion) < 2
        s = 0.0;
    else
        s = normedVariance(lapVals(inRegion), gray(sub2ind(size(gray), rows(inRegion), cols(inRegion))));
    end
    regionScores.(regionNames{i}) = s;
    scoreVals(i) = s;
end

[minScore, minIdx] = min(scoreVals);
minRegion = regionNames{minIdx};

if minScore < THRESH_REGION_MIN_FAIL
    status = "fail";
elseif minScore < THRESH_REGION_MIN_BORDERLINE
    status = "borderline";
else
    status = "pass";
end

result = struct('region_scores', regionScores, 'min_region', minRegion, 'score', minScore, 'status', status);
end

function result = brennerGradientGate(gray, rngStream)
%BRENNERGRADIENTGATE #3.2 Brenner Gradient gate, first stage of the #3 cascade.
%   The notes pin no numeric threshold; the per-resolution calibrated one
%   comes from stage1SharpnessThresholds. The sampling/metric math itself
%   follows the notes exactly.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

thresholds = stage1SharpnessThresholds(size(gray));
THRESH_BRENNER_FAIL = thresholds.brenner_fail;

boxes = sampleSquaresInDisk(size(gray), [], [], rngStream);
n = size(boxes, 1);
scores = zeros(n, 1);
for i = 1:n
    r0 = boxes(i, 1); r1 = boxes(i, 2); c0 = boxes(i, 3); c1 = boxes(i, 4);
    scores(i) = brennerGradient(gray(r0:r1, c0:c1));
end

if n > 0
    score = mean(scores);
else
    score = 0.0;
end

if score < THRESH_BRENNER_FAIL
    status = "fail";
else
    status = "pass";
end

result = struct('score', score, 'status', status, 'n_patches', n);
end

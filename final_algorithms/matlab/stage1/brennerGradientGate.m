function result = brennerGradientGate(gray, rngStream)
%BRENNERGRADIENTGATE #3.2 Brenner Gradient gate, first stage of the #3 cascade.
%   NOTE: exact pass/fail/borderline numeric thresholds for #3.1-#3.3 are
%   not pinned in the source notes (only the sampling strategy is). The
%   THRESH_* constant below is a placeholder that must be calibrated
%   empirically before this gate is used to reject images; the
%   sampling/metric math itself follows the notes exactly.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

THRESH_BRENNER_FAIL = 50.0; % placeholder, needs calibration

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

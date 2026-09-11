function result = tenengradVarGate(gray, rngStream)
%TENENGRADVARGATE #3.3 TenengradVar gate, third stage of the #3 cascade
%   (confirmation for Variance of Laplacian (NORMED)).
%   NOTE: exact pass/fail/borderline numeric thresholds for #3.1-#3.3 are
%   not pinned in the source notes (only the sampling strategy is). The
%   THRESH_* constants below are placeholders that must be calibrated
%   empirically before this gate is used to reject images.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

THRESH_TENENGRAD_VAR_FAIL = 0.02; % placeholder, needs calibration
THRESH_TENENGRAD_VAR_BORDERLINE = 0.05; % placeholder, needs calibration

boxes = sampleSquaresInDisk(size(gray), [], [], rngStream);
n = size(boxes, 1);
scores = zeros(n, 1);
for i = 1:n
    r0 = boxes(i, 1); r1 = boxes(i, 2); c0 = boxes(i, 3); c1 = boxes(i, 4);
    scores(i) = tenengradVar(gray(r0:r1, c0:c1));
end

if n > 0
    score = mean(scores);
else
    score = 0.0;
end

if score < THRESH_TENENGRAD_VAR_FAIL
    status = "fail";
elseif score < THRESH_TENENGRAD_VAR_BORDERLINE
    status = "borderline";
else
    status = "pass";
end

result = struct('score', score, 'status', status, 'n_patches', n);
end

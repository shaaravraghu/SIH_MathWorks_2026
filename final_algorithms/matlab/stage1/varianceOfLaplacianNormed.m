function result = varianceOfLaplacianNormed(gray, rngStream)
%VARIANCEOFLAPLACIANNORMED #3.1 Variance of Laplacian (NORMED) gate.
%   Logic to be applied: pick a random 10% of the points within the
%   0.75*height-diameter disk (centred at the image midpoint) and evaluate
%   a 5-point-stencil Laplacian against the (Right, Left, Up, Down)
%   neighbours at each sampled point, avoiding a full-image convolution
%   (notes #3.1).
%   NOTE: exact pass/fail/borderline numeric thresholds for #3.1-#3.3 are
%   not pinned in the source notes (only the sampling strategy is). The
%   THRESH_* constants below are placeholders that must be calibrated
%   empirically before these gates are used to reject images; the
%   sampling/metric math itself follows the notes exactly.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

THRESH_LAPLACIAN_VAR_NORMED_FAIL = 0.0015; % placeholder, needs calibration
THRESH_LAPLACIAN_VAR_NORMED_BORDERLINE = 0.0030; % placeholder, needs calibration

[rows, cols] = samplePointsInDisk(size(gray), [], [], rngStream);

if isempty(rows)
    result = struct('score', 0.0, 'status', "fail", 'rows', rows, 'cols', cols, 'lap_vals', []);
    return;
end

lapVals = pointLaplacian(gray, rows, cols);
intensities = gray(sub2ind(size(gray), rows, cols));
normedVar = normedVariance(lapVals, intensities);

if normedVar < THRESH_LAPLACIAN_VAR_NORMED_FAIL
    status = "fail";
elseif normedVar < THRESH_LAPLACIAN_VAR_NORMED_BORDERLINE
    status = "borderline";
else
    status = "pass";
end

result = struct('score', normedVar, 'status', status, 'n_points', numel(rows), ...
    'rows', rows, 'cols', cols, 'lap_vals', lapVals);
end


function lap = pointLaplacian(gray, rows, cols)
% Private helper (Python _point_laplacian): 5-point-stencil Laplacian
% evaluated only at sampled points (Right, Left, Up, Down neighbours),
% avoiding a full-image convolution.
sz = size(gray);
centerIdx = sub2ind(sz, rows, cols);
rightIdx = sub2ind(sz, rows, cols + 1);
leftIdx = sub2ind(sz, rows, cols - 1);
upIdx = sub2ind(sz, rows - 1, cols);
downIdx = sub2ind(sz, rows + 1, cols);
lap = gray(rightIdx) + gray(leftIdx) + gray(upIdx) + gray(downIdx) - 4.0 * gray(centerIdx);
end

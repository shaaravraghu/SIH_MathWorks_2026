function [map, parts] = lesionEvidenceMap(eye, options)
%LESIONEVIDENCEMAP Stage 4: a spatial attention map built from Stage 2's own
%   detections, on the 872x872 working grid.
%
%   THIS IS NOT GRAD-CAM, and must never be labelled as such. Grad-CAM
%   backpropagates a class score into a convolutional feature map; this
%   pipeline has no CNN, so there is no feature map to attribute onto. What
%   this produces is the other half of the explainability spec -- "lesion-level
%   evidence correlated with clinical criteria" -- as a heat map: every lesion
%   the detector kept, and every fine-scale-excess (neovascularisation) pixel,
%   stamped at its own location and blurred to disc-diameter scale.
%
%   It is causally grounded in a way Grad-CAM is not: each hot region
%   corresponds to a specific detected structure that the report can name and
%   count, rather than to a gradient that may highlight a clinically
%   irrelevant region (a documented Grad-CAM failure mode in medical imaging).
%
%   report: the struct from runStage2.
%   map:    double, 0..1, same size as the working grid.
%   parts:  per-source maps (ma, haem, hard_exudate, cws, nv), same scaling,
%           so a viewer can show one lesion class at a time.
%
%   The class weights below are DISPLAY weights -- they set how strongly each
%   finding draws the eye, and carry no clinical meaning. The grade itself
%   comes from Stage 3, never from this map.

arguments
    eye struct
    options.Sigma (1,1) double = 31        % ~0.25 disc diameters at DD_PX = 124
    options.Weights (1,1) struct = struct('ma', 0.8, 'haem', 1.0, ...
        'hard_exudate', 0.6, 'cws', 0.6, 'nv', 1.2)
end

report = eye.stage2;
sz = size(report.vessels.matched_filter_mask);

% Same detections the panels draw and the report counts (see gradeOneEye).
fields = {'ma', 'haem', 'hard_exudate', 'cws'};

parts = struct();
accumulated = zeros(sz);

for k = 1:numel(fields)
    field = fields{k};
    layer = zeros(sz);
    if isfield(eye, 'detections') && isfield(eye.detections, field)
        det = eye.detections.(field);
        for i = 1:det.n_kept
            row = min(max(round(det.centroids(i, 2)) + 1, 1), sz(1));
            col = min(max(round(det.centroids(i, 1)) + 1, 1), sz(2));
            layer(row, col) = layer(row, col) + max(det.areas(i), 1);
        end
    end
    layer = imgaussfilt(layer, options.Sigma);
    parts.(field) = normalise(layer);
    accumulated = accumulated + options.Weights.(field) * layer;
end

% Neovascularisation: a pixel mask rather than discrete candidates.
nvLayer = zeros(sz);
if isfield(report.vessels, 'excess_mask') && ~isempty(report.vessels.excess_mask)
    nvLayer = double(report.vessels.excess_mask);
end
nvLayer = imgaussfilt(nvLayer, options.Sigma);
parts.nv = normalise(nvLayer);
accumulated = accumulated + options.Weights.nv * nvLayer;

map = normalise(accumulated);
end


function layer = stampCandidate(layer, candidate, sz)
% Paint the candidate's own pixels where its local mask survived the cache,
% otherwise a single point at its centroid (0-based -> 1-based).
if isfield(candidate, 'mask_local') && isfield(candidate, 'bbox') && ~isempty(candidate.mask_local)
    bb = candidate.bbox;  % [x y w h], 0-based
    r0 = bb(2) + 1; c0 = bb(1) + 1;
    r1 = min(r0 + bb(4) - 1, sz(1));
    c1 = min(c0 + bb(3) - 1, sz(2));
    if r1 >= r0 && c1 >= c0
        patch = candidate.mask_local(1:(r1 - r0 + 1), 1:(c1 - c0 + 1));
        layer(r0:r1, c0:c1) = layer(r0:r1, c0:c1) + double(patch);
        return
    end
end
row = min(max(round(candidate.centroid(2)) + 1, 1), sz(1));
col = min(max(round(candidate.centroid(1)) + 1, 1), sz(2));
layer(row, col) = layer(row, col) + 1;
end


function out = normalise(x)
peak = max(x(:));
if peak <= 0
    out = zeros(size(x));
else
    out = x / peak;
end
end

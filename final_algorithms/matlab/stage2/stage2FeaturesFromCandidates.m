function row = stage2FeaturesFromCandidates(candidates, classifiers)
%STAGE2FEATURESFROMCANDIDATES Turns cached, classifier-free candidates
%   (from extractStage2Candidates) into the S2-01..S2-45 row. Mirrors
%   features.py stage2_features_from_candidates.
%
%   classifiers (optional): scalar struct with optional fields
%   ma/haem/hard_exudate/cws, each either a fitted MATLAB classifier
%   (scored via predict(model, X), positive class in column 2), or a
%   struct with fields model and (optionally) threshold. A missing/empty
%   entry falls back to classifyCandidates()'s placeholder rule.
%
%   row: scalar struct with the 45 STAGE2_COLUMNS fields, in column order.

if nargin < 2 || isempty(classifiers)
    classifiers = struct();
end

row = candidates.image_features;

od = candidates.optic_disc;
fovea = candidates.fovea;
odCenter = [od.center_x, od.center_y];
foveaPoint = [fovea.x, fovea.y];
venousBeadingQuadrants = row.venous_beading_quadrants;
nvIrmaQuadrants = row.nv_irma_quadrants;

m = stage2Masks();
c = stage2Constants();
mmArea = sum(m.MEASUREMENT_MASK(:));

% haemorrhages
haem = candidates.lesion_candidates.haem;
[model, thresh] = resolveClassifier(classifierEntry(classifiers, 'haem'));
keep = classifyCandidates(haem.features, model, thresh);
counts = lesionQuadrantCounts(haem.centroids(keep, :), odCenter, foveaPoint);
row.haem_count = sum(keep);
row.haem_q1 = counts(1); row.haem_q2 = counts(2); row.haem_q3 = counts(3); row.haem_q4 = counts(4);
row.haem_q_min = min(counts); row.haem_q_max = max(counts);
row.rule421_haem = double(row.haem_q_min > quadrantCountThreshold());

% microaneurysms
ma = candidates.lesion_candidates.ma;
[model, thresh] = resolveClassifier(classifierEntry(classifiers, 'ma'));
keep = classifyCandidates(ma.features, model, thresh);
counts = lesionQuadrantCounts(ma.centroids(keep, :), odCenter, foveaPoint);
row.ma_count = sum(keep);
row.ma_q1 = counts(1); row.ma_q2 = counts(2); row.ma_q3 = counts(3); row.ma_q4 = counts(4);

% hard exudates
exu = candidates.lesion_candidates.hard_exudate;
[model, thresh] = resolveClassifier(classifierEntry(classifiers, 'hard_exudate'));
keep = classifyCandidates(exu.features, model, thresh);
row.hard_exudate_count = sum(keep);
row.hard_exudate_area_pct = 100.0 * sum(exu.areas(keep)) / max(mmArea, 1.0);

maxPossibleDistDd = (2 * c.TARGET_R * sqrt(2.0)) / c.DD_PX;
if any(keep)
    keptCentroids = exu.centroids(keep, :);
    dists = hypot(keptCentroids(:, 1) - fovea.x, keptCentroids(:, 2) - fovea.y) / c.DD_PX;
    row.exudate_fovea_min_dist_dd = min(dists);
else
    row.exudate_fovea_min_dist_dd = maxPossibleDistDd;
end

if isfield(exu, 'dme_touch')
    dmeTouchArr = exu.dme_touch;
else
    dmeTouchArr = false(numel(keep), 1);
end
if any(keep)
    row.dme_flag = double(any(dmeTouchArr(keep)));
else
    row.dme_flag = 0;
end

% cotton-wool spots (nerve fibre ischemia)
cws = candidates.lesion_candidates.cws;
[model, thresh] = resolveClassifier(classifierEntry(classifiers, 'cws'));
keep = classifyCandidates(cws.features, model, thresh);
row.cws_count = sum(keep);
row.cws_area_pct = 100.0 * sum(cws.areas(keep)) / max(mmArea, 1.0);

row.rule421_beading = double(venousBeadingQuadrants >= 2);
row.rule421_irma = double(nvIrmaQuadrants >= 1);
row.severe_npdr_flag = double(row.rule421_haem || row.rule421_beading || row.rule421_irma);

columns = stage2Columns();
out = struct();
for i = 1:numel(columns)
    out.(columns{i}) = row.(columns{i});
end
row = out;
end


function entry = classifierEntry(classifiers, name)
if isfield(classifiers, name)
    entry = classifiers.(name);
else
    entry = [];
end
end

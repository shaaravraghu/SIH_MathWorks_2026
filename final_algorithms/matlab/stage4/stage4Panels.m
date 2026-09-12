function outPath = stage4Panels(eye, outPath)
%STAGE4PANELS Stage 4: the labelled Stage 2 segmentation figure for one eye.
%
%   Eight panels on the 872x872 working grid: the image, the vessel map, the
%   calibre tiering, the fine-scale excess (neovascularisation), and one panel
%   per lesion class showing the kept detections over the retina with the
%   OD-fovea quadrant axes drawn.
%
%   Every panel title carries its own number, so the figure is readable
%   without the caller: percentages for the vessel map, nv_score for the
%   excess map, and "N cand, M kept" for each lesion class -- the gap between
%   those two is the classifier's contribution and is worth seeing.

arguments
    eye struct
    outPath (1,1) string
end

r = eye.stage2;
sz = size(r.vessels.matched_filter_mask);
img = eye.image_work;
od = [r.optic_disc.center_x, r.optic_disc.center_y];
fovea = [r.fovea.x, r.fovea.y];

fig = figure(Visible="off", Position=[100 100 1600 860], Color='w');
tl = tiledlayout(fig, 2, 4, TileSpacing="compact", Padding="compact");

title(tl, sprintf('%s eye (%s)   |   OD (%.0f, %.0f) r=%.0f   fovea (%.0f, %.0f)   haem/quadrant [%s]   4-2-1: %d', ...
    upperFirst(eye.side), eye.id, od(1), od(2), r.optic_disc.radius, fovea(1), fovea(2), ...
    strjoin(compose('%d', r.quadrants.counts), ' '), r.quadrants.four_two_one), ...
    FontWeight='bold', Interpreter='none');

% 1 -- the image Stage 2 actually measured
nexttile; imshow(img); title(sprintf('1. Working resolution (%dx%d)', sz(2), sz(1)));

% 2 -- vessels
vessel = r.vessels.matched_filter_mask;
nexttile; imshow(vessel);
title(sprintf('2. Vessels -- matched filter (%.1f%%)', 100 * nnz(vessel) / numel(vessel)));

% 3 -- calibre tiers. The calibre map is int8 with 0..3 for the four bands and
% a negative for "not a vessel"; label2rgb needs nonnegative labels, so shift
% the bands to 1..4 and leave the background at 0 (drawn black).
calibre = double(r.vessels.calibre);
calibreLabels = zeros(size(calibre));
isVessel = calibre >= 0;
calibreLabels(isVessel) = calibre(isVessel) + 1;
nexttile; imshow(label2rgb(calibreLabels, [1 0 0; 1 0.55 0; 1 1 0; 0.25 0.8 1], 'k'));
title('3. Calibre: beading/major/branch/minor');

% 4 -- fine-scale excess (the NV signal)
excess = false(sz);
if isfield(r.vessels, 'excess_mask') && ~isempty(r.vessels.excess_mask)
    excess = r.vessels.excess_mask;
end
nexttile; imshow(excess);
title(sprintf('4. Fine-scale excess   nv\\_score %.2f', r.nv_score));

% 5-8 -- one panel per lesion class
% Drawn as rings, not masks: a microaneurysm is a handful of pixels on an
% 872 px grid and simply disappears at panel scale -- earlier versions of this
% figure looked empty while holding 106 detections. The ring is sized from the
% candidate's own measured area, floored so the smallest lesions stay visible.
classes = { ...
    'ma',           'Microaneurysm', [1 0 0]; ...
    'haem',         'Haemorrhage',   [0.7 0.2 1]; ...
    'hard_exudate', 'Hard exudate',  [1 0.85 0]; ...
    'cws',          'Cotton-wool',   [1 1 1]};

for k = 1:size(classes, 1)
    field = classes{k, 1};
    det = struct('centroids', zeros(0, 2), 'areas', zeros(0, 1), 'n_candidates', 0, 'n_kept', 0);
    if isfield(eye, 'detections') && isfield(eye.detections, field)
        det = eye.detections.(field);
    end

    ax = nexttile;
    imshow(img, Parent=ax);
    hold(ax, 'on');
    if det.n_kept > 0
        radii = max(7, 2.2 * sqrt(max(det.areas, 1) / pi));
        viscircles(ax, det.centroids + 1, radii, Color=classes{k, 3}, ...
            LineWidth=1.1, EnhanceVisibility=false);
    end
    drawLandmarks(od, fovea, sz);
    hold(ax, 'off');
    title(ax, sprintf('%d. %s: %d cand, %d kept', k + 4, classes{k, 2}, ...
        det.n_candidates, det.n_kept));
end

exportgraphics(fig, outPath, Resolution=150);
close(fig);
end


function drawLandmarks(od, fovea, sz)
% Optic disc, fovea, and the quadrant axes anchored to the OD-fovea line
% (quadrants are defined on that axis, not on the frame -- Stage_2_CNN).
axisDeg = atan2d(fovea(2) - od(2), fovea(1) - od(1));
L = max(sz);
for extra = [0 90]
    theta = deg2rad(axisDeg + extra);
    plot(od(1) + 1 + [-L L] * cos(theta), od(2) + 1 + [-L L] * sin(theta), ...
        'w--', LineWidth=0.75);
end
plot(od(1) + 1, od(2) + 1, 'c+', MarkerSize=10, LineWidth=1.5);
plot(fovea(1) + 1, fovea(2) + 1, 'g+', MarkerSize=10, LineWidth=1.5);
xlim([1 sz(2)]); ylim([1 sz(1)]);
end


function s = upperFirst(s)
s = char(string(s));
if isempty(s), s = '?'; return; end
s(1) = upper(s(1));
end

function outPath = attentionOverlay(eye, outPath, options)
%ATTENTIONOVERLAY Stage 4: the lesion-evidence attention map over the retina.
%
%   HONEST LABELLING MATTERS HERE. The figure is titled "lesion evidence", not
%   "Grad-CAM", because it is not Grad-CAM: no CNN exists in this pipeline, so
%   no class score is being backpropagated into a convolutional feature map.
%   Every hot region here is a structure Stage 2 actually detected and the
%   report can name and count, which is the "lesion-level evidence correlated
%   with clinical criteria" half of the explainability spec.
%
%   Reading it: red is where the detected findings concentrate, blue is quiet
%   retina. The colour scale is relative to this image's own peak, so a hot
%   region on a healthy eye does NOT mean disease -- always read it next to
%   the grade and the counts, never alone.

arguments
    eye struct
    outPath (1,1) string
    options.Alpha (1,1) double = 0.45
    options.Floor (1,1) double = 0.12   % below this the map is left transparent
end

img = eye.image_work;
map = eye.evidence_map;

fig = figure(Visible="off", Position=[100 100 760 800], Color='w');
ax = axes(fig);
imshow(img, Parent=ax);
hold(ax, 'on');

alphaData = options.Alpha * double(map > options.Floor) .* map;
overlay = imagesc(ax, map);
overlay.AlphaData = alphaData;
colormap(ax, jet);
clim(ax, [0 1]);

cb = colorbar(ax);
cb.Label.String = 'relative evidence density';

od = [eye.stage2.optic_disc.center_x, eye.stage2.optic_disc.center_y];
fovea = [eye.stage2.fovea.x, eye.stage2.fovea.y];
plot(ax, od(1) + 1, od(2) + 1, 'c+', MarkerSize=12, LineWidth=2);
plot(ax, fovea(1) + 1, fovea(2) + 1, 'g+', MarkerSize=12, LineWidth=2);
hold(ax, 'off');

title(ax, sprintf('%s eye -- lesion evidence attention', upperFirst(eye.side)), ...
    FontWeight='bold');
subtitle(ax, sprintf('grade %d  |  referable p = %.2f  |  nv\\_score %.2f', ...
    eye.grade, eye.referable_probability, eye.stage2.nv_score));

exportgraphics(fig, outPath, Resolution=150);
close(fig);
end


function s = upperFirst(s)
s = char(string(s));
if isempty(s), s = '?'; return; end
s(1) = upper(s(1));
end

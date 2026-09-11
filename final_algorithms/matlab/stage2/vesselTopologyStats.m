function stats = vesselTopologyStats(vesselMask, green01)
%VESSELTOPOLOGYSTATS Vessel density/fragmentation/components/largest-tree/
%   length/orientation-coherence, all reused from the previous
%   implementation. Mirrors features.py _vessel_topology_stats.

m = stage2Masks();
mmArea = sum(m.MEASUREMENT_MASK(:));
bw = vesselMask & m.MEASUREMENT_MASK;
[lengths, ~, n, area] = componentLengths(bw);
total = sum(bw(:));
if n > 0
    vesselLength = sum(lengths);
else
    vesselLength = 0.0;
end

stats = struct();
stats.vessel_density_pct = 100.0 * double(total) / max(double(mmArea), 1.0);
stats.vessel_components = n;
if n > 0
    stats.vessel_largest_tree_pct = 100.0 * double(max(area)) / max(double(total), 1);
else
    stats.vessel_largest_tree_pct = 0.0;
end
stats.vessel_length = vesselLength;
stats.vessel_fragmentation = 1000.0 * n / max(vesselLength, 1.0);

% ndimage.sobel(x, axis=1)/axis=0 are the standard 3x3 Sobel x-/y-
% derivative kernels; fspecial('sobel') is MATLAB's y-derivative-oriented
% kernel and its transpose the x-derivative (only squared/cross-product
% terms are used below, so any sign-convention mismatch is immaterial).
gx = imfilter(green01, fspecial('sobel')', 'replicate', 'same');
gy = imfilter(green01, fspecial('sobel'), 'replicate', 'same');
Jxx = imgaussfilt(gx .* gx, 2.0, 'Padding', 'symmetric');
Jyy = imgaussfilt(gy .* gy, 2.0, 'Padding', 'symmetric');
Jxy = imgaussfilt(gx .* gy, 2.0, 'Padding', 'symmetric');
traceJ = Jxx + Jyy;
discJ = sqrt(max((Jxx - Jyy) .^ 2 + 4 * Jxy .^ 2, 0));
coherence = discJ ./ max(traceJ, 1e-12);
coherence(~isfinite(coherence)) = 0;
if total > 0
    stats.vessel_orientation_coherence = mean(coherence(bw));
else
    stats.vessel_orientation_coherence = 0.0;
end
end

function touch = dmeTouch(centroids, areas, foveaPoint)
%DMETOUCH Approximate per-candidate pixel-level DME test: candidate touches
%   the 500um (34px) DME zone if its centroid, minus its own effective
%   radius (area-equivalent disc), lies within DME_RADIUS_PX of the fovea.
%   Documented approximation - an exact per-pixel mask test would need
%   every candidate's full-resolution mask retained; this uses only
%   centroid+area, which are already cacheable/classifier-free
%   (Module3_Plan.md S4.1). Mirrors features.py _dme_touch.

c = stage2Constants();
n = size(centroids, 1);
if n == 0
    touch = false(0, 1);
    return;
end
effRadius = sqrt(max(areas, 0) / pi);
dist = hypot(centroids(:, 1) - foveaPoint(1), centroids(:, 2) - foveaPoint(2));
touch = (dist - effRadius) <= c.DME_RADIUS_PX;
end

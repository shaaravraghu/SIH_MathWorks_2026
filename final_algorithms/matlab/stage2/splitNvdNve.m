function result = splitNvdNve(excessMask, opticDisc)
%SPLITNVDNVE NVD if a candidate's centroid is within 1 DD of the OD centre,
%   else NVE. IRMA vs NV cannot be separated on colour fundus alone (see
%   vessels.py module docstring) - every candidate here is under the single
%   combined abnormal-vessel class; this only splits by LOCATION, not
%   NV-vs-IRMA. Mirrors vessels.py split_nvd_nve.
%
%   result: scalar struct with fields nvd, nve (struct arrays with fields
%   centroid [x y] and area_px), nvd_count, nve_count.

vc = vesselConstants();
cc = bwconncomp(excessMask, 8);
stats = regionprops(cc, 'Centroid', 'Area');
ddPx = 2.0 * opticDisc.radius;

nvd = struct('centroid', {}, 'area_px', {});
nve = struct('centroid', {}, 'area_px', {});
for i = 1:numel(stats)
    cxy = stats(i).Centroid; % [x y], 1-based pixel coordinates from regionprops
    dist = hypot(cxy(1) - 1 - opticDisc.center_x, cxy(2) - 1 - opticDisc.center_y);
    entry = struct('centroid', [cxy(1) - 1, cxy(2) - 1], 'area_px', round(stats(i).Area));
    if dist <= vc.NVD_MAX_DISC_DIAMETERS * ddPx
        nvd(end + 1) = entry; %#ok<AGROW>
    else
        nve(end + 1) = entry; %#ok<AGROW>
    end
end

result = struct('nvd', {nvd}, 'nve', {nve}, 'nvd_count', numel(nvd), 'nve_count', numel(nve));
end

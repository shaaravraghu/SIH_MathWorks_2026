function result = buildVesselMap(imageRgb, fovMask)
%BUILDVESSELMAP #VESSELS top-level entry point: matched filtering (a) +
%   Frangi calibre map (b) + fine-scale-excess abnormal-vessel labelling
%   (c). Mirrors vessels.py build_vessel_map. fovMask may be [] to skip
%   masking.
%
%   result: scalar struct (VesselMapResult) with fields matched_filter_mask,
%   vesselness, width_px, calibre, vessel_class, excess_mask, nv_score.

green = double(imageRgb(:, :, 2));
green01 = min(max(green / 255.0, 0.0), 1.0);

matched = matchedFilterVesselMap(green, fovMask);
calibreResult = buildVesselCalibreMap(green, matched, []);
excess = fineScaleExcess(green01, fovMask);
vesselClass = classifyVesselPixels(calibreResult.calibre, excess.excess);

result = struct( ...
    'matched_filter_mask', matched, ...
    'vesselness', calibreResult.vesselness, ...
    'width_px', calibreResult.width_px, ...
    'calibre', calibreResult.calibre, ...
    'vessel_class', vesselClass, ...
    'excess_mask', excess.excess, ...
    'nv_score', excess.nv_score);
end

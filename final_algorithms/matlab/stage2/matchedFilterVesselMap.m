function vesselMap = matchedFilterVesselMap(green, fovMask)
%MATCHEDFILTERVESSELMAP #VESSELS (a): boolean vessel map at approx. main &
%   1st-branch width via a bank of oriented matched filters (Chaudhuri-
%   style). pixel true -> vessel. Mirrors vessels.py matched_filter_vessel_map.
%   fovMask may be [] to skip masking.

vc = vesselConstants();
response = matchedFilterResponse(green);
if ~isempty(fovMask)
    values = response(fovMask);
else
    values = response(:);
end
if ~isempty(values)
    % numpy's default percentile interpolation is linear; prctile's
    % "inclusive" method matches it (R2022a+).
    thresh = prctile(values, vc.THRESH_MATCHED_FILTER_PERCENTILE, "Method", "inclusive");
else
    thresh = 0.0;
end
vesselMap = response > thresh;
if ~isempty(fovMask)
    vesselMap = vesselMap & fovMask;
end
end

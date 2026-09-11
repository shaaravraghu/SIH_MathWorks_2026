function bands = bandCalibre(widthPx, vesselMask)
%BANDCALIBRE Buckets a per-pixel width map into the four calibre bands.
%   Mirrors vessels.py band_calibre. vesselMask may be [] to skip masking.
%   bands is int8, -1 = reject/not a vessel, else 0-3 (VESSEL_CALIBRE_*).

vc = vesselConstants();
bands = -ones(size(widthPx), 'int8');
bands(widthPx >= vc.MINOR_VESSEL_MIN_PX) = vc.CALIBRE_MINOR;
bands(widthPx >= vc.FIRST_BRANCH_MIN_PX) = vc.CALIBRE_FIRST_BRANCH;
bands(widthPx >= vc.MAJOR_VESSEL_MIN_PX) = vc.CALIBRE_MAJOR;
bands(widthPx >= vc.BEADING_MIN_PX) = vc.CALIBRE_BEADING;
if ~isempty(vesselMask)
    bands(~vesselMask) = -1;
end
end

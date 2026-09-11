function stats = calibrePct(calibre)
%CALIBREPCT Percentage of the measurement-mask FOV occupied by each Frangi
%   calibre band. Mirrors features.py _calibre_pct.

vc = vesselConstants();
m = stage2Masks();
mmArea = sum(m.MEASUREMENT_MASK(:));
withinMm = calibre(m.MEASUREMENT_MASK);

stats = struct();
stats.major_vessel_pct = 100.0 * double(sum(withinMm == vc.CALIBRE_MAJOR)) / max(double(mmArea), 1.0);
stats.branch1_vessel_pct = 100.0 * double(sum(withinMm == vc.CALIBRE_FIRST_BRANCH)) / max(double(mmArea), 1.0);
stats.minor_vessel_pct = 100.0 * double(sum(withinMm == vc.CALIBRE_MINOR)) / max(double(mmArea), 1.0);
stats.venous_beading_pct = 100.0 * double(sum(withinMm == vc.CALIBRE_BEADING)) / max(double(mmArea), 1.0);
end

function vesselClass = classifyVesselPixels(calibreBands, excessMask)
%CLASSIFYVESSELPIXELS (c) label: 0 = major/regular vessel (Frangi calibre,
%   not excess-flagged); 1 = abnormal vessel (neovascularisation/IRMA,
%   reported here as a single combined class - see vessels.py module
%   docstring). -1 = no vessel. Mirrors vessels.py classify_vessel_pixels.

vc = vesselConstants();
vesselPresent = calibreBands >= 0;
abnormal = vesselPresent & excessMask;
vesselClass = repmat(vc.CLASS_MAJOR, size(calibreBands));
vesselClass(abnormal) = vc.CLASS_NEOVASCULARISATION;
vesselClass(~vesselPresent) = int8(-1);
end

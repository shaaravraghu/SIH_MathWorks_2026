function result = buildVesselCalibreMap(green, vesselMask, sigmas)
%BUILDVESSELCALIBREMAP #VESSELS (b): multi-scale Frangi vesselness, calibre
%   width and band map. Mirrors vessels.py build_vessel_calibre_map.
%   vesselMask may be [] to skip masking; sigmas may be [] for the default
%   frangiSigmaScaleSet().
%
%   result: scalar struct with fields vesselness, width_px, calibre.

if nargin < 3
    sigmas = [];
end
[vesselness, sigmaAtPeak] = multiscaleFrangi(green, sigmas);
widthPx = calibreWidthPx(sigmaAtPeak);
bands = bandCalibre(widthPx, vesselMask);
result = struct('vesselness', vesselness, 'width_px', widthPx, 'calibre', bands);
end

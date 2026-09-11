function width = calibreWidthPx(sigmaAtPeak)
%CALIBREWIDTHPX Inverse of sigma ~ vessel_radius / sqrt(2):
%   width = 2*sqrt(2)*sigma. Mirrors vessels.py calibre_width_px.

width = 2.0 * sqrt(2.0) * sigmaAtPeak;
end

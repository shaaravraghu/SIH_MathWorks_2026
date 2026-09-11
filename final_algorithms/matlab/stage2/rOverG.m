function ratio = rOverG(pixels)
%ROVERG Mean red/green colour ratio of a set of RGB samples (N x 3).
%   Colour RATIO, never absolute intensity - see lesionFeatures module
%   docstring (camera-identity leakage). Mirrors lesion_features.py r_over_g.

m = meanRgb(pixels);
ratio = m(1) / (m(2) + 1e-6);
end


function m = meanRgb(pixels)
if isempty(pixels)
    m = [0 0 0];
else
    m = mean(double(pixels), 1);
end
end

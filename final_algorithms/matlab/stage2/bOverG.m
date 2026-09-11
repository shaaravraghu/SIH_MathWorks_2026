function ratio = bOverG(pixels)
%BOVERG Mean blue/green colour ratio of a set of RGB samples (N x 3).
%   Colour RATIO, never absolute intensity - see lesionFeatures module
%   docstring (camera-identity leakage). Mirrors lesion_features.py b_over_g.

m = meanRgb(pixels);
ratio = m(3) / (m(2) + 1e-6);
end


function m = meanRgb(pixels)
if isempty(pixels)
    m = [0 0 0];
else
    m = mean(double(pixels), 1);
end
end

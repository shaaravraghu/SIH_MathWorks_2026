function frac = saturationFraction(channel, mask)
%SATURATIONFRACTION Fraction of FOV pixels at intensity extremes (#4.2
%   CLAHE helper: "Saturation Count: Detects excessive
%   enhancement/clipping at intensity extremes", notes #4.2).

CLAHE_SATURATION_LEVEL_LOW = 5;
CLAHE_SATURATION_LEVEL_HIGH = 250;

vals = channel(mask);
if isempty(vals)
    frac = 0.0;
    return;
end

frac = mean((vals <= CLAHE_SATURATION_LEVEL_LOW) | (vals >= CLAHE_SATURATION_LEVEL_HIGH));
end

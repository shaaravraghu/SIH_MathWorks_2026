function slope = specSlope(patch)
%SPECSLOPE Slope of the radially-averaged power spectrum on a log-log
%   scale. SpecSlope can cleanly identify blood vessels, which is why it
%   is used alongside Variance of Laplacian (NORMED) in #3.1 (notes #3).
%   A steeper (more negative) slope indicates energy concentrated at low
%   spatial frequencies (blur); a shallower slope indicates rich
%   high-frequency content such as blood vessels.

patch = double(patch);
patch = patch - mean(patch(:));
[h, w] = size(patch);

% np.hanning(M) is hand-rolled rather than using MATLAB's hann() (Signal
% Processing Toolbox) so the window formula matches numpy exactly without
% adding a toolbox dependency.
window = hanningWindow(h) * hanningWindow(w)';
spectrum = fftshift(fft2(patch .* window));
power = abs(spectrum) .^ 2;

cy = floor(h / 2) + 1;
cx = floor(w / 2) + 1;
[xIdx, yIdx] = meshgrid(1:w, 1:h);
radius = floor(sqrt((yIdx - cy) .^ 2 + (xIdx - cx) .^ 2));

maxR = max(radius(:));
radialSum = accumarray(radius(:) + 1, power(:), [maxR + 1, 1]);
radialCount = accumarray(radius(:) + 1, 1, [maxR + 1, 1]);
radialProfile = radialSum ./ max(radialCount, 1);

% Skip the DC/very-low-frequency bin; fit log(power) vs log(radius).
validR = (1:maxR)';
profile = radialProfile(2:end);
keep = profile > 0;
if sum(keep) < 2
    slope = 0.0;
    return;
end

logR = log(validR(keep));
logP = log(profile(keep));
p = polyfit(logR, logP, 1);
slope = p(1);
end


function w = hanningWindow(M)
% numpy.hanning(M): w[n] = 0.5 - 0.5*cos(2*pi*n/(M-1)), n = 0..M-1.
if M == 1
    w = 1;
    return;
end
n = (0:M - 1)';
w = 0.5 - 0.5 * cos(2 * pi * n / (M - 1));
end

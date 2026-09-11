function v = normedVariance(lapVals, intensities)
%NORMEDVARIANCE Shared helper (Python _normed_variance), used by both
%   varianceOfLaplacianNormed (#3.1) and regionMin (#3.4), which live in
%   separate files under the one-public-function-per-file MATLAB rule --
%   so it gets its own small file here.
%   NORMED: variance scaled by (mean intensity)^2 to remove global
%   brightness/exposure dependence.

meanIntensity = mean(intensities) + 1e-6;
% MATLAB's var() defaults to the N-1 (sample) estimator; the second
% argument 1 selects the population estimator (divide by N) to match
% numpy's np.var default (ddof=0) used in the Python version.
v = var(lapVals, 1) / (meanIntensity ^ 2);
end

function scaler = zscoreFit(X)
%ZSCOREFIT §6.1 step 3: normalisation fitted on TRAINING rows ONLY.
%   Fitting on the full table would leak the held-out fold's distribution
%   into training, which is the same class of mistake §4.1 documents for the
%   lesion classifiers.

mu = mean(X, 1);
sigma = std(X, 0, 1);
% A constant column (e.g. dme_flag all-zero in a small fold) would divide by
% zero; leave it at zero rather than producing Inf/NaN.
sigma(sigma <= 1e-12) = 1.0;
scaler = struct('mean', mu, 'scale', sigma);
end

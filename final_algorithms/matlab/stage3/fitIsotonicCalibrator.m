function calibrator = fitIsotonicCalibrator(scores, labels)
%FITISOTONICCALIBRATOR §7.1: isotonic calibration -- more flexible than
%   Platt, but it can overfit 425 rows, so compare ECE before adopting it.
%
%   MATLAB has no isotonic regression built in, so this is the standard
%   pool-adjacent-violators algorithm (PAVA), which is what scikit-learn's
%   IsotonicRegression runs. Documented equivalent, not a library call.

s = double(scores(:)); l = double(labels(:) > 0);
[s, order] = sort(s);
l = l(order);

% PAVA: merge adjacent blocks until the fitted values are non-decreasing.
value = l; weight = ones(size(l));
k = 1;
while k < numel(value)
    if value(k) <= value(k + 1) + 1e-12
        k = k + 1;
        continue;
    end
    merged = (value(k) * weight(k) + value(k + 1) * weight(k + 1)) / (weight(k) + weight(k + 1));
    value(k) = merged; weight(k) = weight(k) + weight(k + 1);
    value(k + 1) = []; weight(k + 1) = []; s(k + 1) = [];
    while k > 1 && value(k - 1) > value(k) + 1e-12
        merged = (value(k - 1) * weight(k - 1) + value(k) * weight(k)) / (weight(k - 1) + weight(k));
        value(k - 1) = merged; weight(k - 1) = weight(k - 1) + weight(k);
        value(k) = []; weight(k) = []; s(k) = [];
        k = k - 1;
    end
end

calibrator = struct('kind', "isotonic", 'x', s(:), 'y', min(max(value(:), 0), 1));
end

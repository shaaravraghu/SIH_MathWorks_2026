function out = percentileLinear(x, p)
%PERCENTILELINEAR numpy.percentile's DEFAULT ("linear") interpolation.
%   Shared by Stage 2 and Stage 3 wherever a threshold has to match the
%   Python implementation's percentile exactly.
%
%   DO NOT REPLACE THIS WITH prctile. Two separate reasons:
%
%   1. prctile has no "inclusive" method. Its Method argument takes only
%      'exact' or 'approximate' (which selects the algorithm, not the
%      interpolation convention). prctile(x, p, "Method", "inclusive")
%      ERRORS -- verified on R2024a: "Method must be 'exact' or
%      'approximate'".
%   2. prctile's DEFAULT convention is not numpy's. prctile places the i-th
%      of n sorted values at percentile 100*(i-0.5)/n and clamps outside
%      that range; numpy places it at 100*(i-1)/(n-1). The two disagree
%      everywhere except the median, and most at the tails -- exactly where
%      these thresholds sit (p90, p92, p95, p96, p99).
%
%   numpy's rule, for q = p/100 on n sorted values:
%       virtual index  = (n - 1) * q          (0-based)
%       out = v(floor) + frac * (v(ceil) - v(floor))
%   which is precisely linear interpolation of the sorted values over an
%   evenly spaced 0..100 grid, i.e. the interp1 below.
%
%   x: any numeric/logical array (flattened, NaNs dropped, like numpy after
%      the callers' own masking). p: scalar or vector of percentiles in
%      [0, 100]. out has the shape of p.

v = double(x(:));
v = v(~isnan(v));

if isempty(v)
    out = nan(size(p));
    return;
end

v = sort(v);
n = numel(v);

if n == 1
    out = repmat(v, size(p));
    return;
end

grid = linspace(0, 100, n);
out = interp1(grid, v, double(p), 'linear');

% interp1 returns NaN just outside the grid for floating-point reasons at
% p == 0 or p == 100; clamp rather than propagate a NaN threshold.
out(double(p) <= 0) = v(1);
out(double(p) >= 100) = v(end);
out = reshape(out, size(p));
end

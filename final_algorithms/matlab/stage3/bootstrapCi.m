function ci = bootstrapCi(metricFn, arrays, nBoot, alpha, seed)
%BOOTSTRAPCI §7.1: bootstrap 95% confidence interval.
%   15 images per grade makes the TEST intervals wide -- report them, don't
%   hide them. That is the plan's instruction, not a stylistic preference.

if nargin < 3 || isempty(nBoot),  nBoot = 2000; end
if nargin < 4 || isempty(alpha),  alpha = 0.05; end
if nargin < 5 || isempty(seed),   seed = 0; end

n = numel(arrays{1});
ci = struct('point', NaN, 'lo', NaN, 'hi', NaN, 'n_boot', 0);
if n == 0, return; end

ci.point = metricFn(arrays{:});

stream = RandStream('mt19937ar', 'Seed', seed);
samples = nan(nBoot, 1);
for b = 1:nBoot
    idx = randi(stream, n, n, 1);
    subset = cell(size(arrays));
    for a = 1:numel(arrays)
        column = arrays{a};
        subset{a} = column(idx);
    end
    samples(b) = metricFn(subset{:});
end
samples = samples(~isnan(samples));
if isempty(samples), return; end

% "inclusive" matches numpy's default linear interpolation, as everywhere else
% in this project (see the stage2 percentile note).
ci.lo = prctile(samples, 100 * alpha / 2, "Method", "inclusive");
ci.hi = prctile(samples, 100 * (1 - alpha / 2), "Method", "inclusive");
ci.n_boot = numel(samples);
end

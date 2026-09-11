function result = laplacianAndSpecSlopeGate(gray, rngStream)
%LAPLACIANANDSPECSLOPEGATE #3.1: Variance of Laplacian (NORMED) + SpecSlope,
%   second stage of the #3 cascade. Status is driven by the Laplacian
%   gate; SpecSlope is recorded alongside (blood-vessel signature, notes
%   #3) but does not itself gate.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

lap = varianceOfLaplacianNormed(gray, rngStream);
spec = specSlopeGate(gray, rngStream);
result = struct('laplacian', lap, 'spec_slope', spec, 'status', lap.status);
end

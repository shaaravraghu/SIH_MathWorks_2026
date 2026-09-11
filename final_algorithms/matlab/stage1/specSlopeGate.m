function result = specSlopeGate(gray, rngStream)
%SPECSLOPEGATE #3.1 companion metric: mean SpecSlope over sampled squares.

if nargin < 2 || isempty(rngStream)
    rngStream = RandStream('mt19937ar', 'Seed', sum(100 * clock));
end

boxes = sampleSquaresInDisk(size(gray), [], [], rngStream);
n = size(boxes, 1);
slopes = zeros(n, 1);
for i = 1:n
    r0 = boxes(i, 1); r1 = boxes(i, 2); c0 = boxes(i, 3); c1 = boxes(i, 4);
    slopes(i) = specSlope(gray(r0:r1, c0:c1));
end

if n > 0
    score = mean(slopes);
else
    score = 0.0;
end

result = struct('score', score, 'n_patches', n);
end

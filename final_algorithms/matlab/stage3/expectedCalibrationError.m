function [ece, diagram] = expectedCalibrationError(labels, probabilities, nBins)
%EXPECTEDCALIBRATIONERROR §7.1's calibration check, reported BEFORE and AFTER
%   calibration alongside the reliability diagram.

if nargin < 3 || isempty(nBins), nBins = 10; end

labels = double(labels(:) > 0);
probabilities = double(probabilities(:));
diagram = struct('lo', {}, 'hi', {}, 'n', {}, 'confidence', {}, 'accuracy', {});
if isempty(labels), ece = NaN; return; end

edges = linspace(0, 1, nBins + 1);
total = numel(labels);
ece = 0.0;
for b = 1:nBins
    lo = edges(b); hi = edges(b + 1);
    if b < nBins
        inBin = probabilities >= lo & probabilities < hi;
    else
        inBin = probabilities >= lo & probabilities <= hi;   % last bin closed
    end
    n = sum(inBin);
    if n == 0
        diagram(end+1) = struct('lo', lo, 'hi', hi, 'n', 0, ...
            'confidence', NaN, 'accuracy', NaN); %#ok<AGROW>
        continue;
    end
    confidence = mean(probabilities(inBin));
    accuracy = mean(labels(inBin));
    ece = ece + (n / total) * abs(accuracy - confidence);
    diagram(end+1) = struct('lo', lo, 'hi', hi, 'n', n, ...
        'confidence', confidence, 'accuracy', accuracy); %#ok<AGROW>
end
end

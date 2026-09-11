function [vesselness, sigmaAtPeak] = multiscaleFrangi(gray, sigmas)
%MULTISCALEFRANGI Max Frangi response, and the sigma at which it peaks, over
%   a scale set. Mirrors vessels.py multiscale_frangi.

if nargin < 2 || isempty(sigmas)
    sigmas = frangiSigmaScaleSet();
end

responses = zeros(size(gray, 1), size(gray, 2), numel(sigmas));
for i = 1:numel(sigmas)
    responses(:, :, i) = frangiResponse(gray, sigmas(i));
end
[vesselness, bestIdx] = max(responses, [], 3);
sigmaAtPeak = reshape(sigmas(bestIdx), size(gray));
end

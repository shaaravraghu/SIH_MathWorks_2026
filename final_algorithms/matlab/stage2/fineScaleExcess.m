function result = fineScaleExcess(green01, fovMask)
%FINESCALEEXCESS #VESSELS (c) fine-scale excess: FINE line-detector response
%   minus a dilated COARSE threshold mask, the basis for major/NV/IRMA
%   vessel-pixel labelling (density alone is wrong-signed - see vessels.py
%   module docstring). Mirrors vessels.py fine_scale_excess. fovMask may be
%   [] to skip masking.
%
%   result: scalar struct with fields fine, coarse, excess, nv_score.

vc = vesselConstants();
fine = lineDetector(green01, vc.FINE_LINE_LENGTH_PX, vc.FINE_LINE_WIDTH_PX);
coarse = lineDetector(green01, vc.COARSE_LINE_LENGTH_PX, vc.COARSE_LINE_WIDTH_PX);

if ~isempty(fovMask)
    valsFine = fine(fovMask);
    valsCoarse = coarse(fovMask);
else
    valsFine = fine(:);
    valsCoarse = coarse(:);
end
% numpy's default percentile interpolation is linear; prctile's "inclusive"
% method matches it (R2022a+).
if ~isempty(valsFine)
    pFine = prctile(valsFine, vc.EXCESS_PERCENTILE, "Method", "inclusive");
else
    pFine = 0.0;
end
if ~isempty(valsCoarse)
    pCoarse = prctile(valsCoarse, vc.EXCESS_PERCENTILE, "Method", "inclusive");
else
    pCoarse = 0.0;
end

kernel = ones(vc.COARSE_DILATE_KERNEL_PX, vc.COARSE_DILATE_KERNEL_PX);
coarseDilated = imdilate(coarse > pCoarse, kernel);
excess = (fine > pFine) & ~coarseDilated;
if ~isempty(fovMask)
    excess = excess & fovMask;
end

if ~isempty(fovMask)
    fovArea = sum(fovMask(:));
else
    fovArea = numel(green01);
end
nvScore = 100.0 * sum(excess(:)) / max(double(fovArea), 1.0);

result = struct('fine', fine, 'coarse', coarse, 'excess', excess, 'nv_score', nvScore);
end

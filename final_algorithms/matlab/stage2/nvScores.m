function [stats, excess] = nvScores(green01, opticDisc)
%NVSCORES Neovascularisation/IRMA excess scores: overall, max-in-a-1DD-
%   window, NVD (within 1 DD of the OD) and NVE (nv_score - nvd_score).
%   Mirrors features.py _nv_scores.

c = stage2Constants();
m = stage2Masks();
fineResult = fineScaleExcess(green01, m.MEASUREMENT_MASK);
excess = fineResult.excess;
mm = m.MEASUREMENT_MASK;
mmArea = sum(mm(:));

nvScore = fineResult.nv_score;
if any(mm(:))
    % scipy.ndimage.uniform_filter -> imboxfilt('Padding','symmetric') per
    % the library-mapping note, but imboxfilt requires an ODD filter size
    % and DD_PX (124) is even, so a manually normalised imfilter box
    % kernel is used instead ('symmetric' padding matches the mapping
    % note's semantics).
    winSize = round(c.DD_PX);
    boxKernel = ones(winSize, winSize) / (winSize * winSize);
    filtered = imfilter(double(excess), boxKernel, 'symmetric', 'same');
    nvScoreMax = max(filtered(mm));
else
    nvScoreMax = 0.0;
end

distFromOd = hypot(m.PIXEL_Y - opticDisc.center_y, m.PIXEL_X - opticDisc.center_x);
within1dd = distFromOd <= c.DD_PX;
nvdScore = 100.0 * double(sum(excess(:) & within1dd(:))) / max(double(mmArea), 1.0);
nveScore = nvScore - nvdScore;

stats = struct('nv_score', nvScore, 'nv_score_max', nvScoreMax, 'nvd_score', nvdScore, 'nve_score', nveScore);
end

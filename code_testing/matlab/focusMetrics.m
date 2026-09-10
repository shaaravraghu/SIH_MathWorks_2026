function f = focusMetrics(I, fov, mode)
%FOCUSMETRICS  Stage [B] of Module 1 -- focus / sharpness features.
%
%   f = focusMetrics(I, fov)            full mask (reference)
%   f = focusMetrics(I, fov, 'ring')    8 x 2.5% patches @0.80R -- 4.9x faster
%
%   Measured on 40 APTOS images x 4 blur levels: 'ring' costs 5.4 ms vs
%   26.4 ms for 'full', with Spearman rho = 0.985 against the full-mask
%   value and 19% median relative error.  The 8 patches also serve directly
%   as the regional breakdown for regionMin / regionCV.
%
%   NEVER downsample the image to speed this up.  Downsampling is a low-pass
%   filter and blur is a low-pass filter, so it destroys the signal: at 4x
%   reduction the dynamic range across sigma=0..4 collapses from 907x to 18x
%   and a heavily blurred image reads 208x too sharp.  Spatial subsetting
%   (patches) is safe; resolution reduction is not.  See retinaSampleMask
%   and the Module1_Performance doc.
%
%   Returns a struct of sharpness features computed on the GREEN channel.
%
%   Run normalizeFundus FIRST.  Every metric here is scale-dependent: a
%   "sharp" gradient at R=1400 px is a different number from the same eye at
%   R=436 px.  Comparing across images is only meaningful once the retinal
%   radius is fixed.
%
%   No single metric is best.  Measured on real data:
%     varLapNorm    contrast-invariant, 22,500x range, but 4.3x inflated by noise
%     tenengradVar  noise-immune (0.91x), 200x range, but scales with contrast^2
%     specSlope     contrast-invariant, different failure mode again
%     noiseSigma    lets the classifier tell "sharp" from "noisy"
%     regionMin     4,100x more sensitive to PARTIAL blur than the global mean
%   Hand all of them to the classifier and let it disentangle them.

if size(I,3) == 3
    Ig = im2double(I(:,:,2));           % green -- max lesion contrast, and the
else                                     % densest Bayer channel (sharpest)
    Ig = im2double(I);
end

if nargin < 3 || isempty(mode), mode = 'full'; end

% NEVER the raw mask: the FOV rim is a ~200-level cliff and dominates every
% gradient-based measure.  retinaSampleMask always builds from maskMeasure.
[M, patches] = retinaSampleMask(fov, mode);

% ---- second-derivative family ----------------------------------------
L = imfilter(Ig, fspecial('laplacian', 0), 'replicate');

f.varLap = var(L(M));

% Contrast-normalised.  var(L) and var(I) both scale as c^2, so the ratio is
% invariant.  This is what stops a SHARP BUT UNDEREXPOSED image being called
% blurry -- at 50% contrast, raw varLap drops 4x for no optical reason.
f.varLapNorm = var(L(M)) / max(var(Ig(M)), eps);

% Modified Laplacian (Nayar & Nakagawa).  The plain Laplacian lets Ixx and
% Iyy cancel at a saddle point, so genuinely sharp structure can read zero.
% Taking |.| before summing fixes that.
ML = abs(2*Ig - circshift(Ig,1,2) - circshift(Ig,-1,2)) + ...
     abs(2*Ig - circshift(Ig,1,1) - circshift(Ig,-1,1));
f.sml = mean(ML(M));

% ---- first-derivative family (less noise-amplifying) ------------------
Gmag = imgradient(Ig, 'sobel');

f.tenengrad    = mean(Gmag(M).^2);
f.tenengradVar = var(Gmag(M));           % the noise-robust one

% Brenner (1971).  Crude, directional, but ~5 lines and very fast -- a good
% pre-check on the edge device.
D = (circshift(Ig,-2,2) - Ig).^2;
f.brenner = mean(D(M));

% ---- frequency domain -------------------------------------------------
f.specSlope = spectralSlope(Ig, fov);

% ---- noise, measured separately ---------------------------------------
% Immerkaer's estimator.  Rather than trying to make one metric immune to
% noise (which costs dynamic range 1:1 -- see the docs), measure the noise
% and let the classifier correct for it.
K = [1 -2 1; -2 4 -2; 1 -2 1];
Rn = imfilter(Ig, K, 'replicate');
f.noiseSigma = sqrt(pi/2) * mean(abs(Rn(M))) / 6;

% ---- spatial breakdown ------------------------------------------------
% Partial blur (camera tilt, eye movement) is common and the global mean
% hides it completely: on a half-blurred image the global varLap moved 1.5x
% while the worst region moved 4,100x.
% In 'ring' mode the 8 sampling patches ARE the regions, so the breakdown is
% free.  In 'full' mode fall back to centre + 4 quadrants.
if strcmpi(mode, 'ring')
    reg = patches;
else
    reg = splitRegions(M, fov);
end
vals = zeros(1, numel(reg));
for k = 1:numel(reg)
    if nnz(reg{k}) > 100
        vals(k) = var(L(reg{k})) / max(var(Ig(reg{k})), eps);
    else
        vals(k) = NaN;
    end
end

f.regionVals = vals;
f.regionMin  = min(vals, [], 'omitnan');                        % the key one
f.regionCV   = std(vals, 'omitnan') / mean(vals, 'omitnan');    % tilt detector

end

% =======================================================================
function a = spectralSlope(Ig, fov)
%SPECTRALSLOPE  Power-law exponent of the radial power spectrum.
%
%   Natural images follow P(f) ~ f^-alpha with alpha ~ 2.  Blur steepens the
%   falloff, so alpha rises.  Because it is a SLOPE it is invariant to
%   contrast and brightness -- unlike every energy-based measure above.

half = round(0.45 * fov.radius);
cx   = round(fov.centre(1));
cy   = round(fov.centre(2));

r0 = max(1, cy-half);  r1 = min(size(Ig,1), cy+half);
c0 = max(1, cx-half);  c1 = min(size(Ig,2), cx+half);
C  = Ig(r0:r1, c0:c1);

% A circular mask boundary is a hard step edge with broadband spectral
% content that swamps everything.  Work on an interior rectangle and window
% it so it tapers to zero.
C = C - mean(C(:));
C = C .* (hann(size(C,1)) * hann(size(C,2))');

P = abs(fftshift(fft2(C))).^2;

[h, w]   = size(P);
[xx, yy] = meshgrid(1:w, 1:h);
rad      = round(hypot(yy - h/2, xx - w/2)) + 1;

prof = accumarray(rad(:), P(:), [], @mean);

lo = 6;                                   % skip DC and the lowest bins
hi = min(120, numel(prof));
if hi <= lo + 5
    a = NaN;  return
end

fr = (lo:hi)';
p  = polyfit(log(fr), log(prof(lo:hi) + eps), 1);
a  = -p(1);                               % larger alpha = blurrier

end

% =======================================================================
function reg = splitRegions(M, fov)
%SPLITREGIONS  Centre disc + 4 quadrants, oriented on the frame axes.
%
%   For the clinical 4-2-1 rule these quadrants must be oriented on the
%   optic-disc-to-fovea axis instead -- but that needs Module 2, and [B]
%   must run before any anatomy is known.  Frame axes are enough to detect
%   tilt and one-sided defocus.

[h, w]   = size(M);
[xx, yy] = meshgrid(1:w, 1:h);

rr  = hypot(yy - fov.centre(2), xx - fov.centre(1));
ang = mod(atan2d(-(yy - fov.centre(2)), xx - fov.centre(1)), 360);

reg    = cell(1,5);
reg{1} = M & rr < 0.4*fov.radius;                  % centre
for k = 1:4
    reg{k+1} = M & rr >= 0.4*fov.radius & ...
               ang >= (k-1)*90 & ang < k*90;
end

end

function c = illuminationMetrics(I, fov)
%ILLUMINATIONMETRICS  Stage [C] -- illumination, exposure and contrast.
%
%   c = ILLUMINATIONMETRICS(I, fov) measures whether there was enough light,
%   delivered evenly, to record the retina -- and whether what was lost is
%   recoverable. I is RGB in [0,1] (im2double). fov comes from detectFOV.
%
%   Every metric is computed inside fov.maskMeasure. Without the mask the
%   black surround destroys bgMean and bgCV outright.
%
%   See notes/docs/Module1_C_Illumination.md for the measured justification
%   of every constant below.

M = fov.maskMeasure;
if ~any(M(:))
    error('illuminationMetrics:emptyMask', 'fov.maskMeasure is empty');
end

R = I(:,:,1);  G = I(:,:,2);  B = I(:,:,3);

% Match Module1_CSV_Schema.md exactly -- if these drift, the CSV columns
% stop meaning the same thing across runs.
SAT_HI = 250/255;
SAT_LO =   5/255;

% ---------------------------------------------------------------- [1]
% Background illumination field: downsample -> median -> upsample.
%
% Median, not Gaussian: the optic disc is a large bright blob and a Gaussian
% estimate puts a 4.3% bump on it (measured), which flat-fielding would then
% divide out of real anatomy. Median rejects it while the disc occupies less
% than half the window.
%
% Downsample first because the field is smooth by definition, so 1/16 scale
% loses none of it -- and a 176 px median at full resolution is ~250x slower.
F      = 16;
small  = imresize(G, 1/F, 'bilinear');
mSmall = imresize(M, 1/F, 'nearest');
if ~any(mSmall(:))
    mSmall = imresize(M, 1/F, 'bilinear') > 0.5;
end

% Hold the outside at the interior median. Leaving the black surround at ~0
% drags the field down near the rim and manufactures a falloff that is not
% optical.
filled = small;
filled(~mSmall) = median(small(mSmall));

% Window must comfortably exceed the optic disc (~1/7 of image width).
win = max(5, 2*floor(0.5 * 176/F) + 1);
L   = imresize(medfilt2(filled, [win win], 'symmetric'), size(G), 'bicubic');

Lm         = L(M);
c.bgMean   = mean(Lm);
c.bgCV     = std(Lm) / max(mean(Lm), eps);
pc         = prctile(Lm, [5 95]);
c.bgSpread = pc(2) - pc(1);

% ---------------------------------------------------------------- [2]
% Plane and radial fits. Symmetric falloff is normal vignetting; asymmetric
% tilt is a fault. Separating them needs two fits, not one.
[yy, xx] = find(M);
X = (xx - fov.centre(1)) / fov.radius;   % scale-free: means the same at
Y = (yy - fov.centre(2)) / fov.radius;   % R=400 and R=1800

sol = [X, Y, ones(numel(X),1)] \ Lm;     % one backslash, same as Kasa in [A]
c.bgTiltMag = hypot(sol(1), sol(2));     % intensity change per retinal radius
c.bgTiltDir = atan2d(sol(2), sol(1));    % 0 = +x right, 90 = +y down

% NOTE: bgTiltDir is systematically pulled toward the optic disc, which is a
% genuinely bright off-centre structure. The bias is consistent (the disc is
% always nasal), so a classifier can learn around it -- but never read a single
% image's tilt as misalignment without cross-checking fov.offset.

rad = hypot(X, Y);
sr  = [rad, ones(numel(rad),1)] \ Lm;
c.bgRadial = sr(1);                      % negative = normal centre-bright

% ---------------------------------------------------------------- [3]
% Saturation. The only [C] measurement of *irreversible* damage: a clipped
% pixel has lost its information permanently and no enhancement recovers it.
%
% Per-channel is not optional. sat_R up to 0.70 is normal (the fundus is
% red-dominant and red is only used for FOV detection). sat_G high is fatal --
% green carries the lesion contrast Module 2 depends on.
c.sat_R = mean(R(M) >= SAT_HI);
c.sat_G = mean(G(M) >= SAT_HI);
c.sat_B = mean(B(M) >= SAT_HI);

c.satLo_R   = mean(R(M) <= SAT_LO);
c.satLo_B   = mean(B(M) <= SAT_LO);
c.dark_frac = mean(G(M) <= SAT_LO);

% ---------------------------------------------------------------- [4]
% Local contrast. [B] measures how sharply edges transition; this measures how
% large the differences are. varLapNorm is contrast-invariant by construction,
% so it structurally cannot see haze -- this is what catches it.
%
% Window scales with radius: 15 px was calibrated at R=436.
w = 2*floor(0.5 * max(5, round(15 * fov.radius / 436))) + 1;
S = stdfilt(G, true(w));
Sm = S(M);
c.localContrast    = mean(Sm);
c.localContrastP10 = prctile(Sm, 10);

% WARNING: localContrast is dominated by anatomy, not quality. Measured on the
% reference image the optic-disc half reads ~50% higher than the macula half,
% and both are perfectly exposed. Calibrate against real distributions before
% thresholding -- this has an anatomical floor, like regionCV in [B].

% ---------------------------------------------------------------- [5]
% Colour. Haze washes the image toward grey-yellow, so colorSat drops while
% brightness stays normal or rises -- that pair is what separates cataract
% (not fixable by retaking) from underexposure (fixable).
mx  = max(I, [], 3);
mn  = min(I, [], 3);
sat = zeros(size(mx));
nz  = mx > 0;
sat(nz) = (mx(nz) - mn(nz)) ./ mx(nz);

c.colorSat = mean(sat(M));
c.mean_R   = mean(R(M));   c.std_R = std(R(M));
c.mean_G   = mean(G(M));   c.std_G = std(G(M));
c.mean_B   = mean(B(M));   c.std_B = std(B(M));
c.ratio_RG = c.mean_R / max(c.mean_G, eps);
c.ratio_BG = c.mean_B / max(c.mean_G, eps);

% ---------------------------------------------------------------- gate
% sat_G is the only [C] feature measuring irreversible damage, which makes it
% the only one with a principled claim to being a hard reject.
%
% Do NOT add gates on localContrast, colorSat or dark_frac without first
% measuring Spearman rho against diagnosis. All three are plausibly
% disease-correlated, and the existing [A] gate already rejects grade-4 images
% at 3.8x the grade-0 rate. See Module1_C_Illumination.md#thresholds.
c.gate_reject = c.sat_G > 0.05;
c.gate_reason = "";
if c.gate_reject
    c.gate_reason = "sat_G";
end
end

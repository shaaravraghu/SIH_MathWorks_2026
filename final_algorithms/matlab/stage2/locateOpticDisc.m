function result = locateOpticDisc(imageRgb, vesselMask, fovMask)
%LOCATEOPTICDISC #OPTIC DISC: brightness-based primary localization,
%   confirmed by centre-surround contrast and a percentage-of-FOV-radius
%   plausibility check (see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN,
%   "OPTIC DISC" section). Mirrors optic_disc.py locate_optic_disc.
%
%   Vessel-detected pixels are masked out of the brightness search before
%   picking a candidate, per the notes' explicit instruction. A later
%   companion review (Stage_2_CNN_Proposed_Changes.md, item M3) argues
%   vessels actually CONVERGE at the disc and excluding them is wrong - that
%   proposal is deliberately NOT applied here (task spec is Stage_2_CNN as
%   written). Flagged for review, not silently resolved either way.
%
%   vesselMask/fovMask may be [] to skip masking. Output center_x/center_y
%   are 0-based pixel coordinates (matching the Python working-resolution
%   grid), even though the search itself runs over MATLAB's 1-based array
%   indices internally.
%
%   result: scalar struct (OpticDiscResult) with fields center_x, center_y,
%   radius, centre_surround_contrast, confirmed.

% --- percentage-of-FOV-radius plausibility band ------------------------------
% Anatomically the OD diameter is roughly 1/5-1/8 of the horizontal FOV, but
% the notes do not pin an exact fraction -> placeholders, calibrate before
% use. The search band is kept WIDER than the plausibility band so the
% confirmation step can actually fail.
OD_SEARCH_FRACTION_LOW = 0.03;
OD_SEARCH_FRACTION_HIGH = 0.15;
OD_SEARCH_RADIUS_STEPS = 5;   % placeholder: number of candidate radii tried

OD_RADIUS_FOV_FRACTION_LOW = 0.05;
OD_RADIUS_FOV_FRACTION_HIGH = 0.12;

% --- centre-surround confirmation --------------------------------------------
OD_ANNULUS_OUTER_FACTOR = 2.0;   % surround annulus outer radius = candidate_radius * this
THRESH_OD_CENTRE_SURROUND_MIN_CONTRAST = 5.0; % placeholder: not pinned in notes

[h, w, ~] = size(imageRgb);
if ~isempty(fovMask) && any(fovMask(:))
    [ys, xs] = find(fovMask);
    fovRadius = (double(max(xs) - min(xs)) + double(max(ys) - min(ys))) / 4.0;
else
    fovRadius = min(h, w) / 2.0;
end

brightness = toGray(imageRgb); % reuse stage1's toGray - identical Rec.601 luma formula

% Each candidate radius proposes its own best centre, and the radii compete
% on centre-surround contrast. Comparing the raw disc-mean across radii does
% not work: a smaller averaging window always reaches a higher maximum, so
% the smallest radius won on all 464 images of the Module 3 sample --
% od_radius_pct came out a constant 2.85 and, sitting below the 5%
% plausibility floor, `confirmed` was never true. Contrast is the quantity
% the notes already use to confirm the disc, and it peaks at the radius that
% actually matches it.
% Each candidate radius proposes its own best centre, and the radii compete
% on centre-surround contrast, preferring those inside the anatomical
% plausibility band. Raw disc-mean cannot rank radii -- a smaller averaging
% window always reaches a higher maximum, so the smallest radius won on all
% 464 images of the Module 3 sample (od_radius_pct a constant 2.85, below
% the 5% floor, so `confirmed` was never true). Contrast alone reverses the
% bias, since a wider annulus reaches further into dark retina and keeps
% growing: the largest radius then won and sat above the 12% ceiling.
% Restricting the choice to the band leaves the contrast test doing the
% confirming, which is what the notes intend.
imgD = double(imageRgb);
best = struct('contrast', -inf, 'y0', 0, 'x0', 0, 'radius', 0);
bestInBand = best;
fractions = linspace(OD_SEARCH_FRACTION_LOW, OD_SEARCH_FRACTION_HIGH, OD_SEARCH_RADIUS_STEPS);
for frac = fractions
    radius = max(3.0, frac * fovRadius);
    discMean = discMeanMap(brightness, vesselMask, radius);
    if ~isempty(fovMask)
        discMean(~fovMask) = -inf;
    end
    [~, linIdx] = max(discMean(:));
    [row, col] = ind2sub(size(discMean), linIdx);
    candidateContrast = centreSurroundContrast(imgD, [h, w], col - 1, row - 1, radius, OD_ANNULUS_OUTER_FACTOR);
    candidate = struct('contrast', candidateContrast, 'y0', row - 1, 'x0', col - 1, 'radius', radius);
    if candidateContrast > best.contrast
        best = candidate;
    end
    inBand = fovRadius > 0 && radius / fovRadius >= OD_RADIUS_FOV_FRACTION_LOW && ...
             radius / fovRadius <= OD_RADIUS_FOV_FRACTION_HIGH;
    if inBand && candidateContrast > bestInBand.contrast
        bestInBand = candidate;
    end
end
if isfinite(bestInBand.contrast)
    best = bestInBand;
end

cy = best.y0; cx = best.x0; radius = best.radius; % 0-based centre
contrast = best.contrast;

if fovRadius > 0
    radiusFraction = radius / fovRadius;
else
    radiusFraction = 0.0;
end
plausible = radiusFraction >= OD_RADIUS_FOV_FRACTION_LOW && radiusFraction <= OD_RADIUS_FOV_FRACTION_HIGH;
confirmed = plausible && contrast >= THRESH_OD_CENTRE_SURROUND_MIN_CONTRAST;

result = struct('center_x', cx, 'center_y', cy, 'radius', radius, ...
    'centre_surround_contrast', contrast, 'confirmed', confirmed);
end


function contrast = centreSurroundContrast(imgD, sz, cx, cy, radius, outerFactor)
% [mean_col(OD) - mean_col(surr)] summarised as a single scalar contrast
% (the notes give it per-channel; a vector magnitude is used here as the
% scalar confirmation score - documented judgment call).
innerMask = circleMask(sz, cx, cy, max(round(radius), 1));
outerR = max(round(radius * outerFactor), 1);
outerMask = circleMask(sz, cx, cy, outerR) & ~innerMask;

if any(innerMask(:))
    meanInner = [mean(subChannel(imgD, innerMask, 1)), mean(subChannel(imgD, innerMask, 2)), mean(subChannel(imgD, innerMask, 3))];
else
    meanInner = [0 0 0];
end
if any(outerMask(:))
    meanOuter = [mean(subChannel(imgD, outerMask, 1)), mean(subChannel(imgD, outerMask, 2)), mean(subChannel(imgD, outerMask, 3))];
else
    meanOuter = [0 0 0];
end
contrast = norm(meanInner - meanOuter);
end


function vals = subChannel(imgD, mask, ch)
layer = imgD(:, :, ch);
vals = layer(mask);
end


function meanMap = discMeanMap(brightness, vesselMask, radius)
% Private helper (Python _disc_mean_map): mean brightness within a
% circular window of the given radius, at every pixel, with
% vessel-detected pixels excluded (normalised correlation:
% sum(brightness*valid) / sum(valid)). cv2's borderType=BORDER_REPLICATE is
% matched exactly by imfilter's 'replicate' option here.
ksize = round(radius) * 2 + 1;
se = ellipseStrel(ksize);
kernel = double(getnhood(se));
if ~isempty(vesselMask)
    valid = double(~vesselMask);
else
    valid = ones(size(brightness));
end
weighted = brightness .* valid;
sumWeighted = imfilter(weighted, kernel, 'replicate', 'same');
sumValid = imfilter(valid, kernel, 'replicate', 'same');
meanMap = sumWeighted ./ max(sumValid, 1e-6);
end

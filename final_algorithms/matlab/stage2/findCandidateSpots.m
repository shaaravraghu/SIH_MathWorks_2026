function candidate = findCandidateSpots(imageRgb, mask, lesionClass)
%FINDCANDIDATESPOTS High-recall, low-precision spot mask from local colour-
%   ratio deviation (step 3 input for Haemorrhage/Hard-Exudate/Nerve-Fibre-
%   Ischemia, per the notes' "Pre-Feature Engineering" section). Deviation
%   thresholds are calibration placeholders (see constants below). Mirrors
%   lesion_features.py find_candidate_spots. mask may be [] to skip masking.

SPOT_LOCAL_WINDOW_PX = 9;  % placeholder: smoothing window for local colour-ratio maps, not pinned in notes
LOCAL_CONTRAST_ANNULUS_OUTER_PX = 24; % pinned (shared with lesionLocalContrast)
THRESH_SPOT_HAEM_B_OVER_G_DEVIATION = 0.05;
THRESH_SPOT_HE_SATURATION = 0.35;
THRESH_SPOT_NFI_B_OVER_G_DEVIATION = 0.05;

[bGMap, ~, satMap] = localRatioMaps(imageRgb, SPOT_LOCAL_WINDOW_PX);
bgWindow = max(LOCAL_CONTRAST_ANNULUS_OUTER_PX, SPOT_LOCAL_WINDOW_PX * 3);
% cv2.boxFilter is a normalized box filter, default border
% BORDER_REFLECT_101; imboxfilt with 'Padding','symmetric' approximates it.
localBgBG = imboxfilt(bGMap, [bgWindow, bgWindow], 'Padding', 'symmetric');

switch lesionClass
    case 'haemorrhage'
        candidate = (localBgBG - bGMap) > THRESH_SPOT_HAEM_B_OVER_G_DEVIATION;
    case 'hard_exudate'
        candidate = satMap > THRESH_SPOT_HE_SATURATION;
    case 'nerve_fibre_ischemia'
        candidate = (bGMap - localBgBG) > THRESH_SPOT_NFI_B_OVER_G_DEVIATION;
    otherwise
        candidate = false(size(bGMap));
end

if ~isempty(mask)
    candidate = candidate & mask;
end
end


function [bGMap, rGMap, satMap] = localRatioMaps(imageRgb, windowPx)
% Private helper (Python _local_ratio_maps).
img = double(imageRgb);
r = img(:, :, 1); g = img(:, :, 2); b = img(:, :, 3);
rLoc = imboxfilt(r, [windowPx, windowPx], 'Padding', 'symmetric');
gLoc = imboxfilt(g, [windowPx, windowPx], 'Padding', 'symmetric');
bLoc = imboxfilt(b, [windowPx, windowPx], 'Padding', 'symmetric');
bGMap = bLoc ./ (gLoc + 1e-6);
rGMap = rLoc ./ (gLoc + 1e-6);
hsvImg = rgb2hsv(double(imageRgb) / 255.0); % already [0,1], unlike cv2's [0,255]
satMap = imboxfilt(hsvImg(:, :, 2), [windowPx, windowPx], 'Padding', 'symmetric');
end

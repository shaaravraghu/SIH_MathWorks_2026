function candidate = thresholdCandidates(imageRgb, correctedGreen, workingMask, lesionClass)
%THRESHOLDCANDIDATES Step 3 of the five-step lesion pipeline: high-recall /
%   low-precision candidate mask (100+ per image is expected and fine -
%   steps 4-5 do the precision work). Mirrors lesion_pipeline.py
%   threshold_candidates. workingMask may be [] to skip masking.
%
%   Scale-matched structuring elements: one SE cannot serve both an 8px
%   microaneurysm and a 30px haemorrhage, because closing only fills what
%   the SE BRIDGES. hard_exudate/nerve_fibre_ischemia SE lengths are
%   placeholders kept only as a secondary/optional morphological pass -
%   they rely mainly on the colour-ratio spot finder (findCandidateSpots).

seLenMap = containers.Map( ...
    {'microaneurysm', 'haemorrhage', 'hard_exudate', 'nerve_fibre_ischemia'}, ...
    {15, 41, 21, 25}); % pinned: L=15 (MA), L=41 (haem); hard_exudate/nfi are placeholders

TOPHAT_LESION_CLASSES = {'microaneurysm', 'haemorrhage'};
RATIO_SPOT_LESION_CLASSES = {'haemorrhage', 'hard_exudate', 'nerve_fibre_ischemia'};

candidate = false(size(correctedGreen));
if ismember(lesionClass, TOPHAT_LESION_CLASSES)
    candidate = candidate | tophatCandidates(correctedGreen, workingMask, seLenMap(lesionClass));
end
if ismember(lesionClass, RATIO_SPOT_LESION_CLASSES)
    candidate = candidate | findCandidateSpots(imageRgb, workingMask, lesionClass);
end
end


function candidate = tophatCandidates(correctedGreen, workingMask, seLengthPx)
% Private helper (Python _tophat_candidates). Microaneurysms/haemorrhages
% are DARK spots -> black-tophat (closing minus original).
THRESH_CANDIDATE_TOPHAT_PERCENTILE = 95.0; % placeholder: not pinned in notes

se = ellipseStrel(seLengthPx);
closed = imclose(single(correctedGreen), se);
tophat = closed - single(correctedGreen);
if ~isempty(workingMask)
    vals = tophat(workingMask);
else
    vals = tophat(:);
end
if isempty(vals)
    candidate = false(size(tophat));
    return;
end
% numpy's default percentile interpolation is linear; prctile's
% "inclusive" method matches it (R2022a+).
thresh = prctile(vals, THRESH_CANDIDATE_TOPHAT_PERCENTILE, "Method", "inclusive");
candidate = tophat > thresh;
if ~isempty(workingMask)
    candidate = candidate & workingMask;
end
end

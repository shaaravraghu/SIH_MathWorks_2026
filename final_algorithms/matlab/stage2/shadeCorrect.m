function out = shadeCorrect(green, mask)
%SHADECORRECT Step 1 of the five-step lesion pipeline: local light shade-
%   correction. Not a reuse of stage1's flat field correction module (that
%   is per-image quality gating); this is a lightweight local background
%   subtraction so lesion candidates aren't swamped by large-scale
%   illumination gradients. Exact method is not pinned in the notes -
%   documented approximation: subtract a heavily blurred estimate of the
%   background and re-add the global mean. Mirrors lesion_pipeline.py
%   shade_correct. mask may be [] to use the whole image.

SHADE_CORRECTION_KERNEL_FRACTION = 0.10; % placeholder: background-blur extent as a fraction of image height

green = double(green);
h = size(green, 1);
blurExtentPx = max(round(h * SHADE_CORRECTION_KERNEL_FRACTION), 3);
% cv2.GaussianBlur's default border is BORDER_REFLECT_101; imgaussfilt's
% 'symmetric' padding is the closest built-in approximation.
background = imgaussfilt(green, blurExtentPx / 3.0, 'Padding', 'symmetric');

if ~isempty(mask)
    valid = mask;
else
    valid = true(size(green));
end
if any(valid(:))
    globalMean = mean(green(valid));
else
    globalMean = mean(green(:));
end
out = green - background + globalMean;
end

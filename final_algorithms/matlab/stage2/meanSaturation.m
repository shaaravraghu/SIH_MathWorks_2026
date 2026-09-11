function s = meanSaturation(pixels)
%MEANSATURATION Mean HSV saturation of a set of RGB samples (N x 3, uint8
%   range). Mirrors lesion_features.py mean_saturation. MATLAB's rgb2hsv
%   already returns saturation in [0, 1] (unlike cv2.cvtColor, which
%   returns [0, 255] and needs an explicit /255 - handled here so the
%   result matches).

if isempty(pixels)
    s = 0.0;
    return;
end
hsvVals = rgb2hsv(double(pixels) / 255.0);
s = mean(hsvVals(:, 2));
end

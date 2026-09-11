function result = enhanceBorderline(image, mask)
%ENHANCEBORDERLINE #4 Enhancement (Illumination/Exposure/Contrast) for
%   Borderline images: Flat Field Correction (#4.1) -> CLAHE (#4.2) ->
%   Image Updation.
%   Background Field Estimation may blur some other key contrast details
%   in an attempt to highlight a few; the Plane and Radial Fit algorithms
%   may fail because of features that contradict the idea of a uniform
%   ascent/descent (notes #4).

ffc = flatFieldCorrection(image, mask);
if ffc.status == "fail"
    result = struct('status', "fail", 'stage', "flat_field_correction", 'ffc', ffc);
    return;
end

clahe = claheEnhancement(ffc.image, mask);
if clahe.status == "fail"
    result = struct('status', "fail", 'stage', "clahe", 'ffc', ffc, 'clahe', clahe);
    return;
end

result = struct('status', "pass", 'image', clahe.image, 'ffc', ffc, 'clahe', clahe);
end

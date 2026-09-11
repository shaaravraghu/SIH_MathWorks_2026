function out = subtractVessels(mask, vesselMask)
%SUBTRACTVESSELS Step 2 of the five-step lesion pipeline: dilate the vessel
%   mask 2-3px before subtracting, so vessel edges don't leak into lesion
%   candidates. Mirrors lesion_pipeline.py subtract_vessels.

VESSEL_DILATION_PX = 3; % pinned: "dilate the vessel mask 2-3 px before subtracting"

se = ellipseStrel(2 * VESSEL_DILATION_PX + 1);
dilatedVessels = imdilate(vesselMask, se);
out = mask & ~dilatedVessels;
end

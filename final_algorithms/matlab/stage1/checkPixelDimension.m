function result = checkPixelDimension(width, height)
%CHECKPIXELDIMENSION #1 Pixel Dimension gate.
%   Mega-Pixel Size: Borderline (0.3-1 MP), Reject (<0.3 MP), Pass (>1 MP).
%
%   result is a scalar struct with fields width, height, megapixels,
%   status ("pass" | "borderline" | "fail") -- mirrors Python's
%   PixelDimensionResult dataclass.

REJECT_MP = 0.3;
BORDERLINE_MP = 1.0;

megapixels = (width * height) / 1e6;

if megapixels < REJECT_MP
    status = "fail";
elseif megapixels < BORDERLINE_MP
    status = "borderline";
else
    status = "pass";
end

result = struct('width', width, 'height', height, 'megapixels', megapixels, 'status', status);
end

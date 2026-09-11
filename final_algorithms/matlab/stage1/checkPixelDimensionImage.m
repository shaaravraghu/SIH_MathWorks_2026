function result = checkPixelDimensionImage(image)
%CHECKPIXELDIMENSIONIMAGE #1 Pixel Dimension gate on an already-loaded image.
%   image: HxW or HxWxC array.
result = checkPixelDimension(size(image, 2), size(image, 1));
end

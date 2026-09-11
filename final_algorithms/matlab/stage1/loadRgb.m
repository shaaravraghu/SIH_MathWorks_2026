function image = loadRgb(path)
%LOADRGB Load an image as RGB.
%   MATLAB's imread already returns RGB channel order (unlike OpenCV's
%   imread, which returns BGR) -- so, unlike the Python version, no
%   BGR2RGB channel swap is needed here.

if ~isfile(path)
    error('loadRgb:FileNotFound', 'File not found: %s', path);
end
image = imread(path);
end

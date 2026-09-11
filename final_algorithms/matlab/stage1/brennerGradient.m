function score = brennerGradient(patch, shift)
%BRENNERGRADIENT #3.2 Brenner gradient, evaluated in both directions
%   ("the 2 functions") and combined as their mean.

if nargin < 2 || isempty(shift)
    shift = 2;
end

patch = double(patch);
[h, w] = size(patch);

horiz = 0.0;
if w > shift
    diffH = patch(:, shift + 1:end) - patch(:, 1:end - shift);
    horiz = mean(diffH(:) .^ 2);
end

vert = 0.0;
if h > shift
    diffV = patch(shift + 1:end, :) - patch(1:end - shift, :);
    vert = mean(diffV(:) .^ 2);
end

score = (horiz + vert) / 2.0;
end

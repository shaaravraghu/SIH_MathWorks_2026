function g = rawGreen(workRgb)
%RAWGREEN Green channel, NOT shade-corrected, surround filled with the
%   interior mean - see optic_disc.py / Stage_2_CNN_Proposed_Changes.md
%   item m1 for why the optic disc wants raw green while vessels want
%   shade-corrected green. Mirrors resample.py raw_green.

m = stage2Masks();
g = double(workRgb(:, :, 2));
if any(m.RETINA_MASK(:))
    g(~m.RETINA_MASK) = mean(g(m.RETINA_MASK));
else
    g(~m.RETINA_MASK) = 0.0;
end
end

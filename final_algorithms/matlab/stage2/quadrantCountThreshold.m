function t = quadrantCountThreshold()
%QUADRANTCOUNTTHRESHOLD Re-derived 4-2-1 count constant (see quadrants.py
%   module docstring): the textbook ">20 haemorrhages per quadrant" does
%   NOT transfer to a single 45-degree field (fired on 0/70 images at every
%   grade). Re-derived: >3 gives 93% specificity at grades 0-2 and 64%
%   sensitivity at grades 3-4. Mirrors quadrants.py QUADRANT_COUNT_THRESH.

t = 3; % pinned: re-derived constant (>3, not the textbook >20)
end

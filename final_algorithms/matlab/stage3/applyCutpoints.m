function grades = applyCutpoints(scores, cutpoints)
%APPLYCUTPOINTS Continuous grade score -> integer grade 0..4.
%   Mirrors numpy's searchsorted(side="left") so MATLAB and Python assign the
%   same grade at a score exactly equal to a cutpoint.

scores = double(scores(:));
cutpoints = sort(double(cutpoints(:)))';
grades = sum(scores >= cutpoints, 2);
end

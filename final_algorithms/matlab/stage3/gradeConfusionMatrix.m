function matrix = gradeConfusionMatrix(trueGrades, predGrades, nClasses)
%GRADECONFUSIONMATRIX §7.1: rows are the TRUE grade, columns the prediction.
%   Named to avoid shadowing the Statistics Toolbox's own confusionmat.

if nargin < 3 || isempty(nClasses), nClasses = 5; end
t = min(max(round(trueGrades(:)), 0), nClasses - 1);
p = min(max(round(predGrades(:)), 0), nClasses - 1);
matrix = accumarray([t + 1, p + 1], 1, [nClasses, nClasses]);
end

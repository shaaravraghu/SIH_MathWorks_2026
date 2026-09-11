function sens = perClassSensitivity(trueGrades, predGrades, nClasses)
%PERCLASSSENSITIVITY §7.1. Plain accuracy is FORBIDDEN here: a model
%   predicting grade 0 for everything scores 49% on APTOS's true mix. Per-
%   class sensitivity does not depend on prevalence, which matters because
%   the pilot sample is balanced at 100 per grade while the true mix is
%   49/10/27/5/8 (§5.1).
%
%   Grade-4 recall (sens(5)) is reported on its own line per §8: the previous
%   model predicted grade 4 for only 3 of 61 true grade-4 images.

if nargin < 3 || isempty(nClasses), nClasses = 5; end
matrix = gradeConfusionMatrix(trueGrades, predGrades, nClasses);
sens = nan(1, nClasses);
for c = 1:nClasses
    total = sum(matrix(c, :));
    if total > 0
        sens(c) = matrix(c, c) / total;
    end
end
end

function calibrator = fitPlattCalibrator(scores, labels)
%FITPLATTCALIBRATOR §6.4/§7.1: logistic (Platt) calibration of the continuous
%   grade score into P(referable).
%
%   Fitted on the 425 OUT-OF-FOLD dev predictions and FROZEN before the test
%   set is touched (§7.2).

model = fitglm(double(scores(:)), double(labels(:) > 0), ...
    'Distribution', 'binomial', 'Link', 'logit');
calibrator = struct('kind', "platt", 'model', model);
end

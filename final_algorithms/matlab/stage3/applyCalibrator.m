function probabilities = applyCalibrator(calibrator, scores)
%APPLYCALIBRATOR Applies a calibrator fitted on out-of-fold predictions.

scores = double(scores(:));
if calibrator.kind == "platt"
    probabilities = predict(calibrator.model, scores);
else
    % out_of_bounds="clip", matching the Python implementation
    if numel(calibrator.x) == 1
        probabilities = repmat(calibrator.y, size(scores));
    else
        probabilities = interp1(calibrator.x, calibrator.y, scores, 'linear', 'extrap');
    end
    probabilities = min(max(probabilities, min(calibrator.y)), max(calibrator.y));
end
probabilities = min(max(probabilities(:), 0), 1);
end

function scores = predictGradingModel(model, X)
%PREDICTGRADINGMODEL Prediction interface for the §6.2 grading network.
%
%   model: the struct returned by fitGradingMlp, whose `kind` field says
%   whether it was trained with trainnet (plain MSE, flat class weights) or
%   the §6.2.2 custom weighted-MSE loop -- the two need different predict
%   calls.
%
%   The §6.3 RandomForest baseline this function used to also cover has been
%   removed: Module 3 grading is neural-network only (see fitGradingMlp.m).

if ~isstruct(model) || ~isfield(model, 'net')
    error('predictGradingModel:badModel', ...
        'Expected the struct from fitGradingMlp; got a %s.', class(model));
end

if model.kind == "customLoop"
    dlX = dlarray(X', 'CB');
    scores = double(extractdata(predict(model.net, dlX)))';
else
    scores = double(predict(model.net, X));
end
scores = scores(:);
end

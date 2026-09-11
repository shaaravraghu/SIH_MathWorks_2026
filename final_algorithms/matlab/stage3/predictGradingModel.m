function scores = predictGradingModel(model, X)
%PREDICTGRADINGMODEL Uniform prediction interface over the two §6 models, so
%   the fold loop does not branch on model type.
%
%   model: either a fitrensemble regression model (§6.3 forest) or the struct
%   returned by fitGradingMlp (§6.2 MLP).

if isstruct(model) && isfield(model, 'net')
    if model.kind == "customLoop"
        dlX = dlarray(X', 'CB');
        scores = double(extractdata(predict(model.net, dlX)))';
    else
        scores = double(predict(model.net, X));
    end
    scores = scores(:);
else
    scores = double(predict(model, X));
    scores = scores(:);
end
end

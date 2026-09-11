function model = fitGradingMlp(X, y, weights, options)
%FITGRADINGMLP §6.2's ordinal-regression MLP, implemented exactly as the plan
%   specifies (§6.2.1 architecture, §6.2.2 hyperparameters, §6.2.3 init).
%
%       inputs (12..38), z-scored
%         -> fullyConnected 32 -> ReLU -> dropout 0.3
%         -> fullyConnected 16 -> ReLU -> dropout 0.3
%         -> fullyConnected 1                    continuous grade score
%       loss: MSE weighted per class (inverse frequency within the fold)
%
%   TWO HIDDEN LAYERS, NOT ONE OR THREE (§6.2). This matches the (32,16) and
%   (64,32) MLPs already measured in §6.3. One wide layer concentrates
%   overfitting risk; a third layer adds weights ~340 rows/fold cannot
%   support. Phase 5 tunes WIDTH, not depth, at this data size.
%
%   SIZE CHECK (§6.2.4). 38 inputs gives 1,793 trainable weights against
%   about 340 training rows per fold -- over five weights per example. The
%   dropout, weight decay, decaying learning rate and early stopping below
%   are all REQUIRED, not optional extras.
%
%   CLASS WEIGHTS (§6.2.2). trainnet's loss function sees only predictions
%   and targets, never per-row weights, so §6.2.2 offers two routes:
%   a custom training loop (the exact implementation), or plain MSE when
%   every weight lands within about 0.9-1.1. This function takes the custom
%   loop whenever the weights are not flat, and trainnet otherwise -- and
%   says which it used. The Python version cannot express either (sklearn's
%   MLPRegressor has no dropout and no sample weights), so THIS is the
%   plan's architecture; see python/stage3/models.py fit_mlp for that
%   deviation.

arguments
    X double
    y double
    weights double = []
    options.Hidden (1,2) double = [32 16]   % §6.2.1
    options.Dropout (1,1) double = 0.3      % §6.2.2
    options.L2 (1,1) double = 1e-2          % §6.2.2, justified by §6.2.4
    options.LearnRate (1,1) double = 1e-3   % §6.2.2: Adam's usual default
    options.LearnRateDropFactor (1,1) double = 0.5   % §6.2.2: x0.5 ...
    options.LearnRateDropPeriod (1,1) double = 30    % ... every 30 epochs
    options.MiniBatchSize (1,1) double = 32 % §6.2.2: ~11 mini-batches/fold-epoch
    options.MaxEpochs (1,1) double = 200    % §6.2.2: an upper bound only
    options.Patience (1,1) double = 20      % §6.2.2: early stopping
    options.ValidationFraction (1,1) double = 0.15  % inner split of the training folds (§6.1)
    options.Seed (1,1) double = 0
end

y = y(:);
numFeatures = size(X, 2);

[classWeights, rounded, isFlat] = gradeClassWeights(y);
if isempty(weights)
    weights = classWeights(rounded + 1);
end
weights = weights(:);

% §6.2.1/§6.2.3: He init for both ReLU hidden layers (Glorot under-scales for
% ReLU's half-zeroed output); Glorot for the linear output layer, since
% nothing after it is a ReLU. All biases start at zero.
layers = [
    featureInputLayer(numFeatures)
    fullyConnectedLayer(options.Hidden(1), WeightsInitializer="he", BiasInitializer="zeros")
    reluLayer
    dropoutLayer(options.Dropout)
    fullyConnectedLayer(options.Hidden(2), WeightsInitializer="he", BiasInitializer="zeros")
    reluLayer
    dropoutLayer(options.Dropout)
    fullyConnectedLayer(1, WeightsInitializer="glorot", BiasInitializer="zeros")];

% Inner validation split of the training rows, for early stopping (§6.1).
stream = RandStream('mt19937ar', 'Seed', options.Seed);
n = size(X, 1);
perm = randperm(stream, n);
nVal = max(round(options.ValidationFraction * n), 1);
valIdx = perm(1:nVal);
trainIdx = perm(nVal+1:end);

if isFlat
    % §6.2.2 permits plain MSE when every class weight is within ~0.9-1.1,
    % which grade-stratified folds from a 100-per-grade sample should give.
    opts = trainingOptions("adam", ...
        InitialLearnRate=options.LearnRate, LearnRateSchedule="piecewise", ...
        LearnRateDropFactor=options.LearnRateDropFactor, ...
        LearnRateDropPeriod=options.LearnRateDropPeriod, ...
        MiniBatchSize=options.MiniBatchSize, MaxEpochs=options.MaxEpochs, ...
        L2Regularization=options.L2, ...
        ValidationData={X(valIdx, :), y(valIdx)}, ValidationPatience=options.Patience, ...
        Shuffle="every-epoch", Verbose=false);
    net = trainnet(X(trainIdx, :), y(trainIdx), layers, "mse", opts);
    model = struct('net', net, 'kind', "trainnet", 'weighted', false);
else
    % §6.2.2's "exact implementation": a custom loop so each row's squared
    % error carries its class weight.
    net = trainWeightedLoop(layers, X, y, weights, trainIdx, valIdx, options);
    model = struct('net', net, 'kind', "customLoop", 'weighted', true);
end
end


function net = trainWeightedLoop(layers, X, y, weights, trainIdx, valIdx, options)
% §6.2.2 custom training loop: dlnetwork + dlfeval + adamupdate, with the
% weighted MSE of §6.2.2 computed directly. Early stopping on the inner
% validation split, piecewise LR decay, and L2 applied as decoupled weight
% decay on the learnable weights.
net = dlnetwork(layers);

Xtrain = X(trainIdx, :);  ytrain = y(trainIdx);  wtrain = weights(trainIdx);
Xval = X(valIdx, :);      yval = y(valIdx);      wval = weights(valIdx);

averageGrad = []; averageSqGrad = [];
iteration = 0;
bestLoss = Inf; bestNet = net; sinceBest = 0;
stream = RandStream('mt19937ar', 'Seed', options.Seed + 1);

for epoch = 1:options.MaxEpochs
    learnRate = options.LearnRate * ...
        options.LearnRateDropFactor ^ floor((epoch - 1) / options.LearnRateDropPeriod);

    order = randperm(stream, size(Xtrain, 1));
    for start = 1:options.MiniBatchSize:numel(order)
        stop = min(start + options.MiniBatchSize - 1, numel(order));
        batch = order(start:stop);
        iteration = iteration + 1;

        dlX = dlarray(Xtrain(batch, :)', 'CB');
        dlY = dlarray(ytrain(batch)', 'CB');
        dlW = dlarray(wtrain(batch)', 'CB');

        [~, gradients] = dlfeval(@weightedMseGradients, net, dlX, dlY, dlW);
        % Decoupled L2 (§6.2.2 weight decay 1e-2) on weight learnables only.
        isWeight = gradients.Parameter == "Weights";
        gradients.Value(isWeight) = cellfun(@(g, w) g + options.L2 * w, ...
            gradients.Value(isWeight), net.Learnables.Value(isWeight), ...
            'UniformOutput', false);

        [net, averageGrad, averageSqGrad] = adamupdate( ...
            net, gradients, averageGrad, averageSqGrad, iteration, learnRate);
    end

    % early stopping on the inner validation split (§6.1, §6.2.2)
    dlXv = dlarray(Xval', 'CB');
    predictions = extractdata(predict(net, dlXv))';
    valLoss = sum(wval .* (predictions - yval) .^ 2) / max(sum(wval), eps);
    if valLoss < bestLoss - 1e-9
        bestLoss = valLoss; bestNet = net; sinceBest = 0;
    else
        sinceBest = sinceBest + 1;
        if sinceBest >= options.Patience
            break;
        end
    end
end
net = bestNet;
end


function [loss, gradients] = weightedMseGradients(net, dlX, dlY, dlW)
% §6.2.2:  loss = (1/N) * sum_i w_{grade(i)} * (score_i - grade_i)^2
predictions = forward(net, dlX);
loss = sum(dlW .* (predictions - dlY) .^ 2) / max(sum(dlW), eps);
gradients = dlgradient(loss, net.Learnables);
end

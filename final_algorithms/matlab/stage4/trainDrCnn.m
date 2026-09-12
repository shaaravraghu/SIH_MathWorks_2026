function info = trainDrCnn(options)
%TRAINDRCNN Stage 4 step 2: the CNN branch, trained from scratch.
%
% WHY FROM SCRATCH. Grad-CAM attributes a class score back to a convolutional
% feature map, so it needs a CNN; the Stage 3 grader is an MLP over 12 tabular
% features and has no spatial feature maps to attribute onto. Transfer learning
% from ResNet-18 would be the stronger starting point, but the pretrained
% weights are a support package that is not installed on this machine, and
% imagePretrainedNetwork(...,Weights="none") gives untrained layers anyway. A
% small purpose-built network trains faster on CPU than ResNet-18 does and
% keeps a 14x14 final feature map, which is what makes the Grad-CAM readable.
%
% The last convolution is named "features" -- that is the layer gradCAM
% attributes onto (see gradCamOverlay).
%
% Class imbalance is handled by oversampling the minority grades to the size of
% the largest class, rather than by a weighted loss, so plain "crossentropy"
% can be used unchanged.
%
% Saves the network, class names and input size to <DataDir>/module3_cnn.mat.

arguments
    options.DataDir (1,1) string = ""            % preprocessForCnn output
    options.ModelFile (1,1) string = ""
    options.Size (1,1) double = 224
    options.MaxEpochs (1,1) double = 12
    options.MiniBatchSize (1,1) double = 16
    options.LearnRate (1,1) double = 1e-3
    options.ValidationFraction (1,1) double = 0.1
    options.Seed (1,1) double = 0
end

repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if options.DataDir == "", options.DataDir = fullfile(repo, "data", "cnn_224"); end
if options.ModelFile == "", options.ModelFile = fullfile(repo, "data", "module3_cnn.mat"); end

rng(options.Seed);
imds = imageDatastore(options.DataDir, IncludeSubfolders=true, LabelSource="foldernames");
fprintf('images: %d\n', numel(imds.Files));
summary(imds.Labels)

[imdsTrain, imdsVal] = splitEachLabel(imds, 1 - options.ValidationFraction, 'randomized');
imdsTrain = balanceByOversampling(imdsTrain);
fprintf('train %d (balanced), validation %d\n', numel(imdsTrain.Files), numel(imdsVal.Files));

inputSize = [options.Size, options.Size, 3];
augmenter = imageDataAugmenter(RandXReflection=true, RandYReflection=true, ...
    RandRotation=[-15 15], RandScale=[0.9 1.1]);
dsTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, DataAugmentation=augmenter);
dsVal = augmentedImageDatastore(inputSize(1:2), imdsVal);

classNames = categories(imds.Labels);
layers = [
    imageInputLayer(inputSize, Normalization="rescale-zero-one")
    convBlock(32), maxPooling2dLayer(2, Stride=2)
    convBlock(64), maxPooling2dLayer(2, Stride=2)
    convBlock(128), maxPooling2dLayer(2, Stride=2)
    % Final convolution: 14x14 spatial at a 224 input -- the Grad-CAM layer.
    convolution2dLayer(3, 256, Padding="same", Name="features")
    batchNormalizationLayer, reluLayer
    globalAveragePooling2dLayer
    dropoutLayer(0.4)
    fullyConnectedLayer(numel(classNames))
    softmaxLayer];

opts = trainingOptions("adam", ...
    InitialLearnRate=options.LearnRate, ...
    LearnRateSchedule="piecewise", LearnRateDropFactor=0.5, LearnRateDropPeriod=4, ...
    MiniBatchSize=options.MiniBatchSize, MaxEpochs=options.MaxEpochs, ...
    ValidationData=dsVal, ValidationFrequency=100, ValidationPatience=5, ...
    Shuffle="every-epoch", Verbose=true, VerboseFrequency=100, Metrics="accuracy");

t0 = tic;
net = trainnet(dsTrain, layers, "crossentropy", opts);
trainMinutes = toc(t0) / 60;

scores = minibatchpredict(net, dsVal);
[~, idx] = max(scores, [], 2);
predicted = categorical(classNames(idx), classNames);
accuracy = mean(predicted == imdsVal.Labels);

% Referable = grade >= 2, the decision the report actually makes.
referableTrue = double(imdsVal.Labels) >= 3;   % categories are "0".."4"
referableScore = sum(scores(:, 3:end), 2);
fprintf('\nvalidation accuracy %.3f over %d images, %.1f min\n', accuracy, numel(imdsVal.Files), trainMinutes);

cnn = struct('net', net, 'class_names', {classNames}, 'input_size', inputSize, ...
    'feature_layer', "features", 'validation_accuracy', accuracy, ...
    'train_minutes', trainMinutes, 'created', datetime('now'));
save(options.ModelFile, 'cnn');
fprintf('saved %s\n', options.ModelFile);

info = struct('accuracy', accuracy, 'referable_true', referableTrue, ...
    'referable_score', referableScore, 'minutes', trainMinutes);
end


function layers = convBlock(numFilters)
layers = [
    convolution2dLayer(3, numFilters, Padding="same")
    batchNormalizationLayer
    reluLayer];
end


function out = balanceByOversampling(imds)
% Replicate minority-class files up to the largest class count, so plain
% crossentropy sees a balanced stream (grade 0 is ~49% of APTOS).
labels = imds.Labels;
counts = countcats(labels);
target = max(counts);
cats = categories(labels);

files = {};
newLabels = {};
for k = 1:numel(cats)
    inClass = find(labels == cats{k});
    if isempty(inClass), continue; end
    pick = inClass(randi(numel(inClass), target, 1));
    files = [files; imds.Files(pick)]; %#ok<AGROW>
    newLabels = [newLabels; repmat(cats(k), target, 1)]; %#ok<AGROW>
end

out = imageDatastore(files);
out.Labels = categorical(newLabels, cats);
end

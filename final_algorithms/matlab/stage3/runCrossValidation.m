function oof = runCrossValidation(data, cacheDir, featureNames, options)
%RUNCROSSVALIDATION §6.1: the leakage-safe cross-validation loop.
%
%     for each of the 5 dev folds:
%         train rows = the other 4 folds
%         1. fit every lesion candidate classifier on TRAIN rows only   (§4.1)
%         2. extract lesion counts for TRAIN and the held-out fold with them
%         3. fit z-score normalisation on TRAIN rows only
%         4. train the model on TRAIN rows
%         5. predict the held-out fold  ->  out-of-fold predictions
%
%   Steps 1-2 are the expensive ones and the reason this is not a call to
%   crossval(): candidate features are cached per image, but the lesion
%   classifiers are refitted five times so no image is ever scored by a
%   classifier that trained on it (§4.1).
%
%   oof: struct with ids, scores, grades, resolutions, folds (per-fold
%   artefacts). Aligned to the dev rows that produced a prediction.

arguments
    data struct
    cacheDir (1,1) string
    featureNames cell
    options.Model (1,1) string = "forest"     % "forest" (§6.3) | "mlp" (§6.2)
    options.RefitLesions (1,1) logical = true % false is LEAKY -- QC only (§4.1)
    options.Verbose (1,1) logical = true
end

isDev = data.split == "dev";
foldIds = unique(data.cv_fold(isDev));
foldIds = foldIds(foldIds ~= "");
if isempty(foldIds)
    error('runCrossValidation:noFolds', ...
        'No dev rows carry a cv_fold -- check data/module3_splits.csv.');
end

gradeMap = containers.Map(cellstr(data.ids), num2cell(data.grades));

scores = nan(numel(data.ids), 1);
predicted = false(numel(data.ids), 1);
foldArtefacts = struct('fold', {}, 'model', {}, 'scaler', {}, 'classifiers', {}, ...
                       'n_train', {}, 'n_held', {});

for k = 1:numel(foldIds)
    fold = foldIds(k);
    heldMask = isDev & data.cv_fold == fold;
    trainMask = isDev & data.cv_fold ~= fold;

    if options.Verbose
        fprintf('  fold %s: train %d | held-out %d\n', fold, sum(trainMask), sum(heldMask));
    end

    trainIds = data.ids(trainMask);
    heldIds = data.ids(heldMask);

    % --- step 1 + 2: lesion classifiers on TRAIN rows only (§4.1) ----------
    if options.RefitLesions
        classifiers = fitLesionClassifiers(cacheDir, trainIds, gradeMap, options.Verbose);
        trainOver = recomputeLesionColumns(cacheDir, trainIds, classifiers, options.Verbose);
        heldOver = recomputeLesionColumns(cacheDir, heldIds, classifiers, options.Verbose);
    else
        % Knowingly-leaky fast path: reuses the placeholder-rule columns
        % already in the CSV. QC only -- never report a metric from this.
        classifiers = [];
        trainOver = containers.Map('KeyType', 'char', 'ValueType', 'any');
        heldOver = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    Xtrain = datasetMatrix(data, trainMask, featureNames, trainOver);
    Xheld = datasetMatrix(data, heldMask, featureNames, heldOver);
    ytrain = data.grades(trainMask);

    % --- step 3: z-score on TRAIN rows only --------------------------------
    scaler = zscoreFit(Xtrain);
    Xtrain = zscoreApply(scaler, Xtrain);
    Xheld = zscoreApply(scaler, Xheld);

    % --- step 4: train ------------------------------------------------------
    [classWeights, rounded] = gradeClassWeights(ytrain);
    if options.Model == "forest"
        model = fitGradingForest(Xtrain, ytrain, classWeights(rounded + 1));
    else
        model = fitGradingMlp(Xtrain, ytrain);
    end

    % --- step 5: predict the held-out fold ----------------------------------
    scores(heldMask) = predictGradingModel(model, Xheld);
    predicted(heldMask) = true;

    foldArtefacts(end+1) = struct('fold', fold, 'model', model, 'scaler', scaler, ...
        'classifiers', classifiers, 'n_train', sum(trainMask), ...
        'n_held', sum(heldMask)); %#ok<AGROW>
end

oof = struct();
oof.mask = predicted;
oof.ids = data.ids(predicted);
oof.scores = scores(predicted);
oof.grades = data.grades(predicted);
oof.resolutions = data.resolution(predicted);
oof.folds = foldArtefacts;
end

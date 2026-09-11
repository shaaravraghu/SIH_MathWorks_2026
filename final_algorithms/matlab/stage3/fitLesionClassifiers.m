function classifiers = fitLesionClassifiers(cacheDir, trainIds, gradeMap, verbose)
%FITLESIONCLASSIFIERS §6.1 step 1 + §4.1: fit the lesion candidate
%   classifiers INSIDE one cross-validation fold, on TRAINING rows only.
%
%   WHY THIS EXISTS. Each lesion counter contains a classifier trained on
%   weak labels taken from the image grade (grade 0 vs grades 3-4). If that
%   classifier is fitted on an image and then scores the same image, the
%   lesion count for that image already encodes its grade, and Module 3
%   learns the answer rather than the disease. This HAS ALREADY HAPPENED:
%   the previous implementation's microaneurysm classifier trained on 250
%   images and all 250 sat inside the 309-row feature table (§4.1).
%
%   WEAK LABELS (§4.1): positive = candidates from grade 3-4 images,
%   negative = candidates from grade 0 images. Grades 1-2 are DROPPED from
%   classifier training -- they are the ambiguous middle and the plan's
%   weak-label definition names only 0 against 3-4. Those images are still
%   SCORED, just never trained on.
%
%   classifiers: struct with fields ma/haem/hard_exudate/cws, each a struct
%   with model and threshold, shaped for stage2FeaturesFromCandidates. A
%   class with too little labelled candidate data gets an empty model, and
%   stage2 falls back to its documented placeholder rule rather than
%   silently skipping step 5.

if nargin < 4 || isempty(verbose), verbose = true; end

LESION_KEYS = {'ma', 'haem', 'hard_exudate', 'cws'};
MIN_TRAINING_CANDIDATES = 30;
MIN_MINORITY_CANDIDATES = 10;
N_TREES = 200;
MIN_LEAF = 5;

classifiers = struct();
for k = 1:numel(LESION_KEYS)
    key = LESION_KEYS{k};
    [X, y] = weakLabelMatrix(cacheDir, trainIds, gradeMap, key);

    enoughRows = numel(y) >= MIN_TRAINING_CANDIDATES;
    enoughMinority = ~isempty(y) && min(sum(y == 0), sum(y == 1)) >= MIN_MINORITY_CANDIDATES;

    if ~enoughRows || ~enoughMinority
        classifiers.(key) = struct('model', [], 'threshold', classifierDefaultThreshold());
        if verbose
            fprintf('    lesion classifier %13s: placeholder (too few labelled candidates)\n', key);
        end
        continue;
    end

    template = templateTree('MinLeafSize', MIN_LEAF);
    model = fitcensemble(X, y, 'Method', 'Bag', 'NumLearningCycles', N_TREES, ...
        'Learners', template);
    threshold = selectLesionThreshold(model, cacheDir, trainIds, gradeMap, key);
    classifiers.(key) = struct('model', model, 'threshold', threshold);
    if verbose
        fprintf('    lesion classifier %13s: fitted, keep>=%.2f\n', key, threshold);
    end
end
end


function [X, y] = weakLabelMatrix(cacheDir, trainIds, gradeMap, key)
% Stacks every candidate of every training image into one table, with a weak
% label per candidate inherited from its image's grade (§4.1).
X = []; y = [];
for i = 1:numel(trainIds)
    idCode = char(trainIds(i));
    if ~isKey(gradeMap, idCode), continue; end
    grade = gradeMap(idCode);
    if grade == 0
        label = 0;
    elseif grade == 3 || grade == 4
        label = 1;
    else
        continue;   % grades 1-2: scored later, never trained on
    end

    candidates = loadCandidates(cacheDir, idCode);
    if isempty(candidates), continue; end
    if ~isfield(candidates.lesion_candidates, key), continue; end
    packed = candidates.lesion_candidates.(key);
    if isempty(packed.features), continue; end

    X = [X; packed.features]; %#ok<AGROW>
    y = [y; repmat(label, size(packed.features, 1), 1)]; %#ok<AGROW>
end
end


function threshold = selectLesionThreshold(model, cacheDir, trainIds, gradeMap, key)
% §4.1's PRE-DECLARED criterion: the LOWEST probability at which the median
% per-image candidate count on GRADE-0 TRAINING images is 0.
%
% Fixing the criterion before sweeping is the whole point -- choosing a
% threshold to maximise a correlation and then reporting that correlation is
% circular, which the notes call out explicitly.
%
% Computed on TRAINING images only: the held-out fold must not influence the
% threshold any more than it influences the weights.

THRESHOLD_GRID = 0.05:0.05:0.95;

countsPerImage = {};
for i = 1:numel(trainIds)
    idCode = char(trainIds(i));
    if ~isKey(gradeMap, idCode) || gradeMap(idCode) ~= 0, continue; end
    candidates = loadCandidates(cacheDir, idCode);
    if isempty(candidates) || ~isfield(candidates.lesion_candidates, key)
        continue;
    end
    packed = candidates.lesion_candidates.(key);
    if isempty(packed.features)
        countsPerImage{end+1} = zeros(0, 1); %#ok<AGROW>
        continue;
    end
    [~, score] = predict(model, packed.features);
    countsPerImage{end+1} = score(:, 2); %#ok<AGROW>
end

if isempty(countsPerImage)
    threshold = classifierDefaultThreshold();
    return;
end

for t = THRESHOLD_GRID
    counts = cellfun(@(s) sum(s >= t), countsPerImage);
    if median(counts) == 0
        threshold = t;
        return;
    end
end
threshold = THRESHOLD_GRID(end);
end

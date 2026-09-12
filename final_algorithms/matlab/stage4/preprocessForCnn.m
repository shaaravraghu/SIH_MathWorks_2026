function preprocessForCnn(options)
%PREPROCESSFORCNN Stage 4 step 1: FOV-cropped, square, fixed-size copies of the
%   APTOS images for the CNN branch, written once so training never repeats it.
%
% Writes <OutDir>/<grade>/<id_code>.png, the layout imageDatastore reads with
% LabelSource="foldernames".
%
% The crop is the FOV bounding box from Stage 1's buildFovMask, so the retina
% fills the frame and the black surround (which differs by camera and is pure
% camera identity) is discarded. No Stage 1 gating or enhancement runs here:
% the CNN branch sees the image as captured, and Stage 1's verdict stays a
% separate signal the report shows alongside it.
%
% Already-written files are skipped, so an interrupted run resumes.
%
% Example:
%   preprocessForCnn(ExcludeIdsFile="data/cnn_holdout_ids.txt")

arguments
    options.AptosDir (1,1) string = ""
    options.OutDir (1,1) string = ""
    options.Size (1,1) double = 224
    options.ExcludeIdsFile (1,1) string = ""   % ids the CNN must never see
end

here = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(here, 'stage1'));
repo = fileparts(fileparts(here));
if options.AptosDir == "", options.AptosDir = fullfile(repo, "aptos2019-blindness-detection"); end
if options.OutDir == "", options.OutDir = fullfile(repo, "data", "cnn_224"); end

trainCsv = fullfile(options.AptosDir, "train.csv");
importOpts = detectImportOptions(trainCsv);
importOpts = setvartype(importOpts, 'id_code', 'string');
train = readtable(trainCsv, importOpts);

excluded = strings(0, 1);
if options.ExcludeIdsFile ~= "" && isfile(options.ExcludeIdsFile)
    excluded = strtrim(readlines(options.ExcludeIdsFile));
    excluded = excluded(excluded ~= "");
end
fprintf('excluding %d ids (demo + held-out test) from the CNN''s view\n', numel(excluded));

n = height(train);
written = 0; skipped = 0; failed = 0;
t0 = tic;
for i = 1:n
    idCode = train.id_code(i);
    if ismember(idCode, excluded)
        skipped = skipped + 1;
        continue
    end
    classDir = fullfile(options.OutDir, sprintf('%d', train.diagnosis(i)));
    if ~isfolder(classDir), mkdir(classDir); end
    dst = fullfile(classDir, idCode + ".png");
    if isfile(dst)
        written = written + 1;
        continue
    end
    try
        image = loadRgb(fullfile(options.AptosDir, "train_images", idCode + ".png"));
        imwrite(cropResize(image, options.Size), dst);
        written = written + 1;
    catch err
        failed = failed + 1;
        fprintf(2, '%s ERROR %s\n', idCode, err.message);
    end
    if mod(i, 250) == 0
        fprintf('[%d/%d] written %d, skipped %d, %.1f min\n', i, n, written, skipped, toc(t0) / 60);
    end
end
fprintf('done: %d written, %d excluded, %d failed, %.1f min\n', written, skipped, failed, toc(t0) / 60);
end


function out = cropResize(image, side)
% FOV bounding box, padded to a square so the resize does not distort the
% retina's aspect, then resized to side x side.
fov = buildFovMask(image);
[ys, xs] = find(fov.mask);
if isempty(ys)
    cropped = image;
else
    cropped = image(min(ys):max(ys), min(xs):max(xs), :);
end

[h, w, ~] = size(cropped);
padRows = max(0, w - h);
padCols = max(0, h - w);
cropped = padarray(cropped, [floor(padRows / 2), floor(padCols / 2)], 0, 'pre');
cropped = padarray(cropped, [ceil(padRows / 2), ceil(padCols / 2)], 0, 'post');

out = imresize(cropped, [side, side]);
end

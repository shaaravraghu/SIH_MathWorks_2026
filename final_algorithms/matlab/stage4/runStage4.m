function out = runStage4(leftImage, rightImage, options)
%RUNSTAGE4 Stage 4 driver: two eyes in, annotated screening report out.
%
%   out = runStage4("...left.png", "...right.png")
%   out = runStage4(left, right, OutDir="reports/patient001", Patient=p)
%
%   Produces, per eye, the labelled Stage 2 segmentation panels and the lesion
%   evidence attention map, then one PDF covering both eyes.
%
%   On Grad-CAM: the explainability spec asks for it, and this pipeline cannot
%   produce it, because Grad-CAM differentiates a class score with respect to a
%   convolutional feature map and there is no CNN here. The attention map below
%   is lesion evidence, labelled as such. Adding a CNN branch is what would
%   make a genuine Grad-CAM possible.
%
%   Roughly 30 s per eye: Stage 1, then Stage 2 twice (candidates for grading,
%   masks for drawing), then Stage 3.

arguments
    leftImage (1,1) string
    rightImage (1,1) string
    options.OutDir (1,1) string = ""
    options.ModelFile (1,1) string = ""
    options.Patient (1,1) struct = struct()
    options.Seed (1,1) double = 0
end

here = fileparts(fileparts(mfilename('fullpath')));
addpath(here, fullfile(here, 'stage1'), fullfile(here, 'stage2'), fullfile(here, 'stage3'), ...
        fullfile(here, 'stage4'));
repo = fileparts(fileparts(here));
if options.OutDir == "", options.OutDir = fullfile(repo, "reports"); end
if ~isfolder(options.OutDir), mkdir(options.OutDir); end

paths = [leftImage, rightImage];
sides = ["left", "right"];

% Collected in a cell first: assigning a full eye struct into a struct array
% seeded with fewer fields errors with "dissimilar structures".
collected = cell(1, 2);
for k = 1:2
    fprintf('=== %s eye: %s ===\n', sides(k), paths(k));
    t0 = tic;
    eye = gradeOneEye(paths(k), Side=sides(k), ModelFile=options.ModelFile, Seed=options.Seed);

    eye.panel_file = fullfile(options.OutDir, sprintf('%s_%s_panels.png', sides(k), eye.id));
    eye.attention_file = fullfile(options.OutDir, sprintf('%s_%s_attention.png', sides(k), eye.id));
    stage4Panels(eye, eye.panel_file);
    attentionOverlay(eye, eye.attention_file);

    fprintf('  grade %d, referable p = %.2f, quality %s  (%.0f s)\n', ...
        eye.grade, eye.referable_probability, string(eye.stage1.stage1_verdict), toc(t0));
    collected{k} = eye;
end
eyes = [collected{:}];

pdfPath = fullfile(options.OutDir, "screening_report.pdf");
pdfPath = generateScreeningReport(eyes, pdfPath, options.Patient);

fprintf('\nwrote %s\n', pdfPath);
out = struct('eyes', eyes, 'report', pdfPath, 'out_dir', options.OutDir);
end

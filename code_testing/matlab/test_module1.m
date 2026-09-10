function test_module1(imgPath)
%TEST_MODULE1  Smoke-test [A] detectFOV + [B] focusMetrics on one image.
%
%   test_module1                 uses the bundled reference image
%   test_module1(path)           uses your own
%
%   Prints every field of both structs and runs a synthetic blur sweep,
%   which is the fastest way to confirm the pipeline is wired correctly:
%   EVERY sharpness feature must fall monotonically as sigma rises.

if nargin < 1
    here    = fileparts(mfilename('fullpath'));
    imgPath = fullfile(here, '..', 'notes', 'Diabetic_Retinopathy_Concept', ...
                       'Fovea_&_Optic_Disk.jpg');
end

fprintf('image: %s\n', imgPath);
I = imread(imgPath);
fprintf('size : %d x %d x %d  (%s)\n\n', size(I,1), size(I,2), size(I,3), class(I));

% ---------------- [A] ----------------
t = tic;
fov = detectFOV(I);
tA  = toc(t);

if ~fov.ok
    error('detectFOV FAILED on this image');
end

fprintf('--- [A] detectFOV  (%.0f ms) ---\n', tA*1000);
fprintf('  centre       : (%.1f, %.1f)\n', fov.centre(1), fov.centre(2));
fprintf('  radius       : %.1f px\n',  fov.radius);
fprintf('  residual     : %.4f    (shape; good < 0.01)\n', fov.residual);
fprintf('  raggedness   : %.3f     (threshold sanity; clean 1.0-1.3)\n', fov.raggedness);
fprintf('  circularity  : %.3f     (UNRELIABLE -- do not gate on this)\n', fov.circularity);
fprintf('  areaFrac     : %.4f\n', fov.areaFrac);
fprintf('  offset       : %.4f\n', fov.offset);
fprintf('  borderFrac   : %.4f\n', fov.borderFrac);
fprintf('  mask         : %d px (%.1f%% of frame)\n', ...
        nnz(fov.mask), 100*mean(fov.mask(:)));
fprintf('  maskMeasure  : %d px (%.1f%% of mask kept)\n\n', ...
        nnz(fov.maskMeasure), 100*nnz(fov.maskMeasure)/nnz(fov.mask));

% ---------------- normalise ----------------
t = tic;
[J, fovJ] = normalizeFundus(I, fov, 436);
tN = toc(t);
fprintf('--- normalizeFundus  (%.0f ms) ---\n', tN*1000);
fprintf('  %d x %d, radius %.1f\n\n', size(J,1), size(J,2), fovJ.radius);

% ---------------- [B] ----------------
t = tic;
f = focusMetrics(J, fovJ);
tB = toc(t);

fprintf('--- [B] focusMetrics  (%.0f ms) ---\n', tB*1000);
names = {'varLap','varLapNorm','sml','tenengrad','tenengradVar','brenner', ...
         'specSlope','noiseSigma','regionMin','regionCV'};
for k = 1:numel(names)
    fprintf('  %-14s : %.6g\n', names{k}, f.(names{k}));
end
fprintf('  regionVals     : ');  fprintf('%.4g  ', f.regionVals);  fprintf('\n\n');

% ---------------- blur sweep ----------------
% The acceptance test.  If any column here is non-monotonic, something is
% wrong -- most often the mask was not eroded (see Module1_A doc).
fprintf('--- blur sweep (every column MUST decrease; specSlope MUST increase) ---\n');
fprintf('%7s', 'sigma');
fprintf('%13s', names{:});
fprintf('\n');

sweep = [0 0.5 1 2 4 8];
Vals  = zeros(numel(sweep), numel(names));
for i = 1:numel(sweep)
    if sweep(i) == 0
        Jb = J;
    else
        Jb = imgaussfilt(im2double(J), sweep(i));
    end
    fb = focusMetrics(Jb, fovJ);
    fprintf('%7.1f', sweep(i));
    for k = 1:numel(names)
        Vals(i,k) = fb.(names{k});
        fprintf('%13.4g', Vals(i,k));
    end
    fprintf('\n');
end

fprintf('\nmonotonicity check:\n');
for k = 1:numel(names)
    d = diff(Vals(:,k));
    switch names{k}
        case 'specSlope',  ok = all(d >= -1e-9);   want = 'increasing';
        case 'noiseSigma', ok = true;              want = 'n/a (noise, not focus)';
        case 'regionCV',   ok = true;              want = 'n/a (dispersion)';
        otherwise,         ok = all(d <=  1e-12);  want = 'decreasing';
    end
    fprintf('  %-14s %-26s %s\n', names{k}, want, ternary(ok, 'PASS', '** FAIL **'));
end

end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

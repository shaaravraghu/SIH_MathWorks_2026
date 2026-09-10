function T = benchmarkModule1(aptosRoot, perGrade)
%BENCHMARKMODULE1  Validate [A]+[B] over a stratified APTOS sample.
%
%   T = benchmarkModule1(aptosRoot)            30 images per DR grade
%   T = benchmarkModule1(aptosRoot, perGrade)
%
%   Reproduces every number in notes/docs/Module1_*.md.  Reports:
%     1. detection rate and which code paths fired
%     2. distribution of all [A] geometry + [B] focus features
%     3. Spearman correlation of each feature with DR grade
%        -- |rho| > 0.3 means the feature tracks disease/acquisition, not
%           optics, and must NOT be used as a rejection gate
%     4. fast-reject gate firing rate BY GRADE (must be flat)
%
%   Example:
%     T = benchmarkModule1('C:\...\aptos2019-blindness-detection');

if nargin < 2, perGrade = 30; end

rng(7);
lbl = readtable(fullfile(aptosRoot, 'train.csv'), 'TextType','string');

ids = strings(0,1);  grades = [];
for g = 0:4
    sub = lbl.id_code(lbl.diagnosis == g);
    k   = min(perGrade, numel(sub));
    sel = sub(randperm(numel(sub), k));
    ids = [ids; sel];  grades = [grades; repmat(g, k, 1)];  %#ok<AGROW>
end
fprintf('sampled %d images (%d per grade)\n', numel(ids), perGrade);

fNames = {'radius','residual','raggedness','circularity','areaFrac', ...
          'offset','borderFrac'};
bNames = {'varLap','varLapNorm','sml','tenengrad','tenengradVar','brenner', ...
          'specSlope','noiseSigma','regionMin','regionCV'};
allN   = [fNames bNames];

V    = nan(numel(ids), numel(allN));
okv  = false(numel(ids),1);
tRet = 0;

t0 = tic;
for i = 1:numel(ids)
    try
        I   = imread(fullfile(aptosRoot, 'train_images', ids(i) + ".png"));
        fov = detectFOV(I);
        if ~fov.ok, continue, end
        if fov.raggedness > 1.4, tRet = tRet + 1; end

        [J, fovJ] = normalizeFundus(I, fov, 436);
        fm = focusMetrics(J, fovJ);

        for k = 1:numel(fNames), V(i,k) = fov.(fNames{k}); end
        for k = 1:numel(bNames), V(i,numel(fNames)+k) = fm.(bNames{k}); end
        okv(i) = true;
    catch ME
        fprintf('  FAIL %s : %s\n', ids(i), ME.message);
    end
    if mod(i,25) == 0
        fprintf('  %3d/%d  (%.0f s)\n', i, numel(ids), toc(t0));
    end
end

V = V(okv,:);  g = grades(okv);
fprintf('\n==============================================================\n');
fprintf('DETECTION: %d/%d = %.1f%%\n', nnz(okv), numel(ids), 100*mean(okv));
fprintf('raggedness retry fired on %d images\n', tRet);
fprintf('==============================================================\n');

% ---- distributions ----
fprintf('\n%16s %10s %10s %10s %10s %10s\n', 'feature','min','p25','median','p75','max');
for k = 1:numel(allN)
    v = V(~isnan(V(:,k)), k);
    if isempty(v), fprintf('%16s   ALL NaN\n', allN{k}); continue, end
    fprintf('%16s %10.4g %10.4g %10.4g %10.4g %10.4g\n', allN{k}, ...
            min(v), prctile(v,25), median(v), prctile(v,75), max(v));
end

% ---- disease-blindness ----
fprintf('\n--- Spearman rho vs DR grade  (|rho|>0.3 = DO NOT GATE ON IT) ---\n');
for k = 1:numel(allN)
    m = ~isnan(V(:,k));
    if nnz(m) < 10, continue, end
    r = corr(V(m,k), g(m), 'Type','Spearman');
    flag = '';
    if abs(r) > 0.3, flag = '   <-- suspicious'; end
    fprintf('%16s %8.3f%s\n', allN{k}, r, flag);
end

% ---- gate by grade ----
iRes = find(strcmp(allN,'residual'));
iAre = find(strcmp(allN,'areaFrac'));
iOff = find(strcmp(allN,'offset'));
iBor = find(strcmp(allN,'borderFrac'));
rej  = V(:,iRes) > 0.06 | V(:,iAre) < 0.50 | V(:,iOff) > 0.35 | V(:,iBor) > 0.80;

fprintf('\n--- fast-reject gate BY GRADE (must be flat -- see disease-blindness) ---\n');
fprintf('%7s %6s %10s\n', 'grade', 'n', 'rejected');
for gg = 0:4
    m = g == gg;
    if ~any(m), continue, end
    fprintf('%7d %6d %8.1f%%\n', gg, nnz(m), 100*mean(rej(m)));
end
fprintf('%7s %6d %8.1f%%\n', 'ALL', numel(g), 100*mean(rej));

T = array2table(V, 'VariableNames', allN);
T.grade = g;

end

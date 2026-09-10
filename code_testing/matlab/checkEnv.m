function checkEnv(outFile)
%CHECKENV  Report which toolboxes are licensed/installed and which functions
%   resolve.  Writes to a file directly rather than relying on stdout, because
%   MATLAB -batch stdout redirection is unreliable on Windows.

if nargin < 1
    outFile = fullfile(fileparts(mfilename('fullpath')), 'env_report.txt');
end

fid = fopen(outFile, 'w');
c = onCleanup(@() fclose(fid));

fprintf(fid, 'MATLAB %s   %s\n', version, datestr(now));
fprintf(fid, 'computer: %s\n\n', computer);

feats = {'Image_Toolbox','Statistics_Toolbox','Neural_Network_Toolbox', ...
         'Video_and_Image_Blockset','Simulink','SimEvents','Medical_Imaging_Toolbox'};
nms   = {'Image Processing','Statistics and Machine Learning','Deep Learning', ...
         'Computer Vision','Simulink','SimEvents','Medical Imaging'};

v = ver();
installed = {v.Name};

fprintf(fid, '%-34s %10s %10s\n', 'TOOLBOX', 'licensed', 'installed');
fprintf(fid, '%s\n', repmat('-', 1, 56));
for k = 1:numel(feats)
    lic = license('test', feats{k});
    ins = any(contains(installed, nms{k}));
    fprintf(fid, '%-34s %10d %10d\n', nms{k}, lic, ins);
end

fprintf(fid, '\nFULL ver() LIST:\n');
for k = 1:numel(v)
    fprintf(fid, '   %-46s %s\n', v(k).Name, v(k).Version);
end

fns = {'graythresh','imfill','bwareafilt','imopen','imerode','imgradient', ...
       'imgaussfilt','imfilter','fspecial','bwboundaries','regionprops', ...
       'imresize','padarray','fibermetric','adapthisteq','imflatfield', ...
       'imbilatfilt','stdfilt','medfilt2','bwskel','bwmorph','imreconstruct', ...
       'fitcensemble','perfcurve','prctile','corr','hann','accumarray'};

fprintf(fid, '\n%-16s %s\n', 'FUNCTION', 'RESOLVES');
fprintf(fid, '%s\n', repmat('-', 1, 40));
missing = {};
for k = 1:numel(fns)
    w = which(fns{k});
    ok = ~isempty(w);
    if ~ok, missing{end+1} = fns{k}; end %#ok<AGROW>
    fprintf(fid, '%-16s %d\n', fns{k}, ok);
end

fprintf(fid, '\nMISSING: ');
if isempty(missing)
    fprintf(fid, '(none)\n');
else
    fprintf(fid, '%s ', missing{:});
    fprintf(fid, '\n');
end

fprintf(fid, '\nDONE\n');
end

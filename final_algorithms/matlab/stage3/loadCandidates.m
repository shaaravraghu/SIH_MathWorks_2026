function candidates = loadCandidates(cacheDir, idCode)
%LOADCANDIDATES Reads one image's cached Stage 2 candidates
%   (data/module3_candidates/<id>.mat, written by extractModule3Features).
%
%   Returns [] when the image has no cache -- the caller then keeps that
%   row's placeholder-rule lesion columns rather than failing the fold.
%
%   The cache is classifier-free by construction (§4.1), which is exactly
%   what makes it safe to compute once per image and reuse in every fold.

path = fullfile(cacheDir, [char(idCode) '.mat']);
if ~isfile(path)
    candidates = [];
    return;
end
loaded = load(path, 'candidates');
candidates = loaded.candidates;
end

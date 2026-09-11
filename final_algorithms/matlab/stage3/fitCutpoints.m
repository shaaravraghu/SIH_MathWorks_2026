function cutpoints = fitCutpoints(scores, trueGrades, maxPasses)
%FITCUTPOINTS §6.2 / D6: fit the four rounding cutpoints on the DEV data
%   rather than rounding a regression output at 0.5/1.5/2.5/3.5.
%
%   WHY. Rounding pulls predictions toward the middle grades (§7.3): the
%   previous model predicted grade 4 for only 3 of 61 true grade-4 images,
%   calling most of them grade 3, and called grade 1 "grade 2" more often
%   than "grade 1". Fitted cutpoints are the first remedy the plan
%   prescribes; an ordinal (CORAL) head is the second, only if middle-grade
%   collapse persists (D6).
%
%   FITTED ON OUT-OF-FOLD PREDICTIONS ONLY (§7.2), then FROZEN before the
%   test set is touched.
%
%   Method: coordinate ascent on QWK. Each cutpoint moves in turn to the
%   candidate position that maximises QWK with the others held fixed,
%   repeating until nothing improves. Deterministic, and with 425 rows an
%   exhaustive 4-D search buys nothing.

if nargin < 3 || isempty(maxPasses), maxPasses = 50; end

scores = double(scores(:));
trueGrades = min(max(round(double(trueGrades(:))), 0), 4);
if isempty(scores)
    cutpoints = [0.5 1.5 2.5 3.5];
    return;
end

% Initialise from the score quantiles matching the TRUE grade distribution --
% a far better start than naive rounding when the regression is compressed.
counts = accumarray(trueGrades + 1, 1, [5, 1]);
cumulative = cumsum(counts(1:end-1)) / max(sum(counts), 1);
cutpoints = sort(prctile(scores, 100 * min(max(cumulative, 0), 1)', "Method", "inclusive"));
cutpoints = cutpoints(:)';

candidates = candidatePositions(scores);
best = quadraticWeightedKappa(trueGrades, applyCutpoints(scores, cutpoints));

for pass = 1:maxPasses
    improved = false;
    for k = 1:numel(cutpoints)
        if k > 1, lower = cutpoints(k - 1); else, lower = -Inf; end
        if k < numel(cutpoints), upper = cutpoints(k + 1); else, upper = Inf; end
        for c = 1:numel(candidates)
            position = candidates(c);
            if position < lower || position > upper, continue; end
            trial = cutpoints;
            trial(k) = position;
            score = quadraticWeightedKappa(trueGrades, applyCutpoints(scores, trial));
            if ~isnan(score) && score > best + 1e-12
                best = score; cutpoints = trial; improved = true;
            end
        end
    end
    if ~improved, break; end
end
end


function positions = candidatePositions(scores)
% Midpoints between consecutive unique scores -- the only places a cutpoint
% changes any assignment. Capped so a large dev set stays fast.
u = unique(scores);
if numel(u) < 2, positions = u(:)'; return; end
positions = ((u(1:end-1) + u(2:end)) / 2)';
if numel(positions) > 400
    positions = prctile(positions, linspace(0, 100, 400), "Method", "inclusive");
end
end

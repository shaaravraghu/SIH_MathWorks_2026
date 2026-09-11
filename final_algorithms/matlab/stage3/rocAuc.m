function auc = rocAuc(labels, scores)
%ROCAUC Rank-based AUC (the Mann-Whitney U statistic). Ties take averaged
%   ranks, matching numpy/scipy behaviour in the Python implementation.

labels = double(labels(:) > 0);
scores = double(scores(:));
nPos = sum(labels == 1); nNeg = sum(labels == 0);
if nPos == 0 || nNeg == 0, auc = NaN; return; end

ranks = tiedrank(scores);   % Statistics Toolbox; averages ties
auc = (sum(ranks(labels == 1)) - nPos * (nPos + 1) / 2) / (nPos * nNeg);
end

function [sens, spec] = sensitivitySpecificity(labels, scores, threshold)
%SENSITIVITYSPECIFICITY At one operating threshold, for the referable
%   (grade >= 2) decision (§7.1).

labels = double(labels(:) > 0);
predicted = double(scores(:) >= threshold);

tp = sum(predicted == 1 & labels == 1);
fn = sum(predicted == 0 & labels == 1);
tn = sum(predicted == 0 & labels == 0);
fp = sum(predicted == 1 & labels == 0);

if (tp + fn) > 0, sens = tp / (tp + fn); else, sens = NaN; end
if (tn + fp) > 0, spec = tn / (tn + fp); else, spec = NaN; end
end

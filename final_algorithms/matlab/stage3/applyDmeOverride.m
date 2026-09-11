function [final, urgent] = applyDmeOverride(referableDecisions, dmeFlags)
%APPLYDMEOVERRIDE §6.4: dme_flag (S2-34) OVERRIDES the grade -- urgent
%   referral regardless of it.
%
%   An exudate within 500 um (34 px) of the fovea is sight-threatening on its
%   own, so it overrides the grading decision rather than feeding into it.
%
%   final:  the referral decision after the override
%   urgent: which rows the override fired on

decisions = logical(referableDecisions(:));
dme = logical(dmeFlags(:));
final = decisions | dme;
urgent = dme;
end

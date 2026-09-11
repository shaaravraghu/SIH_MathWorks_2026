function routed = applyConfidenceRouting(probabilities, borderline, enhanced)
%APPLYCONFIDENCEROUTING §6.4: lower the calibrated probability for images
%   Stage 1 flagged as borderline (S1-20) or enhanced (S1-21).
%
%   This changes the CONFIDENCE attached to a prediction, not the prediction
%   itself. S1-21 exists precisely because CLAHE cost 20% of microaneurysm
%   detectability in Module 1 testing -- this is how Module 3 detects that
%   effect rather than silently absorbing it.
%
%   The multipliers are NOT pinned by the plan: calibration placeholders.

CONFIDENCE_PENALTY_BORDERLINE = 0.85;   % placeholder (S1-20)
CONFIDENCE_PENALTY_ENHANCED = 0.90;     % placeholder (S1-21)

routed = double(probabilities(:));
borderline = logical(borderline(:));
enhanced = logical(enhanced(:));

routed(borderline) = routed(borderline) * CONFIDENCE_PENALTY_BORDERLINE;
routed(enhanced) = routed(enhanced) * CONFIDENCE_PENALTY_ENHANCED;
routed = min(max(routed, 0), 1);
end

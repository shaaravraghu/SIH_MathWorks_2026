function [features, blocks] = stage3Columns(lastBlock)
%STAGE3COLUMNS Which Stage 2 columns reach the grading model, and the Phase 6
%   ablation blocks (Module3_Plan.md §2.2, §6, §8, D5, D7).
%
%   features = stage3Columns()                  -> the 12-column 6a start (D5)
%   features = stage3Columns("6d_nv_split")     -> cumulative through that block
%   features = stage3Columns("all")             -> all 38 model inputs
%   [~, blocks] = stage3Columns(...)            -> the ordered block table
%
%   TWO RULES THIS FUNCTION ENFORCES, both measured rather than stylistic:
%
%   1. STAGE 1 CONTRIBUTES NO MODEL INPUTS (D7, §2.1). Module 1 features alone
%      reached AUC 0.707 for referable DR, and adding them to the Module 2 set
%      moved AUC only 0.910 -> 0.915. Within resolution strata every sharpness
%      metric's apparent link to grade turns out to be the camera: sicker
%      APTOS patients were photographed on different equipment, their retinas
%      are not blurrier. S1 columns are carried for QC and confidence routing
%      (§6.4) and never appear here.
%
%   2. EXCLUDE AND QC COLUMNS NEVER REACH THE NETWORK (§2.2). od_x/od_y/
%      fovea_x/fovea_y are raw coordinates; od_radius_pct/od_contrast/
%      od_fovea_dist_dd are localisation sanity checks whose own search window
%      bounds them (od_fovea_dist_dd within rho -0.036).
%
%   PHASE 6 ADDS BLOCKS IN ORDER, NOT ALL AT ONCE (D5): 38 inputs on ~340
%   training rows per fold overfits, so the plan starts at the 12 columns with
%   a measured within-resolution equivalent and keeps each later block only if
%   within-resolution out-of-fold QWK improves.

if nargin < 1 || isempty(lastBlock)
    lastBlock = "6a_measured_core";
end
lastBlock = string(lastBlock);

blocks = phase6Blocks();

if lastBlock == "all"
    lastBlock = blocks(end).name;
end

names = [blocks.name];
idx = find(names == lastBlock, 1);
if isempty(idx)
    error('stage3Columns:unknownBlock', ...
        'Unknown block "%s". Expected one of: %s, or "all".', lastBlock, strjoin(names, ', '));
end

features = {};
for k = 1:idx
    features = [features, blocks(k).columns]; %#ok<AGROW>
end
end

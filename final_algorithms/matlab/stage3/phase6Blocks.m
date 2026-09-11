function blocks = phase6Blocks()
%PHASE6BLOCKS The Phase 6 feature blocks, in the order §8 adds them.
%   Mirrors Python stage3/columns.py PHASE6_BLOCKS.
%
%   blocks: 1xN struct array with fields name (string) and columns (cellstr).
%   Each block is kept only if within-resolution out-of-fold QWK improves
%   (§8) -- the pooled figure partly measures the camera (§4.3), so it must
%   not be the deciding number.

blocks = struct('name', {}, 'columns', {});

% 6a: S2-01..06, 12, 13, 24, 29, 30, 37 -- the baseline the finalized design
% can already reproduce, i.e. every column with a measured within-rho.
blocks(end+1) = struct('name', "6a_measured_core", 'columns', {{ ...
    'vessel_density_pct', 'vessel_fragmentation', 'vessel_components', ...
    'vessel_largest_tree_pct', 'vessel_length', 'vessel_orientation_coherence', ...
    'nv_score', 'nv_score_max', ...
    'haem_count', 'haem_q_min', 'haem_q_max', 'rule421_haem'}});

% 6b: S2-41..45. Decision D1 -- grade 1 is DEFINED by microaneurysms, and
% ma_n ranked first on every measure tried in the previous implementation
% (within rho +0.478, same sign 5/5).
blocks(end+1) = struct('name', "6b_microaneurysm", 'columns', {{ ...
    'ma_count', 'ma_q1', 'ma_q2', 'ma_q3', 'ma_q4'}});

% 6c: S2-07..11, new and unmeasured.
blocks(end+1) = struct('name', "6c_calibre_beading", 'columns', {{ ...
    'major_vessel_pct', 'branch1_vessel_pct', 'minor_vessel_pct', ...
    'venous_beading_pct', 'venous_beading_quadrants'}});

% 6d: S2-14..16. Asks whether grade-4 recall improves -- the previous model
% predicted grade 4 for only 3 of 61 true grade-4 images (§7.3).
blocks(end+1) = struct('name', "6d_nv_split", 'columns', {{ ...
    'nvd_score', 'nve_score', 'nv_irma_quadrants'}});

% 6e: S2-31..34. CHECK THE SIGN FIRST -- the previous brightness-threshold
% exudate detector was INVERTED: healthy eyes averaged 57 marks, diseased
% eyes 17-23. The finalized ratio-based detector is new and unvalidated.
blocks(end+1) = struct('name', "6e_exudate_dme", 'columns', {{ ...
    'hard_exudate_count', 'hard_exudate_area_pct', ...
    'exudate_fovea_min_dist_dd', 'dme_flag'}});

% 6f: S2-35, 36, new.
blocks(end+1) = struct('name', "6f_cws", 'columns', {{ ...
    'cws_count', 'cws_area_pct'}});

% 6g: S2-25..28, 38..40 -- the spatial rule.
blocks(end+1) = struct('name', "6g_quadrants_421", 'columns', {{ ...
    'haem_q1', 'haem_q2', 'haem_q3', 'haem_q4', ...
    'rule421_beading', 'rule421_irma', 'severe_npdr_flag'}});
end

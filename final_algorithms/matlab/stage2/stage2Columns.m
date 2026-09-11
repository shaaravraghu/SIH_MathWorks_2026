function [columns, roles] = stage2Columns()
%STAGE2COLUMNS Stage 2 feature row for Module 3 (Module3_Plan.md S2.2, S3,
%   S4.1; S2-01..S2-45). Mirrors features.py STAGE2_COLUMNS/STAGE2_ROLES.
%
%   columns: 1x45 cellstr of column names, in CSV column order.
%   roles (optional second output): containers.Map from column name to
%   role string ("EXCLUDE" | "QC" | "MODEL"), mirroring Python's
%   STAGE2_ROLES dict.

columns = { ...
    'vessel_density_pct', 'vessel_fragmentation', 'vessel_components', ...          % S2-01..03
    'vessel_largest_tree_pct', 'vessel_length', 'vessel_orientation_coherence', ...  % S2-04..06
    'major_vessel_pct', 'branch1_vessel_pct', 'minor_vessel_pct', ...                % S2-07..09
    'venous_beading_pct', 'venous_beading_quadrants', ...                            % S2-10..11
    'nv_score', 'nv_score_max', 'nvd_score', 'nve_score', 'nv_irma_quadrants', ...    % S2-12..16
    'od_x', 'od_y', 'od_radius_pct', 'od_contrast', ...                              % S2-17..20
    'fovea_x', 'fovea_y', 'od_fovea_dist_dd', ...                                    % S2-21..23
    'haem_count', 'haem_q1', 'haem_q2', 'haem_q3', 'haem_q4', 'haem_q_min', 'haem_q_max', ... % S2-24..30
    'hard_exudate_count', 'hard_exudate_area_pct', 'exudate_fovea_min_dist_dd', 'dme_flag', ... % S2-31..34
    'cws_count', 'cws_area_pct', ...                                                 % S2-35..36
    'rule421_haem', 'rule421_beading', 'rule421_irma', 'severe_npdr_flag', ...        % S2-37..40
    'ma_count', 'ma_q1', 'ma_q2', 'ma_q3', 'ma_q4' ...                                % S2-41..45
    };

if nargout > 1
    exclude = {'od_x', 'od_y', 'fovea_x', 'fovea_y'};
    qc = {'od_radius_pct', 'od_contrast', 'od_fovea_dist_dd'};
    roleValues = cell(1, numel(columns));
    for i = 1:numel(columns)
        if ismember(columns{i}, exclude)
            roleValues{i} = 'EXCLUDE';
        elseif ismember(columns{i}, qc)
            roleValues{i} = 'QC';
        else
            roleValues{i} = 'MODEL';
        end
    end
    roles = containers.Map(columns, roleValues);
end
end

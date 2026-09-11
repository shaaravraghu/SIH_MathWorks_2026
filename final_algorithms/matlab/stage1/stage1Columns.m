function [columns, roles] = stage1Columns()
%STAGE1COLUMNS Stage 1 feature row for Module 3 (Module3_Plan.md S2.1, S1-01..S1-21).
%   Stage 1 contributes NO model inputs: every column is QC, CONF or
%   EXCLUDE (decision D7). Within resolution strata every sharpness
%   metric's apparent link to grade turns out to be the camera, and
%   megapixels alone predicts referable DR at AUC 0.809, so none of these
%   may reach the grading network.
%
%   columns: 1x21 cellstr of column names, in CSV column order.
%   roles (optional second output): containers.Map from column name to
%   role string ("EXCLUDE" | "QC" | "CONF"), mirroring Python's
%   STAGE1_ROLES dict.
%
%   (Python's MODULE1_EQUIVALENT rank-comparison mapping is documentation
%   for cross-checking against a different CSV and is not needed
%   downstream here, so it is not ported.)

columns = { ...
    'megapixels', ...          % S1-01
    'aspect_ratio', ...        % S1-02
    'area_ratio_s1', ...       % S1-03
    'area_ratio_s2', ...       % S1-04
    'black_region_pct', ...    % S1-05
    'varLapNorm', ...          % S1-06
    'specSlope', ...           % S1-07
    'brenner', ...             % S1-08
    'tenengradVar', ...        % S1-09
    'regionMin', ...           % S1-10
    'region_centre', ...       % S1-11
    'region_q1', ...           % S1-12
    'region_q2', ...           % S1-13
    'region_q3', ...           % S1-14
    'region_q4', ...           % S1-15
    'illum_plane_tilt', ...    % S1-16
    'illum_radial', ...        % S1-17
    'local_contrast', ...      % S1-18
    'saturation_count', ...    % S1-19
    'stage1_verdict', ...      % S1-20
    'enhancement_applied' ...  % S1-21
    };

if nargout > 1
    roleValues = { ...
        'EXCLUDE', 'EXCLUDE', 'QC', 'QC', 'EXCLUDE', 'QC', 'QC', 'QC', ...
        'EXCLUDE', ... % tenengradVar: pooled rho +0.352 but within rho +0.024 -- the camera
        'QC', 'QC', 'QC', 'QC', 'QC', 'QC', 'QC', 'QC', 'QC', 'QC', ...
        'CONF', 'CONF' ...
        };
    roles = containers.Map(columns, roleValues);
end
end

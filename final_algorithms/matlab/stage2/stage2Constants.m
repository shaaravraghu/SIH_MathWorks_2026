function c = stage2Constants()
%STAGE2CONSTANTS Working-resolution normalisation constants shared by every
%   Stage 2 feature (resample.py). Every pixel constant quoted in
%   Stage_2_CNN (2.7-10.1 px vessel bands, 14.9 um/px, L=15/41 structuring
%   elements, 1 DD for NVD/NVE, etc.) assumes images are resampled so the
%   retina radius is exactly TARGET_R pixels.

c = struct();
c.TARGET_R = 436;                      % pinned: working-resolution retina radius, px
c.OD_R_PX = round(436 / 7.0);          % 62 px
c.DD_PX = 2 * c.OD_R_PX;               % 124 px, one disc diameter
c.UM_PER_PX = 1850.0 / c.DD_PX;        % ~14.9 um/px - where the scale table's 14.9 comes from
c.DME_RADIUS_PX = 34;                  % pinned: 500 um DME zone radius
end

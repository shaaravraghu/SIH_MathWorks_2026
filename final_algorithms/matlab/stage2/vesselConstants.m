function c = vesselConstants()
%VESSELCONSTANTS #VESSELS (a)-(c) scale table, calibre-band and fine-scale-
%   excess constants (see notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN,
%   "VESSELS" section). Mirrors vessels.py's module-level constants.

c = struct();

% --- scale table (VESSELS, shared px<->um conversion) -----------------------
c.UM_PER_PX = 14.9;
c.VESSEL_WIDTH_UM_MIN = 40.0;
c.VESSEL_WIDTH_UM_MAX = 150.0;
c.VESSEL_WIDTH_PX_MIN = c.VESSEL_WIDTH_UM_MIN / c.UM_PER_PX;  % ~2.7 px
c.VESSEL_WIDTH_PX_MAX = c.VESSEL_WIDTH_UM_MAX / c.UM_PER_PX;  % ~10.1 px

% calibre bands, in px, anchored to the scale table (pinned exactly in notes)
c.MINOR_VESSEL_MIN_PX = c.VESSEL_WIDTH_PX_MIN;   % 2.7 px
c.FIRST_BRANCH_MIN_PX = 4.0;
c.MAJOR_VESSEL_MIN_PX = 7.0;
% Widths above VESSEL_WIDTH_PX_MAX (10.1 px, the scale table's own upper
% bound) are outside the normal major-vessel band -> venous beading. The
% notes say "width above the major-vessel band" without a numeric cap, so
% the scale table's own ceiling is used as that cap - documented judgment
% call, flagged for review.
c.BEADING_MIN_PX = c.VESSEL_WIDTH_PX_MAX;

c.CALIBRE_BEADING = int8(0);
c.CALIBRE_MAJOR = int8(1);
c.CALIBRE_FIRST_BRANCH = int8(2);
c.CALIBRE_MINOR = int8(3);

c.CLASS_MAJOR = int8(0);
c.CLASS_NEOVASCULARISATION = int8(1);
c.CLASS_IRMA = int8(2);

% --- (a) matched filtering ---------------------------------------------------
% Chaudhuri-style: a bank of oriented Gaussian-cross-section kernels, matched
% to "approx. width of main & 1st branch" vessels. The notes do not pin
% sigma/length/orientation-count/binarisation-percentile for this filter ->
% placeholders below (calibrate before use).
c.MATCHED_FILTER_SIGMA_PX = 2.0;          % placeholder: ~half of the 4-10px major/1st-branch band
c.MATCHED_FILTER_LENGTH_PX = 9;           % placeholder
c.MATCHED_FILTER_N_ORIENTATIONS = 12;     % placeholder: 15 degree steps
c.THRESH_MATCHED_FILTER_PERCENTILE = 90.0; % placeholder: binarisation threshold not pinned in notes

% --- (b) Frangi multi-scale vesselness --------------------------------------
% sigma ~ vessel_radius / sqrt(2). Do NOT add a sigma below ~2.7 px - the
% notes report that a sigma of 1.2 px (18 um) corrupted the map, moving
% measured branchpoints from 195 to 2,539.
c.FRANGI_SIGMA_FLOOR_PX = 2.7;
% Tension in the notes, documented rather than silently resolved: the width
% formula above would want sigma ~0.95px for the MINOR_VESSEL_MIN_PX (2.7px)
% band, which is below the floor just stated. The floor wins here (per the
% explicit branchpoint-corruption warning), so calibre resolution below
% roughly a 7.6px-equivalent width is coarser than the formula alone would
% give. Judgment call - flagged for review.
c.FRANGI_SIGMA_MAX_PX = 6.0;   % placeholder: covers up to ~17px width (venous-beading range)
c.FRANGI_N_SCALES = 8;         % placeholder: number of sigma steps in the scan
c.FRANGI_BETA = 0.5;           % standard Frangi blobness-term sensitivity
c.FRANGI_GAMMA = 15.0;         % standard Frangi structureness-term sensitivity (placeholder magnitude)

% --- (c) fine-scale excess (major / NV / IRMA) ------------------------------
c.FINE_LINE_LENGTH_PX = 9;     % pinned: L=9
c.FINE_LINE_WIDTH_PX = 11;     % pinned: W=11
c.COARSE_LINE_LENGTH_PX = 31;  % pinned: L=31
c.COARSE_LINE_WIDTH_PX = 31;   % pinned: W=31
c.EXCESS_PERCENTILE = 92.0;    % pinned: p92
c.COARSE_DILATE_KERNEL_PX = 5; % pinned: 5x5 dilation
c.LINE_DETECTOR_N_ORIENTATIONS = 12; % pinned (matches the reused line_detector definition)

c.NVD_MAX_DISC_DIAMETERS = 1.0; % pinned: NVD if within 1 DD of the OD centre
end

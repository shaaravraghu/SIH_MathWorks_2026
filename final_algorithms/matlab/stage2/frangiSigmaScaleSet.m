function sigmas = frangiSigmaScaleSet()
%FRANGISIGMASCALESET Sigma scan array, floored at FRANGI_SIGMA_FLOOR_PX per
%   the branchpoint-corruption caveat (see vessels.py module docstring).
%   Mirrors vessels.py frangi_sigma_scale_set.

vc = vesselConstants();
sigmas = linspace(vc.FRANGI_SIGMA_FLOOR_PX, vc.FRANGI_SIGMA_MAX_PX, vc.FRANGI_N_SCALES);
end

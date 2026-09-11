function v = frangiResponse(gray, sigma, beta, gamma, darkRidges)
%FRANGIRESPONSE 2D Frangi vesselness at one scale, via Hessian eigenvalues
%   (scipy.ndimage Gaussian derivatives), rather than skimage.filters.frangi
%   (skimage is not part of stage1's numpy/opencv/scipy-equivalent stack) -
%   documented judgment call, mirroring vessels.py frangi_response.
%
%   Retinal vessels are DARK relative to background in the green channel,
%   so darkRidges=true keeps only the polarity where the cross-ridge second
%   derivative is positive (lambda2 > 0); bright-ridge structure is
%   suppressed.

if nargin < 3 || isempty(beta)
    vc = vesselConstants();
    beta = vc.FRANGI_BETA;
end
if nargin < 4 || isempty(gamma)
    vc = vesselConstants();
    gamma = vc.FRANGI_GAMMA;
end
if nargin < 5 || isempty(darkRidges)
    darkRidges = true;
end

[Ixx, Iyy, Ixy] = hessianElements(double(gray), sigma);
[lambda1, lambda2] = hessianEigenvalues(Ixx, Iyy, Ixy);
lambda2Safe = lambda2;
lambda2Safe(lambda2 == 0) = 1e-6;

rb = lambda1 ./ lambda2Safe; % blobness - NOT used for width, see vessels module docstring
s = sqrt(lambda1 .^ 2 + lambda2 .^ 2);
v = exp(-(rb .^ 2) / (2 * beta ^ 2)) .* (1 - exp(-(s .^ 2) / (2 * gamma ^ 2)));

if darkRidges
    polarityOk = lambda2 > 0;
else
    polarityOk = lambda2 < 0;
end
v(~polarityOk) = 0.0;
end


function [Ixx, Iyy, Ixy] = hessianElements(gray, sigma)
% Private helper (Python _hessian_elements). scipy's gaussian_filter with
% order=(0,2)/(2,0)/(1,1) computes a Gaussian-smoothed 2nd derivative along
% each axis; imgaussfilt has no derivative-order option, so the derivative
% is taken explicitly (central differences) after Gaussian smoothing, which
% is mathematically equivalent for a Gaussian kernel (differentiation and
% convolution commute) - documented approximation of the finite-difference
% discretisation.
smoothed = imgaussfilt(gray, sigma, 'Padding', 'symmetric');
[Gx, Gy] = gradient(smoothed);
[Gxx, Gxy] = gradient(Gx);
[Gyx, Gyy] = gradient(Gy);
Ixy0 = 0.5 * (Gxy + Gyx);
norm = sigma ^ 2; % gamma-normalised derivatives, comparable across sigma
Ixx = Gxx * norm;
Iyy = Gyy * norm;
Ixy = Ixy0 * norm;
end


function [lambda1, lambda2] = hessianEigenvalues(Ixx, Iyy, Ixy)
% Private helper (Python _hessian_eigenvalues).
tmp = sqrt((Ixx - Iyy) .^ 2 + 4 * Ixy .^ 2);
a = 0.5 * (Ixx + Iyy + tmp);
b = 0.5 * (Ixx + Iyy - tmp);
swap = abs(a) > abs(b);
lambda1 = b; lambda1(~swap) = a(~swap);
lambda2 = a; lambda2(~swap) = b(~swap);
end

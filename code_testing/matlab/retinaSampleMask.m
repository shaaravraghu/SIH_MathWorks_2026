function [M, patches] = retinaSampleMask(fov, mode, varargin)
%RETINASAMPLEMASK  Build a sampling mask for stage [B] focus metrics.
%
%   M = retinaSampleMask(fov, 'full')
%   M = retinaSampleMask(fov, 'ring')                  % 8 x 2.5% @ 0.80R
%   M = retinaSampleMask(fov, 'ring', n, ringR, frac)
%   [M, patches] = retinaSampleMask(...)               % per-patch masks
%
%   Measured on 40 APTOS images x 4 blur levels (872x872, R=436):
%
%     mode                  %px    ms   speedup   rho    med rel err
%     full                 100%  26.4     1.00x  1.000          0%
%     ring 8 x 2.5% @0.80R  21%   5.4     4.88x  0.985         19%
%     ring 8 x 2.5% @0.65R  21%   5.5     4.83x  0.973         78%
%     ring 8 x 2.5% @0.50R  21%   5.3     4.95x  0.955         86%
%     central r < 0.40R     17%   3.8     6.86x  0.944        146%
%
%   RING RADIUS DOMINATES.  At identical cost, 0.80R beats 0.50R by 4.5x on
%   relative error.  Reason: the full-mask value is area-weighted and area
%   grows as r^2, so most retinal pixels live near the rim.  Sampling the
%   centre measures an unrepresentative minority -- which is also why the
%   'central' mode is the worst option tested despite being the fastest.
%
%   Structure density is NOT the reason: measured mean |Laplacian| varies by
%   under 15% from centre to rim, so the fovea is not edge-poor.
%
%   The 8 patches double as the 5-region breakdown used by regionMin /
%   regionCV -- you get the 4,100x partial-blur detector for free.

if nargin < 2, mode = 'ring'; end

R  = fov.radius;
cx = fov.centre(1);
cy = fov.centre(2);
[h, w]   = size(fov.maskMeasure);
[xx, yy] = meshgrid(1:w, 1:h);

switch lower(mode)

    case 'full'
        M       = fov.maskMeasure;
        patches = {M};

    case 'central'
        % Included for completeness -- NOT recommended, see the table above.
        fr = 0.40;
        if ~isempty(varargin), fr = varargin{1}; end
        M       = fov.maskMeasure & hypot(xx-cx, yy-cy) < fr*R;
        patches = {M};

    case 'ring'
        n     = 8;
        ringR = 0.80;
        frac  = 0.025;
        if numel(varargin) >= 1, n     = varargin{1}; end
        if numel(varargin) >= 2, ringR = varargin{2}; end
        if numel(varargin) >= 3, frac  = varargin{3}; end

        % pi*pr^2 = frac * pi*R^2  ->  pr = sqrt(frac)*R
        pr      = sqrt(frac) * R;
        patches = cell(1, n);
        M       = false(h, w);
        for k = 1:n
            a  = 2*pi*(k-1)/n;
            py = cy - ringR*R*sin(a);
            px = cx + ringR*R*cos(a);
            p  = fov.maskMeasure & hypot(xx-px, yy-py) <= pr;
            patches{k} = p;
            M = M | p;
        end

    otherwise
        error('retinaSampleMask:mode', ...
              'mode must be ''full'', ''ring'' or ''central''');
end

end

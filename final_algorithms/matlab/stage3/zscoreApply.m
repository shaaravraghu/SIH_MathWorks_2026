function Z = zscoreApply(scaler, X)
%ZSCOREAPPLY Applies a scaler fitted by zscoreFit on training rows only.
Z = (X - scaler.mean) ./ scaler.scale;
end

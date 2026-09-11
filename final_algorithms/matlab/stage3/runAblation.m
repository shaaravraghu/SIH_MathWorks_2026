function table = runAblation(data, cacheDir, options)
%RUNABLATION §8 Phase 6: add the feature blocks in order, keeping a block
%   only if WITHIN-RESOLUTION out-of-fold QWK improves.
%
%   The pooled figure must NOT be the deciding number (§4.3): even the
%   Module 2 features alone identify the camera 66% of the time against a
%   16.7% chance baseline, and on the previous implementation pooled
%   referable AUC ranked gradient boosting first (0.928) while within strata
%   it came last (0.660). Pooled comparisons reward learning the camera.
%
%   D5 is the reason this walk exists at all: 38 inputs on about 340
%   training rows per fold overfits, so the design starts at the 12 columns
%   with a measured within-resolution equivalent and earns the rest.
%
%   table: struct array with block, n_features, qwk_pooled, qwk_within,
%   delta_within, keep.

arguments
    data struct
    cacheDir (1,1) string
    options.RefitLesions (1,1) logical = true
    options.Verbose (1,1) logical = true
end

blocks = phase6Blocks();
table = struct('block', {}, 'n_features', {}, 'qwk_pooled', {}, ...
               'qwk_within', {}, 'delta_within', {}, 'keep', {});
previous = NaN;

for k = 1:numel(blocks)
    name = blocks(k).name;
    featureNames = stage3Columns(name);
    if options.Verbose
        fprintf('\n[%s] %d features\n', name, numel(featureNames));
    end

    oof = runCrossValidation(data, cacheDir, featureNames, ...
        RefitLesions=options.RefitLesions, Verbose=false);

    cutpoints = fitCutpoints(oof.scores, oof.grades);
    predicted = applyCutpoints(oof.scores, cutpoints);
    pooled = quadraticWeightedKappa(oof.grades, predicted);
    within = withinResolution(@(t, p) quadraticWeightedKappa(t, p), ...
        oof.resolutions, {oof.grades, predicted});

    if isnan(previous)
        delta = NaN;
        keep = true;
    else
        delta = within.mean - previous;
        keep = delta > 0;
    end

    table(end+1) = struct('block', name, 'n_features', numel(featureNames), ...
        'qwk_pooled', pooled, 'qwk_within', within.mean, ...
        'delta_within', delta, 'keep', keep); %#ok<AGROW>

    if options.Verbose
        if isnan(delta)
            fprintf('  QWK pooled %.4f | within resolution %.4f\n', pooled, within.mean);
        else
            if keep, verdict = 'KEEP'; else, verdict = 'DROP'; end
            fprintf('  QWK pooled %.4f | within resolution %.4f  (within %+.4f  ->  %s)\n', ...
                pooled, within.mean, delta, verdict);
        end
    end

    if keep
        previous = within.mean;
    end
end
end

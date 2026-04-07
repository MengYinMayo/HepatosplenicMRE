function corrMap = computeSliceCorrespondence(S)
% COMPUTESLICECORRESPONDENCE  Find Dixon slices that spatially overlap each MRE slice.
%
%   Returns corrMap — a struct array with one entry per MRE slice:
%     corrMap(i).mreSlice       - MRE slice index (1-based)
%     corrMap(i).mreCenter_mm   - physical z-center of MRE slice
%     corrMap(i).dixonIndices   - Dixon slice indices overlapping this MRE slice
%     corrMap(i).dixonWeights   - fractional overlap weights (sum to 1)
%     corrMap(i).coverageFrac   - fraction of MRE slab covered by Dixon
%     corrMap(i).warning        - '' or description of coverage problem

    mreHdrs   = S.mre.magnitude.headers;
    dixonHdrs = S.dixon.fat.headers;    % use fat channel for geometry (all channels identical)

    nMRE   = numel(mreHdrs);
    nDixon = numel(dixonHdrs);

    % Build per-slice physical positions and slab boundaries
    mreBounds   = getSlabBounds(mreHdrs);    % [nMRE x 2] [zTop, zBottom] in mm
    dixonBounds = getSlabBounds(dixonHdrs);  % [nDixon x 2]

    % Check that stacks are approximately parallel (dot product of normals)
    mreNormal   = getSliceNormal(mreHdrs{1});
    dixonNormal = getSliceNormal(dixonHdrs{1});
    parallelism = abs(dot(mreNormal, dixonNormal));
    if parallelism < 0.99
        warning('computeSliceCorrespondence:notParallel', ...
            'MRE and Dixon stacks are not parallel (dot=%.3f). Registration required.', ...
            parallelism);
    end

    corrMap = struct();
    for i = 1:nMRE
        mreTop = mreBounds(i,1);
        mreBot = mreBounds(i,2);
        mreCtr = (mreTop + mreBot) / 2;
        mreThk = abs(mreTop - mreBot);

        corrMap(i).mreSlice     = i;
        corrMap(i).mreCenter_mm = mreCtr;
        corrMap(i).dixonIndices = [];
        corrMap(i).dixonWeights = [];
        corrMap(i).warning      = '';

        totalOverlap = 0;
        weights = zeros(1, nDixon);

        for j = 1:nDixon
            dTop = dixonBounds(j,1);
            dBot = dixonBounds(j,2);

            % Overlap = intersection of [mreBot, mreTop] and [dBot, dTop]
            overlapTop = min(mreTop, dTop);
            overlapBot = max(mreBot, dBot);
            overlap    = max(0, overlapTop - overlapBot);

            if overlap > 0
                weights(j)   = overlap;
                totalOverlap = totalOverlap + overlap;
            end
        end

        if totalOverlap == 0
            corrMap(i).warning = sprintf('MRE slice %d has no overlapping Dixon slices', i);
            corrMap(i).coverageFrac = 0;
            continue
        end

        % Normalize weights; keep only non-zero entries
        overlapping = weights > 0;
        corrMap(i).dixonIndices  = find(overlapping);
        corrMap(i).dixonWeights  = weights(overlapping) / totalOverlap;
        corrMap(i).coverageFrac  = min(1, totalOverlap / mreThk);

        if corrMap(i).coverageFrac < 0.80
            corrMap(i).warning = sprintf(...
                'MRE slice %d: only %.0f%% covered by Dixon stack', ...
                i, corrMap(i).coverageFrac * 100);
        end
    end
end
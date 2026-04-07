function S = extractBodyCompAtL1L2(S, varargin)
% EXTRACTBODYCOMPATL1L2  Measure muscle and SAT at the L1-L2 slab.
%
%   Requires:
%     - S.landmarks.L1L2 populated (propagateL1L2Slab already called)
%     - S.seg.muscle, S.seg.sat populated (segmentation module already run)
%     - S.dixon.fat.registeredToMRE or S.dixon.pdff.pixelData available

    p = inputParser();
    addParameter(p, 'MuscleType', 'all',  @(x) ismember(x,{'all','paraspinal','total'}));
    addParameter(p, 'Verbose',    true,   @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    dixonIdx = S.landmarks.L1L2.dixonSlices;
    mreIdx   = S.landmarks.L1L2.mreSlices;

    if isempty(dixonIdx)
        warning('extractBodyCompAtL1L2:noSlices', 'No Dixon slices at L1-L2 level.');
        return
    end

    ps_mm   = S.dixon.fat.voxelSize_mm(1:2);    % [row col] spacing in mm
    voxArea_cm2 = prod(ps_mm) / 100;             % mm² → cm²

    %% --- Dixon-derived measurements ---
    muscleMask_L1L2 = S.seg.muscle(:,:,dixonIdx);   % [R x C x nSlices]
    satMask_L1L2    = S.seg.sat(:,:,dixonIdx);

    % Thickness-weighted combination across slices
    w = S.landmarks.L1L2.dixonSliceWeights;   % normalized overlap weights

    % Area: weighted mean across slices (each slice contributes proportionally)
    muscleAreaPerSlice = squeeze(sum(sum(muscleMask_L1L2, 1), 2)) * voxArea_cm2;
    satAreaPerSlice    = squeeze(sum(sum(satMask_L1L2,    1), 2)) * voxArea_cm2;

    S.features.l1l2.muscleArea_cm2 = dot(muscleAreaPerSlice(:), w(:));
    S.features.l1l2.satArea_cm2    = dot(satAreaPerSlice(:),    w(:));
    S.features.l1l2.nDixonSlicesUsed = numel(dixonIdx);

    % PDFF within muscle at L1-L2
    if isfield(S.dixon, 'pdff') && S.dixon.pdff.identified && ~isempty(S.dixon.pdff.pixelData)
        pdffVol = S.dixon.pdff.pixelData(:,:,dixonIdx);
    elseif isfield(S.dixon.fat, 'registeredToMRE')
        % Compute PDFF from fat/(fat+water) if PDFF map not available
        fatVol   = S.dixon.fat.registeredToMRE(:,:,mreIdx);
        waterVol = S.dixon.water.registeredToMRE(:,:,mreIdx);
        pdffVol  = fatVol ./ (fatVol + waterVol + eps) * 100;
        % Remap back to Dixon slice indices for masking
        pdffVol = S.dixon.pdff.pixelData(:,:,dixonIdx);  % fallback
    else
        pdffVol = [];
    end

    if ~isempty(pdffVol)
        pdffPerSlice = zeros(numel(dixonIdx), 1);
        for k = 1:numel(dixonIdx)
            maskSlice = logical(muscleMask_L1L2(:,:,k));
            pdffSlice = pdffVol(:,:,k);
            if any(maskSlice(:))
                pdffPerSlice(k) = mean(pdffSlice(maskSlice));
            end
        end
        S.features.l1l2.musclePDFF_pct = dot(pdffPerSlice, w(:));
    end

    %% --- MRE-derived measurements at L1-L2 ---
    if ~isempty(mreIdx) && S.landmarks.L1L2.mreCoverage >= 0.5
        stiffVol  = S.mre.stiffness.pixelData;
        mrePS_mm  = S.mre.stiffness.voxelSize_mm(1:2);
        mreVoxArea_cm2 = prod(mrePS_mm) / 100;

        % Muscle mask in MRE space — use registeredToMRE if available
        if isfield(S.seg, 'muscleOnMRE') && ~isempty(S.seg.muscleOnMRE)
            muscleMaskMRE = S.seg.muscleOnMRE(:,:,mreIdx);
        else
            % Fallback: use co-registered muscle mask (nearest-neighbor resample)
            muscleMaskMRE = resampleMaskToMRE(S.seg.muscle, S, 'nearest');
            muscleMaskMRE = muscleMaskMRE(:,:,mreIdx);
        end

        wMRE = S.landmarks.L1L2.mreSliceWeights;
        stiffPerSlice = zeros(numel(mreIdx), 1);

        for k = 1:numel(mreIdx)
            sl   = mreIdx(k);
            mask = logical(muscleMaskMRE(:,:,k));
            stiffSlice = stiffVol(:,:,sl);

            % Validity mask: stiffness values must be in physiological range
            validStiff = stiffSlice > 0.5 & stiffSlice < 30;   % kPa
            combined   = mask & validStiff;

            if any(combined(:))
                stiffPerSlice(k) = mean(stiffSlice(combined));
            end
        end

        if any(stiffPerSlice > 0)
            S.features.l1l2.muscleStiffness_kPa = dot(stiffPerSlice, wMRE(:));
            S.features.l1l2.nMREslicesUsed      = numel(mreIdx);
        end
    else
        if opts.Verbose
            fprintf('[L1-L2] MRE coverage insufficient (%.0f%%) — stiffness set to NaN\n', ...
                S.landmarks.L1L2.mreCoverage * 100);
        end
    end

    if opts.Verbose
        fprintf('[L1-L2] Muscle area: %.1f cm² | SAT area: %.1f cm² | Muscle PDFF: %.1f%%\n', ...
            S.features.l1l2.muscleArea_cm2, S.features.l1l2.satArea_cm2, ...
            S.features.l1l2.musclePDFF_pct);
        if ~isnan(S.features.l1l2.muscleStiffness_kPa)
            fprintf('[L1-L2] Muscle stiffness: %.2f kPa\n', S.features.l1l2.muscleStiffness_kPa);
        end
    end
end
function [S, regResult] = registerDixonToMRE(S, varargin)
% REGISTERDIXONTOMRE  Detect and correct in-plane motion between Dixon and MRE.
%
%   Uses normalized mutual information as the similarity metric,
%   with a rigid (translation + rotation) transformation model.
%
%   Motion is detected per MRE slice. If max displacement exceeds
%   motionThreshold_mm, rigid registration is applied.

    p = inputParser();
    addParameter(p, 'MotionThreshold_mm', 3.0,  @isnumeric);
    addParameter(p, 'Verbose',            true,  @islogical);
    addParameter(p, 'MaxIterations',      200,   @isnumeric);
    parse(p, varargin{:});
    opts = p.Results;

    regResult.applied          = false;
    regResult.motionPerSlice   = zeros(1, S.mre.magnitude.nSlices);
    regResult.transforms       = {};
    regResult.nmiPerSlice      = zeros(1, S.mre.magnitude.nSlices);
    regResult.warning          = '';

    nSlices = S.mre.magnitude.nSlices;

    % Get Dixon fat channel resampled to MRE grid (reference space)
    dixonOnMRE = resampleDixonToMRE(S, 'fat');

    %% Step 1 — Detect motion per slice
    for sl = 1:nSlices
        mreSlice   = S.mre.magnitude.pixelData(:,:,sl);
        dixonSlice = dixonOnMRE(:,:,sl);

        % Skip slices where Dixon coverage is poor
        if all(dixonSlice(:) == 0), continue; end

        % Normalize both images to [0,1] for NMI computation
        mreNorm   = normalizeImage(mreSlice);
        dixonNorm = normalizeImage(dixonSlice);

        % Initial NMI (no registration)
        nmi0 = computeNMI(mreNorm, dixonNorm);
        regResult.nmiPerSlice(sl) = nmi0;
    end

    %% Step 2 — Estimate motion using imregtform (MATLAB Image Processing Toolbox)
    for sl = 1:nSlices
        mreSlice   = S.mre.magnitude.pixelData(:,:,sl);
        dixonSlice = dixonOnMRE(:,:,sl);

        if all(dixonSlice(:) == 0), continue; end

        % Use imregconfig for optimizer/metric setup
        [optimizer, metric] = imregconfig('multimodal');
        optimizer.MaximumIterations = opts.MaxIterations;
        optimizer.InitialRadius     = 1e-3;
        optimizer.Epsilon           = 1.5e-5;
        optimizer.GrowthFactor      = 1.01;

        % Spatial referencing objects (both in MRE pixel space)
        mreRef   = imref2d(size(mreSlice));
        dixonRef = imref2d(size(dixonSlice));

        try
            tform = imregtform(dixonSlice, dixonRef, mreSlice, mreRef, ...
                               'rigid', optimizer, metric, ...
                               'PyramidLevels', 3);

            % Extract translation magnitude from transform matrix
            tx = tform.T(3,1);
            ty = tform.T(3,2);
            ps = S.mre.magnitude.voxelSize_mm(1);   % in-plane pixel size
            displacement_mm = sqrt((tx*ps)^2 + (ty*ps)^2);

            regResult.motionPerSlice(sl) = displacement_mm;
            regResult.transforms{sl}    = tform;

            if opts.Verbose && displacement_mm > opts.MotionThreshold_mm
                fprintf('[Registration] MRE slice %d: motion %.1f mm — correction applied\n', ...
                    sl, displacement_mm);
            end

        catch ME
            warning('registerDixonToMRE:regFailed', ...
                'Registration failed for slice %d: %s', sl, ME.message);
            regResult.transforms{sl} = [];
        end
    end

    maxMotion = max(regResult.motionPerSlice);
    if maxMotion > opts.MotionThreshold_mm
        regResult.applied = true;
        if opts.Verbose
            fprintf('[Registration] Max motion: %.1f mm — applying corrections\n', maxMotion);
        end

        %% Step 3 — Apply corrections to resampled Dixon channels
        channels = {'fat','water','inPhase','outPhase'};
        if S.dixon.pdff.identified
            channels{end+1} = 'pdff';
        end

        for ch = 1:numel(channels)
            chan = channels{ch};
            dixonChanOnMRE = resampleDixonToMRE(S, chan);

            for sl = 1:nSlices
                tform = regResult.transforms{sl};
                if isempty(tform) || regResult.motionPerSlice(sl) <= opts.MotionThreshold_mm
                    continue
                end
                mreRef = imref2d(size(dixonChanOnMRE(:,:,sl)));
                dixonChanOnMRE(:,:,sl) = imwarp(dixonChanOnMRE(:,:,sl), tform, ...
                                                 'OutputView', mreRef, ...
                                                 'Interp', 'linear');
            end

            S.dixon.(chan).registeredToMRE = dixonChanOnMRE;
        end

        % Also apply to segmentation masks if they exist (nearest-neighbor interp)
        segFields = fieldnames(S.seg);
        for sf = 1:numel(segFields)
            field = segFields{sf};
            if ~isempty(S.seg.(field)) && strcmp(field, 'conf'), continue; end
            if isempty(S.seg.(field)), continue; end
            for sl = 1:nSlices
                tform = regResult.transforms{sl};
                if isempty(tform) || regResult.motionPerSlice(sl) <= opts.MotionThreshold_mm
                    continue
                end
                mreRef = imref2d(size(S.seg.(field)(:,:,sl)));
                S.seg.(field)(:,:,sl) = imwarp(S.seg.(field)(:,:,sl), tform, ...
                                                'OutputView', mreRef, ...
                                                'Interp', 'nearest');
            end
        end

        if maxMotion > 8.0
            regResult.warning = sprintf(['Max motion %.1f mm exceeds 8mm threshold — ', ...
                'registration accuracy uncertain. Flag for manual review.'], maxMotion);
            S.qc.flags{end+1} = regResult.warning;
            S.qc.reviewNeeded = true;
        end
    else
        % No significant motion — store geometrically resampled Dixon directly
        channels = {'fat','water','inPhase','outPhase'};
        for ch = 1:numel(channels)
            S.dixon.(channels{ch}).registeredToMRE = resampleDixonToMRE(S, channels{ch});
        end
        if S.dixon.pdff.identified
            S.dixon.pdff.registeredToMRE = resampleDixonToMRE(S, 'pdff');
        end
        if opts.Verbose
            fprintf('[Registration] Max motion: %.1f mm — geometric alignment sufficient\n', maxMotion);
        end
    end

    S.coregistration = regResult;
end
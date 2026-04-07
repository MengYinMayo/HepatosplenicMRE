function S = runCoregistration(S, varargin)
% RUNCOREGISTRATION  Full co-registration pipeline for one StudyData struct.
%
%   Sequentially: compute correspondence → resample → motion check → validate

    p = inputParser();
    addParameter(p, 'MotionThreshold_mm', 3.0, @isnumeric);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    if opts.Verbose
        fprintf('[Coreg] Starting co-registration for %s\n', S.patientID);
    end

    %% 1 — Slice correspondence map (always computed, stored for audit)
    S.coregistration.sliceMap = computeSliceCorrespondence(S);

    % Flag any MRE slices with poor Dixon coverage immediately
    for i = 1:numel(S.coregistration.sliceMap)
        entry = S.coregistration.sliceMap(i);
        if ~isempty(entry.warning)
            S.qc.flags{end+1} = entry.warning;
            if entry.coverageFrac == 0
                S.qc.status = 'failed';
                S.qc.reviewNeeded = true;
                warning('runCoregistration:noCoverage', '%s', entry.warning);
            end
        end
    end

    if strcmp(S.qc.status, 'failed')
        if opts.Verbose
            fprintf('[Coreg] FAILED — insufficient slice coverage\n');
        end
        return
    end

    %% 2 — Register Dixon to MRE (handles both geometric-only and motion-corrected cases)
    [S, ~] = registerDixonToMRE(S, ...
        'MotionThreshold_mm', opts.MotionThreshold_mm, ...
        'Verbose', opts.Verbose);

    %% 3 — Validate
    S = validateRegistration(S);

    if opts.Verbose
        reg = S.coregistration;
        fprintf('[Coreg] Max motion: %.1f mm | Mean NMI: %.3f | Coverage: %.0f%% | Status: %s\n', ...
            reg.validation.summary.maxMotion_mm, ...
            reg.validation.summary.meanNMI, ...
            reg.validation.summary.minCoverage * 100, ...
            S.qc.status);
    end
end
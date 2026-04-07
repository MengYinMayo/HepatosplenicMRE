function S = runL1L2Analysis(S, varargin)
% RUNL1L2ANALYSIS  Full L1-L2 body composition pipeline.
%
%   Runs detection → GUI confirmation → slab propagation → feature extraction.
%   Pass 'HeadlessMode', true to skip GUI (uses automated candidates only —
%   not recommended for production; requires downstream manual review).

    p = inputParser();
    addParameter(p, 'PatientHeight_m', NaN,    @isnumeric);
    addParameter(p, 'HeadlessMode',    false,  @islogical);
    addParameter(p, 'MuscleType',      'all',  @ischar);
    addParameter(p, 'Verbose',         true,   @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    if opts.Verbose
        fprintf('[L1-L2] Starting vertebral level analysis for %s\n', S.patientID);
    end

    %% 1 — GUI annotation (or headless auto)
    if opts.HeadlessMode
        % Use automated candidates directly — flag for review
        [sagImg, sagHdr, ~] = identifySagittalScout(S);
        candidates = detectVertebralCandidates(sagImg, sagHdr, 'Verbose', opts.Verbose);
        if ~isnan(candidates.L1_sup_z_estimated)
            S.landmarks.L1L2.L1_sup_z_mm       = candidates.L1_sup_z_estimated;
            S.landmarks.L1L2.L2_inf_z_mm       = candidates.L2_inf_z_estimated;
            S.landmarks.L1L2.slab_thickness_mm  = abs(candidates.L1_sup_z_estimated - ...
                                                      candidates.L2_inf_z_estimated);
            S.landmarks.L1L2.defined = true;
            S.landmarks.L1L2.method  = 'auto';
            S.qc.flags{end+1} = 'L1-L2: auto-detected without GUI confirmation — review required';
            S.qc.reviewNeeded  = true;
        else
            S.qc.flags{end+1} = 'L1-L2: vertebral detection failed — manual annotation needed';
            S.qc.status = 'flagged'; S.qc.reviewNeeded = true;
            warning('runL1L2Analysis:detectionFailed', ...
                'Vertebral detection failed for %s.', S.patientID);
            return
        end
    else
        S = launchL1L2Annotator(S);
        if ~S.landmarks.L1L2.defined
            warning('runL1L2Analysis:notConfirmed', 'L1-L2 not confirmed by user — skipping.');
            return
        end
    end

    %% 2 — Propagate slab to Dixon and MRE
    S = propagateL1L2Slab(S, 'Verbose', opts.Verbose);

    if isempty(S.landmarks.L1L2.dixonSlices)
        return   % QC flag already set inside propagateL1L2Slab
    end

    %% 3 — Extract features
    S = extractBodyCompAtL1L2(S, 'MuscleType', opts.MuscleType, 'Verbose', opts.Verbose);

    %% 4 — Compute ratios
    S = computeL1L2AreaRatios(S, 'PatientHeight_m', opts.PatientHeight_m, ...
                               'Verbose', opts.Verbose);

    if opts.Verbose
        printL1L2Summary(S);
    end
end

function printL1L2Summary(S)
    f = S.features.l1l2;
    lm = S.landmarks.L1L2;
    fprintf('\n--- L1-L2 Body Composition Summary: %s ---\n', S.patientID);
    fprintf('  Slab:              z=[%.1f, %.1f] mm, %.1f mm thick\n', ...
        lm.L2_inf_z_mm, lm.L1_sup_z_mm, lm.slab_thickness_mm);
    fprintf('  Dixon slices used: %d\n', lm.nDixonSlices);
    fprintf('  MRE coverage:      %.0f%%\n', lm.mreCoverage * 100);
    fprintf('  Muscle area:       %.2f cm²\n', f.muscleArea_cm2);
    fprintf('  SAT area:          %.2f cm²\n', f.satArea_cm2);
    fprintf('  Muscle:SAT ratio:  %.3f\n',     f.muscleSATratio);
    fprintf('  Muscle PDFF:       %.1f %%\n',  f.musclePDFF_pct);
    if ~isnan(f.muscleStiffness_kPa)
        fprintf('  Muscle stiffness:  %.2f kPa\n', f.muscleStiffness_kPa);
    else
        fprintf('  Muscle stiffness:  N/A (MRE not covering L1-L2)\n');
    end
    if ~isnan(f.SMI)
        fprintf('  SMI:               %.2f cm²/m² (sarcopenia: %d)\n', ...
            f.SMI, f.sarcopeniaFlag);
    end
    fprintf('  Method: %s\n\n', S.landmarks.L1L2.method);
end
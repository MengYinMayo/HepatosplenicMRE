function report = validateRegistration(S)
% VALIDATEREGISTRATION  Compute post-registration quality metrics.
%
%   Checks NMI improvement, coverage, and motion estimates per slice.
%   Adds QC flags to S if thresholds are breached.

    report.perSlice = struct();
    report.summary  = struct();
    report.passed   = true;

    nSlices = S.mre.magnitude.nSlices;

    nmiPost  = zeros(1, nSlices);
    coverage = zeros(1, nSlices);

    for sl = 1:nSlices
        mreSlice = S.mre.magnitude.pixelData(:,:,sl);

        % Use registered fat channel as reference
        if isfield(S.dixon.fat, 'registeredToMRE') && ~isempty(S.dixon.fat.registeredToMRE)
            dixonSlice = S.dixon.fat.registeredToMRE(:,:,sl);
        else
            dixonSlice = zeros(size(mreSlice));
        end

        coverage(sl) = nnz(dixonSlice) / numel(dixonSlice);
        nmiPost(sl)  = computeNMI(normalizeImage(mreSlice), normalizeImage(dixonSlice));

        report.perSlice(sl).slice    = sl;
        report.perSlice(sl).nmi      = nmiPost(sl);
        report.perSlice(sl).coverage = coverage(sl);
        report.perSlice(sl).motion   = S.coregistration.motionPerSlice(sl);
    end

    report.summary.meanNMI      = mean(nmiPost);
    report.summary.minCoverage  = min(coverage);
    report.summary.maxMotion_mm = max(S.coregistration.motionPerSlice);
    report.summary.regApplied   = S.coregistration.applied;

    % Thresholds
    if report.summary.minCoverage < 0.70
        report.passed = false;
        msg = sprintf('Low Dixon coverage on MRE grid: %.0f%%', ...
                      report.summary.minCoverage * 100);
        S.qc.flags{end+1} = msg;
    end
    if report.summary.meanNMI < 0.30
        report.passed = false;
        msg = sprintf('Low post-registration NMI: %.3f — possible registration failure', ...
                      report.summary.meanNMI);
        S.qc.flags{end+1} = msg;
    end
    if ~report.passed
        S.qc.reviewNeeded = true;
        S.qc.status = 'flagged';
    end

    S.coregistration.validation = report;
end
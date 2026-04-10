function matPath = mre_buildMATFile(exam, opts)
% MRE_BUILDMATFILE  Build the .mat input file for mmdi_roi_gui from DICOM.
%
%   MATPATH = MRE_BUILDMATFILE(EXAM) reads all relevant DICOM series from the
%   exam struct (produced by mre_parseDICOMExam), assembles the M/W/S/LapC/H
%   variables, and saves them to a .mat file ready for mmdi_roi_gui.
%
%   The output .mat file contains:
%
%     M      [256×256×nZ×nT_M]  double    Magnitude images
%                                          nT_M = 1 (time-averaged) or nPhases
%     W      [256×256×nZ×nT_W]  double    Wave images in radians
%                                          nT_W = nPhases (raw) or 8 (interpolated)
%     S      [256×256×nZ]       double    Stiffness map in kPa
%                                          (converted from Pa: S_kPa = S_Pa / 1000)
%     LapC   [256×256×nZ]       double    Laplacian confidence, range 0.000–1.000
%                                          (converted from 0–999: LapC = raw/1000)
%     H      struct              DICOM header of the first MRE wave file
%
%   OPTS fields:
%     .outputDir        char    where to save the .mat (default: exam.ExamRootDir)
%     .fileName         char    output filename (default: 'mre_data.mat')
%     .interpolateWave  logical  interpolate W from nPhases→8 (default: true)
%     .verbose          logical  (default: true)
%     .forceRebuild     logical  overwrite existing .mat (default: false)
%
%   SEE ALSO  mre_parseDICOMExam, mre_readWaveMagSeries, mre_interpolatePhases,
%             mmdi_roi_gui
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 2, opts = struct(); end

    % ── Accept either exam struct or selection struct ──────────────────
    % selection (from mre_selectSeriesGUI) has .MREGroup and .Confirmed.
    % Convert it to an exam-compatible struct so the rest of the function
    % can use exam.Series, exam.MREType, exam.ExamRootDir uniformly.
    if isfield(exam, 'Confirmed') && isfield(exam, 'MREGroup')
        % Build synthetic exam from selection
        exam = selectionToExam(exam);
    end

    % Derive outputDir from series files when not supplied
    defaultOutDir = '';
    if isfield(exam,'ExamRootDir') && ~isempty(exam.ExamRootDir)
        defaultOutDir = exam.ExamRootDir;
    elseif isfield(exam,'Series') && ~isempty(exam.Series) && ...
           isfield(exam.Series(1),'Files') && ~isempty(exam.Series(1).Files)
        defaultOutDir = fileparts(exam.Series(1).Files{1});
    end

    opts = applyDefaults(opts, struct( ...
        'outputDir',       defaultOutDir, ...
        'fileName',        'mre_data.mat', ...
        'interpolateWave', true, ...
        'verbose',         true, ...
        'forceRebuild',    false));

    matPath = fullfile(opts.outputDir, opts.fileName);

    % Check cache
    if isfile(matPath) && ~opts.forceRebuild
        vprint(opts, 'MAT file already exists: %s', matPath);
        vprint(opts, 'Use opts.forceRebuild=true to overwrite.');
        return
    end

    vprint(opts, '=== mre_buildMATFile ===');
    vprint(opts, 'MRE type: %s', exam.MREType);

    % ── Identify series roles ──────────────────────────────────────────
    roles = {exam.Series.Role};
    getSeries = @(role) exam.Series(strcmp(roles, role));

    % ── Determine primary series based on MRE type ────────────────────
    switch exam.MREType
        case 'EPI'
            waveMagRole  = 'EPI_WaveMag';
            stiffRole    = 'EPI_Stiffness';
            confRole     = 'EPI_ConfMap';
        case 'GRE'
            waveMagRole  = 'GRE_WaveMag';
            stiffRole    = 'GRE_Stiffness';
            confRole     = 'GRE_ConfMap';
        case 'both'
            % Prefer EPI if both present
            waveMagRole  = 'EPI_WaveMag';
            stiffRole    = 'EPI_Stiffness';
            confRole     = 'EPI_ConfMap';
            vprint(opts, 'Both EPI and GRE found — using EPI.');
        otherwise
            error('mre_buildMATFile:noMRE', 'No MRE series found in exam.');
    end

    % ── 1.  Read Wave + Magnitude ──────────────────────────────────────
    % For GRE: magnitude comes from GRE_WaveMag (S700, second half of files).
    %          Wave comes from GRE_ProcWave (S705) — processed, 8-phase interpolated.
    %          Fall back to splitting GRE_WaveMag if GRE_ProcWave is absent.
    wmSeries = getSeries(waveMagRole);
    if isempty(wmSeries)
        error('mre_buildMATFile:noWaveMag', 'Wave+Mag series not found.');
    end
    wmSeries = wmSeries(1);  % take first if multiple

    vprint(opts, 'Reading wave+magnitude series: S%d', wmSeries.SeriesNumber);
    [W_raw, M, sinfo, ~] = mre_readWaveMagSeries(wmSeries, opts);

    if isempty(W_raw)
        error('mre_buildMATFile:readFail', 'Failed to read wave+magnitude data.');
    end

    % ── 1b.  GRE: override W from ProcWave series (S705/S707) if present ─
    % Try each GRE_ProcWave candidate (sorted by SeriesNumber) until we
    % get a non-zero wave volume.  This handles scanners that put the
    % processed wave in S707 (nPhases>1) rather than the more common S705.
    if ismember(exam.MREType, {'GRE','both'})
        procWaveCandidates = getSeries('GRE_ProcWave');
        foundProcWave = false;
        for pwIdx = 1:numel(procWaveCandidates)
            pw = procWaveCandidates(pwIdx);
            vprint(opts, 'GRE: trying processed wave from S%d (%d files)', ...
                pw.SeriesNumber, numel(pw.Files));
            [W_proc, ~, sinfo_pw, ~] = mre_readWaveMagSeries(pw, opts);
            if ~isempty(W_proc) && max(abs(W_proc(:))) > 0
                W_raw = W_proc;
                if ~isempty(sinfo_pw) && isstruct(sinfo_pw) && ~isempty(fieldnames(sinfo_pw))
                    sinfo = sinfo_pw;
                end
                vprint(opts, 'GRE: wave from S%d — %d phases, range [%.1f, %.1f]', ...
                    pw.SeriesNumber, size(W_raw,4), min(W_raw(:)), max(W_raw(:)));
                foundProcWave = true;
                break
            else
                vprint(opts, 'GRE: S%d gave empty/zero wave — trying next candidate.', ...
                    pw.SeriesNumber);
            end
        end
        if ~foundProcWave
            vprint(opts, 'GRE: no valid ProcWave found — using WaveMag split for wave.');
        end
    end

    % ── 2.  Interpolate wave phases (4 → 8) if not already 8 ─────────
    if opts.interpolateWave && size(W_raw, 4) < 8
        vprint(opts, 'Interpolating wave phases (%d→8)...', size(W_raw, 4));
        W = mre_interpolatePhases(W_raw, 8);
    else
        W = W_raw;
        if size(W, 4) >= 8
            vprint(opts, 'Wave already has %d phases — skipping interpolation.', size(W,4));
        end
    end

    % ── 3.  Read Stiffness map ─────────────────────────────────────────
    S = [];
    stiffSeries = getSeries(stiffRole);
    if ~isempty(stiffSeries)
        stiffSeries = stiffSeries(1);
        vprint(opts, 'Reading stiffness: S%d (%d files)', ...
            stiffSeries.SeriesNumber, numel(stiffSeries.Files));
        S_raw = readGrayscaleVolume(stiffSeries.Files, ...
            size(W,1), size(W,2), size(W,3));
        % GE stores stiffness in Pa — convert to kPa
        S = double(S_raw) / 1000.0;
        vprint(opts, 'Stiffness: range [%.1f, %.1f] kPa', min(S(:)), max(S(:)));
    else
        vprint(opts, 'WARNING: No stiffness series found. S will be empty.');
        S = zeros(size(W,1), size(W,2), size(W,3));
    end

    % ── 4.  Read Confidence map ────────────────────────────────────────
    LapC = [];
    confSeries = getSeries(confRole);
    if ~isempty(confSeries)
        confSeries = confSeries(1);
        vprint(opts, 'Reading confidence map: S%d (%d files)', ...
            confSeries.SeriesNumber, numel(confSeries.Files));
        LapC_raw = readGrayscaleVolume(confSeries.Files, ...
            size(W,1), size(W,2), size(W,3));
        % GE stores confidence as 0–999 → convert to 0.000–1.000
        LapC = double(LapC_raw) / 1000.0;
        vprint(opts, 'LapC: range [%.3f, %.3f]', min(LapC(:)), max(LapC(:)));
    else
        vprint(opts, 'WARNING: No confidence map found. LapC will be empty.');
        LapC = ones(size(W,1), size(W,2), size(W,3));
    end

    % ── 5.  Build DICOM header struct ─────────────────────────────────
    H = buildHeaderStruct(wmSeries.Header, sinfo);
    % Embed full spatial info in H for cross-series co-localization
    H.SpatialInfo = sinfo;

    % ── 6.  Match S and LapC dimensions to W/M ────────────────────────
    [nR, nC, nZ] = size(W, 1, 2, 3);
    S    = matchVolumeDimensions(S,    nR, nC, nZ, 'S');
    LapC = matchVolumeDimensions(LapC, nR, nC, nZ, 'LapC');
    M    = matchVolumeDimensions(M,    nR, nC, nZ, 'M');

    % ── 7.  Save to .mat ──────────────────────────────────────────────
    vprint(opts, 'Saving: %s', matPath);
    vprint(opts, '  M:    %s  double', mat2str(size(M)));
    vprint(opts, '  W:    %s  double (radians)', mat2str(size(W)));
    vprint(opts, '  S:    %s  double (kPa)', mat2str(size(S)));
    vprint(opts, '  LapC: %s  double (0-1)', mat2str(size(LapC)));

    % Try v7.3 for large arrays, fall back to v7
    try
        save(matPath, 'M', 'W', 'S', 'LapC', 'H', '-v7.3');
        vprint(opts, 'Saved as v7.3 MAT.');
    catch
        save(matPath, 'M', 'W', 'S', 'LapC', 'H');
        vprint(opts, 'Saved as v7 MAT.');
    end

    vprint(opts, 'Done — mre_buildMATFile complete.');
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function vol = readGrayscaleVolume(files, nR, nC, nZ, opts)
%READGRAYSCALEVOLUME  Read nZ grayscale images from file list.
%   Sorts by SliceLocation (physical position), handles mismatched dims.

    if nargin < 5, opts = struct('verbose', false); end

    nFiles = numel(files);
    if nFiles == 0
        vol = zeros(nR, nC, nZ);
        return
    end

    % Sort by SliceLocation
    sliceLocs = zeros(1, nFiles);
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            else
                sliceLocs(k) = k;
            end
        catch
            sliceLocs(k) = k;
        end
    end
    [~, idx] = sort(sliceLocs);
    files = files(idx);

    % Read
    nRead = min(nFiles, nZ);
    vol   = zeros(nR, nC, nZ, 'double');

    for k = 1:nRead
        try
            img = dicomread(files{k});
            img = double(img);
            % Resize if needed
            if size(img,1) ~= nR || size(img,2) ~= nC
                img = imresize(img, [nR nC], 'bilinear');
            end
            vol(:,:,k) = img;
        catch
        end
    end
end

function vol = matchVolumeDimensions(vol, nR, nC, nZ, name)
%MATCHVOLUMEDIMENSIONS  Resize/pad volume to match expected [nR,nC,nZ].
    if isempty(vol)
        vol = zeros(nR, nC, nZ);
        return
    end
    [r, c, z] = size(vol);
    if r ~= nR || c ~= nC
        warning('mre_buildMATFile:dimMismatch', ...
            '%s in-plane size [%d×%d] ≠ [%d×%d] — resampling.', ...
            name, r, c, nR, nC);
        vol2 = zeros(nR, nC, z);
        for sl = 1:z
            vol2(:,:,sl) = imresize(vol(:,:,sl), [nR nC], 'bilinear');
        end
        vol = vol2;
    end
    if z ~= nZ
        if z < nZ
            % Pad with zeros
            vol = cat(3, vol, zeros(nR, nC, nZ-z));
        else
            % Trim to nZ
            vol = vol(:,:,1:nZ);
        end
    end
end

function H = buildHeaderStruct(hdr, sinfo)
%BUILDHEADERSTRUCT  Build the H struct expected by mmdi_roi_gui/voxelSizeFromH.
%   Contains geometry and scanner info fields needed for shape metrics.
    H = struct();

    % Physical geometry — used by voxelSizeFromH()
    if isfield(hdr, 'ReconstructionDiameter') && ~isempty(hdr.ReconstructionDiameter)
        H.DisplayFieldOfView = double(hdr.ReconstructionDiameter);
    elseif ~isempty(sinfo) && isfield(sinfo, 'VoxelSize')
        H.DisplayFieldOfView = sinfo.VoxelSize(1) * double(hdr.Rows);
    end

    if isfield(hdr, 'SliceThickness') && ~isempty(hdr.SliceThickness)
        H.SliceThickness = double(hdr.SliceThickness);
    elseif ~isempty(sinfo) && isfield(sinfo,'SliceSpacing')
        H.SliceThickness = sinfo.SliceSpacing;
    end

    if isfield(hdr, 'SpacingBetweenSlices') && ~isempty(hdr.SpacingBetweenSlices)
        H.SpacingBetweenSlices = double(hdr.SpacingBetweenSlices);
    end

    % Scanner / acquisition info
    copyFields = {'Manufacturer','ManufacturerModelName','MagneticFieldStrength', ...
                  'ProtocolName','SeriesDescription','PatientID','StudyDate', ...
                  'RepetitionTime','EchoTime','FlipAngle','PixelSpacing', ...
                  'ImageOrientationPatient','ImagePositionPatient', ...
                  'Rows','Columns','PixelBandwidth','Private_0043_1082'};
    for k = 1:numel(copyFields)
        fn = copyFields{k};
        if isfield(hdr, fn) && ~isempty(hdr.(fn))
            H.(fn) = hdr.(fn);
        end
    end

    % Drive frequency (extracted from GE private tag)
    H.DriveFrequency_Hz = 60;  % default
    if isfield(hdr, 'Private_0043_1082')
        tok = regexp(char(hdr.Private_0043_1082), 'lineFreq=(\d+)', 'tokens');
        if ~isempty(tok)
            H.DriveFrequency_Hz = str2double(tok{1}{1});
        end
    end
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k})
            opts.(fields{k}) = defaults.(fields{k});
        end
    end
end

function exam = selectionToExam(selection)
% Convert a selection struct (from mre_selectSeriesGUI) into an exam-compatible
% struct with .Series, .MREType, and .ExamRootDir fields.
    exam = struct();
    exam.Series     = selection.MREGroup;
    exam.ExamRootDir = '';

    % Derive root dir from first series file
    if ~isempty(exam.Series) && isfield(exam.Series(1),'Files') && ...
       ~isempty(exam.Series(1).Files)
        exam.ExamRootDir = fileparts(exam.Series(1).Files{1});
    end

    % Determine MREType from roles present
    roles = {exam.Series.Role};
    hasGRE = any(strncmp(roles, 'GRE_', 4));
    hasEPI = any(strncmp(roles, 'EPI_', 4));
    if hasGRE && hasEPI
        exam.MREType = 'both';
    elseif hasGRE
        exam.MREType = 'GRE';
    elseif hasEPI
        exam.MREType = 'EPI';
    else
        exam.MREType = 'unknown';
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[mre_buildMATFile] ' fmt '\n'], varargin{:});
    end
end

function matPath = mre_buildMATFile(exam, opts)
% MRE_BUILDMATFILE  Build the .mat input file for mmdi_roi_gui from DICOM.
%
%   MATPATH = MRE_BUILDMATFILE(EXAM) uses mre_parseDICOMExam output directly.
%   MATPATH = MRE_BUILDMATFILE(SELECTION) uses output from mre_selectSeriesGUI.
%
%   The second form is preferred in the interactive workflow:
%     exam      = mre_parseDICOMExam(rootDir);
%     selection = mre_selectSeriesGUI(exam);
%     matPath   = mre_buildMATFile(selection);
%
%   When called with a SELECTION struct, the function uses exactly the series
%   the user chose rather than auto-detecting from exam roles.

    if nargin < 2, opts = struct(); end

    % ── Detect whether input is exam or selection ─────────────────────
    if isfield(exam, 'Confirmed')
        % Input is a selection struct from mre_selectSeriesGUI
        matPath = buildFromSelection(exam, opts);
        return
    end

    % Otherwise fall through to original exam-based logic below
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
    opts = applyDefaults(opts, struct( ...
        'outputDir',       exam.ExamRootDir, ...
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

    % ── 2.  Interpolate wave phases (4 → 8) ───────────────────────────
    if opts.interpolateWave
        vprint(opts, 'Interpolating wave phases (4→8)...');
        W = mre_interpolatePhases(W_raw, 8);
    else
        W = W_raw;
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

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[mre_buildMATFile] ' fmt '\n'], varargin{:});
    end
end

% ======================================================================
%  SELECTION-BASED ENTRY POINT
% ======================================================================

function matPath = buildFromSelection(sel, opts)
%BUILDFROMSELECTION  Build .mat using explicit user selection from mre_selectSeriesGUI.

    opts = applyDefaults(opts, struct( ...
        'outputDir',       '', ...
        'fileName',        'mre_data.mat', ...
        'interpolateWave', true, ...
        'verbose',         true, ...
        'forceRebuild',    false));

    % Determine output dir from MRE anchor folder
    if isempty(opts.outputDir) && ~isempty(sel.MRE)
        opts.outputDir = fileparts(sel.MRE.Folder);
        % Go up one level so .mat sits next to series subfolders
        if isempty(opts.outputDir)
            opts.outputDir = sel.MRE.Folder;
        end
    end
    if isempty(opts.outputDir)
        opts.outputDir = pwd;
    end

    matPath = fullfile(opts.outputDir, opts.fileName);

    if isfile(matPath) && ~opts.forceRebuild
        vprint(opts, 'MAT file exists: %s  (use forceRebuild=true to overwrite)', matPath);
        return
    end

    vprint(opts, '=== mre_buildMATFile (from selection) ===');

    % ── MRE wave + magnitude ──────────────────────────────────────────
    W_raw = []; W = []; M = []; sinfo = struct(); S = []; LapC = []; H = [];

    if ~isempty(sel.MRE)
        grp = sel.MREGroup;
        if isempty(grp), grp = sel.MRE; end

        % ── 1a. Raw wave+magnitude (4 acquired phases + magnitude) ────
        rawSeries = findRoleInGroup(grp, ...
            {'EPI_WaveMag_Raw','GRE_WaveMag_Raw', ...
             'EPI_WaveMag',    'GRE_WaveMag'});   % legacy roles as fallback
        if isempty(rawSeries), rawSeries = sel.MRE; end

        vprint(opts, 'Reading raw wave+mag: S%d  %s', ...
            rawSeries.SeriesNumber, rawSeries.SeriesDescription);
        [W_raw, M, sinfo, ~] = mre_readWaveMagSeries(rawSeries, opts);

        % ── 1b. Processed wave (unwrapped + filtered + interpolated) ──
        procSeries = findRoleInGroup(grp, ...
            {'EPI_WaveMag_Proc','GRE_WaveMag_Proc','EPI_ProcWave','GRE_ProcWave'});

        if ~isempty(procSeries)
            vprint(opts, 'Reading processed wave: S%d  %s  (no re-interpolation)', ...
                procSeries.SeriesNumber, procSeries.SeriesDescription);
            [W_proc, ~, ~, ~] = mre_readWaveMagSeries(procSeries, opts);
            if ~isempty(W_proc)
                W = W_proc;
                vprint(opts, 'W (display): processed wave %s', mat2str(size(W)));
            end
        end

        % ── 1c. If no processed wave, interpolate raw ─────────────────
        if isempty(W) && ~isempty(W_raw)
            if opts.interpolateWave && size(W_raw,4) < 8
                vprint(opts, 'No processed wave found — interpolating raw %d→8 phases.', ...
                    size(W_raw,4));
                W = mre_interpolatePhases(W_raw, 8);
            else
                W = W_raw;
            end
        end

        % If still no magnitude, estimate from raw wave amplitude
        if isempty(M) && ~isempty(W_raw)
            vprint(opts, 'No separate magnitude — using raw wave amplitude envelope.');
            M = mean(abs(W_raw), 4);
        end

        % ── Stiffness ─────────────────────────────────────────────────
        stiffSeries = findRoleInGroup(grp, {'EPI_Stiffness','GRE_Stiffness'});
        if ~isempty(stiffSeries)
            vprint(opts, 'Reading stiffness: S%d', stiffSeries.SeriesNumber);
            nZ = max(1, round(size(W_raw,3)));
            S_raw = readGrayscaleVolume(stiffSeries.Files, 256, 256, nZ);
            S = double(S_raw) / 1000.0;   % Pa → kPa
            vprint(opts, 'S: [%.1f, %.1f] kPa', min(S(:)), max(S(:)));
        end

        % ── Confidence map ────────────────────────────────────────────
        confSeries = findRoleInGroup(grp, {'EPI_ConfMap','GRE_ConfMap'});
        if isempty(confSeries)
            confSeries = findByDesc(grp, {'confidence','conf map','laplacian'});
        end
        if ~isempty(confSeries)
            vprint(opts, 'Reading confidence: S%d', confSeries.SeriesNumber);
            nZ = max(1, round(size(W_raw,3)));
            LapC_raw = readGrayscaleVolume(confSeries.Files, 256, 256, nZ);
            LapC = double(LapC_raw) / 1000.0;   % 0–999 → 0.000–1.000
            vprint(opts, 'LapC: [%.3f, %.3f]', min(LapC(:)), max(LapC(:)));
        end

        H = buildHeaderStruct(rawSeries.Header, sinfo);
    end

    % ── Fallbacks ─────────────────────────────────────────────────────
    if isempty(W) && isempty(W_raw)
        error('mre_buildMATFile:noWave','No wave data could be read.');
    end
    if isempty(W), W = W_raw; end   % ensure W is always populated

    [nR, nC, nZ] = size(W, 1, 2, 3);

    if isempty(S),    S    = zeros(nR, nC, nZ); end
    if isempty(LapC), LapC = ones(nR, nC, nZ);  end
    if isempty(M),    M    = zeros(nR, nC, nZ);  end
    if isempty(W_raw),W_raw = W;                 end   % fallback

    S    = matchVolumeDimensions(S,    nR, nC, nZ, 'S');
    LapC = matchVolumeDimensions(LapC, nR, nC, nZ, 'LapC');
    M    = matchVolumeDimensions(M,    nR, nC, nZ, 'M');

    % ── Save ──────────────────────────────────────────────────────────
    vprint(opts, 'Saving: %s', matPath);
    vprint(opts, '  M:     %s', mat2str(size(M)));
    vprint(opts, '  W:     %s  (processed, for display)', mat2str(size(W)));
    vprint(opts, '  W_raw: %s  (raw, for QC)', mat2str(size(W_raw)));
    vprint(opts, '  S:     %s  (kPa)', mat2str(size(S)));
    vprint(opts, '  LapC:  %s  (0-1)', mat2str(size(LapC)));
    try
        save(matPath, 'M','W','W_raw','S','LapC','H', '-v7.3');
    catch
        save(matPath, 'M','W','W_raw','S','LapC','H');
    end
    vprint(opts, 'Done.');
end

function s = findRoleInGroup(grp, roles)
    s = [];
    for k = 1:numel(grp)
        if any(strcmp(grp(k).Role, roles))
            s = grp(k); return
        end
    end
end

function s = findByDesc(grp, kws)
    s = [];
    for k = 1:numel(grp)
        desc = lower(grp(k).SeriesDescription);
        for w = 1:numel(kws)
            if contains(desc, kws{w}), s = grp(k); return; end
        end
    end
end

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
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu
%   DATE    April 17, 2026

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
    [W_raw, M, sinfo, ~, M_raw] = mre_readWaveMagSeries(wmSeries, opts);

    if isempty(W_raw)
        error('mre_buildMATFile:readFail', 'Failed to read wave+magnitude data.');
    end

    % ── 2.  Prefer processed wave for display when available ───────────────
    W = [];
    procGroup  = findSameMREGroup(exam.Series, wmSeries);
    procSeries = findBestProcSeries(procGroup, wmSeries, size(W_raw,3));
    if ~isempty(procSeries)
        vprint(opts, 'Reading processed wave: S%d  %s', procSeries.SeriesNumber, procSeries.SeriesDescription);
        procOpts = opts; procOpts.forceProcessedWave = true;
        [W_proc, ~, ~, ~] = mre_readWaveMagSeries(procSeries, procOpts);
        if ~isempty(W_proc)
            if size(W_proc,3) ~= size(W_raw,3)
                vprint(opts, 'Processed wave slice count %d mismatches raw %d - ignoring proc series.', size(W_proc,3), size(W_raw,3));
            else
                if opts.interpolateWave && shouldInterpolateForMREType(exam.MREType) && size(W_proc,4) > 1 && size(W_proc,4) < 8
                    vprint(opts, 'Interpolating processed wave (%d->8).', size(W_proc,4));
                    W_proc = mre_interpolatePhases(W_proc, 8);
                end
                W = W_proc;
                vprint(opts, 'W (display): processed wave %s', mat2str(size(W)));
            end
        end
    end

    % Fallback to raw wave interpolation only if no valid processed wave exists.
    if isempty(W)
        if opts.interpolateWave && shouldInterpolateForMREType(exam.MREType) && size(W_raw,4) < 8
            vprint(opts, 'No valid processed wave found - interpolating raw %d->8 phases.', size(W_raw,4));
            W = mre_interpolatePhases(W_raw, 8);
        else
            W = W_raw;
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

    % ── 6.  Match S and LapC dimensions to W/M ────────────────────────
    [nR, nC, nZ] = size(W, 1, 2, 3);
    S    = matchVolumeDimensions(S,    nR, nC, nZ, 'S');
    LapC = matchVolumeDimensions(LapC, nR, nC, nZ, 'LapC');
    M    = matchVolumeDimensions(M,    nR, nC, nZ, 'M');
    M_raw = normalizeWaveDims(M_raw, nZ, 'M_raw');

    % ── 7.  Save to .mat ──────────────────────────────────────────────
    vprint(opts, 'Saving: %s', matPath);
    vprint(opts, '  M:    %s  double', mat2str(size(M)));
    vprint(opts, '  M_raw:%s  double (raw mag phases)', mat2str(size(M_raw)));
    vprint(opts, '  W:    %s  double (radians)', mat2str(size(W)));
    vprint(opts, '  S:    %s  double (kPa)', mat2str(size(S)));
    vprint(opts, '  LapC: %s  double (0-1)', mat2str(size(LapC)));

    % Try v7.3 for large arrays, fall back to v7
    try
        save(matPath, 'M', 'M_raw', 'W', 'W_raw', 'S', 'LapC', 'H', '-v7.3');
        vprint(opts, 'Saved as v7.3 MAT.');
    catch
        save(matPath, 'M', 'M_raw', 'W', 'W_raw', 'S', 'LapC', 'H');
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


function tf = shouldInterpolateForMREType(typeOrRole)
    tf = true;
    try
        s = char(typeOrRole);
    catch
        s = '';
    end
    s = upper(strtrim(s));
    if startsWith(s, 'EPI')
        tf = false;
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

    if isempty(opts.outputDir) && ~isempty(sel.MRE)
        opts.outputDir = fileparts(sel.MRE.Folder);
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

    W_raw = []; W = []; M = []; M_raw = []; sinfo = struct(); S = []; LapC = []; H = [];

    if ~isempty(sel.MRE)
        grp = sel.MREGroup;
        if isempty(grp), grp = sel.MRE; end
        grp = filterMREGroupToAnchorFamily(grp, sel.MRE);
        if isempty(grp), grp = sel.MRE; end

        isEPI = false;
        try
            roles = {grp.Role};
            isEPI = any(startsWith(roles, 'EPI_')) || startsWith(sel.MRE.Role, 'EPI_');
        catch
        end

        if isEPI
            [W_raw, W, M, M_raw, S, LapC, H] = buildFromSelectionEPI(grp, opts);
        else
            % -------- Existing GRE / legacy path unchanged --------
            rawSeries = findRoleInGroup(grp, ...
                {'EPI_WaveMag_Raw','GRE_WaveMag_Raw', ...
                 'EPI_WaveMag',    'GRE_WaveMag'});
            if isempty(rawSeries), rawSeries = sel.MRE; end

            vprint(opts, 'Reading raw wave+mag: S%d  %s', ...
                rawSeries.SeriesNumber, rawSeries.SeriesDescription);
            [W_raw, M, sinfo, ~, M_raw] = mre_readWaveMagSeries(rawSeries, opts);

            procSeries = findBestProcSeries(grp, rawSeries, size(W_raw,3));

            if ~isempty(procSeries)
                vprint(opts, 'Reading processed wave: S%d  %s', ...
                    procSeries.SeriesNumber, procSeries.SeriesDescription);
                procOpts = opts; procOpts.forceProcessedWave = true;
                [W_proc, ~, ~, ~] = mre_readWaveMagSeries(procSeries, procOpts);
                if ~isempty(W_proc)
                    if ~isempty(W_raw) && size(W_proc,3) ~= size(W_raw,3)
                        vprint(opts, 'Processed wave slice count %d mismatches raw %d - ignoring proc series.', ...
                            size(W_proc,3), size(W_raw,3));
                    else
                        if opts.interpolateWave && size(W_proc,4) > 1 && size(W_proc,4) < 8
                            vprint(opts, 'Interpolating processed wave (%d->8).', size(W_proc,4));
                            W_proc = mre_interpolatePhases(W_proc, 8);
                        end
                        W = W_proc;
                        vprint(opts, 'W (display): processed wave %s', mat2str(size(W)));
                    end
                end
            end

            if isempty(W) && ~isempty(W_raw)
                if opts.interpolateWave && size(W_raw,4) < 8
                    vprint(opts, 'No valid processed wave found - interpolating raw %d→8 phases.', ...
                        size(W_raw,4));
                    W = mre_interpolatePhases(W_raw, 8);
                else
                    W = W_raw;
                end
            end

            if isempty(M) && ~isempty(W_raw)
                vprint(opts, 'No separate magnitude — using raw wave amplitude envelope.');
                M = mean(abs(W_raw), 4);
            end
            if isempty(M_raw) && ~isempty(M)
                M_raw = repmat(M, [1 1 1 max(1, size(W_raw,4))]);
            end

            stiffSeries = findRoleInGroup(grp, {'EPI_Stiffness','GRE_Stiffness'});
            if ~isempty(stiffSeries)
                vprint(opts, 'Reading stiffness: S%d', stiffSeries.SeriesNumber);
                nZ = max(1, round(size(W_raw,3)));
                S_raw = readGrayscaleVolume(stiffSeries.Files, 256, 256, nZ);
                S = double(S_raw) / 1000.0;
            end

            confSeries = findRoleInGroup(grp, {'EPI_ConfMap','GRE_ConfMap'});
            if isempty(confSeries)
                confSeries = findByDesc(grp, {'confidence','conf map','laplacian'});
            end
            if ~isempty(confSeries)
                vprint(opts, 'Reading confidence: S%d', confSeries.SeriesNumber);
                nZ = max(1, round(size(W_raw,3)));
                LapC_raw = readGrayscaleVolume(confSeries.Files, 256, 256, nZ);
                LapC = double(LapC_raw) / 1000.0;
            end

            H = buildHeaderStruct(rawSeries.Header, sinfo);
        end
    end

    if isempty(W) && isempty(W_raw)
        error('mre_buildMATFile:noWave','No wave data could be read.');
    end
    if isempty(W), W = W_raw; end

    [nR, nC, nZ] = size(W, 1, 2, 3);

    if isempty(S),     S     = zeros(nR, nC, nZ); end
    if isempty(LapC),  LapC  = ones(nR, nC, nZ);  end
    if isempty(M),     M     = zeros(nR, nC, nZ); end
    if isempty(W_raw), W_raw = W;                 end
    if isempty(M_raw), M_raw = repmat(M, [1 1 1 max(1,size(W_raw,4))]); end

    S     = matchVolumeDimensions(S,     nR, nC, nZ, 'S');
    LapC  = matchVolumeDimensions(LapC,  nR, nC, nZ, 'LapC');
    M     = matchVolumeDimensions(M,     nR, nC, nZ, 'M');
    M_raw = normalizeWaveDims(M_raw, nZ, 'M_raw');
    W_raw = normalizeWaveDims(W_raw, nZ, 'W_raw');

    vprint(opts, 'Saving: %s', matPath);
    vprint(opts, '  M:     %s', mat2str(size(M)));
    vprint(opts, '  W:     %s  (processed, for display)', mat2str(size(W)));
    vprint(opts, '  W_raw: %s  (raw, for QC)', mat2str(size(W_raw)));
    vprint(opts, '  M_raw: %s  (raw mag phases)', mat2str(size(M_raw)));
    vprint(opts, '  S:     %s  (kPa)', mat2str(size(S)));
    vprint(opts, '  LapC:  %s  (0-1)', mat2str(size(LapC)));

    try
        save(matPath, 'M','M_raw','W','W_raw','S','LapC','H', '-v7.3');
    catch
        save(matPath, 'M','M_raw','W','W_raw','S','LapC','H');
    end
    vprint(opts, 'Done.');
end

function grpOut = filterMREGroupToAnchorFamily(grpIn, anchor)
%FILTERMREGROUPTOANCHORFAMILY  Keep only series in the same numeric family
% as the selected MRE anchor.
%
% Examples:
%   anchor S4      -> keep S4, S401, S40100, S40105, S40107
%   anchor S5      -> keep S5, S501...S517
%   anchor S7      -> keep S7, S701...S707
%
% This is selection-stage hygiene only. It does not change GRE behavior.

    grpOut = struct([]);
    if isempty(grpIn) || isempty(anchor) || ~isfield(anchor,'SeriesNumber')
        grpOut = grpIn;
        return
    end

    rootNum = double(anchor.SeriesNumber);
    while rootNum >= 100
        rootNum = floor(rootNum / 100);
    end
    rootStr = sprintf('%d', rootNum);

    for k = 1:numel(grpIn)
        s = grpIn(k);
        sNum = double(s.SeriesNumber);
        sRoot = sNum;
        while sRoot >= 100
            sRoot = floor(sRoot / 100);
        end
        sRootStr = sprintf('%d', sRoot);

        % same top-level family root only
        if strcmp(sRootStr, rootStr)
            if isempty(grpOut)
                grpOut = s;
            else
                grpOut(end+1) = s; %#ok<AGROW>
            end
        end
    end

    if isempty(grpOut)
        grpOut = anchor;
    else
        [~, ord] = sort([grpOut.SeriesNumber]);
        grpOut = grpOut(ord);
    end
end

function [W_raw, W, M, M_raw, S, LapC, H] = buildFromSelectionEPI(grp, opts)
%BUILDFROMSELECTIONEPI  EPI-specific 2D/3D load rules with no interpolation.

    W_raw = []; W = []; M = []; M_raw = []; S = []; LapC = []; H = [];
    sinfo = struct();

    grp = sortStructBySeriesNumber(grp);
    rootSeries = chooseEPIRootSeries(grp);
    rootNum = double(rootSeries.SeriesNumber);

    rems = cell(size(grp));
    for k = 1:numel(grp)
        rems{k} = epiRemainder(rootNum, double(grp(k).SeriesNumber));
    end

    % When all remainders are empty the chosen root is at a deeper level
    % than the actual family root (e.g. rootNum=1203 but true root=12).
    % Climb up by repeatedly flooring until we find a root that produces
    % at least one non-empty remainder.
    if all(cellfun(@isempty, rems)) && rootNum >= 100
        virtRoot = rootNum;
        while virtRoot >= 100
            virtRoot = floor(virtRoot / 100);
            testRems = cell(size(grp));
            for k = 1:numel(grp)
                testRems{k} = epiRemainder(virtRoot, double(grp(k).SeriesNumber));
            end
            if any(~cellfun(@isempty, testRems))
                rootNum = virtRoot;
                rems = testRems;
                break
            end
        end
    end

    is3D = any(strcmp(rems,'02')) && any(strcmp(rems,'03'));
    if ~is3D
        nDesc = sum(~cellfun(@isempty, rems));
        if nDesc > 10
            is3D = true;
        end
    end
    % Combined-3D: scanner writes all three MEG directions into one series
    % filed under remainder '03' (no separate '01' or '02' series).
    if ~is3D && any(strcmp(rems,'03')) && ...
            ~any(strcmp(rems,'01')) && ~any(strcmp(rems,'02'))
        if ~isempty(pickEPISeriesByRemainder(grp, rootNum, {'03'}, {'EPI_WaveMag_Raw'}))
            is3D = true;
        end
    end

    epiOpts = opts;
    epiOpts.interpolateWave = false;

    if is3D
        rawSet  = pickEPISeriesByRemainder(grp, rootNum, {'01','02','03'}, {'EPI_WaveMag_Raw'});
        procSet = pickEPISeriesByRemainder(grp, rootNum, {'04','05','06'}, {'EPI_WaveMag_Proc','EPI_ProcWave'});
        stiffSeries = pickEPISeriesByRemainder(grp, rootNum, {'08'}, {'EPI_Stiffness'});
        confSeries  = pickEPISeriesByRemainder(grp, rootNum, {'15'}, {'EPI_ConfMap'});

        [W_raw, M, M_raw, sinfo, rawHdr] = readAndPackEPIRawSet(rawSet, epiOpts);
        W = readAndPackEPIProcSet(procSet, epiOpts, size(W_raw,3));

    else
        rawSeries   = firstOrEmpty(pickEPISeriesByRemainder(grp, rootNum, {'01'}, {'EPI_WaveMag_Raw'}));
        procSeries  = firstOrEmpty(pickEPISeriesByRemainder(grp, rootNum, {'0105'}, {'EPI_WaveMag_Proc','EPI_ProcWave'}));
        stiffSeries = firstOrEmpty(pickEPISeriesByRemainder(grp, rootNum, {'0100'}, {'EPI_Stiffness'}));
        confSeries  = firstOrEmpty(pickEPISeriesByRemainder(grp, rootNum, {'0107'}, {'EPI_ConfMap'}));

        if isempty(rawSeries)
            error('mre_buildMATFile:noEPI2DRaw', 'No EPI 2D raw wave/mag series (..01) found.');
        end

        vprint(epiOpts, 'Reading EPI 2D raw wave+mag: S%d  %s', rawSeries.SeriesNumber, rawSeries.SeriesDescription);
        [W_raw, M, sinfo, ~, M_raw] = mre_readWaveMagSeries(rawSeries, epiOpts);
        rawHdr = rawSeries.Header;

        if ~isempty(procSeries)
            procOpts = epiOpts;
            procOpts.forceProcessedWave = true;
            vprint(procOpts, 'Reading EPI 2D processed wave: S%d  %s', procSeries.SeriesNumber, procSeries.SeriesDescription);
            [W, ~, ~, ~] = mre_readWaveMagSeries(procSeries, procOpts);
        else
            W = [];
        end
    end

    if isempty(W)
        W = W_raw;
    end

    nZ = max(1, size(W_raw,3));
    if ~isempty(stiffSeries)
        stiffSeries = firstOrEmpty(stiffSeries);
        vprint(epiOpts, 'Reading EPI stiffness: S%d', stiffSeries.SeriesNumber);
        S_raw = readGrayscaleVolume(stiffSeries.Files, size(W_raw,1), size(W_raw,2), nZ);
        S = double(S_raw) / 1000.0;
    end

    if ~isempty(confSeries)
        confSeries = firstOrEmpty(confSeries);
        vprint(epiOpts, 'Reading EPI confidence: S%d', confSeries.SeriesNumber);
        LapC_raw = readGrayscaleVolume(confSeries.Files, size(W_raw,1), size(W_raw,2), nZ);
        LapC = double(LapC_raw) / 1000.0;
    end

    H = buildHeaderStruct(rawHdr, sinfo);
end

function rootSeries = chooseEPIRootSeries(grp)
    rootSeries = grp(1);
    bestLen = inf;
    for k = 1:numel(grp)
        if strcmp(grp(k).Role, 'EPI_RawIQ')
            sn = sprintf('%d', double(grp(k).SeriesNumber));
            if numel(sn) < bestLen
                bestLen = numel(sn);
                rootSeries = grp(k);
            end
        end
    end
end

function rem = epiRemainder(rootNum, seriesNum)
    rs = sprintf('%d', floor(double(rootNum)));
    ss = sprintf('%d', floor(double(seriesNum)));
    if startsWith(ss, rs)
        rem = ss(numel(rs)+1:end);
    else
        rem = '';
    end
end

function out = pickEPISeriesByRemainder(grp, rootNum, wantedRemainders, wantedRoles)
    out = struct([]);
    for k = 1:numel(grp)
        g = grp(k);
        rem = epiRemainder(rootNum, double(g.SeriesNumber));
        if isempty(rem)
            continue
        end
        if ~any(strcmp(rem, wantedRemainders))
            continue
        end
        if ~isempty(wantedRoles) && ~any(strcmp(g.Role, wantedRoles))
            continue
        end
        if isempty(out)
            out = g;
        else
            out(end+1) = g; %#ok<AGROW>
        end
    end
    if ~isempty(out)
        [~, ord] = sort([out.SeriesNumber]);
        out = out(ord);
    end
end

function [W_raw, M, M_raw, sinfo, rawHdr] = readAndPackEPIRawSet(rawSet, opts)
    if isempty(rawSet)
        error('mre_buildMATFile:noEPI3DRaw', 'No EPI 3D raw directional series (..01/..02/..03) found.');
    end

    Wcells = {};
    Mcells = {};
    MrawCells = {};
    sinfo = struct();
    rawHdr = rawSet(1).Header;

    for k = 1:numel(rawSet)
        [Wk, Mk, sinfoK, ~, MrawK] = mre_readWaveMagSeries(rawSet(k), opts);
        if isempty(Wk)
            continue
        end
        if isempty(sinfo) || ~isfield(sinfo,'VoxelSize')
            sinfo = sinfoK;
            rawHdr = rawSet(k).Header;
        end
        Wcells{end+1} = Wk; %#ok<AGROW>
        if ~isempty(Mk)
            Mcells{end+1} = Mk; %#ok<AGROW>
        end
        if ~isempty(MrawK)
            MrawCells{end+1} = MrawK; %#ok<AGROW>
        end
    end

    if isempty(Wcells)
        error('mre_buildMATFile:noReadableEPI3DRaw', 'Could not read any EPI 3D raw directional series.');
    end

    W_raw = Wcells{1};
    for k = 2:numel(Wcells)
        W_raw = cat(4, W_raw, Wcells{k});
    end

    if ~isempty(Mcells)
        M = Mcells{1};
        for k = 2:numel(Mcells)
            M = M + Mcells{k};
        end
        M = M ./ numel(Mcells);
    else
        M = mean(abs(W_raw), 4);
    end

    if ~isempty(MrawCells)
        M_raw = MrawCells{1};
        for k = 2:numel(MrawCells)
            M_raw = cat(4, M_raw, MrawCells{k});
        end
    else
        M_raw = repmat(M, [1 1 1 max(1, size(W_raw,4))]);
    end
end

function W = readAndPackEPIProcSet(procSet, opts, rawSlices)
    W = [];
    if isempty(procSet)
        return
    end

    Wcells = {};
    procOpts = opts;
    procOpts.forceProcessedWave = true;

    for k = 1:numel(procSet)
        [Wk, ~, ~, ~] = mre_readWaveMagSeries(procSet(k), procOpts);
        if isempty(Wk)
            continue
        end
        if rawSlices > 0 && size(Wk,3) ~= rawSlices
            continue
        end
        Wcells{end+1} = Wk; %#ok<AGROW>
    end

    if isempty(Wcells)
        return
    end

    W = Wcells{1};
    for k = 2:numel(Wcells)
        W = cat(4, W, Wcells{k});
    end
end

function s = firstOrEmpty(s)
    if ~isempty(s) && numel(s) > 1
        s = s(1);
    end
end

function grp = sortStructBySeriesNumber(grp)
    if isempty(grp), return; end
    [~, ord] = sort([grp.SeriesNumber]);
    grp = grp(ord);
end

function W = normalizeWaveDims(W, expSlices, name)
    if nargin < 3, name = 'W'; end
    if isempty(W) || ndims(W) ~= 4 || isempty(expSlices) || expSlices < 1
        return
    end
    sz = size(W);
    if sz(3) ~= expSlices && sz(4) == expSlices
        W = permute(W, [1 2 4 3]);
        fprintf('normalizeWaveDims: swapped dims 3/4 for %s -> %s\n', name, mat2str(size(W)));
    end
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

function grp = findSameMREGroup(seriesList, anchor)
    if isempty(anchor)
        grp = seriesList;
        return
    end
    grp = struct([]);
    baseNum = floor(anchor.SeriesNumber / 100) * 100;
    for k = 1:numel(seriesList)
        s = seriesList(k);
        sBase = floor(s.SeriesNumber / 100) * 100;
        if sBase == baseNum
            if isempty(grp)
                grp = s;
            else
                grp(end+1) = s; %#ok<AGROW>
            end
        end
    end
    if isempty(grp)
        grp = anchor;
    end
end

function s = findBestProcSeries(grp, rawSeries, rawSlices)
%FINDBESTPROCSERIES  Prefer the true processed-wave series (e.g. XX07/S705)
%over interpolated raw. Uses DICOM-derived counts and avoids stiffness/conf maps.
    s = [];
    bestScore = -inf;
    for k = 1:numel(grp)
        g = grp(k);
        if ~isempty(rawSeries) && g.SeriesNumber == rawSeries.SeriesNumber
            continue
        end
        [ok, score] = scoreProcCandidate(g, rawSlices);
        if ok && score > bestScore
            s = g;
            bestScore = score;
        end
    end
end

function [ok, score] = scoreProcCandidate(g, rawSlices)
%SCOREPROCCANDIDATE  Pick the true processed-wave series (for example S705)
%and exclude the raw GRE anchor, stiffness, and confidence maps.
    ok = false;
    score = -inf;
    try
        desc  = lower(g.SeriesDescription);
        role  = lower(g.Role);
        itype = lower(g.ImageType);
        nImg  = double(g.nImages);
        hdr   = g.Header;
        wc = 0; ww = 0;
        if isfield(hdr,'WindowCenter') && ~isempty(hdr.WindowCenter), wc = double(hdr.WindowCenter(1)); end
        if isfield(hdr,'WindowWidth')  && ~isempty(hdr.WindowWidth),  ww = double(hdr.WindowWidth(1));  end

        % Reject obvious non-wave derived maps.
        hasConfDesc  = contains(desc, 'conf') || contains(desc, 'confidence') || contains(desc, 'lap');
        hasStiffDesc = contains(desc, 'stiff') || contains(desc, 'elasto') || contains(desc, 'kpa');
        confLikeHdr  = (ww > 0 && ww < 500) && (wc > 500);
        stiffLikeHdr = (wc >= 1000 && wc <= 15000) && (nImg <= max(rawSlices, 8));
        if hasConfDesc || hasStiffDesc || confLikeHdr || stiffLikeHdr
            return
        end

        % Prefer DERIVED multi-frame wave series in the same block.
        isOrig = contains(itype, 'original');
        isDer  = contains(itype, 'derived');
        if isOrig && ~contains(role, 'proc')
            return
        end
        if nImg < 2 * max(rawSlices,1)
            return
        end

        % Expected processed-wave phase count from same slice count.
        if rawSlices > 0
            if mod(nImg, rawSlices) ~= 0
                return
            end
            nPh = nImg / rawSlices;
        else
            nPh = max(1, double(g.nPhases));
        end
        if nPh < 2
            return
        end

        score = 0;
        if isDer, score = score + 120; end
        if contains(role, 'proc'), score = score + 80; end
        if contains(desc, 'proc') || contains(desc, 'wave') || contains(desc, 'unwrap') || contains(desc, 'curl')
            score = score + 30;
        end
        if rawSlices > 0 && (nImg / max(nPh,1)) == rawSlices
            score = score + 20;
        end
        if nPh >= 8
            score = score + 20;
        end
        snMod = mod(double(g.SeriesNumber), 100);
        if snMod == 5 || snMod == 7
            score = score + 10;
        end
        ok = true;
    catch
        ok = false;
        score = -inf;
    end
end

function exam = mre_parseDICOMExam(examRootDir, opts)
% MRE_PARSEDICOMEXAM  Identify and classify all GE MRE series in an exam folder.
%
%   EXAM = MRE_PARSEDICOMEXAM(EXAMROOTDIR) recursively scans EXAMROOTDIR,
%   reads one DICOM header per subfolder, and classifies each subfolder into
%   one of the following roles based on GE-specific private tags and series
%   number patterns:
%
%     Role string        Description
%     ─────────────────  ──────────────────────────────────────────────────
%     'Localizer'        3-plane SSFSE scout (SeriesNum~1, seq='ssfse')
%     'IDEALIQ_Raw'      IDEAL-IQ raw water series (seq='ideal3darc', nImg small)
%     'IDEALIQ_Multi'    IDEAL-IQ multi-contrast stack (6 contrasts × nSlices)
%     'IDEALIQ_PDFF'     Fat fraction map from IDEAL-IQ ('FatFrac' in desc)
%     'IDEALIQ_T2s'      T2* map from IDEAL-IQ ('T2*' in desc)
%     'EPI_RawIQ'        EPI-MRE raw I/Q data (seq='epimre', ImageType=ORIGINAL)
%     'EPI_WaveMag'      EPI-MRE phase contrast + magnitude (seq='epimre', DERIVED)
%     'EPI_Stiffness'    EPI-MRE grayscale stiffness in Pa (16-bit, seq='epimre')
%     'EPI_ConfMap'      EPI-MRE confidence map 0-999 (16-bit, small series)
%     'EPI_ProcWave'     EPI-MRE processed/filtered wave (16-bit, small series)
%     'GRE_WaveMag'      GRE-MRE phase contrast + magnitude (seq='fgremre', ORIGINAL)
%     'GRE_Stiffness'    GRE-MRE grayscale stiffness in Pa (16-bit, DERIVED)
%     'GRE_ConfMap'      GRE-MRE confidence map 0-999 (16-bit, small series)
%     'GRE_ProcWave'     GRE-MRE processed wave images (16-bit, DERIVED)
%     'RGB_Visualization' Any 8-bit RGB SCREEN SAVE — skip for analysis
%     'Unknown'          Not classified
%
%   EXAM struct fields:
%     .ExamRootDir      char     root folder scanned
%     .PatientID        char
%     .StudyDate        char
%     .ScannerModel     char
%     .MREType          char     'EPI' | 'GRE' | 'both' | 'none'
%     .Series           struct array with fields:
%         .Folder       char     full path
%         .Role         char     (from table above)
%         .SeriesNumber double
%         .SeriesDescription char
%         .nImages      double   actual count in this folder
%         .nPhases      double   NumberOfTemporalPositions
%         .BitDepth     double   8 or 16
%         .IsGrayscale  logical
%         .SeqName      char     Private_0019_109c (GE internal sequence name)
%         .ImageType    char
%         .Header       struct   full DICOM header of first file
%         .Files        cell     sorted list of all DICOM files
%
%   USAGE
%     exam = mre_parseDICOMExam('/data/Subject01/DICOM/MRE');
%     exam = mre_parseDICOMExam(dir, struct('verbose', true));
%
%   SEE ALSO  mre_buildMATFile, mre_readWaveMagSeries, loc_loadLocalizer
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3
%   DATE    2026-04

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    vprint(opts, '=== mre_parseDICOMExam ===');
    vprint(opts, 'Root: %s', examRootDir);

    % ------------------------------------------------------------------
    % 1.  Find all subfolders containing DICOM files
    % ------------------------------------------------------------------
    subfolders = findDICOMFolders(examRootDir);
    vprint(opts, 'Found %d subfolders with DICOM files.', numel(subfolders));

    % ------------------------------------------------------------------
    % 2.  Read first DICOM header from each subfolder
    % ------------------------------------------------------------------
    exam = initExamStruct(examRootDir);
    seriesList = struct([]);

    for k = 1:numel(subfolders)
        folder = subfolders{k};
        files  = getDICOMFilesInFolder(folder);
        if isempty(files), continue; end

        try
            hdr = dicominfo(files{1}, 'UseDictionaryVR', true);
        catch
            continue
        end

        % Populate exam-level metadata on first valid series
        if isempty(exam.PatientID)
            exam.PatientID    = safeTag(hdr, 'PatientID');
            exam.StudyDate    = safeTag(hdr, 'StudyDate');
            exam.ScannerModel = safeTag(hdr, 'ManufacturerModelName');
        end

        entry = buildSeriesEntry(folder, files, hdr);
        entry = classifySeries(entry);

        if isempty(seriesList)
            seriesList = entry;
        else
            seriesList(end+1) = entry; %#ok<AGROW>
        end

        vprint(opts, '  S%06d  %-28s → %s', ...
            entry.SeriesNumber, entry.SeriesDescription, entry.Role);
    end

    % Sort by SeriesNumber
    if ~isempty(seriesList)
        [~, idx] = sort([seriesList.SeriesNumber]);
        seriesList = seriesList(idx);
    end

    exam.Series = seriesList;
    exam.MREType = determineMREType(seriesList);
    vprint(opts, 'MRE type detected: %s', exam.MREType);
end


% ======================================================================
%  CLASSIFICATION LOGIC
% ======================================================================

function entry = classifySeries(entry)
%CLASSIFYSERIES  Assign a Role to the series entry.

    sn    = entry.SeriesNumber;
    seq   = lower(entry.SeqName);           % Private_0019_109c
    itype = lower(entry.ImageType);
    desc  = lower(entry.SeriesDescription);
    gray  = entry.IsGrayscale;
    bits  = entry.BitDepth;
    nImg  = entry.nImages;

    % ── RGB visualizations — always skip for analysis ─────────────────
    if ~gray
        entry.Role = 'RGB_Visualization';
        return
    end

    % ── Localizer ─────────────────────────────────────────────────────
    if contains(seq, 'ssfse') || contains(desc, 'localizer') || ...
       contains(desc, '3-plane') || (sn <= 3 && nImg <= 30)
        entry.Role = 'Localizer';
        return
    end

    % ── IDEAL-IQ ──────────────────────────────────────────────────────
    if contains(seq, 'ideal') || contains(desc, 'ideal')
        if contains(desc, 'fatfrac') || contains(desc, 'fat%') || ...
           contains(desc, 'fat frac') || contains(desc, 'pdff')
            entry.Role = 'IDEALIQ_PDFF';
        elseif contains(desc, 't2*') || contains(desc, 't2star')
            entry.Role = 'IDEALIQ_T2s';
        elseif contains(desc, 'water:') || ...
               (contains(desc, 'water') && nImg < 50)
            entry.Role = 'IDEALIQ_Raw';
        else
            entry.Role = 'IDEALIQ_Multi';  % multi-contrast stack
        end
        return
    end

    % ── EPI-MRE ───────────────────────────────────────────────────────
    if contains(seq, 'epimre') || contains(seq, 'epi')

        if contains(itype, 'original') && contains(itype, 'primary')
            entry.Role = 'EPI_RawIQ';   % raw I/Q — skip
            return
        end

        if contains(itype, 'derived') && bits == 16
            % Primary classifier: last 2 digits of SeriesNumber encode type
            %   mod=1 → Stiffness (x001)
            %   mod=5 → Processed wave (x005, post-processed 8-phase, no magnitude)
            %   mod=7 → Confidence map (x007)
            %   other → fall through to heuristics
            snMod = mod(sn, 100);
            if snMod == 1
                entry.Role = 'EPI_Stiffness';
            elseif snMod == 5
                entry.Role = 'EPI_ProcWave';
            elseif snMod == 7
                entry.Role = 'EPI_ConfMap';
            elseif isWaveMagSeries(entry)
                entry.Role = 'EPI_WaveMag';
            elseif isStiffnessSeries(entry)
                entry.Role = 'EPI_Stiffness';
            elseif isConfidenceSeries(entry)
                entry.Role = 'EPI_ConfMap';
            else
                entry.Role = 'EPI_ProcWave';
            end
            return
        end

        entry.Role = 'Unknown';
        return
    end

    % ── GRE-MRE ───────────────────────────────────────────────────────
    if contains(seq, 'fgremre') || contains(seq, 'gremre') || ...
       contains(desc, 'gre mre') || contains(desc, '2d gre mre')

        % Series-number suffix is the PRIMARY classifier — GE sometimes
        % stores processed-wave (S705) with ImageType=ORIGINAL, so we
        % must check snMod BEFORE the ImageType branch.
        snMod = mod(sn, 100);

        if snMod == 5 && bits == 16
            % Processed wave: 8-phase post-processed, no magnitude.
            % GE marks this as ORIGINAL despite being derived — override.
            entry.Role = 'GRE_ProcWave';
            return
        end

        if contains(itype, 'original')
            % Raw wave + magnitude (S700/S7 ORIGINAL)
            entry.Role = 'GRE_WaveMag';
            return
        end

        if bits == 16
            if snMod == 1
                entry.Role = 'GRE_Stiffness';
            elseif snMod == 7
                % S707: processed wave (8-phase) on some GE versions,
                % or confidence map on others. Discriminate by nPhases.
                if entry.nPhases > 1
                    entry.Role = 'GRE_ProcWave';
                else
                    entry.Role = 'GRE_ConfMap';
                end
            elseif isStiffnessSeries(entry)
                entry.Role = 'GRE_Stiffness';
            elseif isConfidenceSeries(entry)
                entry.Role = 'GRE_ConfMap';
            elseif isWaveMagSeries(entry)
                entry.Role = 'GRE_ProcWave';
            else
                entry.Role = 'GRE_Stiffness';  % most common remaining derived
            end
            return
        end

        entry.Role = 'Unknown';
        return
    end

    entry.Role = 'Unknown';
end

% ── Sub-classifiers for derived grayscale MRE series ─────────────────

function tf = isWaveMagSeries(e)
% Wave+Mag: large nImages = nSlices × nPhases × 2
% Characteristic: nImages divisible by (nPhases × 2) and large
    tf = (e.nImages >= 20) && (e.nPhases > 1) && ...
         mod(e.nImages, e.nPhases * 2) == 0;
end

function tf = isStiffnessSeries(e)
% Stiffness: small nImages = nSlices (no temporal cycling)
% WindowCenter near 4000-8000 (stiffness display range)
    hdr = e.Header;
    wc = 0;
    if isfield(hdr, 'WindowCenter') && ~isempty(hdr.WindowCenter)
        wc = double(hdr.WindowCenter(1));
    end
    % GRE 700: WindowCenter=4000, nImg=nSlices (small, no phase dim)
    tf = (e.nImages <= 20) && (wc >= 1000) && (wc <= 15000) && ...
         ~isConfidenceSeries(e);
end

function tf = isConfidenceSeries(e)
% Confidence: small nImages, pixel values 0-999
% WindowCenter ≈ 950, WindowWidth ≈ 100
    hdr = e.Header;
    wc = 0; ww = 1000;
    if isfield(hdr, 'WindowCenter') && ~isempty(hdr.WindowCenter)
        wc = double(hdr.WindowCenter(1));
    end
    if isfield(hdr, 'WindowWidth') && ~isempty(hdr.WindowWidth)
        ww = double(hdr.WindowWidth(1));
    end
    % Confidence: WindowCenter~950, WindowWidth~100
    tf = (wc > 500) && (ww < 500);
end


% ======================================================================
%  HELPER — BUILD SERIES ENTRY
% ======================================================================

function entry = buildSeriesEntry(folder, files, hdr)
    entry.Folder           = folder;
    entry.SeriesNumber     = safeTagNum(hdr, 'SeriesNumber');
    entry.SeriesDescription= safeTag(hdr,    'SeriesDescription');
    entry.ImageType        = safeTag(hdr,    'ImageType');
    entry.nImages          = numel(files);
    entry.nPhases          = safeTagNum(hdr, 'NumberOfTemporalPositions');
    if isnan(entry.nPhases), entry.nPhases = 1; end
    entry.BitDepth         = safeTagNum(hdr, 'BitsAllocated');
    if isnan(entry.BitDepth), entry.BitDepth = 16; end
    entry.IsGrayscale      = safeTagNum(hdr, 'SamplesPerPixel') == 1;
    if isnan(entry.IsGrayscale)
        entry.IsGrayscale = ~contains(lower(safeTag(hdr,'PhotometricInterpretation')),'rgb');
    end
    entry.SeqName          = safeGEPrivateTag(hdr, 'Private_0019_109c');
    entry.SequenceType     = safeGEPrivateTag(hdr, 'Private_0019_109e');
    entry.Header           = hdr;
    entry.Files            = files;
    entry.Role             = 'Unknown';
end


% ======================================================================
%  HELPER — FIND DICOM FOLDERS / FILES
% ======================================================================

function subfolders = findDICOMFolders(rootDir)
% Return list of subfolders (incl. root) that contain at least one DICOM.
    allDirs = [struct('folder', rootDir, 'name', '.', 'isdir', true); ...
               dir(fullfile(rootDir, '**'))];
    allDirs = allDirs([allDirs.isdir]);
    subfolders = {};
    visited = containers.Map();
    for k = 1:numel(allDirs)
        d = allDirs(k);
        p = fullfile(d.folder, d.name);
        p = strrep(p, [filesep '.'], '');
        if isKey(visited, p), continue; end
        visited(p) = true;
        % Quick check: is there at least one DICOM here?
        flist = dir(fullfile(p, 'I*'));
        if isempty(flist)
            flist = dir(fullfile(p, '*.dcm'));
        end
        if isempty(flist)
            flist = dir(p);
            flist = flist(~[flist.isdir]);
        end
        if ~isempty(flist)
            subfolders{end+1} = p; %#ok<AGROW>
        end
    end
end

function files = getDICOMFilesInFolder(folder)
% Return sorted DICOM file paths in this folder (not recursive).
    flist = dir(folder);
    flist = flist(~[flist.isdir]);
    files = {};
    for k = 1:numel(flist)
        fp = fullfile(folder, flist(k).name);
        try
            fid = fopen(fp, 'r');
            if fid < 0, continue; end
            fseek(fid, 128, 'bof');
            magic = fread(fid, 4, '*char')';
            fclose(fid);
            if strcmp(magic, 'DICM') || isdicom(fp)
                files{end+1} = fp; %#ok<AGROW>
            end
        catch
        end
    end
    % Sort by filename (preserves instance ordering)
    [~, idx] = sort(cellfun(@(f) {f}, files));
    files = files(idx);
end


% ======================================================================
%  HELPERS
% ======================================================================

function mreType = determineMREType(seriesList)
    roles = {seriesList.Role};
    hasEPI = any(contains(roles, 'EPI_'));
    hasGRE = any(contains(roles, 'GRE_'));
    if hasEPI && hasGRE,     mreType = 'both';
    elseif hasEPI,           mreType = 'EPI';
    elseif hasGRE,           mreType = 'GRE';
    else,                    mreType = 'none';
    end
end

function exam = initExamStruct(dir_)
    exam.ExamRootDir  = dir_;
    exam.PatientID    = '';
    exam.StudyDate    = '';
    exam.ScannerModel = '';
    exam.MREType      = 'none';
    exam.Series       = struct([]);
end

function v = safeTag(hdr, field)
    if isfield(hdr, field) && ~isempty(hdr.(field))
        v = char(hdr.(field));
    else
        v = '';
    end
end

function v = safeTagNum(hdr, field)
    if isfield(hdr, field) && ~isempty(hdr.(field))
        v = double(hdr.(field)(1));
    else
        v = NaN;
    end
end

function v = safeGEPrivateTag(hdr, field)
% GE private tags may be char or numeric.
    if isfield(hdr, field) && ~isempty(hdr.(field))
        raw = hdr.(field);
        if ischar(raw) || isstring(raw)
            v = char(raw);
        else
            v = '';
        end
    else
        v = '';
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
        fprintf(['[mre_parseDICOMExam] ' fmt '\n'], varargin{:});
    end
end

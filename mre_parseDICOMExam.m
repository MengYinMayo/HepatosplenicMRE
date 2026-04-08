function exam = mre_parseDICOMExam(examRootDir, opts)
% MRE_PARSEDICOMEXAM  Identify and classify all GE MRE series in an exam folder.
%
%   NETWORK-OPTIMISED version:
%     - Zero file I/O during folder discovery (filename patterns only)
%     - One dicominfo() call per series folder (not per file)
%     - Max recursion depth capped at 4 levels
%     - Progress dots printed during scan
%
%   EXAM = MRE_PARSEDICOMEXAM(EXAMROOTDIR) scans all subfolders and
%   classifies each series using a 3-tier evidence system:
%     Tier 1 (definitive): GE private tag Private_0019_109c
%     Tier 2 (strong):     SeriesDescription keywords
%     Tier 3 (supporting): Folder name + ScanOptions
%
%   Roles assigned:
%     'Localizer'          3-plane SSFSE scout
%     'IDEALIQ_Raw'        IDEAL-IQ raw water
%     'IDEALIQ_Multi'      IDEAL-IQ multi-contrast stack
%     'IDEALIQ_PDFF'       Fat fraction map
%     'IDEALIQ_T2s'        T2* map
%     'EPI_RawIQ'          EPI-MRE raw I/Q (skip)
%     'EPI_WaveMag'        EPI-MRE wave + magnitude
%     'EPI_Stiffness'      EPI-MRE stiffness in Pa
%     'EPI_ConfMap'        EPI-MRE confidence map
%     'EPI_ProcWave'       EPI-MRE processed wave
%     'GRE_WaveMag'        GRE-MRE wave + magnitude
%     'GRE_Stiffness'      GRE-MRE stiffness in Pa
%     'GRE_ConfMap'        GRE-MRE confidence map
%     'GRE_ProcWave'       GRE-MRE processed wave
%     'RGB_Visualization'  8-bit RGB screen save (skip)
%     'Unknown'            Not classified
%
%   USAGE
%     exam = mre_parseDICOMExam('\\server\share\PatientExam');
%     exam = mre_parseDICOMExam(path, struct('verbose', true, 'maxDepth', 3));
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3  (network-optimised)

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'verbose',  true, ...
        'maxDepth', 4));

    vprint(opts, '=== mre_parseDICOMExam ===');
    vprint(opts, 'Root: %s', examRootDir);

    % 1. Find all series folders (fast — filename patterns, no file I/O)
    vprint(opts, 'Scanning for DICOM series folders...');
    subfolders = findDICOMFolders(examRootDir, opts.maxDepth);
    vprint(opts, 'Found %d series folders.', numel(subfolders));

    if isempty(subfolders)
        warning('mre_parseDICOMExam:noFolders', ...
            'No DICOM folders found under:\n  %s', examRootDir);
        exam = initExamStruct(examRootDir);
        return
    end

    % 2. Read ONE header per folder, classify
    exam = initExamStruct(examRootDir);
    seriesList = struct([]);

    for k = 1:numel(subfolders)
        folder = subfolders{k};
        files  = listDICOMFiles(folder);        % fast — no file I/O
        if isempty(files), continue; end

        try
            hdr = dicominfo(files{1}, 'UseDictionaryVR', true);
        catch
            continue   % not a valid DICOM — skip
        end

        % Exam-level metadata from first valid series
        if isempty(exam.PatientID)
            exam.PatientID    = safeStr(hdr, 'PatientID');
            exam.StudyDate    = safeStr(hdr, 'StudyDate');
            exam.ScannerModel = safeStr(hdr, 'ManufacturerModelName');
        end

        entry = buildEntry(folder, files, hdr);
        entry = classifySeries(entry);

        if isempty(seriesList)
            seriesList = entry;
        else
            seriesList(end+1) = entry; %#ok<AGROW>
        end

        vprint(opts, '  S%-8d  %-35s -> %s', ...
            entry.SeriesNumber, entry.SeriesDescription, entry.Role);
    end

    % 3. Sort by SeriesNumber
    if ~isempty(seriesList)
        [~, idx] = sort([seriesList.SeriesNumber]);
        seriesList = seriesList(idx);
    end

    exam.Series  = seriesList;
    exam.MREType = detectMREType(seriesList);

    vprint(opts, '--- Summary ---');
    vprint(opts, 'MRE type : %s', exam.MREType);
    vprint(opts, 'Patient  : %s  Date: %s', exam.PatientID, exam.StudyDate);
    vprint(opts, 'Series   : %d total', numel(exam.Series));
    if ~isempty(seriesList)
        roles = {seriesList.Role};
        uniq  = unique(roles);
        for r = 1:numel(uniq)
            vprint(opts, '           %-25s x%d', uniq{r}, sum(strcmp(roles,uniq{r})));
        end
    end
end


%% ====================================================================
%  FOLDER DISCOVERY  (zero file I/O — filename patterns only)
%% ====================================================================

function subfolders = findDICOMFolders(rootDir, maxDepth)
    subfolders = {};
    if nargin < 2, maxDepth = 4; end

    % GE DICOM file patterns (no regex — plain dir wildcards)
    PATTERNS = {'I*', '*.dcm', '*.IMA', 'IM*'};

    % Folders whose names suggest non-DICOM content — skip immediately
    SKIP_NAMES = {'thumbnails','db','.system','backup','archive', ...
                  'report','pdf','doc','log','tmp','temp','cache'};

    function sf = scan(dir_, depth)
        sf = {};
        if depth > maxDepth, return; end

        % Check if this folder itself has DICOM-like files (pattern match, no open)
        hasDcm = false;
        for p = 1:numel(PATTERNS)
            try
                d = dir(fullfile(dir_, PATTERNS{p}));
                d = d(~[d.isdir]);
                if ~isempty(d), hasDcm = true; break; end
            catch
            end
        end
        if hasDcm
            sf{end+1} = dir_;
        end

        % Recurse into subdirectories
        try
            children = dir(dir_);
        catch
            return   % network timeout or permission — skip
        end
        children = children([children.isdir]);
        children = children(~ismember({children.name},{'.','..'}));

        for k = 1:numel(children)
            cname = lower(children(k).name);
            if any(cellfun(@(s) strncmp(cname,s,numel(s)), SKIP_NAMES))
                continue   % skip non-DICOM folder
            end
            child = fullfile(dir_, children(k).name);
            sub   = scan(child, depth+1);
            sf    = [sf, sub]; %#ok<AGROW>
        end
    end

    subfolders = scan(rootDir, 0);
end


function files = listDICOMFiles(folder)
% List all DICOM files in folder using GE filename patterns. No file I/O.
% Numeric sort on the instance number embedded in filename.
    PATTERNS = {'I*', '*.dcm', '*.IMA', 'IM*'};
    all = [];
    for p = 1:numel(PATTERNS)
        try
            d = dir(fullfile(folder, PATTERNS{p}));
            d = d(~[d.isdir]);
            all = [all; d]; %#ok<AGROW>
        catch
        end
    end

    if isempty(all)
        % Last resort: any file in folder
        all = dir(folder);
        all = all(~[all.isdir]);
    end

    if isempty(all)
        files = {}; return
    end

    % Remove duplicates (a file might match multiple patterns)
    [~, ia] = unique({all.name});
    all = all(ia);

    % Natural-numeric sort: extract digits from filename stem
    nums = zeros(1, numel(all));
    for k = 1:numel(all)
        tok = regexp(all(k).name, '\d+', 'match', 'once');
        if ~isempty(tok), nums(k) = str2double(tok); end
    end
    [~, idx] = sort(nums);
    all = all(idx);

    files = cellfun(@(nm) fullfile(folder, nm), {all.name}, ...
                    'UniformOutput', false);
end


%% ====================================================================
%  SERIES ENTRY BUILDER
%% ====================================================================

function entry = buildEntry(folder, files, hdr)
    entry.Folder            = folder;
    entry.FolderName        = lower(leafName(folder));
    entry.SeriesNumber      = safeNum(hdr, 'SeriesNumber');
    entry.SeriesDescription = safeStr(hdr, 'SeriesDescription');
    entry.ImageType         = safeStr(hdr, 'ImageType');
    entry.nImages           = numel(files);
    entry.nPhases           = safeNum(hdr, 'NumberOfTemporalPositions');
    if isnan(entry.nPhases), entry.nPhases = 1; end
    entry.BitDepth          = safeNum(hdr, 'BitsAllocated');
    if isnan(entry.BitDepth), entry.BitDepth = 16; end
    spp = safeNum(hdr, 'SamplesPerPixel');
    entry.IsGrayscale       = ~isnan(spp) && spp == 1;
    if isnan(spp)
        entry.IsGrayscale   = ~contains(lower(safeStr(hdr,'PhotometricInterpretation')),'rgb');
    end
    entry.SeqName           = safePrivateTag(hdr, 'Private_0019_109c');
    entry.SeqType           = safePrivateTag(hdr, 'Private_0019_109e');
    entry.ScanOptions       = safeStr(hdr, 'ScanOptions');
    entry.ScanningSequence  = safeStr(hdr, 'ScanningSequence');
    entry.Header            = hdr;
    entry.Files             = files;
    entry.Role              = 'Unknown';
end

function n = leafName(folder)
    [~, n] = fileparts(folder);
    if isempty(n), [~, n] = fileparts(fileparts(folder)); end
end


%% ====================================================================
%  CLASSIFICATION  (3-tier: GE private tag / description / folder name)
%% ====================================================================

function entry = classifySeries(entry)
    seq     = lower(entry.SeqName);
    itype   = lower(entry.ImageType);
    desc    = lower(entry.SeriesDescription);
    fnam    = lower(entry.FolderName);
    gray    = entry.IsGrayscale;
    bits    = entry.BitDepth;
    nImg    = entry.nImages; %#ok<NASGU>
    scanopt = lower(entry.ScanOptions);

    % RGB — skip
    if ~gray
        entry.Role = 'RGB_Visualization'; return
    end

    % ── Localizer ─────────────────────────────────────────────────────
    if hit(seq,  {'ssfse','ssfp','fiesta'}) || ...
       hit(desc, {'localizer','localiser','3-plane','3plane','scout', ...
                  'survey','aahscout','loc_'}) || ...
       hit(fnam, {'loc','scout','survey','3plane','localiz'})
        entry.Role = 'Localizer'; return
    end

    % ── IDEAL-IQ ─────────────────────────────────────────────────────
    if hit(seq,  {'ideal3darc','ideal3d','idealarc','ideal'}) || ...
       hit(desc, {'ideal','idealiq','ideal-iq','fat frac','fatfrac', ...
                  'pdff','water:','t2*:'}) || ...
       hit(fnam, {'ideal','idealiq','dixon','pdff'})
        if hit(desc,{'fatfrac','fat frac','fat%','pdff','fatpct'}) || ...
           hit(fnam,{'pdff','fatfrac'})
            entry.Role = 'IDEALIQ_PDFF';
        elseif hit(desc,{'t2*','t2star','t2_star'})
            entry.Role = 'IDEALIQ_T2s';
        elseif contains(desc,'water') && entry.nImages < 50
            entry.Role = 'IDEALIQ_Raw';
        else
            entry.Role = 'IDEALIQ_Multi';
        end
        return
    end

    % ── EPI-MRE ──────────────────────────────────────────────────────
    isEPI = hit(seq,  {'epimre','epi_mre'}) || ...
            (hit(desc,{'mre','elastograph'}) && ...
             (hit(desc,{'epi mre','epi-mre','epimre'}) || ...
              contains(scanopt,'epi_gems'))) || ...
            hit(fnam, {'epimre','epi_mre'}) || ...
            (hit(fnam,{'mre'}) && hit(fnam,{'epi'}));

    if isEPI
        if contains(itype,'original') && contains(itype,'primary')
            entry.Role = 'EPI_RawIQ';
        elseif contains(itype,'derived') && bits == 16
            entry = mreGraySub(entry, 'EPI');
        else
            entry.Role = 'Unknown';
        end
        return
    end

    % ── GRE-MRE ──────────────────────────────────────────────────────
    isGRE = hit(seq,  {'fgremre','fgre_mre','gremre'}) || ...
            hit(desc, {'gre mre','gre-mre','2d gre mre','mre 2d','mre2d'}) || ...
            (hit(desc,{'mre','elastograph'}) && hit(seq,{'fgre','spgr','gre'})) || ...
            hit(fnam, {'gremre','fgremre','gre_mre'}) || ...
            (hit(fnam,{'mre'}) && ~hit(fnam,{'epi'}));

    if isGRE
        if contains(itype,'original')
            % ORIGINAL GRE series always = raw phase-contrast + magnitude
            entry.Role = 'GRE_WaveMag_Raw';
        elseif contains(itype,'derived') && bits == 16
            entry = mreGraySub(entry, 'GRE');
        else
            entry.Role = 'Unknown';
        end
        return
    end

    % ── Generic MRE fallback ─────────────────────────────────────────
    if hit(desc,{'mre','elastograph','wave image','stiffness'}) || ...
       hit(fnam,{'mre','elastog'})
        if contains(itype,'original')
            entry.Role = 'GRE_WaveMag';
        elseif bits == 16
            entry = mreGraySub(entry, 'GRE');
        end
    end
end

function entry = mreGraySub(entry, prefix)
% Sub-classify a 16-bit gray derived MRE series.
% For GRE: DERIVED series are always processed (raw=ORIGINAL, already handled).
% For EPI: "Phs and Mag" in description → raw wave+mag;
%          large nImages = nSlices×nPhases×2 also → raw wave+mag.
    desc = lower(entry.SeriesDescription);
    isRawWaveMag = isWaveMagRaw(entry);

    if isRawWaveMag
        entry.Role = [prefix '_WaveMag_Raw'];   % contains both wave + mag
    elseif isProcWave(entry)
        entry.Role = [prefix '_WaveMag_Proc'];  % processed wave only
    elseif isConf(entry)
        entry.Role = [prefix '_ConfMap'];
    elseif isStiff(entry)
        entry.Role = [prefix '_Stiffness'];
    else
        entry.Role = [prefix '_ProcWave'];      % other derived grayscale
    end
    %#ok<NODEF>
end

function tf = isWaveMagRaw(e)
% Raw wave+mag: large series with nImages = nSlices × nPhases × 2,
% AND description contains "phs and mag" or "phase and mag".
% (For GRE, ORIGINAL is already caught above; this handles EPI DERIVED.)
    desc = lower(e.SeriesDescription);
    hasPhasMag = contains(desc,'phs and mag') || contains(desc,'phase and mag') || ...
                 contains(desc,'phase+mag')   || contains(desc,'phs+mag');
    sizeFit    = (e.nImages >= 20) && (e.nPhases > 1) && ...
                 mod(e.nImages, e.nPhases * 2) == 0;
    tf = hasPhasMag || (sizeFit && ~isProcWave(e));
end

function tf = isProcWave(e)
% Processed wave: keyword in description indicates processed content.
    desc = lower(e.SeriesDescription);
    tf = contains(desc,'curl') || contains(desc,'divergence') || ...
         contains(desc,'unwrap') || contains(desc,'filtered') || ...
         contains(desc,'interpolat') || ...
         (contains(desc,'wave') && ~contains(desc,'mag'));
end

function tf = isStiff(e)
% Stiffness: WindowCenter in 1000-15000 Pa range, small series
    wc = getWinCenter(e.Header);
    tf = (e.nImages <= 20) && (wc >= 1000) && (wc <= 15000) && ~isConf(e);
end

function tf = isConf(e)
% Confidence: WindowCenter~950, WindowWidth narrow (~100)
    hdr = e.Header;
    wc = getWinCenter(hdr);
    ww = 1000;
    if isfield(hdr,'WindowWidth') && ~isempty(hdr.WindowWidth)
        ww = double(hdr.WindowWidth(1));
    end
    tf = (wc > 500) && (ww < 500);
end

function wc = getWinCenter(hdr)
    wc = 0;
    if isfield(hdr,'WindowCenter') && ~isempty(hdr.WindowCenter)
        wc = double(hdr.WindowCenter(1));
    end
end

function tf = hit(str, kwList)
% True if str contains any keyword in kwList (case-already-lowered).
    tf = false;
    for k = 1:numel(kwList)
        if contains(str, kwList{k}), tf = true; return; end
    end
end


%% ====================================================================
%  UTILITIES
%% ====================================================================

function mreType = detectMREType(sl)
    if isempty(sl), mreType = 'none'; return; end
    roles  = {sl.Role};
    hasEPI = any(contains(roles,'EPI_'));
    hasGRE = any(contains(roles,'GRE_'));
    if hasEPI && hasGRE,  mreType = 'both';
    elseif hasEPI,        mreType = 'EPI';
    elseif hasGRE,        mreType = 'GRE';
    else,                 mreType = 'none';
    end
end

function exam = initExamStruct(dir_)
    exam = struct('ExamRootDir',dir_,'PatientID','','StudyDate','', ...
                  'ScannerModel','','MREType','none','Series',struct([]));
end

function v = safeStr(hdr, field)
    if isfield(hdr,field) && ~isempty(hdr.(field)), v = char(hdr.(field));
    else, v = ''; end
end

function v = safeNum(hdr, field)
    if isfield(hdr,field) && ~isempty(hdr.(field)), v = double(hdr.(field)(1));
    else, v = NaN; end
end

function v = safePrivateTag(hdr, field)
    if isfield(hdr,field) && ~isempty(hdr.(field))
        raw = hdr.(field);
        if ischar(raw) || isstring(raw), v = char(raw);
        else, v = ''; end
    else, v = ''; end
end

function opts = applyDefaults(opts, defaults)
    for f = fieldnames(defaults)'
        if ~isfield(opts, f{1}), opts.(f{1}) = defaults.(f{1}); end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[mre_parseDICOMExam] ' fmt '\n'], varargin{:});
    end
end

function study = io_loadDICOMStudy(folderPath, opts)
% IO_LOADDICOMSTUDY  Load and parse a full abdominal MRE DICOM study folder.
%
%   STUDY = IO_LOADDICOMSTUDY(FOLDERPATH) recursively scans FOLDERPATH for
%   DICOM files, groups them into series, classifies each series as Scout,
%   Dixon (Water/Fat/FF/IP/OP), or MRE (Magnitude/Wave/Stiffness), reads
%   every series into a 3-D or 4-D numeric array, and returns a structured
%   STUDY object ready for harmonization (Phase 2) and segmentation (Phase 4).
%
%   STUDY = IO_LOADDICOMSTUDY(FOLDERPATH, OPTS) accepts an options struct:
%     opts.verbose        - true/false, print progress (default true)
%     opts.forceReread    - true/false, bypass any cached .mat (default false)
%     opts.seriesFilter   - cell array of SeriesDescription patterns to keep
%                           (default: all recognized series)
%     opts.dicomLib       - 'matlab' | 'dicm2nii'  (default 'matlab')
%
%   OUTPUT STRUCT fields:
%     study.FolderPath        char    source folder
%     study.PatientID         char
%     study.StudyDate         char    YYYYMMDD
%     study.StudyDescription  char
%     study.ScannerVendor     char    Siemens | GE | Philips | unknown
%     study.AllSeries         struct  array of ALL series found (raw)
%     study.Scout             struct  3-plane localizer volume + spatial info
%     study.Dixon             struct  Water/Fat/FF/InPhase/OutPhase + spatial info
%     study.MRE               struct  Magnitude/WaveImages/Stiffness + spatial info
%     study.Harmonized        struct  filled by harm_harmonizeStudy (Phase 2)
%     study.QCFlags           struct  per-series load-quality flags
%
%   USAGE
%     study = io_loadDICOMStudy('D:\data\Patient001\Session1');
%     study = io_loadDICOMStudy(path, struct('verbose', false));
%
%   REQUIRES  MATLAB Image Processing Toolbox (dicominfo, dicomread).
%
%   SEE ALSO  io_recognizeSequences, io_readDICOMSeries,
%             io_extractSpatialInfo, harm_harmonizeStudy
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2
%   DATE    2026-04

    % ------------------------------------------------------------------
    % 0.  Defaults
    % ------------------------------------------------------------------
    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    opts = applyDefaults(opts, struct( ...
        'verbose',      true,  ...
        'forceReread',  false, ...
        'seriesFilter', {{}},  ...
        'dicomLib',     'matlab'));

    vprint(opts, '=== io_loadDICOMStudy ===');
    vprint(opts, 'Folder: %s', folderPath);

    % ------------------------------------------------------------------
    % 1.  Cache check
    % ------------------------------------------------------------------
    cacheFile = fullfile(folderPath, '.mre_study_cache.mat');
    if ~opts.forceReread && isfile(cacheFile)
        vprint(opts, 'Loading from cache: %s', cacheFile);
        tmp = load(cacheFile, 'study');
        study = tmp.study;
        return
    end

    % ------------------------------------------------------------------
    % 2.  Find all DICOM files
    % ------------------------------------------------------------------
    vprint(opts, 'Scanning for DICOM files...');
    dcmFiles = findDICOMFiles(folderPath);
    if isempty(dcmFiles)
        error('io_loadDICOMStudy:noDICOM', ...
            'No DICOM files found in:\n  %s', folderPath);
    end
    vprint(opts, 'Found %d DICOM files.', numel(dcmFiles));

    % ------------------------------------------------------------------
    % 3.  Read headers and group into series
    % ------------------------------------------------------------------
    vprint(opts, 'Reading DICOM headers...');
    [seriesList, studyMeta] = groupIntoSeries(dcmFiles, opts);
    vprint(opts, 'Found %d series.', numel(seriesList));

    % ------------------------------------------------------------------
    % 4.  Classify series
    % ------------------------------------------------------------------
    vprint(opts, 'Classifying series (Scout / Dixon / MRE)...');
    seriesList = io_recognizeSequences(seriesList, opts);

    % ------------------------------------------------------------------
    % 5.  Apply series filter if requested
    % ------------------------------------------------------------------
    if ~isempty(opts.seriesFilter)
        keep = false(1, numel(seriesList));
        for k = 1:numel(seriesList)
            for f = 1:numel(opts.seriesFilter)
                if contains(seriesList(k).SeriesDescription, ...
                        opts.seriesFilter{f}, 'IgnoreCase', true)
                    keep(k) = true;
                end
            end
        end
        seriesList = seriesList(keep);
        vprint(opts, 'After filter: %d series.', numel(seriesList));
    end

    % ------------------------------------------------------------------
    % 6.  Read volumes for each recognized class
    % ------------------------------------------------------------------
    study = initStudyStruct(folderPath, studyMeta);
    study.AllSeries = seriesList;

    study = readScoutSeries(study,  seriesList, opts);
    study = readDixonSeries(study,  seriesList, opts);
    study = readMRESeries(study,    seriesList, opts);

    % ------------------------------------------------------------------
    % 7.  QC flags
    % ------------------------------------------------------------------
    study = flagLoadQuality(study);

    % ------------------------------------------------------------------
    % 8.  Cache result
    % ------------------------------------------------------------------
    try
        save(cacheFile, 'study', '-v7.3');
        vprint(opts, 'Cached to: %s', cacheFile);
    catch
        warning('io_loadDICOMStudy:cacheWrite', ...
            'Could not write cache file (read-only folder?).');
    end

    vprint(opts, 'Study loaded successfully.');
end


% ======================================================================
%  LOCAL FUNCTIONS
% ======================================================================

function dcmFiles = findDICOMFiles(rootDir)
%FINDDICOMFILES  Return full paths of all valid DICOM files under rootDir.
    allFiles = dir(fullfile(rootDir, '**', '*'));
    allFiles = allFiles(~[allFiles.isdir]);
    dcmFiles = {};
    for k = 1:numel(allFiles)
        fp = fullfile(allFiles(k).folder, allFiles(k).name);
        % Quick magic-byte check: bytes 128-131 must be "DICM"
        try
            fid = fopen(fp, 'r');
            fseek(fid, 128, 'bof');
            magic = fread(fid, 4, '*char')';
            fclose(fid);
            if strcmp(magic, 'DICM') || isdicom(fp)
                dcmFiles{end+1} = fp; %#ok<AGROW>
            end
        catch
            % not a DICOM — skip silently
        end
    end
end

% ----------------------------------------------------------------------
function [seriesList, studyMeta] = groupIntoSeries(dcmFiles, opts)
%GROUPINTOSERIES  Read headers, cluster files by SeriesInstanceUID.
    studyMeta = struct('PatientID','','StudyDate','', ...
        'StudyDescription','','ScannerVendor','unknown');

    headerMap = containers.Map();   % UID -> struct with file list + tags

    for k = 1:numel(dcmFiles)
        try
            info = dicominfo(dcmFiles{k}, 'UseDictionaryVR', true);
        catch
            continue
        end

        % Populate study-level metadata from first valid file
        if isempty(studyMeta.PatientID)
            studyMeta.PatientID       = safeTag(info, 'PatientID');
            studyMeta.StudyDate       = safeTag(info, 'StudyDate');
            studyMeta.StudyDescription= safeTag(info, 'StudyDescription');
            studyMeta.ScannerVendor   = detectVendor(info);
        end

        uid = safeTag(info, 'SeriesInstanceUID');
        if isempty(uid), uid = sprintf('unknown_%d', k); end

        if ~isKey(headerMap, uid)
            entry.Files              = {};
            entry.SeriesNumber       = safeTagNum(info, 'SeriesNumber');
            entry.SeriesDescription  = safeTag(info,    'SeriesDescription');
            entry.SeriesInstanceUID  = uid;
            entry.Modality           = safeTag(info,    'Modality');
            entry.ImageType          = safeTag(info,    'ImageType');
            entry.Rows               = safeTagNum(info, 'Rows');
            entry.Columns            = safeTagNum(info, 'Columns');
            entry.EchoTime           = safeTagNum(info, 'EchoTime');
            entry.RepetitionTime     = safeTagNum(info, 'RepetitionTime');
            entry.FlipAngle          = safeTagNum(info, 'FlipAngle');
            entry.SliceThickness     = safeTagNum(info, 'SliceThickness');
            entry.PixelSpacing       = safeTag(info,    'PixelSpacing');
            entry.MRAcquisitionType  = safeTag(info,    'MRAcquisitionType');
            entry.SequenceName       = safeTag(info,    'SequenceName');
            entry.BodyPartExamined   = safeTag(info,    'BodyPartExamined');
            entry.Class              = 'unknown';   % filled by recognizer
            entry.SubClass           = '';
            entry.SpatialInfo        = struct();
            headerMap(uid) = entry;
        end

        e = headerMap(uid);
        e.Files{end+1} = dcmFiles{k};
        headerMap(uid) = e;

        if opts.verbose && mod(k, 200) == 0
            fprintf('  Headers read: %d / %d\n', k, numel(dcmFiles));
        end
    end

    keys_   = keys(headerMap);
    seriesList = struct([]);
    for k = 1:numel(keys_)
        entry = headerMap(keys_{k});
        % Sort files by InstanceNumber / filename
        entry.Files = sortDICOMFiles(entry.Files);
        if isempty(seriesList)
            seriesList = entry;
        else
            seriesList(end+1) = entry; %#ok<AGROW>
        end
    end

    % Sort series by SeriesNumber
    if ~isempty(seriesList)
        [~, idx] = sort([seriesList.SeriesNumber]);
        seriesList = seriesList(idx);
    end
end

% ----------------------------------------------------------------------
function files = sortDICOMFiles(files)
%SORTDICOMFILES  Sort by InstanceNumber from header; fallback to filename.
    nums = zeros(1, numel(files));
    for k = 1:numel(files)
        try
            info = dicominfo(files{k});
            nums(k) = double(info.InstanceNumber);
        catch
            nums(k) = k;
        end
    end
    [~, idx] = sort(nums);
    files = files(idx);
end

% ----------------------------------------------------------------------
function study = initStudyStruct(folderPath, meta)
    study = struct();
    study.FolderPath        = folderPath;
    study.PatientID         = meta.PatientID;
    study.StudyDate         = meta.StudyDate;
    study.StudyDescription  = meta.StudyDescription;
    study.ScannerVendor     = meta.ScannerVendor;
    study.AllSeries         = struct([]);
    study.Scout             = struct('Volume',[],'SpatialInfo',struct(),'SeriesIdx',[]);
    study.Dixon             = struct('Water',[],'Fat',[],'FF',[],'InPhase',[], ...
                                     'OutPhase',[],'SpatialInfo',struct(), ...
                                     'SeriesIdx',struct());
    study.MRE               = struct('Magnitude',[],'WaveImages',[], ...
                                     'Stiffness',[],'SpatialInfo',struct(), ...
                                     'DriveFrequency_Hz',0,'SeriesIdx',struct());
    study.Harmonized        = struct();
    study.QCFlags           = struct('ScoutLoaded',false,'DixonLoaded',false, ...
                                     'MRELoaded',false,'PartialDixon',false, ...
                                     'Messages',{{}});
end

% ----------------------------------------------------------------------
function study = readScoutSeries(study, seriesList, opts)
    idx = find(strcmp({seriesList.Class}, 'Scout'), 1);
    if isempty(idx)
        study.QCFlags.Messages{end+1} = 'WARNING: No Scout/localizer series found.';
        return
    end
    vprint(opts, 'Reading Scout: "%s" (%d files)', ...
        seriesList(idx).SeriesDescription, numel(seriesList(idx).Files));
    [vol, sinfo] = io_readDICOMSeries(seriesList(idx).Files, opts);
    study.Scout.Volume     = vol;
    study.Scout.SpatialInfo = sinfo;
    study.Scout.SeriesIdx  = idx;
    study.QCFlags.ScoutLoaded = ~isempty(vol);
end

% ----------------------------------------------------------------------
function study = readDixonSeries(study, seriesList, opts)
    subClasses = {'Water','Fat','FF','InPhase','OutPhase'};
    loaded = 0;
    for sc = 1:numel(subClasses)
        sub = subClasses{sc};
        idx = find(strcmp({seriesList.Class}, 'Dixon') & ...
                   strcmp({seriesList.SubClass}, sub), 1);
        if isempty(idx), continue; end
        vprint(opts, 'Reading Dixon/%s: "%s" (%d files)', sub, ...
            seriesList(idx).SeriesDescription, numel(seriesList(idx).Files));
        [vol, sinfo] = io_readDICOMSeries(seriesList(idx).Files, opts);
        study.Dixon.(sub) = vol;
        study.Dixon.SeriesIdx.(sub) = idx;
        if isempty(study.Dixon.SpatialInfo) || ~isfield(study.Dixon.SpatialInfo,'VoxelSize')
            study.Dixon.SpatialInfo = sinfo;
        end
        loaded = loaded + 1;
    end
    study.QCFlags.DixonLoaded  = loaded >= 2;
    study.QCFlags.PartialDixon = loaded > 0 && loaded < 4;

    % If FF not provided directly, compute from Water and Fat
    if isempty(study.Dixon.FF) && ...
       ~isempty(study.Dixon.Water) && ~isempty(study.Dixon.Fat)
        W = double(study.Dixon.Water);
        F = double(study.Dixon.Fat);
        denom = W + F;
        denom(denom == 0) = 1;   % avoid /0
        study.Dixon.FF = single(100 .* F ./ denom);
        vprint(opts, 'Fat fraction map computed from Water+Fat images.');
    end
end

% ----------------------------------------------------------------------
function study = readMRESeries(study, seriesList, opts)
    % Magnitude
    idx = find(strcmp({seriesList.Class}, 'MRE') & ...
               strcmp({seriesList.SubClass}, 'Magnitude'), 1);
    if ~isempty(idx)
        vprint(opts, 'Reading MRE/Magnitude: "%s"', ...
            seriesList(idx).SeriesDescription);
        [vol, sinfo] = io_readDICOMSeries(seriesList(idx).Files, opts);
        study.MRE.Magnitude   = vol;
        study.MRE.SpatialInfo = sinfo;
        study.MRE.SeriesIdx.Magnitude = idx;
    end

    % Wave images (phase images at multiple time offsets)
    waveIdx = find(strcmp({seriesList.Class}, 'MRE') & ...
                   strcmp({seriesList.SubClass}, 'Wave'));
    if ~isempty(waveIdx)
        waveVols = cell(1, numel(waveIdx));
        for w = 1:numel(waveIdx)
            vprint(opts, 'Reading MRE/Wave[%d]: "%s"', w, ...
                seriesList(waveIdx(w)).SeriesDescription);
            [vol, ~] = io_readDICOMSeries(seriesList(waveIdx(w)).Files, opts);
            waveVols{w} = vol;
        end
        % Concatenate along 4th dim: [rows x cols x slices x nPhases]
        try
            study.MRE.WaveImages = cat(4, waveVols{:});
        catch
            study.MRE.WaveImages = waveVols;
        end
        study.MRE.SeriesIdx.Wave = waveIdx;
    end

    % Pre-computed stiffness map (if scanner exported it)
    idx = find(strcmp({seriesList.Class}, 'MRE') & ...
               strcmp({seriesList.SubClass}, 'Stiffness'), 1);
    if ~isempty(idx)
        vprint(opts, 'Reading MRE/Stiffness: "%s"', ...
            seriesList(idx).SeriesDescription);
        [vol, sinfo] = io_readDICOMSeries(seriesList(idx).Files, opts);
        study.MRE.Stiffness = vol;
        if isempty(fieldnames(study.MRE.SpatialInfo))
            study.MRE.SpatialInfo = sinfo;
        end
        study.MRE.SeriesIdx.Stiffness = idx;
    end

    study.QCFlags.MRELoaded = ~isempty(study.MRE.Magnitude) || ...
                               ~isempty(study.MRE.Stiffness);

    % Try to extract drive frequency from series description
    for k = 1:numel(seriesList)
        if strcmp(seriesList(k).Class, 'MRE')
            freq = extractDriveFrequency(seriesList(k).SeriesDescription);
            if freq > 0
                study.MRE.DriveFrequency_Hz = freq;
                break
            end
        end
    end
    if study.MRE.DriveFrequency_Hz == 0
        study.MRE.DriveFrequency_Hz = 60;   % most common abdominal MRE freq
        vprint(opts, 'Drive frequency not found in headers — assuming 60 Hz.');
    end
end

% ----------------------------------------------------------------------
function study = flagLoadQuality(study)
    if ~study.QCFlags.ScoutLoaded
        study.QCFlags.Messages{end+1} = ...
            'Scout not loaded — L1-L2 localization will be skipped.';
    end
    if ~study.QCFlags.DixonLoaded
        study.QCFlags.Messages{end+1} = ...
            'Dixon not loaded — PDFF and body-composition features unavailable.';
    end
    if study.QCFlags.PartialDixon
        study.QCFlags.Messages{end+1} = ...
            'Partial Dixon loaded (fewer than 4 contrasts found).';
    end
    if ~study.QCFlags.MRELoaded
        study.QCFlags.Messages{end+1} = ...
            'MRE not loaded — stiffness features unavailable.';
    end
end

% ----------------------------------------------------------------------
%  Utility helpers
% ----------------------------------------------------------------------
function v = safeTag(info, tag)
    if isfield(info, tag) && ~isempty(info.(tag))
        v = char(info.(tag));
    else
        v = '';
    end
end

function v = safeTagNum(info, tag)
    if isfield(info, tag) && ~isempty(info.(tag))
        v = double(info.(tag)(1));
    else
        v = NaN;
    end
end

function vendor = detectVendor(info)
    mfr = '';
    if isfield(info, 'Manufacturer'), mfr = lower(char(info.Manufacturer)); end
    if contains(mfr, 'siemens'),  vendor = 'Siemens';
    elseif contains(mfr, 'ge'),   vendor = 'GE';
    elseif contains(mfr, 'phil'), vendor = 'Philips';
    else,                          vendor = 'unknown';
    end
end

function freq = extractDriveFrequency(descStr)
    % Look for patterns like "60Hz", "60 Hz", "MRE60"
    tok = regexp(descStr, '(\d+)\s*[Hh][Zz]', 'tokens');
    if ~isempty(tok)
        freq = str2double(tok{1}{1});
    else
        freq = 0;
    end
end

function vprint(opts, fmt, varargin)
    if opts.verbose
        fprintf(['[io_loadDICOMStudy] ' fmt '\n'], varargin{:});
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

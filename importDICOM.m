function S = importDICOM(dicomDir, site, varargin)
% IMPORTDICOM  Load and organize an abbreviated abdominal MRE study.
%
%   S = importDICOM(dicomDir, site)
%   S = importDICOM(dicomDir, site, 'Verbose', true)
%
%   Inputs:
%     dicomDir  - path to folder containing DICOM files (searched recursively)
%     site      - 'Mayo' or 'UCSD'
%
%   Output:
%     S         - StudyData struct (see initStudyData)

    p = inputParser();
    addRequired(p, 'dicomDir',  @(x) isfolder(x));
    addRequired(p, 'site',      @(x) ismember(x, {'Mayo','UCSD'}));
    addParameter(p, 'Verbose',  true,  @islogical);
    addParameter(p, 'LoadPixels', true, @islogical);
    parse(p, dicomDir, site, varargin{:});
    opts = p.Results;

    S = initStudyData();
    S.site = site;
    S.importTimestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');

    if opts.Verbose
        fprintf('[Import] Scanning: %s\n', dicomDir);
    end

    %% Step 1 — Collect all DICOM files
    files = collectDICOMFiles(dicomDir);
    if isempty(files)
        error('importDICOM:noFiles', 'No DICOM files found in: %s', dicomDir);
    end
    if opts.Verbose
        fprintf('[Import] Found %d DICOM files\n', numel(files));
    end

    %% Step 2 — Read headers and group by SeriesInstanceUID
    [seriesMap, studyMeta] = groupSeriesByUID(files, opts.Verbose);

    S.patientID = studyMeta.patientID;
    S.studyDate = studyMeta.studyDate;
    S.studyUID  = studyMeta.studyUID;

    %% Step 3 — Classify each series
    seriesUIDs = keys(seriesMap);
    classified = struct();
    for i = 1:numel(seriesUIDs)
        uid = seriesUIDs{i};
        seriesHeaders = seriesMap(uid);
        label = classifySeries(seriesHeaders{1});   % use first-slice header
        classified(i).uid     = uid;
        classified(i).label   = label;
        classified(i).headers = seriesHeaders;
        if opts.Verbose
            fprintf('[Import]   Series %02d → %-20s  (%s)\n', i, label, ...
                seriesHeaders{1}.SeriesDescription);
        end
    end

    %% Step 4 — Assign series to StudyData slots
    S = assignSeriesToStudy(S, classified, opts.LoadPixels, opts.Verbose);

    %% Step 5 — Validate completeness
    S = validateSeriesCompleteness(S, opts.Verbose);

    if opts.Verbose
        fprintf('[Import] Done. Status: %s\n', S.qc.status);
    end
end
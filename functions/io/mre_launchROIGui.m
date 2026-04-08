function status = mre_launchROIGui(exam, matPath, organ, opts)
% MRE_LAUNCHROI  Build the meta struct and launch mmdi_roi_gui for one MRE series.
%
%   STATUS = MRE_LAUNCHROI(EXAM, MATPATH, ORGAN) launches the interactive
%   ROI placement GUI (mmdi_roi_gui) for a completed MRE .mat file.
%
%   This function is the bridge between the HepatosplenicMRE platform and the
%   mmdi_roi_gui, handling:
%     - Construction of the meta struct required by mmdi_roi_gui
%     - Stiffness display scale selection (0-8 kPa / 0-20 kPa / custom)
%     - Automatic .mat build if no existing file is found
%     - Status return for batch processing
%
%   INPUTS
%     exam      struct from mre_parseDICOMExam
%     matPath   char    full path to .mat file (from mre_buildMATFile)
%               If empty, mre_buildMATFile is called automatically.
%     organ     char    'liver' | 'spleen' | '' (empty = ask user)
%     opts      struct (optional):
%       .stiffScale     [lo hi] in kPa  (default: ask user)
%       .seriesDir      char   folder where ROI files will be saved
%                              (default: folder containing matPath)
%       .examId         char   string label for exam (default: PatientID_StudyDate)
%       .seriesId       char   string label for series (default: MREType_SeriesNum)
%       .lapCutoff      double Laplacian confidence cutoff 0-1 (default: 0.95)
%       .verbose        logical (default: true)
%
%   OUTPUT
%     status  char  'saved' | 'skipped' | 'abort' (from mmdi_roi_gui)
%
%   SEE ALSO  mmdi_roi_gui, mre_buildMATFile, mre_parseDICOMExam
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    status = 'abort';

    if nargin < 3, organ = ''; end
    if nargin < 4, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'stiffScale',  [], ...       % empty = ask user
        'seriesDir',   '', ...
        'examId',      '', ...
        'seriesId',    '', ...
        'lapCutoff',   0.95, ...
        'verbose',     true));

    % ── 1.  Build .mat if not provided ────────────────────────────────
    if isempty(matPath) || ~isfile(matPath)
        vprint(opts, 'No .mat found — building from DICOM...');
        buildOpts = struct('verbose', opts.verbose);
        matPath = mre_buildMATFile(exam, buildOpts);
        if isempty(matPath) || ~isfile(matPath)
            warning('mre_launchROIGui:buildFailed', 'Could not build MAT file.');
            return
        end
    end

    % ── 2.  Resolve output directory ──────────────────────────────────
    if isempty(opts.seriesDir)
        opts.seriesDir = fileparts(matPath);
    end
    if ~isfolder(opts.seriesDir)
        mkdir(opts.seriesDir);
    end

    % ── 3.  Build exam/series identifiers ─────────────────────────────
    if isempty(opts.examId)
        opts.examId = sprintf('%s_%s', exam.PatientID, exam.StudyDate);
    end
    if isempty(opts.seriesId)
        waveSeries = findFirstSeries(exam, {'EPI_WaveMag','GRE_WaveMag'});
        if ~isempty(waveSeries)
            opts.seriesId = sprintf('%s_S%d', exam.MREType, waveSeries.SeriesNumber);
        else
            opts.seriesId = exam.MREType;
        end
    end

    % ── 4.  Stiffness scale ────────────────────────────────────────────
    stiffScale = opts.stiffScale;
    if isempty(stiffScale)
        stiffScale = selectStiffnessScale();
        if isempty(stiffScale)
            status = 'skipped';
            return
        end
    end

    % ── 5.  Build meta struct for mmdi_roi_gui ─────────────────────────
    meta = struct();
    meta.SeriesDir   = opts.seriesDir;
    meta.ExamId      = opts.examId;
    meta.SeriesId    = opts.seriesId;
    meta.StiffCLim   = stiffScale;      % [lo hi] kPa for display
    meta.LapCutoff   = opts.lapCutoff;  % confidence threshold
    meta.MREType     = exam.MREType;

    % ── 6.  Launch GUI ─────────────────────────────────────────────────
    vprint(opts, 'Launching mmdi_roi_gui...');
    vprint(opts, '  MAT:    %s', matPath);
    vprint(opts, '  Organ:  %s', organ);
    vprint(opts, '  Scale:  [%.0f–%.0f] kPa', stiffScale(1), stiffScale(2));

    try
        status = mmdi_roi_gui(matPath, meta);
    catch ME
        warning('mre_launchROIGui:guiError', 'mmdi_roi_gui error: %s', ME.message);
        status = 'abort';
    end

    vprint(opts, 'GUI returned status: %s', status);
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function scale = selectStiffnessScale()
%SELECTSTIFFNESSSCALE  Ask user for clinical stiffness display range.
    choice = questdlg( ...
        'Select stiffness display scale for liver/spleen:', ...
        'Stiffness Scale', ...
        '0–8 kPa (standard)', ...
        '0–20 kPa (fibrosis)', ...
        'Custom...', ...
        '0–8 kPa (standard)');

    switch choice
        case '0–8 kPa (standard)'
            scale = [0 8];
        case '0–20 kPa (fibrosis)'
            scale = [0 20];
        case 'Custom...'
            answer = inputdlg({'Min stiffness (kPa):', 'Max stiffness (kPa):'}, ...
                'Custom Scale', 1, {'0', '8'});
            if isempty(answer)
                scale = [];
                return
            end
            lo = str2double(answer{1});
            hi = str2double(answer{2});
            if isnan(lo) || isnan(hi) || lo >= hi
                warndlg('Invalid range. Using 0–8 kPa.', 'Scale Error');
                scale = [0 8];
            else
                scale = [lo hi];
            end
        otherwise
            scale = [];  % cancelled
    end
end

function s = findFirstSeries(exam, roles)
%FINDFIRSTSERIES  Return first series matching any of the given roles.
    s = [];
    for k = 1:numel(exam.Series)
        if any(strcmp(exam.Series(k).Role, roles))
            s = exam.Series(k);
            return
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
        fprintf(['[mre_launchROIGui] ' fmt '\n'], varargin{:});
    end
end

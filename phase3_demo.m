%% PHASE3_DEMO  End-to-end Phase 3 workflow demonstration.
%
%   Run this script from your project root after setup_platform.m.
%   Demonstrates the complete Phase 3 pipeline:
%     1.  Parse a GE MRE exam folder
%     2.  Build the .mat input for mmdi_roi_gui
%     3.  Detect L1-L2 from 3-plane localizer
%     4.  Propagate L1-L2 to IDEAL-IQ and MRE spaces
%     5.  Launch the ROI GUI for liver/spleen stiffness measurement
%
%   USAGE
%     Set EXAM_ROOT_DIR below, then:
%       run('phase3_demo.m')
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

clc; clear;
fprintf('===================================\n');
fprintf('HepatosplenicMRE — Phase 3 Demo\n');
fprintf('===================================\n\n');

% ── Set your exam root directory here ─────────────────────────────────
EXAM_ROOT_DIR = '\\mr-cimstore\mre-cim\JiaHui\2_Human_studies\Free_Breathing\Images_protocols\Longitudinal_study\20190812_043Y_F_32_e6464_4486156_ANGIE CARPENTER';
% Replace with path to a folder containing the GE MRE DICOM subfolders
% (e.g., the folder that contains 030/, 3001/, 300101/, ... subfolders)

if ~isfolder(EXAM_ROOT_DIR)
    error(['Exam folder not found:\n  %s\n' ...
           'Please set EXAM_ROOT_DIR at the top of this script.'], EXAM_ROOT_DIR);
end

% ── Step 1: Parse the exam ────────────────────────────────────────────
fprintf('Step 1: Parsing exam folder...\n');
exam = mre_parseDICOMExam(EXAM_ROOT_DIR, struct('verbose', true));

fprintf('\nExam summary:\n');
fprintf('  Patient:      %s\n', exam.PatientID);
fprintf('  Date:         %s\n', exam.StudyDate);
fprintf('  MRE type:     %s\n', exam.MREType);
fprintf('  Total series: %d\n', numel(exam.Series));
fprintf('\nSeries list:\n');
for k = 1:numel(exam.Series)
    s = exam.Series(k);
    fprintf('  S%-8d  %-20s  %s\n', s.SeriesNumber, s.Role, s.SeriesDescription);
end

% ── Step 2: Interactive series selection ──────────────────────────────
fprintf('\nStep 2: Opening series selection panel...\n');
selection = mre_selectSeriesGUI(exam);

if ~selection.Confirmed
    fprintf('Selection cancelled by user.\n');
    return
end

fprintf('\nUser selection:\n');
if ~isempty(selection.Localizer)
    fprintf('  Localizer: S%06d  %s\n', ...
        selection.Localizer.SeriesNumber, selection.Localizer.SeriesDescription);
end
if ~isempty(selection.Dixon)
    fprintf('  Dixon:     S%06d  %s  (%d related series)\n', ...
        selection.Dixon.SeriesNumber, selection.Dixon.SeriesDescription, ...
        numel(selection.DixonGroup));
end
if ~isempty(selection.MRE)
    fprintf('  MRE:       S%06d  %s  (%d related series)\n', ...
        selection.MRE.SeriesNumber, selection.MRE.SeriesDescription, ...
        numel(selection.MREGroup));
    fprintf('  MRE group members:\n');
    for k = 1:numel(selection.MREGroup)
        fprintf('    S%06d  %-20s  %s\n', ...
            selection.MREGroup(k).SeriesNumber, ...
            selection.MREGroup(k).Role, ...
            selection.MREGroup(k).SeriesDescription);
    end
end

% ── Step 3: Build MRE .mat file ───────────────────────────────────────
fprintf('\nStep 3: Building MRE MAT file...\n');
matOpts = struct( ...
    'outputDir',       EXAM_ROOT_DIR, ...
    'fileName',        'mre_data.mat', ...
    'interpolateWave', true, ...  % 4 → 8 phases for smooth GUI animation
    'verbose',         true, ...
    'forceRebuild',    false);

matPath = mre_buildMATFile(exam, matOpts);

if isfile(matPath)
    fprintf('MAT file ready: %s\n', matPath);
    tmp = load(matPath, 'M', 'W', 'S', 'LapC');
    fprintf('  M:    %s\n', mat2str(size(tmp.M)));
    fprintf('  W:    %s  (radians)\n', mat2str(size(tmp.W)));
    fprintf('  S:    %s  (kPa)\n', mat2str(size(tmp.S)));
    fprintf('  LapC: %s  (0-1)\n', mat2str(size(tmp.LapC)));
else
    fprintf('WARNING: MAT file not created. Check series availability.\n');
end

% ── Step 3: L1-L2 detection ───────────────────────────────────────────
fprintf('\nStep 3: Detecting L1-L2 vertebral levels...\n');

locSeries = [];
for k = 1:numel(exam.Series)
    if strcmp(exam.Series(k).Role, 'Localizer')
        locSeries = exam.Series(k);
        break
    end
end

if ~isempty(locSeries)
    localizer = loc_loadLocalizer(locSeries, struct('verbose', true));

    L12 = loc_detectL1L2(localizer, struct( ...
        'interactive', true, ...   % show image, allow correction
        'verbose',     true));

    fprintf('\nL1-L2 results:\n');
    fprintf('  L1 position:    Z = %.1f mm  (row %d in %s)\n', ...
        L12.L1_mm, L12.L1_row_coronal, L12.SourcePlane);
    fprintf('  L2 position:    Z = %.1f mm  (row %d)\n', ...
        L12.L2_mm, L12.L2_row_coronal);
    fprintf('  L1-L2 midpoint: Z = %.1f mm\n', L12.L1_L2_mid_mm);
    fprintf('  Confidence:     %.2f\n', L12.Confidence);
    fprintf('  Method:         %s\n', L12.DetectionMethod);
else
    fprintf('No localizer series found. Skipping L1-L2 detection.\n');
    L12 = [];
end

% ── Step 4: Propagate L1-L2 to IDEAL-IQ and MRE ─────────────────────
if ~isempty(L12) && ~isnan(L12.L1_mm)
    fprintf('\nStep 4: Propagating L1-L2 to target spaces...\n');

    % Find IDEAL-IQ spatial info (PDFF series)
    dixonSeries = [];
    for k = 1:numel(exam.Series)
        if strcmp(exam.Series(k).Role, 'IDEALIQ_PDFF')
            dixonSeries = exam.Series(k);
            break
        end
    end

    mreSeries = [];
    for k = 1:numel(exam.Series)
        if contains(exam.Series(k).Role, '_WaveMag')
            mreSeries = exam.Series(k);
            break
        end
    end

    % Read spatial info (headers only, no pixel data)
    if ~isempty(dixonSeries) && ~isempty(dixonSeries.Files)
        try
            hdr1 = dicominfo(dixonSeries.Files{1}, 'UseDictionaryVR', true);
            nZ   = dixonSeries.nImages;
            sinfo_dixon = io_extractSpatialInfo(dixonSeries.Files, hdr1, nZ, 1);
            L12_dixon = loc_propagateToSpace(L12, sinfo_dixon, struct('verbose',true));
            fprintf('  IDEAL-IQ: L1→slice %d,  L2→slice %d\n', ...
                L12_dixon.L1_sliceIdx, L12_dixon.L2_sliceIdx);
        catch ME
            fprintf('  IDEAL-IQ propagation failed: %s\n', ME.message);
            L12_dixon = L12;
        end
    else
        fprintf('  No IDEAL-IQ series found for propagation.\n');
        L12_dixon = L12;
    end

    if ~isempty(mreSeries) && ~isempty(mreSeries.Files)
        try
            hdr1 = dicominfo(mreSeries.Files{1}, 'UseDictionaryVR', true);
            nPhases = mreSeries.nPhases;
            nZ = mreSeries.nImages / (nPhases * 2);
            nZ = max(1, round(nZ));
            sinfo_mre = io_extractSpatialInfo(mreSeries.Files, hdr1, nZ, nPhases);
            L12_mre = loc_propagateToSpace(L12, sinfo_mre, struct('verbose',true));
            fprintf('  MRE:      L1→slice %d,  L2→slice %d\n', ...
                L12_mre.L1_sliceIdx, L12_mre.L2_sliceIdx);
        catch ME
            fprintf('  MRE propagation failed: %s\n', ME.message);
            L12_mre = L12;
        end
    else
        fprintf('  No MRE wave+mag series found for propagation.\n');
        L12_mre = L12;
    end
end

% ── Step 5: Launch ROI GUI ────────────────────────────────────────────
fprintf('\nStep 5: Launching MRE ROI GUI...\n');

if isfile(matPath)
    guiOpts = struct( ...
        'stiffScale',  [0 8], ...   % 0-8 kPa initial display
        'lapCutoff',   0.95, ...    % 95% confidence threshold
        'verbose',     true);

    % Will ask user for organ (liver vs spleen) if not specified
    status = mre_launchROIGui(exam, matPath, '', guiOpts);
    fprintf('\nGUI status: %s\n', status);
else
    fprintf('Skipping GUI — MAT file not available.\n');
end

fprintf('\n===================================\n');
fprintf('Phase 3 demo complete.\n');
fprintf('===================================\n');

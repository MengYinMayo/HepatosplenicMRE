function results = seg_runFullPipeline(exam, selection, matPath, opts)
% SEG_RUNFULLPIPELINE  Run the complete co-localisation + segmentation pipeline.
%
%   RESULTS = SEG_RUNFULLPIPELINE(EXAM, SELECTION, MATPATH) executes the
%   full analysis pipeline for one exam session:
%
%     Step 1  Co-localization
%               Load 3-plane localizer → detect L1/L2 vertebral levels
%               Propagate L1/L2 to Dixon and MRE spaces
%
%     Step 2  L1-L2 body composition
%               Load IDEAL-IQ Dixon volumes
%               Interactive ROI placement: muscle + SAT at L1 and L2 levels
%               Compute areas (cm²), PDFF (%), muscle:SAT ratio
%
%     Step 3  Liver ROI  (via mmdi_roi_gui)
%               Show MRE wave animation + stiffness + confidence
%               Two-stage ROI: outer contour → inner measurement
%               Export stiffness, organ shape metrics
%
%     Step 4  Spleen ROI  (via mmdi_roi_gui)
%               Same workflow as liver
%
%   INPUTS
%     exam        struct from mre_parseDICOMExam
%     selection   struct from mre_selectSeriesGUI
%     matPath     char   path to MRE .mat file (from mre_buildMATFile)
%     opts        struct (optional):
%       .outputDir    char    where to save all results (default: exam folder)
%       .subjectId    char    label for filenames (default: PatientID_StudyDate)
%       .stiffScale   [lo hi] kPa display range (default: ask user)
%       .doLiver      logical (default: true)
%       .doSpleen     logical (default: true)
%       .doL12        logical (default: true)
%       .verbose      logical (default: true)
%
%   OUTPUT RESULTS struct:
%     .L12          struct from seg_L1L2ROIGui
%     .LiverROI     status char from mmdi_roi_gui ('saved'|'skipped')
%     .SpleenROI    status char
%     .L12_dixon    struct from loc_propagateToSpace
%     .L12_mre      struct from loc_propagateToSpace
%     .Dixon        struct from seg_buildDixonVolume
%
%   USAGE
%     results = seg_runFullPipeline(exam, selection, matPath);
%
%   SEE ALSO  mre_parseDICOMExam, mre_selectSeriesGUI, mre_buildMATFile,
%             loc_detectL1L2, seg_buildDixonVolume, seg_L1L2ROIGui,
%             mre_launchROIGui, mmdi_roi_gui
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 4, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'outputDir',  '', ...
        'subjectId',  '', ...
        'stiffScale', [], ...
        'doLiver',    true, ...
        'doSpleen',   true, ...
        'doL12',      true, ...
        'verbose',    true));

    % Output directory
    if isempty(opts.outputDir)
        opts.outputDir = exam.ExamRootDir;
    end
    if ~isfolder(opts.outputDir)
        mkdir(opts.outputDir);
    end

    % Subject ID
    if isempty(opts.subjectId)
        opts.subjectId = sprintf('%s_%s', exam.PatientID, exam.StudyDate);
        opts.subjectId = strrep(opts.subjectId, ' ', '_');
    end

    results = initResults();
    vprint(opts, '=== seg_runFullPipeline ===');
    vprint(opts, 'Subject: %s', opts.subjectId);

    % ==================================================================
    % STEP 1 — CO-LOCALIZATION  (L1/L2 detection + propagation)
    % ==================================================================
    L12 = []; L12_dixon = []; L12_mre = [];

    if opts.doL12 && ~isempty(selection.Localizer)
        vprint(opts, '--- Step 1: Co-localization ---');

        % 1a. Load localizer
        localizer = loc_loadLocalizer(selection.Localizer, ...
            struct('verbose', opts.verbose));

        % 1b. Detect L1/L2 with interactive correction
        L12 = loc_detectL1L2(localizer, struct( ...
            'interactive', true, ...
            'verbose',     opts.verbose));

        vprint(opts, 'L1=%.1f mm  L2=%.1f mm  confidence=%.2f  method=%s', ...
            L12.L1_mm, L12.L2_mm, L12.Confidence, L12.DetectionMethod);

        % 1c. Propagate to Dixon space
        if ~isempty(selection.Dixon) && ~isempty(selection.DixonGroup)
            try
                dixSeries = selection.DixonGroup(1);   % use first series for geometry
                hdr1      = dicominfo(dixSeries.Files{1}, 'UseDictionaryVR', true);
                nZ_dix    = dixSeries.nImages;
                sinfoD    = io_extractSpatialInfo(dixSeries.Files, hdr1, nZ_dix, 1);
                L12_dixon = loc_propagateToSpace(L12, sinfoD, ...
                    struct('verbose', opts.verbose));
                vprint(opts, 'Dixon: L1→slice %d,  L2→slice %d', ...
                    L12_dixon.L1_sliceIdx, L12_dixon.L2_sliceIdx);
            catch ME
                warning('seg_runFullPipeline:dixonProp', ...
                    'Dixon propagation failed: %s', ME.message);
                L12_dixon = makeDefaultL12(L12, 1);
            end
        end

        % 1d. Propagate to MRE space
        if ~isempty(matPath) && isfile(matPath)
            try
                tmp = load(matPath, 'H');
                H   = tmp.H;
                % Build spatial info from H struct
                sinfoMRE = buildSinfoFromH(H, matPath);
                if ~isempty(sinfoMRE)
                    L12_mre = loc_propagateToSpace(L12, sinfoMRE, ...
                        struct('verbose', opts.verbose));
                    vprint(opts, 'MRE:   L1→slice %d,  L2→slice %d', ...
                        L12_mre.L1_sliceIdx, L12_mre.L2_sliceIdx);
                end
            catch ME
                warning('seg_runFullPipeline:mreProp', ...
                    'MRE propagation failed: %s', ME.message);
            end
        end

        results.L12_dixon = L12_dixon;
        results.L12_mre   = L12_mre;
    else
        vprint(opts, 'Skipping co-localization (no localizer or doL12=false).');
    end

    % ==================================================================
    % STEP 2 — L1-L2 BODY COMPOSITION
    % ==================================================================
    if opts.doL12 && ~isempty(selection.Dixon)
        vprint(opts, '--- Step 2: L1-L2 body composition ---');

        % 2a. Build Dixon volumes from DixonGroup
        dixon = seg_buildDixonVolume(selection.DixonGroup, ...
            struct('verbose', opts.verbose));
        results.Dixon = dixon;

        % 2b. Determine L1/L2 slice indices in Dixon space
        if isempty(L12_dixon) || isnan(L12_dixon.L1_sliceIdx)
            % Auto-estimate: use middle of the Dixon volume
            nZd = max(1, dixon.nSlices);
            L12_dixon = struct('L1_sliceIdx', round(nZd*0.4), ...
                               'L2_sliceIdx', round(nZd*0.5), ...
                               'L1_mm', NaN, 'L2_mm', NaN);
            vprint(opts, 'No L1/L2 propagation — using estimated slice indices.');
        end

        % 2c. Launch interactive ROI GUI
        if ~isempty(dixon.Water) || ~isempty(dixon.PDFF)
            roiOpts = struct('verbose',   opts.verbose, ...
                             'subjectId', opts.subjectId, ...
                             'roiSaveDir',opts.outputDir);
            results.L12 = seg_L1L2ROIGui(dixon, L12_dixon, roiOpts);
        else
            vprint(opts, 'Dixon volumes empty — skipping body composition GUI.');
        end
    else
        vprint(opts, 'Skipping L1-L2 body composition (no Dixon or doL12=false).');
    end

    % ==================================================================
    % STEP 3 — LIVER ROI  (via mmdi_roi_gui)
    % ==================================================================
    if opts.doLiver && ~isempty(matPath) && isfile(matPath)
        vprint(opts, '--- Step 3: Liver ROI ---');
        guiOpts = struct('verbose',    opts.verbose, ...
                         'stiffScale', opts.stiffScale, ...
                         'seriesDir',  opts.outputDir, ...
                         'examId',     opts.subjectId, ...
                         'seriesId',   'MRE');
        results.LiverROI = mre_launchROIGui(exam, matPath, 'liver', guiOpts);
        vprint(opts, 'Liver ROI status: %s', results.LiverROI);
    else
        if ~opts.doLiver
            vprint(opts, 'Skipping liver ROI (doLiver=false).');
        else
            vprint(opts, 'Skipping liver ROI (no MAT file).');
        end
    end

    % ==================================================================
    % STEP 4 — SPLEEN ROI  (via mmdi_roi_gui)
    % ==================================================================
    if opts.doSpleen && ~isempty(matPath) && isfile(matPath)
        vprint(opts, '--- Step 4: Spleen ROI ---');
        guiOpts = struct('verbose',    opts.verbose, ...
                         'stiffScale', opts.stiffScale, ...
                         'seriesDir',  opts.outputDir, ...
                         'examId',     opts.subjectId, ...
                         'seriesId',   'MRE');
        results.SpleenROI = mre_launchROIGui(exam, matPath, 'spleen', guiOpts);
        vprint(opts, 'Spleen ROI status: %s', results.SpleenROI);
    else
        if ~opts.doSpleen
            vprint(opts, 'Skipping spleen ROI (doSpleen=false).');
        end
    end

    % ==================================================================
    % SUMMARY
    % ==================================================================
    vprint(opts, '');
    vprint(opts, '=== Pipeline complete ===');
    if isfield(results.L12,'L1') && isfield(results.L12.L1,'MuscleArea_cm2')
        vprint(opts, 'L1  Muscle: %.2f cm²   SAT: %.2f cm²   Ratio: %.3f', ...
            results.L12.L1.MuscleArea_cm2, ...
            results.L12.L1.SATArea_cm2, ...
            results.L12.L1.MuscleSATRatio);
        vprint(opts, 'L2  Muscle: %.2f cm²   SAT: %.2f cm²   Ratio: %.3f', ...
            results.L12.L2.MuscleArea_cm2, ...
            results.L12.L2.SATArea_cm2, ...
            results.L12.L2.MuscleSATRatio);
    end
    vprint(opts, 'Liver:  %s   Spleen: %s', results.LiverROI, results.SpleenROI);
end


% ======================================================================
%  HELPERS
% ======================================================================

function sinfo = buildSinfoFromH(H, matPath)
%BUILDSFINFOFROMH  Reconstruct a minimal spatial info from the H header.
    sinfo = [];
    if isempty(H), return; end

    sinfo = struct();
    try
        tmp   = load(matPath, 'S');
        [r,c,z] = size(tmp.S);
    catch
        r = 256; c = 256; z = 4;
    end

    sinfo.Rows    = r; sinfo.Columns = c; sinfo.NumSlices = z; sinfo.NumPhases = 1;

    if isfield(H,'DisplayFieldOfView') && ~isempty(H.DisplayFieldOfView)
        ps = double(H.DisplayFieldOfView) / c;
        sinfo.PixelSpacing = [ps ps];
    else
        sinfo.PixelSpacing = [1.7 1.7];
    end

    if isfield(H,'SliceThickness') && ~isempty(H.SliceThickness)
        sinfo.SliceSpacing = double(H.SliceThickness);
    else
        sinfo.SliceSpacing = 10;
    end

    sinfo.VoxelSize = [sinfo.PixelSpacing, sinfo.SliceSpacing];

    if isfield(H,'ImageOrientationPatient') && ~isempty(H.ImageOrientationPatient)
        iop = double(H.ImageOrientationPatient(:))';
    else
        iop = [1 0 0 0 1 0];
    end
    sinfo.ImageOrientationPatient = iop;

    if isfield(H,'ImagePositionPatient') && ~isempty(H.ImagePositionPatient)
        pos1 = double(H.ImagePositionPatient(:))';
    else
        pos1 = [0 0 0];
    end
    sinfo.ImagePositionFirst = pos1;
    sinfo.ImagePositionLast  = pos1 + (z-1)*sinfo.SliceSpacing * cross(iop(1:3),iop(4:6));

    % Build simple affine
    rowDir = iop(1:3); colDir = iop(4:6);
    slNorm = cross(rowDir, colDir);
    dr = sinfo.PixelSpacing(1); dc = sinfo.PixelSpacing(2); ds = sinfo.SliceSpacing;
    A  = [rowDir(:)*dr, colDir(:)*dc, slNorm(:)*ds, pos1(:); 0 0 0 1];
    sinfo.AffineMatrix    = A;
    sinfo.AffineMatrixInv = inv(A);
    sinfo.SliceNormal     = slNorm;
end

function L12 = makeDefaultL12(L12src, sliceIdx)
    L12 = L12src;
    L12.L1_sliceIdx = sliceIdx;
    L12.L2_sliceIdx = sliceIdx + 1;
    L12.L1_sliceFrac = sliceIdx;
    L12.L2_sliceFrac = sliceIdx + 1;
end

function results = initResults()
    results = struct('L12',struct(),'LiverROI','not run', ...
                     'SpleenROI','not run','L12_dixon',[],'L12_mre',[], ...
                     'Dixon',struct());
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k}), opts.(fields{k}) = defaults.(fields{k}); end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[seg_runFullPipeline] ' fmt '\n'], varargin{:});
    end
end

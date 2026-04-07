function app = app_integratePhase2(app)
% APP_INTEGRATEPHASE2  Wire Phase-2 I/O functions into the App callbacks.
%
%   This function is NOT called directly. Instead, paste the method bodies
%   below into HepatosplenicMRE_App.m to replace the Phase-1 stubs for
%   LoadStudyCallback and RunStage1Callback.
%
%   ── INSTRUCTIONS ──────────────────────────────────────────────────────
%   In HepatosplenicMRE_App.m, replace:
%
%       function LoadStudyCallback(app)
%           setStatus(app, '[Phase 2] LoadStudyCallback — not yet implemented.');
%       end
%
%   with the full implementation below (LoadStudyCallback section).
%   Do the same for RunStage1Callback.
%   ──────────────────────────────────────────────────────────────────────
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2

    error('app_integratePhase2:notCallable', ...
        ['This file contains method bodies to copy into HepatosplenicMRE_App.m.\n' ...
         'See the source code comments for instructions.']);
end


%% ======================================================================
%  COPY THIS BLOCK into HepatosplenicMRE_App.m → LoadStudyCallback
%  ======================================================================
%{
function LoadStudyCallback(app)
    % Let the user pick a folder
    folderPath = uigetdir(pwd, 'Select DICOM Study Folder');
    if isequal(folderPath, 0)
        return   % user cancelled
    end

    % Show a progress dialog
    dlg = uiprogressdlg(app.UIFigure, ...
        'Title',   'Loading Study', ...
        'Message', 'Scanning DICOM files...', ...
        'Indeterminate', true);

    try
        % Load all series
        loadOpts = struct('verbose', true, 'forceReread', false);
        study = io_loadDICOMStudy(folderPath, loadOpts);

        dlg.Message = 'Harmonizing image grids...';

        % Harmonize to common grid (Stage 1 lite — auto-run on load)
        harmOpts = struct('verbose', true, 'method', 'linear');
        study = harm_harmonizeStudy(study, harmOpts);

        % Store in AppData
        app.AppData.ActiveStudy = study;

        % Update study browser tree
        updateStudyTree(app, study);

        % Display first slice in each tab
        app.AppData.CurrentSlice = 1;
        updateSliceSlider(app);
        refreshDisplayedSlice(app);

        % Update feature panel placeholders
        clearFeatureDisplay(app);

        % Pipeline status
        updatePipelineStatus(app, 'S1', 'done');

        % Report QC flags
        for m = 1:numel(study.QCFlags.Messages)
            setStatus(app, study.QCFlags.Messages{m});
        end

        setStatus(app, sprintf( ...
            'Loaded: %s  |  %s  |  Scout=%d  Dixon=%d  MRE=%d', ...
            study.PatientID, study.StudyDate, ...
            study.QCFlags.ScoutLoaded, ...
            study.QCFlags.DixonLoaded, ...
            study.QCFlags.MRELoaded));

    catch ME
        close(dlg);
        uialert(app.UIFigure, ME.message, 'Load Error', 'Icon','error');
        setStatus(app, ['ERROR: ' ME.message]);
        return
    end

    close(dlg);
end
%}


%% ======================================================================
%  COPY THIS BLOCK into HepatosplenicMRE_App.m → RunStage1Callback
%  ======================================================================
%{
function RunStage1Callback(app)
    if ~isfield(app.AppData, 'ActiveStudy') || isempty(app.AppData.ActiveStudy)
        uialert(app.UIFigure, 'Please load a study first.', 'No Study');
        return
    end

    updatePipelineStatus(app, 'S1', 'running');
    dlg = uiprogressdlg(app.UIFigure, ...
        'Title',   'Stage 1 — Harmonization', ...
        'Message', 'Resampling volumes to common grid...', ...
        'Indeterminate', true);

    try
        harmOpts = struct('verbose', true, 'method', 'linear');
        app.AppData.ActiveStudy = harm_harmonizeStudy( ...
            app.AppData.ActiveStudy, harmOpts);
        updatePipelineStatus(app, 'S1', 'done');
        setStatus(app, 'Stage 1 complete — all volumes on common grid.');
    catch ME
        updatePipelineStatus(app, 'S1', 'error');
        uialert(app.UIFigure, ME.message, 'Stage 1 Error', 'Icon','error');
    end

    close(dlg);
end
%}


%% ======================================================================
%  COPY THIS BLOCK into HepatosplenicMRE_App.m → refreshDisplayedSlice
%  (replaces the Phase-1 placeholder)
%  ======================================================================
%{
function refreshDisplayedSlice(app)
    if ~isfield(app.AppData, 'ActiveStudy') || isempty(app.AppData.ActiveStudy)
        return
    end
    H = app.AppData.ActiveStudy.Harmonized;
    s = app.AppData.CurrentSlice;

    tab = app.ImageTabGroup.SelectedTab;

    if tab == app.ScoutTab && ~isempty(H.Scout)
        s = min(s, size(H.Scout, 3));
        displaySlice(app, app.AxScoutAxial,   H.Scout(:,:,s), 'Axial');
        displaySlice(app, app.AxScoutCoronal, ...
            squeeze(H.Scout(:, round(end/2), :))', 'Coronal');
        displaySlice(app, app.AxScoutSagittal, ...
            squeeze(H.Scout(round(end/2), :, :))', 'Sagittal');

    elseif tab == app.DixonTab
        if ~isempty(H.DixonWater)
            s = min(s, size(H.DixonWater, 3));
            displaySlice(app, app.AxDixonWater,   H.DixonWater(:,:,s),   'Water');
            displaySlice(app, app.AxDixonFat,     H.DixonFat(:,:,s),     'Fat');
            displaySlice(app, app.AxDixonFF,      H.DixonFF(:,:,s),      'Fat Fraction (%)');
            displaySlice(app, app.AxDixonInPhase, H.DixonInPhase(:,:,s), 'In-Phase');
        end

    elseif tab == app.MRETab
        if ~isempty(H.MREMagnitude)
            s = min(s, size(H.MREMagnitude, 3));
            displaySlice(app, app.AxMREMagnitude, H.MREMagnitude(:,:,s), 'MRE Magnitude');
        end
        if ~isempty(H.MREStiffness)
            displaySlice(app, app.AxMREStiffness, H.MREStiffness(:,:,s), ...
                'Stiffness (kPa)');
        end

    elseif tab == app.L12Tab
        % Display Dixon water at L1 level (populated after Phase 3 L1-L2)
        if ~isempty(H.DixonWater) && ~isempty(app.AppData.L1SliceDixon)
            sl = app.AppData.L1SliceDixon;
            displaySlice(app, app.AxL12Axial, H.DixonWater(:,:,sl), ...
                sprintf('Axial — L1 level (slice %d)', sl));
        end
    end

    app.LblImageInfo.Text = sprintf('Slice %d / %d', s, ...
        app.SldrSlice.Limits(2));
end

function displaySlice(app, ax, img, titleStr)
    % Normalize and display a 2-D image in a uiaxes.
    img = double(img);
    lo  = min(img(:));
    hi  = max(img(:));
    if hi > lo
        img = (img - lo) ./ (hi - lo);
    end
    imshow(img, 'Parent', ax);
    title(ax, titleStr, 'FontSize', 9, 'Color', [0.85 0.85 0.85], ...
        'FontWeight', 'normal');
end

function clearFeatureDisplay(app)
    fields = {'LiverVol','SpleenVol','LSRatio','LiverPDFF', ...
              'LiverStiff','SpleenStiff','StiffRatio','HetIQR', ...
              'MuscleArea','SATArea','MuscleFatRatio','MusclePDFF', ...
              'L1Status','L2Status','L12MuscleArea','L12SATArea', ...
              'L12MuscleFat','L12PDFF','SegConf','Coverage', ...
              'RangeCheck','ManualReview'};
    for k = 1:numel(fields)
        propName = ['Val' fields{k}];
        if isprop(app, propName)
            app.(propName).Text      = '—';
            app.(propName).FontColor = [0.45 0.45 0.45];
        end
    end
end

function updateStudyTree(app, study)
    % Refresh left-panel study browser with loaded study info.
    delete(app.StudyTree.Children);
    root = uitreenode(app.StudyTree, ...
        'Text', sprintf('🏥  %s', study.PatientID), ...
        'NodeData', study);
    sessNode = uitreenode(root, ...
        'Text', sprintf('📋  %s', study.StudyDate));

    % Add series nodes
    for k = 1:numel(study.AllSeries)
        s = study.AllSeries(k);
        icon = seriesIcon(s.Class);
        uitreenode(sessNode, 'Text', sprintf('%s  S%02d  %s  [%s/%s]', ...
            icon, s.SeriesNumber, s.SeriesDescription, s.Class, s.SubClass));
    end

    expand(app.StudyTree, root);
    expand(app.StudyTree, sessNode);
    app.LblStudyStats.Text = sprintf( ...
        'Loaded: 1  |  Series: %d  |  Flagged: %d', ...
        numel(study.AllSeries), ...
        ~isempty(study.QCFlags.Messages));
end

function icon = seriesIcon(cls)
    switch cls
        case 'Scout',   icon = '🗺';
        case 'Dixon',   icon = '🧲';
        case 'MRE',     icon = '🌊';
        otherwise,      icon = '📄';
    end
end
%}

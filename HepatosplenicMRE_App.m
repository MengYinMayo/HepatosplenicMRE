classdef HepatosplenicMRE_App < matlab.apps.AppBase
% HepatosplenicMRE_App  — Abdominal MRI/MRE Analysis (Version 1.0, M.Y., April 17, 2026)
%
%   All processing, image viewing, and ROI placement occurs inside this
%   one window. ROI drawing uses a magnified popup window for precision.
%
%   TABS
%     Localizer  Scrollable coronal + sagittal; interactive L1/L2 placement
%     Dixon      Multi-contrast viewer (Water, PDFF, InPhase) + organ ROIs
%     MRE        Magnitude / animated wave / stiffness + organ ROIs
%     Results    Summary table of all measurements
%
%   ROI SETS (all saved separately)
%     Liver_Dixon    entire-organ contour on Dixon → volume, PDFF
%     Spleen_Dixon   entire-organ contour on Dixon → volume, PDFF
%     Muscle_L1      L1 slice on Dixon → area, PDFF
%     Muscle_L2      L2 slice on Dixon → area, PDFF
%     SAT_L1         L1 slice on Dixon → area, PDFF
%     SAT_L2         L2 slice on Dixon → area, PDFF
%     Liver_MRE      inner stiffness ROI on MRE (per slice)
%     Spleen_MRE     inner stiffness ROI on MRE (per slice)
%
%   USAGE
%     app = HepatosplenicMRE_App;
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu
%   DATE    April 17, 2026

    % =====================================================================
    %  UI PROPERTIES
    % =====================================================================
    properties (Access = public)
        UIFigure            matlab.ui.Figure

        % Menus
        FileMenu            matlab.ui.container.Menu
        ViewMenu            matlab.ui.container.Menu
        ExportMenu          matlab.ui.container.Menu
        HelpMenu            matlab.ui.container.Menu

        % Toolbar
        ToolbarPanel        matlab.ui.container.Panel
        BtnLoadStudy        matlab.ui.control.Button
        BtnConfirmL12       matlab.ui.control.Button
        LblPatientInfo      matlab.ui.control.Label

        % Body layout
        BodyGrid            matlab.ui.container.GridLayout

        % ── LEFT: Study Browser ──
        LeftPanel           matlab.ui.container.Panel
        StudyTree           matlab.ui.container.CheckBoxTree
        LblStudyStats       matlab.ui.control.Label

        % ── CENTER: Tabbed image viewer ──
        CenterPanel         matlab.ui.container.Panel
        ImageTabGroup       matlab.ui.container.TabGroup

        % Localizer tab
        LocTab              matlab.ui.container.Tab
        LocGrid             matlab.ui.container.GridLayout
        AxLocCoronal        matlab.ui.control.UIAxes
        AxLocSagittal       matlab.ui.control.UIAxes
        SldrLocCor          matlab.ui.control.Slider
        SldrLocSag          matlab.ui.control.Slider
        LblLocCor           matlab.ui.control.Label
        LblLocSag           matlab.ui.control.Label
        BtnPlaceL1          matlab.ui.control.Button   % legacy (T12)
        BtnPlaceL2          matlab.ui.control.Button   % legacy (L3)
        BtnClearL12         matlab.ui.control.Button
        LblL12Status        matlab.ui.control.Label
        % Seven disc-level mark buttons (T9/10 → L3/4)
        BtnMarkLM_T9T10     matlab.ui.control.Button
        BtnMarkLM_T10T11    matlab.ui.control.Button
        BtnMarkLM_T11T12    matlab.ui.control.Button
        BtnMarkLM_T12L1     matlab.ui.control.Button
        BtnMarkLM_L1L2      matlab.ui.control.Button
        BtnMarkLM_L2L3      matlab.ui.control.Button
        BtnMarkLM_L3L4      matlab.ui.control.Button
        % Dixon landmark jump buttons (one per disc level)
        BtnJumpLM_T9T10     matlab.ui.control.Button
        BtnJumpLM_T10T11    matlab.ui.control.Button
        BtnJumpLM_T11T12    matlab.ui.control.Button
        BtnJumpLM_T12L1     matlab.ui.control.Button
        BtnJumpLM_L1L2      matlab.ui.control.Button
        BtnJumpLM_L2L3      matlab.ui.control.Button
        BtnJumpLM_L3L4      matlab.ui.control.Button

        % Dixon tab
        DixonTab            matlab.ui.container.Tab
        DixonGrid           matlab.ui.container.GridLayout
        AxDixon             matlab.ui.control.UIAxes   % single-panel display
        AxDixonWater        matlab.ui.control.UIAxes   % kept for compatibility
        AxDixonPDFF         matlab.ui.control.UIAxes
        AxDixonIP           matlab.ui.control.UIAxes
        DdlDixonContrast    matlab.ui.control.DropDown
        DdlDixonCmap        matlab.ui.control.DropDown   % colormap for PDFF/current
        EdtDixonMin         matlab.ui.control.NumericEditField  % display min
        EdtDixonMax         matlab.ui.control.NumericEditField  % display max
        LblDixonSlice       matlab.ui.control.Label
        LblDixonInfo        matlab.ui.control.Label
        % Dixon ROI buttons
        BtnROI_LiverDixon   matlab.ui.control.Button
        BtnROI_SpleenDixon  matlab.ui.control.Button
        BtnROI_MuscleDixon  matlab.ui.control.Button
        BtnROI_PsoasDixon   matlab.ui.control.Button   % psoas muscle (Dixon)
        BtnROI_TrunkDixon   matlab.ui.control.Button   % non-psoas trunk skeletal muscle (Dixon)
        BtnROI_SATDixon     matlab.ui.control.Button   % subcutaneous adipose tissue (magenta)
        BtnROI_VATDixon     matlab.ui.control.Button   % visceral adipose tissue (yellow)
        BtnROI_FatDixon     matlab.ui.control.Button   % legacy – kept for compatibility
        BtnClearDixonROIs   matlab.ui.control.Button
        LblDixonROIInfo     matlab.ui.control.Label
        EdtROIVerticesDixon matlab.ui.control.NumericEditField  % polygon vertex count (Dixon)
        EdtROIVerticesMRE   matlab.ui.control.NumericEditField  % polygon vertex count (MRE)
        % Water / Fat panel window-level controls
        EdtWaterWinLo   matlab.ui.control.NumericEditField
        EdtWaterWinHi   matlab.ui.control.NumericEditField
        EdtFatWinLo     matlab.ui.control.NumericEditField
        EdtFatWinHi     matlab.ui.control.NumericEditField
        % Localizer coronal/sagittal window-level controls
        EdtCorWinLo     matlab.ui.control.NumericEditField
        EdtCorWinHi     matlab.ui.control.NumericEditField
        EdtSagWinLo     matlab.ui.control.NumericEditField
        EdtSagWinHi     matlab.ui.control.NumericEditField
        % Legacy properties kept for code compatibility (no longer wired to UI)
        BtnROI_MuscleL1     matlab.ui.control.Button
        BtnROI_MuscleL2     matlab.ui.control.Button
        BtnROI_SATL1        matlab.ui.control.Button
        BtnROI_SATL2        matlab.ui.control.Button

        % MRE tab
        MRETab              matlab.ui.container.Tab
        MREGrid             matlab.ui.container.GridLayout
        AxMREMag            matlab.ui.control.UIAxes
        AxMRERawWave        matlab.ui.control.UIAxes
        AxMREWave           matlab.ui.control.UIAxes
        AxMREStiff          matlab.ui.control.UIAxes
        AxMREWaveBar        matlab.ui.control.UIAxes
        AxMREStiffBar       matlab.ui.control.UIAxes
        SldrMRE             matlab.ui.control.Slider
        LblMRESlice         matlab.ui.control.Label
        LblMREInfo          matlab.ui.control.Label
        BtnMREPlay          matlab.ui.control.Button
        EdtWaveMax          matlab.ui.control.NumericEditField
        BtnStiff8           matlab.ui.control.Button
        BtnStiff20          matlab.ui.control.Button
        BtnConfMap          matlab.ui.control.StateButton
        EdtConfThresh       matlab.ui.control.NumericEditField
        BtnROI_LiverMRE     matlab.ui.control.Button
        BtnROI_SpleenMRE    matlab.ui.control.Button
        BtnROI_MuscleMRE    matlab.ui.control.Button
        BtnROI_FatMRE       matlab.ui.control.Button
        EdtLiverConfThresh  matlab.ui.control.NumericEditField
        EdtSpleenConfThresh matlab.ui.control.NumericEditField
        EdtMuscleConfThresh matlab.ui.control.NumericEditField
        EdtFatConfThresh    matlab.ui.control.NumericEditField
        BtnClearMREROIs     matlab.ui.control.Button

        % Results tab
        ResultsTab              matlab.ui.container.Tab
        ResultsGrid             matlab.ui.container.GridLayout
        ResultsTable            matlab.ui.control.Table
        ResultsBtnGrid          matlab.ui.container.GridLayout
        BtnExportPDFFRadiomics  matlab.ui.control.Button
        BtnExportMRERadiomics   matlab.ui.control.Button

        % ── RIGHT: Feature results ──
        RightPanel          matlab.ui.container.Panel
        RightGrid           matlab.ui.container.GridLayout

        % Feature value labels (generated dynamically — see buildRightPanel)
        ValLiverDixonVol    matlab.ui.control.Label
        ValLiverDixonPDFF   matlab.ui.control.Label
        ValSpleenDixonVol   matlab.ui.control.Label
        ValSpleenDixonPDFF  matlab.ui.control.Label
        ValMuscleDixonVol   matlab.ui.control.Label
        ValMuscleDixonPDFF  matlab.ui.control.Label
        ValPsoasDixonVol    matlab.ui.control.Label
        ValPsoasDixonPDFF   matlab.ui.control.Label
        ValTrunkDixonVol    matlab.ui.control.Label
        ValTrunkDixonPDFF   matlab.ui.control.Label
        ValSATDixonVol      matlab.ui.control.Label   % subcutaneous adipose tissue
        ValSATDixonPDFF     matlab.ui.control.Label
        ValVATDixonVol      matlab.ui.control.Label   % visceral adipose tissue
        ValVATDixonPDFF     matlab.ui.control.Label
        ValFatDixonVol      matlab.ui.control.Label   % legacy label (kept for compatibility)
        ValFatDixonPDFF     matlab.ui.control.Label   % legacy label (kept for compatibility)
        % Legacy label handles (not wired to UI; kept for backward compatibility)
        ValMuscleL1Area     matlab.ui.control.Label
        ValMuscleL1PDFF     matlab.ui.control.Label
        ValMuscleL2Area     matlab.ui.control.Label
        ValMuscleL2PDFF     matlab.ui.control.Label
        ValSATL1Area        matlab.ui.control.Label
        ValSATL1PDFF        matlab.ui.control.Label
        ValSATL2Area        matlab.ui.control.Label
        ValSATL2PDFF        matlab.ui.control.Label
        ValMuscleSATRatio   matlab.ui.control.Label
        ValLiverStiff       matlab.ui.control.Label
        ValSpleenStiff      matlab.ui.control.Label
        % NOTE FOR MAINTAINERS:
        % The following *IQR properties keep their historical names for
        % backward compatibility with older app revisions, but they no
        % longer display interquartile range. In the current UI they are
        % repurposed to show the combined text "N / volume" for each
        % MRE ROI. Use the visible panel text, not the property suffix,
        % as the source of truth for interpretation.
        ValLiverStiffIQR    matlab.ui.control.Label
        ValSpleenStiffIQR   matlab.ui.control.Label
        ValMuscleMREStiff   matlab.ui.control.Label
        ValMuscleMREStiffIQR matlab.ui.control.Label
        ValFatMREStiff      matlab.ui.control.Label
        ValFatMREStiffIQR   matlab.ui.control.Label
        % The legacy *Vol properties below are retained only for code
        % compatibility with earlier revisions. The visible panel now
        % combines N and volume onto a single line, so these handles are
        % no longer shown separately in the active UI.
        ValLiverStiffVol    matlab.ui.control.Label
        ValSpleenStiffVol   matlab.ui.control.Label
        ValMuscleMREStiffVol matlab.ui.control.Label
        ValFatMREStiffVol   matlab.ui.control.Label
        ValSegConf          matlab.ui.control.Label
        ValCoverage         matlab.ui.control.Label

        % Bottom bar
        BottomPanel         matlab.ui.container.Panel
        BottomGrid          matlab.ui.container.GridLayout
        LblStatusMsg        matlab.ui.control.Label
        LblCursorVal        matlab.ui.control.Label
    end

    % =====================================================================
    %  APP DATA
    % =====================================================================
    properties (Access = public)
        AppData struct = struct( ...
            'Exam',         [], ...
            'Selection',    [], ...
            'MATPath',      '', ...
            'ExamPath',     '', ...
            'Localizer',    [], ...   % from loc_loadLocalizer
            'Dixon',        [], ...   % from seg_buildDixonVolume
            'MRE',          [], ...   % struct: M,W,W_raw,S,LapC,H
            'L12',          [], ...   % legacy (kept for loc_propagateToSpace compat)
            'L12_Dixon',    [], ...   % legacy
            'L12_MRE',      [], ...   % legacy
            'L1_CorRow',    NaN, ...  % legacy (T12)
            'L2_CorRow',    NaN, ...  % legacy (L3)
            'L1_SagRow',    NaN, ...  % legacy
            'L2_SagRow',    NaN, ...  % legacy
            'LM', struct( ...
                'T9T10',  struct('CorRow',NaN,'SagRow',NaN), ...
                'T10T11', struct('CorRow',NaN,'SagRow',NaN), ...
                'T11T12', struct('CorRow',NaN,'SagRow',NaN), ...
                'T12L1',  struct('CorRow',NaN,'SagRow',NaN), ...
                'L1L2',   struct('CorRow',NaN,'SagRow',NaN), ...
                'L2L3',   struct('CorRow',NaN,'SagRow',NaN), ...
                'L3L4',   struct('CorRow',NaN,'SagRow',NaN)), ...
            'LM_Dixon', struct( ...   % slice indices after confirmLandmarks
                'T9T10',  struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T10T11', struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T11T12', struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T12L1',  struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L1L2',   struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L2L3',   struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L3L4',   struct('SliceIdx',NaN,'Dist_mm',NaN)), ...
            'LM_MRE', struct( ...
                'T9T10',  struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T10T11', struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T11T12', struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'T12L1',  struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L1L2',   struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L2L3',   struct('SliceIdx',NaN,'Dist_mm',NaN), ...
                'L3L4',   struct('SliceIdx',NaN,'Dist_mm',NaN)), ...
            'ActiveLM',     '', ...   % which landmark is being placed
            'LocHoverAxes', '', ...   % 'cor' | 'sag' | '' for scroll-wheel routing
            'AwaitingClick','', ...   % legacy click-arm flag
            'CorSlice',     1, ...    % current coronal slice index
            'SagSlice',     1, ...    % current sagittal slice index
            'DixonSlice',   1, ...
            'MRESlice',     1, ...
            'MREPhase',     1, ...
            'MREPlaying',   false, ...
            'MRETimer',     [], ...
            'MREPlaybackWasOnBeforeROI', false, ...
            'MRERefreshBusy', false, ...
            'MREROIBusy',  false, ...
            'StiffCLim',    [0 8], ...
            'WaveMax',      2000, ... % default processed-wave half-range (W/L)
            'DixonContrast', 'PDFF', ...  % 'PDFF'|'Water'|'Fat'|'T2star'|'InPhase'|'OutPhase'
            'DixonCmap',    'hot', ...   % colormap name for current contrast
            'DixonClimMin', 0, ...       % display range min
            'DixonClimMax', 100, ...     % display range max
            'DispWave',     [], ...   % current processed-wave slice for cursor readout
            'DispWaveRaw',  [], ...   % current raw-wave slice
            'DispStiff',    [], ...   % current stiffness slice
            'DispDixon',    [], ...   % current Dixon PDFF slice (PDFF panel)
            'DispDixonIP',  [], ...   % current Dixon Water/InPhase slice
            'DispDixonOP',  [], ...   % current Dixon Fat/OutPhase slice
            'ShowConfMask', false, ...
            'ConfThresh',   0.50, ...
            'MREObjectConf', struct('LiverMRE',0.90,'SpleenMRE',0.75,'MuscleMRE',0.50,'FatMRE',0.90), ...
            'MRETechFailure', struct('LiverMRE',false,'SpleenMRE',false,'MuscleMRE',false,'FatMRE',false), ...
            'MREROIActive', false, ...
            'MREROIName',   '', ...
            'MREROISlice',  NaN, ...
            'MREROIOuterMask', [], ...
            'MREROIBaseInnerMask', [], ...
            'MREROIConfMask', [], ...
            'MREROIFinalMask', [], ...
            'MREROIErodePx', 2, ...
            'MRETargetAxis', 'mag', ...
            'MREROIDrawing', false, ...
            'MREROIPopupFig',   [], ...      % magnified drawing popup figure
            'DixonROIActive',   false, ...
            'DixonROIName',     '', ...
            'DixonROISlice',    NaN, ...
            'DixonROIOuterMask', [], ...
            'DixonROIFinalMask', [], ...
            'DixonROIErodePx',  2, ...
            'DixonROIDrawing',  false, ...
            'DixonROIPopupFig', [], ...      % magnified drawing popup figure
            'DixonTargetAxis',  'pdff', ...  % 'pdff'|'water'|'fat'
            'ROIVertices',      47, ...      % polygon vertex count after freehand
            'ROIs',         struct( ...   % all ROI masks
                'LiverDixon',   struct('Slices',struct()), ...
                'SpleenDixon',  struct('Slices',struct()), ...
                'MuscleDixon',  struct('Slices',struct()), ...
                'PsoasDixon',   struct('Slices',struct()), ...  % psoas muscle
                'TrunkDixon',   struct('Slices',struct()), ...  % non-psoas trunk skeletal muscle
                'SATDixon',     struct('Slices',struct()), ...  % subcutaneous adipose tissue
                'VATDixon',     struct('Slices',struct()), ...  % visceral adipose tissue
                'FatDixon',     struct('Slices',struct()), ...  % legacy (kept for compatibility)
                'LiverMRE',     struct('Slices',struct()), ...
                'SpleenMRE',    struct('Slices',struct()), ...
                'MuscleMRE',    struct('Slices',struct()), ...
                'FatMRE',       struct('Slices',struct())), ...
            'WaterWin',     [0 0], ...   % [lo hi] for Water panel; [0 0] = auto
            'FatWin',       [0 0], ...   % [lo hi] for Fat panel; [0 0] = auto
            'CorWin',       [0 0], ...   % [lo hi] for Coronal panel; [0 0] = auto
            'SagWin',       [0 0])
    end

    % =====================================================================
    %  COMPONENT CREATION
    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position  = [20 20 1440 860];
            app.UIFigure.Name      = 'Abdominal MRI/MRE Analysis (Version 1.0, M.Y., April 17, 2026)';
            app.UIFigure.Resize    = 'on';
            app.UIFigure.CloseRequestFcn = @(~,~) app.onClose();
            app.UIFigure.WindowKeyPressFcn = @(~,e) app.onKeyPress(e);

            createMenus(app);

            % Outer grid: toolbar | body | bottom
            outer = uigridlayout(app.UIFigure, [3 1]);
            outer.RowHeight   = {52,'1x',56};
            outer.ColumnWidth = {'1x'};
            outer.Padding     = [0 0 0 0];
            outer.RowSpacing  = 0;

            createToolbar(app, outer);

            % Body: left | center | right
            app.BodyGrid = uigridlayout(outer,[1 3]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {260,'1x',310};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;

            createLeftPanel(app);
            createCenterPanel(app);
            createRightPanel(app);
            createBottomBar(app, outer);
        end

        % -----------------------------------------------------------------
        function createMenus(app)
            app.FileMenu = uimenu(app.UIFigure,'Text','File');
            uimenu(app.FileMenu,'Text','Load Study (DICOM)...', ...
                'Accelerator','O','MenuSelectedFcn',@(~,~)app.loadStudy());
            uimenu(app.FileMenu,'Text','Save Session...','Separator','on', ...
                'Accelerator','S','MenuSelectedFcn',@(~,~)app.saveSession());
            uimenu(app.FileMenu,'Text','Load Session...', ...
                'MenuSelectedFcn',@(~,~)app.loadSession());
            uimenu(app.FileMenu,'Text','Exit','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.onClose());

            app.ViewMenu = uimenu(app.UIFigure,'Text','View');
            uimenu(app.ViewMenu,'Text','Colormap: Gray (images)', ...
                'MenuSelectedFcn',@(~,~)app.setColormap('gray'));
            uimenu(app.ViewMenu,'Text','Colormap: Hot (PDFF/stiffness)', ...
                'MenuSelectedFcn',@(~,~)app.setColormap('hot'));
            uimenu(app.ViewMenu,'Text','Stiffness 0-8 kPa','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.setStiffScale([0 8]));
            uimenu(app.ViewMenu,'Text','Stiffness 0-20 kPa', ...
                'MenuSelectedFcn',@(~,~)app.setStiffScale([0 20]));
            uimenu(app.ViewMenu,'Text','Stiffness custom...', ...
                'MenuSelectedFcn',@(~,~)app.setStiffScaleCustom());

            app.ExportMenu = uimenu(app.UIFigure,'Text','Export');
            uimenu(app.ExportMenu,'Text','Export ROI Masks (MAT)...', ...
                'MenuSelectedFcn',@(~,~)app.exportROIs());
            uimenu(app.ExportMenu,'Text','Export Report (PDF)...', ...
                'MenuSelectedFcn',@(~,~)app.exportPDF());
            uimenu(app.ExportMenu,'Text','Export PDFF Radiomics CSV...','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.exportPDFFRadiomicsCSV());
            uimenu(app.ExportMenu,'Text','Export MRE Radiomics CSV...', ...
                'MenuSelectedFcn',@(~,~)app.exportMRERadiomicsCSV());

            app.HelpMenu = uimenu(app.UIFigure,'Text','Help');
            uimenu(app.HelpMenu,'Text','About', ...
                'MenuSelectedFcn',@(~,~)app.showAbout());
            uimenu(app.HelpMenu,'Text','Radiomic Features Reference...','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.showRadiomicsHelp());
        end

        % -----------------------------------------------------------------
        function createToolbar(app, parentGrid)
            app.ToolbarPanel = uipanel(parentGrid);
            app.ToolbarPanel.Layout.Row    = 1;
            app.ToolbarPanel.Layout.Column = 1;
            app.ToolbarPanel.BorderType    = 'none';
            app.ToolbarPanel.BackgroundColor = [0.93 0.93 0.93];

            tg = uigridlayout(app.ToolbarPanel,[1 4]);
            tg.ColumnWidth   = {150,160,8,'1x'};
            tg.RowHeight     = {'1x'};
            tg.Padding       = [8 7 8 7];
            tg.ColumnSpacing = 6;

            app.BtnLoadStudy = mkBtn(tg,1,'Load Study', ...
                [0.18 0.44 0.74],[1 1 1],14);
            app.BtnLoadStudy.ButtonPushedFcn = @(~,~)app.loadStudy();
            app.BtnLoadStudy.Tooltip = 'Load DICOM exam, select series, build MAT';

            app.BtnConfirmL12 = mkBtn(tg,2,'Confirm T9-L4', ...
                [0.58 0.29 0.07],[1 1 1],14);
            app.BtnConfirmL12.ButtonPushedFcn = @(~,~)app.confirmL12();
            app.BtnConfirmL12.Tooltip = 'Confirm T9-L4 levels and propagate to Dixon/MRE';
            app.BtnConfirmL12.Enable  = 'off';

            sep = uilabel(tg); sep.Layout.Column=3;
            sep.Text='|'; sep.FontColor=[0.7 0.7 0.7];
            sep.HorizontalAlignment='center';

            app.LblPatientInfo = uilabel(tg);
            app.LblPatientInfo.Layout.Column = 4;
            app.LblPatientInfo.Text      = 'No study loaded';
            app.LblPatientInfo.FontSize  = 13;
            app.LblPatientInfo.FontColor = [0.45 0.45 0.45];
            app.LblPatientInfo.FontAngle = 'italic';
        end

        % -----------------------------------------------------------------
        function createLeftPanel(app)
            app.LeftPanel = uipanel(app.BodyGrid,'Title','Study Browser', ...
                'FontSize',13,'FontWeight','bold');
            app.LeftPanel.Layout.Column = 1;

            lg = uigridlayout(app.LeftPanel,[2 1]);
            lg.RowHeight={'1x',24}; lg.Padding=[4 4 4 4]; lg.RowSpacing=4;

            app.StudyTree = uitree(lg,'checkbox');
            app.StudyTree.Layout.Row=1; app.StudyTree.FontSize=11;
            app.StudyTree.SelectionChangedFcn = @(~,e)app.onStudySelect(e);

            sn = uitreenode(app.StudyTree,'Text','Load a study to begin');
            sn.NodeData = [];
            expand(sn,'all');

            app.LblStudyStats = uilabel(lg);
            app.LblStudyStats.Layout.Row=2;
            app.LblStudyStats.Text='Ready';
            app.LblStudyStats.FontSize=10; app.LblStudyStats.FontColor=[0.5 0.5 0.5];
            app.LblStudyStats.HorizontalAlignment='center';
        end

        % -----------------------------------------------------------------
        function createCenterPanel(app)
            % Place the tab group directly in the body grid so it fills
            % the full center column without any intermediate panel.
            app.ImageTabGroup = uitabgroup(app.BodyGrid);
            app.ImageTabGroup.Layout.Row    = 1;
            app.ImageTabGroup.Layout.Column = 2;
            app.ImageTabGroup.FontSize = 13;
            app.ImageTabGroup.SelectionChangedFcn = @(~,e)app.onTabChange(e);

            createLocalizerTab(app);
            createDixonTab(app);
            createMRETab(app);
            createResultsTab(app);
        end

        % ── LOCALIZER TAB ────────────────────────────────────────────────
        function createLocalizerTab(app)
            app.LocTab = uitab(app.ImageTabGroup,'Title','Localizer / Disc Levels');

            % Grid: images row | W/L row | slider row | landmark buttons row | status row
            app.LocGrid = uigridlayout(app.LocTab,[5 2]);
            app.LocGrid.RowHeight    = {'1x',24,32,36,22};
            app.LocGrid.ColumnWidth  = {'1x','1x'};
            app.LocGrid.Padding      = [6 6 6 6];
            app.LocGrid.RowSpacing   = 4;
            app.LocGrid.ColumnSpacing = 8;

            % Coronal axis
            app.AxLocCoronal = uiaxes(app.LocGrid);
            app.AxLocCoronal.Layout.Row=1; app.AxLocCoronal.Layout.Column=1;
            setupDarkAxes(app.AxLocCoronal,'Coronal  (disc level identification)');

            % Sagittal axis
            app.AxLocSagittal = uiaxes(app.LocGrid);
            app.AxLocSagittal.Layout.Row=1; app.AxLocSagittal.Layout.Column=2;
            setupDarkAxes(app.AxLocSagittal,'Sagittal  (disc level verification)');

            % W/L controls (row 2)
            corWLrow = uigridlayout(app.LocGrid,[1 6]);
            corWLrow.Layout.Row=2; corWLrow.Layout.Column=1;
            corWLrow.ColumnWidth = {'1x',40,10,40,34,34}; corWLrow.Padding=[2 1 2 1]; corWLrow.ColumnSpacing=3;
            lblCorWL = uilabel(corWLrow); lblCorWL.Layout.Column=1;
            lblCorWL.Text='Cor W/L:'; lblCorWL.FontSize=9; lblCorWL.HorizontalAlignment='right';
            app.EdtCorWinLo = uieditfield(corWLrow,'numeric');
            app.EdtCorWinLo.Layout.Column=2; app.EdtCorWinLo.Value=0; app.EdtCorWinLo.FontSize=9;
            app.EdtCorWinLo.Tooltip='Coronal display min (0=auto)';
            app.EdtCorWinLo.ValueChangedFcn = @(~,~)app.refreshLocCoronal();
            lblCorDash = uilabel(corWLrow); lblCorDash.Layout.Column=3;
            lblCorDash.Text=char(8211); lblCorDash.FontSize=10; lblCorDash.HorizontalAlignment='center';
            app.EdtCorWinHi = uieditfield(corWLrow,'numeric');
            app.EdtCorWinHi.Layout.Column=4; app.EdtCorWinHi.Value=0; app.EdtCorWinHi.FontSize=9;
            app.EdtCorWinHi.Tooltip='Coronal display max (0=auto)';
            app.EdtCorWinHi.ValueChangedFcn = @(~,~)app.refreshLocCoronal();
            btnCorA = uibutton(corWLrow,'push'); btnCorA.Layout.Column=5; btnCorA.Text='A'; btnCorA.FontSize=9;
            btnCorA.Tooltip='Auto coronal window'; btnCorA.ButtonPushedFcn = @(~,~)app.autoLocWin('cor');

            sagWLrow = uigridlayout(app.LocGrid,[1 6]);
            sagWLrow.Layout.Row=2; sagWLrow.Layout.Column=2;
            sagWLrow.ColumnWidth = {'1x',40,10,40,34,34}; sagWLrow.Padding=[2 1 2 1]; sagWLrow.ColumnSpacing=3;
            lblSagWL = uilabel(sagWLrow); lblSagWL.Layout.Column=1;
            lblSagWL.Text='Sag W/L:'; lblSagWL.FontSize=9; lblSagWL.HorizontalAlignment='right';
            app.EdtSagWinLo = uieditfield(sagWLrow,'numeric');
            app.EdtSagWinLo.Layout.Column=2; app.EdtSagWinLo.Value=0; app.EdtSagWinLo.FontSize=9;
            app.EdtSagWinLo.Tooltip='Sagittal display min (0=auto)';
            app.EdtSagWinLo.ValueChangedFcn = @(~,~)app.refreshLocSagittal();
            lblSagDash = uilabel(sagWLrow); lblSagDash.Layout.Column=3;
            lblSagDash.Text=char(8211); lblSagDash.FontSize=10; lblSagDash.HorizontalAlignment='center';
            app.EdtSagWinHi = uieditfield(sagWLrow,'numeric');
            app.EdtSagWinHi.Layout.Column=4; app.EdtSagWinHi.Value=0; app.EdtSagWinHi.FontSize=9;
            app.EdtSagWinHi.Tooltip='Sagittal display max (0=auto)';
            app.EdtSagWinHi.ValueChangedFcn = @(~,~)app.refreshLocSagittal();
            btnSagA = uibutton(sagWLrow,'push'); btnSagA.Layout.Column=5; btnSagA.Text='A'; btnSagA.FontSize=9;
            btnSagA.Tooltip='Auto sagittal window'; btnSagA.ButtonPushedFcn = @(~,~)app.autoLocWin('sag');

            % Sliders (row 3)
            corSliderGrid = uigridlayout(app.LocGrid,[1 3]);
            corSliderGrid.Layout.Row=3; corSliderGrid.Layout.Column=1;
            corSliderGrid.ColumnWidth={60,'1x',40}; corSliderGrid.Padding=[0 0 0 0];
            lc = uilabel(corSliderGrid); lc.Layout.Column=1;
            lc.Text='Coronal:'; lc.FontSize=12;
            app.SldrLocCor = uislider(corSliderGrid);
            app.SldrLocCor.Layout.Column=2; app.SldrLocCor.Limits=[1 9];
            app.SldrLocCor.Value=5; app.SldrLocCor.MajorTicks=[];
            app.SldrLocCor.MinorTicks=[];
            app.SldrLocCor.ValueChangedFcn = @(src,~)app.onLocCorSlide(src);
            app.LblLocCor = uilabel(corSliderGrid); app.LblLocCor.Layout.Column=3;
            app.LblLocCor.Text='5'; app.LblLocCor.FontSize=12;
            app.LblLocCor.HorizontalAlignment='center';

            sagSliderGrid = uigridlayout(app.LocGrid,[1 3]);
            sagSliderGrid.Layout.Row=3; sagSliderGrid.Layout.Column=2;
            sagSliderGrid.ColumnWidth={60,'1x',40}; sagSliderGrid.Padding=[0 0 0 0];
            ls = uilabel(sagSliderGrid); ls.Layout.Column=1;
            ls.Text='Sagittal:'; ls.FontSize=12;
            app.SldrLocSag = uislider(sagSliderGrid);
            app.SldrLocSag.Layout.Column=2; app.SldrLocSag.Limits=[1 9];
            app.SldrLocSag.Value=5; app.SldrLocSag.MajorTicks=[];
            app.SldrLocSag.MinorTicks=[];
            app.SldrLocSag.ValueChangedFcn = @(src,~)app.onLocSagSlide(src);
            app.LblLocSag = uilabel(sagSliderGrid); app.LblLocSag.Layout.Column=3;
            app.LblLocSag.Text='5'; app.LblLocSag.FontSize=12;
            app.LblLocSag.HorizontalAlignment='center';

            % ── Landmark buttons row (row 4, spanning both columns) ───────
            % Seven disc levels: T9/10, T10/11, T11/12, T12/L1, L1/2, L2/3, L3/4
            lmNames  = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            lmLabels = {'T9/10','T10/11','T11/12','T12/L1','L1/2','L2/3','L3/4'};
            lmColors = {[0.55 0.05 0.05],[0.75 0.10 0.10],[0.88 0.35 0.08],[0.92 0.65 0.05],[0.30 0.72 0.30],[0.15 0.58 0.88],[0.50 0.20 0.85]};
            lmBtnProps = {'BtnMarkLM_T9T10','BtnMarkLM_T10T11','BtnMarkLM_T11T12','BtnMarkLM_T12L1','BtnMarkLM_L1L2','BtnMarkLM_L2L3','BtnMarkLM_L3L4'};

            btnGrid = uigridlayout(app.LocGrid,[1 10]);
            btnGrid.Layout.Row=4; btnGrid.Layout.Column=[1 2];
            btnGrid.ColumnWidth = {80,80,80,80,80,80,80,80,'1x',80};
            btnGrid.Padding=[0 2 0 2]; btnGrid.ColumnSpacing=4;

            for ki = 1:7
                b = uibutton(btnGrid,'push');
                b.Layout.Column = ki;
                b.Text = lmLabels{ki};
                b.FontSize = 11; b.FontWeight = 'bold';
                b.BackgroundColor = lmColors{ki};
                b.FontColor = [1 1 1];
                b.Tooltip = sprintf('Mark %s disc level — click, then click in coronal or sagittal image', lmLabels{ki});
                lmNameCap = lmNames{ki};
                b.ButtonPushedFcn = @(~,~)app.placeLandmark(lmNameCap);
                app.(lmBtnProps{ki}) = b;
            end

            app.BtnClearL12 = uibutton(btnGrid,'push');
            app.BtnClearL12.Layout.Column = 8;
            app.BtnClearL12.Text = 'Clear all';
            app.BtnClearL12.FontSize = 11;
            app.BtnClearL12.ButtonPushedFcn = @(~,~)app.clearLandmarks();

            % Status row (row 5)
            app.LblL12Status = uilabel(app.LocGrid);
            app.LblL12Status.Layout.Row=5; app.LblL12Status.Layout.Column=[1 2];
            app.LblL12Status.Text='Scroll wheel over image to navigate.  Click a disc button, then click in coronal or sagittal image.';
            app.LblL12Status.FontSize=11; app.LblL12Status.FontColor=[0.4 0.4 0.4];

            % Scroll-wheel and mouse-hover tracking (figure-level, registered once)
            app.UIFigure.WindowScrollWheelFcn   = @(~,e)app.onScrollWheel(e);
            app.UIFigure.WindowButtonMotionFcn  = @(~,~)app.onMouseMove();
        end

        % ── DIXON TAB ────────────────────────────────────────────────────
        function createDixonTab(app)
            app.DixonTab = uitab(app.ImageTabGroup,'Title','Dixon / Body Comp');

            app.DixonGrid = uigridlayout(app.DixonTab,[1 2]);
            app.DixonGrid.ColumnWidth  = {'1x',190};
            app.DixonGrid.RowHeight    = {'1x'};
            app.DixonGrid.Padding      = [4 4 4 4];
            app.DixonGrid.ColumnSpacing = 6;

            % Image area: header row + PDFF controls + image panels + landmark jump bar.
            imgArea = uipanel(app.DixonGrid,'BorderType','none');
            imgArea.Layout.Column = 1;
            imgG = uigridlayout(imgArea,[4 1]);
            imgG.RowHeight   = {28,30,'1x',42};
            imgG.ColumnWidth = {'1x'};
            imgG.Padding     = [0 0 0 0];
            imgG.RowSpacing  = 3;

            % Row 1: static panel labels + info.
            contRow = uigridlayout(imgG,[1 3]);
            contRow.Layout.Row=1;
            contRow.ColumnWidth = {180,'1x',140};
            contRow.Padding=[0 2 0 2]; contRow.ColumnSpacing=6;
            lcon = uilabel(contRow); lcon.Layout.Column=1;
            lcon.Text='PDFF | Water | Fat'; lcon.FontSize=13; lcon.FontWeight='bold';
            app.DdlDixonContrast = uidropdown(contRow);
            app.DdlDixonContrast.Layout.Column=2;
            app.DdlDixonContrast.Items     = {'PDFF'};
            app.DdlDixonContrast.ItemsData = {'PDFF'};
            app.DdlDixonContrast.Value     = 'PDFF';
            app.DdlDixonContrast.Visible   = 'off';
            app.DdlDixonContrast.ValueChangedFcn = @(~,~)app.onDixonContrastChange();
            app.LblDixonInfo = uilabel(contRow); app.LblDixonInfo.Layout.Column=3;
            app.LblDixonInfo.Text='';
            app.LblDixonInfo.FontSize=10; app.LblDixonInfo.FontColor=[0.5 0.5 0.5];

            % Row 2: PDFF colormap + display range controls.
            scaleRow = uigridlayout(imgG,[1 7]);
            scaleRow.Layout.Row=2;
            scaleRow.ColumnWidth = {65,90,40,50,10,50,50};
            scaleRow.Padding=[0 1 0 1]; scaleRow.ColumnSpacing=4;
            lcm = uilabel(scaleRow); lcm.Layout.Column=1;
            lcm.Text='PDFF map:'; lcm.FontSize=11; lcm.FontWeight='bold';
            app.DdlDixonCmap = uidropdown(scaleRow);
            app.DdlDixonCmap.Layout.Column=2;
            app.DdlDixonCmap.Items     = {'Hot','Jet','Turbo'};
            app.DdlDixonCmap.ItemsData = {'hot','jet','turbo'};
            app.DdlDixonCmap.Value     = 'hot';
            app.DdlDixonCmap.FontSize  = 11;
            app.DdlDixonCmap.ValueChangedFcn = @(~,~)app.onDixonScaleChange();
            lrng = uilabel(scaleRow); lrng.Layout.Column=3;
            lrng.Text='Range:'; lrng.FontSize=11; lrng.FontWeight='bold';
            app.EdtDixonMin = uieditfield(scaleRow,'numeric');
            app.EdtDixonMin.Layout.Column=4; app.EdtDixonMin.Value=0;
            app.EdtDixonMin.FontSize=11;
            app.EdtDixonMin.ValueChangedFcn = @(~,~)app.onDixonScaleChange();
            lto = uilabel(scaleRow); lto.Layout.Column=5;
            lto.Text='–'; lto.FontSize=12; lto.HorizontalAlignment='center';
            app.EdtDixonMax = uieditfield(scaleRow,'numeric');
            app.EdtDixonMax.Layout.Column=6; app.EdtDixonMax.Value=100;
            app.EdtDixonMax.FontSize=11;
            app.EdtDixonMax.ValueChangedFcn = @(~,~)app.onDixonScaleChange();
            btnAuto = uibutton(scaleRow,'push');
            btnAuto.Layout.Column=7; btnAuto.Text='Auto';
            btnAuto.FontSize=11;
            btnAuto.ButtonPushedFcn = @(~,~)app.onDixonAutoScale();

            % Row 3: two-column display.
            % Left  = PDFF image + Water W/L + Fat W/L (stacked below).
            % Right = Water image + nav bar + Fat image (maximised).
            panelGrid = uigridlayout(imgG,[1 2]);
            panelGrid.Layout.Row=3;
            panelGrid.ColumnWidth={'1x','1x'};
            panelGrid.Padding=[0 0 0 0]; panelGrid.ColumnSpacing=6;

            % Left column: PDFF on top, then compact W/L rows below.
            leftPnl = uipanel(panelGrid,'BorderType','none');
            leftPnl.Layout.Column = 1;
            leftG = uigridlayout(leftPnl,[3 1]);
            leftG.RowHeight = {'1x',22,22};
            leftG.ColumnWidth = {'1x'};
            leftG.Padding    = [0 0 0 0];
            leftG.RowSpacing = 2;

            app.AxDixonPDFF = uiaxes(leftG);
            app.AxDixonPDFF.Layout.Row = 1;
            setupDarkAxes(app.AxDixonPDFF,'PDFF (%)');
            app.AxDixonPDFF.ButtonDownFcn = @(~,~)app.onDixonPanelClick('pdff');

            % Water W/L row (under PDFF)
            wWLrow = uigridlayout(leftG,[1 5]);
            wWLrow.Layout.Row = 2;
            wWLrow.ColumnWidth = {'1x',36,10,36,36}; wWLrow.Padding=[2 1 2 1]; wWLrow.ColumnSpacing=2;
            lblWaterWL = uilabel(wWLrow); lblWaterWL.Layout.Column=1;
            lblWaterWL.Text='Water W/L:'; lblWaterWL.FontSize=9; lblWaterWL.HorizontalAlignment='right';
            app.EdtWaterWinLo = uieditfield(wWLrow,'numeric');
            app.EdtWaterWinLo.Layout.Column=2; app.EdtWaterWinLo.Value=0; app.EdtWaterWinLo.FontSize=9;
            app.EdtWaterWinLo.Tooltip='Water panel display min (0=auto)';
            app.EdtWaterWinLo.ValueChangedFcn = @(~,~)refreshDixon(app);
            lblWDash = uilabel(wWLrow); lblWDash.Layout.Column=3;
            lblWDash.Text=char(8211); lblWDash.FontSize=10; lblWDash.HorizontalAlignment='center';
            app.EdtWaterWinHi = uieditfield(wWLrow,'numeric');
            app.EdtWaterWinHi.Layout.Column=4; app.EdtWaterWinHi.Value=0; app.EdtWaterWinHi.FontSize=9;
            app.EdtWaterWinHi.Tooltip='Water panel display max (0=auto)';
            app.EdtWaterWinHi.ValueChangedFcn = @(~,~)refreshDixon(app);
            btnWAuto = uibutton(wWLrow,'push');
            btnWAuto.Layout.Column=5; btnWAuto.Text='A'; btnWAuto.FontSize=9;
            btnWAuto.Tooltip='Auto water window';
            btnWAuto.ButtonPushedFcn = @(~,~)app.autoWaterFatWin('water');

            % Fat W/L row (under Water W/L)
            fWLrow = uigridlayout(leftG,[1 5]);
            fWLrow.Layout.Row = 3;
            fWLrow.ColumnWidth = {'1x',36,10,36,36}; fWLrow.Padding=[2 1 2 1]; fWLrow.ColumnSpacing=2;
            lblFatWL = uilabel(fWLrow); lblFatWL.Layout.Column=1;
            lblFatWL.Text='Fat W/L:'; lblFatWL.FontSize=9; lblFatWL.HorizontalAlignment='right';
            app.EdtFatWinLo = uieditfield(fWLrow,'numeric');
            app.EdtFatWinLo.Layout.Column=2; app.EdtFatWinLo.Value=0; app.EdtFatWinLo.FontSize=9;
            app.EdtFatWinLo.Tooltip='Fat panel display min (0=auto)';
            app.EdtFatWinLo.ValueChangedFcn = @(~,~)refreshDixon(app);
            lblFDash = uilabel(fWLrow); lblFDash.Layout.Column=3;
            lblFDash.Text=char(8211); lblFDash.FontSize=10; lblFDash.HorizontalAlignment='center';
            app.EdtFatWinHi = uieditfield(fWLrow,'numeric');
            app.EdtFatWinHi.Layout.Column=4; app.EdtFatWinHi.Value=0; app.EdtFatWinHi.FontSize=9;
            app.EdtFatWinHi.Tooltip='Fat panel display max (0=auto)';
            app.EdtFatWinHi.ValueChangedFcn = @(~,~)refreshDixon(app);
            btnFAuto = uibutton(fWLrow,'push');
            btnFAuto.Layout.Column=5; btnFAuto.Text='A'; btnFAuto.FontSize=9;
            btnFAuto.Tooltip='Auto fat window';
            btnFAuto.ButtonPushedFcn = @(~,~)app.autoWaterFatWin('fat');

            % Right column: Water (top) — Nav — Fat (bottom), full height.
            rightPnl = uipanel(panelGrid,'BorderType','none');
            rightPnl.Layout.Column = 2;
            rightG = uigridlayout(rightPnl,[3 1]);
            rightG.RowHeight   = {'1x',34,'1x'};
            rightG.ColumnWidth = {'1x'};
            rightG.Padding     = [0 0 0 0];
            rightG.RowSpacing  = 2;

            app.AxDixonIP = uiaxes(rightG);
            app.AxDixonIP.Layout.Row = 1;
            setupDarkAxes(app.AxDixonIP,'Water');
            app.AxDixonIP.ButtonDownFcn = @(~,~)app.onDixonPanelClick('water');

            % Nav row: Prev / slice label / Next
            navG = uigridlayout(rightG,[1 3]);
            navG.Layout.Row = 2;
            navG.ColumnWidth = {64,'1x',64};
            navG.Padding = [4 4 4 4]; navG.ColumnSpacing=10;

            prevBtnDix = uibutton(navG,'push');
            prevBtnDix.Layout.Column=1;
            prevBtnDix.Text='Prev'; prevBtnDix.FontSize=12; prevBtnDix.FontWeight='bold';
            prevBtnDix.BackgroundColor=[1.00 0.93 0.25]; prevBtnDix.FontColor=[0.75 0.10 0.10];
            prevBtnDix.Tooltip='Previous slice';
            prevBtnDix.ButtonPushedFcn = @(~,~)app.nudgeDixonSlice(-1);

            app.LblDixonSlice = uilabel(navG);
            app.LblDixonSlice.Layout.Column=2;
            app.LblDixonSlice.Text='1/1';
            app.LblDixonSlice.FontSize=12; app.LblDixonSlice.FontWeight='bold';
            app.LblDixonSlice.HorizontalAlignment='center';

            nextBtnDix = uibutton(navG,'push');
            nextBtnDix.Layout.Column=3;
            nextBtnDix.Text='Next'; nextBtnDix.FontSize=12; nextBtnDix.FontWeight='bold';
            nextBtnDix.BackgroundColor=[1.00 0.93 0.25]; nextBtnDix.FontColor=[0.75 0.10 0.10];
            nextBtnDix.Tooltip='Next slice';
            nextBtnDix.ButtonPushedFcn = @(~,~)app.nudgeDixonSlice(+1);

            app.AxDixonWater = uiaxes(rightG);
            app.AxDixonWater.Layout.Row = 3;
            setupDarkAxes(app.AxDixonWater,'Fat');
            app.AxDixonWater.ButtonDownFcn = @(~,~)app.onDixonPanelClick('fat');

            % Keep the legacy ROI drawing path anchored to the PDFF panel.
            app.AxDixon = app.AxDixonPDFF;

            % ── Row 4: Landmark jump bar ─────────────────────────────────
            lmJumpGrid = uigridlayout(imgG,[1 9]);
            lmJumpGrid.Layout.Row = 4;
            lmJumpGrid.Padding = [0 1 0 1]; lmJumpGrid.ColumnSpacing = 3;
            lmJumpGrid.ColumnWidth = {55,62,62,62,62,62,62,62,'1x'};
            ljLabel = uilabel(lmJumpGrid,'Text','Jump to:','FontSize',10, ...
                'FontColor',[0.45 0.45 0.45],'HorizontalAlignment','right');
            ljLabel.Layout.Column = 1;
            lmJNames  = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            lmJLabels = {'T9/10','T10/11','T11/12','T12/L1','L1/2','L2/3','L3/4'};
            lmJColors = {[0.55 0.05 0.05],[0.75 0.10 0.10],[0.88 0.35 0.08],[0.92 0.65 0.05],[0.30 0.72 0.30],[0.15 0.58 0.88],[0.50 0.20 0.85]};
            lmJProps  = {'BtnJumpLM_T9T10','BtnJumpLM_T10T11','BtnJumpLM_T11T12','BtnJumpLM_T12L1','BtnJumpLM_L1L2','BtnJumpLM_L2L3','BtnJumpLM_L3L4'};
            for ki = 1:7
                jb = uibutton(lmJumpGrid,'push');
                jb.Layout.Column = ki + 1;
                jb.Text = lmJLabels{ki};
                jb.FontSize = 10; jb.FontWeight = 'bold';
                jb.BackgroundColor = lmJColors{ki} * 0.75 + 0.25;
                jb.FontColor = lmJColors{ki} * 0.4;
                jb.Enable = 'off';
                jb.Tooltip = sprintf('Jump Dixon to %s disc level', lmJLabels{ki});
                lmJNameCap = lmJNames{ki};
                jb.ButtonPushedFcn = @(~,~)app.jumpDixonToLandmark(lmJNameCap);
                app.(lmJProps{ki}) = jb;
            end

            % ROI panel (right column) — Liver / Spleen / Muscle / SAT / VAT workflow
            roiPnl = uipanel(app.DixonGrid,'Title','Dixon ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            roiPnl.Layout.Column = 2;
            rg = uigridlayout(roiPnl,[12 1]);
            rg.RowHeight = {20,36,36,36,36,36,36,36,22,20,'1x',36};
            rg.Padding=[4 4 4 4]; rg.RowSpacing=4;

            hdr = uilabel(rg,'Text','Click organ, then F/D on image:','FontSize',10, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);
            hdr.Layout.Row = 1;

            app.BtnROI_LiverDixon = roiBtn(rg,2,'Liver', ...
                [0.15 0.75 0.15],[1 1 1]);
            app.BtnROI_LiverDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('LiverDixon');

            app.BtnROI_SpleenDixon = roiBtn(rg,3,'Spleen', ...
                [0.15 0.55 0.90],[1 1 1]);
            app.BtnROI_SpleenDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('SpleenDixon');

            app.BtnROI_PsoasDixon = roiBtn(rg,4,'Psoas Muscle', ...
                [0.95 0.55 0.15],[1 1 1]);
            app.BtnROI_PsoasDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('PsoasDixon');

            app.BtnROI_TrunkDixon = roiBtn(rg,5,'Trunk Muscle', ...
                [0.85 0.40 0.05],[1 1 1]);
            app.BtnROI_TrunkDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('TrunkDixon');

            % Keep legacy Muscle button hidden in row 8 (for backward-compat code paths)
            app.BtnROI_MuscleDixon = roiBtn(rg,8,'Muscle (legacy)', ...
                [0.70 0.70 0.70],[0.3 0.3 0.3]);
            app.BtnROI_MuscleDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('MuscleDixon');
            app.BtnROI_MuscleDixon.Visible = 'off';

            app.BtnROI_SATDixon = roiBtn(rg,6,'SAT (subcut.)', ...
                [0.85 0.20 0.85],[1 1 1]);
            app.BtnROI_SATDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('SATDixon');

            app.BtnROI_VATDixon = roiBtn(rg,7,'VAT (visceral)', ...
                [0.85 0.80 0.00],[0 0 0]);
            app.BtnROI_VATDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('VATDixon');

            % Polygon vertex count (row 9, below organ buttons)
            vtxRowD = uigridlayout(rg,[1 3]);
            vtxRowD.Layout.Row = 9;
            vtxRowD.ColumnWidth = {'1x',52,10}; vtxRowD.Padding=[2 0 2 0]; vtxRowD.ColumnSpacing=3;
            uilabel(vtxRowD,'Text','Poly vertices:','FontSize',9, ...
                'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            app.EdtROIVerticesDixon = uieditfield(vtxRowD,'numeric');
            app.EdtROIVerticesDixon.Layout.Column = 2;
            app.EdtROIVerticesDixon.Limits = [3 500]; app.EdtROIVerticesDixon.Value = 47;
            app.EdtROIVerticesDixon.RoundFractionalValues = true; app.EdtROIVerticesDixon.FontSize = 10;
            app.EdtROIVerticesDixon.Tooltip = 'Vertices in the editable polygon after freehand draw (default 47)';
            app.EdtROIVerticesDixon.ValueChangedFcn = @(src,~)app.onROIVerticesChanged(src);

            workflowHdr = uilabel(rg,'Text','Hotkeys (after arming organ):','FontSize',9, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);
            workflowHdr.Layout.Row = 10;

            app.LblDixonROIInfo = uilabel(rg);
            app.LblDixonROIInfo.Layout.Row = 11;
            app.LblDixonROIInfo.Text = sprintf(['F = freehand → edit polygon → dbl-click confirm' char(10) ...
                'D = seed+auto on panel' char(10) ...
                'E/I = exclude/include' char(10) ...
                'Enter/A = accept    Esc = cancel']);
            app.LblDixonROIInfo.FontSize=10; app.LblDixonROIInfo.WordWrap='on';
            app.LblDixonROIInfo.FontColor=[0.40 0.40 0.40];

            app.BtnClearDixonROIs = roiBtn(rg,12,'Clear this slice', ...
                [0.72 0.72 0.72],[0.2 0.2 0.2]);
            app.BtnClearDixonROIs.ButtonPushedFcn = @(~,~)app.clearDixonSlice();
        end

        % ── MRE TAB ──────────────────────────────────────────────────────
        function createMRETab(app)
            app.MRETab = uitab(app.ImageTabGroup,'Title','MRE');

            app.MREGrid = uigridlayout(app.MRETab,[1 2]);
            app.MREGrid.ColumnWidth  = {'1x',180};
            app.MREGrid.RowHeight    = {'1x'};
            app.MREGrid.Padding      = [4 4 4 4];
            app.MREGrid.ColumnSpacing = 6;

            % Image area: 3 columns. The left column shows magnitude and raw
            % wave with slice navigation placed between them. The processed
            % wave and stiffness panels occupy the middle and right columns,
            % with dedicated color strips below and controls at the bottom.
            imgArea = uipanel(app.MREGrid,'BorderType','none');
            imgArea.Layout.Column = 1;
            imgG = uigridlayout(imgArea,[5 3]);
            imgG.RowHeight   = {'1x',42,'1x',66,56};
            imgG.ColumnWidth = {'1x','1x','1x'};
            imgG.Padding     = [0 0 0 0];
            imgG.ColumnSpacing = 4;
            imgG.RowSpacing    = 4;

            app.AxMREStiff = uiaxes(imgG);
            app.AxMREStiff.Layout.Row=[1 3]; app.AxMREStiff.Layout.Column=1;
            setupDarkAxes(app.AxMREStiff,'Stiffness (kPa)');
            colormap(app.AxMREStiff, mreStiffCmap());
            app.AxMREStiff.ButtonDownFcn = @(~,~)app.onMREPanelClick('stiff');

            app.AxMREWave = uiaxes(imgG);
            app.AxMREWave.Layout.Row=[1 3]; app.AxMREWave.Layout.Column=2;
            setupDarkAxes(app.AxMREWave,'Processed wave');
            colormap(app.AxMREWave, mreWaveCmap());
            app.AxMREWave.ButtonDownFcn = @(~,~)app.onMREPanelClick('proc');

            app.AxMREMag = uiaxes(imgG);
            app.AxMREMag.Layout.Row=1; app.AxMREMag.Layout.Column=3;
            setupDarkAxes(app.AxMREMag,'Magnitude');
            colormap(app.AxMREMag,'gray');
            app.AxMREMag.ButtonDownFcn = @(~,~)app.onMREPanelClick('mag');

            navG = uigridlayout(imgG,[1 3]);
            navG.Layout.Row = 2; navG.Layout.Column = 3;
            navG.ColumnWidth = {64,'1x',64};
            navG.Padding = [4 10 4 10];
            navG.ColumnSpacing = 10;

            prevBtn = uibutton(navG,'push');
            prevBtn.Layout.Column = 1;
            prevBtn.Text = 'Prev';
            prevBtn.FontSize = 12; prevBtn.FontWeight = 'bold'; prevBtn.BackgroundColor = [1.00 0.93 0.25]; prevBtn.FontColor = [0.75 0.10 0.10]; prevBtn.Tooltip = 'Previous slice';
            prevBtn.ButtonPushedFcn = @(~,~)app.nudgeMRESlice(-1);

            app.LblMRESlice = uilabel(navG);
            app.LblMRESlice.Layout.Column = 2;
            app.LblMRESlice.Text = '2/4';
            app.LblMRESlice.FontSize = 12;
            app.LblMRESlice.FontWeight = 'bold';
            app.LblMRESlice.HorizontalAlignment = 'center';

            nextBtn = uibutton(navG,'push');
            nextBtn.Layout.Column = 3;
            nextBtn.Text = 'Next';
            nextBtn.FontSize = 12; nextBtn.FontWeight = 'bold'; nextBtn.BackgroundColor = [1.00 0.93 0.25]; nextBtn.FontColor = [0.75 0.10 0.10]; nextBtn.Tooltip = 'Next slice';
            nextBtn.ButtonPushedFcn = @(~,~)app.nudgeMRESlice(1);

            app.AxMRERawWave = uiaxes(imgG);
            app.AxMRERawWave.Layout.Row=3; app.AxMRERawWave.Layout.Column=3;
            setupDarkAxes(app.AxMRERawWave,'Raw wave');
            colormap(app.AxMRERawWave,'gray');
            app.AxMRERawWave.ButtonDownFcn = @(~,~)app.onMREPanelClick('raw');

            app.AxMREStiffBar = uiaxes(imgG);
            app.AxMREStiffBar.Layout.Row = 4; app.AxMREStiffBar.Layout.Column = 1;
            setupColorStripAxes(app.AxMREStiffBar);

            app.AxMREWaveBar = uiaxes(imgG);
            app.AxMREWaveBar.Layout.Row = 4; app.AxMREWaveBar.Layout.Column = 2;
            setupColorStripAxes(app.AxMREWaveBar);

            ctrlG = uigridlayout(imgG,[1 8]);
            ctrlG.Layout.Row=5; ctrlG.Layout.Column=[1 3];
            ctrlG.ColumnWidth={92,64,64,80,80,88,24,64};
            ctrlG.Padding=[0 4 0 4];

            app.BtnMREPlay = uibutton(ctrlG,'push');
            app.BtnMREPlay.Layout.Column=1;
            app.BtnMREPlay.Text='▶ Play wave';
            app.BtnMREPlay.FontSize=12; app.BtnMREPlay.FontWeight='bold';
            app.BtnMREPlay.BackgroundColor=[0.18 0.60 0.34];
            app.BtnMREPlay.FontColor=[1 1 1];
            app.BtnMREPlay.ButtonPushedFcn = @(~,~)app.toggleMREPlay();

            wlbl = uilabel(ctrlG); wlbl.Layout.Column=2;
            wlbl.Text='Waves W/L'; wlbl.FontSize=11; wlbl.HorizontalAlignment='right';

            app.EdtWaveMax = uieditfield(ctrlG,'numeric');
            app.EdtWaveMax.Layout.Column=3;
            app.EdtWaveMax.Value=2000; app.EdtWaveMax.Limits=[0 Inf];
            app.EdtWaveMax.FontSize=11;
            app.EdtWaveMax.Tooltip='Processed-wave half-range for display (default 2000). Raw wave uses automatic native scaling.';
            app.EdtWaveMax.ValueChangedFcn = @(src,~)app.onWaveMaxChange(src);

            app.BtnStiff8 = uibutton(ctrlG,'push');
            app.BtnStiff8.Layout.Column=4;
            app.BtnStiff8.Text='0-8 kPa';
            app.BtnStiff8.FontSize=12; app.BtnStiff8.FontWeight='bold';
            app.BtnStiff8.BackgroundColor=[0.25 0.55 0.85];
            app.BtnStiff8.FontColor=[1 1 1];
            app.BtnStiff8.ButtonPushedFcn = @(~,~)app.setStiffScale([0 8]);

            app.BtnStiff20 = uibutton(ctrlG,'push');
            app.BtnStiff20.Layout.Column=5;
            app.BtnStiff20.Text='0-20 kPa';
            app.BtnStiff20.FontSize=12;
            app.BtnStiff20.BackgroundColor=[0.70 0.88 0.70];
            app.BtnStiff20.FontColor=[0.1 0.3 0.1];
            app.BtnStiff20.ButtonPushedFcn = @(~,~)app.setStiffScale([0 20]);

            app.BtnConfMap = uibutton(ctrlG,'state');
            app.BtnConfMap.Layout.Column=6;
            app.BtnConfMap.Text='Conf. mask';
            app.BtnConfMap.FontSize=12;
            app.BtnConfMap.Value=false;
            app.BtnConfMap.Tooltip = 'Overlay low-confidence pixels on the stiffness map';
            app.BtnConfMap.ValueChangedFcn = @(~,~)app.toggleConfMask();

            clbl = uilabel(ctrlG); clbl.Layout.Column=7;
            clbl.Text='≥'; clbl.FontSize=12; clbl.HorizontalAlignment='center';

            app.EdtConfThresh = uieditfield(ctrlG,'numeric');
            app.EdtConfThresh.Layout.Column=8;
            app.EdtConfThresh.Limits = [0 1];
            app.EdtConfThresh.Value  = 0.50;
            app.EdtConfThresh.FontSize = 11;
            app.EdtConfThresh.Tooltip = 'General confidence threshold for the overlay checkbox on the elastogram';
            app.EdtConfThresh.ValueChangedFcn = @(src,~)app.onConfThreshChange(src);

            % ROI panel
            roiPnl = uipanel(app.MREGrid,'Title','MRE ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            roiPnl.Layout.Column = 2;
            rg = uigridlayout(roiPnl,[13 1]);
            rg.RowHeight   = {24,36,24,36,24,36,24,36,24,22,24,'1x',36};
            rg.Padding=[4 4 4 4]; rg.RowSpacing=4;

            uilabel(rg,'Text','Stiffness ROIs (same-slice, any panel):','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);

            app.BtnROI_LiverMRE = roiBtn(rg,2,'Liver stiffness', ...
                [0.15 0.85 0.15],[1 1 1]);
            app.BtnROI_LiverMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('LiverMRE');
            liverConfGrid = uigridlayout(rg,[1 3]);
            liverConfGrid.Layout.Row = 3; liverConfGrid.ColumnWidth = {50,34,'1x'}; liverConfGrid.Padding = [4 0 4 0]; liverConfGrid.ColumnSpacing = 4;
            uilabel(liverConfGrid,'Text','Conf.','FontSize',10,'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            uilabel(liverConfGrid,'Text','≥','FontSize',10,'HorizontalAlignment','center','FontColor',[0.35 0.35 0.35]);
            app.EdtLiverConfThresh = uieditfield(liverConfGrid,'numeric');
            app.EdtLiverConfThresh.Layout.Column = 3; app.EdtLiverConfThresh.Limits = [0 1]; app.EdtLiverConfThresh.Value = 0.90; app.EdtLiverConfThresh.ValueDisplayFormat = '%.2f'; app.EdtLiverConfThresh.FontSize = 10;
            app.EdtLiverConfThresh.Tooltip = 'Confidence threshold used for Liver ROI masking';
            app.EdtLiverConfThresh.ValueChangedFcn = @(src,~)app.onMREObjectConfChange('LiverMRE', src);

            app.BtnROI_SpleenMRE = roiBtn(rg,4,'Spleen stiffness', ...
                [0.15 0.65 0.95],[1 1 1]);
            app.BtnROI_SpleenMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('SpleenMRE');
            spleenConfGrid = uigridlayout(rg,[1 3]);
            spleenConfGrid.Layout.Row = 5; spleenConfGrid.ColumnWidth = {50,34,'1x'}; spleenConfGrid.Padding = [4 0 4 0]; spleenConfGrid.ColumnSpacing = 4;
            uilabel(spleenConfGrid,'Text','Conf.','FontSize',10,'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            uilabel(spleenConfGrid,'Text','≥','FontSize',10,'HorizontalAlignment','center','FontColor',[0.35 0.35 0.35]);
            app.EdtSpleenConfThresh = uieditfield(spleenConfGrid,'numeric');
            app.EdtSpleenConfThresh.Layout.Column = 3; app.EdtSpleenConfThresh.Limits = [0 1]; app.EdtSpleenConfThresh.Value = 0.75; app.EdtSpleenConfThresh.ValueDisplayFormat = '%.2f'; app.EdtSpleenConfThresh.FontSize = 10;
            app.EdtSpleenConfThresh.Tooltip = 'Confidence threshold used for Spleen ROI masking';
            app.EdtSpleenConfThresh.ValueChangedFcn = @(src,~)app.onMREObjectConfChange('SpleenMRE', src);

            app.BtnROI_MuscleMRE = roiBtn(rg,6,'Muscle stiffness', ...
                [0.95 0.55 0.15],[1 1 1]);
            app.BtnROI_MuscleMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('MuscleMRE');
            muscleConfGrid = uigridlayout(rg,[1 3]);
            muscleConfGrid.Layout.Row = 7; muscleConfGrid.ColumnWidth = {50,34,'1x'}; muscleConfGrid.Padding = [4 0 4 0]; muscleConfGrid.ColumnSpacing = 4;
            uilabel(muscleConfGrid,'Text','Conf.','FontSize',10,'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            uilabel(muscleConfGrid,'Text','≥','FontSize',10,'HorizontalAlignment','center','FontColor',[0.35 0.35 0.35]);
            app.EdtMuscleConfThresh = uieditfield(muscleConfGrid,'numeric');
            app.EdtMuscleConfThresh.Layout.Column = 3; app.EdtMuscleConfThresh.Limits = [0 1]; app.EdtMuscleConfThresh.Value = 0.50; app.EdtMuscleConfThresh.ValueDisplayFormat = '%.2f'; app.EdtMuscleConfThresh.FontSize = 10;
            app.EdtMuscleConfThresh.Tooltip = 'Confidence threshold used for Muscle ROI masking';
            app.EdtMuscleConfThresh.ValueChangedFcn = @(src,~)app.onMREObjectConfChange('MuscleMRE', src);

            app.BtnROI_FatMRE = roiBtn(rg,8,'Fat stiffness', ...
                [0.85 0.30 0.85],[1 1 1]);
            app.BtnROI_FatMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('FatMRE');
            fatConfGrid = uigridlayout(rg,[1 3]);
            fatConfGrid.Layout.Row = 9; fatConfGrid.ColumnWidth = {50,34,'1x'}; fatConfGrid.Padding = [4 0 4 0]; fatConfGrid.ColumnSpacing = 4;
            uilabel(fatConfGrid,'Text','Conf.','FontSize',10,'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            uilabel(fatConfGrid,'Text','≥','FontSize',10,'HorizontalAlignment','center','FontColor',[0.35 0.35 0.35]);
            app.EdtFatConfThresh = uieditfield(fatConfGrid,'numeric');
            app.EdtFatConfThresh.Layout.Column = 3; app.EdtFatConfThresh.Limits = [0 1]; app.EdtFatConfThresh.Value = 0.90; app.EdtFatConfThresh.ValueDisplayFormat = '%.2f'; app.EdtFatConfThresh.FontSize = 10;
            app.EdtFatConfThresh.Tooltip = 'Confidence threshold used for Fat ROI masking';
            app.EdtFatConfThresh.ValueChangedFcn = @(src,~)app.onMREObjectConfChange('FatMRE', src);

            % Polygon vertex count (row 10, below Fat confidence)
            vtxRowM = uigridlayout(rg,[1 3]);
            vtxRowM.Layout.Row = 10;
            vtxRowM.ColumnWidth = {'1x',52,10}; vtxRowM.Padding=[2 0 2 0]; vtxRowM.ColumnSpacing=3;
            uilabel(vtxRowM,'Text','Poly vertices:','FontSize',9, ...
                'HorizontalAlignment','right','FontColor',[0.35 0.35 0.35]);
            app.EdtROIVerticesMRE = uieditfield(vtxRowM,'numeric');
            app.EdtROIVerticesMRE.Layout.Column = 2;
            app.EdtROIVerticesMRE.Limits = [3 500]; app.EdtROIVerticesMRE.Value = 47;
            app.EdtROIVerticesMRE.RoundFractionalValues = true; app.EdtROIVerticesMRE.FontSize = 10;
            app.EdtROIVerticesMRE.Tooltip = 'Vertices in the editable polygon after freehand draw (default 47)';
            app.EdtROIVerticesMRE.ValueChangedFcn = @(src,~)app.onROIVerticesChanged(src);

            workflowLbl = uilabel(rg,'Text','Workflow:','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);
            workflowLbl.Layout.Row = 11;
            app.LblMREInfo = uilabel(rg);
            app.LblMREInfo.Layout.Row=12;
            app.LblMREInfo.Text = sprintf(['Choose organ, click target panel, hotkeys:' char(10) ...
                'F = freehand → edit polygon → dbl-click confirm' char(10) ...
                'D = seed + auto on Magnitude' char(10) ...
                'E = exclude, I = include, +/- = erosion' char(10) ...
                'A/Enter = accept, Esc = cancel']);
            app.LblMREInfo.FontSize=11; app.LblMREInfo.WordWrap='on';
            app.LblMREInfo.FontColor=[0.45 0.45 0.45];

            app.BtnClearMREROIs = roiBtn(rg,13,'Clear this slice', ...
                [0.72 0.72 0.72],[0.2 0.2 0.2]);
            app.BtnClearMREROIs.ButtonPushedFcn = @(~,~)app.clearMRESlice();
        end

        % ── RESULTS TAB ──────────────────────────────────────────────────
        function createResultsTab(app)
            app.ResultsTab = uitab(app.ImageTabGroup,'Title','Results');
            app.ResultsGrid = uigridlayout(app.ResultsTab,[2 1]);
            app.ResultsGrid.Padding    = [8 8 8 8];
            app.ResultsGrid.RowHeight  = {'1x', 44};
            app.ResultsGrid.RowSpacing = 6;

            app.ResultsTable = uitable(app.ResultsGrid);
            app.ResultsTable.Layout.Row    = 1;
            app.ResultsTable.Layout.Column = 1;
            app.ResultsTable.FontSize      = 11;
            app.ResultsTable.ColumnName    = {'Slice Location','Measurement', ...
                'Volume (mm³)','Mean Value','Unit','Notes'};
            app.ResultsTable.Data          = {'—','—','—','—','—', ...
                'Load a study and draw ROIs first'};
            app.ResultsTable.ColumnWidth   = {120, 160, 110, 100, 60, 250};

            % Export buttons row
            app.ResultsBtnGrid = uigridlayout(app.ResultsGrid,[1 3]);
            app.ResultsBtnGrid.Layout.Row    = 2;
            app.ResultsBtnGrid.Layout.Column = 1;
            app.ResultsBtnGrid.Padding       = [0 0 0 0];
            app.ResultsBtnGrid.ColumnWidth   = {220, 220, '1x'};

            app.BtnExportPDFFRadiomics = uibutton(app.ResultsBtnGrid, ...
                'Text','Export PDFF Radiomics CSV');
            app.BtnExportPDFFRadiomics.Layout.Column = 1;
            app.BtnExportPDFFRadiomics.FontSize      = 12;
            app.BtnExportPDFFRadiomics.ButtonPushedFcn = @(~,~)app.exportPDFFRadiomicsCSV();

            app.BtnExportMRERadiomics = uibutton(app.ResultsBtnGrid, ...
                'Text','Export MRE Radiomics CSV');
            app.BtnExportMRERadiomics.Layout.Column = 2;
            app.BtnExportMRERadiomics.FontSize      = 12;
            app.BtnExportMRERadiomics.ButtonPushedFcn = @(~,~)app.exportMRERadiomicsCSV();
        end

        % -----------------------------------------------------------------
        function createRightPanel(app)
            app.RightPanel = uipanel(app.BodyGrid,'Title','Measurements', ...
                'FontSize',13,'FontWeight','bold');
            app.RightPanel.Layout.Column = 3;

            app.RightGrid = uigridlayout(app.RightPanel,[3 1]);
            app.RightGrid.RowHeight   = {110,220,'1x'};
            app.RightGrid.ColumnWidth = {'1x'};
            app.RightGrid.Padding     = [2 2 2 2];
            app.RightGrid.RowSpacing  = 2;

            addMeasSection(app,1,'Dixon — Liver & Spleen', ...
                {'Liver vol. (mm³)','Liver PDFF','Spleen vol. (mm³)','Spleen PDFF'}, ...
                {'ValLiverDixonVol','ValLiverDixonPDFF', ...
                 'ValSpleenDixonVol','ValSpleenDixonPDFF'});

            addMeasSection(app,2,'Dixon — Muscle & Fat', ...
                {'Psoas vol. (mm³)','Psoas PDFF', ...
                 'Trunk vol. (mm³)','Trunk PDFF', ...
                 'SAT vol. (mm³)','SAT PDFF', ...
                 'VAT vol. (mm³)','VAT PDFF'}, ...
                {'ValPsoasDixonVol','ValPsoasDixonPDFF', ...
                 'ValTrunkDixonVol','ValTrunkDixonPDFF', ...
                 'ValSATDixonVol','ValSATDixonPDFF', ...
                 'ValVATDixonVol','ValVATDixonPDFF'});

            % NOTE FOR MAINTAINERS:
            % The visible labels below were changed from stiffness + IQR to
            % stiffness + combined "N / volume" text. The backing UI
            % handle names ending in *IQR are intentionally retained to
            % avoid widespread refactoring, but those handles now show
            % "N / volume" rather than interquartile range.
            addMeasSection(app,3,'MRE — Stiffness', ...
                {'Liver stiffness','Liver N/vol.', ...
                 'Spleen stiffness','Spleen N/vol.', ...
                 'Muscle stiffness','Muscle N/vol.', ...
                 'Fat stiffness','Fat N/vol.'}, ...
                {'ValLiverStiff','ValLiverStiffIQR', ...
                 'ValSpleenStiff','ValSpleenStiffIQR', ...
                 'ValMuscleMREStiff','ValMuscleMREStiffIQR', ...
                 'ValFatMREStiff','ValFatMREStiffIQR'});
        end

        function addMeasSection(app, row, sectionTitle, labels, propNames)
            pnl = uipanel(app.RightGrid,'Title',sectionTitle, ...
                'FontSize',11,'FontWeight','bold');
            pnl.Layout.Row=row;
            n = numel(labels);
            g = uigridlayout(pnl,[n 2]);
            g.ColumnWidth={110,'1x'}; g.RowHeight=repmat({20},1,n);
            g.Padding=[4 2 4 2]; g.ColumnSpacing=4; g.RowSpacing=2;
            for k = 1:n
                lbl = uilabel(g); lbl.Layout.Row=k; lbl.Layout.Column=1;
                lbl.Text=labels{k}; lbl.FontSize=11; lbl.FontColor=[0.40 0.40 0.40];
                val = uilabel(g); val.Layout.Row=k; val.Layout.Column=2;
                val.Text='—'; val.FontSize=12; val.FontWeight='bold';
                val.HorizontalAlignment='right'; val.FontColor=[0.25 0.25 0.25];
                app.(propNames{k}) = val;
            end
        end

        % -----------------------------------------------------------------
        function createBottomBar(app, parentGrid)
            app.BottomPanel = uipanel(parentGrid,'BorderType','line');
            app.BottomPanel.Layout.Row=3; app.BottomPanel.Layout.Column=1;
            app.BottomPanel.BackgroundColor=[0.91 0.91 0.91];

            app.BottomGrid = uigridlayout(app.BottomPanel,[2 2]);
            app.BottomGrid.RowHeight    = {'1x',18};
            app.BottomGrid.ColumnWidth  = {'1x',200};
            app.BottomGrid.Padding      = [6 3 6 2]; app.BottomGrid.ColumnSpacing=4;

            app.LblCursorVal = uilabel(app.BottomGrid);
            app.LblCursorVal.Layout.Row=1; app.LblCursorVal.Layout.Column=2;
            app.LblCursorVal.Text='';
            app.LblCursorVal.FontSize=11; app.LblCursorVal.FontColor=[0.25 0.35 0.70];
            app.LblCursorVal.HorizontalAlignment='right';

            app.LblStatusMsg = uilabel(app.BottomGrid);
            app.LblStatusMsg.Layout.Row=2; app.LblStatusMsg.Layout.Column=[1 2];
            app.LblStatusMsg.Text='Ready — click Load Study to begin.';
            app.LblStatusMsg.FontSize=11; app.LblStatusMsg.FontColor=[0.40 0.40 0.40];
        end

    end % createComponents

    % =====================================================================
    %  STARTUP
    % =====================================================================
    methods (Access = private)
        function startupFcn(app)
            try, app.EdtConfThresh.Value = app.AppData.ConfThresh; catch, end
            try, app.EdtLiverConfThresh.Value = app.AppData.MREObjectConf.LiverMRE; catch, end
            try, app.EdtSpleenConfThresh.Value = app.AppData.MREObjectConf.SpleenMRE; catch, end
            try, app.EdtMuscleConfThresh.Value = app.AppData.MREObjectConf.MuscleMRE; catch, end
            try, app.EdtFatConfThresh.Value = app.AppData.MREObjectConf.FatMRE; catch, end
            setStatus(app,'Ready — click Load Study to begin.');
        end
    end

    % =====================================================================
    %  PUBLIC CALLBACKS
    % =====================================================================
    methods (Access = public)

        % ── LOAD STUDY ────────────────────────────────────────────────────
        function loadStudy(app)
            % 1. Pick folder
            folderPath = uigetdir(pwd,'Select DICOM Exam Folder');
            if isequal(folderPath,0), return; end

            % Clear all exam-specific data to prevent bleed from prior exam.
            app.resetExamAppData();

            % Check for previously saved session files
            pdffPath   = fullfile(folderPath, 'pdff_data.mat');
            mreMatPath = fullfile(folderPath, 'mre_data.mat');
            hasPdff    = isfile(pdffPath);
            hasMreMat  = isfile(mreMatPath);
            loadFromMat = false;

            if hasPdff || hasMreMat
                found = {};
                if hasPdff,   found{end+1} = 'pdff_data.mat  (Dixon images + landmarks + ROIs)'; end
                if hasMreMat, found{end+1} = 'mre_data.mat  (MRE data + ROIs)'; end
                msg = sprintf('Previous session data found:\n  \x2022 %s\n\nLoad from saved files (fast, ROIs preserved) or re-select series from DICOM (overwrites saved data)?', ...
                    strjoin(found, sprintf('\n  \x2022 ')));
                choice = uiconfirm(app.UIFigure, msg, 'Previous Session Found', ...
                    'Options', {'Load Saved Data', 'Re-select from DICOM'}, ...
                    'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'question');
                loadFromMat = strcmp(choice, 'Load Saved Data');
            end

            dlg = uiprogressdlg(app.UIFigure,'Title','Loading Study', ...
                'Message','Loading...','Indeterminate','on');

            try
                if loadFromMat
                    % ── Fast path: restore from saved mat files ──────────────
                    app.AppData.ExamPath = folderPath;
                    app.AppData.MATPath  = mreMatPath;

                    if hasPdff
                        dlg.Message = 'Loading from pdff_data.mat...';
                        loadPDFFMat(app, folderPath);   % loads Dixon + Localizer + ROIs + LMs
                        % Patient info from pdff_data.mat metadata
                        try
                            S = load(pdffPath, 'pdff');
                            p = S.pdff;
                            pid = ''; dt = ''; tp = '';
                            if isfield(p,'PatientID'), pid = p.PatientID; end
                            if isfield(p,'StudyDate'), dt  = p.StudyDate;  end
                            if isfield(p,'MREType'),   tp  = p.MREType;    end
                            app.LblPatientInfo.Text = sprintf('%s  |  %s  |  %s', pid, dt, tp);
                        catch
                        end
                        % Warn if the saved file predates image storage
                        if isempty(app.AppData.Dixon)
                            uialert(app.UIFigure, ...
                                ['pdff_data.mat does not contain Dixon images (saved with an older version).' ...
                                 newline newline ...
                                 'Click OK, then use "Re-select from DICOM" to rebuild pdff_data.mat ' ...
                                 'with images included. Your ROIs and landmarks are still loaded.'], ...
                                'Dixon Images Missing', 'Icon','warning');
                        end
                    end

                    if hasMreMat
                        dlg.Message = 'Loading MRE from mre_data.mat...';
                        tmp = load(mreMatPath,'M','M_raw','W','W_raw','S','LapC','H');
                        if ~isfield(tmp,'W_raw') || isempty(tmp.W_raw)
                            tmp.W_raw = tmp.W;
                        end
                        tmp = normalizeMREStruct(app, tmp);
                        app.AppData.MRE = tmp;
                        loadMREROIsFromMat(app, mreMatPath);
                        populateMRETab(app);
                        updateAllMREStats(app);
                    end

                    app.BtnConfirmL12.Enable  = 'on';
                    setStatus(app, 'Session restored from saved data.');
                    try, app.updateResultsTable(); catch, end
                    % Surface any pre-existing radiomics exports in this folder
                    csvFound = {};
                    if isfile(fullfile(folderPath,'pdff_radiomics.csv')), csvFound{end+1}='pdff_radiomics.csv'; end
                    if isfile(fullfile(folderPath,'mre_radiomics.csv')),  csvFound{end+1}='mre_radiomics.csv';  end
                    if ~isempty(csvFound)
                        setStatus(app, sprintf('Session restored. Previous radiomics exports found: %s', ...
                            strjoin(csvFound,', ')));
                    end

                else
                    % ── Full DICOM load path ─────────────────────────────────
                    dlg.Message = 'Parsing DICOM exam...';
                    setStatus(app,'Parsing DICOM exam...');
                    exam = mre_parseDICOMExam(folderPath, struct('verbose',false));
                    app.AppData.Exam = exam;

                    close(dlg);

                    setStatus(app,'Select series...');
                    selection = mre_selectSeriesGUI(exam);
                    if ~selection.Confirmed
                        setStatus(app,'Series selection cancelled.');
                        return
                    end
                    app.AppData.Selection = selection;

                    dlg = uiprogressdlg(app.UIFigure,'Title','Building Data', ...
                        'Message','Loading series data...','Indeterminate','on');

                    matOpts = struct('outputDir',folderPath,'verbose',false, ...
                                     'forceRebuild',true,'interpolateWave',true);
                    matPath = '';

                    if ~isempty(selection.MRE)
                        dlg.Message = 'Building MRE MAT file...';
                        matPath = mre_buildMATFile(selection, matOpts);
                    end
                    app.AppData.MATPath  = matPath;
                    app.AppData.ExamPath = folderPath;

                    if ~isempty(selection.Localizer)
                        dlg.Message = 'Loading localizer...';
                        app.AppData.Localizer = loc_loadLocalizer( ...
                            selection.Localizer, struct('verbose',false));
                        populateLocalizerTab(app);
                    end

                    if ~isempty(selection.DixonGroup)
                        dlg.Message = 'Building Dixon volumes...';
                        app.AppData.Dixon = seg_buildDixonVolume( ...
                            selection.DixonGroup, struct('verbose',false));
                        populateDixonTab(app);
                    end

                    % Save pdff_data.mat now (with Dixon images + Localizer) so the
                    % fast-path reload works even before any ROI is accepted.
                    % Then re-apply any previously saved landmarks/ROIs on top.
                    dlg.Message = 'Saving pdff_data.mat...';
                    app.savePDFFMat();
                    if hasPdff
                        loadPDFFMat(app, folderPath);
                    end

                    if ~isempty(matPath) && isfile(matPath)
                        dlg.Message = 'Loading MRE data...';
                        tmp = load(matPath,'M','M_raw','W','W_raw','S','LapC','H');
                        if ~isfield(tmp,'W_raw') || isempty(tmp.W_raw)
                            tmp.W_raw = tmp.W;
                        end
                        tmp = normalizeMREStruct(app, tmp);
                        app.AppData.MRE = tmp;
                        loadMREROIsFromMat(app, matPath);
                        populateMRETab(app);
                    end

                    app.LblPatientInfo.Text = sprintf('%s  |  %s  |  %s', ...
                        exam.PatientID, exam.StudyDate, exam.MREType);
                    app.BtnConfirmL12.Enable   = 'on';

                    updateStudyBrowser(app, exam, selection);
                    setStatus(app,sprintf('Loaded: %s — %s | %d series', ...
                        exam.PatientID, exam.StudyDate, numel(exam.Series)));
                end

            catch ME
                if isvalid(dlg), close(dlg); end
                uialert(app.UIFigure, ME.message,'Load Error','Icon','error');
                setStatus(app,['ERROR: ' ME.message]);
            end
            if isvalid(dlg), close(dlg); end
        end

        % ── LOCALIZER / L1-L2 ────────────────────────────────────────────
        function onLocCorSlide(app, src)
            sl = round(src.Value);
            app.AppData.CorSlice = sl;
            app.LblLocCor.Text = sprintf('%d/%d', sl, round(src.Limits(2)));
            refreshLocCoronal(app);
        end

        function onLocSagSlide(app, src)
            sl = round(src.Value);
            app.AppData.SagSlice = sl;
            app.LblLocSag.Text = sprintf('%d/%d', sl, round(src.Limits(2)));
            refreshLocSagittal(app);
        end

        % ── Landmark placement (replaces legacy placeL1/placeL2) ─────────

        function placeLandmark(app, lmName)
        % Arm click-to-place for the given disc landmark name.
            if isempty(app.AppData.Localizer)
                uialert(app.UIFigure,'Load a study first.','No Localizer');
                return
            end
            cancelPendingClick(app);
            % Refresh to show current line positions (only placed markers are shown).
            refreshLocCoronal(app);
            refreshLocSagittal(app);
            % Highlight the active button
            app.AppData.ActiveLM = lmName;
            app.AppData.AwaitingClick = lmName;
            try
                btnProp = ['BtnMarkLM_' lmName];
                app.(btnProp).BackgroundColor = [1 1 0.7];
            catch, end
            lbl = locLandmarkLabel(lmName);
            setStatus(app, sprintf('%s line shown.  Click coronal or sagittal image to reposition.', lbl));
            app.LblL12Status.Text = sprintf('%s — click image to reposition, scroll to navigate.', lbl);
            app.AxLocCoronal.ButtonDownFcn  = @(~,e)app.onLocImageClick(e,'cor',lmName);
            app.AxLocSagittal.ButtonDownFcn = @(~,e)app.onLocImageClick(e,'sag',lmName);
        end

        function cancelPendingClick(app)
        % Reset armed state and restore all landmark button colors.
            try; app.AxLocCoronal.ButtonDownFcn  = ''; catch; end
            try; app.AxLocSagittal.ButtonDownFcn = ''; catch; end
            app.AppData.AwaitingClick = '';
            app.AppData.ActiveLM = '';
            lmNames  = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            lmColors = {[0.55 0.05 0.05],[0.75 0.10 0.10],[0.88 0.35 0.08],[0.92 0.65 0.05],[0.30 0.72 0.30],[0.15 0.58 0.88],[0.50 0.20 0.85]};
            for ki = 1:7
                try
                    app.(['BtnMarkLM_' lmNames{ki}]).BackgroundColor = lmColors{ki};
                catch, end
            end
            % Legacy button resets
            try; app.BtnPlaceL1.BackgroundColor = [0.92 0.60 0.12]; catch, end
            try; app.BtnPlaceL2.BackgroundColor = [0.38 0.62 0.92]; catch, end
        end

        function clearLandmarks(app)
        % Clear all 7 disc landmark positions.
            cancelPendingClick(app);
            lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            for ki = 1:7
                app.AppData.LM.(lmNames{ki}).CorRow = NaN;
                app.AppData.LM.(lmNames{ki}).SagRow = NaN;
            end
            % Legacy fields
            app.AppData.L1_CorRow = NaN; app.AppData.L2_CorRow = NaN;
            app.AppData.L1_SagRow = NaN; app.AppData.L2_SagRow = NaN;
            refreshLocCoronal(app);
            refreshLocSagittal(app);
            app.LblL12Status.Text = 'All landmarks cleared.';
            setStatus(app,'Disc landmarks cleared.');
        end

        % Keep legacy wrappers so old code paths still compile
        function placeL1(app), app.placeLandmark('T12L1'); end
        function placeL2(app), app.placeLandmark('L3L4');  end
        function clearL12(app), app.clearLandmarks(); end

        function updateLandmarkStatus(app)
        % Update the status label and enable Confirm button when enough landmarks are set.
            lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            nPlaced = 0;
            for ki = 1:7
                if ~isnan(app.AppData.LM.(lmNames{ki}).CorRow)
                    nPlaced = nPlaced + 1;
                end
            end
            if nPlaced == 0
                app.LblL12Status.Text = 'No disc landmarks placed yet.  Click a disc button above.';
            elseif nPlaced < 2
                app.LblL12Status.Text = sprintf('%d/7 disc levels placed.  Press Confirm when done.', nPlaced);
            else
                app.LblL12Status.Text = sprintf('%d/7 disc levels placed — press Confirm Levels in toolbar.', nPlaced);
            end
            if nPlaced >= 2
                try, app.BtnConfirmL12.Enable = 'on'; catch, end
            end
        end

        % Legacy alias
        function updateL12Status(app), app.updateLandmarkStatus(); end

        function confirmLandmarks(app)
        % Convert all placed landmarks to mm and propagate to Dixon + MRE.
            loc = app.AppData.Localizer;
            if isempty(loc)
                uialert(app.UIFigure,'No localizer loaded.','Missing Data'); return
            end
            lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            anyPlaced = false;
            for ki = 1:7
                if ~isnan(app.AppData.LM.(lmNames{ki}).CorRow)
                    anyPlaced = true; break
                end
            end
            if ~anyPlaced
                uialert(app.UIFigure,'Place at least one disc level marker first.','No Landmarks');
                return
            end

            % Convert coronal row → patient Z (mm) for each landmark
            sinfo = loc.Coronal.SpatialInfo;
            lmZ   = struct();
            for ki = 1:7
                n = lmNames{ki};
                lmZ.(n) = NaN;
                row = app.AppData.LM.(n).CorRow;
                if ~isnan(row)
                    lmZ.(n) = corRowToZmm(app, row);
                end
            end

            % Propagate to Dixon — use buildDixonSliceZ which tries all available methods
            dixSliceZ = [];
            try
                dix = app.AppData.Dixon;
                if ~isempty(dix)
                    dixSliceZ = buildDixonSliceZ(dix);
                end
            catch, end
            for ki = 1:7
                n = lmNames{ki};
                app.AppData.LM_Dixon.(n).SliceIdx = NaN;
                app.AppData.LM_Dixon.(n).Dist_mm  = NaN;
                if ~isnan(lmZ.(n)) && ~isempty(dixSliceZ)
                    [dm, si] = min(abs(dixSliceZ - lmZ.(n)));
                    app.AppData.LM_Dixon.(n).SliceIdx = si;
                    app.AppData.LM_Dixon.(n).Dist_mm  = dm;
                end
            end

            % Propagate to MRE — try SpatialInfo, fall back to H header
            mreSliceZ = [];
            try
                mre = app.AppData.MRE;
                if ~isempty(mre)
                    if isfield(mre,'SpatialInfo') && ~isempty(mre.SpatialInfo) && ...
                       isfield(mre.SpatialInfo,'AffineMatrix')
                        mreSliceZ = buildSliceZFromSinfo(mre.SpatialInfo);
                    end
                    if isempty(mreSliceZ) && isfield(mre,'H') && isstruct(mre.H) && ...
                       isfield(mre.H,'ImagePositionPatient') && ...
                       isfield(mre.H,'ImageOrientationPatient')
                        % Compute slice Z positions from DICOM header geometry
                        nZ  = size(mre.M, 3);
                        ipp = double(mre.H.ImagePositionPatient(:));
                        iop = double(mre.H.ImageOrientationPatient(:));
                        normalDir = cross(iop(1:3), iop(4:6));
                        dz = 0;
                        if isfield(mre.H,'SpacingBetweenSlices') && ~isempty(mre.H.SpacingBetweenSlices)
                            dz = double(mre.H.SpacingBetweenSlices) * sign(normalDir(3));
                        elseif isfield(mre.H,'SliceThickness') && ~isempty(mre.H.SliceThickness)
                            dz = double(mre.H.SliceThickness) * sign(normalDir(3));
                        end
                        if dz ~= 0 && nZ >= 1
                            mreSliceZ = ipp(3) + (0:nZ-1)' * dz;
                        end
                    end
                end
            catch, end
            for ki = 1:7
                n = lmNames{ki};
                app.AppData.LM_MRE.(n).SliceIdx = NaN;
                app.AppData.LM_MRE.(n).Dist_mm  = NaN;
                if ~isnan(lmZ.(n)) && ~isempty(mreSliceZ)
                    [dm, si] = min(abs(mreSliceZ - lmZ.(n)));
                    app.AppData.LM_MRE.(n).SliceIdx = si;
                    app.AppData.LM_MRE.(n).Dist_mm  = dm;
                end
            end

            % Legacy L12 struct (keep for loc_propagateToSpace compat)
            try
                L12 = rowsToL12mm(app, sinfo);
                app.AppData.L12 = L12;
                if ~isempty(dixSinfo)
                    app.AppData.L12_Dixon = loc_propagateToSpace(L12, dixSinfo, struct('verbose',false));
                end
            catch, end

            % Enable Dixon jump buttons for placed landmarks
            updateDixonJumpButtons(app);

            % Jump Dixon to first available confirmed landmark
            jumpSl = NaN;
            for ki = 1:7
                si = app.AppData.LM_Dixon.(lmNames{ki}).SliceIdx;
                if ~isnan(si), jumpSl = si; break; end
            end
            if ~isnan(jumpSl) && ~isempty(app.AppData.Dixon)
                sl = max(1, min(app.AppData.Dixon.nSlices, round(jumpSl)));
                app.AppData.DixonSlice = sl;
                refreshDixon(app);
            end

            % Build status summary
            parts = {};
            for ki = 1:7
                n = lmNames{ki};
                lbl = locLandmarkLabel(n);
                si  = app.AppData.LM_Dixon.(n).SliceIdx;
                dm  = app.AppData.LM_Dixon.(n).Dist_mm;
                if ~isnan(si)
                    parts{end+1} = sprintf('%s→sl%d(%.1fmm)', lbl, si, dm); %#ok<AGROW>
                end
            end
            allZnan = all(cellfun(@(n) isnan(lmZ.(n)), lmNames));
            if isempty(parts) && allZnan
                setStatus(app,'Landmarks confirmed but could not compute Z positions from localizer — check coronal SpatialInfo.');
            elseif isempty(parts)
                setStatus(app,'Landmarks confirmed but could not map to Dixon slices — Dixon SliceLocations may be missing.');
            else
                setStatus(app,['Confirmed.  Dixon: ' strjoin(parts,'  ')]);
            end
            app.LblL12Status.Text = sprintf('%d/7 disc levels confirmed and propagated.', ...
                sum(~isnan(cellfun(@(n)app.AppData.LM_Dixon.(n).SliceIdx, lmNames))));
            activateTab(app,'dixon');
            app.savePDFFMat();   % persist disc marks to pdff_data.mat
        end

        % Legacy alias
        function confirmL12(app), app.confirmLandmarks(); end

        function updateDixonJumpButtons(app)
        % Enable/disable Dixon jump buttons based on propagated slice indices.
            lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            lmProps = {'BtnJumpLM_T9T10','BtnJumpLM_T10T11','BtnJumpLM_T11T12','BtnJumpLM_T12L1','BtnJumpLM_L1L2','BtnJumpLM_L2L3','BtnJumpLM_L3L4'};
            for ki = 1:7
                try
                    si = app.AppData.LM_Dixon.(lmNames{ki}).SliceIdx;
                    dm = app.AppData.LM_Dixon.(lmNames{ki}).Dist_mm;
                    if ~isnan(si)
                        lbl = locLandmarkLabel(lmNames{ki});
                        app.(lmProps{ki}).Text = sprintf('%s\nsl%d', lbl, si);
                        app.(lmProps{ki}).Enable = 'on';
                        if ~isnan(dm) && dm > 5
                            app.(lmProps{ki}).Enable = 'off';  % outside 5mm threshold
                        end
                    else
                        app.(lmProps{ki}).Enable = 'off';
                    end
                catch, end
            end
        end

        function jumpDixonToLandmark(app, lmName)
        % Jump Dixon display to the slice closest to the given landmark.
            try
                si = app.AppData.LM_Dixon.(lmName).SliceIdx;
                if isnan(si), return; end
                sl = max(1, min(app.AppData.Dixon.nSlices, round(si)));
                app.AppData.DixonSlice = sl;
                refreshDixon(app);
                setStatus(app, sprintf('Jumped to %s → Dixon slice %d.', locLandmarkLabel(lmName), sl));
            catch, end
        end

        % ── DIXON ─────────────────────────────────────────────────────────
        function drawDixonROI(app, roiName)
            if isempty(app.AppData.Dixon)
                uialert(app.UIFigure,'No Dixon data loaded.','No Data');
                return
            end
            app.cancelDixonROIWorkflow(false);
            app.AppData.DixonROIActive  = true;
            app.AppData.DixonROIName    = roiName;
            app.AppData.DixonROISlice   = app.AppData.DixonSlice;
            app.AppData.DixonROIOuterMask = [];
            app.AppData.DixonROIFinalMask = [];
            app.AppData.DixonROIErodePx = 2;
            app.AppData.DixonROIDrawing = false;
            % Set organ-specific default vertex count and sync edit fields.
            dixonVtxDefaults = struct('LiverDixon',58,'SpleenDixon',58, ...
                'PsoasDixon',27,'TrunkDixon',58,'SATDixon',100,'VATDixon',58);
            if isfield(dixonVtxDefaults, roiName)
                nv = dixonVtxDefaults.(roiName);
                app.AppData.ROIVertices = nv;
                try, app.EdtROIVerticesDixon.Value = nv; catch, end
                try, app.EdtROIVerticesMRE.Value   = nv; catch, end
            end
            app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
            app.setDixonROIButtonsEnabled(false);

            % If a ROI already exists on this slice, pre-load it for editing.
            existMask = getStoredDixonROIMask(app, roiName, app.AppData.DixonROISlice);
            if ~isempty(existMask) && any(existMask(:))
                app.AppData.DixonROIOuterMask = existMask;
                app.AppData.DixonROIFinalMask = existMask;
                app.showDixonROIHotkeyHelp();
                refreshDixon(app);
                setStatus(app, sprintf('%s ROI loaded for editing (sl %d). R = vertex-edit, F = redraw, Enter = accept.', ...
                    app.getDixonOrganLabel(roiName), app.AppData.DixonROISlice));
            else
                app.showDixonROIHotkeyHelp();
                setStatus(app, sprintf('%s ROI armed (sl %d). F = freehand  D = seed+auto  R = edit vertices.', ...
                    app.getDixonOrganLabel(roiName), app.AppData.DixonROISlice));
            end
        end

        function clearDixonSlice(app)
            sl = app.AppData.DixonSlice;
            dixonROINames = {'LiverDixon','SpleenDixon','MuscleDixon', ...
                             'PsoasDixon','TrunkDixon','SATDixon','VATDixon','FatDixon'};
            for ri = 1:numel(dixonROINames)
                n = dixonROINames{ri};
                if isfield(app.AppData.ROIs, n)
                    app.AppData.ROIs.(n).Slices = removeSlice(app.AppData.ROIs.(n).Slices, sl);
                end
            end
            refreshDixon(app);
            setStatus(app,sprintf('ROIs cleared for Dixon slice %d.',sl));
        end

        % ── MRE ───────────────────────────────────────────────────────────
        
function onMRESlide(app, src)
    if app.isMREROIWorkflowActive()
        keepSl = app.AppData.MREROISlice;
        if isnan(keepSl), keepSl = app.AppData.MRESlice; end
        src.Value = keepSl;
        app.AppData.MRESlice = keepSl;
        nZ = max(1, size(app.AppData.MRE.S,3));
        app.LblMRESlice.Text = sprintf('%d/%d', keepSl, nZ);
        setStatus(app, 'Finish the active MRE ROI with Enter or cancel with Esc before changing slices.');
        refreshMRE(app);
        return
    end
    sl = round(src.Value);
    app.AppData.MRESlice = sl;
    nZ = max(1, size(app.AppData.MRE.S,3));
    app.LblMRESlice.Text = sprintf('%d/%d',sl,nZ);
    refreshMRE(app);
end

function stopMREPlayback(app)
            try
                if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                    stop(app.AppData.MRETimer);
                    delete(app.AppData.MRETimer);
                end
            catch
            end
            app.AppData.MRETimer = [];
            app.AppData.MREPlaying = false;
            try
                app.BtnMREPlay.Text = sprintf('%s Play wave', char(9654));
                app.BtnMREPlay.BackgroundColor = [0.18 0.60 0.34];
            catch
            end
        end

function pauseMREPlaybackForROI(app)
            try
                if app.AppData.MREPlaying || (~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer))
                    app.stopMREPlayback();
                    setStatus(app, 'Wave playback paused while saving the MRE ROI.');
                end
            catch
                app.stopMREPlayback();
            end
        end

function finishMREROIDrawing(app)
            try
                app.AppData.MREROIDrawing = false;
            catch
            end
            try
                app.updateMREPlaybackButtonEnabled();
            catch
            end
        end

function clearMRERefreshBusy(app)
            try
                app.AppData.MRERefreshBusy = false;
            catch
            end
        end

function clearMREROIBusy(app)
            resumePlayback = false;
            try
                app.AppData.MREROIBusy = false;
            catch
            end
            try
                if isfield(app.AppData,'MREPlaybackWasOnBeforeROI') && app.AppData.MREPlaybackWasOnBeforeROI
                    resumePlayback = true;
                end
                app.AppData.MREPlaybackWasOnBeforeROI = false;
            catch
            end
            try
                app.updateMREPlaybackButtonEnabled();
            catch
            end
            if resumePlayback
                try
                    activeTab = app.ImageTabGroup.SelectedTab;
                    if isequal(activeTab, app.MRETab) && ~app.AppData.MREPlaying && ...
                            ~(isfield(app.AppData,'MREROIDrawing') && app.AppData.MREROIDrawing) && ...
                            ~(isfield(app.AppData,'MRERefreshBusy') && app.AppData.MRERefreshBusy)
                        app.toggleMREPlay();
                    end
                catch
                end
            end
        end

function updateMREPlaybackButtonEnabled(app)
            state = 'on';
            try
                if isempty(app.AppData.MRE)
                    state = 'off';
                elseif isfield(app.AppData,'MREROIBusy') && app.AppData.MREROIBusy
                    state = 'off';
                end
            catch
                state = 'on';
            end
            try
                app.BtnMREPlay.Enable = state;
            catch
            end
        end

function toggleMREPlay(app)
            if isfield(app.AppData,'MREROIBusy') && app.AppData.MREROIBusy
                app.stopMREPlayback();
                setStatus(app, 'Wave playback is disabled only while saving an MRE ROI.');
                return
            end
            if app.AppData.MREPlaying
                app.stopMREPlayback();
            else
                app.AppData.MREPlaying = true;
                try
                    app.BtnMREPlay.Text = sprintf('%s Pause', char(9208));
                catch
                    app.BtnMREPlay.Text = 'Pause';
                end
                app.BtnMREPlay.BackgroundColor = [0.75 0.35 0.10];
                t = timer('ExecutionMode','fixedRate','BusyMode','drop','Period',0.15, ...
                    'TimerFcn',@(~,~)app.advanceWaveFrame());
                app.AppData.MRETimer = t;
                start(t);
            end
        end

        function advanceWaveFrame(app)
            if isempty(app.AppData.MRE) || ~isfield(app.AppData.MRE,'W'), return; end
            try
                activeTab = app.ImageTabGroup.SelectedTab;
                if ~isequal(activeTab, app.MRETab)
                    app.stopMREPlayback();
                    return
                end
            catch
            end
            if (isfield(app.AppData,'MREROIBusy') && app.AppData.MREROIBusy) || ...
                    (isfield(app.AppData,'MRERefreshBusy') && app.AppData.MRERefreshBusy)
                return
            end
            nPh = size(app.AppData.MRE.W, 4);
            ph  = mod(app.AppData.MREPhase, nPh) + 1;
            app.AppData.MREPhase = ph;
            refreshMRE(app);
        end

function drawMREROI(app, roiName)
    if isempty(app.AppData.MRE)
        uialert(app.UIFigure,'No MRE data loaded.','No Data');
        return
    end
    app.cancelMREROIWorkflow(false);
    app.clearMREROIPreviewOverlay();
    app.AppData.MREROIActive = true;
    app.AppData.MREROIName = roiName;
    app.AppData.MREROISlice = app.AppData.MRESlice;
    app.AppData.MREROIOuterMask = [];
    app.AppData.MREROIBaseInnerMask = [];
    app.AppData.MREROIConfMask = [];
    app.AppData.MREROIFinalMask = [];
    app.AppData.MREROIErodePx = 2;
    app.AppData.MREROIDrawing = false;
    % Set organ-specific default vertex count and sync edit fields.
    mreVtxDefaults = struct('LiverMRE',58,'SpleenMRE',58,'MuscleMRE',58,'FatMRE',100);
    if isfield(mreVtxDefaults, roiName)
        nv = mreVtxDefaults.(roiName);
        app.AppData.ROIVertices = nv;
        try, app.EdtROIVerticesDixon.Value = nv; catch, end
        try, app.EdtROIVerticesMRE.Value   = nv; catch, end
    end
    app.setCurrentMRETargetAxis(app.inferCurrentMRETargetAxis());
    app.setMREROIButtonsEnabled(false);
    app.updateMREPlaybackButtonEnabled();
    app.showMREROIHotkeyHelp();

    % If a ROI already exists on this slice, pre-load it for editing.
    existMask = getStoredDixonROIMask(app, roiName, app.AppData.MREROISlice);
    if ~isempty(existMask) && any(existMask(:))
        app.AppData.MREROIOuterMask = existMask;
        app.AppData.MREROIFinalMask = existMask;
        refreshMRE(app);
        setStatus(app, sprintf('%s ROI loaded for editing (sl %d). R = vertex-edit, F = redraw, Enter = accept.', ...
            app.getMREROIOrganLabel(roiName), app.AppData.MREROISlice));
    else
        refreshMRE(app);
        setStatus(app, sprintf('%s ROI armed on slice %d. F = freehand  D = seed+auto  R = edit vertices.', ...
            app.getMREROIOrganLabel(roiName), app.AppData.MREROISlice));
    end
end

function tf = isMREROIWorkflowActive(app)
    tf = false;
    try
        tf = isvalid(app) && ~isempty(app.UIFigure) && isvalid(app.UIFigure) && ...
            isfield(app.AppData,'MREROIActive') && logical(app.AppData.MREROIActive) && ...
            ~isempty(app.AppData.MREROIName);
    catch
        tf = false;
    end
end

function organLabel = getMREROIOrganLabel(app, roiName)
    if nargin < 2 || isempty(roiName)
        roiName = app.AppData.MREROIName;
    end
    if contains(roiName, 'Liver')
        organLabel = 'Liver';
    elseif contains(roiName, 'Spleen')
        organLabel = 'Spleen';
    elseif contains(roiName, 'Muscle')
        organLabel = 'Muscle';
    elseif contains(roiName, 'Fat')
        organLabel = 'Fat';
    else
        organLabel = 'ROI';
    end
end

function thresh = getMREROIConfThresh(app, roiName)
    if nargin < 2 || isempty(roiName)
        roiName = app.AppData.MREROIName;
    end
    thresh = 0.50;
    try
        if isfield(app.AppData,'MREObjectConf') && isstruct(app.AppData.MREObjectConf) && isfield(app.AppData.MREObjectConf, roiName)
            thresh = double(app.AppData.MREObjectConf.(roiName));
        end
    catch
    end
    thresh = min(1, max(0, thresh));
end

function onMREObjectConfChange(app, roiName, src)
    val = min(1, max(0, double(src.Value)));
    if src.Value ~= val
        src.Value = val;
    end
    if ~isfield(app.AppData,'MREObjectConf') || ~isstruct(app.AppData.MREObjectConf)
        app.AppData.MREObjectConf = struct('LiverMRE',0.90,'SpleenMRE',0.75,'MuscleMRE',0.50,'FatMRE',0.90);
    end
    app.AppData.MREObjectConf.(roiName) = val;
    if app.isMREROIWorkflowActive() && strcmp(app.AppData.MREROIName, roiName) && ~isempty(app.AppData.MREROIOuterMask)
        app.recomputeCurrentMREROI(true);
    elseif ~isempty(app.AppData.MRE)
        app.updateMREAggregateStats(roiName);
        refreshMRE(app);
    end
end

function setCurrentMRETargetAxis(app, axisKey)
    if nargin < 2 || isempty(axisKey)
        axisKey = 'mag';
    end
    validKeys = {'mag','raw','proc','stiff'};
    if ~any(strcmp(axisKey, validKeys))
        axisKey = 'mag';
    end
    app.AppData.MRETargetAxis = axisKey;
end

function axisKey = inferCurrentMRETargetAxis(app)
    axisKey = 'mag';
    try
        if isfield(app.AppData,'MRETargetAxis') && ~isempty(app.AppData.MRETargetAxis)
            axisKey = app.AppData.MRETargetAxis;
        end
    catch
    end
    try
        obj = app.UIFigure.CurrentObject;
        while ~isempty(obj)
            if isequal(obj, app.AxMREMag)
                axisKey = 'mag'; break
            elseif isequal(obj, app.AxMRERawWave)
                axisKey = 'raw'; break
            elseif isequal(obj, app.AxMREWave)
                axisKey = 'proc'; break
            elseif isequal(obj, app.AxMREStiff)
                axisKey = 'stiff'; break
            end
            try
                obj = obj.Parent;
            catch
                break
            end
        end
    catch
    end
end

function ax = getMREAxisByKey(app, axisKey)
    switch lower(axisKey)
        case 'raw'
            ax = app.AxMRERawWave;
        case 'proc'
            ax = app.AxMREWave;
        case 'stiff'
            ax = app.AxMREStiff;
        otherwise
            ax = app.AxMREMag;
    end
end

function label = getMREAxisLabel(app, axisKey)
    switch lower(axisKey)
        case 'raw'
            label = 'Raw wave';
        case 'proc'
            label = 'Processed wave';
        case 'stiff'
            label = 'Elastogram';
        otherwise
            label = 'Magnitude';
    end
end

function setMREROIButtonsEnabled(app, tf)
    state = 'off';
    if tf, state = 'on'; end
    try, app.BtnROI_LiverMRE.Enable = state; catch, end
    try, app.BtnROI_SpleenMRE.Enable = state; catch, end
    try, app.BtnROI_MuscleMRE.Enable = state; catch, end
    try, app.BtnROI_FatMRE.Enable = state; catch, end
    try, app.BtnClearMREROIs.Enable = state; catch, end
    app.updateMREPlaybackButtonEnabled();
end

function showMREROIHotkeyHelp(app)
    app.LblMREInfo.Text = sprintf(['MRE ROI workflow hotkeys:' char(10) ...
        'Click a panel first. F = freehand on that panel, D = seed + auto on Magnitude' char(10) ...
        'R = edit vertices of existing ROI' char(10) ...
        'E = exclude, I = include, +/- = erosion (%d px)' char(10) ...
        'A or Enter = accept ROI, Esc = cancel' char(10) ...
        'Current panel: %s. ROI confidence LapC >= %.2f applies automatically.'], ...
        app.AppData.MREROIErodePx, app.getMREAxisLabel(app.AppData.MRETargetAxis), app.getMREROIConfThresh(app.AppData.MREROIName));
end

function resetMREROIHotkeyHelp(app)
    app.LblMREInfo.Text = sprintf(['MRE ROI workflow:' char(10) ...
        'Choose Liver, Spleen, Muscle, or Fat stiffness, then click a panel:' char(10) ...
        'F = freehand on panel, D = seed + auto on Magnitude' char(10) ...
        'E = exclude, I = include, +/- = erosion' char(10) ...
        'A or Enter = accept, Esc = cancel' char(10) ...
        'Use the Conf. fields under each organ button for ROI-specific LapC thresholds.']);
end

function handled = handleMREROIHotkey(app, event)
    handled = false;
    if ~app.isMREROIWorkflowActive()
        return
    end
    handled = true;
    key = lower(event.Key);
    ch = '';
    try
        ch = lower(event.Character);
    catch
    end
    if strcmp(ch, '+'), key = 'add'; end
    if strcmp(ch, '-'), key = 'subtract'; end
    switch key
        case 'escape'
            app.cancelMREROIWorkflow(true);
            setStatus(app, 'MRE ROI workflow cancelled.');
        case {'return','enter','a'}
            app.acceptCurrentMREROI();
        case 'f'
            app.setCurrentMRETargetAxis(app.inferCurrentMRETargetAxis());
            app.captureManualOuterMREROI();
        case 'd'
            app.setCurrentMRETargetAxis('mag');
            app.captureSeedAutoMREROI();
        case 'r'
            app.setCurrentMRETargetAxis(app.inferCurrentMRETargetAxis());
            editCurrentMREROIVertices(app);
        case {'e','x'}
            app.setCurrentMRETargetAxis(app.inferCurrentMRETargetAxis());
            app.excludeFromCurrentMREROI();
        case 'i'
            app.setCurrentMRETargetAxis(app.inferCurrentMRETargetAxis());
            app.includeIntoCurrentMREROI();
        case 'add'
            app.adjustCurrentMREROIErosion(+1);
        case 'subtract'
            app.adjustCurrentMREROIErosion(-1);
        otherwise
            handled = false;
    end
end

function captureManualOuterMREROI(app)
    if ~app.isMREROIWorkflowActive(), return; end
    nR = size(app.AppData.MRE.M, 1);
    nC = size(app.AppData.MRE.M, 2);
    roiColor = mreROIColor(app.AppData.MREROIName);
    axisKey = app.inferCurrentMRETargetAxis();
    app.setCurrentMRETargetAxis(axisKey);

    [popupFig, popupAx, imgData, cmapData, climVals] = app.openMREROIPopup(axisKey);
    if isempty(popupFig) || ~isvalid(popupFig)
        setStatus(app,'Could not open magnified drawing window.'); return
    end

    setStatus(app, 'Draw contour in magnified window. Double-click to finish.');
    app.AppData.MREROIDrawing = true;
    app.updateMREPlaybackButtonEnabled();
    drawCleanup = onCleanup(@()app.finishMREROIDrawing());
    mask = captureFreehandMask(app, popupAx, nR, nC, roiColor);
    clear drawCleanup;

    if ~isvalid(popupFig) || ~any(mask(:))
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        setStatus(app, 'Freehand contour was empty. Press F to try again or Esc to cancel.');
        return
    end

    % Stay in popup: allow include/exclude before final accept
    [mask, accepted] = roiPopupMultiOpLoop(app, popupFig, popupAx, mask, ...
        imgData, cmapData, climVals, roiColor, nR, nC, 'MRE');

    if isvalid(popupFig), delete(popupFig); end
    app.AppData.MREROIPopupFig = [];

    if ~accepted || ~any(mask(:))
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        setStatus(app, 'ROI discarded. Press F to retry or Esc to cancel workflow.');
        return
    end

    app.AppData.MREROIOuterMask = cleanOuterMask(app, mask);
    app.recomputeCurrentMREROI(true);
end

function captureSeedAutoMREROI(app)
    if ~app.isMREROIWorkflowActive(), return; end
    sl = app.AppData.MREROISlice;
    nR = size(app.AppData.MRE.M, 1);
    nC = size(app.AppData.MRE.M, 2);
    roiColor = mreROIColor(app.AppData.MREROIName);
    app.setCurrentMRETargetAxis('mag');
    Iseg = getMREMagnitudeForROI(app, sl);
    if isempty(Iseg)
        setStatus(app, 'Could not prepare the magnitude image for seed-based ROI.');
        return
    end
    setStatus(app, sprintf('Draw a seed circle inside the %s on Magnitude. Double-click to finish.', lower(app.getMREROIOrganLabel())));
    app.AppData.MREROIDrawing = true;
    app.updateMREPlaybackButtonEnabled();
    drawCleanup = onCleanup(@()app.finishMREROIDrawing());
    seedMask = captureSeedMask(app, app.AxMREMag, nR, nC, roiColor);
    clear drawCleanup;
    if ~any(seedMask(:))
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        setStatus(app, 'Seed circle was empty. Press D to try again or F for freehand.');
        return
    end
    outerMask = autoMaskFromSeedCircleApp(app, Iseg, seedMask);
    outerMask = cleanOuterMask(app, outerMask);
    if ~any(outerMask(:))
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        setStatus(app, 'Automatic contour failed. Press D to retry or F for freehand.');
        return
    end
    app.AppData.MREROIOuterMask = outerMask;
    app.recomputeCurrentMREROI(true);
end

function editCurrentMREROIVertices(app)
% Load the current MRE outer mask as an editable drawpolygon in a
% magnified popup window. Press A/Enter to accept, Esc to discard.
    if ~app.isMREROIWorkflowActive(), return; end
    mask = app.AppData.MREROIOuterMask;
    if isempty(mask) || ~any(mask(:))
        app.captureManualOuterMREROI(); return;
    end
    axisKey = app.inferCurrentMRETargetAxis();
    app.setCurrentMRETargetAxis(axisKey);
    [nR, nC] = size(mask);
    roiColor = mreROIColor(app.AppData.MREROIName);
    nVerts   = max(3, round(app.AppData.ROIVertices));

    [popupFig, popupAx, imgData, cmapData, climVals] = app.openMREROIPopup(axisKey);
    if isempty(popupFig) || ~isvalid(popupFig)
        setStatus(app,'Could not open magnified drawing window.'); return
    end

    bndList = bwboundaries(mask, 'noholes');
    if isempty(bndList)
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        app.captureManualOuterMREROI(); return;
    end
    [~, maxIdx] = max(cellfun(@(b) size(b,1), bndList));
    bnd  = bndList{maxIdx};
    pos0 = [bnd(:,2), bnd(:,1)];
    polyPts = roiResamplePolyline(pos0, nVerts);
    polyPts(:,1) = min(max(polyPts(:,1), 1), nC);
    polyPts(:,2) = min(max(polyPts(:,2), 1), nR);

    hPoly = [];
    try
        setStatus(app, 'Vertex edit in magnified window: drag vertices, double-click to confirm.');
        app.AppData.MREROIDrawing = true;
        app.updateMREPlaybackButtonEnabled();
        hPoly = drawpolygon(popupAx, ...
            'Position',  polyPts, ...
            'Color',     roiColor, ...
            'LineWidth', 1.8, ...
            'FaceAlpha', 0.10);
        wait(hPoly);
    catch
        try, delete(hPoly); catch, end
        app.AppData.MREROIDrawing = false;
        app.updateMREPlaybackButtonEnabled();
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        return
    end
    app.AppData.MREROIDrawing = false;
    app.updateMREPlaybackButtonEnabled();

    if isempty(hPoly) || ~isvalid(hPoly)
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        return
    end
    try, posFinal = hPoly.Position; catch, posFinal = []; end
    try, delete(hPoly); catch, end

    if isempty(posFinal) || size(posFinal,1) < 3
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        return
    end

    x0 = min(max(posFinal(:,1), 1), nC);
    y0 = min(max(posFinal(:,2), 1), nR);
    newMask = logical(poly2mask(x0, y0, nR, nC));
    newMask = imfill(newMask, 'holes');
    if ~any(newMask(:))
        try, delete(popupFig); catch, end
        app.AppData.MREROIPopupFig = [];
        return
    end

    % Multi-op loop: allow include/exclude before final accept
    [newMask, accepted] = roiPopupMultiOpLoop(app, popupFig, popupAx, newMask, ...
        imgData, cmapData, climVals, roiColor, nR, nC, 'MRE');

    if isvalid(popupFig), delete(popupFig); end
    app.AppData.MREROIPopupFig = [];

    if ~accepted || ~any(newMask(:)), return; end

    app.AppData.MREROIOuterMask = newMask;
    app.recomputeCurrentMREROI(true);
end

function adjustCurrentMREROIErosion(app, deltaPx)
    if ~app.isMREROIWorkflowActive() || isempty(app.AppData.MREROIOuterMask)
        setStatus(app, 'Press F or D first to create an outer contour before changing erosion.');
        return
    end
    app.AppData.MREROIErodePx = max(0, round(app.AppData.MREROIErodePx + deltaPx));
    app.recomputeCurrentMREROI(true);
end

function recomputeCurrentMREROI(app, doPreview)
    if nargin < 2, doPreview = true; end
    if ~app.isMREROIWorkflowActive(), return; end
    outerMask = logical(app.AppData.MREROIOuterMask);
    if isempty(outerMask) || ~any(outerMask(:))
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        return
    end
    sl = app.AppData.MREROISlice;
    confMask = getMREConfidenceMask(app, sl, [size(outerMask,1) size(outerMask,2)], app.AppData.MREROIName);
    baseInner = erodeMaskInward(app, outerMask, app.AppData.MREROIErodePx);
    finalMask = cleanMeasurementMask(app, baseInner & confMask);
    app.AppData.MREROIBaseInnerMask = baseInner;
    app.AppData.MREROIConfMask = confMask;
    app.AppData.MREROIFinalMask = finalMask;
    app.showMREROIHotkeyHelp();
    if doPreview
        refreshMRE(app);
    end
    if any(finalMask(:))
        setStatus(app, sprintf('%s ROI preview ready on slice %d. E/I refine, +/- erosion=%d px, Enter to accept.', app.getMREROIOrganLabel(), sl, app.AppData.MREROIErodePx));
    else
        setStatus(app, sprintf('ROI became empty after %d px erosion and confidence %.2f. Press - to reduce erosion, lower the threshold, redraw with F/D, or press Enter/A to accept this slice as technical failure.', app.AppData.MREROIErodePx, app.getMREROIConfThresh(app.AppData.MREROIName)));
    end
end

function excludeFromCurrentMREROI(app)
    if ~app.isMREROIWorkflowActive() || isempty(app.AppData.MREROIFinalMask) || ~any(app.AppData.MREROIFinalMask(:))
        setStatus(app, 'There is no measurement ROI to edit yet. Press F or D first.');
        return
    end
    nR = size(app.AppData.MREROIFinalMask,1);
    nC = size(app.AppData.MREROIFinalMask,2);
    axisKey = app.inferCurrentMRETargetAxis();
    app.setCurrentMRETargetAxis(axisKey);
    ax = app.getMREAxisByKey(axisKey);
    setStatus(app, sprintf('Draw a freehand region on %s to exclude from the measurement ROI.', app.getMREAxisLabel(axisKey)));
    app.AppData.MREROIDrawing = true;
    app.updateMREPlaybackButtonEnabled();
    drawCleanup = onCleanup(@()app.finishMREROIDrawing());
    delta = captureFreehandMask(app, ax, nR, nC, [1 0 1]);
    clear drawCleanup;
    if ~any(delta(:))
        refreshMRE(app);
        app.showMREROIHotkeyHelp();
        return
    end
    newMask = cleanMeasurementMask(app, app.AppData.MREROIFinalMask & ~delta);
    if ~any(newMask(:))
        refreshMRE(app);
        setStatus(app, 'That exclusion removed the entire ROI. The previous ROI was kept.');
        return
    end
    app.AppData.MREROIFinalMask = newMask;
    refreshMRE(app);
    app.showMREROIHotkeyHelp();
    setStatus(app, 'Region excluded from the measurement ROI.');
end

function includeIntoCurrentMREROI(app)
    if ~app.isMREROIWorkflowActive() || isempty(app.AppData.MREROIOuterMask) || ~any(app.AppData.MREROIOuterMask(:))
        setStatus(app, 'There is no outer contour yet. Press F or D first.');
        return
    end
    nR = size(app.AppData.MREROIOuterMask,1);
    nC = size(app.AppData.MREROIOuterMask,2);
    axisKey = app.inferCurrentMRETargetAxis();
    app.setCurrentMRETargetAxis(axisKey);
    ax = app.getMREAxisByKey(axisKey);
    setStatus(app, sprintf('Draw a freehand region on %s to add into the measurement ROI (disconnected islands allowed if confidence passes).', app.getMREAxisLabel(axisKey)));
    app.AppData.MREROIDrawing = true;
    app.updateMREPlaybackButtonEnabled();
    drawCleanup = onCleanup(@()app.finishMREROIDrawing());
    delta = captureFreehandMask(app, ax, nR, nC, mreROIColor(app.AppData.MREROIName));
    clear drawCleanup;
    if ~any(delta(:))
        if ~isempty(app.AppData.MREROIFinalMask) && any(app.AppData.MREROIFinalMask(:))
            refreshMRE(app);
        end
        app.showMREROIHotkeyHelp();
        return
    end
    allowed = true(nR,nC);
    if ~isempty(app.AppData.MREROIConfMask)
        allowed = logical(app.AppData.MREROIConfMask);
    end
    baseMask = false(nR,nC);
    if ~isempty(app.AppData.MREROIFinalMask)
        baseMask = logical(app.AppData.MREROIFinalMask);
    end
    newMask = cleanMeasurementMask(app, baseMask | (delta & allowed));
    if ~any(newMask(:))
        setStatus(app, 'The added region did not produce a valid ROI inside the confidence mask.');
        return
    end
    app.AppData.MREROIFinalMask = newMask;
    refreshMRE(app);
    app.showMREROIHotkeyHelp();
    setStatus(app, 'Region added to the measurement ROI.');
end

function acceptCurrentMREROI(app)
    if ~app.isMREROIWorkflowActive()
        return
    end
    if isfield(app.AppData,'MREROIBusy') && app.AppData.MREROIBusy
        return
    end
    try
        app.AppData.MREPlaybackWasOnBeforeROI = app.AppData.MREPlaying || ...
            (~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer));
    catch
        app.AppData.MREPlaybackWasOnBeforeROI = false;
    end
    app.pauseMREPlaybackForROI();
    app.AppData.MREROIBusy = true;
    app.updateMREPlaybackButtonEnabled();
    busyCleanup = onCleanup(@()app.clearMREROIBusy());

    roiName = app.AppData.MREROIName;
    sl = app.AppData.MREROISlice;
    finalMask = app.AppData.MREROIFinalMask;

    hasOuter = ~isempty(app.AppData.MREROIOuterMask) && any(app.AppData.MREROIOuterMask(:));
    hasBaseInner = ~isempty(app.AppData.MREROIBaseInnerMask) && any(app.AppData.MREROIBaseInnerMask(:));
    hasValid = ~isempty(finalMask) && any(finalMask(:));
    hasAttempt = hasOuter || hasBaseInner || hasValid;

    if ~hasValid
        if ~hasAttempt
            setStatus(app, 'There is no ROI attempt yet. Press F or D first, then Enter to accept.');
            return
        end
        nR = 0; nC = 0;
        try
            if ~isempty(app.AppData.MREROIOuterMask)
                [nR, nC] = size(app.AppData.MREROIOuterMask);
            elseif ~isempty(app.AppData.MREROIBaseInnerMask)
                [nR, nC] = size(app.AppData.MREROIBaseInnerMask);
            end
        catch
            nR = 0; nC = 0;
        end
        if nR <= 0 || nC <= 0
            try
                nR = size(app.AppData.MRE.M, 1);
                nC = size(app.AppData.MRE.M, 2);
            catch
                nR = 256; nC = 256;
            end
        end
        app.storeEmptyMREROISlice(roiName, sl, nR, nC);
        app.cancelMREROIWorkflow(false);
        try
            app.updateMREAggregateStats(roiName);
        catch ME
            refreshMRE(app);
            setStatus(app, sprintf('%s finalized on slice %d with no valid pixels, but the stats update failed: %s', app.getMREROIOrganLabel(roiName), sl, strtrim(ME.message)));
            return
        end
        refreshMRE(app);
        setStatus(app, sprintf('%s finalized on slice %d with no valid pixels after confidence masking (technical failure recorded; no ROI output stored).', app.getMREROIOrganLabel(roiName), sl));
        return
    end

    nR = size(finalMask,1);
    nC = size(finalMask,2);
    storeROI(app, roiName, sl, finalMask, nR, nC);
    app.cancelMREROIWorkflow(false);
    try
        computeMREROIStats(app, roiName, finalMask, sl);
    catch ME
        refreshMRE(app);
        setStatus(app, sprintf('%s ROI saved on slice %d, but the stats update failed: %s', app.getMREROIOrganLabel(roiName), sl, strtrim(ME.message)));
        return
    end
    try, app.updateResultsTable(); catch, end
    refreshMRE(app);
    setStatus(app, sprintf('%s ROI saved on slice %d.', app.getMREROIOrganLabel(roiName), sl));
    app.saveMREROIsToMat();   % persist MRE ROI to exam mat file
end

function cancelMREROIWorkflow(app, doRefresh)
    if nargin < 2, doRefresh = true; end
    if ~isfield(app.AppData,'MREROIActive')
        return
    end
    try
        if isfield(app.AppData,'MREROIPopupFig') && ...
                ~isempty(app.AppData.MREROIPopupFig) && ...
                isvalid(app.AppData.MREROIPopupFig)
            delete(app.AppData.MREROIPopupFig);
        end
    catch, end
    app.AppData.MREROIPopupFig = [];
    app.clearMREROIPreviewOverlay();
    app.AppData.MREROIActive = false;
    app.AppData.MREROIName = '';
    app.AppData.MREROISlice = NaN;
    app.AppData.MREROIOuterMask = [];
    app.AppData.MREROIBaseInnerMask = [];
    app.AppData.MREROIConfMask = [];
    app.AppData.MREROIFinalMask = [];
    app.AppData.MREROIErodePx = 2;
    app.AppData.MREROIDrawing = false;
    app.AppData.MREROIBusy = false;
    app.setMREROIButtonsEnabled(true);
    app.updateMREPlaybackButtonEnabled();
    app.resetMREROIHotkeyHelp();
    if doRefresh && ~isempty(app.AppData.MRE)
        refreshMRE(app);
    end
end

function I = getMREMagnitudeForROI(app, sl)

            I = [];
            try
                mre = app.AppData.MRE;
                nZ = size(mre.M, 3);
                sl = max(1, min(sl, nZ));
                if ndims(mre.M) >= 4
                    I = mean(double(mre.M(:,:,sl,:)), 4, 'omitnan');
                else
                    I = double(mre.M(:,:,sl));
                end
            catch
                I = [];
            end
        end

        % =================================================================
        %  DIXON ROI WORKFLOW  (parallel to MRE ROI workflow)
        % =================================================================

        function tf = isDixonROIWorkflowActive(app)
            tf = false;
            try
                tf = isvalid(app) && isfield(app.AppData,'DixonROIActive') && ...
                    logical(app.AppData.DixonROIActive) && ~isempty(app.AppData.DixonROIName);
            catch
            end
        end

        function organLabel = getDixonOrganLabel(app, roiName)
            if nargin < 2 || isempty(roiName), roiName = app.AppData.DixonROIName; end
            if contains(roiName,'Liver'),    organLabel = 'Liver';
            elseif contains(roiName,'Spleen'),  organLabel = 'Spleen';
            elseif contains(roiName,'Psoas'),   organLabel = 'Psoas Muscle';
            elseif contains(roiName,'Trunk'),   organLabel = 'Trunk Muscle';
            elseif contains(roiName,'Muscle'),  organLabel = 'Muscle';
            elseif contains(roiName,'SAT'),     organLabel = 'SAT';
            elseif contains(roiName,'VAT'),     organLabel = 'VAT';
            elseif contains(roiName,'Fat'),     organLabel = 'Fat';
            else,                               organLabel = 'ROI';
            end
        end

        function setDixonROIButtonsEnabled(app, tf)
            state = 'off'; if tf, state = 'on'; end
            try, app.BtnROI_LiverDixon.Enable   = state; catch, end
            try, app.BtnROI_SpleenDixon.Enable  = state; catch, end
            try, app.BtnROI_PsoasDixon.Enable   = state; catch, end
            try, app.BtnROI_TrunkDixon.Enable   = state; catch, end
            try, app.BtnROI_SATDixon.Enable     = state; catch, end
            try, app.BtnROI_VATDixon.Enable     = state; catch, end
            try, app.BtnClearDixonROIs.Enable   = state; catch, end
        end

        function showDixonROIHotkeyHelp(app)
            try
                app.LblDixonROIInfo.Text = sprintf(['%s ROI — slice %d' char(10) ...
                    'F = freehand   D = seed+auto' char(10) ...
                    'R = edit vertices of existing ROI' char(10) ...
                    'E/I = exclude/include region' char(10) ...
                    'Enter/A = accept   Esc = cancel'], ...
                    app.getDixonOrganLabel(), app.AppData.DixonROISlice);
            catch
            end
        end

        function resetDixonROIHotkeyHelp(app)
            try
                app.LblDixonROIInfo.Text = sprintf(['F = freehand on panel' char(10) ...
                    'D = seed+auto on panel' char(10) ...
                    'E/I = exclude/include' char(10) ...
                    'Enter/A = accept    Esc = cancel']);
            catch
            end
        end

        function setCurrentDixonTargetAxis(app, axisKey)
            validKeys = {'pdff','water','fat'};
            if nargin < 2 || ~any(strcmp(axisKey, validKeys)), axisKey = 'pdff'; end
            app.AppData.DixonTargetAxis = axisKey;
        end

        function axisKey = inferCurrentDixonTargetAxis(app)
            axisKey = 'pdff';
            try
                if isfield(app.AppData,'DixonTargetAxis') && ~isempty(app.AppData.DixonTargetAxis)
                    axisKey = app.AppData.DixonTargetAxis;
                end
                obj = app.UIFigure.CurrentObject;
                while ~isempty(obj)
                    if isequal(obj, app.AxDixonPDFF),  axisKey = 'pdff';  break
                    elseif isequal(obj, app.AxDixonIP), axisKey = 'water'; break
                    elseif isequal(obj, app.AxDixonWater), axisKey = 'fat'; break
                    end
                    try, obj = obj.Parent; catch, break; end
                end
            catch
            end
        end

        function ax = getDixonAxisByKey(app, axisKey)
            switch lower(axisKey)
                case 'water', ax = app.AxDixonIP;
                case 'fat',   ax = app.AxDixonWater;
                otherwise,    ax = app.AxDixonPDFF;
            end
        end

        function label = getDixonAxisLabel(~, axisKey)
            switch lower(axisKey)
                case 'water', label = 'Water/In-phase';
                case 'fat',   label = 'Fat/Out-of-phase';
                otherwise,    label = 'PDFF';
            end
        end

        function I = getDixonImageForROI(app, sl, axisKey)
            I = [];
            try
                dix = app.AppData.Dixon;
                switch lower(axisKey)
                    case 'water'
                        vol = dixonPreferredDisplayVolume(dix, 'InPhase');
                    case 'fat'
                        vol = dixonPreferredDisplayVolume(dix, 'OutPhase');
                    otherwise
                        vol = dixonPreferredDisplayVolume(dix, 'PDFF');
                        if isempty(vol), vol = dixonPreferredDisplayVolume(dix, 'InPhase'); end
                end
                if ~isempty(vol)
                    sl = max(1, min(sl, size(vol,3)));
                    I = double(vol(:,:,sl));
                end
            catch
            end
        end

        function cancelDixonROIWorkflow(app, doRefresh)
            if nargin < 2, doRefresh = true; end
            try
                if isfield(app.AppData,'DixonROIPopupFig') && ...
                        ~isempty(app.AppData.DixonROIPopupFig) && ...
                        isvalid(app.AppData.DixonROIPopupFig)
                    delete(app.AppData.DixonROIPopupFig);
                end
            catch, end
            app.AppData.DixonROIPopupFig = [];
            app.AppData.DixonROIActive   = false;
            app.AppData.DixonROIName     = '';
            app.AppData.DixonROISlice    = NaN;
            app.AppData.DixonROIOuterMask = [];
            app.AppData.DixonROIFinalMask = [];
            app.AppData.DixonROIErodePx  = 2;
            app.AppData.DixonROIDrawing  = false;
            app.setDixonROIButtonsEnabled(true);
            app.resetDixonROIHotkeyHelp();
            if doRefresh && ~isempty(app.AppData.Dixon)
                refreshDixon(app);
            end
        end

        function recomputeCurrentDixonROI(app, doPreview)
            if nargin < 2, doPreview = true; end
            if ~app.isDixonROIWorkflowActive(), return; end
            outerMask = logical(app.AppData.DixonROIOuterMask);
            if isempty(outerMask) || ~any(outerMask(:))
                if doPreview, refreshDixon(app); end
                app.showDixonROIHotkeyHelp();
                return
            end
            % No automatic erosion for Dixon — use outer mask directly.
            finalMask = cleanMeasurementMask(app, outerMask);
            app.AppData.DixonROIFinalMask = finalMask;
            app.showDixonROIHotkeyHelp();
            if doPreview, refreshDixon(app); end
            if any(finalMask(:))
                setStatus(app, sprintf('%s ROI preview on slice %d. E/I to refine, Enter to accept.', ...
                    app.getDixonOrganLabel(), app.AppData.DixonROISlice));
            else
                setStatus(app, 'ROI is empty — redraw with F or D, or press Esc to cancel.');
            end
        end

        function captureManualOuterDixonROI(app)
            if ~app.isDixonROIWorkflowActive(), return; end
            axisKey = app.inferCurrentDixonTargetAxis();
            app.setCurrentDixonTargetAxis(axisKey);
            sl = app.AppData.DixonROISlice;
            I = app.getDixonImageForROI(sl, axisKey);
            if isempty(I), setStatus(app,'No image on selected panel.'); return; end
            [nR, nC] = size(I);
            roiColor = dixonROIColor(app.AppData.DixonROIName);

            [popupFig, popupAx, imgData, cmapData, climVals] = app.openDixonROIPopup(axisKey);
            if isempty(popupFig) || ~isvalid(popupFig)
                setStatus(app,'Could not open magnified drawing window.'); return
            end

            setStatus(app, 'Draw contour in magnified window. Double-click to finish.');
            app.AppData.DixonROIDrawing = true;
            mask = captureFreehandMask(app, popupAx, nR, nC, roiColor);
            app.AppData.DixonROIDrawing = false;

            if ~isvalid(popupFig) || ~any(mask(:))
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                refreshDixon(app); app.showDixonROIHotkeyHelp();
                setStatus(app,'Freehand contour was empty. Press F to retry or Esc to cancel.');
                return
            end

            % Fill + merge with any existing mask (bilateral structures)
            try, mask = imfill(logical(mask), 'holes'); catch, mask = logical(mask); end
            existing = logical(app.AppData.DixonROIFinalMask);
            if ~isequal(size(existing), [nR nC]), existing = false(nR, nC); end
            mask = existing | mask;

            % Stay in popup: allow include/exclude before final accept
            [mask, accepted] = roiPopupMultiOpLoop(app, popupFig, popupAx, mask, ...
                imgData, cmapData, climVals, roiColor, nR, nC, 'Dixon');

            if isvalid(popupFig), delete(popupFig); end
            app.AppData.DixonROIPopupFig = [];

            if ~accepted || ~any(mask(:))
                refreshDixon(app); app.showDixonROIHotkeyHelp();
                setStatus(app,'ROI discarded. Press F to retry or Esc to cancel workflow.');
                return
            end

            app.AppData.DixonROIOuterMask = mask;
            app.AppData.DixonROIFinalMask = mask;
            app.acceptCurrentDixonROI();
        end

        function captureSATFreehandDixonROI(app)
        % Legacy stub — SAT now uses the same freehand polygon as other organs.
            app.captureManualOuterDixonROI();
        end

        function captureSeedAutoDixonROI(app)
        % Dispatch to organ-specific seed-and-grow strategy:
        %   LiverDixon / SpleenDixon — user draws rough outline → eroded
        %     seed core → multi-channel constrained grow.
        %   SATDixon — fully automatic hard ring geometry (non-negotiable).
        %   VATDixon / MuscleDixon  — legacy circle seed + generic grow.
            if ~app.isDixonROIWorkflowActive(), return; end
            roiName = app.AppData.DixonROIName;
            sl      = app.AppData.DixonROISlice;
            dix     = app.AppData.Dixon;

            switch roiName

                % ── Liver: rough outline → eroded core → multi-channel grow ──
                case 'LiverDixon'
                    axisKey = app.inferCurrentDixonTargetAxis();
                    app.setCurrentDixonTargetAxis(axisKey);
                    I  = app.getDixonImageForROI(sl, axisKey);
                    if isempty(I)
                        setStatus(app,'No image on selected panel.'); return;
                    end
                    nR = size(I,1); nC = size(I,2);
                    [popupFig, popupAx] = app.openDixonROIPopup(axisKey);
                    if isempty(popupFig) || ~isvalid(popupFig)
                        setStatus(app,'Could not open magnified drawing window.'); return
                    end
                    setStatus(app, 'Draw ROUGH liver outline in magnified window. Double-click to finish.');
                    app.AppData.DixonROIDrawing = true;
                    roughMask = captureFreehandMask(app, popupAx, nR, nC, dixonROIColor(roiName));
                    app.AppData.DixonROIDrawing = false;
                    try, delete(popupFig); catch, end
                    app.AppData.DixonROIPopupFig = [];
                    if ~any(roughMask(:))
                        refreshDixon(app); app.showDixonROIHotkeyHelp();
                        setStatus(app,'Outline empty. Press D to retry or F for freehand.'); return;
                    end
                    setStatus(app,'Refining liver contour (multi-channel grow)...');
                    outerMask = dixonSeedGrowLiver(dix, roughMask, sl);

                % ── Spleen: rough outline → eroded core → compact grow ─────────
                case 'SpleenDixon'
                    axisKey = app.inferCurrentDixonTargetAxis();
                    app.setCurrentDixonTargetAxis(axisKey);
                    I  = app.getDixonImageForROI(sl, axisKey);
                    if isempty(I)
                        setStatus(app,'No image on selected panel.'); return;
                    end
                    nR = size(I,1); nC = size(I,2);
                    [popupFig, popupAx] = app.openDixonROIPopup(axisKey);
                    if isempty(popupFig) || ~isvalid(popupFig)
                        setStatus(app,'Could not open magnified drawing window.'); return
                    end
                    setStatus(app, 'Draw ROUGH spleen outline in magnified window. Double-click to finish.');
                    app.AppData.DixonROIDrawing = true;
                    roughMask = captureFreehandMask(app, popupAx, nR, nC, dixonROIColor(roiName));
                    app.AppData.DixonROIDrawing = false;
                    try, delete(popupFig); catch, end
                    app.AppData.DixonROIPopupFig = [];
                    if ~any(roughMask(:))
                        refreshDixon(app); app.showDixonROIHotkeyHelp();
                        setStatus(app,'Outline empty. Press D to retry or F for freehand.'); return;
                    end
                    setStatus(app,'Refining spleen contour (compact grow)...');
                    outerMask = dixonSeedGrowSpleen(dix, roughMask, sl);

                % ── SAT: fully automatic hard ring geometry ────────────────────
                case 'SATDixon'
                    setStatus(app,'Computing SAT ring mask (automatic body ring, PDFF-guided)...');
                    outerMask = dixonSeedGrowSAT(dix, sl);

                % ── VAT / Muscle: legacy circle-seed + generic grow ────────────
                otherwise
                    axisKey = app.inferCurrentDixonTargetAxis();
                    app.setCurrentDixonTargetAxis(axisKey);
                    I  = app.getDixonImageForROI(sl, axisKey);
                    if isempty(I)
                        setStatus(app,'No image on selected panel for seeding.'); return;
                    end
                    nR = size(I,1); nC = size(I,2);
                    [popupFig, popupAx] = app.openDixonROIPopup(axisKey);
                    if isempty(popupFig) || ~isvalid(popupFig)
                        setStatus(app,'Could not open magnified drawing window.'); return
                    end
                    setStatus(app, sprintf('Draw seed circle inside %s. Double-click to finish.', ...
                        lower(app.getDixonOrganLabel())));
                    app.AppData.DixonROIDrawing = true;
                    seedMask = captureSeedMask(app, popupAx, nR, nC, dixonROIColor(roiName));
                    app.AppData.DixonROIDrawing = false;
                    try, delete(popupFig); catch, end
                    app.AppData.DixonROIPopupFig = [];
                    if ~any(seedMask(:))
                        refreshDixon(app); app.showDixonROIHotkeyHelp();
                        setStatus(app,'Seed circle empty. Press D to retry or F for freehand.'); return;
                    end
                    outerMask = autoMaskFromSeedCircleApp(app, I, seedMask);
            end

            outerMask = cleanOuterMask(app, outerMask);
            if ~any(outerMask(:))
                refreshDixon(app); app.showDixonROIHotkeyHelp();
                setStatus(app,'Auto contour failed. Press D to retry or F for freehand.');
                return
            end
            app.AppData.DixonROIOuterMask = outerMask;
            app.recomputeCurrentDixonROI(true);
        end

        function excludeFromCurrentDixonROI(app)
            if ~app.isDixonROIWorkflowActive() || isempty(app.AppData.DixonROIFinalMask) || ...
                    ~any(app.AppData.DixonROIFinalMask(:))
                setStatus(app,'No ROI to edit yet. Press F or D first.'); return
            end
            nR = size(app.AppData.DixonROIFinalMask,1);
            nC = size(app.AppData.DixonROIFinalMask,2);
            axisKey = app.inferCurrentDixonTargetAxis();
            ax = app.getDixonAxisByKey(axisKey);
            setStatus(app, sprintf('Draw region on %s to EXCLUDE.', app.getDixonAxisLabel(axisKey)));
            app.AppData.DixonROIDrawing = true;
            delta = captureFreehandMask(app, ax, nR, nC, [1 0 1]);
            app.AppData.DixonROIDrawing = false;
            if ~any(delta(:)), refreshDixon(app); app.showDixonROIHotkeyHelp(); return; end
            newMask = cleanMeasurementMask(app, app.AppData.DixonROIFinalMask & ~delta);
            if ~any(newMask(:))
                refreshDixon(app); setStatus(app,'Exclusion removed entire ROI — kept previous.'); return
            end
            app.AppData.DixonROIFinalMask = newMask;
            refreshDixon(app); app.showDixonROIHotkeyHelp();
            setStatus(app,'Region excluded.');
        end

        function includeIntoCurrentDixonROI(app)
            if ~app.isDixonROIWorkflowActive() || isempty(app.AppData.DixonROIOuterMask) || ...
                    ~any(app.AppData.DixonROIOuterMask(:))
                setStatus(app,'No outer contour yet. Press F or D first.'); return
            end
            nR = size(app.AppData.DixonROIOuterMask,1);
            nC = size(app.AppData.DixonROIOuterMask,2);
            axisKey = app.inferCurrentDixonTargetAxis();
            ax = app.getDixonAxisByKey(axisKey);
            setStatus(app, sprintf('Draw region on %s to INCLUDE.', app.getDixonAxisLabel(axisKey)));
            app.AppData.DixonROIDrawing = true;
            delta = captureFreehandMask(app, ax, nR, nC, dixonROIColor(app.AppData.DixonROIName));
            app.AppData.DixonROIDrawing = false;
            if ~any(delta(:))
                if ~isempty(app.AppData.DixonROIFinalMask) && any(app.AppData.DixonROIFinalMask(:))
                    refreshDixon(app);
                end
                app.showDixonROIHotkeyHelp(); return
            end
            baseMask = false(nR,nC);
            if ~isempty(app.AppData.DixonROIFinalMask), baseMask = logical(app.AppData.DixonROIFinalMask); end
            newMask = cleanMeasurementMask(app, baseMask | delta);
            if ~any(newMask(:)), setStatus(app,'Added region produced empty ROI.'); return; end
            app.AppData.DixonROIFinalMask = newMask;
            refreshDixon(app); app.showDixonROIHotkeyHelp();
            setStatus(app,'Region included.');
        end

        function editCurrentDixonROIVertices(app)
        % Load the current outer mask as an editable drawpolygon in a
        % magnified popup window. Press A/Enter to accept, Esc to discard.
            if ~app.isDixonROIWorkflowActive(), return; end
            mask = app.AppData.DixonROIOuterMask;
            if isempty(mask) || ~any(mask(:))
                app.captureManualOuterDixonROI(); return;
            end
            axisKey = app.inferCurrentDixonTargetAxis();
            app.setCurrentDixonTargetAxis(axisKey);
            [nR, nC] = size(mask);
            roiColor = dixonROIColor(app.AppData.DixonROIName);
            nVerts   = max(3, round(app.AppData.ROIVertices));

            [popupFig, popupAx, imgData, cmapData, climVals] = app.openDixonROIPopup(axisKey);
            if isempty(popupFig) || ~isvalid(popupFig)
                setStatus(app,'Could not open magnified drawing window.'); return
            end

            bndList = bwboundaries(mask, 'noholes');
            if isempty(bndList)
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                app.captureManualOuterDixonROI(); return;
            end
            [~, maxIdx] = max(cellfun(@(b) size(b,1), bndList));
            bnd  = bndList{maxIdx};
            pos0 = [bnd(:,2), bnd(:,1)];
            polyPts = roiResamplePolyline(pos0, nVerts);
            polyPts(:,1) = min(max(polyPts(:,1), 1), nC);
            polyPts(:,2) = min(max(polyPts(:,2), 1), nR);

            hPoly = [];
            try
                setStatus(app, 'Vertex edit in magnified window: drag vertices, double-click to confirm.');
                app.AppData.DixonROIDrawing = true;
                hPoly = drawpolygon(popupAx, ...
                    'Position',  polyPts, ...
                    'Color',     roiColor, ...
                    'LineWidth', 1.8, ...
                    'FaceAlpha', 0.10);
                wait(hPoly);
            catch
                try, delete(hPoly); catch, end
                app.AppData.DixonROIDrawing = false;
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                return
            end
            app.AppData.DixonROIDrawing = false;

            if isempty(hPoly) || ~isvalid(hPoly)
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                return
            end
            try, posFinal = hPoly.Position; catch, posFinal = []; end
            try, delete(hPoly); catch, end

            if isempty(posFinal) || size(posFinal,1) < 3
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                return
            end

            x0 = min(max(posFinal(:,1), 1), nC);
            y0 = min(max(posFinal(:,2), 1), nR);
            newMask = logical(poly2mask(x0, y0, nR, nC));
            newMask = imfill(newMask, 'holes');
            if ~any(newMask(:))
                try, delete(popupFig); catch, end
                app.AppData.DixonROIPopupFig = [];
                return
            end

            % Multi-op loop: allow include/exclude before final accept
            [newMask, accepted] = roiPopupMultiOpLoop(app, popupFig, popupAx, newMask, ...
                imgData, cmapData, climVals, roiColor, nR, nC, 'Dixon');

            if isvalid(popupFig), delete(popupFig); end
            app.AppData.DixonROIPopupFig = [];

            if ~accepted || ~any(newMask(:)), return; end

            app.AppData.DixonROIOuterMask = newMask;
            app.recomputeCurrentDixonROI(true);
        end

        function adjustCurrentDixonROIErosion(app, deltaPx)
            if ~app.isDixonROIWorkflowActive() || isempty(app.AppData.DixonROIOuterMask)
                setStatus(app,'Press F or D first before adjusting erosion.'); return
            end
            app.AppData.DixonROIErodePx = max(0, round(app.AppData.DixonROIErodePx + deltaPx));
            app.recomputeCurrentDixonROI(true);
        end

        function acceptCurrentDixonROI(app)
            if ~app.isDixonROIWorkflowActive(), return; end
            roiName  = app.AppData.DixonROIName;
            sl       = app.AppData.DixonROISlice;
            finalMask = app.AppData.DixonROIFinalMask;
            hasOuter  = ~isempty(app.AppData.DixonROIOuterMask) && any(app.AppData.DixonROIOuterMask(:));
            hasValid  = ~isempty(finalMask) && any(finalMask(:));
            if ~hasOuter && ~hasValid
                app.cancelDixonROIWorkflow(true);
                setStatus(app,'Nothing to accept — ROI cancelled.'); return
            end
            % Get reference size from any available Dixon volume
            dix = app.AppData.Dixon;
            baseVol = dixonPreferredDisplayVolume(dix, 'PDFF');
            if isempty(baseVol), baseVol = dixonPreferredDisplayVolume(dix,'InPhase'); end
            if isempty(baseVol), baseVol = dixonPreferredDisplayVolume(dix,'OutPhase'); end
            nR = size(baseVol,1); nC = size(baseVol,2);
            if ~hasValid
                finalMask = false(nR,nC);  % technical failure — store empty
            end
            storeROI(app, roiName, sl, finalMask, nR, nC);
            if hasValid
                computeAggregatedDixonROIStats(app, roiName);
            end
            app.cancelDixonROIWorkflow(false);
            try, app.updateResultsTable(); catch, end
            refreshDixon(app);
            setStatus(app, sprintf('%s ROI accepted on slice %d.', app.getDixonOrganLabel(roiName), sl));
            app.savePDFFMat();  % persist Dixon ROI to exam folder
        end

        function handled = handleDixonROIHotkey(app, event)
            handled = false;
            if ~app.isDixonROIWorkflowActive(), return; end
            % Block re-entry: if a freehand/polygon draw is already blocking
            % on wait(), ignore all further hotkeys until it finishes.
            try
                if app.AppData.DixonROIDrawing, return; end
            catch, end
            handled = true;
            key = lower(event.Key);
            switch key
                case 'escape'
                    app.cancelDixonROIWorkflow(true);
                    setStatus(app,'Dixon ROI workflow cancelled.');
                case {'return','enter','a'}
                    app.acceptCurrentDixonROI();
                case 'f'
                    app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
                    app.captureManualOuterDixonROI();
                case 'd'
                    app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
                    app.captureSeedAutoDixonROI();
                case 'r'
                    app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
                    app.editCurrentDixonROIVertices();
                case {'e','x'}
                    app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
                    app.excludeFromCurrentDixonROI();
                case 'i'
                    app.setCurrentDixonTargetAxis(app.inferCurrentDixonTargetAxis());
                    app.includeIntoCurrentDixonROI();
                otherwise
                    handled = false;
            end
        end

        % =================================================================
        %  END DIXON ROI WORKFLOW
        % =================================================================

        function seedMask = captureSeedMask(app, ax, nR, nC, seedColor)
            seedMask = false(nR, nC);
            hSeed = [];
            try
                hSeed = drawcircle(ax, 'LineWidth', 1.6, 'Color', seedColor);
            catch
                try
                    hSeed = drawellipse(ax, 'LineWidth', 1.6, 'Color', seedColor);
                catch
                    uialert(app.UIFigure, 'drawcircle/drawellipse is not available in this MATLAB installation.', 'Seed Tool');
                    return
                end
            end
            if isempty(hSeed) || ~isvalid(hSeed), return; end
            try
                if isprop(hSeed,'Center') && isprop(hSeed,'Radius')
                    cx = hSeed.Center(1);
                    cy = hSeed.Center(2);
                    rr = hSeed.Radius;
                    seedMask = circleMaskFromGeom(cx, cy, rr, nR, nC);
                elseif isprop(hSeed,'Center') && isprop(hSeed,'SemiAxes')
                    cx = hSeed.Center(1);
                    cy = hSeed.Center(2);
                    rr = mean(hSeed.SemiAxes);
                    seedMask = circleMaskFromGeom(cx, cy, rr, nR, nC);
                else
                    seedMask = createMask(hSeed);
                end
            catch
                try
                    seedMask = createMask(hSeed);
                catch
                end
            end
            try, delete(hSeed); catch, end
            seedMask = logical(seedMask);
        end

        function mask = captureFreehandMask(app, ax, nR, nC, roiColor)
        % Three-phase ROI capture:
        %   Phase 1 — user draws freehand contour (mouse drag, release to close).
        %   Phase 2 — contour is resampled to N polygon vertices shown as an
        %             editable drawpolygon; user refines by dragging vertices,
        %             then double-clicks the polygon interior to confirm.
        %   Phase 3 — automatic contour optimisation within a 2-px boundary
        %             band using edge strength, core statistics, and local
        %             variance; result is smoothed before returning.
            mask   = false(nR, nC);
            nVerts = max(3, round(app.AppData.ROIVertices));

            % ── Phase 1: freehand draw ────────────────────────────────────
            hFree = [];
            try
                if exist('drawfreehand','file') == 2
                    hFree = drawfreehand(ax, 'Color', roiColor, ...
                        'LineWidth', 1.5, 'FaceAlpha', 0.06);
                else
                    % Older toolbox: drawpolygon in draw mode (no Position)
                    hFree = drawpolygon(ax, 'Color', roiColor, ...
                        'LineWidth', 1.5, 'FaceAlpha', 0.06);
                end
            catch
                return
            end
            if isempty(hFree) || ~isvalid(hFree), return; end
            try, posRaw = hFree.Position; catch, posRaw = []; end
            try, delete(hFree); catch, end

            if isempty(posRaw) || size(posRaw,1) < 3, return; end

            % ── Phase 2: resample → editable polygon ─────────────────────
            polyPts = roiResamplePolyline(posRaw, nVerts);

            hPoly = [];
            try
                setStatus(app, sprintf( ...
                    'Polygon: %d vertices. Drag to refine. Double-click interior to confirm.', ...
                    nVerts));
                hPoly = drawpolygon(ax, ...
                    'Position',   polyPts, ...
                    'Color',      roiColor, ...
                    'LineWidth',  1.8, ...
                    'FaceAlpha',  0.10);
                wait(hPoly);   % blocks until double-click or deletion
            catch
                try, delete(hPoly); catch, end
                return
            end

            if isempty(hPoly) || ~isvalid(hPoly), return; end
            try, posFinal = hPoly.Position; catch, posFinal = []; end
            try, delete(hPoly); catch, end

            if isempty(posFinal) || size(posFinal,1) < 3, return; end

            % ── Phase 3: automatic contour optimisation ───────────────────
            setStatus(app, 'Optimising contour boundary...');
            try
                imgData = getimage(ax);
                if ~isempty(imgData) && isnumeric(imgData)
                    % Use first channel if RGB
                    if ndims(imgData) == 3, imgData = imgData(:,:,1); end
                    imgData = double(imgData);
                    mask = optimizeContourBand(posFinal, imgData, nR, nC);
                else
                    x = min(max(posFinal(:,1), 1), nC);
                    y = min(max(posFinal(:,2), 1), nR);
                    mask = logical(poly2mask(x, y, nR, nC));
                end
            catch
                x = min(max(posFinal(:,1), 1), nC);
                y = min(max(posFinal(:,2), 1), nR);
                mask = logical(poly2mask(x, y, nR, nC));
            end
        end

        function onROIVerticesChanged(app, src)
        % Sync vertex count between Dixon and MRE tabs.
            nV = max(3, round(src.Value));
            src.Value = nV;
            app.AppData.ROIVertices = nV;
            try
                if ~isequal(src, app.EdtROIVerticesDixon)
                    app.EdtROIVerticesDixon.Value = nV;
                end
            catch, end
            try
                if ~isequal(src, app.EdtROIVerticesMRE)
                    app.EdtROIVerticesMRE.Value = nV;
                end
            catch, end
        end

        function choice = askROIChoice(app, msg, options, defaultOption, cancelOption)
            choice = cancelOption;
            try
                choice = uiconfirm(app.UIFigure, msg, 'MRE ROI Workflow', ...
                    'Options', options, 'DefaultOption', defaultOption, ...
                    'CancelOption', cancelOption, 'Icon', 'question');
            catch
                if ~isempty(defaultOption)
                    choice = defaultOption;
                end
            end
        end

        function previewTempMREROI(app, mask, roiName, sl)
            if isempty(app), return; end
            try
                if ~isvalid(app), return; end
            catch
                return
            end
            app.clearMREROIPreviewOverlay();
            if ~any(mask(:)), return; end
            freezeKey = '';
            if isfield(app.AppData,'MREROIDrawing') && app.AppData.MREROIDrawing
                freezeKey = app.AppData.MRETargetAxis;
            end
            B = bwboundaries(mask);
            holeMask = getMaskHoleMask(mask);
            axesList = {'mag', app.AxMREMag; 'raw', app.AxMRERawWave; 'proc', app.AxMREWave; 'stiff', app.AxMREStiff};
            for ii = 1:size(axesList,1)
                if strcmp(freezeKey, axesList{ii,1}), continue; end
                ax = axesList{ii,2};
                hold(ax, 'on');
                for b = 1:numel(B)
                    pts = B{b};
                    hp = plot(ax, pts(:,2), pts(:,1), '-', 'Color', mreROIColor(roiName), 'LineWidth', 2.0);
                    try; hp.Tag = 'MREROIPreview'; hp.HitTest='off'; hp.PickableParts='none'; catch; end
                end
                if any(holeMask(:))
                    hh = overlayCheckerMask(ax, holeMask, 0.34);
                    try; hh.Tag = 'MREROIPreview'; hh.HitTest='off'; hh.PickableParts='none'; catch; end
                end
                hold(ax, 'off');
            end
            try
                drawnow limitrate nocallbacks;
            catch
                drawnow limitrate;
            end
        end

        function clearMREROIPreviewOverlay(app, skipAxisKey)
            if nargin < 2, skipAxisKey = ''; end
            axesToClear = {'mag', app.AxMREMag; 'raw', app.AxMRERawWave; 'proc', app.AxMREWave; 'stiff', app.AxMREStiff};
            for ii = 1:size(axesToClear,1)
                if strcmp(skipAxisKey, axesToClear{ii,1}), continue; end
                ax = axesToClear{ii,2};
                try
                    if isempty(ax) || ~isvalid(ax), continue; end
                    hPrev = findobj(ax.Children, 'flat', 'Tag', 'MREROIPreview');
                    if ~isempty(hPrev)
                        delete(hPrev);
                    end
                catch
                end
            end
        end

        function clearMRERefreshOverlay(app, skipAxisKey)
            if nargin < 2, skipAxisKey = ''; end
            axesToClear = {'mag', app.AxMREMag; 'raw', app.AxMRERawWave; 'proc', app.AxMREWave; 'stiff', app.AxMREStiff};
            for ii = 1:size(axesToClear,1)
                if strcmp(skipAxisKey, axesToClear{ii,1}), continue; end
                ax = axesToClear{ii,2};
                try
                    if isempty(ax) || ~isvalid(ax), continue; end
                    hPrev = findobj(ax.Children, 'flat', 'Tag', 'MRERefreshOverlay');
                    if ~isempty(hPrev)
                        delete(hPrev);
                    end
                catch
                end
            end
        end

        function goodMask = getMREConfidenceMask(app, sl, outSize, roiName)
            if nargin < 4 || isempty(outSize)
                outSize = [size(app.AppData.MRE.M,1), size(app.AppData.MRE.M,2)];
            end
            if nargin < 5
                roiName = '';
            end
            goodMask = true(outSize);
            thr = app.getMREROIConfThresh(roiName);
            try
                mre = app.AppData.MRE;
                if isfield(mre,'LapC') && ~isempty(mre.LapC)
                    sl = max(1, min(sl, size(mre.LapC, 3)));
                    LapC = double(squeeze(mre.LapC(:,:,sl)));
                    if ~isequal(size(LapC), outSize)
                        LapC = imresize(LapC, outSize, 'nearest');
                    end
                    goodMask = LapC >= thr;
                end
            catch
            end
            goodMask = logical(goodMask);
        end

        function mask = erodeMaskInward(app, maskIn, erodePx)
            mask = logical(maskIn);
            if nargin < 3 || isempty(erodePx), erodePx = 2; end
            if ~any(mask(:)), return; end
            try
                se = strel('disk', erodePx, 0);
            catch
                se = strel('disk', erodePx);
            end
            m2 = imerode(mask, se);
            if any(m2(:))
                mask = m2;
            end
        end

        function mask = cleanOuterMask(app, maskIn)
            mask = logical(maskIn);
            if ~any(mask(:)), return; end
            try
                mask = imfill(mask, 'holes');
            catch
            end
            try
                mask = bwareaopen(mask, 100);
            catch
            end
            try
                if any(mask(:)), mask = bwareafilt(mask, 1); end
            catch
            end
        end

        function mask = cleanMeasurementMask(app, maskIn)
            mask = logical(maskIn);
            if ~any(mask(:)), return; end
            try
                mask = bwareaopen(mask, 12);
            catch
            end
        end

        function mask = autoMaskFromSeedCircleApp(app, I, seedMask)
            mask = false(size(I));
            if isempty(I) || ~any(seedMask(:)), return; end
            I = double(I);
            I(~isfinite(I)) = 0;
            loI = prctile(I(:), 1);
            hiI = prctile(I(:), 99);
            if ~isfinite(loI) || ~isfinite(hiI) || hiI <= loI
                I = mat2gray(I);
            else
                I = (I - loI) ./ max(eps, (hiI - loI));
                I = min(max(I, 0), 1);
            end

            seedVals = I(seedMask);
            seedVals = seedVals(isfinite(seedVals));
            if numel(seedVals) < 20
                return;
            end

            lo0 = prctile(seedVals, 10);
            hi0 = prctile(seedVals, 90);
            w0  = hi0 - lo0;
            if ~isfinite(w0) || w0 <= 0
                w0 = 0.05;
            end

            minA = 200;
            maxA = 0.60 * numel(I);
            best = false(size(I));
            bestScore = -inf;
            expandList = [0.20 0.35 0.50 0.75 1.00];

            for ex = expandList
                lo = max(0, lo0 - ex*w0 - 0.02);
                hi = min(1, hi0 + ex*w0 + 0.02);
                cand = (I >= lo) & (I <= hi);
                try, cand = imfill(cand, 'holes'); catch, end
                try, cand = bwareaopen(cand, 100); catch, end
                try
                    cand = imclose(cand, strel('disk', 2, 0));
                catch
                    try, cand = imclose(cand, strel('disk', 2)); catch, end
                end

                CC = bwconncomp(cand, 8);
                if CC.NumObjects < 1
                    continue;
                end

                ov = zeros(CC.NumObjects, 1);
                sz = zeros(CC.NumObjects, 1);
                for iCC = 1:CC.NumObjects
                    pix = CC.PixelIdxList{iCC};
                    ov(iCC) = nnz(seedMask(pix));
                    sz(iCC) = numel(pix);
                end

                [ovBest, idx] = max(ov);
                if ovBest == 0
                    [~, idx] = max(sz);
                    ovBest = 0;
                end

                m = false(size(I));
                m(CC.PixelIdxList{idx}) = true;
                try, m = imfill(m, 'holes'); catch, end
                a = nnz(m);
                if a < minA || a > maxA
                    score = ovBest - 1e6;
                else
                    score = ovBest - 0.001*a;
                end

                if score > bestScore
                    bestScore = score;
                    best = m;
                end

                if ovBest > 0 && a >= minA && a <= maxA
                    mask = m;
                    return
                end
            end

            mask = best;
            try
                if any(mask(:)), mask = bwareafilt(mask, 1); end
            catch
            end
        end

        function clearMRESlice(app)
            sl = app.AppData.MRESlice;
            if isfield(app.AppData,'MREPlaying') && app.AppData.MREPlaying
                app.stopMREPlayback();
            end
            app.AppData.ROIs.LiverMRE.Slices  = removeSlice(app.AppData.ROIs.LiverMRE.Slices,  sl);
            app.AppData.ROIs.SpleenMRE.Slices = removeSlice(app.AppData.ROIs.SpleenMRE.Slices, sl);
            app.AppData.ROIs.MuscleMRE.Slices = removeSlice(app.AppData.ROIs.MuscleMRE.Slices, sl);
            app.AppData.ROIs.FatMRE.Slices    = removeSlice(app.AppData.ROIs.FatMRE.Slices, sl);
            app.updateAllMREStats();
            refreshMRE(app);
            setStatus(app,sprintf('MRE ROIs cleared for slice %d.',sl));
        end

        function onWaveMaxChange(app, src)
            app.AppData.WaveMax = max(0, src.Value);
            if ~isempty(app.AppData.MRE)
                refreshMRE(app);
            end
        end

        
function onConfThreshChange(app, src)
    app.AppData.ConfThresh = min(1, max(0, src.Value));
    if src.Value ~= app.AppData.ConfThresh
        src.Value = app.AppData.ConfThresh;
    end
    if ~isempty(app.AppData.MRE)
        refreshMRE(app);
    end
end

function setStiffScale(app, newClim)
            app.AppData.StiffCLim = newClim;
            setStatus(app,sprintf('Stiffness scale: %.0f–%.0f kPa', newClim(1), newClim(2)));
            if ~isempty(app.AppData.MRE)
                refreshMRE(app);   % redraws with updated StiffCLim + colorbar
            end
        end

        function setStiffScaleCustom(app)
            ans_ = inputdlg({'Min (kPa):','Max (kPa):'},'Custom Scale',1,{0,8});
            if isempty(ans_), return; end
            lo=str2double(ans_{1}); hi=str2double(ans_{2});
            if isnan(lo)||isnan(hi)||lo>=hi
                uialert(app.UIFigure,'Invalid range.','Error'); return
            end
            setStiffScale(app,[lo hi]);
        end

        function toggleConfMask(app)
            app.AppData.ShowConfMask = app.BtnConfMap.Value;
            refreshMRE(app);
        end

        % ── EXPORT / MISC ─────────────────────────────────────────────────
        function exportROIs(app)
        % Export all accepted ROI binary masks + polygon vertices to a MAT file.
        % Each ROI entry contains:
        %   .masks.(sliceKey)    — logical binary mask [nR x nC]
        %   .vertices.(sliceKey) — cell array of Nx2 [col,row] polygon boundaries
            examPath = '';
            try, examPath = app.AppData.ExamPath; catch, end
            defaultName = 'roi_export.mat';
            if ~isempty(examPath)
                [~, examName] = fileparts(examPath);
                defaultName = sprintf('%s_rois.mat', examName);
            end
            [fname, fpath] = uiputfile('*.mat', 'Export ROI Masks', defaultName);
            if isequal(fname, 0), return; end
            try
                setStatus(app, 'Exporting ROI masks...');
                roiExport = struct();
                roiExport.ExportedAt  = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
                roiExport.ExamPath    = examPath;
                % Metadata from Dixon geometry
                dix = app.AppData.Dixon;
                if ~isempty(dix)
                    roiExport.PixelSpacing_mm   = dix.PixelSpacing_mm;
                    roiExport.SliceThickness_mm = dix.SliceThickness_mm;
                    roiExport.SliceLocations    = dix.SliceLocations;
                end
                allROINames = {'LiverDixon','SpleenDixon','PsoasDixon','TrunkDixon', ...
                               'MuscleDixon','SATDixon','VATDixon','FatDixon', ...
                               'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'};
                rois = app.AppData.ROIs;
                for ri = 1:numel(allROINames)
                    rn = allROINames{ri};
                    if ~isfield(rois, rn), continue; end
                    slices = rois.(rn).Slices;
                    keys = fieldnames(slices);
                    if isempty(keys), continue; end
                    entry = struct('masks', struct(), 'vertices', struct());
                    for ki = 1:numel(keys)
                        k = keys{ki};
                        mask = logical(slices.(k));
                        entry.masks.(k) = mask;
                        % Derive polygon boundary vertices [col, row] per region
                        if any(mask(:))
                            bnds = bwboundaries(mask, 'noholes');
                            verts = cell(numel(bnds), 1);
                            for b = 1:numel(bnds)
                                verts{b} = [bnds{b}(:,2), bnds{b}(:,1)];  % [x, y]
                            end
                            entry.vertices.(k) = verts;
                        else
                            entry.vertices.(k) = {};
                        end
                    end
                    roiExport.(rn) = entry;
                end
                save(fullfile(fpath, fname), 'roiExport', '-v7');
                setStatus(app, sprintf('ROI masks exported to %s', fname));
            catch ME
                uialert(app.UIFigure, ME.message, 'Export Error', 'Icon', 'error');
                setStatus(app, ['Export failed: ' ME.message]);
            end
        end
        function exportPDF(app)
            setStatus(app,'[Phase 7] Export PDF — not yet implemented.');
        end
        function resetExamAppData(app)
        % Clear all per-exam data so a new exam starts fresh.
            lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            for ki = 1:numel(lmNames)
                n = lmNames{ki};
                app.AppData.LM.(n).CorRow = NaN;
                app.AppData.LM.(n).SagRow = NaN;
                app.AppData.LM_Dixon.(n).SliceIdx = NaN;
                app.AppData.LM_Dixon.(n).Dist_mm  = NaN;
                app.AppData.LM_MRE.(n).SliceIdx   = NaN;
                app.AppData.LM_MRE.(n).Dist_mm    = NaN;
            end
            dixonROINames = {'LiverDixon','SpleenDixon','MuscleDixon', ...
                             'PsoasDixon','TrunkDixon','SATDixon','VATDixon','FatDixon'};
            mreROINames   = {'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'};
            for ri = 1:numel(dixonROINames)
                app.AppData.ROIs.(dixonROINames{ri}) = struct('Slices',struct());
            end
            for ri = 1:numel(mreROINames)
                app.AppData.ROIs.(mreROINames{ri}) = struct('Slices',struct());
            end
            app.AppData.Dixon    = [];
            app.AppData.MRE      = [];
            app.AppData.Localizer= [];
            app.AppData.ExamPath = '';
        end

        function savePDFFMat(app)
        % Save disc landmarks + Dixon ROIs + Dixon image volumes + Localizer into
        % pdff_data.mat so the exam can be fully restored without re-selecting DICOM series.
            examPath = '';
            try, examPath = app.AppData.ExamPath; catch, end
            if isempty(examPath) || ~isfolder(examPath), return; end
            try
                pdff = struct();
                pdff.SavedAt = datestr(now,'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
                pdff.LM       = app.AppData.LM;
                pdff.LM_Dixon = app.AppData.LM_Dixon;
                pdff.LM_MRE   = app.AppData.LM_MRE;
                % Patient metadata for fast-path reload display
                try
                    pdff.PatientID = app.AppData.Exam.PatientID;
                    pdff.StudyDate = app.AppData.Exam.StudyDate;
                    pdff.MREType   = app.AppData.Exam.MREType;
                catch
                end
                % Full Dixon image volumes (enables fast-path reload without DICOM)
                dix = app.AppData.Dixon;
                if ~isempty(dix)
                    pdff.DixonData = dix;
                end
                % Localizer scout images (enables fast-path reload without DICOM)
                loc = app.AppData.Localizer;
                if ~isempty(loc)
                    pdff.LocalizerData = loc;
                end
                rois = app.AppData.ROIs;
                dixonROINames = {'LiverDixon','SpleenDixon','MuscleDixon', ...
                                 'PsoasDixon','TrunkDixon','SATDixon','VATDixon','FatDixon'};
                pdff.ROIs = struct();
                for ri = 1:numel(dixonROINames)
                    n = dixonROINames{ri};
                    if isfield(rois, n), pdff.ROIs.(n) = rois.(n); end
                end
                save(fullfile(examPath,'pdff_data.mat'), 'pdff', '-v7.3');
            catch ME
                warning('savePDFFMat:fail','Could not save pdff_data.mat: %s', ME.message);
            end
        end

        function loadPDFFMat(app, examPath)
        % Load from pdff_data.mat: landmarks, ROIs, Dixon volumes, Localizer.
        % When DixonData and LocalizerData are present (saved since v2.1),
        % the Dixon and Localizer tabs are fully populated without DICOM access.
            matFile = fullfile(examPath, 'pdff_data.mat');
            if ~isfile(matFile), return; end
            try
                S = load(matFile, 'pdff');
                if ~isfield(S,'pdff'), return; end
                p = S.pdff;
                lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
                if isfield(p,'LM')
                    for ki = 1:numel(lmNames)
                        n = lmNames{ki};
                        if isfield(p.LM,n), app.AppData.LM.(n) = p.LM.(n); end
                    end
                end
                if isfield(p,'LM_Dixon')
                    for ki = 1:numel(lmNames)
                        n = lmNames{ki};
                        if isfield(p.LM_Dixon,n)
                            app.AppData.LM_Dixon.(n) = p.LM_Dixon.(n);
                        end
                    end
                end
                if isfield(p,'LM_MRE')
                    for ki = 1:numel(lmNames)
                        n = lmNames{ki};
                        if isfield(p.LM_MRE,n)
                            app.AppData.LM_MRE.(n) = p.LM_MRE.(n);
                        end
                    end
                end
                if isfield(p,'ROIs')
                    rnames = fieldnames(p.ROIs);
                    for ri = 1:numel(rnames)
                        rn = rnames{ri};
                        if isfield(app.AppData.ROIs, rn)
                            app.AppData.ROIs.(rn) = p.ROIs.(rn);
                        end
                    end
                end
                % Restore full Dixon image volumes (saved since the session that
                % first loaded this exam after code update).
                hasDixon = isfield(p,'DixonData') && ~isempty(p.DixonData);
                hasLoc   = isfield(p,'LocalizerData') && ~isempty(p.LocalizerData);
                if hasDixon
                    app.AppData.Dixon = p.DixonData;
                    populateDixonTab(app);
                end
                if hasLoc
                    app.AppData.Localizer = p.LocalizerData;
                    populateLocalizerTab(app);
                end
                refreshDixon(app);
                app.refreshLocCoronal(); app.refreshLocSagittal();
                updateDixonJumpButtons(app);
                updateAllDixonStats(app);
                try, app.updateResultsTable(); catch, end
                if hasDixon && hasLoc
                    setStatus(app,'Loaded saved session data from pdff_data.mat.');
                elseif hasDixon
                    setStatus(app,'Loaded pdff_data.mat — Dixon restored; no scout images (re-select from DICOM to add them).');
                else
                    setStatus(app,'Loaded pdff_data.mat — ROIs and landmarks restored; no Dixon images (re-select from DICOM to rebuild).');
                end
            catch ME
                warning('loadPDFFMat:fail','Could not load pdff_data.mat: %s', ME.message);
            end
        end

        function saveMREROIsToMat(app)
        % Append MRE ROIs into mre_data.mat (the main MRE processing file).
        % Only call this after the file has been built; on fast-path reloads
        % the file is preserved intact, so the appended ROIs survive.
            matPath = '';
            try, matPath = app.AppData.MATPath; catch, end
            if isempty(matPath) || ~isfile(matPath), return; end
            try
                mreROIs = struct();
                mreROINames = {'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'};
                for ri = 1:numel(mreROINames)
                    n = mreROINames{ri};
                    if isfield(app.AppData.ROIs, n)
                        mreROIs.(n) = app.AppData.ROIs.(n);
                    end
                end
                mreLM = app.AppData.LM_MRE;
                save(matPath, 'mreROIs', 'mreLM', '-append');
            catch ME
                warning('saveMREROIsToMat:fail','Could not save MRE ROIs: %s', ME.message);
            end
        end

        function loadMREROIsFromMat(app, matPath)
        % Load MRE ROIs appended to mre_data.mat.
            if ~isfile(matPath), return; end
            try
                % Use whos to discover which variables exist before loading,
                % avoiding MATLAB's "Variable not found" warning.
                ws = whos('-file', matPath);
                varNames = {ws.name};
                toLoad = intersect(varNames, {'mreROIs','mreLM'});
                if isempty(toLoad), return; end
                S = load(matPath, toLoad{:});
                if isfield(S,'mreROIs')
                    rnames = fieldnames(S.mreROIs);
                    for ri = 1:numel(rnames)
                        rn = rnames{ri};
                        if isfield(app.AppData.ROIs, rn)
                            app.AppData.ROIs.(rn) = S.mreROIs.(rn);
                        end
                    end
                end
                if isfield(S,'mreLM')
                    lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
                    for ki = 1:numel(lmNames)
                        n = lmNames{ki};
                        if isfield(S.mreLM, n)
                            app.AppData.LM_MRE.(n) = S.mreLM.(n);
                        end
                    end
                end
            catch ME
                warning('loadMREROIsFromMat:fail','Could not load MRE ROIs: %s', ME.message);
            end
        end

        function saveSession(app)
            [fname, fpath] = uiputfile('*.mat', 'Save HepatosplenicMRE Session', ...
                'HepatosplenicMRE_session.mat');
            if isequal(fname, 0), return; end
            try
                session        = struct();
                session.Version  = '2.0';
                session.SavedAt  = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
                session.LM       = app.AppData.LM;
                session.LM_Dixon = app.AppData.LM_Dixon;
                session.LM_MRE   = app.AppData.LM_MRE;
                session.ROIs     = app.AppData.ROIs;
                try, session.PatientInfo = app.LblPatientInfo.Text; catch, end
                save(fullfile(fpath, fname), 'session', '-v7');
                setStatus(app, sprintf('Session saved → %s', fname));
            catch ME
                uialert(app.UIFigure, ME.message, 'Save Failed');
            end
        end

        function loadSession(app)
            [fname, fpath] = uigetfile('*.mat', 'Load HepatosplenicMRE Session');
            if isequal(fname, 0), return; end
            try
                S = load(fullfile(fpath, fname), 'session');
                sess = S.session;
                if isfield(sess,'LM'),       app.AppData.LM       = sess.LM;       end
                if isfield(sess,'LM_Dixon'), app.AppData.LM_Dixon = sess.LM_Dixon; end
                if isfield(sess,'LM_MRE'),   app.AppData.LM_MRE   = sess.LM_MRE;   end
                if isfield(sess,'ROIs')
                    for fn = fieldnames(sess.ROIs)'
                        if isfield(app.AppData.ROIs, fn{1})
                            app.AppData.ROIs.(fn{1}) = sess.ROIs.(fn{1});
                        end
                    end
                end
                % Refresh all active displays
                if ~isempty(app.AppData.Localizer)
                    refreshLocCoronal(app); refreshLocSagittal(app);
                    updateLandmarkStatus(app);
                end
                updateDixonJumpButtons(app);
                if ~isempty(app.AppData.Dixon)
                    refreshDixon(app); updateAllDixonStats(app);
                end
                if ~isempty(app.AppData.MRE)
                    refreshMRE(app); updateAllMREStats(app);
                end
                try, app.updateResultsTable(); catch, end
                setStatus(app, sprintf('Session loaded ← %s', fname));
            catch ME
                uialert(app.UIFigure, ME.message, 'Load Failed');
            end
        end
        function setColormap(app,~)
            % Placeholder
        end
        function showAbout(~)
            msgbox(sprintf(['Abdominal MRI/MRE Analysis\n' ...
                '(Version 1.0, M.Y., April 17, 2026)\n\n' ...
                'Mayo Clinic\nPI: Meng Yin, PhD']), ...
                'About','help');
        end
        function onStudySelect(app,event)
            n=event.SelectedNodes;
            if ~isempty(n), setStatus(app,sprintf('Selected: %s',n.Text)); end
        end
        function onTabChange(app,~)
            try
                activeTab = app.ImageTabGroup.SelectedTab;
            catch
                return
            end
            if isequal(activeTab, app.MRETab)
                if ~isempty(app.AppData.MRE)
                    refreshMRE(app);
                end
            else
                try
                    if app.AppData.MREPlaying || (~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer))
                        app.stopMREPlayback();
                    end
                catch
                    app.stopMREPlayback();
                end
            end
        end
        function activateTab(app, which)
            tabs = struct('loc',app.LocTab,'dixon',app.DixonTab, ...
                          'mre',app.MRETab,'results',app.ResultsTab);
            if isfield(tabs,which)
                app.ImageTabGroup.SelectedTab = tabs.(which);
            end
        end

        
function onKeyPress(app, event)
    if isempty(app)
        return
    end
    try
        if ~isvalid(app)
            return
        end
    catch
        return
    end
    if app.handleMREROIHotkey(event)
        return
    end
    if app.handleDixonROIHotkey(event)
        return
    end
    if app.shouldBypassGlobalHotkeys()
        return
    end

    key = lower(event.Key);
    delta = 0;
    switch key
        case {'uparrow','rightarrow','pagedown'}
            delta = 1;
        case {'downarrow','leftarrow','pageup'}
            delta = -1;
        otherwise
            return
    end

    try
        activeTab = app.ImageTabGroup.SelectedTab;
    catch
        return
    end

    if isequal(activeTab, app.MRETab) && ~isempty(app.AppData.MRE)
        app.nudgeMRESlice(delta);
    elseif isequal(activeTab, app.DixonTab) && ~isempty(app.AppData.Dixon)
        app.nudgeDixonSlice(delta);
    end
end

function tf = shouldBypassGlobalHotkeys(app)
            tf = false;
            try
                obj = app.UIFigure.CurrentObject;
                tf = isa(obj,'matlab.ui.control.NumericEditField') || ...
                     isa(obj,'matlab.ui.control.EditField') || ...
                     isa(obj,'matlab.ui.control.TextArea') || ...
                     isa(obj,'matlab.ui.control.DropDown');
            catch
                tf = false;
            end
        end

        function nudgeMRESlice(app, delta)
            if app.isMREROIWorkflowActive()
                setStatus(app, 'Finish the active MRE ROI with A/Enter or cancel with Esc before changing slices.');
                return
            end
            if isempty(app.AppData.MRE) || delta == 0
                return
            end
            nZ = [];
            if isfield(app.AppData.MRE,'S') && ~isempty(app.AppData.MRE.S)
                nZ = size(app.AppData.MRE.S,3);
            elseif isfield(app.AppData.MRE,'W') && ~isempty(app.AppData.MRE.W)
                nZ = size(app.AppData.MRE.W,3);
            elseif isfield(app.AppData.MRE,'M') && ~isempty(app.AppData.MRE.M)
                nZ = size(app.AppData.MRE.M,3);
            end
            if isempty(nZ) || nZ < 1
                return
            end
            sl = max(1, min(nZ, round(app.AppData.MRESlice + delta)));
            app.AppData.MRESlice = sl;
            try, app.SldrMRE.Value = sl; catch, end
            app.LblMRESlice.Text = sprintf('%d/%d', sl, nZ);
            refreshMRE(app);
        end

        function nudgeDixonSlice(app, delta)
            if app.isDixonROIWorkflowActive()
                setStatus(app,'Finish the active Dixon ROI with Enter or cancel with Esc before changing slices.');
                return
            end
            if isempty(app.AppData.Dixon) || delta == 0
                return
            end
            nZ = max(1, app.AppData.Dixon.nSlices);
            sl = max(1, min(nZ, round(app.AppData.DixonSlice + delta)));
            app.AppData.DixonSlice = sl;
            app.LblDixonSlice.Text = sprintf('%d/%d', sl, nZ);
            refreshDixon(app);
        end

        function onClose(app)
            % Close directly to avoid modal-confirm hangs in some MATLAB versions.
            try
                if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                    stop(app.AppData.MRETimer);
                    delete(app.AppData.MRETimer);
                    app.AppData.MRETimer = [];
                end
            catch
            end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch
            end
        end

        % -----------------------------------------------------------------
        %  PANEL CLICK HANDLERS — open magnified popup when ROI workflow active
        % -----------------------------------------------------------------

        function onDixonPanelClick(app, axisKey)
            app.setCurrentDixonTargetAxis(axisKey);
            if app.isDixonROIWorkflowActive()
                try, if app.AppData.DixonROIDrawing, return; end, catch, end
                app.captureManualOuterDixonROI();
            end
        end

        function onMREPanelClick(app, axisKey)
            app.setCurrentMRETargetAxis(axisKey);
            if app.isMREROIWorkflowActive()
                try, if app.AppData.MREROIDrawing, return; end, catch, end
                app.captureManualOuterMREROI();
            end
        end

        % -----------------------------------------------------------------
        %  MAGNIFIED ROI POPUP BUILDERS
        % -----------------------------------------------------------------

        function [fig, ax, imgData, cmapData, climVals] = openDixonROIPopup(app, axisKey)
        % Create a magnified figure showing the Dixon image for ROI drawing.
            fig = []; ax = []; imgData = []; cmapData = 'gray'; climVals = [0 1];
            sl = app.AppData.DixonROISlice;
            I  = app.getDixonImageForROI(sl, axisKey);
            if isempty(I), return; end

            % Match colormap / clim from the main display
            if strcmp(axisKey, 'pdff')
                cmapData = app.AppData.DixonCmap;
                lo = app.AppData.DixonClimMin;
                hi = app.AppData.DixonClimMax;
                if lo == 0 && hi == 0, [lo,hi] = robustCLim(I,1,99,false); end
            else
                cmapData = 'gray';
                lo = 0; hi = 0;
                try
                    if strcmp(axisKey,'water')
                        lo = app.EdtWaterWinLo.Value;
                        hi = app.EdtWaterWinHi.Value;
                    else
                        lo = app.EdtFatWinLo.Value;
                        hi = app.EdtFatWinHi.Value;
                    end
                catch, end
                if hi <= lo, [lo,hi] = robustCLim(I,1,99,false); end
            end
            imgData  = I;
            climVals = [lo hi];

            titleStr = sprintf('ROI Drawing — %s · %s · Slice %d    [A/Enter=accept  Esc=discard  I=include  E=exclude]', ...
                app.getDixonOrganLabel(), app.getDixonAxisLabel(axisKey), sl);
            [fig, ax] = openROIPopupFigure(I, cmapData, [lo hi], titleStr);
            app.AppData.DixonROIPopupFig = fig;

            % Overlay any existing mask for the same slice as dashed guide
            try
                existMask = getStoredDixonROIMask(app, app.AppData.DixonROIName, sl);
                if ~isempty(existMask) && any(existMask(:))
                    hold(ax,'on');
                    bL = bwboundaries(existMask,'noholes');
                    rc = dixonROIColor(app.AppData.DixonROIName) * 0.5 + 0.35;
                    for k = 1:numel(bL)
                        b = bL{k};
                        plot(ax, b(:,2), b(:,1), '--', 'Color', rc, 'LineWidth', 1.5);
                    end
                    hold(ax,'off');
                end
            catch, end
        end

        function [fig, ax, imgData, cmapData, climVals] = openMREROIPopup(app, axisKey)
        % Create a magnified figure showing the MRE image for ROI drawing.
            fig = []; ax = []; imgData = []; cmapData = gray(256); climVals = [0 1];
            sl  = app.AppData.MREROISlice;
            mre = app.AppData.MRE;
            if isempty(mre), return; end

            switch axisKey
                case 'stiff'
                    if ~isfield(mre,'S') || isempty(mre.S), return; end
                    I = double(mre.S(:,:,min(sl,size(mre.S,3))));
                    climVals = app.AppData.StiffCLim;
                    cmapData = mreStiffCmap();
                case 'proc'
                    if ~isfield(mre,'W') || isempty(mre.W), return; end
                    nPh = size(mre.W,4);
                    ph  = max(1,min(nPh,app.AppData.MREPhase));
                    I   = double(squeeze(mre.W(:,:,min(sl,size(mre.W,3)),ph)));
                    wMax = app.AppData.WaveMax;
                    if wMax <= 0, [lo,hi] = robustCLim(I,0,99.5,true); climVals=[lo hi];
                    else, climVals = [-wMax wMax]; end
                    cmapData = mreWaveCmap();
                case 'raw'
                    if isfield(mre,'W_raw') && ~isempty(mre.W_raw)
                        nPh = size(mre.W_raw,4);
                        ph  = max(1,min(nPh,app.AppData.MREPhase));
                        I   = double(squeeze(mre.W_raw(:,:,min(sl,size(mre.W_raw,3)),ph)));
                    elseif isfield(mre,'W') && ~isempty(mre.W)
                        nPh = size(mre.W,4);
                        ph  = max(1,min(nPh,app.AppData.MREPhase));
                        I   = double(squeeze(mre.W(:,:,min(sl,size(mre.W,3)),ph)));
                    else, return; end
                    [lo,hi] = robustCLim(I,0,99.5,true);
                    climVals = [lo hi];
                    cmapData = mreWaveCmap();
                otherwise  % 'mag'
                    I = getMREMagnitudeForROI(app, sl);
                    if isempty(I), return; end
                    [lo,hi] = robustCLim(I,1,99,false);
                    climVals = [lo hi];
                    cmapData = gray(256);
            end
            imgData = I;

            titleStr = sprintf('ROI Drawing — %s · %s · Slice %d    [A/Enter=accept  Esc=discard  I=include  E=exclude]', ...
                app.getMREROIOrganLabel(), app.getMREAxisLabel(axisKey), sl);
            [fig, ax] = openROIPopupFigure(I, cmapData, climVals, titleStr);
            app.AppData.MREROIPopupFig = fig;
        end

    end

    % =====================================================================
    %  PRIVATE DISPLAY HELPERS
    % =====================================================================
    methods (Access = private)

        function mre = normalizeMREStruct(app, mre) %#ok<INUSD>
            if isempty(mre) || ~isstruct(mre)
                return
            end
            expSlices = [];
            if isfield(mre,'M') && ~isempty(mre.M) && ndims(mre.M) >= 3
                expSlices(end+1) = size(mre.M,3); %#ok<AGROW>
            end
            if isfield(mre,'S') && ~isempty(mre.S) && ndims(mre.S) >= 3
                expSlices(end+1) = size(mre.S,3); %#ok<AGROW>
            end
            if isfield(mre,'LapC') && ~isempty(mre.LapC) && ndims(mre.LapC) >= 3
                expSlices(end+1) = size(mre.LapC,3); %#ok<AGROW>
            end
            if isempty(expSlices)
                expSlice = [];
            else
                expSlice = max(expSlices);
            end
            if isfield(mre,'W_raw') && ~isempty(mre.W_raw) && ndims(mre.W_raw) == 4
                sz = size(mre.W_raw);
                doSwap = false;
                if ~isempty(expSlice)
                    if sz(3) ~= expSlice && sz(4) == expSlice
                        doSwap = true;
                    end
                else
                    if sz(3) <= 8 && sz(4) > 8
                        doSwap = true;
                    end
                end
                if doSwap
                    mre.W_raw = permute(mre.W_raw, [1 2 4 3]);
                end
            end
            if isfield(mre,'M_raw') && ~isempty(mre.M_raw) && ndims(mre.M_raw) == 4
                sz = size(mre.M_raw);
                doSwap = false;
                if ~isempty(expSlice)
                    if sz(3) ~= expSlice && sz(4) == expSlice
                        doSwap = true;
                    end
                else
                    if sz(3) <= 8 && sz(4) > 8
                        doSwap = true;
                    end
                end
                if doSwap
                    mre.M_raw = permute(mre.M_raw, [1 2 4 3]);
                end
            end
        end

        function populateLocalizerTab(app)
            loc = app.AppData.Localizer;
            if isempty(loc), return; end

            % Set slider ranges
            nCor = size(loc.Coronal.Volume,3);
            nSag = size(loc.Sagittal.Volume,3);
            if nCor == 0 && nSag == 0
                setStatus(app,'Localizer loaded but no images decoded (check DICOM path)');
                return
            end
            corMid = max(1, round(nCor/2));
            sagMid = max(1, round(nSag/2));
            app.SldrLocCor.Limits = [1 max(nCor,2)];
            app.SldrLocSag.Limits = [1 max(nSag,2)];
            app.SldrLocCor.Value  = corMid;
            app.SldrLocSag.Value  = sagMid;
            app.AppData.CorSlice  = corMid;
            app.AppData.SagSlice  = sagMid;
            app.LblLocCor.Text = sprintf('%d/%d', corMid, max(nCor,1));
            app.LblLocSag.Text = sprintf('%d/%d', sagMid, max(nSag,1));

            refreshLocCoronal(app);
            refreshLocSagittal(app);
        end

        function refreshLocCoronal(app)
            loc = app.AppData.Localizer;
            if isempty(loc) || isempty(loc.Coronal.Volume), return; end
            sl  = app.AppData.CorSlice;
            sl  = max(1, min(size(loc.Coronal.Volume,3), sl));
            img = double(loc.Coronal.Volume(:,:,sl));
            showImgWL(app.AxLocCoronal, img, sprintf('Coronal  slice %d',sl), ...
                app.EdtCorWinLo.Value, app.EdtCorWinHi.Value);
            hold(app.AxLocCoronal,'on');
            nC = size(img,2);
            drawLocLines(app, app.AxLocCoronal, nC, 'cor', sl);
            hold(app.AxLocCoronal,'off');
        end

        function refreshLocSagittal(app)
            loc = app.AppData.Localizer;
            if isempty(loc) || isempty(loc.Sagittal.Volume), return; end
            sl  = app.AppData.SagSlice;
            nSl = size(loc.Sagittal.Volume,3);
            sl  = max(1, min(nSl, sl));
            img = double(loc.Sagittal.Volume(:,:,sl));
            showImgWL(app.AxLocSagittal, img, sprintf('Sagittal  %d/%d',sl,nSl), ...
                app.EdtSagWinLo.Value, app.EdtSagWinHi.Value);
            hold(app.AxLocSagittal,'on');
            nC = size(img,2);
            drawLocLines(app, app.AxLocSagittal, nC, 'sag', sl);
            hold(app.AxLocSagittal,'off');
        end

        function drawLocLines(app, ax, nC, plane, sl)
        % Draw all 7 disc landmark lines on a localizer axes.
            lmNames  = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
            lmColors = {[0.55 0.05 0.05],[0.75 0.10 0.10],[0.88 0.35 0.08],[0.92 0.65 0.05],[0.30 0.72 0.30],[0.15 0.58 0.88],[0.50 0.20 0.85]};
            for ki = 1:7
                n   = lmNames{ki};
                clr = lmColors{ki};
                corRow = app.AppData.LM.(n).CorRow;
                if isnan(corRow), continue; end
                if strcmp(plane,'sag')
                    rowY = corRowToSagRow(app, corRow, sl);
                else
                    rowY = corRow;
                end
                if isnan(rowY), continue; end
                z = corRowToZmm(app, corRow);
                lbl = [locLandmarkLabel(n) '  ' siCoordStr(z)];
                hl = plot(ax, [1 nC], [rowY rowY], '-', 'Color', clr, 'LineWidth', 2.2);
                ht = text(ax, nC-2, rowY-3, lbl, 'Color', clr, 'FontSize', 11, ...
                    'FontWeight','bold','HorizontalAlignment','right');
                try
                    hl.HitTest='off'; hl.PickableParts='none';
                    ht.HitTest='off'; ht.PickableParts='none';
                catch, end
            end
        end

        function populateDixonTab(app)
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            if dix.nSlices == 0
                setStatus(app,'Dixon loaded but no slices decoded (check DICOM path)');
                return
            end
            nZ = dix.nSlices;
            dixMid = max(1, round(nZ/2));
            app.AppData.DixonSlice = dixMid;
            app.LblDixonSlice.Text = sprintf('%d/%d', dixMid, nZ);
            app.LblDixonInfo.Text  = sprintf('Pixel: %.2fmm  Slice: %.1fmm', ...
                dix.PixelSpacing_mm(1), dix.SliceThickness_mm);
            try
                app.DdlDixonContrast.Value = 'PDFF';
                app.DdlDixonContrast.Visible = 'off';
            catch
            end
            app.AppData.DixonContrast = 'PDFF';
            app.DdlDixonCmap.Value = 'hot';
            app.EdtDixonMin.Value  = 0;
            app.EdtDixonMax.Value  = 100;
            app.AppData.DixonCmap    = app.DdlDixonCmap.Value;
            app.AppData.DixonClimMin = app.EdtDixonMin.Value;
            app.AppData.DixonClimMax = app.EdtDixonMax.Value;
            refreshDixon(app);
        end

        function onDixonContrastChange(app)
            % Three-panel Dixon view is fixed to PDFF / In-phase / Out-of-phase.
            app.AppData.DixonContrast = 'PDFF';
            try, app.DdlDixonContrast.Value = 'PDFF'; catch, end
            refreshDixon(app);
        end

        function onDixonScaleChange(app)
            app.AppData.DixonCmap    = app.DdlDixonCmap.Value;
            app.AppData.DixonClimMin = app.EdtDixonMin.Value;
            app.AppData.DixonClimMax = app.EdtDixonMax.Value;
            refreshDixon(app);
        end

        function onDixonAutoScale(app)
            % Auto-scale applies to the PDFF panel only.
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            sl  = app.AppData.DixonSlice;
            vol = dixonPreferredDisplayVolume(dix, 'PDFF');
            if isempty(vol), return; end
            img = double(vol(:,:, min(sl, size(vol,3))));
            lo = min(img(:)); hi = max(img(:));
            if hi <= lo, return; end
            app.EdtDixonMin.Value  = lo;
            app.EdtDixonMax.Value  = hi;
            app.AppData.DixonClimMin = lo;
            app.AppData.DixonClimMax = hi;
            refreshDixon(app);
        end

        function autoWaterFatWin(app, panelKey)
        % Reset Water or Fat W/L to auto (0/0 = auto-scale).
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            sl = app.AppData.DixonSlice;
            switch panelKey
                case 'water'
                    vol = dixonPreferredDisplayVolume(dix,'InPhase');
                    if isempty(vol), return; end
                    img = double(vol(:,:,min(sl,size(vol,3))));
                    [lo,hi] = robustCLim(img,1,99,false);
                    app.EdtWaterWinLo.Value = lo; app.EdtWaterWinHi.Value = hi;
                case 'fat'
                    vol = dixonPreferredDisplayVolume(dix,'OutPhase');
                    if isempty(vol), return; end
                    img = double(vol(:,:,min(sl,size(vol,3))));
                    [lo,hi] = robustCLim(img,1,99,false);
                    app.EdtFatWinLo.Value = lo; app.EdtFatWinHi.Value = hi;
            end
            refreshDixon(app);
        end

        function autoLocWin(app, panelKey)
        % Reset Coronal or Sagittal W/L to auto.
            loc = app.AppData.Localizer;
            if isempty(loc), return; end
            switch panelKey
                case 'cor'
                    if isempty(loc.Coronal.Volume), return; end
                    sl = app.AppData.CorSlice;
                    sl = max(1,min(size(loc.Coronal.Volume,3),sl));
                    img = double(loc.Coronal.Volume(:,:,sl));
                    [lo,hi] = robustCLim(img,1,99,false);
                    app.EdtCorWinLo.Value = lo; app.EdtCorWinHi.Value = hi;
                case 'sag'
                    if isempty(loc.Sagittal.Volume), return; end
                    sl = app.AppData.SagSlice;
                    sl = max(1,min(size(loc.Sagittal.Volume,3),sl));
                    img = double(loc.Sagittal.Volume(:,:,sl));
                    [lo,hi] = robustCLim(img,1,99,false);
                    app.EdtSagWinLo.Value = lo; app.EdtSagWinHi.Value = hi;
            end
            app.refreshLocCoronal(); app.refreshLocSagittal();
        end

        function refreshDixon(app)
            % Do not redraw axes while an ROI polygon is being drawn/edited —
            % cla() would destroy the drawpolygon object and crash wait().
            if isfield(app.AppData,'DixonROIDrawing') && app.AppData.DixonROIDrawing
                return
            end
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            sl  = app.AppData.DixonSlice;
            nZ  = max(1, dix.nSlices);
            sl  = max(1, min(nZ, sl));
            app.LblDixonSlice.Text = sprintf('%d/%d', sl, nZ);

            pdffVol = dixonPreferredDisplayVolume(dix, 'PDFF');
            ipVol   = dixonPreferredDisplayVolume(dix, 'InPhase');
            opVol   = dixonPreferredDisplayVolume(dix, 'OutPhase');

            if ~isempty(pdffVol)
                app.AppData.DispDixon = double(pdffVol(:,:, min(sl, size(pdffVol,3))));
            elseif ~isempty(ipVol)
                app.AppData.DispDixon = double(ipVol(:,:, min(sl, size(ipVol,3))));
            elseif ~isempty(opVol)
                app.AppData.DispDixon = double(opVol(:,:, min(sl, size(opVol,3))));
            else
                app.AppData.DispDixon = [];
            end

            % Per-panel cursor buffers for Water/IP and Fat/OP axes
            if ~isempty(ipVol)
                app.AppData.DispDixonIP = double(ipVol(:,:, min(sl, size(ipVol,3))));
            else
                app.AppData.DispDixonIP = [];
            end
            if ~isempty(opVol)
                app.AppData.DispDixonOP = double(opVol(:,:, min(sl, size(opVol,3))));
            else
                app.AppData.DispDixonOP = [];
            end

            renderDixonPanelAxes(app, app.AxDixonPDFF, pdffVol, sl, nZ, 'PDFF (%)', true);
            renderDixonPanelAxes(app, app.AxDixonIP,   ipVol,   sl, nZ, 'Water', false, 'water');
            renderDixonPanelAxes(app, app.AxDixonWater,opVol,   sl, nZ, 'Fat',   false, 'fat');
        end

        function populateMRETab(app)
            mre = app.AppData.MRE;
            if isempty(mre), return; end
            nZM = size(mre.M, 3);
            nZW = size(mre.W, 3);
            nZR = nZW;
            if isfield(mre,'W_raw') && ~isempty(mre.W_raw)
                nZR = size(mre.W_raw, 3);
            end
            nZS = 1;
            if isfield(mre,'S') && ~isempty(mre.S), nZS = size(mre.S,3); end
            nZ = max(1, max([nZM nZW nZR nZS]));
            mreMid = max(1, round(nZ/2));
            try
                app.SldrMRE.Limits = [1 max(nZ,2)];
                app.SldrMRE.Value  = mreMid;
            catch
            end
            app.AppData.MRESlice = mreMid;
            app.LblMRESlice.Text = sprintf('%d/%d', mreMid, nZ);
            refreshMRE(app);
        end

        function refreshMRE(app)
            if isempty(app), return; end
            try
                if ~isvalid(app) || isempty(app.UIFigure) || ~isvalid(app.UIFigure)
                    return
                end
            catch
                return
            end
            if isfield(app.AppData,'MRERefreshBusy') && app.AppData.MRERefreshBusy
                return
            end
            app.AppData.MRERefreshBusy = true;
            refreshCleanup = onCleanup(@()app.clearMRERefreshBusy()); %#ok<NASGU>

            freezeKey = '';
            if app.isMREROIWorkflowActive() && isfield(app.AppData,'MREROIDrawing') && app.AppData.MREROIDrawing
                freezeKey = app.AppData.MRETargetAxis;
            end
            app.clearMRERefreshOverlay(freezeKey);
            app.clearMREROIPreviewOverlay(freezeKey);

            mre = app.AppData.MRE;
            if isempty(mre) || ~isfield(mre,'M'), return; end

            nZM = size(mre.M,3);
            nZW = size(mre.W,3);
            nZS = 1; if isfield(mre,'S') && ~isempty(mre.S), nZS = size(mre.S,3); end
            nZL = 1; if isfield(mre,'LapC') && ~isempty(mre.LapC), nZL = size(mre.LapC,3); end
            nZR = nZW;
            if isfield(mre,'W_raw') && ~isempty(mre.W_raw), nZR = size(mre.W_raw,3); end

            sl = max(1, app.AppData.MRESlice);
            slM = min(sl, max(1,nZM));
            slW = min(sl, max(1,nZW));
            slR = min(sl, max(1,nZR));
            slS = min(sl, max(1,nZS));
            slL = min(sl, max(1,nZL));

            nPhProc = max(1, size(mre.W,4));
            phProc  = max(1, min(nPhProc, app.AppData.MREPhase));

            if isfield(mre,'W_raw') && ~isempty(mre.W_raw)
                nPhRaw = max(1, size(mre.W_raw,4));
                phRaw  = mapPhaseIndex(phProc, nPhProc, nPhRaw);
                Wraw = double(squeeze(mre.W_raw(:,:,slR,phRaw)));
            else
                nPhRaw = nPhProc;
                phRaw  = phProc;
                Wraw   = double(squeeze(mre.W(:,:,slW,phProc)));
            end

            if isfield(mre,'M_raw') && ~isempty(mre.M_raw) && ndims(mre.M_raw) == 4
                nZMr = size(mre.M_raw,3);
                nPhMag = max(1, size(mre.M_raw,4));
                phMag = mapPhaseIndex(phProc, nPhProc, nPhMag);
                slMr = min(sl, max(1,nZMr));
                Msl = double(squeeze(mre.M_raw(:,:,slMr,phMag)));
                magTitle = sprintf('Magnitude  sl %d/%d  ph %d/%d', slMr, nZMr, phMag, nPhMag);
            else
                Msl = double(squeeze(mre.M(:,:,slM,1)));
                magTitle = sprintf('Magnitude  sl %d/%d', slM, nZM);
            end
            if ~strcmp(freezeKey,'mag')
                showNativeGray(app.AxMREMag, Msl, magTitle, 1, 99, 'MREBaseMag');
            end

            if ~strcmp(freezeKey,'raw')
                showNativeWave(app.AxMRERawWave, Wraw, ...
                    sprintf('Raw wave  sl %d/%d  ph %d/%d', slR, nZR, phRaw, nPhRaw), 0, 'gray', 'MREBaseRaw');
            end

            Wproc = double(squeeze(mre.W(:,:,slW,phProc)));
            if ~strcmp(freezeKey,'proc')
                waveMap = mreWaveCmap();
                [waveLo, waveHi] = showNativeWave(app.AxMREWave, Wproc, ...
                    sprintf('Processed wave  sl %d/%d  ph %d/%d', slW, nZW, phProc, nPhProc), ...
                    app.AppData.WaveMax, waveMap, 'MREBaseWave');
                try; colormap(app.AxMREWave, waveMap); catch; end
                renderColorStrip(app.AxMREWaveBar, waveMap, [waveLo waveHi], [waveLo 0 waveHi]);
                try; colormap(app.AxMREWaveBar, waveMap); catch; end
            end

            if isfield(mre,'S') && ~isempty(mre.S)
                S = double(squeeze(mre.S(:,:,slS)));
            else
                S = zeros(size(Msl));
            end
            if ~strcmp(freezeKey,'stiff')
                stiffMap = mreStiffCmap();
                safeMREAxesImage(app.AxMREStiff, S, app.AppData.StiffCLim, stiffMap, 'MREBaseStiff');
                try; colormap(app.AxMREStiff, stiffMap); catch; end
                title(app.AxMREStiff, sprintf('Stiffness (kPa)  sl %d/%d', slS, nZS), ...
                    'FontSize',12,'Color',[0.75 0.75 0.75],'FontWeight','normal');
                renderColorStrip(app.AxMREStiffBar, stiffMap, app.AppData.StiffCLim, []);
                try; colormap(app.AxMREStiffBar, stiffMap); catch; end
                if app.AppData.ShowConfMask && isfield(mre,'LapC') && ~isempty(mre.LapC)
                    lowConf = double(squeeze(mre.LapC(:,:,slL))) < app.AppData.ConfThresh;
                    hh = overlayCheckerMask(app.AxMREStiff, lowConf, 0.42);
                    try; hh.Tag = 'MRERefreshOverlay'; hh.HitTest='off'; hh.PickableParts='none'; catch; end
                end
            end

            app.AppData.DispWave    = Wproc;
            app.AppData.DispWaveRaw = Wraw;
            app.AppData.DispStiff   = S;

            previewMask = [];
            if app.isMREROIWorkflowActive() && app.AppData.MREROISlice == sl
                if ~isempty(app.AppData.MREROIFinalMask) && any(app.AppData.MREROIFinalMask(:))
                    previewMask = app.AppData.MREROIFinalMask;
                elseif ~isempty(app.AppData.MREROIOuterMask) && any(app.AppData.MREROIOuterMask(:))
                    previewMask = app.AppData.MREROIOuterMask;
                end
            end
            showHoleMasks = ~(isfield(app.AppData,'MREPlaying') && app.AppData.MREPlaying);
            if ~isempty(previewMask) && any(previewMask(:))
                holeMask = false(size(previewMask));
                if showHoleMasks
                    holeMask = getMaskHoleMask(previewMask);
                end
                Btmp = bwboundaries(previewMask);
                axesList = {'mag', app.AxMREMag; 'raw', app.AxMRERawWave; 'proc', app.AxMREWave; 'stiff', app.AxMREStiff};
                for ii = 1:size(axesList,1)
                    if strcmp(freezeKey, axesList{ii,1}), continue; end
                    ax = axesList{ii,2};
                    hold(ax, 'on');
                    for b = 1:numel(Btmp)
                        pts = Btmp{b};
                        hp = plot(ax, pts(:,2), pts(:,1), '-', 'Color', mreROIColor(app.AppData.MREROIName), 'LineWidth', 2.0);
                        try; hp.Tag = 'MREROIPreview'; hp.HitTest = 'off'; hp.PickableParts = 'none'; catch; end
                    end
                    hold(ax, 'off');
                    if showHoleMasks && any(holeMask(:))
                        hh = overlayCheckerMask(ax, holeMask, 0.34);
                        try; hh.Tag = 'MREROIPreview'; hh.HitTest = 'off'; hh.PickableParts = 'none'; catch; end
                    end
                end
            end

            mreOverlayROI(app, sl);
        end

        function mreOverlayROI(app, sl)
            % Draw stored ROI boundaries on all MRE panels.
            key = sprintf('sl%d', sl);
            freezeKey = '';
            if isfield(app.AppData,'MREROIDrawing') && app.AppData.MREROIDrawing
                freezeKey = app.AppData.MRETargetAxis;
            end
            showHoleMasks = ~(isfield(app.AppData,'MREPlaying') && app.AppData.MREPlaying);
            overlayData = cell(0,1);
            for rName = {'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'}
                rn = rName{1};
                slices = app.AppData.ROIs.(rn).Slices;
                if isfield(slices, key)
                    mask = logical(slices.(key));
                    if ~any(mask(:))
                        continue
                    end
                    item = struct();
                    item.Name = rn;
                    item.B = bwboundaries(mask);
                    item.HoleMask = false(size(mask));
                    if showHoleMasks
                        item.HoleMask = getMaskHoleMask(mask);
                    end
                    overlayData{end+1,1} = item; %#ok<AGROW>
                end
            end
            if isempty(overlayData)
                return
            end
            axesList = {'mag', app.AxMREMag; 'raw', app.AxMRERawWave; 'proc', app.AxMREWave; 'stiff', app.AxMREStiff};
            for ii = 1:size(axesList,1)
                if strcmp(freezeKey, axesList{ii,1}), continue; end
                ax = axesList{ii,2};
                hold(ax, 'on');
                for jj = 1:numel(overlayData)
                    item = overlayData{jj};
                    for b = 1:numel(item.B)
                        pts = item.B{b};   % [row col]
                        hp = plot(ax, pts(:,2), pts(:,1), '-', ...
                            'Color', mreROIColor(item.Name), 'LineWidth', 1.5);
                        try; hp.Tag = 'MRERefreshOverlay'; hp.HitTest = 'off'; hp.PickableParts = 'none'; catch; end
                    end
                    if showHoleMasks && any(item.HoleMask(:))
                        hh = overlayCheckerMask(ax, item.HoleMask, 0.30);
                        try; hh.Tag = 'MRERefreshOverlay'; hh.HitTest='off'; hh.PickableParts='none'; catch; end
                    end
                end
                hold(ax, 'off');
            end
        end

        function storeROI(app, roiName, sl, mask, nR, nC)
            if nargin < 5, nR=256; nC=256; end
            mask = imresize(logical(mask),[nR nC],'nearest');
            key = sprintf('sl%d',sl);
            switch roiName
                case 'LiverDixon',  app.AppData.ROIs.LiverDixon.Slices.(key)  = mask;
                case 'SpleenDixon', app.AppData.ROIs.SpleenDixon.Slices.(key) = mask;
                case 'MuscleDixon', app.AppData.ROIs.MuscleDixon.Slices.(key) = mask;
                case 'PsoasDixon',  app.AppData.ROIs.PsoasDixon.Slices.(key)  = mask;
                case 'TrunkDixon',  app.AppData.ROIs.TrunkDixon.Slices.(key)  = mask;
                case 'SATDixon',    app.AppData.ROIs.SATDixon.Slices.(key)    = mask;
                case 'VATDixon',    app.AppData.ROIs.VATDixon.Slices.(key)    = mask;
                case 'FatDixon',    app.AppData.ROIs.FatDixon.Slices.(key)    = mask;
                case 'LiverMRE',    app.AppData.ROIs.LiverMRE.Slices.(key)  = mask;
                case 'SpleenMRE',   app.AppData.ROIs.SpleenMRE.Slices.(key) = mask;
                case 'MuscleMRE',   app.AppData.ROIs.MuscleMRE.Slices.(key) = mask;
                case 'FatMRE',      app.AppData.ROIs.FatMRE.Slices.(key)    = mask;
            end
        end

        function storeEmptyMREROISlice(app, roiName, sl, nR, nC)
            if nargin < 4 || isempty(nR) || nR <= 0
                nR = size(app.AppData.MRE.M, 1);
            end
            if nargin < 5 || isempty(nC) || nC <= 0
                nC = size(app.AppData.MRE.M, 2);
            end
            emptyMask = false(nR, nC);
            storeROI(app, roiName, sl, emptyMask, nR, nC);
        end

        function computeAggregatedDixonROIStats(app, roiName)
        % Aggregate volume and mean PDFF across all stored slices for roiName
        % and update the corresponding measurement labels.
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            if ~isfield(app.AppData.ROIs, roiName), return; end
            dx = dix.PixelSpacing_mm(1);
            dy = dix.PixelSpacing_mm(2);
            dz = 5;
            if isfield(dix,'SliceThickness_mm') && ~isempty(dix.SliceThickness_mm)
                dz = dix.SliceThickness_mm;
            end
            sliceKeys = fieldnames(app.AppData.ROIs.(roiName).Slices);
            totalVox = 0;
            pdffVals = [];
            for k = 1:numel(sliceKeys)
                key = sliceKeys{k};
                sl  = str2double(strrep(key,'sl',''));
                mask = logical(app.AppData.ROIs.(roiName).Slices.(key));
                if ~any(mask(:)), continue; end
                totalVox = totalVox + sum(mask(:));
                if ~isempty(dix.PDFF) && sl >= 1 && sl <= size(dix.PDFF,3)
                    ff = dix.PDFF(:,:,sl);
                    pdffVals = [pdffVals; double(ff(mask(:)))]; %#ok<AGROW>
                end
            end
            if totalVox == 0, return; end
            volTxt  = sprintf('%d vox / %.0f mm³', totalVox, totalVox * dx * dy * dz);
            pdffTxt = '';
            if ~isempty(pdffVals)
                pdffTxt = sprintf('%.1f%%', nanmean(pdffVals));
            end
            switch roiName
                case 'LiverDixon'
                    try, app.ValLiverDixonVol.Text  = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValLiverDixonPDFF.Text  = pdffTxt; end; catch, end
                case 'SpleenDixon'
                    try, app.ValSpleenDixonVol.Text = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValSpleenDixonPDFF.Text = pdffTxt; end; catch, end
                case 'PsoasDixon'
                    try, app.ValPsoasDixonVol.Text  = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValPsoasDixonPDFF.Text  = pdffTxt; end; catch, end
                case 'TrunkDixon'
                    try, app.ValTrunkDixonVol.Text  = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValTrunkDixonPDFF.Text  = pdffTxt; end; catch, end
                case 'MuscleDixon'
                    try, app.ValMuscleDixonVol.Text = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValMuscleDixonPDFF.Text = pdffTxt; end; catch, end
                case 'SATDixon'
                    try, app.ValSATDixonVol.Text    = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValSATDixonPDFF.Text    = pdffTxt; end; catch, end
                case 'VATDixon'
                    try, app.ValVATDixonVol.Text    = volTxt;  catch, end
                    try, if ~isempty(pdffTxt), app.ValVATDixonPDFF.Text    = pdffTxt; end; catch, end
            end
        end

        function computeDixonROIStats(app, roiName, ~, ~) %#ok<INUSD>
            computeAggregatedDixonROIStats(app, roiName);
        end

        function updateAllDixonStats(app)
            if isempty(app.AppData.Dixon), return; end
            for rn = {'LiverDixon','SpleenDixon','PsoasDixon','TrunkDixon','MuscleDixon','SATDixon','VATDixon'}
                computeAggregatedDixonROIStats(app, rn{1});
            end
        end

        function computeMREROIStats(app, roiName, mask, sl)
            %#ok<INUSD>
            app.updateMREAggregateStats(roiName);
        end

        function updateAllMREStats(app)
            for roiName = {'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'}
                app.updateMREAggregateStats(roiName{1});
            end
        end

        function updateMREAggregateStats(app, roiName)
            [validPx, totalN, totalVolMm3, nStored] = app.collectMREValidPixels(roiName);

            if totalN > 0
                validPx = validPx(isfinite(validPx));
                meanStiff = mean(validPx(:));
                app.setMREMeasurementLabels(roiName, ...
                    sprintf('%.2f kPa (mean)', meanStiff), ...
                    sprintf('%d / %.0f mm^3', totalN, totalVolMm3));
                if isfield(app.AppData,'MRETechFailure') && isstruct(app.AppData.MRETechFailure) && isfield(app.AppData.MRETechFailure, roiName)
                    app.AppData.MRETechFailure.(roiName) = false;
                end
            elseif nStored > 0
                app.setMREMeasurementLabels(roiName, 'Technical failure', '0 / 0 mm^3');
                if isfield(app.AppData,'MRETechFailure') && isstruct(app.AppData.MRETechFailure) && isfield(app.AppData.MRETechFailure, roiName)
                    app.AppData.MRETechFailure.(roiName) = false;
                end
            else
                app.setMREMeasurementLabels(roiName, '—', '—');
                if isfield(app.AppData,'MRETechFailure') && isstruct(app.AppData.MRETechFailure) && isfield(app.AppData.MRETechFailure, roiName)
                    app.AppData.MRETechFailure.(roiName) = false;
                end
            end
        end

        function [validPx, totalN, totalVolMm3, nStored] = collectMREValidPixels(app, roiName)
            validPx = [];
            totalN = 0;
            totalVolMm3 = 0;
            nStored = 0;
            if isempty(app.AppData.MRE) || ~isfield(app.AppData.MRE,'S') || isempty(app.AppData.MRE.S)
                return
            end
            try
                slices = app.AppData.ROIs.(roiName).Slices;
            catch
                return
            end
            if isempty(slices)
                return
            end
            keys = fieldnames(slices);
            nStored = numel(keys);
            if nStored == 0
                return
            end
            voxelVolMm3 = app.getMREVoxelVolumeMm3();
            roiConfThr = app.getMREROIConfThresh(roiName);
            for k = 1:numel(keys)
                key = keys{k};
                mask = slices.(key);
                sl = sscanf(key, 'sl%d');
                if isempty(sl), continue; end
                sl = max(1, min(size(app.AppData.MRE.S,3), sl));
                S = double(app.AppData.MRE.S(:,:,sl));
                if isfield(app.AppData.MRE,'LapC') && ~isempty(app.AppData.MRE.LapC)
                    slL = max(1, min(size(app.AppData.MRE.LapC,3), sl));
                    LapC = double(app.AppData.MRE.LapC(:,:,slL));
                    S(LapC < roiConfThr) = NaN;
                end
                if ~isequal(size(mask), [size(S,1) size(S,2)])
                    mask = imresize(logical(mask), [size(S,1) size(S,2)], 'nearest');
                end
                validMask = logical(mask) & isfinite(S);
                vals = S(validMask);
                if isempty(vals)
                    continue
                end
                validPx = [validPx; vals(:)]; %#ok<AGROW>
                totalN = totalN + numel(vals);
            end
            totalVolMm3 = totalN * voxelVolMm3;
        end

        function voxelVolMm3 = getMREVoxelVolumeMm3(app)
            voxelVolMm3 = 1.0;
            dx = NaN; dy = NaN; dz = NaN;
            try
                H = app.AppData.MRE.H;
            catch
                H = [];
            end
            try
                if isstruct(H) && isfield(H,'PixelSpacing') && numel(H.PixelSpacing) >= 2
                    dx = double(H.PixelSpacing(1));
                    dy = double(H.PixelSpacing(2));
                end
            catch
            end
            try
                if isstruct(H) && isfield(H,'SpacingBetweenSlices') && ~isempty(H.SpacingBetweenSlices)
                    dz = double(H.SpacingBetweenSlices);
                elseif isstruct(H) && isfield(H,'SliceThickness') && ~isempty(H.SliceThickness)
                    dz = double(H.SliceThickness);
                end
            catch
            end
            try
                if (~isfinite(dx) || ~isfinite(dy)) && isstruct(H) && isfield(H,'DisplayFieldOfView') && isfield(H,'Rows') && isfield(H,'Columns')
                    fov = double(H.DisplayFieldOfView);
                    if isfinite(fov) && fov > 0
                        dx = fov / double(H.Rows);
                        dy = fov / double(H.Columns);
                    end
                end
            catch
            end
            if ~isfinite(dx) || dx <= 0, dx = 1; end
            if ~isfinite(dy) || dy <= 0, dy = dx; end
            if ~isfinite(dz) || dz <= 0, dz = 1; end
            % Voxel volume is reported in mm^3 and is based on the
            % currently loaded MRE header metadata (preferred source: H).
            voxelVolMm3 = dx * dy * dz;
        end

        function setMREMeasurementLabels(app, roiName, stiffTxt, nVolTxt)
            % NOTE FOR MAINTAINERS:
            % nVolTxt is written into legacy UI properties whose names
            % still include the suffix *IQR. Those properties now display
            % the combined text "N / volume" rather than interquartile
            % range. The separate *Vol properties are retained only for
            % backward compatibility and are no longer shown in the active
            % UI layout.
            switch roiName
                case 'LiverMRE'
                    app.ValLiverStiff.Text = stiffTxt;
                    app.ValLiverStiffIQR.Text = nVolTxt;
                    if ~isempty(app.ValLiverStiffVol), app.ValLiverStiffVol.Text = ''; end
                case 'SpleenMRE'
                    app.ValSpleenStiff.Text = stiffTxt;
                    app.ValSpleenStiffIQR.Text = nVolTxt;
                    if ~isempty(app.ValSpleenStiffVol), app.ValSpleenStiffVol.Text = ''; end
                case 'MuscleMRE'
                    app.ValMuscleMREStiff.Text = stiffTxt;
                    app.ValMuscleMREStiffIQR.Text = nVolTxt;
                    if ~isempty(app.ValMuscleMREStiffVol), app.ValMuscleMREStiffVol.Text = ''; end
                case 'FatMRE'
                    app.ValFatMREStiff.Text = stiffTxt;
                    app.ValFatMREStiffIQR.Text = nVolTxt;
                    if ~isempty(app.ValFatMREStiffVol), app.ValFatMREStiffVol.Text = ''; end
            end
        end

        function clearStoredMREROISlice(app, roiName, sl)
            switch roiName
                case 'LiverMRE'
                    app.AppData.ROIs.LiverMRE.Slices  = removeSlice(app.AppData.ROIs.LiverMRE.Slices, sl);
                case 'SpleenMRE'
                    app.AppData.ROIs.SpleenMRE.Slices = removeSlice(app.AppData.ROIs.SpleenMRE.Slices, sl);
                case 'MuscleMRE'
                    app.AppData.ROIs.MuscleMRE.Slices = removeSlice(app.AppData.ROIs.MuscleMRE.Slices, sl);
                case 'FatMRE'
                    app.AppData.ROIs.FatMRE.Slices    = removeSlice(app.AppData.ROIs.FatMRE.Slices, sl);
            end
        end

        function setMRETechnicalFailure(app, roiName)
            if nargin < 2 || isempty(roiName)
                roiName = app.AppData.MREROIName;
            end
            if ~isfield(app.AppData,'MRETechFailure') || ~isstruct(app.AppData.MRETechFailure)
                app.AppData.MRETechFailure = struct('LiverMRE',false,'SpleenMRE',false,'MuscleMRE',false,'FatMRE',false);
            end
            if isfield(app.AppData.MRETechFailure, roiName)
                app.AppData.MRETechFailure.(roiName) = true;
            end
        end

        function updateMuscleSATRatio(app)
            try
                m1 = str2double(strrep(app.ValMuscleL1Area.Text,' cm²',''));
                m2 = str2double(strrep(app.ValMuscleL2Area.Text,' cm²',''));
                s1 = str2double(strrep(app.ValSATL1Area.Text,' cm²',''));
                s2 = str2double(strrep(app.ValSATL2Area.Text,' cm²',''));
                totalM = nanmean([m1 m2]); totalS = nanmean([s1 s2]);
                if isfinite(totalM) && isfinite(totalS) && totalS>0
                    app.ValMuscleSATRatio.Text = sprintf('%.3f',totalM/totalS);
                end
            catch
            end
        end

        function overlayROIOnDixon(app, roiName, mask)
            bnd = bwboundaries(mask);
            clr = dixonROIColor(roiName);
            axesList = {app.AxDixonPDFF, app.AxDixonIP, app.AxDixonWater};
            for ii = 1:numel(axesList)
                ax = axesList{ii};
                if isempty(ax) || ~isvalid(ax), continue; end
                hold(ax,'on');
                for b = 1:numel(bnd)
                    plot(ax, bnd{b}(:,2), bnd{b}(:,1), '-','Color',clr,'LineWidth',2);
                end
                hold(ax,'off');
            end
        end

        function updateStudyBrowser(app, exam, selection)
            delete(app.StudyTree.Children);
            root = uitreenode(app.StudyTree,'Text', ...
                sprintf('%s  %s  (%s)', exam.PatientID, exam.StudyDate, exam.MREType));
            root.NodeData = exam;
            if ~isempty(selection.Localizer)
                uitreenode(root,'Text',sprintf('[Localizer]  S%d  %s', ...
                    selection.Localizer.SeriesNumber, selection.Localizer.SeriesDescription));
            end
            if ~isempty(selection.Dixon)
                dixNode = uitreenode(root,'Text', ...
                    sprintf('[Dixon / IDEAL-IQ]  %d series', numel(selection.DixonGroup)));
                for k = 1:numel(selection.DixonGroup)
                    s = selection.DixonGroup(k);
                    roleDisp = strrep(s.Role,'IDEALIQ_','');
                    uitreenode(dixNode,'Text',sprintf('  S%d  %-12s  %s', ...
                        s.SeriesNumber, roleDisp, s.SeriesDescription));
                end
            end
            if ~isempty(selection.MRE)
                mreNode = uitreenode(root,'Text', ...
                    sprintf('[MRE]  %d series', numel(selection.MREGroup)));
                for k = 1:numel(selection.MREGroup)
                    s = selection.MREGroup(k);
                    roleDisp = mreRoleLabel(s.Role);
                    uitreenode(mreNode,'Text',sprintf('  S%d  %-14s  %s', ...
                        s.SeriesNumber, roleDisp, s.SeriesDescription));
                end
            end
            expand(root,'all');
            app.LblStudyStats.Text = sprintf('%d series loaded', numel(exam.Series));
        end

        function updateResultsFromStruct(app, results)
            rows = {};
            if isfield(results,'L12') && isfield(results.L12,'L1')
                L1 = results.L12.L1; L2 = results.L12.L2;
                rows{end+1} = {'Muscle area T12',  sprintf('%.1f',L1.MuscleArea_cm2), 'cm²',  ''};
                rows{end+1} = {'Muscle PDFF T12',  sprintf('%.1f',L1.MusclePDFF_pct), '%',    ''};
                rows{end+1} = {'SAT area T12',      sprintf('%.1f',L1.SATArea_cm2),   'cm²',  ''};
                rows{end+1} = {'SAT PDFF T12',      sprintf('%.1f',L1.SAT_PDFF_pct),  '%',    ''};
                rows{end+1} = {'Muscle area L3',  sprintf('%.1f',L2.MuscleArea_cm2), 'cm²',  ''};
                rows{end+1} = {'Muscle:SAT ratio', sprintf('%.3f',L1.MuscleSATRatio),'',     ''};
            end
            if ~isempty(rows)
                app.ResultsTable.Data = vertcat(rows{:});
            end
        end

        function updateResultsTable(app)
        % Rebuild the Results tab table from all stored ROI measurements.
        % Rows: one per (organ, slice) combination, showing PDFF and MRE stiffness.
        % Notes column flags slices within 15 mm of a confirmed disc marker.
            try
                rows = {};
                dix  = app.AppData.Dixon;
                mre  = app.AppData.MRE;

                % ── Geometry helpers ──────────────────────────────────────
                dx = 1; dy = 1; dz = 5;
                dixSliceZ = [];
                if ~isempty(dix)
                    try, dx = dix.PixelSpacing_mm(1); dy = dix.PixelSpacing_mm(2); catch, end
                    try, dz = dix.SliceThickness_mm; catch, end
                    try, dixSliceZ = buildDixonSliceZ(dix); catch, end
                end
                voxVol = dx * dy * dz;   % mm³ per voxel

                % ── Disc landmark proximity helper ────────────────────────
                lmNames = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
                lmShort = {'T9-10','T10-11','T11-12','T12-L1','L1-2','L2-3','L3-4'};
                PROX_MM = 15;   % show note when within this distance (mm)

                getNote = @(sliceZ) resultsDiscNote(sliceZ, ...
                    app.AppData.LM_Dixon, lmNames, lmShort, PROX_MM, dixSliceZ);

                % ── PDFF ROI organs ───────────────────────────────────────
                dixOrgans = { ...
                    'LiverDixon',  'Fat fraction (liver)'; ...
                    'SpleenDixon', 'Fat fraction (spleen)'; ...
                    'PsoasDixon',  'Fat fraction (psoas)'; ...
                    'TrunkDixon',  'Fat fraction (trunk muscle)'; ...
                    'SATDixon',    'Fat fraction (SAT)'; ...
                    'VATDixon',    'Fat fraction (VAT)'};

                if ~isempty(dix) && ~isempty(dix.PDFF)
                    for oi = 1:size(dixOrgans,1)
                        rn    = dixOrgans{oi,1};
                        label = dixOrgans{oi,2};
                        if ~isfield(app.AppData.ROIs, rn), continue; end
                        slKeys = fieldnames(app.AppData.ROIs.(rn).Slices);
                        for ki = 1:numel(slKeys)
                            key  = slKeys{ki};
                            sl   = str2double(strrep(key,'sl',''));
                            mask = logical(app.AppData.ROIs.(rn).Slices.(key));
                            if ~any(mask(:)), continue; end
                            nVox = sum(mask(:));
                            vol  = nVox * voxVol;
                            % Mean PDFF in ROI
                            pdffMean = NaN;
                            if sl >= 1 && sl <= size(dix.PDFF,3)
                                ff = double(dix.PDFF(:,:,sl));
                                pdffMean = mean(ff(mask(:)));
                            end
                            % Slice location label
                            slLocTxt = sprintf('Sl%d', sl);
                            if ~isempty(dixSliceZ) && sl <= numel(dixSliceZ)
                                slLocTxt = sprintf('Sl%d (%.1fmm)', sl, dixSliceZ(sl));
                            end
                            note = getNote(sl);
                            rows{end+1} = {slLocTxt, label, ...   %#ok<AGROW>
                                sprintf('%.0f', vol), ...
                                sprintf('%.1f', pdffMean), '%', note};
                        end
                    end
                end

                % ── MRE stiffness ROI organs ──────────────────────────────
                mreOrgans = { ...
                    'LiverMRE',  'Stiffness (liver)'; ...
                    'SpleenMRE', 'Stiffness (spleen)'; ...
                    'MuscleMRE', 'Stiffness (muscle)'; ...
                    'FatMRE',    'Stiffness (fat)'};

                mreSliceZ = [];
                mreDx = 1; mreDy = 1; mreDz = 5;
                if ~isempty(mre)
                    try
                        mreSliceZ = buildSliceZFromSinfo(mre.SpatialInfo);
                    catch, end
                    try, mreDx = mre.PixelSpacing_mm(1); mreDy = mre.PixelSpacing_mm(2); catch, end
                    try, mreDz = mre.SliceThickness_mm; catch, end
                end
                mreVoxVol = mreDx * mreDy * mreDz;
                getMRENote = @(sl) resultsDiscNote(sl, ...
                    app.AppData.LM_MRE, lmNames, lmShort, PROX_MM, mreSliceZ);

                if ~isempty(mre) && isfield(mre,'S') && ~isempty(mre.S)
                    for oi = 1:size(mreOrgans,1)
                        rn    = mreOrgans{oi,1};
                        label = mreOrgans{oi,2};
                        if ~isfield(app.AppData.ROIs, rn), continue; end
                        slKeys = fieldnames(app.AppData.ROIs.(rn).Slices);
                        for ki = 1:numel(slKeys)
                            key  = slKeys{ki};
                            sl   = str2double(strrep(key,'sl',''));
                            mask = logical(app.AppData.ROIs.(rn).Slices.(key));
                            if ~any(mask(:)), continue; end
                            nVox = sum(mask(:));
                            vol  = nVox * mreVoxVol;
                            stiffMean = NaN;
                            if sl >= 1 && sl <= size(mre.S,3)
                                st = double(mre.S(:,:,sl));
                                stiffMean = mean(st(mask(:)));
                            end
                            slLocTxt = sprintf('Sl%d', sl);
                            if ~isempty(mreSliceZ) && sl <= numel(mreSliceZ)
                                slLocTxt = sprintf('Sl%d (%.1fmm)', sl, mreSliceZ(sl));
                            end
                            note = getMRENote(sl);
                            rows{end+1} = {slLocTxt, label, ...   %#ok<AGROW>
                                sprintf('%.0f', vol), ...
                                sprintf('%.2f', stiffMean), 'kPa', note};
                        end
                    end
                end

                if isempty(rows)
                    rows = {{'—','—','—','—','—','No ROIs drawn yet'}};
                end
                app.ResultsTable.Data = vertcat(rows{:});
            catch ME
                warning('updateResultsTable:fail', '%s', ME.message);
            end
        end

        function exportPDFFRadiomicsCSV(app)
            dix = app.AppData.Dixon;
            if isempty(dix) || isempty(dix.PDFF)
                uialert(app.UIFigure,'No PDFF data loaded.','Export'); return
            end
            examPath = '';
            try, examPath = app.AppData.ExamPath; catch, end
            if isempty(examPath) || ~isfolder(examPath)
                uialert(app.UIFigure,'No exam folder set — load a study first.','Export'); return
            end
            outFile = fullfile(examPath, 'pdff_radiomics.csv');
            try
                setStatus(app,'Computing PDFF radiomics features (this may take a moment)...');
                drawnow;
                dx = dix.PixelSpacing_mm(1); dy = dix.PixelSpacing_mm(2);
                dz = dix.SliceThickness_mm;
                dixSliceZ = [];
                try, dixSliceZ = buildDixonSliceZ(dix); catch, end
                organs = {'LiverDixon','SpleenDixon','PsoasDixon','TrunkDixon','SATDixon','VATDixon'};
                hdr = radiomicsCSVHeader();
                lines = {hdr};
                for oi = 1:numel(organs)
                    rn = organs{oi};
                    if ~isfield(app.AppData.ROIs,rn), continue; end
                    slKeys = fieldnames(app.AppData.ROIs.(rn).Slices);
                    for ki = 1:numel(slKeys)
                        key  = slKeys{ki};
                        sl   = str2double(strrep(key,'sl',''));
                        mask = logical(app.AppData.ROIs.(rn).Slices.(key));
                        if ~any(mask(:)) || sl < 1 || sl > size(dix.PDFF,3), continue; end
                        img2d = double(dix.PDFF(:,:,sl));
                        vals  = img2d(mask(:));
                        slZ   = NaN;
                        if ~isempty(dixSliceZ) && sl <= numel(dixSliceZ), slZ = dixSliceZ(sl); end
                        row = buildRadiomicsRow(rn, sl, slZ, vals, mask, img2d, dx, dy, dz);
                        lines{end+1} = row; %#ok<AGROW>
                    end
                end
                fid = fopen(outFile,'w');
                fprintf(fid,'%s\n',lines{:});
                fclose(fid);
                setStatus(app,sprintf('PDFF radiomics saved → %s', outFile));
            catch ME
                uialert(app.UIFigure, ME.message,'Export Error','Icon','error');
                setStatus(app,['PDFF radiomics export failed: ' ME.message]);
            end
        end

        function exportMRERadiomicsCSV(app)
            mre = app.AppData.MRE;
            if isempty(mre) || ~isfield(mre,'S') || isempty(mre.S)
                uialert(app.UIFigure,'No MRE stiffness data loaded.','Export'); return
            end
            examPath = '';
            try, examPath = app.AppData.ExamPath; catch, end
            if isempty(examPath) || ~isfolder(examPath)
                uialert(app.UIFigure,'No exam folder set — load a study first.','Export'); return
            end
            outFile = fullfile(examPath, 'mre_radiomics.csv');
            try
                setStatus(app,'Computing MRE radiomics features (this may take a moment)...');
                drawnow;
                mreDx = 1; mreDy = 1; mreDz = 5;
                try, mreDx = mre.PixelSpacing_mm(1); mreDy = mre.PixelSpacing_mm(2); catch, end
                try, mreDz = mre.SliceThickness_mm; catch, end
                mreSliceZ = [];
                try, mreSliceZ = buildSliceZFromSinfo(mre.SpatialInfo); catch, end
                organs = {'LiverMRE','SpleenMRE','MuscleMRE','FatMRE'};
                hdr = radiomicsCSVHeader();
                lines = {hdr};
                for oi = 1:numel(organs)
                    rn = organs{oi};
                    if ~isfield(app.AppData.ROIs,rn), continue; end
                    slKeys = fieldnames(app.AppData.ROIs.(rn).Slices);
                    for ki = 1:numel(slKeys)
                        key  = slKeys{ki};
                        sl   = str2double(strrep(key,'sl',''));
                        mask = logical(app.AppData.ROIs.(rn).Slices.(key));
                        if ~any(mask(:)) || sl < 1 || sl > size(mre.S,3), continue; end
                        img2d = double(mre.S(:,:,sl));
                        vals  = img2d(mask(:));
                        slZ   = NaN;
                        if ~isempty(mreSliceZ) && sl <= numel(mreSliceZ), slZ = mreSliceZ(sl); end
                        row = buildRadiomicsRow(rn, sl, slZ, vals, mask, img2d, mreDx, mreDy, mreDz);
                        lines{end+1} = row; %#ok<AGROW>
                    end
                end
                fid = fopen(outFile,'w');
                fprintf(fid,'%s\n',lines{:});
                fclose(fid);
                setStatus(app,sprintf('MRE radiomics saved → %s', outFile));
            catch ME
                uialert(app.UIFigure, ME.message,'Export Error','Icon','error');
                setStatus(app,['MRE radiomics export failed: ' ME.message]);
            end
        end

        function showRadiomicsHelp(app)
            showRadiomicsHelpDialog(app.UIFigure);
        end

        function setStatus(app, msg)
            ts = datestr(now,'HH:MM:SS');
            app.LblStatusMsg.Text = sprintf('[%s]  %s', ts, msg);
            try
                drawnow limitrate nocallbacks;
            catch
                drawnow limitrate;
            end
        end

        function L12 = rowsToL12mm(app, sinfo)
            L12 = struct('L1_mm',NaN,'L2_mm',NaN,'L1_L2_mid_mm',NaN, ...
                'L1_row_coronal',app.AppData.L1_CorRow, ...
                'L2_row_coronal',app.AppData.L2_CorRow, ...
                'Confidence',1.0,'DetectionMethod','manual', ...
                'SourcePlane','Coronal','PixelSpacing_mm',[1 1]);
            try
                ps = sinfo.PixelSpacing(1);
                iop = sinfo.ImageOrientationPatient;
                colDir = iop(4:6);   % column direction (down the image)
                imgPos = app.AppData.Localizer.Coronal.ImagePositions( ...
                    app.AppData.CorSlice,:);
                L1pos = imgPos + (app.AppData.L1_CorRow-1)*ps*colDir;
                L2pos = imgPos + (app.AppData.L2_CorRow-1)*ps*colDir;
                L12.L1_mm = L1pos(3); L12.L2_mm = L2pos(3);
                L12.L1_L2_mid_mm = (L12.L1_mm+L12.L2_mm)/2;
                L12.PixelSpacing_mm = [ps ps];
            catch
            end
        end

        % -----------------------------------------------------------------
        %  SCROLL-WHEEL NAVIGATION
        % -----------------------------------------------------------------
        function onScrollWheel(app, event)
            % Route scroll wheel to the image the cursor is currently over.
            delta = -event.VerticalScrollCount;   % positive = scroll up = next slice
            switch app.AppData.LocHoverAxes
                case 'cor'
                    nMax = round(app.SldrLocCor.Limits(2));
                    sl   = max(1, min(nMax, app.AppData.CorSlice + delta));
                    app.AppData.CorSlice = sl;
                    app.SldrLocCor.Value = sl;
                    app.LblLocCor.Text   = sprintf('%d/%d', sl, nMax);
                    refreshLocCoronal(app);
                case 'sag'
                    nMax = round(app.SldrLocSag.Limits(2));
                    sl   = max(1, min(nMax, app.AppData.SagSlice + delta));
                    app.AppData.SagSlice = sl;
                    app.SldrLocSag.Value = sl;
                    app.LblLocSag.Text   = sprintf('%d/%d', sl, nMax);
                    refreshLocSagittal(app);
            end
        end

        function onMouseMove(app)
            try
                if (isfield(app.AppData,'MREROIDrawing') && app.AppData.MREROIDrawing) || ...
                        (isfield(app.AppData,'MREROIBusy') && app.AppData.MREROIBusy)
                    return
                end
            catch
            end
            % ── 1. Cursor value readout for quantitative image axes ──────
            try
                activeTab  = app.ImageTabGroup.SelectedTab;
                isDixonTab = isequal(activeTab, app.DixonTab);
                isMRETab   = isequal(activeTab, app.MRETab);
            catch
                isDixonTab = false; isMRETab = false;
            end
            quantAxes  = {app.AxMREWave, app.AxMREStiff, app.AxDixonPDFF, app.AxDixonIP, app.AxDixonWater};
            quantData  = {app.AppData.DispWave, app.AppData.DispStiff, app.AppData.DispDixon, ...
                          app.AppData.DispDixonIP, app.AppData.DispDixonOP};
            quantLabel = {'Wave', 'Stiffness (kPa)', 'PDFF (%)', 'Water/IP', 'Fat/OP'};
            tabMask    = {isMRETab, isMRETab, isDixonTab, isDixonTab, isDixonTab};
            hitQuant   = false;
            for k = 1:numel(quantAxes)
                if ~tabMask{k}, continue; end   % skip axes that belong to another tab
                ax  = quantAxes{k};
                dat = quantData{k};
                if isempty(dat), continue; end
                try
                    cp = ax.CurrentPoint;
                    x  = round(cp(1,1));
                    y  = round(cp(1,2));
                    xl = ax.XLim; yl = ax.YLim;
                    if x >= xl(1) && x <= xl(2) && y >= yl(1) && y <= yl(2) && ...
                       x >= 1 && x <= size(dat,2) && y >= 1 && y <= size(dat,1)
                        val = dat(y, x);
                        app.LblCursorVal.Text = sprintf('%s  (x=%d, y=%d) = %.3g', ...
                            quantLabel{k}, x, y, val);
                        hitQuant = true;
                        break
                    end
                catch; end
            end
            if ~hitQuant
                app.LblCursorVal.Text = '';
            end

            % ── 2. Localizer scroll-wheel routing ─────────────────────────
            try
                cp = app.AxLocCoronal.CurrentPoint;
                xl = app.AxLocCoronal.XLim;
                yl = app.AxLocCoronal.YLim;
                if cp(1,1) >= xl(1) && cp(1,1) <= xl(2) && ...
                   cp(1,2) >= yl(1) && cp(1,2) <= yl(2)
                    app.AppData.LocHoverAxes = 'cor';
                    return
                end
            catch; end
            try
                cp = app.AxLocSagittal.CurrentPoint;
                xl = app.AxLocSagittal.XLim;
                yl = app.AxLocSagittal.YLim;
                if cp(1,1) >= xl(1) && cp(1,1) <= xl(2) && ...
                   cp(1,2) >= yl(1) && cp(1,2) <= yl(2)
                    app.AppData.LocHoverAxes = 'sag';
                    return
                end
            catch; end
            app.AppData.LocHoverAxes = '';
        end

        % -----------------------------------------------------------------
        %  L1/L2 CLICK HANDLER (fires from ButtonDownFcn on either axes)
        % -----------------------------------------------------------------
        function onLocImageClick(app, event, plane, lmName)  %#ok<INUSD>
            if ~strcmp(app.AppData.AwaitingClick, lmName), return; end

            % Clear armed state immediately
            cancelPendingClick(app);

            % Use ax.CurrentPoint (reliable in App Designer uiaxes)
            ax = app.AxLocCoronal;
            if strcmp(plane, 'sag'), ax = app.AxLocSagittal; end
            cp   = ax.CurrentPoint;
            rowY = round(cp(1, 2));

            if strcmp(plane, 'cor')
                corRow = rowY;
                sagRow = corRowToSagRow(app, corRow);
            else
                corRow = sagRowToCorRow(app, rowY, app.AppData.SagSlice);
                sagRow = rowY;
            end

            % Store in new LM struct (and legacy fields for T12L1/L3L4)
            if isfield(app.AppData.LM, lmName)
                app.AppData.LM.(lmName).CorRow = corRow;
                app.AppData.LM.(lmName).SagRow = sagRow;
            end
            % Keep legacy T12/L3 fields in sync
            if strcmp(lmName,'T12L1')
                app.AppData.L1_CorRow = corRow; app.AppData.L1_SagRow = sagRow;
            elseif strcmp(lmName,'L3L4')
                app.AppData.L2_CorRow = corRow; app.AppData.L2_SagRow = sagRow;
            end

            refreshLocCoronal(app);
            refreshLocSagittal(app);
            updateLandmarkStatus(app);
        end

        % -----------------------------------------------------------------
        %  COORDINATE CONVERSION HELPERS
        % -----------------------------------------------------------------
        function sagRow = corRowToSagRow(app, corRow, sagSliceOverride)
            % Convert a coronal row index to the equivalent sagittal row index
            % using patient-coordinate Z positions.
            % Both panels use column direction cosines (iop(4:6)) for row→Z.
            sagRow = NaN;
            if isnan(corRow), return; end
            loc = app.AppData.Localizer;
            if isempty(loc), return; end

            % --- coronal row → Z mm ---
            try
                cor    = loc.Coronal;
                corSl  = app.AppData.CorSlice;
                corSl  = max(1, min(size(cor.Volume,3), corSl));
                ps     = cor.SpatialInfo.PixelSpacing(1);
                iop    = cor.SpatialInfo.ImageOrientationPatient;
                colDir = iop(4:6);   % column direction (down the image)
                imgPos = cor.ImagePositions(corSl, :);
                ptMm   = imgPos + (corRow - 1) * ps * colDir;
                z_mm   = ptMm(3);
            catch
                return
            end

            % --- Z mm → sagittal row ---
            try
                sag    = loc.Sagittal;
                if nargin < 3 || isempty(sagSliceOverride)
                    sagSl = app.AppData.SagSlice;
                else
                    sagSl = sagSliceOverride;
                end
                sagSl   = max(1, min(size(sag.Volume,3), sagSl));
                ps2     = sag.SpatialInfo.PixelSpacing(1);
                iop2    = sag.SpatialInfo.ImageOrientationPatient;
                colDir2 = iop2(4:6);   % column direction (down the sagittal image)
                imgPos2 = sag.ImagePositions(sagSl, :);
                dz      = colDir2(3);
                if abs(dz) < 1e-6, return; end
                sagRow = round(1 + (z_mm - imgPos2(3)) / (ps2 * dz));
                nRows  = size(sag.Volume, 1);
                if sagRow < 1 || sagRow > nRows, sagRow = NaN; end
            catch
                return
            end
        end

        function z_mm = corRowToZmm(app, corRow)
            % Convert a coronal row index to patient Z coordinate (mm, LPS).
            % Moving down a coronal image (increasing row) moves in the
            % COLUMN direction (iop(4:6)), NOT the row direction (iop(1:3)).
            z_mm = NaN;
            if isnan(corRow), return; end
            loc = app.AppData.Localizer;
            if isempty(loc), return; end
            try
                cor    = loc.Coronal;
                corSl  = app.AppData.CorSlice;
                corSl  = max(1, min(size(cor.Volume,3), corSl));
                ps     = cor.SpatialInfo.PixelSpacing(1);   % row spacing (mm per row step)
                iop    = cor.SpatialInfo.ImageOrientationPatient;
                colDir = iop(4:6);   % column direction cosines (down the image)
                imgPos = cor.ImagePositions(corSl, :);
                ptMm   = imgPos + (corRow - 1) * ps * colDir;
                z_mm   = ptMm(3);
            catch
            end
        end

        function corRow = sagRowToCorRow(app, sagRow, sagSlice)
            % Convert a sagittal row index (on given slice) to a coronal row index.
            % Both panels use column direction cosines (iop(4:6)) for row→Z.
            corRow = NaN;
            if isnan(sagRow), return; end
            loc = app.AppData.Localizer;
            if isempty(loc), return; end

            % --- sagittal row → Z mm ---
            try
                sag    = loc.Sagittal;
                sagSl  = max(1, min(size(sag.Volume,3), sagSlice));
                ps     = sag.SpatialInfo.PixelSpacing(1);
                iop    = sag.SpatialInfo.ImageOrientationPatient;
                colDir = iop(4:6);   % column direction (down the sagittal image)
                imgPos = sag.ImagePositions(sagSl, :);
                ptMm   = imgPos + (sagRow - 1) * ps * colDir;
                z_mm   = ptMm(3);
            catch
                return
            end

            % --- Z mm → coronal row ---
            try
                cor    = loc.Coronal;
                corSl  = app.AppData.CorSlice;
                corSl  = max(1, min(size(cor.Volume,3), corSl));
                ps2     = cor.SpatialInfo.PixelSpacing(1);
                iop2    = cor.SpatialInfo.ImageOrientationPatient;
                colDir2 = iop2(4:6);   % column direction (down the coronal image)
                imgPos2 = cor.ImagePositions(corSl, :);
                dz      = colDir2(3);
                if abs(dz) < 1e-6, return; end
                corRow = round(1 + (z_mm - imgPos2(3)) / (ps2 * dz));
                nRows  = size(cor.Volume, 1);
                if corRow < 1 || corRow > nRows, corRow = NaN; end
            catch
                return
            end
        end

    end

    methods (Access = private)
        function ensureRepoPath(app) %#ok<MANU>
            repoRoot = fileparts(mfilename('fullpath'));
            addList = {repoRoot, ...
                fullfile(repoRoot,'functions','io'), ...
                fullfile(repoRoot,'functions','registration'), ...
                fullfile(repoRoot,'functions','segmentation'), ...
                fullfile(repoRoot,'functions','harmonization')};
            for kk = 1:numel(addList)
                if isfolder(addList{kk})
                    addpath(addList{kk});
                end
            end
            rehash;
        end
    end

    % =====================================================================
    %  CONSTRUCTOR / DESTRUCTOR
    % =====================================================================
    methods (Access = public)
        function app = HepatosplenicMRE_App()
            ensureRepoPath(app);
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            app.UIFigure.Visible = 'on';
            if nargout == 0, clear app; end
        end
        function delete(app)
            try
                if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                    stop(app.AppData.MRETimer);
                    delete(app.AppData.MRETimer);
                end
            catch
            end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch
            end
        end
    end

end % classdef


% =========================================================================
%  MODULE-LEVEL HELPERS
% =========================================================================

function s = siCoordStr(z_mm)
% Format a patient Z coordinate (mm) as "S123" (Superior) or "I45" (Inferior).
% Returns '' if z_mm is NaN.
    if isnan(z_mm)
        s = '';
    elseif z_mm >= 0
        s = sprintf('S%d', abs(round(z_mm)));
    else
        s = sprintf('I%d', abs(round(z_mm)));
    end
end

function vol = dixonVolume(dix, contrast)
% Return the 3-D volume for the requested Dixon contrast string.
    vol = [];
    if isempty(dix), return; end
    switch contrast
        case 'PDFF'
            if isfield(dix,'PDFF'),     vol = dix.PDFF;     end
        case 'Water'
            if isfield(dix,'Water'),    vol = dix.Water;    end
        case 'Fat'
            if isfield(dix,'Fat'),      vol = dix.Fat;      end
        case 'T2star'
            f   = fieldnames(dix);
            t2f = f(strcmpi(f,'T2star'));
            if ~isempty(t2f),           vol = dix.(t2f{1}); end
        case 'InPhase'
            if isfield(dix,'InPhase'),  vol = dix.InPhase;  end
        case 'OutPhase'
            if isfield(dix,'OutPhase'), vol = dix.OutPhase; end
        otherwise
            if isfield(dix,'Water'),    vol = dix.Water;    end
    end
end
function vol = dixonPreferredDisplayVolume(dix, which)
% Return the preferred volume for the fixed three-panel Dixon view.
% Water panel: prefer Water (T2*-corrected) over InPhase when both exist.
% Fat panel:   prefer Fat  (T2*-corrected) over OutPhase when both exist.
    vol = [];
    switch which
        case 'PDFF'
            vol = dixonVolume(dix, 'PDFF');
        case 'InPhase'
            vol = dixonVolume(dix, 'Water');
            if isempty(vol), vol = dixonVolume(dix, 'InPhase'); end
        case 'OutPhase'
            vol = dixonVolume(dix, 'Fat');
            if isempty(vol), vol = dixonVolume(dix, 'OutPhase'); end
    end
end

function renderDixonPanelAxes(app, ax, vol, sl, nZ, labelTxt, isPdff, panelKey)
% panelKey (optional): 'water'|'fat' to apply user W/L; omit for auto.
    if nargin < 8, panelKey = ''; end
    if isempty(ax) || ~isvalid(ax)
        return
    end
    cla(ax);
    if isempty(vol)
        title(ax, sprintf('%s — not available', labelTxt), ...
            'FontSize',12,'Color',[0.7 0.4 0.2],'FontWeight','normal');
        ax.XTick=[]; ax.YTick=[];
        return
    end
    img = double(vol(:,:, min(sl, size(vol,3))));
    imagesc(ax, img);
    if isPdff
        cmapName = app.AppData.DixonCmap;
        if endsWith(cmapName, '_r')
            baseName = cmapName(1:end-2);
            try, cmapData = flip(feval(baseName, 256), 1); catch, cmapData = flip(gray(256),1); end
            colormap(ax, cmapData);
        else
            try, colormap(ax, cmapName); catch, colormap(ax, 'hot'); end
        end
        lo = app.AppData.DixonClimMin;
        hi = app.AppData.DixonClimMax;
        if lo == 0 && hi == 0
            lo = min(img(:)); hi = max(img(:));
        end
        if hi > lo, clim(ax, [lo hi]); end
    else
        colormap(ax, 'gray');
        % Apply user-defined W/L when available, otherwise auto.
        userLo = 0; userHi = 0;
        try
            switch panelKey
                case 'water'
                    userLo = app.EdtWaterWinLo.Value;
                    userHi = app.EdtWaterWinHi.Value;
                case 'fat'
                    userLo = app.EdtFatWinLo.Value;
                    userHi = app.EdtFatWinHi.Value;
            end
        catch
        end
        if userHi > userLo
            clim(ax, [userLo userHi]);
        else
            [lo, hi] = robustCLim(img, 1, 99, false);
            if hi > lo, clim(ax, [lo hi]); end
        end
    end
    axis(ax,'image');
    ax.XTick=[]; ax.YTick=[];
    title(ax, sprintf('%s   sl %d/%d', labelTxt, sl, nZ), ...
        'FontSize',13,'Color',[0.78 0.78 0.78],'FontWeight','normal');
    overlayDixonLevelMarkers(app, ax, img, sl);
    overlayStoredDixonROIs(app, ax, sl, ~isPdff);
end

function overlayDixonLevelMarkers(app, ax, img, sl)
% Draw disc landmark lines on a Dixon panel axes.
% A dashed line + label is shown when the current slice is within 5 mm of
% a confirmed landmark.  The distance is shown in the label if > 1 mm.
    THRESH_MM = 5.0;   % show marker when closer than this
    lmNames  = {'T9T10','T10T11','T11T12','T12L1','L1L2','L2L3','L3L4'};
    lmColors = {[0.55 0.05 0.05],[0.75 0.10 0.10],[0.88 0.35 0.08],[0.92 0.65 0.05],[0.30 0.72 0.30],[0.15 0.58 0.88],[0.50 0.20 0.85]};

    nC = size(img, 2);
    nR = size(img, 1);
    anyDrawn = false;
    try
        lmDix = app.AppData.LM_Dixon;
    catch
        lmDix = [];
    end
    if isempty(lmDix), return; end

    hold(ax,'on');
    textRow = 8;   % y offset for successive labels so they don't overlap
    for ki = 1:7
        n   = lmNames{ki};
        clr = lmColors{ki};
        try
            si = lmDix.(n).SliceIdx;
            dm = lmDix.(n).Dist_mm;
        catch
            continue
        end
        if isnan(si) || isnan(dm), continue; end
        if dm > THRESH_MM, continue; end   % outside threshold → skip
        if round(si) ~= sl, continue; end  % not this slice → skip

        % Draw dashed line across the image
        hl = plot(ax, [1 nC], [textRow textRow], '--', 'Color', clr, 'LineWidth', 1.8);
        try; hl.HitTest='off'; hl.PickableParts='none'; catch, end

        % Label: disc name + distance if > 1 mm
        lbl = locLandmarkLabel(n);
        if dm > 1.0
            lbl = sprintf('%s  (%.1f mm)', lbl, dm);
        end
        ht = text(ax, 4, textRow + 9, lbl, 'Color', clr, 'FontSize', 11, ...
            'FontWeight','bold','HorizontalAlignment','left');
        try; ht.HitTest='off'; ht.PickableParts='none'; catch, end
        anyDrawn = true;
        textRow = textRow + 18;   % next label below this one
    end
    hold(ax,'off');
end

function overlayStoredDixonROIs(app, ax, sl, doFill)
    if nargin < 4, doFill = false; end
    key = sprintf('sl%d', sl);
    items = {};
    for rn = {'LiverDixon','SpleenDixon','PsoasDixon','TrunkDixon','MuscleDixon','SATDixon','VATDixon'}
        roiName = rn{1};
        try
            if isfield(app.AppData.ROIs.(roiName).Slices, key)
                items(end+1,:) = {roiName, app.AppData.ROIs.(roiName).Slices.(key)}; %#ok<AGROW>
            end
        catch
        end
    end
    % Overlay active-workflow preview mask if on this slice
    try
        if app.AppData.DixonROIActive && app.AppData.DixonROISlice == sl && ...
                ~isempty(app.AppData.DixonROIFinalMask)
            items(end+1,:) = {app.AppData.DixonROIName, app.AppData.DixonROIFinalMask}; %#ok<AGROW>
        end
    catch
    end
    if isempty(items), return; end
    hold(ax,'on');
    for ii = 1:size(items,1)
        roiName = items{ii,1};
        mask = logical(items{ii,2});
        if ~any(mask(:)), continue; end
        clr = dixonROIColor(roiName);
        % Semi-transparent fill on Water/Fat panels
        if doFill
            [nR, nC] = size(mask);
            colorData = reshape(clr, [1 1 3]);
            colorData = repmat(colorData, [nR nC 1]);
            hFill = image(ax, 'CData', colorData, 'AlphaData', single(mask)*0.25, ...
                'XData', [1 nC], 'YData', [1 nR]);
            try; hFill.HitTest = 'off'; hFill.PickableParts = 'none'; catch; end
        end
        bnd = bwboundaries(mask);
        for b = 1:numel(bnd)
            plot(ax, bnd{b}(:,2), bnd{b}(:,1), '-', 'Color', clr, 'LineWidth', 2);
        end
    end
    hold(ax,'off');
end

function tf = endsWith(str, suffix)
    tf = numel(str) >= numel(suffix) && strcmp(str(end-numel(suffix)+1:end), suffix);
end

function lbl = mreRoleLabel(role)
% Map internal Role string to friendly display name for study browser.
    map = struct( ...
        'GRE_WaveMag_Raw',  'WaveMag_Raw', ...
        'GRE_WaveMag',      'WaveMag_Raw', ...
        'GRE_WaveMag_Proc', 'ProcessedWave', ...
        'GRE_ProcWave',     'ProcessedWave', ...
        'GRE_Stiffness',    'Stiffness', ...
        'GRE_ConfMap',      'ConfMap', ...
        'EPI_WaveMag_Raw',  'WaveMag_Raw', ...
        'EPI_WaveMag',      'WaveMag_Raw', ...
        'EPI_WaveMag_Proc', 'ProcessedWave', ...
        'EPI_ProcWave',     'ProcessedWave', ...
        'EPI_Stiffness',    'Stiffness', ...
        'EPI_ConfMap',      'ConfMap');
    if isfield(map, role)
        lbl = map.(role);
    else
        lbl = strrep(strrep(role, 'GRE_', ''), 'EPI_', '');
    end
end

function idxOut = mapPhaseIndex(idxIn, nIn, nOut)
% Map a phase index from one phase count to another while keeping the cycle aligned.
    if nOut <= 1 || nIn <= 1
        idxOut = 1;
        return
    end
    frac = (idxIn - 1) / max(1, nIn - 1);
    idxOut = 1 + round(frac * (nOut - 1));
    idxOut = max(1, min(nOut, idxOut));
end

function holeMask = getMaskHoleMask(mask)
% Return enclosed holes inside a binary ROI mask so exclusions remain visible.
    holeMask = false(size(mask));
    try
        mask = logical(mask);
        if ~any(mask(:)), return; end
        filled = imfill(mask, 'holes');
        holeMask = filled & ~mask;
    catch
    end
end

function h = overlayCheckerMask(ax, mask, alphaScale)
% Overlay a darker, finer checker pattern on low-confidence pixels.
    h = gobjects(0);
    if nargin < 3, alphaScale = 0.38; end
    if isempty(mask) || ~any(mask(:)), return; end
    [nR, nC] = size(mask);
    tileSize = 2;
    [rr, cc] = ndgrid(1:nR, 1:nC);
    tile = mod(floor((rr-1)/tileSize) + floor((cc-1)/tileSize), 2) == 0;
    rgb = 0.08 * ones(nR, nC, 3);
    hold(ax,'on');
    h = image(ax, rgb, 'AlphaData', alphaScale * double(mask) .* double(tile));
    try; h.HitTest='off'; h.PickableParts='none'; catch; end
    hold(ax,'off');
end

function safeMREAxesImage(ax, img, climVals, cmapIn, baseTag)
    if nargin < 5 || isempty(baseTag)
        baseTag = 'MREBaseImage';
    end
    if isempty(ax)
        return
    end
    try
        if ~isvalid(ax)
            return
        end
    catch
        return
    end
    nR = size(img,1);
    nC = size(img,2);

    hBase = [];
    try
        ud = ax.UserData;
    catch
        ud = [];
    end
    try
        if isstruct(ud) && isfield(ud, 'MREBaseHandle') && isfield(ud, 'MREBaseTag') && ...
                strcmp(ud.MREBaseTag, baseTag) && ~isempty(ud.MREBaseHandle) && isvalid(ud.MREBaseHandle)
            hBase = ud.MREBaseHandle;
        end
    catch
        hBase = [];
    end
    if isempty(hBase)
        try
            hMatch = findobj(ax.Children, 'flat', 'Type', 'image', 'Tag', baseTag);
            if ~isempty(hMatch)
                hBase = hMatch(1);
            end
        catch
            hBase = [];
        end
    end

    if isempty(hBase) || ~isvalid(hBase)
        holdState = false;
        try, holdState = ishold(ax); catch, end
        try, hold(ax, 'on'); catch, end
        try
            hBase = image(ax, 'CData', img, 'CDataMapping', 'scaled', 'Tag', baseTag);
        catch
            hBase = image(ax, img, 'CDataMapping', 'scaled', 'Tag', baseTag);
        end
        if ~holdState
            try, hold(ax, 'off'); catch, end
        end
    else
        try, hBase.CData = img; catch, end
        try, hBase.CDataMapping = 'scaled'; catch, end
        try, hBase.Visible = 'on'; catch, end
        try, hBase.Tag = baseTag; catch, end
    end

    try
        hImgs = findobj(ax.Children, 'flat', 'Type', 'image');
    catch
        hImgs = gobjects(0);
    end
    for ii = 1:numel(hImgs)
        hThis = hImgs(ii);
        try
            if isequal(hThis, hBase)
                continue;
            end
        catch
        end
        try
            delete(hThis);
        catch
        end
    end

    try, hBase.XData = [1 nC]; hBase.YData = [1 nR]; catch, end
    try; hBase.AlphaData = 1; catch; end
    try; hBase.Visible = 'on'; catch; end
    try; hBase.Tag = baseTag; catch; end
    try; hBase.HitTest='off'; hBase.PickableParts='none'; catch; end
    try; colormap(ax, cmapIn); catch; end
    try; clim(ax, climVals); catch; try; caxis(ax, climVals); catch; end; end
    try; ax.SortMethod = 'childorder'; catch; end
    try; ax.XLim = [0.5 nC + 0.5]; ax.YLim = [0.5 nR + 0.5]; catch; end
    try; axis(ax, 'image'); catch; end
    try; ax.YDir = 'reverse'; catch; end
    try; uistack(hBase, 'bottom'); catch; end
    try; ax.XTick = []; ax.YTick = []; catch; end
    try
        ud = ax.UserData;
        if ~isstruct(ud), ud = struct(); end
        ud.MREBaseHandle = hBase;
        ud.MREBaseTag = baseTag;
        ax.UserData = ud;
    catch
    end
end

function safeAxesImage(ax, img, climVals, cmapIn)
    if isempty(ax)
        return
    end
    try
        if ~isvalid(ax)
            return
        end
    catch
        return
    end
    try
        cla(ax);
    catch
    end
    try
        h = image(ax, 'CData', img, 'CDataMapping', 'scaled');
    catch
        % Fallback for older syntaxes
        h = image(ax, img, 'CDataMapping', 'scaled');
    end
    try; colormap(ax, cmapIn); catch; end
    try; clim(ax, climVals); catch; try; caxis(ax, climVals); catch; end; end
    try; axis(ax, 'image'); catch; end
    try; ax.YDir = 'reverse'; catch; end
    try; h.HitTest='off'; h.PickableParts='none'; catch; end
    try; ax.XTick = []; ax.YTick = []; catch; end
end

function setupDarkAxes(ax, titleStr)
    ax.XTick=[]; ax.YTick=[]; ax.Box='on';
    ax.Color=[0.06 0.06 0.06];
    ax.XColor=[0.28 0.28 0.28]; ax.YColor=[0.28 0.28 0.28];
    ax.BackgroundColor=[0.06 0.06 0.06];
    % Keep image-display axes passive. Allowing MATLAB to auto-create
    % axes toolbars/interactions on uiaxes can trigger internal GridLayout
    % child-add errors during ROI drawing/finalization and leave the MRE
    % panels looking frozen (black background with only the ROI outline).
    try; ax.Toolbar.Visible = 'off'; catch; end
    try; ax.Interactions = []; catch; end
    try; disableDefaultInteractivity(ax); catch; end
    colormap(ax,'gray');
    title(ax,titleStr,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function showImg(ax, img, titleStr)
    lo=min(img(:)); hi=max(img(:));
    if hi>lo, img=(img-lo)./(hi-lo); end
    safeAxesImage(ax, img, [0 1], 'gray');
    ax.XTick=[]; ax.YTick=[];
    title(ax,titleStr,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function showImgWL(ax, img, titleStr, userLo, userHi)
% Like showImg but respects user-defined window/level (userLo/userHi).
% When userHi <= userLo the window is computed automatically.
    if nargin < 4, userLo = 0; userHi = 0; end
    colormap(ax,'gray');
    hImg = imagesc(ax, img);
    % Allow clicks to pass through the image to the axes ButtonDownFcn
    try; hImg.HitTest = 'off'; hImg.PickableParts = 'none'; catch; end
    if userHi > userLo
        clim(ax, [userLo userHi]);
    else
        [lo, hi] = robustCLim(img, 1, 99, false);
        if hi > lo, clim(ax, [lo hi]); end
    end
    axis(ax,'image');
    ax.XTick=[]; ax.YTick=[];
    title(ax,titleStr,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end


function showNativeGray(ax, img, titleStr, pctLo, pctHi, baseTag)
    if nargin < 4, pctLo = 1; end
    if nargin < 5, pctHi = 99; end
    if nargin < 6, baseTag = 'MREBaseImage'; end
    [lo, hi] = robustCLim(img, pctLo, pctHi, false);
    safeMREAxesImage(ax, img, [lo hi], 'gray', baseTag);
    ax.XTick = []; ax.YTick = [];
    title(ax, sprintf('%s\n[display %.0f to %.0f]', titleStr, lo, hi), ...
        'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function [lo, hi] = showNativeWave(ax, img, titleStr, manualMax, cmapIn, baseTag)
    if nargin < 4, manualMax = 0; end
    if nargin < 5 || isempty(cmapIn), cmapIn = 'gray'; end
    if nargin < 6, baseTag = 'MREBaseImage'; end
    if manualMax > 0
        lo = -manualMax;
        hi = manualMax;
    else
        [lo, hi] = robustCLim(img, 0, 99.5, true);
    end
    safeMREAxesImage(ax, img, [lo hi], cmapIn, baseTag);
    ax.XTick = []; ax.YTick = [];
    title(ax, sprintf('%s\n[display %.0f to %.0f]', titleStr, lo, hi), ...
        'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function setupColorStripAxes(ax)
    ax.Box = 'on';
    ax.Color = [0.06 0.06 0.06];
    ax.BackgroundColor = [0.06 0.06 0.06];
    ax.XColor = [0.72 0.72 0.72];
    ax.YColor = [0.28 0.28 0.28];
    ax.YTick = [];
    ax.FontSize = 9;
    try; ax.Toolbar.Visible = 'off'; catch; end
    try; ax.Interactions = []; catch; end
end

function renderColorStrip(ax, cmapIn, climVals, tickVals)
    if isempty(ax) || ~isvalid(ax)
        return
    end
    lo = climVals(1);
    hi = climVals(2);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        lo = 0; hi = 1;
    end
    x = linspace(lo, hi, 256);
    img = repmat(x, [10 1]);
    try
        cla(ax);
    catch
    end
    try
        h = image(ax, 'XData', [lo hi], 'YData', [0 1], 'CData', img, 'CDataMapping', 'scaled');
    catch
        h = image(ax, img, 'CDataMapping', 'scaled');
    end
    try; colormap(ax, cmapIn); catch; end
    try; clim(ax, [lo hi]); catch; try; caxis(ax, [lo hi]); catch; end; end
    try; axis(ax, 'normal'); catch; end
    try; ax.YDir = 'normal'; catch; end
    try; ax.XLim = [lo hi]; ax.YLim = [0 1]; catch; end
    try; h.HitTest='off'; h.PickableParts='none'; catch; end
    ax.YTick = [];
    if nargin < 4 || isempty(tickVals)
        tickVals = [lo, (lo + hi)/2, hi];
    end
    tickVals = tickVals(isfinite(tickVals));
    tickVals = unique(tickVals);
    ax.XTick = tickVals;
    ax.Box = 'on';
end

function [lo, hi] = robustCLim(img, pctLo, pctHi, symmetric)
    vals = double(img(isfinite(img)));
    if isempty(vals)
        lo = 0; hi = 1; return
    end
    if nargin < 4, symmetric = false; end
    if symmetric
        avals = sort(abs(vals(:)));
        hi = percentileFromSorted(avals, pctHi);
        if ~isfinite(hi) || hi <= 0
            hi = max(abs(vals(:)));
        end
        if ~isfinite(hi) || hi <= 0
            hi = 1;
        end
        lo = -hi;
    else
        svals = sort(vals(:));
        lo = percentileFromSorted(svals, pctLo);
        hi = percentileFromSorted(svals, pctHi);
        if ~isfinite(lo), lo = svals(1); end
        if ~isfinite(hi), hi = svals(end); end
        if hi <= lo
            lo = min(vals(:));
            hi = max(vals(:));
            if hi <= lo, hi = lo + 1; end
        end
    end
end

function v = percentileFromSorted(sortedVals, pct)
    if isempty(sortedVals)
        v = NaN; return
    end
    pct = max(0, min(100, pct));
    idx = 1 + (numel(sortedVals)-1) * pct / 100;
    loIdx = floor(idx);
    hiIdx = ceil(idx);
    frac = idx - loIdx;
    loIdx = max(1, min(numel(sortedVals), loIdx));
    hiIdx = max(1, min(numel(sortedVals), hiIdx));
    if loIdx == hiIdx
        v = sortedVals(loIdx);
    else
        v = (1-frac) * sortedVals(loIdx) + frac * sortedVals(hiIdx);
    end
end

function btn = mkBtn(parent, col, txt, bg, fg, fs)
    btn = uibutton(parent,'push');
    btn.Layout.Column=col; btn.Text=txt;
    btn.FontSize=fs; btn.FontWeight='bold';
    btn.BackgroundColor=bg; btn.FontColor=fg;
end

function btn = roiBtn(parent, row, txt, bg, fg)
    btn = uibutton(parent,'push');
    btn.Layout.Row=row; btn.Text=txt;
    btn.FontSize=12; btn.FontWeight='bold';
    btn.BackgroundColor=bg; btn.FontColor=fg;
end

function clr = dixonROIColor(name)
    if contains(name,'Liver')
        clr = [0.15 0.75 0.15];   % green
    elseif contains(name,'Spleen')
        clr = [0.15 0.55 0.90];   % blue
    elseif contains(name,'Psoas')
        clr = [0.95 0.55 0.15];   % orange — psoas muscle
    elseif contains(name,'Trunk')
        clr = [0.85 0.40 0.05];   % dark orange — trunk muscle
    elseif contains(name,'Muscle')
        clr = [0.95 0.55 0.15];   % orange (legacy generic muscle)
    elseif contains(name,'SAT')
        clr = [0.85 0.20 0.85];   % magenta — subcutaneous adipose tissue
    elseif contains(name,'VAT')
        clr = [0.85 0.80 0.00];   % yellow — visceral adipose tissue
    elseif contains(name,'Fat')
        clr = [0.85 0.20 0.85];   % magenta (legacy)
    else
        clr = [1 1 0];
    end
end

function clr = mreROIColor(name)
    if contains(name,'Liver')
        clr = [0.15 0.85 0.15];
    elseif contains(name,'Spleen')
        clr = [0.15 0.65 0.95];
    elseif contains(name,'Muscle')
        clr = [0.95 0.55 0.15];
    elseif contains(name,'Fat')
        clr = [0.85 0.30 0.85];
    else
        clr = [1 1 0];
    end
end

function pts = mreROIMaskToPolygon(mask)
% Convert a binary mask to a simplified polygon for drawpolygon initialization.
% Returns [N×2] [x y] = [col row] array.
    pts = [1 1];  % fallback
    try
        B = bwboundaries(mask, 'noholes');
        if isempty(B), return; end
        bnd = B{1};   % [row col]
        % Simplify to ~60 vertices using uniform subsampling
        nPts = min(60, size(bnd,1));
        idx  = round(linspace(1, size(bnd,1), nPts));
        bnd  = bnd(idx,:);
        pts  = [bnd(:,2) bnd(:,1)];   % [col row] = [x y]
    catch
    end
end

function cmap = mreWaveCmap()
% Standard MRE wave displacement colormap (awave), embedded from mmdi_roi_gui.
    m = 256;
    aw = [ ...
        'ff';'ff';'00';'ff';'fc';'00';'ff';'fa';'00';'ff';'f7';'00'; ...
        'ff';'f4';'00';'ff';'f2';'00';'ff';'ef';'00';'ff';'ec';'00'; ...
        'ff';'ea';'00';'ff';'e7';'00';'ff';'e4';'00';'ff';'e1';'00'; ...
        'ff';'df';'00';'ff';'dc';'00';'ff';'d9';'00';'ff';'d7';'00'; ...
        'ff';'d4';'00';'ff';'d1';'00';'ff';'cf';'00';'ff';'cc';'00'; ...
        'ff';'c9';'00';'ff';'c7';'00';'ff';'c4';'00';'ff';'c1';'00'; ...
        'ff';'bf';'00';'ff';'bc';'00';'ff';'b9';'00';'ff';'b7';'00'; ...
        'ff';'b4';'00';'ff';'b1';'00';'ff';'ae';'00';'ff';'ac';'00'; ...
        'ff';'a9';'00';'ff';'a6';'00';'ff';'a4';'00';'ff';'a1';'00'; ...
        'ff';'9e';'00';'ff';'9c';'00';'ff';'99';'00';'ff';'96';'00'; ...
        'ff';'94';'00';'ff';'91';'00';'ff';'8e';'00';'ff';'8c';'00'; ...
        'ff';'89';'00';'ff';'86';'00';'ff';'84';'00';'ff';'81';'00'; ...
        'ff';'7e';'00';'ff';'7b';'00';'ff';'79';'00';'ff';'76';'00'; ...
        'ff';'73';'00';'ff';'71';'00';'ff';'6e';'00';'ff';'6b';'00'; ...
        'ff';'69';'00';'ff';'66';'00';'ff';'63';'00';'ff';'61';'00'; ...
        'ff';'5e';'00';'ff';'5b';'00';'ff';'59';'00';'ff';'56';'00'; ...
        'ff';'53';'00';'ff';'51';'00';'ff';'4e';'00';'ff';'4b';'00'; ...
        'ff';'48';'00';'ff';'46';'00';'ff';'43';'00';'ff';'40';'00'; ...
        'ff';'3e';'00';'ff';'3b';'00';'ff';'38';'00';'ff';'36';'00'; ...
        'ff';'33';'00';'ff';'30';'00';'ff';'2e';'00';'ff';'2b';'00'; ...
        'ff';'28';'00';'ff';'26';'00';'ff';'23';'00';'ff';'20';'00'; ...
        'ff';'1e';'00';'ff';'1b';'00';'ff';'18';'00';'ff';'15';'00'; ...
        'ff';'13';'00';'ff';'10';'00';'ff';'0d';'00';'ff';'0b';'00'; ...
        'ff';'08';'00';'ff';'05';'00';'ff';'03';'00';'ff';'00';'00'; ...
        'f7';'00';'00';'ef';'00';'00';'e7';'00';'00';'df';'00';'00'; ...
        'd7';'00';'00';'cf';'00';'00';'c7';'00';'00';'bf';'00';'00'; ...
        'b7';'00';'00';'af';'00';'00';'a7';'00';'00';'9f';'00';'00'; ...
        '97';'00';'00';'8f';'00';'00';'87';'00';'00';'80';'00';'00'; ...
        '78';'00';'00';'70';'00';'00';'68';'00';'00';'60';'00';'00'; ...
        '58';'00';'00';'50';'00';'00';'48';'00';'00';'40';'00';'00'; ...
        '38';'00';'00';'30';'00';'00';'28';'00';'00';'20';'00';'00'; ...
        '18';'00';'00';'10';'00';'00';'08';'00';'00';'00';'00';'00'; ...
        '00';'00';'00';'00';'00';'08';'00';'00';'10';'00';'00';'18'; ...
        '00';'00';'20';'00';'00';'28';'00';'00';'30';'00';'00';'38'; ...
        '00';'00';'40';'00';'00';'48';'00';'00';'50';'00';'00';'58'; ...
        '00';'00';'60';'00';'00';'68';'00';'00';'70';'00';'00';'78'; ...
        '00';'00';'80';'00';'00';'87';'00';'00';'8f';'00';'00';'97'; ...
        '00';'00';'9f';'00';'00';'a7';'00';'00';'af';'00';'00';'b7'; ...
        '00';'00';'bf';'00';'00';'c7';'00';'00';'cf';'00';'00';'d7'; ...
        '00';'00';'df';'00';'00';'e7';'00';'00';'ef';'00';'00';'f7'; ...
        '00';'00';'ff';'00';'03';'ff';'00';'05';'ff';'00';'08';'ff'; ...
        '00';'0b';'ff';'00';'0d';'ff';'00';'10';'ff';'00';'13';'ff'; ...
        '00';'15';'ff';'00';'18';'ff';'00';'1b';'ff';'00';'1e';'ff'; ...
        '00';'20';'ff';'00';'23';'ff';'00';'26';'ff';'00';'28';'ff'; ...
        '00';'2b';'ff';'00';'2e';'ff';'00';'30';'ff';'00';'33';'ff'; ...
        '00';'36';'ff';'00';'38';'ff';'00';'3b';'ff';'00';'3e';'ff'; ...
        '00';'40';'ff';'00';'43';'ff';'00';'46';'ff';'00';'48';'ff'; ...
        '00';'4b';'ff';'00';'4e';'ff';'00';'51';'ff';'00';'53';'ff'; ...
        '00';'56';'ff';'00';'59';'ff';'00';'5b';'ff';'00';'5e';'ff'; ...
        '00';'61';'ff';'00';'63';'ff';'00';'66';'ff';'00';'69';'ff'; ...
        '00';'6b';'ff';'00';'6e';'ff';'00';'71';'ff';'00';'73';'ff'; ...
        '00';'76';'ff';'00';'79';'ff';'00';'7b';'ff';'00';'7e';'ff'; ...
        '00';'81';'ff';'00';'84';'ff';'00';'86';'ff';'00';'89';'ff'; ...
        '00';'8c';'ff';'00';'8e';'ff';'00';'91';'ff';'00';'94';'ff'; ...
        '00';'96';'ff';'00';'99';'ff';'00';'9c';'ff';'00';'9e';'ff'; ...
        '00';'a1';'ff';'00';'a4';'ff';'00';'a6';'ff';'00';'a9';'ff'; ...
        '00';'ac';'ff';'00';'ae';'ff';'00';'b1';'ff';'00';'b4';'ff'; ...
        '00';'b7';'ff';'00';'b9';'ff';'00';'bc';'ff';'00';'bf';'ff'; ...
        '00';'c1';'ff';'00';'c4';'ff';'00';'c7';'ff';'00';'c9';'ff'; ...
        '00';'cc';'ff';'00';'cf';'ff';'00';'d1';'ff';'00';'d4';'ff'; ...
        '00';'d7';'ff';'00';'d9';'ff';'00';'dc';'ff';'00';'df';'ff'; ...
        '00';'e1';'ff';'00';'e4';'ff';'00';'e7';'ff';'00';'ea';'ff'; ...
        '00';'ec';'ff';'00';'ef';'ff';'00';'f2';'ff';'00';'f4';'ff'; ...
        '00';'f7';'ff';'00';'fa';'ff';'00';'fc';'ff';'00';'ff';'ff'];
    aw = hex2dec(aw);
    naw = reshape(aw, 3, 256) ./ 255;
    cmap = [naw(1,:)', naw(2,:)', naw(3,:)'];
    cmap = flip(cmap, 1);
    idx = round(linspace(1, 256, m));
    cmap = cmap(idx, :);
end

function cmap = mreStiffCmap()
% Standard MRE stiffness colormap (aaasmo/LFE LUT), embedded from mmdi_roi_gui.
    m = 256;
    aw = [ ...
        '00';'00';'00';'22';'00';'55';'24';'00';'55';'26';'00';'56'; ...
        '28';'00';'56';'29';'00';'57';'2b';'00';'57';'2d';'00';'58'; ...
        '2f';'00';'58';'31';'00';'59';'33';'00';'59';'34';'00';'5a'; ...
        '36';'00';'5a';'38';'00';'5b';'3a';'00';'5b';'3c';'00';'5b'; ...
        '3e';'00';'5c';'3f';'00';'5c';'41';'00';'5d';'43';'00';'5d'; ...
        '45';'00';'5e';'47';'00';'5e';'49';'00';'5f';'4a';'00';'5f'; ...
        '4c';'00';'60';'4e';'00';'60';'50';'00';'60';'52';'00';'61'; ...
        '54';'00';'61';'55';'00';'62';'57';'00';'62';'59';'00';'63'; ...
        '5b';'00';'63';'5d';'00';'64';'5f';'00';'64';'60';'00';'65'; ...
        '62';'00';'65';'64';'00';'66';'66';'00';'66';'66';'00';'6a'; ...
        '66';'00';'6f';'66';'00';'73';'66';'00';'77';'66';'00';'7b'; ...
        '66';'00';'80';'66';'00';'84';'66';'00';'88';'66';'00';'8c'; ...
        '66';'00';'91';'66';'00';'95';'66';'00';'99';'5e';'00';'9c'; ...
        '56';'00';'9e';'4e';'00';'a1';'47';'00';'a3';'3f';'00';'a6'; ...
        '37';'00';'a9';'2f';'00';'ab';'27';'00';'ae';'1f';'00';'b1'; ...
        '18';'00';'b3';'10';'00';'b6';'08';'00';'b8';'00';'00';'bb'; ...
        '00';'06';'c1';'00';'0b';'c6';'00';'11';'cc';'00';'17';'d2'; ...
        '00';'1c';'d7';'00';'22';'dd';'00';'28';'e3';'00';'2d';'e8'; ...
        '00';'33';'ee';'00';'39';'f4';'00';'3e';'f9';'00';'44';'ff'; ...
        '00';'48';'fb';'00';'4d';'f7';'00';'51';'f2';'00';'55';'ee'; ...
        '00';'59';'ea';'00';'5e';'e6';'00';'62';'e1';'00';'66';'dd'; ...
        '00';'6a';'d9';'00';'6f';'d5';'00';'73';'d0';'00';'77';'cc'; ...
        '00';'7b';'c8';'00';'7e';'c5';'00';'82';'c1';'00';'86';'bd'; ...
        '00';'89';'ba';'00';'8d';'b6';'00';'91';'b3';'00';'94';'af'; ...
        '00';'98';'ab';'00';'9b';'a8';'00';'9f';'a4';'00';'a3';'a0'; ...
        '00';'a6';'9d';'00';'aa';'99';'00';'aa';'8c';'00';'aa';'80'; ...
        '00';'aa';'73';'00';'aa';'66';'00';'aa';'59';'00';'aa';'4d'; ...
        '00';'aa';'40';'00';'aa';'33';'00';'aa';'26';'00';'aa';'1a'; ...
        '00';'aa';'0d';'00';'aa';'00';'00';'ae';'00';'00';'b3';'00'; ...
        '00';'b7';'00';'00';'bb';'00';'00';'bf';'00';'00';'c4';'00'; ...
        '00';'c8';'00';'00';'cc';'00';'00';'d0';'00';'00';'d5';'00'; ...
        '00';'d9';'00';'00';'dd';'00';'0a';'e0';'00';'15';'e2';'00'; ...
        '1f';'e5';'00';'2a';'e7';'00';'34';'ea';'00';'3f';'ed';'00'; ...
        '49';'ef';'00';'54';'f2';'00';'5e';'f5';'00';'69';'f7';'00'; ...
        '73';'fa';'00';'7e';'fc';'00';'88';'ff';'00';'8d';'ff';'00'; ...
        '92';'ff';'00';'98';'ff';'00';'9d';'ff';'00';'a2';'ff';'00'; ...
        'a7';'ff';'00';'ad';'ff';'00';'b2';'ff';'00';'b7';'ff';'00'; ...
        'bc';'ff';'00';'c2';'ff';'00';'c7';'ff';'00';'cc';'ff';'00'; ...
        'd0';'ff';'00';'d5';'ff';'00';'d9';'ff';'00';'dd';'ff';'00'; ...
        'e1';'ff';'00';'e6';'ff';'00';'ea';'ff';'00';'ee';'ff';'00'; ...
        'f2';'ff';'00';'f7';'ff';'00';'fb';'ff';'00';'ff';'ff';'00'; ...
        'ff';'fd';'00';'ff';'fb';'00';'ff';'f9';'00';'ff';'f7';'00'; ...
        'ff';'f5';'00';'ff';'f3';'00';'ff';'f1';'00';'ff';'ef';'00'; ...
        'ff';'ed';'00';'ff';'eb';'00';'ff';'e9';'00';'ff';'e7';'00'; ...
        'ff';'e4';'00';'ff';'e2';'00';'ff';'e0';'00';'ff';'de';'00'; ...
        'ff';'dc';'00';'ff';'da';'00';'ff';'d8';'00';'ff';'d6';'00'; ...
        'ff';'d4';'00';'ff';'d2';'00';'ff';'d0';'00';'ff';'ce';'00'; ...
        'ff';'cc';'00';'ff';'c9';'00';'ff';'c7';'00';'ff';'c4';'00'; ...
        'ff';'c2';'00';'ff';'bf';'00';'ff';'bc';'00';'ff';'ba';'00'; ...
        'ff';'b7';'00';'ff';'b4';'00';'ff';'b2';'00';'ff';'af';'00'; ...
        'ff';'ad';'00';'ff';'aa';'00';'ff';'a7';'00';'ff';'a4';'00'; ...
        'ff';'a2';'00';'ff';'9f';'00';'ff';'9c';'00';'ff';'99';'00'; ...
        'ff';'96';'00';'ff';'93';'00';'ff';'91';'00';'ff';'8e';'00'; ...
        'ff';'8b';'00';'ff';'88';'00';'fe';'80';'00';'fc';'78';'00'; ...
        'fb';'70';'00';'fa';'69';'00';'f8';'61';'00';'f7';'59';'00'; ...
        'f6';'51';'00';'f5';'49';'00';'f3';'41';'00';'f2';'3a';'00'; ...
        'f1';'32';'00';'ef';'2a';'00';'ee';'22';'00';'ef';'1f';'00'; ...
        'f1';'1c';'00';'f2';'1a';'00';'f4';'17';'00';'f5';'14';'00'; ...
        'f7';'11';'00';'f8';'0e';'00';'f9';'0b';'00';'fb';'09';'00'; ...
        'fc';'06';'00';'fe';'03';'00';'ff';'00';'00';'ff';'00';'00'; ...
        'ff';'00';'00';'ff';'00';'00';'ff';'00';'00';'ff';'00';'00'; ...
        'ff';'00';'00';'ff';'00';'00';'ff';'00';'00';'ff';'00';'00'; ...
        'ff';'00';'00';'ff';'00';'00';'ff';'00';'00';'ff';'00';'00'; ...
        'ff';'00';'00';'ff';'00';'00';'ff';'00';'00';'ff';'00';'00'];
    aw = hex2dec(aw);
    naw = reshape(aw, 3, 256) ./ 255;
    cmap = [naw(1,:)', naw(2,:)', naw(3,:)'];
    idx = round(linspace(1, 256, m));
    cmap = cmap(idx, :);
end

function [x,y] = ginputAxes(ax)
    % Single-point click capture within a uiaxes
    x=NaN; y=NaN;
    try
        ax.ButtonDownFcn = @(~,e) assignin('base','_ginput_pt_',[e.IntersectionPoint(1) e.IntersectionPoint(2)]);
        uiwait(ancestor(ax,'figure'), 5);   % 5 sec timeout
        pt = evalin('base','_ginput_pt_');
        x=pt(1); y=pt(2);
        evalin('base','clear _ginput_pt_');
    catch
    end
    ax.ButtonDownFcn = '';
end


function mask = circleMaskFromGeom(cx, cy, r, nRow, nCol)
    [X, Y] = meshgrid(1:nCol, 1:nRow);
    mask = ((X - cx).^2 + (Y - cy).^2) <= (r.^2);
end

function slices = removeSlice(slices, sl)
    key = sprintf('sl%d',sl);
    if isfield(slices,key)
        slices = rmfield(slices,key);
    end
end

function sliceZ = buildDixonSliceZ(dix)
% Build a full Z-coordinate vector (one entry per slice) for the Dixon volume.
%
% Tries five methods in order, accepting a result only when it has nZ distinct
% values (guards against the GE IDEAL-IQ SliceLocation-all-same quirk, where
% earlier methods can return a degenerate constant array that maps every
% landmark to sl1).
%
%   1. dix.SliceLocations — complete AND non-degenerate
%   2. SpatialInfo.AffineMatrix — voxel→world transform
%   3. SpatialInfo linear: ImagePositionFirst + SliceNormal*SliceSpacing
%   3b. Direct: ImagePositionFirst(z) + SliceSpacing*(0:nZ-1)*dirSign
%       (implements the user-requested "use SliceThickness from DICOM" approach)
%   4. SliceLocations[1] or ImagePositionFirst(z) + SliceThickness_mm*(0:nZ-1)
%
% Returns [] if none of the methods can produce a valid vector.
    sliceZ = [];
    if isempty(dix), return; end

    nZ = 0;
    try, nZ = double(dix.nSlices); catch, end
    if nZ < 1, return; end

    % Helper: accept only if nZ entries with >1 distinct value
    isGood = @(z) numel(z) == nZ && numel(unique(round(double(z(:)), 1))) > 1;

    % --- Method 1: SliceLocations if complete AND non-degenerate ---
    try
        locs = double(dix.SliceLocations(:));
        if isGood(locs)
            sliceZ = locs;
            return;
        end
    catch, end

    % --- Method 2: AffineMatrix (needs NumSlices, Rows, Columns in sinfo) ---
    try
        sinfo = dix.SpatialInfo;
        if ~isfield(sinfo,'NumSlices') || isempty(sinfo.NumSlices)
            sinfo.NumSlices = nZ;
        end
        if ~isfield(sinfo,'Rows')    || isempty(sinfo.Rows),    sinfo.Rows    = size(dix.Water,1); end
        if ~isfield(sinfo,'Columns') || isempty(sinfo.Columns), sinfo.Columns = size(dix.Water,2); end
        if isfield(sinfo,'AffineMatrix') && ~isempty(sinfo.AffineMatrix)
            z2 = buildSliceZFromSinfo(sinfo);
            if isGood(z2)
                sliceZ = z2;
                return;
            end
        end
    catch, end

    % --- Method 3: ImagePositionFirst + SliceNormal*SliceSpacing ---
    try
        sinfo = dix.SpatialInfo;
        if isfield(sinfo,'ImagePositionFirst') && ~isempty(sinfo.ImagePositionFirst) && ...
           isfield(sinfo,'SliceNormal')        && ~isempty(sinfo.SliceNormal) && ...
           isfield(sinfo,'SliceSpacing')       && sinfo.SliceSpacing > 0
            pos1   = double(sinfo.ImagePositionFirst(:));
            normal = double(sinfo.SliceNormal(:));
            ds     = double(sinfo.SliceSpacing);
            if norm(normal) > 0
                normal = normal / norm(normal);
                z3 = pos1(3) + (0:nZ-1)' * ds * normal(3);
                if abs(normal(3)) < 0.1 && abs(normal(2)) > 0.5
                    z3 = pos1(2) + (0:nZ-1)' * ds * normal(2);
                end
                if isGood(z3), sliceZ = z3; return; end
            end
        end
    catch, end

    % --- Method 3b: ImagePositionFirst(z) + SliceSpacing*(0:nZ-1) ---
    % Directly implements "use DICOM SliceThickness/SpacingBetweenSlices to
    % reconstruct slice positions" regardless of SliceNormal z-component.
    % Always +1 direction: ImagePositionFirst is the inferior-most slice
    % (IPP-priority reference in readMultiContrast), volume sorted ascending.
    try
        sinfo = dix.SpatialInfo;
        if isfield(sinfo,'ImagePositionFirst') && ~isempty(sinfo.ImagePositionFirst) && ...
           isfield(sinfo,'SliceSpacing')       && sinfo.SliceSpacing > 0
            z0 = double(sinfo.ImagePositionFirst(3));
            ds = double(sinfo.SliceSpacing);
            z3b = z0 + (0:nZ-1)' * ds;
            if isGood(z3b), sliceZ = z3b; return; end
        end
    catch, end

    % --- Method 4: any known z0 + SliceThickness_mm extrapolation ---
    try
        ds = 0;
        if isfield(dix,'SliceThickness_mm') && dix.SliceThickness_mm > 0
            ds = double(dix.SliceThickness_mm);
        end
        if ds <= 0
            try, ds = double(dix.SpatialInfo.SliceSpacing); catch, end
        end
        if ds <= 0, ds = 10; end   % anatomically reasonable default

        z0 = NaN;
        try
            locs = double(dix.SliceLocations(:));
            if ~isempty(locs), z0 = locs(1); end
        catch, end
        if isnan(z0)
            try, z0 = double(dix.SpatialInfo.ImagePositionFirst(3)); catch, end
        end
        if isnan(z0), return; end

        sliceZ = z0 + (0:nZ-1)' * ds;
    catch, end
end


function sliceZ = buildSliceZFromSinfo(sinfo)
% Build a column vector of patient Z coordinates (mm) for each slice,
% using the affine matrix stored in sinfo.
    sliceZ = [];
    if isempty(sinfo) || ~isfield(sinfo,'AffineMatrix'), return; end
    try
        A  = sinfo.AffineMatrix;
        nZ = sinfo.NumSlices;
        if nZ < 1, return; end
        cC = sinfo.Columns / 2 - 0.5;
        cR = sinfo.Rows    / 2 - 0.5;
        sliceZ = zeros(nZ, 1);
        for sl = 1:nZ
            p = A * [cC; cR; sl-1; 1];
            sliceZ(sl) = p(3);
        end
    catch
        sliceZ = [];
    end
end

function [sliceIdx, dist_mm] = propagateLandmarkMm(z_mm, sinfo)
% Map a disc landmark Z-position (patient mm) to the nearest slice in sinfo.
% Uses the affine matrix to build slice centre Z-coordinates, then finds the
% closest slice.  Returns sliceIdx (1-based integer) and dist_mm.
    sliceIdx = NaN; dist_mm = NaN;
    if isnan(z_mm) || isempty(sinfo) || ~isfield(sinfo,'AffineMatrix'), return; end
    try
        A  = sinfo.AffineMatrix;
        nZ = sinfo.NumSlices;
        if nZ < 1, return; end
        cCol = sinfo.Columns / 2 - 0.5;
        cRow = sinfo.Rows    / 2 - 0.5;
        sliceZ = zeros(nZ, 1);
        for sl = 1:nZ
            pos4 = A * [cCol; cRow; sl-1; 1];
            sliceZ(sl) = pos4(3);    % patient Z of this slice centre
        end
        dists = abs(sliceZ - z_mm);
        [dist_mm, sliceIdx] = min(dists);
    catch
    end
end

function lbl = locLandmarkLabel(lmName)
% Return the human-readable label for a landmark name string.
    switch lmName
        case 'T9T10',  lbl = 'T9/10';
        case 'T10T11', lbl = 'T10/11';
        case 'T11T12', lbl = 'T11/12';
        case 'T12L1',  lbl = 'T12/L1';
        case 'L1L2',   lbl = 'L1/2';
        case 'L2L3',   lbl = 'L2/3';
        case 'L3L4',   lbl = 'L3/4';
        otherwise,     lbl = lmName;
    end
end

function mask = optimizeContourBand(polyPts, imgData, nR, nC)
% Refine a confirmed polygon contour within a narrow boundary band.
%
% Algorithm:
%   1. Build initial binary mask from polygon vertices.
%   2. Create a 2-px dilation/erosion band around the boundary.
%   3. Compute inner-core (eroded) mean and SD.
%   4. Score each band pixel using four cues:
%        a) edge strength  (gradient magnitude, normalised)
%        b) distance from the original contour (closer = less confident)
%        c) deviation from core mean (normalised z-score)
%        d) local variance  (3×3 stdfilt, normalised)
%   5. Include band pixels whose combined score exceeds a threshold.
%   6. Smooth the resulting contour boundary with a circular moving average.
%
% Returns a logical mask of size nR×nC.

    BAND_PX   = 2;      % half-band width in pixels
    INCL_THR  = 0.42;   % inclusion threshold (0–1, lower → more inclusive)
    SMOOTH_W  = 9;      % smoothing window for boundary points

    % ── Initial mask ─────────────────────────────────────────────────────
    x0 = min(max(polyPts(:,1), 1), nC);
    y0 = min(max(polyPts(:,2), 1), nR);
    initMask = logical(poly2mask(x0, y0, nR, nC));

    if ~any(initMask(:)) || isempty(imgData)
        mask = initMask; return;
    end

    img = double(imgData);

    % ── Boundary band ─────────────────────────────────────────────────────
    se       = strel('disk', BAND_PX);
    dilated  = imdilate(initMask, se);
    eroded   = imerode(initMask, se);
    bandMask = dilated & ~eroded;   % ring around the boundary
    coreMask = eroded;              % strictly inner core

    if ~any(coreMask(:))
        % Contour too small to erode — return the original polygon mask
        mask = initMask; return;
    end

    % ── Inner-core statistics ─────────────────────────────────────────────
    coreVals = img(coreMask);
    coreMean = mean(coreVals);
    coreSD   = std(coreVals);
    if coreSD < eps, coreSD = max(1, abs(coreMean) * 0.05 + 1); end

    % ── Cue a: edge strength (gradient magnitude, normalised 0–1) ────────
    [Gx, Gy]  = gradient(img);
    edgeStr   = sqrt(Gx.^2 + Gy.^2);
    edgeMax   = max(edgeStr(:));
    if edgeMax > eps, edgeStr = edgeStr / edgeMax; end

    % ── Cue b: distance from original contour boundary (normalised 0–1) ──
    % Build a 1-px-thick boundary mask and compute distance transform
    bndEdge   = initMask & ~imerode(initMask, strel('disk',1));
    distFromBnd = bwdist(bndEdge);                        % distance in pixels
    distNorm    = min(distFromBnd / BAND_PX, 1);          % 0 at boundary, 1 at band edge

    % ── Cue c: deviation from core mean (z-score, clamped to [0,1]) ──────
    devScore = min(abs(img - coreMean) / coreSD, 4) / 4;  % 0=similar, 1=very different

    % ── Cue d: local variance (3×3 neighbourhood, normalised) ────────────
    localSD      = stdfilt(img, ones(3,3));
    localVarNorm = min(localSD / (coreSD + eps), 3) / 3;  % 0=uniform, 1=highly variable

    % ── Combined inclusion score ──────────────────────────────────────────
    % A band pixel is IN if it resembles the core, has low local variance,
    % and does not sit on a strong edge.
    %   – (1 - devScore)     high when pixel is close to core mean
    %   – (1 - edgeStr*0.4)  penalise pixels on strong edges slightly
    %   – (1 - localVarNorm*0.3) penalise highly variable regions
    %   – distNorm has minor contribution (pixels closer to boundary
    %     are harder to classify, so we apply a small penalty)
    inclScore = (1 - devScore) .* (1 - 0.4*edgeStr) .* (1 - 0.3*localVarNorm) ...
                .* (1 - 0.1*distNorm);

    % Apply threshold only within the boundary band
    bandIn  = bandMask & (inclScore > INCL_THR);
    newMask = coreMask | bandIn;
    newMask = imfill(newMask, 'holes');

    if ~any(newMask(:)), mask = initMask; return; end

    % ── Smooth boundary ───────────────────────────────────────────────────
    bndList = bwboundaries(newMask);
    if isempty(bndList), mask = initMask; return; end

    % Take the largest connected boundary
    [~, maxIdx] = max(cellfun(@(b) size(b,1), bndList));
    bRow = bndList{maxIdx}(:,1);
    bCol = bndList{maxIdx}(:,2);

    % Circular padding to avoid end-effects in movmean
    n = numel(bRow);
    W = min(SMOOTH_W, floor(n/4));   % guard for very small contours
    if W >= 2
        padRow = [bRow(end-W+1:end); bRow; bRow(1:W)];
        padCol = [bCol(end-W+1:end); bCol; bCol(1:W)];
        sRow   = movmean(padRow, W);
        sCol   = movmean(padCol, W);
        sRow   = sRow(W+1:end-W);
        sCol   = sCol(W+1:end-W);
        % Clamp to image bounds
        sRow = min(max(sRow, 1), nR);
        sCol = min(max(sCol, 1), nC);
        mask = logical(poly2mask(sCol, sRow, nR, nC));
        mask = imfill(mask, 'holes');
        if ~any(mask(:)), mask = newMask; end
    else
        mask = newMask;
    end
end

function note = resultsDiscNote(sl, lmStruct, lmNames, lmShort, proxMm, sliceZ)
% Build a Notes string flagging when slice sl is within proxMm of a disc marker.
    note = '';
    if isempty(sliceZ) || sl < 1 || sl > numel(sliceZ), return; end
    slZ = sliceZ(sl);
    parts = {};
    for ki = 1:numel(lmNames)
        n = lmNames{ki};
        if ~isfield(lmStruct, n), continue; end
        lmSl  = lmStruct.(n).SliceIdx;
        lmDst = lmStruct.(n).Dist_mm;
        if isnan(lmSl) || isnan(lmDst), continue; end
        % Distance from this slice's Z to the landmark's slice Z
        if lmSl >= 1 && lmSl <= numel(sliceZ)
            d = abs(slZ - sliceZ(lmSl));
        else
            d = abs(sl - lmSl) * (sliceZ(2) - sliceZ(1));
        end
        if d <= proxMm
            parts{end+1} = sprintf('%s (%.1fmm)', lmShort{ki}, d); %#ok<AGROW>
        end
    end
    if ~isempty(parts)
        note = ['Near: ' strjoin(parts, ', ')];
    end
end

function feat = computeFirstOrderRadiomics(vals, voxVol)
% Compute first-order radiomics features from a vector of ROI voxel values.
    vals = vals(isfinite(vals));
    feat.n      = numel(vals);
    feat.vol    = feat.n * voxVol;
    if isempty(vals)
        feat.mean=NaN; feat.median=NaN; feat.std=NaN;
        feat.skew=NaN; feat.kurt=NaN; feat.energy=NaN; feat.entropy=NaN;
        feat.mn=NaN;   feat.mx=NaN;   feat.range=NaN;  feat.iqr=NaN;
        feat.p10=NaN;  feat.p25=NaN;  feat.p75=NaN;    feat.p90=NaN;
        return
    end
    feat.mean   = mean(vals);
    feat.median = median(vals);
    feat.std    = std(vals);
    feat.mn     = min(vals);
    feat.mx     = max(vals);
    feat.range  = feat.mx - feat.mn;
    feat.iqr    = iqr(vals);
    feat.p10    = prctile(vals, 10);
    feat.p25    = prctile(vals, 25);
    feat.p75    = prctile(vals, 75);
    feat.p90    = prctile(vals, 90);
    % Skewness and kurtosis
    try, feat.skew = skewness(vals); catch, feat.skew = NaN; end
    try, feat.kurt = kurtosis(vals); catch, feat.kurt = NaN; end
    % Energy (sum of squares, normalised by n)
    feat.energy = sum(vals.^2) / max(feat.n, 1);
    % Entropy (histogram-based, 64 bins)
    try
        edges = linspace(feat.mn - eps, feat.mx + eps, 65);
        counts = histcounts(vals, edges);
        p = counts / sum(counts);
        p = p(p > 0);
        feat.entropy = -sum(p .* log2(p));
    catch
        feat.entropy = NaN;
    end
end

% =========================================================================
%  RADIOMICS HELPERS
% =========================================================================

function hdr = radiomicsCSVHeader()
% Return the 67-column CSV header for full radiomics export.
hdr = ['OrganROI,SliceIndex,SliceLocation_mm,' ...
    'VoxelCount,Volume_mm3,' ...
    'Mean,Median,Mode,Variance,StdDev,Skewness,Kurtosis,' ...
    'Energy,Entropy,Uniformity,RMS,MAD,Min,Max,Range,IQR,' ...
    'P10,P25,P75,P90,' ...
    'Area_mm2,Perimeter_mm,Sphericity,Compactness,Eccentricity,' ...
    'MajorAxis_mm,MinorAxis_mm,Elongation,Solidity,MaxDiameter_mm,' ...
    'GLCM_Contrast,GLCM_Correlation,GLCM_Energy,GLCM_Homogeneity,' ...
    'GLCM_Entropy,GLCM_Dissimilarity,GLCM_Autocorrelation,' ...
    'GLCM_ClusterShade,GLCM_ClusterProminence,GLCM_MaxProbability,' ...
    'GLRLM_SRE,GLRLM_LRE,GLRLM_GLNU,GLRLM_RLNU,GLRLM_RunPct,' ...
    'GLRLM_LGLRE,GLRLM_HGLRE,GLRLM_SRLGLE,GLRLM_SRHGLE,' ...
    'GLRLM_LRLGLE,GLRLM_LRHGLE,' ...
    'GLSZM_SAE,GLSZM_LAE,GLSZM_GLNU,GLSZM_SZNU,GLSZM_ZonePct,' ...
    'GLSZM_LGLZE,GLSZM_HGLZE,GLSZM_SALGLE,GLSZM_SAHGLE,' ...
    'GLSZM_LALGLE,GLSZM_LAHGLE'];
end

function row = buildRadiomicsRow(organ, sl, slZ, vals, mask, img2d, dx, dy, dz)
% Assemble one CSV data row with all radiomics categories.
    nLevels = 32;
    voxVol  = dx * dy * dz;
    I  = computeIntensityFeatures(vals, voxVol);
    Sh = computeShapeFeatures(mask, dx, dy);
    GL = computeGLCMFeatures(img2d, mask, nLevels);
    RL = computeGLRLMFeatures(img2d, mask, nLevels);
    SZ = computeGLSZMFeatures(img2d, mask, nLevels);
    f = @(x) num2fmtstr(x);
    row = sprintf('%s,%d,%s,%s', organ, sl, f(slZ), ...
        strjoin({ ...
            f(I.n),      f(I.vol), ...
            f(I.mean),   f(I.median), f(I.mode),  f(I.variance), f(I.std), ...
            f(I.skew),   f(I.kurt), ...
            f(I.energy), f(I.entropy), f(I.uniformity), f(I.rms), f(I.mad), ...
            f(I.mn),     f(I.mx),  f(I.range), f(I.iqr), ...
            f(I.p10),    f(I.p25), f(I.p75),   f(I.p90), ...
            f(Sh.area_mm2),      f(Sh.perimeter_mm),  f(Sh.sphericity), ...
            f(Sh.compactness),   f(Sh.eccentricity),  f(Sh.major_axis_mm), ...
            f(Sh.minor_axis_mm), f(Sh.elongation),    f(Sh.solidity), ...
            f(Sh.max_diameter_mm), ...
            f(GL.contrast),      f(GL.correlation),   f(GL.energy), ...
            f(GL.homogeneity),   f(GL.entropy),       f(GL.dissimilarity), ...
            f(GL.autocorrelation), f(GL.cluster_shade), f(GL.cluster_prominence), ...
            f(GL.max_prob), ...
            f(RL.sre),    f(RL.lre),    f(RL.glnu),   f(RL.rlnu), f(RL.run_pct), ...
            f(RL.lglre),  f(RL.hglre), ...
            f(RL.srlgle), f(RL.srhgle), f(RL.lrlgle), f(RL.lrhgle), ...
            f(SZ.sae),    f(SZ.lae),    f(SZ.glnu),   f(SZ.sznu), f(SZ.zone_pct), ...
            f(SZ.lglze),  f(SZ.hglze), ...
            f(SZ.salgle), f(SZ.sahgle), f(SZ.lalgle), f(SZ.lahgle) ...
        }, ','));
end

function s = num2fmtstr(x)
    if isnan(x) || isinf(x), s = 'NaN'; else, s = sprintf('%.6g', x); end
end

% ── Intensity features ────────────────────────────────────────────────────
function feat = computeIntensityFeatures(vals, voxVol)
% 22 first-order (intensity) radiomic features.
    vals = vals(isfinite(vals));
    feat.n = numel(vals);
    feat.vol = feat.n * voxVol;
    nanFields = {'mean','median','mode','variance','std','skew','kurt', ...
                 'energy','entropy','uniformity','rms','mad', ...
                 'mn','mx','range','iqr','p10','p25','p75','p90'};
    if isempty(vals)
        for f = nanFields, feat.(f{1}) = NaN; end
        return
    end
    feat.mean     = mean(vals);
    feat.median   = median(vals);
    feat.mn       = min(vals);
    feat.mx       = max(vals);
    feat.range    = feat.mx - feat.mn;
    feat.variance = var(vals);
    feat.std      = sqrt(feat.variance);
    feat.iqr      = iqr(vals);
    feat.p10      = prctile(vals, 10);
    feat.p25      = prctile(vals, 25);
    feat.p75      = prctile(vals, 75);
    feat.p90      = prctile(vals, 90);
    feat.rms      = sqrt(mean(vals.^2));
    feat.mad      = mean(abs(vals - feat.mean));
    try, feat.skew = skewness(vals); catch, feat.skew = NaN; end
    try, feat.kurt = kurtosis(vals); catch, feat.kurt = NaN; end
    feat.energy   = sum(vals.^2) / max(feat.n, 1);
    try
        edges = linspace(feat.mn - eps, feat.mx + eps, 65);
        counts = histcounts(vals, edges);
        p = counts / max(sum(counts), 1);
        pp = p(p > 0);
        feat.entropy    = -sum(pp .* log2(pp));
        feat.uniformity = sum(p .^ 2);
    catch
        feat.entropy    = NaN;
        feat.uniformity = NaN;
    end
    try
        edges2 = linspace(feat.mn - eps, feat.mx + eps, 65);
        [cnt2, ~] = histcounts(vals, edges2);
        [~, peakBin] = max(cnt2);
        feat.mode = (edges2(peakBin) + edges2(peakBin+1)) / 2;
    catch
        feat.mode = NaN;
    end
end

% ── Shape features ────────────────────────────────────────────────────────
function feat = computeShapeFeatures(mask, dx, dy)
% 10 shape-based radiomic features from a 2-D binary mask.
    fields = {'area_mm2','perimeter_mm','sphericity','compactness', ...
              'eccentricity','major_axis_mm','minor_axis_mm','elongation', ...
              'solidity','max_diameter_mm'};
    for f = fields, feat.(f{1}) = NaN; end
    if ~any(mask(:)), return; end
    try
        mask = logical(mask);
        rp = regionprops(mask, 'Area','Perimeter','MajorAxisLength', ...
            'MinorAxisLength','Eccentricity','Solidity');
        if isempty(rp), return; end
        rp = rp(1);
        pixSize = (dx + dy) / 2;
        feat.area_mm2      = rp.Area * dx * dy;
        feat.perimeter_mm  = rp.Perimeter * pixSize;
        if feat.perimeter_mm > 0
            feat.sphericity  = 4 * pi * feat.area_mm2 / (feat.perimeter_mm^2);
            feat.compactness = feat.perimeter_mm^2 / (4 * pi * feat.area_mm2);
        end
        feat.eccentricity  = rp.Eccentricity;
        feat.major_axis_mm = rp.MajorAxisLength * pixSize;
        feat.minor_axis_mm = rp.MinorAxisLength * pixSize;
        if feat.major_axis_mm > 0
            feat.elongation = feat.minor_axis_mm / feat.major_axis_mm;
        end
        feat.solidity = rp.Solidity;
        try
            bnd = bwperim(mask);
            [ry, cx] = find(bnd);
            pts = [ry * dx, cx * dy];
            if size(pts,1) > 1
                if size(pts,1) > 500
                    idx = round(linspace(1, size(pts,1), 500));
                    pts = pts(idx,:);
                end
                feat.max_diameter_mm = max(pdist(pts, 'euclidean'));
            end
        catch, end
    catch, end
end

% ── GLCM texture features ─────────────────────────────────────────────────
function feat = computeGLCMFeatures(img2d, mask, nLevels)
% 10 GLCM texture features, averaged over 4 directions (0°,45°,90°,135°).
    fields = {'contrast','correlation','energy','homogeneity','entropy', ...
              'dissimilarity','autocorrelation','cluster_shade', ...
              'cluster_prominence','max_prob'};
    for f = fields, feat.(f{1}) = NaN; end
    try
        img2d = double(img2d);
        mask  = logical(mask);
        if ~any(mask(:)), return; end
        v = img2d(mask);
        vmin = min(v); vmax = max(v);
        if vmax <= vmin, return; end
        qImg = zeros(size(img2d), 'uint8');
        qImg(mask) = uint8(max(1, min(nLevels, ...
            round(1 + (nLevels-1) * (img2d(mask) - vmin) / (vmax - vmin)))));
        glcm = graycomatrix(qImg, 'NumLevels', nLevels, ...
            'GrayLimits', [1, nLevels], ...
            'Offset', [0 1; -1 1; -1 0; -1 -1], 'Symmetric', true);
        gcp = graycoprops(glcm, {'Contrast','Correlation','Energy','Homogeneity'});
        feat.contrast     = mean(gcp.Contrast);
        feat.correlation  = mean(gcp.Correlation);
        feat.energy       = mean(gcp.Energy);
        feat.homogeneity  = mean(gcp.Homogeneity);
        P = mean(glcm, 3);
        S = max(sum(P(:)), eps);
        P = P / S;
        n = nLevels;
        [I, J] = meshgrid(1:n, 1:n);
        I = I'; J = J';
        pp = P(P > 0);
        feat.entropy        = -sum(pp .* log2(pp));
        feat.dissimilarity  = sum(sum(abs(I - J) .* P));
        feat.autocorrelation = sum(sum(I .* J .* P));
        feat.max_prob       = max(P(:));
        mu_i = sum(sum(I .* P));
        mu_j = sum(sum(J .* P));
        c_ij = (I - mu_i) + (J - mu_j);
        feat.cluster_shade      = sum(sum(c_ij.^3 .* P));
        feat.cluster_prominence = sum(sum(c_ij.^4 .* P));
    catch, end
end

% ── GLRLM texture features ────────────────────────────────────────────────
function feat = computeGLRLMFeatures(img2d, mask, nLevels)
% 11 GLRLM texture features, averaged over 0° and 90° directions.
    emptyFeat = struct('sre',NaN,'lre',NaN,'glnu',NaN,'rlnu',NaN,'run_pct',NaN, ...
        'lglre',NaN,'hglre',NaN,'srlgle',NaN,'srhgle',NaN,'lrlgle',NaN,'lrhgle',NaN);
    feat = emptyFeat;
    try
        img2d = double(img2d);
        mask  = logical(mask);
        if ~any(mask(:)), return; end
        v = img2d(mask);
        vmin = min(v); vmax = max(v);
        if vmax <= vmin, return; end
        qImg = zeros(size(img2d));
        qImg(mask) = max(1, min(nLevels, ...
            round(1 + (nLevels-1) * (img2d(mask) - vmin) / (vmax - vmin))));
        [nR, nC] = size(qImg);
        maxRun = max(nR, nC);
        rlm = buildGLRLM(qImg, mask, nLevels, maxRun, [0,1]) + ...
              buildGLRLM(qImg, mask, nLevels, maxRun, [1,0]);
        feat = glrlmFeatures(rlm, sum(mask(:)));
    catch, end
end

function rlm = buildGLRLM(qImg, mask, nG, maxRun, offset)
    [nR, nC] = size(qImg);
    rlm = zeros(nG, maxRun);
    dy = offset(1); dx = offset(2);
    visited = false(nR, nC);
    for r = 1:nR
        for c = 1:nC
            if ~mask(r,c) || visited(r,c), continue; end
            g = qImg(r,c);
            if g < 1, continue; end
            runLen = 1; rr = r+dy; cc = c+dx;
            while rr>=1 && rr<=nR && cc>=1 && cc<=nC && mask(rr,cc) && qImg(rr,cc)==g
                runLen = runLen+1;
                visited(rr,cc) = true;
                rr = rr+dy; cc = cc+dx;
            end
            if runLen <= maxRun
                rlm(g, runLen) = rlm(g, runLen) + 1;
            end
        end
    end
end

function feat = glrlmFeatures(rlm, nVoxels)
    nRuns = sum(rlm(:));
    if nRuns == 0
        feat = struct('sre',NaN,'lre',NaN,'glnu',NaN,'rlnu',NaN,'run_pct',NaN, ...
            'lglre',NaN,'hglre',NaN,'srlgle',NaN,'srhgle',NaN,'lrlgle',NaN,'lrhgle',NaN);
        return
    end
    [nG, maxRun] = size(rlm);
    [G, R] = meshgrid(1:nG, 1:maxRun);
    G = G'; R = R';
    feat.sre     = sum(sum(rlm ./ R.^2))  / nRuns;
    feat.lre     = sum(sum(rlm .* R.^2))  / nRuns;
    feat.glnu    = sum(sum(rlm,2).^2)     / nRuns;
    feat.rlnu    = sum(sum(rlm,1).^2)     / nRuns;
    feat.run_pct = nRuns / max(nVoxels, 1);
    feat.lglre   = sum(sum(rlm ./ G.^2))  / nRuns;
    feat.hglre   = sum(sum(rlm .* G.^2))  / nRuns;
    feat.srlgle  = sum(sum(rlm ./ (G.^2 .* R.^2))) / nRuns;
    feat.srhgle  = sum(sum(rlm .* G.^2 ./ R.^2))   / nRuns;
    feat.lrlgle  = sum(sum(rlm .* R.^2 ./ G.^2))   / nRuns;
    feat.lrhgle  = sum(sum(rlm .* G.^2 .* R.^2))   / nRuns;
end

% ── GLSZM texture features ────────────────────────────────────────────────
function feat = computeGLSZMFeatures(img2d, mask, nLevels)
% 11 GLSZM texture features using bwconncomp per gray level.
    emptyFeat = struct('sae',NaN,'lae',NaN,'glnu',NaN,'sznu',NaN,'zone_pct',NaN, ...
        'lglze',NaN,'hglze',NaN,'salgle',NaN,'sahgle',NaN,'lalgle',NaN,'lahgle',NaN);
    feat = emptyFeat;
    try
        img2d = double(img2d);
        mask  = logical(mask);
        if ~any(mask(:)), return; end
        v = img2d(mask);
        vmin = min(v); vmax = max(v);
        if vmax <= vmin, return; end
        qImg = zeros(size(img2d));
        qImg(mask) = max(1, min(nLevels, ...
            round(1 + (nLevels-1) * (img2d(mask) - vmin) / (vmax - vmin))));
        nVox = sum(mask(:));
        maxSz = min(nVox, 512);
        szm = zeros(nLevels, maxSz);
        for g = 1:nLevels
            gMask = (qImg == g) & mask;
            if ~any(gMask(:)), continue; end
            CC = bwconncomp(gMask, 4);
            for ci = 1:CC.NumObjects
                sz = min(numel(CC.PixelIdxList{ci}), maxSz);
                szm(g, sz) = szm(g, sz) + 1;
            end
        end
        nZones = sum(szm(:));
        if nZones == 0, return; end
        [G, S] = meshgrid(1:nLevels, 1:maxSz);
        G = G'; S = S';
        feat.sae      = sum(sum(szm ./ S.^2))             / nZones;
        feat.lae      = sum(sum(szm .* S.^2))             / nZones;
        feat.glnu     = sum(sum(szm,2).^2)                / nZones;
        feat.sznu     = sum(sum(szm,1).^2)                / nZones;
        feat.zone_pct = nZones / max(nVox, 1);
        feat.lglze    = sum(sum(szm ./ G.^2))             / nZones;
        feat.hglze    = sum(sum(szm .* G.^2))             / nZones;
        feat.salgle   = sum(sum(szm ./ (G.^2 .* S.^2)))  / nZones;
        feat.sahgle   = sum(sum(szm .* G.^2 ./ S.^2))    / nZones;
        feat.lalgle   = sum(sum(szm .* S.^2 ./ G.^2))    / nZones;
        feat.lahgle   = sum(sum(szm .* G.^2 .* S.^2))    / nZones;
    catch, end
end

% ── Radiomics help dialog ─────────────────────────────────────────────────
function showRadiomicsHelpDialog(~)
% Open a non-modal window with a scrollable feature reference table.
    f = uifigure('Name','Radiomic Features Reference', ...
        'Position',[100 80 880 680],'Resize','on');
    t = uitable(f,'Position',[10 10 860 660]);
    t.ColumnName  = {'Category','Feature','Definition'};
    t.ColumnWidth = {90, 180, 'auto'};
    t.RowStriping = 'on';
    t.Data = { ...
        'Intensity','VoxelCount',       'Number of voxels inside the ROI'; ...
        'Intensity','Volume_mm3',       'VoxelCount × voxel volume (mm³)'; ...
        'Intensity','Mean',             'Average intensity across all ROI voxels'; ...
        'Intensity','Median',           '50th percentile of the intensity distribution'; ...
        'Intensity','Mode',             'Centre of the peak bin of a 64-bin intensity histogram'; ...
        'Intensity','Variance',         'Mean squared deviation from the mean'; ...
        'Intensity','StdDev',           'Square root of Variance; measures dispersion around the mean'; ...
        'Intensity','Skewness',         'Asymmetry of intensity histogram: 0=symmetric, >0=right-skewed'; ...
        'Intensity','Kurtosis',         '"Tailedness"; equals 3 for a Gaussian distribution'; ...
        'Intensity','Energy',           'Σx²/n — measures overall signal magnitude'; ...
        'Intensity','Entropy',          '−Σp·log₂p (64 bins) — higher value = more uniform histogram'; ...
        'Intensity','Uniformity',       'Σp² (64 bins) — higher value = fewer dominant intensity bins'; ...
        'Intensity','RMS',              'Root Mean Square = √(mean(x²)); combines mean and spread'; ...
        'Intensity','MAD',              'Mean Absolute Deviation from mean = mean|xᵢ−μ|; robust to outliers'; ...
        'Intensity','Min',              'Minimum intensity in the ROI'; ...
        'Intensity','Max',              'Maximum intensity in the ROI'; ...
        'Intensity','Range',            'Max − Min'; ...
        'Intensity','IQR',              'Interquartile Range = P75 − P25; robust measure of spread'; ...
        'Intensity','P10',              '10th percentile intensity'; ...
        'Intensity','P25',              '25th percentile (1st quartile)'; ...
        'Intensity','P75',              '75th percentile (3rd quartile)'; ...
        'Intensity','P90',              '90th percentile intensity'; ...
        'Shape','Area_mm2',             'Cross-sectional ROI area in the slice plane (mm²)'; ...
        'Shape','Perimeter_mm',         'Length of the ROI boundary (mm)'; ...
        'Shape','Sphericity',           '4π·Area/Perimeter²; equals 1 for a perfect circle, <1 for complex shapes'; ...
        'Shape','Compactness',          'Perimeter²/(4π·Area); inverse of Sphericity; 1 = circle'; ...
        'Shape','Eccentricity',         'Eccentricity of equivalent ellipse: 0 = circle, 1 = line segment'; ...
        'Shape','MajorAxis_mm',         'Length of the major axis of the equivalent ellipse (mm)'; ...
        'Shape','MinorAxis_mm',         'Length of the minor axis of the equivalent ellipse (mm)'; ...
        'Shape','Elongation',           'MinorAxisLength / MajorAxisLength; 1 = equidimensional'; ...
        'Shape','Solidity',             'Area / ConvexHullArea; measures convexity (1 = fully convex shape)'; ...
        'Shape','MaxDiameter_mm',       'Maximum Feret diameter: largest distance between boundary points (mm)'; ...
        'GLCM','GLCM_Contrast',         'Σ|i−j|²·P(i,j): measures local intensity variation'; ...
        'GLCM','GLCM_Correlation',      'Linear dependency of gray levels across neighbouring voxels (−1 to 1)'; ...
        'GLCM','GLCM_Energy',           'Angular Second Moment = Σ P(i,j)²: measures textural uniformity'; ...
        'GLCM','GLCM_Homogeneity',      'Inverse Difference Moment = Σ P/(1+|i−j|): high = similar neighbours'; ...
        'GLCM','GLCM_Entropy',          '−Σ P·log₂P: high value = many equally probable co-occurrence pairs'; ...
        'GLCM','GLCM_Dissimilarity',    'Σ |i−j|·P(i,j): linear contrast penalty (less sensitive than Contrast)'; ...
        'GLCM','GLCM_Autocorrelation',  'Σ i·j·P(i,j): related to the fineness of image texture'; ...
        'GLCM','GLCM_ClusterShade',     'Σ(i+j−μᵢ−μⱼ)³·P: skewness of the GLCM; sensitive to asymmetry'; ...
        'GLCM','GLCM_ClusterProminence','Σ(i+j−μᵢ−μⱼ)⁴·P: higher-order cluster variation; less sensitive to mean'; ...
        'GLCM','GLCM_MaxProbability',   'Maximum single entry of the GLCM; dominant co-occurrence pair frequency'; ...
        'GLRLM','GLRLM_SRE',            'Short Run Emphasis = Σ rlm/r²/N; high = many short runs (fine texture)'; ...
        'GLRLM','GLRLM_LRE',            'Long Run Emphasis = Σ rlm·r²/N; high = many long runs (coarse texture)'; ...
        'GLRLM','GLRLM_GLNU',           'Gray Level Non-Uniformity = Σ row_sums²/N; low = uniform gray distribution'; ...
        'GLRLM','GLRLM_RLNU',           'Run Length Non-Uniformity = Σ col_sums²/N; low = uniform run-length distribution'; ...
        'GLRLM','GLRLM_RunPct',         'Run Percentage = nRuns/nVoxels; high = many short runs, low = few long runs'; ...
        'GLRLM','GLRLM_LGLRE',          'Low Gray Level Run Emphasis = Σ rlm/g²/N; high = many low-intensity runs'; ...
        'GLRLM','GLRLM_HGLRE',          'High Gray Level Run Emphasis = Σ rlm·g²/N; high = many high-intensity runs'; ...
        'GLRLM','GLRLM_SRLGLE',         'Short Run Low Gray Level Emphasis: combined short run + low intensity'; ...
        'GLRLM','GLRLM_SRHGLE',         'Short Run High Gray Level Emphasis: combined short run + high intensity'; ...
        'GLRLM','GLRLM_LRLGLE',         'Long Run Low Gray Level Emphasis: combined long run + low intensity'; ...
        'GLRLM','GLRLM_LRHGLE',         'Long Run High Gray Level Emphasis: combined long run + high intensity'; ...
        'GLSZM','GLSZM_SAE',            'Small Area Emphasis = Σ P(g,s)/s²/N; high = many small connected zones'; ...
        'GLSZM','GLSZM_LAE',            'Large Area Emphasis = Σ P(g,s)·s²/N; high = few large zones'; ...
        'GLSZM','GLSZM_GLNU',           'GLSZM Gray Level Non-Uniformity; low = uniform gray across zones'; ...
        'GLSZM','GLSZM_SZNU',           'Size Zone Non-Uniformity; low = uniform zone-size distribution'; ...
        'GLSZM','GLSZM_ZonePct',        'Zone Percentage = nZones/nVoxels; high = heterogeneous, many small zones'; ...
        'GLSZM','GLSZM_LGLZE',          'Low Gray Level Zone Emphasis; high = many low-intensity connected zones'; ...
        'GLSZM','GLSZM_HGLZE',          'High Gray Level Zone Emphasis; high = many high-intensity connected zones'; ...
        'GLSZM','GLSZM_SALGLE',         'Small Area Low Gray Level Emphasis: combined small zone + low intensity'; ...
        'GLSZM','GLSZM_SAHGLE',         'Small Area High Gray Level Emphasis: combined small zone + high intensity'; ...
        'GLSZM','GLSZM_LALGLE',         'Large Area Low Gray Level Emphasis: combined large zone + low intensity'; ...
        'GLSZM','GLSZM_LAHGLE',         'Large Area High Gray Level Emphasis: combined large zone + high intensity'; ...
    };
end

function pts = roiResamplePolyline(pos, nVerts)
% Resample a freehand polyline to exactly nVerts equally-spaced points
% using arc-length parameterization. The loop is closed before resampling
% and the returned polygon is open (no repeated endpoint).
    if size(pos,1) <= 2
        pts = pos;
        return;
    end
    % Close the loop if not already closed
    if norm(pos(end,:) - pos(1,:)) > 1
        pos = [pos; pos(1,:)];
    end
    diffs  = diff(pos, 1, 1);
    segLen = sqrt(sum(diffs.^2, 2));
    cumLen = [0; cumsum(segLen)];
    totalLen = cumLen(end);
    if totalLen < eps
        pts = repmat(pos(1,:), nVerts, 1);
        return;
    end
    % Remove duplicate arc-length values (from zero-length freehand segments)
    % so that interp1 receives strictly unique sample points.
    [cumLen, uIdx] = unique(cumLen, 'stable');
    pos = pos(uIdx, :);
    % Sample nVerts equally-spaced arc-length positions (open polygon)
    tq = linspace(0, totalLen, nVerts + 1);
    tq = tq(1:end-1);
    xi = interp1(cumLen, pos(:,1), tq, 'linear');
    yi = interp1(cumLen, pos(:,2), tq, 'linear');
    pts = [xi(:), yi(:)];
end


% =========================================================================
%  ORGAN-SPECIFIC DIXON SEED-AND-GROW  (module-level helpers)
% =========================================================================

function outerMask = dixonSeedGrowLiver(dix, roughMask, sl)
% DIXONSEEDGROWLIVER  Multi-channel liver segmentation from a rough ROI.
%
%   ALGORITHM
%     1. Erode rough freehand mask to a trusted seed core.
%     2. Build liver tissue model: mean ± 2.5σ from water image,
%        mean ± 3σ from fat image (if available).
%     3. Candidate pixels: within tissue model bounds AND within
%        a spatially expanded bounding box of the rough mask.
%     4. Keep only connected components that overlap the seed core.
%     5. Fill holes (vessels appear as small dark holes in liver).
%     6. Morphological cleanup; return the refined mask.

    outerMask = roughMask;   % safe fallback: return rough mask on failure

    % ── Images ────────────────────────────────────────────────────────────
    Iw = dixonSliceImg(dix, 'Water', sl);
    if isempty(Iw), Iw = dixonSliceImg(dix, 'InPhase', sl); end
    if isempty(Iw), return; end

    If = dixonSliceImg(dix, 'Fat', sl);
    if isempty(If), If = dixonSliceImg(dix, 'OutPhase', sl); end
    hasFat = ~isempty(If);

    Iw = normImg(Iw);
    if hasFat, If = normImg(If); end

    % ── Trusted seed core (progressive erosion) ────────────────────────────
    coreMask = erodeToCore(roughMask, [5 3 2]);

    % ── Tissue model from core ──────────────────────────────────────────────
    wVals = Iw(coreMask);
    wMu   = mean(wVals(:));
    wSig  = max(0.02, std(wVals(:)));

    SIGMA_W = 2.5;
    cand = (Iw >= wMu - SIGMA_W*wSig) & (Iw <= wMu + SIGMA_W*wSig);

    if hasFat
        fVals = If(coreMask);
        fMu   = mean(fVals(:));
        fSig  = max(0.02, std(fVals(:)));
        SIGMA_F = 3.0;   % slightly wider: liver fat varies
        cand  = cand & (If >= fMu - SIGMA_F*fSig) & (If <= fMu + SIGMA_F*fSig);
    end

    % Spatial constraint: expanded bounding box of rough mask
    cand = cand & dilateForGrow(roughMask, 0.15);

    % ── Seed-connected grow ────────────────────────────────────────────────
    grown = seedConnectedGrow(cand, coreMask);
    if ~any(grown(:)), grown = roughMask; end

    % Fill holes (vessel lumens appear as small dark holes in liver parenchyma)
    try, grown = imfill(grown, 'holes'); catch, end

    % ── Morphological cleanup ──────────────────────────────────────────────
    try, grown = imclose(grown, strel('disk', 2)); catch, end
    try, grown = imfill(grown, 'holes'); catch, end
    try, grown = bwareaopen(grown, 50); catch, end

    outerMask = logical(grown);
end


function outerMask = dixonSeedGrowSpleen(dix, roughMask, sl)
% DIXONSEEDGROWSPLEEN  Compact homogeneous spleen segmentation.
%
%   ALGORITHM
%     1. Erode rough mask to a seed core.
%     2. Build spleen model from water image (tighter sigma than liver).
%     3. Candidate pixels within model bounds AND expanded bounding box.
%     4. Keep seed-connected components.
%     5. Compactness clip: trim protrusions beyond 20% of rough-mask extent.
%     6. Morphological cleanup.

    outerMask = roughMask;

    Iw = dixonSliceImg(dix, 'Water', sl);
    if isempty(Iw), Iw = dixonSliceImg(dix, 'InPhase', sl); end
    if isempty(Iw), return; end

    Iw = normImg(Iw);

    % ── Trusted seed core ─────────────────────────────────────────────────
    coreMask = erodeToCore(roughMask, [4 2]);

    % ── Tissue model ──────────────────────────────────────────────────────
    wVals = Iw(coreMask);
    wMu   = mean(wVals(:));
    wSig  = max(0.02, std(wVals(:)));

    SIGMA = 2.0;   % tighter than liver: spleen is more homogeneous
    cand  = (Iw >= wMu - SIGMA*wSig) & (Iw <= wMu + SIGMA*wSig);
    cand  = cand & dilateForGrow(roughMask, 0.10);

    % ── Seed-connected grow ────────────────────────────────────────────────
    grown = seedConnectedGrow(cand, coreMask);
    if ~any(grown(:)), grown = roughMask; end

    % Compactness: clip to 120% of rough-mask bounding box
    grown = enforceCompactness(grown, roughMask);

    % ── Cleanup ───────────────────────────────────────────────────────────
    try, grown = imclose(grown, strel('disk', 2)); catch, end
    try, grown = imfill(grown, 'holes'); catch, end
    try, grown = bwareaopen(grown, 50); catch, end

    outerMask = logical(grown);
end


function outerMask = dixonSeedGrowSAT(dix, sl)
% DIXONSEEDGROWSAT  Subcutaneous adipose tissue segmentation.
%
%   Hard ring-mask geometry is NON-NEGOTIABLE per the design specification.
%
%   ALGORITHM
%     1. Build body mask from water/InPhase image (Otsu threshold + fill).
%     2. Distance transform from body boundary gives inward depth D.
%     3. Ring mask = body pixels with D ∈ [5 mm, 40 mm].
%     4. High-confidence PDFF seeds (> 50%) within ring.
%     5. Grow PDFF > 25% pixels within ring, seeded from step 4.
%     6. Keep boundary-connected fat: retain only components touching the
%        skin-proximal layer of the ring (D ≤ dMin + 5 mm).
%     7. Remove tiny isolated blobs; light morphological smoothing.

    outerMask = false(0);   % empty mask returned if algorithm fails

    % ── Images ────────────────────────────────────────────────────────────
    Iw = dixonSliceImg(dix, 'Water', sl);
    if isempty(Iw), Iw = dixonSliceImg(dix, 'InPhase', sl); end
    if isempty(Iw), return; end

    Ip = dixonSliceImg(dix, 'PDFF', sl);
    if isempty(Ip)
        % Fallback: estimate fat fraction from Fat / (Water + Fat)
        Iff = dixonSliceImg(dix, 'Fat', sl);
        if isempty(Iff), Iff = dixonSliceImg(dix, 'OutPhase', sl); end
        if ~isempty(Iff)
            Ip = double(Iff) ./ max(double(Iw) + double(Iff), eps);
            Ip(~isfinite(Ip)) = 0;
        else
            return;   % no fat quantification available → cannot segment SAT
        end
    end

    [nR, nC] = size(Iw);
    outerMask = false(nR, nC);

    % ── Pixel spacing (mm/pixel) ────────────────────────────────────────────
    pixSpacing = 1.5;   % nominal fallback
    if isfield(dix, 'PixelSpacing_mm') && numel(dix.PixelSpacing_mm) >= 1
        pixSpacing = mean(double(dix.PixelSpacing_mm(1:min(2, end))));
    elseif isfield(dix, 'SpatialInfo') && isfield(dix.SpatialInfo, 'PixelSpacing')
        pixSpacing = mean(double(dix.SpatialInfo.PixelSpacing));
    end
    pixSpacing = max(0.1, pixSpacing);

    dMin_px = max(1, round( 5 / pixSpacing));   % 5 mm inward from body surface
    dMax_px =        round(40 / pixSpacing);     % 40 mm inward from body surface

    % ── Step 1: Body mask ──────────────────────────────────────────────────
    bodyMask = buildBodyMask(double(Iw));
    if ~any(bodyMask(:)), return; end

    % ── Steps 2–3: Distance transform → ring mask ──────────────────────────
    % bwdist(~bodyMask) gives each interior pixel its depth from the body surface.
    D = bwdist(~bodyMask);
    ringMask = bodyMask & (D >= dMin_px) & (D <= dMax_px);
    if ~any(ringMask(:)), return; end

    % ── Steps 4–5: Fat seed grow within ring ───────────────────────────────
    Ip = double(Ip);
    Ip(~isfinite(Ip)) = 0;

    SEED_PDFF  = 0.50;   % high-confidence fat seeds
    GROW_PDFF  = 0.25;   % threshold for fat grow candidates
    fatSeeds = ringMask & (Ip >= SEED_PDFF);

    if ~any(fatSeeds(:))
        % Relax: accept PDFF > 35% as seeds if no 50% seeds found in ring
        fatSeeds = ringMask & (Ip >= 0.35);
    end
    if ~any(fatSeeds(:)), return; end   % no fat in ring

    fatCand = ringMask & (Ip >= GROW_PDFF);
    grown   = seedConnectedGrow(fatCand, fatSeeds);
    if ~any(grown(:)), return; end

    % ── Step 6: Keep only skin-proximal (boundary-connected) fat ───────────
    % SAT must be anchored to the superficial part of the ring (near skin).
    % A deep VAT pocket that happens to fall within the ring is excluded here.
    extraPx       = max(1, round(5 / pixSpacing));   % 5 mm extra buffer
    skinProxLayer = ringMask & (D <= dMin_px + extraPx);
    anchoredSeeds = grown & skinProxLayer;
    if any(anchoredSeeds(:))
        grown = seedConnectedGrow(grown, anchoredSeeds);
    end
    % If no fat touches the skin-proximal layer, return empty (anomalous case)
    if ~any(grown(:)), return; end

    % ── Step 7: Remove tiny blobs; mild smoothing ──────────────────────────
    try, grown = bwareaopen(grown, 50); catch, end
    try, grown = imclose(grown, strel('disk', 2)); catch, end
    try, grown = bwareaopen(grown, 50); catch, end

    outerMask = logical(grown);
end


% ─── Low-level utilities shared by the organ-grow functions ───────────────

function bodyMask = buildBodyMask(Iw)
% Build a binary body mask from a water (or in-phase) image using Otsu
% thresholding followed by hole-fill and largest-component selection.
    Iw = double(Iw);
    Iw(~isfinite(Iw)) = 0;

    nzVals = Iw(Iw > 0);
    if numel(nzVals) < 100
        bodyMask = false(size(Iw));
        return;
    end

    % Otsu threshold on the non-zero histogram
    try
        thresh = graythresh(mat2gray(Iw)) * max(Iw(:));
    catch
        thresh = prctile(nzVals, 20);
    end
    thresh = max(thresh, prctile(nzVals, 5));   % floor at 5th percentile

    bodyMask = Iw > thresh;
    try, bodyMask = imfill(bodyMask, 'holes'); catch, end

    % Keep largest connected component
    CC = bwconncomp(bodyMask, 8);
    if CC.NumObjects > 1
        sz = cellfun(@numel, CC.PixelIdxList);
        [~, idx] = max(sz);
        bodyMask = false(size(bodyMask));
        bodyMask(CC.PixelIdxList{idx}) = true;
    end

    try, bodyMask = imfill(bodyMask, 'holes'); catch, end
    bodyMask = logical(bodyMask);
end


function I = dixonSliceImg(dix, contrast, sl)
% Extract a double-precision 2-D slice from a Dixon volume struct.
    I = [];
    vol = dixonVolume(dix, contrast);
    if isempty(vol), return; end
    sl  = max(1, min(sl, size(vol, 3)));
    I   = double(vol(:,:,sl));
    I(~isfinite(I)) = 0;
end


function I = normImg(I)
% Normalize image to [0,1] using robust 1st–99th percentile scaling.
    I  = double(I);
    lo = prctile(I(:), 1);
    hi = prctile(I(:), 99);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        hi = max(I(:));  lo = min(I(:));
    end
    if hi > lo
        I = (I - lo) / (hi - lo);
        I = min(max(I, 0), 1);
    else
        I = zeros(size(I));
    end
end


function coreMask = erodeToCore(roughMask, erodeList)
% Erode roughMask with decreasing radii until the core has >= 50 pixels.
% erodeList is a vector of radii to try in order, e.g. [5 3 2].
% If all radii produce < 50 pixels, returns the original rough mask.
    coreMask = logical(roughMask);
    for ep = erodeList(:)'
        try
            cm = imerode(roughMask, strel('disk', ep));
        catch
            cm = roughMask;
        end
        if nnz(cm) >= 50
            coreMask = logical(cm);
            return;
        end
    end
end


function grown = seedConnectedGrow(cand, seed)
% Keep connected components of the candidate mask that overlap the seed.
% Uses 8-connectivity.
    grown = false(size(cand));
    if ~any(seed(:)), return; end
    CC = bwconncomp(logical(cand), 8);
    for ii = 1:CC.NumObjects
        pix = CC.PixelIdxList{ii};
        if any(seed(pix))
            grown(pix) = true;
        end
    end
end


function spatialMask = dilateForGrow(roughMask, expandFrac)
% Return a bounding-box mask that is expandFrac larger than roughMask's
% axis-aligned bounding box on each side.  Used as a spatial constraint
% to prevent the grow from wandering too far from the manual ROI.
    [nR, nC] = size(roughMask);
    [r, c]   = find(roughMask);
    if isempty(r)
        spatialMask = false(nR, nC);
        return;
    end
    h   = max(r) - min(r) + 1;
    w   = max(c) - min(c) + 1;
    pad = max(5, round(expandFrac * max(h, w)));
    r1  = max(1,  min(r) - pad);
    r2  = min(nR, max(r) + pad);
    c1  = max(1,  min(c) - pad);
    c2  = min(nC, max(c) + pad);
    spatialMask = false(nR, nC);
    spatialMask(r1:r2, c1:c2) = true;
end


function grown = enforceCompactness(grown, roughMask)
% Clip the grown mask to a bounding box 20% larger than the rough mask.
% Prevents elongated protrusions beyond the region plausibly spleen-shaped.
    [nR, nC] = size(grown);
    [r, c]   = find(roughMask);
    if isempty(r), return; end
    h   = max(r) - min(r) + 1;
    w   = max(c) - min(c) + 1;
    pad = max(5, round(0.20 * max(h, w)));
    r1  = max(1,  min(r) - pad);
    r2  = min(nR, max(r) + pad);
    c1  = max(1,  min(c) - pad);
    c2  = min(nC, max(c) + pad);
    clip = false(nR, nC);
    clip(r1:r2, c1:c2) = true;
    grown = grown & clip;
end


function mask = getStoredDixonROIMask(app, roiName, sl)
% Return the stored binary mask for roiName on slice sl, or [] if none exists.
    mask = [];
    key  = sprintf('sl%d', sl);
    try
        slices = app.AppData.ROIs.(roiName).Slices;
        if isfield(slices, key)
            m = slices.(key);
            if ~isempty(m) && any(m(:))
                mask = logical(m);
            end
        end
    catch
    end
end


% =========================================================================
%  MAGNIFIED ROI POPUP HELPERS
% =========================================================================

function [fig, ax] = openROIPopupFigure(imgData, cmapData, climVals, titleStr)
% Create a large standalone figure for precise ROI drawing.
% Returns [fig, ax] — the figure and its single axes.
    scr  = get(0,'ScreenSize');
    popH = min(round(scr(4) * 0.82), 840);
    popW = min(round(scr(3) * 0.82), 960);
    popX = scr(1) + round((scr(3) - popW) / 2);
    popY = scr(2) + round((scr(4) - popH) / 2);

    fig = uifigure('Name', titleStr, ...
        'Position', [popX popY popW popH], ...
        'Resize',   'on', ...
        'Color',    [0.10 0.10 0.10]);
    gl = uigridlayout(fig, [1 1]);
    gl.Padding = [2 2 2 2];
    ax = uiaxes(gl);
    ax.Color = [0.10 0.10 0.10];

    imagesc(ax, imgData);
    axis(ax, 'image');
    ax.XTick = []; ax.YTick = [];
    ax.XColor = 'none'; ax.YColor = 'none';

    if ischar(cmapData) || isstring(cmapData)
        try, colormap(ax, char(cmapData)); catch, colormap(ax, 'gray'); end
    elseif isnumeric(cmapData) && size(cmapData,2) == 3
        colormap(ax, cmapData);
    end
    if numel(climVals) == 2 && all(isfinite(climVals)) && climVals(2) > climVals(1)
        clim(ax, climVals);
    end
    drawnow;
end


function roiPopupConfirmKey(fig, event)
% Keyboard handler for the ROI drawing popup.
% A / Enter → accept;  Esc → discard.
    if ~isvalid(fig), return; end
    key = lower(event.Key);
    if any(strcmp(key, {'a', 'return', 'enter'}))
        fig.UserData = struct('accepted', true);
        uiresume(fig);
    elseif strcmp(key, 'escape')
        fig.UserData = struct('accepted', false);
        uiresume(fig);
    end
end


function roiPopupMultiKey(fig, event)
% Extended key handler: A/Enter=accept, Esc=discard, I=include, E/X=exclude.
    if ~isvalid(fig), return; end
    key = lower(event.Key);
    ch = ''; try, ch = lower(event.Character); catch, end
    if any(strcmp(key, {'a', 'return', 'enter'}))
        fig.UserData = struct('action', 'accept'); uiresume(fig);
    elseif strcmp(key, 'escape')
        fig.UserData = struct('action', 'discard'); uiresume(fig);
    elseif strcmp(key, 'i') || strcmp(ch, 'i')
        fig.UserData = struct('action', 'include'); uiresume(fig);
    elseif any(strcmp(key, {'e', 'x'})) || any(strcmp(ch, {'e', 'x'}))
        fig.UserData = struct('action', 'exclude'); uiresume(fig);
    end
end


function redrawROIPopup(ax, imgData, cmapData, climVals, mask, roiColor)
% Clear axis, re-display image with colormap/clim, overlay current mask boundary.
    try
        cla(ax);
        imagesc(ax, imgData);
        axis(ax, 'image');
        ax.XTick = []; ax.YTick = [];
        ax.XColor = 'none'; ax.YColor = 'none';
        if ischar(cmapData) || isstring(cmapData)
            try, colormap(ax, char(cmapData)); catch, colormap(ax, 'gray'); end
        elseif isnumeric(cmapData) && size(cmapData, 2) == 3
            colormap(ax, cmapData);
        end
        if numel(climVals) == 2 && all(isfinite(climVals)) && climVals(2) > climVals(1)
            clim(ax, climVals);
        end
        if ~isempty(mask) && any(mask(:))
            hold(ax, 'on');
            bndList = bwboundaries(logical(mask), 'noholes');
            for k = 1:numel(bndList)
                b = bndList{k};
                plot(ax, b(:,2), b(:,1), '-', 'Color', roiColor, 'LineWidth', 2.5);
            end
            hold(ax, 'off');
        end
        drawnow;
    catch, end
end


function [mask, accepted] = roiPopupMultiOpLoop(app, popupFig, popupAx, ...
        initialMask, imgData, cmapData, climVals, roiColor, nR, nC, modality)
% Main loop: redraw popup → uiwait for key → handle accept/discard/include/exclude.
    mask = initialMask;
    accepted = false;
    redrawROIPopup(popupAx, imgData, cmapData, climVals, mask, roiColor);

    while true
        if ~isvalid(popupFig), break; end
        setStatus(app, 'A=accept  Esc=discard  I=include region  E/X=exclude region');
        popupFig.UserData = struct('action', '');
        popupFig.WindowKeyPressFcn = @(~,e) roiPopupMultiKey(popupFig, e);
        uiwait(popupFig);

        if ~isvalid(popupFig), break; end
        action = '';
        try, action = popupFig.UserData.action; catch, end

        if strcmp(action, 'accept')
            accepted = true; break;
        elseif strcmp(action, 'discard')
            mask = []; break;
        elseif strcmp(action, 'include')
            if strcmp(modality, 'MRE')
                app.AppData.MREROIDrawing = true;
                try, app.updateMREPlaybackButtonEnabled(); catch, end
            else
                app.AppData.DixonROIDrawing = true;
            end
            setStatus(app, 'Draw region to INCLUDE (green). Double-click to finish.');
            delta = captureFreehandMask(app, popupAx, nR, nC, [0.2 0.9 0.2]);
            if strcmp(modality, 'MRE')
                app.AppData.MREROIDrawing = false;
                try, app.updateMREPlaybackButtonEnabled(); catch, end
            else
                app.AppData.DixonROIDrawing = false;
            end
            if any(delta(:))
                try, delta = imfill(logical(delta), 'holes'); catch, end
                mask = logical(mask) | logical(delta);
            end
            redrawROIPopup(popupAx, imgData, cmapData, climVals, mask, roiColor);
        else  % exclude
            if strcmp(modality, 'MRE')
                app.AppData.MREROIDrawing = true;
                try, app.updateMREPlaybackButtonEnabled(); catch, end
            else
                app.AppData.DixonROIDrawing = true;
            end
            setStatus(app, 'Draw region to EXCLUDE (magenta). Double-click to finish.');
            delta = captureFreehandMask(app, popupAx, nR, nC, [1 0 1]);
            if strcmp(modality, 'MRE')
                app.AppData.MREROIDrawing = false;
                try, app.updateMREPlaybackButtonEnabled(); catch, end
            else
                app.AppData.DixonROIDrawing = false;
            end
            if any(delta(:))
                mask = logical(mask) & ~logical(delta);
            end
            redrawROIPopup(popupAx, imgData, cmapData, climVals, mask, roiColor);
        end
    end
end



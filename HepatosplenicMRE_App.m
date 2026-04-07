classdef HepatosplenicMRE_App < matlab.apps.AppBase
% HepatosplenicMRE_App  GUI skeleton for the hepatosplenic MRE analysis platform.
%
%   PURPOSE
%     Phase 1 scaffold: builds the complete UI layout with all panels,
%     menus, toolbar buttons, image tabs, feature display, and pipeline
%     status bar.  Every callback is stubbed so later phases can fill in
%     the logic without touching the layout code.
%
%   USAGE
%     app = HepatosplenicMRE_App;   % launch the app
%     delete(app);                  % close programmatically
%
%   LAYOUT  (approximate)
%     ┌──────────────────────────────────────────────────────────────────┐
%     │  Menu bar                                                        │
%     │  Toolbar                                                         │
%     ├──────────┬─────────────────────────────────────┬────────────────┤
%     │  Study   │  [Scout][Dixon][MRE][L1-L2][Overlay]│  Feature       │
%     │  Browser │         Image display axes          │  Results panel │
%     │  (tree)  │         Slice / overlay controls    │  (collapsible) │
%     ├──────────┴─────────────────────────────────────┴────────────────┤
%     │  Pipeline status bar  S1 → S2 → S3 → S4 | L1-L2 | message     │
%     └──────────────────────────────────────────────────────────────────┘
%
%   PHASES
%     Phase 1  This file — UI skeleton only, all callbacks are stubs.
%     Phase 2  DICOM I/O, series sorter, matrix harmonization.
%     Phase 3  L1–L2 vertebral localization + Scout→Dixon→MRE propagation.
%     Phase 4  Organ segmentation (liver, spleen, muscle, SAT).
%     Phase 5  Feature extraction (stiffness, PDFF, volumes, ratios).
%     Phase 6  Technical QC engine (confidence, range/coverage checks).
%     Phase 7  Export (CSV, PDF report, NIfTI masks, JSON config).
%
%   REQUIREMENTS
%     MATLAB R2019b or later (uifigure, uigridlayout, uitabgroup, uitree).
%     Image Processing Toolbox (imadjust, imshow into uiaxes).
%     (Optional) Deep Learning Toolbox — for Phase 4 segmentation.
%
%   AUTHOR  MengYin Mayo / HepatosplenicMRE project
%   DATE    2026-04

    % =====================================================================
    %  PROPERTIES — UI components
    % =====================================================================
    properties (Access = public)

        % --- Main window ---
        UIFigure            matlab.ui.Figure

        % --- Menus ---
        FileMenu            matlab.ui.container.Menu
        ProcessMenu         matlab.ui.container.Menu
        SegmentationMenu    matlab.ui.container.Menu
        FeaturesMenu        matlab.ui.container.Menu
        L12Menu             matlab.ui.container.Menu
        QCMenu              matlab.ui.container.Menu
        RegistrationMenu    matlab.ui.container.Menu
        ExportMenu          matlab.ui.container.Menu
        HelpMenu            matlab.ui.container.Menu

        % --- Toolbar (top button row) ---
        ToolbarPanel        matlab.ui.container.Panel
        BtnLoadStudy        matlab.ui.control.Button
        BtnRunStage1        matlab.ui.control.Button
        BtnRunStage2        matlab.ui.control.Button
        BtnRunStage3        matlab.ui.control.Button
        BtnRunQC            matlab.ui.control.Button
        BtnL12Locate        matlab.ui.control.Button
        BtnRunAll           matlab.ui.control.Button
        BtnExportCSV        matlab.ui.control.Button

        % --- Overall body grid ---
        BodyGrid            matlab.ui.container.GridLayout

        % --- LEFT PANEL: Study browser ---
        LeftPanel           matlab.ui.container.Panel
        LeftGrid            matlab.ui.container.GridLayout
        LblBrowser          matlab.ui.control.Label
        StudyTree           matlab.ui.container.CheckBoxTree
        LblStudyStats       matlab.ui.control.Label

        % --- CENTER PANEL: Tabbed image views ---
        CenterPanel         matlab.ui.container.Panel
        CenterGrid          matlab.ui.container.GridLayout
        ImageTabGroup       matlab.ui.container.TabGroup

        ScoutTab            matlab.ui.container.Tab
        ScoutGrid           matlab.ui.container.GridLayout
        AxScoutAxial        matlab.ui.control.UIAxes
        AxScoutCoronal      matlab.ui.control.UIAxes
        AxScoutSagittal     matlab.ui.control.UIAxes

        DixonTab            matlab.ui.container.Tab
        DixonGrid           matlab.ui.container.GridLayout
        AxDixonWater        matlab.ui.control.UIAxes
        AxDixonFat          matlab.ui.control.UIAxes
        AxDixonFF           matlab.ui.control.UIAxes
        AxDixonInPhase      matlab.ui.control.UIAxes

        MRETab              matlab.ui.container.Tab
        MREGrid             matlab.ui.container.GridLayout
        AxMREMagnitude      matlab.ui.control.UIAxes
        AxMREStiffness      matlab.ui.control.UIAxes
        AxMREWave           matlab.ui.control.UIAxes

        L12Tab              matlab.ui.container.Tab
        L12Grid             matlab.ui.container.GridLayout
        AxL12Axial          matlab.ui.control.UIAxes
        AxL12Coronal        matlab.ui.control.UIAxes

        OverlayTab          matlab.ui.container.Tab
        OverlayGrid         matlab.ui.container.GridLayout
        AxOverlayDixon      matlab.ui.control.UIAxes
        AxOverlayMRE        matlab.ui.control.UIAxes

        % --- Image controls (below tabs) ---
        ControlPanel        matlab.ui.container.Panel
        ControlGrid         matlab.ui.container.GridLayout
        BtnSegOverlay       matlab.ui.control.StateButton
        BtnL12Lines         matlab.ui.control.StateButton
        BtnStiffnessMap     matlab.ui.control.StateButton
        BtnPDFFMap          matlab.ui.control.StateButton
        SldrSlice           matlab.ui.control.Slider
        LblSlice            matlab.ui.control.Label
        DropColormap        matlab.ui.control.DropDown
        LblImageInfo        matlab.ui.control.Label

        % --- RIGHT PANEL: Feature results ---
        RightPanel          matlab.ui.container.Panel
        RightGrid           matlab.ui.container.GridLayout

        % Organ size & composition section
        PnlOrgan            matlab.ui.container.Panel
        LblLiverVol         matlab.ui.control.Label
        ValLiverVol         matlab.ui.control.Label
        LblSpleenVol        matlab.ui.control.Label
        ValSpleenVol        matlab.ui.control.Label
        LblLSRatio          matlab.ui.control.Label
        ValLSRatio          matlab.ui.control.Label
        LblLiverPDFF        matlab.ui.control.Label
        ValLiverPDFF        matlab.ui.control.Label

        % Mechanical / MRE section
        PnlMRE              matlab.ui.container.Panel
        LblLiverStiff       matlab.ui.control.Label
        ValLiverStiff       matlab.ui.control.Label
        LblSpleenStiff      matlab.ui.control.Label
        ValSpleenStiff      matlab.ui.control.Label
        LblStiffRatio       matlab.ui.control.Label
        ValStiffRatio       matlab.ui.control.Label
        LblHetIQR           matlab.ui.control.Label
        ValHetIQR           matlab.ui.control.Label

        % Body composition section
        PnlBodyComp         matlab.ui.container.Panel
        LblMuscleArea       matlab.ui.control.Label
        ValMuscleArea       matlab.ui.control.Label
        LblSATArea          matlab.ui.control.Label
        ValSATArea          matlab.ui.control.Label
        LblMuscleFatRatio   matlab.ui.control.Label
        ValMuscleFatRatio   matlab.ui.control.Label
        LblMusclePDFF       matlab.ui.control.Label
        ValMusclePDFF       matlab.ui.control.Label

        % L1-L2 section
        PnlL12              matlab.ui.container.Panel
        LblL1Status         matlab.ui.control.Label
        ValL1Status         matlab.ui.control.Label
        LblL2Status         matlab.ui.control.Label
        ValL2Status         matlab.ui.control.Label
        LblL12MuscleArea    matlab.ui.control.Label
        ValL12MuscleArea    matlab.ui.control.Label
        LblL12SATArea       matlab.ui.control.Label
        ValL12SATArea       matlab.ui.control.Label
        LblL12MuscleFat     matlab.ui.control.Label
        ValL12MuscleFat     matlab.ui.control.Label
        LblL12PDFF          matlab.ui.control.Label
        ValL12PDFF          matlab.ui.control.Label

        % QC section
        PnlQC               matlab.ui.container.Panel
        LblSegConf          matlab.ui.control.Label
        ValSegConf          matlab.ui.control.Label
        LblCoverage         matlab.ui.control.Label
        ValCoverage         matlab.ui.control.Label
        LblRangeCheck       matlab.ui.control.Label
        ValRangeCheck       matlab.ui.control.Label
        LblManualReview     matlab.ui.control.Label
        ValManualReview     matlab.ui.control.Label

        % --- BOTTOM: Pipeline status bar ---
        BottomPanel         matlab.ui.container.Panel
        BottomGrid          matlab.ui.container.GridLayout
        BtnStage1Status     matlab.ui.control.Button
        BtnStage2Status     matlab.ui.control.Button
        BtnStage3Status     matlab.ui.control.Button
        BtnStage4Status     matlab.ui.control.Button
        BtnL12Status        matlab.ui.control.Button
        LblStatusMsg        matlab.ui.control.Label
    end

    % =====================================================================
    %  PROPERTIES — App data (filled in by later phases)
    % =====================================================================
    properties (Access = public)
        AppData struct = struct( ...
            'StudyList',        {{}}, ...   % cell array of study structs
            'ActiveStudyIdx',   0,    ...   % index into StudyList
            'ScoutVolume',      [],   ...   % 3D array [rows x cols x slices]
            'DixonWater',       [],   ...   % 3D Dixon water image
            'DixonFat',         [],   ...   % 3D Dixon fat image
            'DixonFF',          [],   ...   % 3D fat fraction map (0–100%)
            'DixonInPhase',     [],   ...   % 3D in-phase image
            'MREMagnitude',     [],   ...   % 4D MRE magnitude [r x c x s x t]
            'MREStiffness',     [],   ...   % 3D stiffness map (kPa)
            'MREWaveImages',    [],   ...   % 4D wave images
            'LiverMask',        [],   ...   % 3D binary liver mask
            'SpleenMask',       [],   ...   % 3D binary spleen mask
            'MuscleMask',       [],   ...   % 3D binary muscle mask
            'SATMask',          [],   ...   % 3D binary SAT mask
            'L1SliceScout',     [],   ...   % slice index of L1 in Scout
            'L2SliceScout',     [],   ...   % slice index of L2 in Scout
            'L1SliceDixon',     [],   ...   % propagated L1 in Dixon space
            'L2SliceDixon',     [],   ...   % propagated L2 in Dixon space
            'L1SliceMRE',       [],   ...   % propagated L1 in MRE space
            'L2SliceMRE',       [],   ...   % propagated L2 in MRE space
            'RegistrationTform',[], ...     % Scout→Dixon tform struct
            'Features',         struct(), ...% extracted feature struct
            'QCResults',        struct(), ...% QC output struct
            'CurrentSlice',     1,    ...   % displayed slice index
            'PipelineStatus',   struct( ...
                'S1', 'idle', 'S2', 'idle', ...
                'S3', 'idle', 'S4', 'idle', ...
                'L12','idle') ...
        )
    end

    % =====================================================================
    %  COMPONENT CREATION
    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            % ---- Main window ----------------------------------------
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position  = [50 50 1440 860];
            app.UIFigure.Name      = 'HepatosplenicMRE Analysis Platform  v1.0';
            app.UIFigure.Resize    = 'on';
            app.UIFigure.CloseRequestFcn = @(s,e) app.CloseFcn();

            % ---- Menus ----------------------------------------------
            createMenus(app);

            % ---- Outer grid (toolbar | body | bottom) ---------------
            outerGrid = uigridlayout(app.UIFigure, [3 1]);
            outerGrid.RowHeight    = {44, '1x', 68};
            outerGrid.ColumnWidth  = {'1x'};
            outerGrid.Padding      = [0 0 0 0];
            outerGrid.RowSpacing   = 0;

            % ---- Toolbar --------------------------------------------
            createToolbar(app, outerGrid);

            % ---- Body (left | center | right) -----------------------
            app.BodyGrid = uigridlayout(outerGrid, [1 3]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {200, '1x', 220};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;

            createLeftPanel(app);
            createCenterPanel(app);
            createRightPanel(app);

            % ---- Bottom status bar ----------------------------------
            createBottomBar(app, outerGrid);
        end

        % -----------------------------------------------------------------
        function createMenus(app)
            % FILE --------------------------------------------------------
            app.FileMenu = uimenu(app.UIFigure, 'Text', 'File');
            uimenu(app.FileMenu, 'Text', 'Load Study (DICOM)...', ...
                'Accelerator', 'O', ...
                'MenuSelectedFcn', @(~,~) app.LoadStudyCallback());
            uimenu(app.FileMenu, 'Text', 'Load Study List (.csv)...', ...
                'MenuSelectedFcn', @(~,~) app.LoadStudyListCallback());
            uimenu(app.FileMenu, 'Text', 'Save Session...', ...
                'Separator', 'on', 'Accelerator', 'S', ...
                'MenuSelectedFcn', @(~,~) app.SaveSessionCallback());
            uimenu(app.FileMenu, 'Text', 'Load Session...', ...
                'MenuSelectedFcn', @(~,~) app.LoadSessionCallback());
            uimenu(app.FileMenu, 'Text', 'Exit', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.CloseFcn());

            % PROCESS -----------------------------------------------------
            app.ProcessMenu = uimenu(app.UIFigure, 'Text', 'Process');
            uimenu(app.ProcessMenu, 'Text', 'Run All Stages (Batch)', ...
                'Accelerator', 'R', ...
                'MenuSelectedFcn', @(~,~) app.RunAllStagesCallback());
            uimenu(app.ProcessMenu, 'Text', '─────────', 'Enable', 'off');
            uimenu(app.ProcessMenu, 'Text', 'Stage 1 — Sequence Recognition & Harmonization', ...
                'MenuSelectedFcn', @(~,~) app.RunStage1Callback());
            uimenu(app.ProcessMenu, 'Text', 'Stage 2 — AI Organ Segmentation', ...
                'MenuSelectedFcn', @(~,~) app.RunStage2Callback());
            uimenu(app.ProcessMenu, 'Text', 'Stage 3 — Feature Extraction', ...
                'MenuSelectedFcn', @(~,~) app.RunStage3Callback());
            uimenu(app.ProcessMenu, 'Text', 'Stage 4 — Technical QC', ...
                'MenuSelectedFcn', @(~,~) app.RunQCCallback());

            % SEGMENTATION ------------------------------------------------
            app.SegmentationMenu = uimenu(app.UIFigure, 'Text', 'Segmentation');
            uimenu(app.SegmentationMenu, 'Text', 'Edit Liver Mask', ...
                'MenuSelectedFcn', @(~,~) app.EditMaskCallback('liver'));
            uimenu(app.SegmentationMenu, 'Text', 'Edit Spleen Mask', ...
                'MenuSelectedFcn', @(~,~) app.EditMaskCallback('spleen'));
            uimenu(app.SegmentationMenu, 'Text', 'Edit Muscle Mask', ...
                'MenuSelectedFcn', @(~,~) app.EditMaskCallback('muscle'));
            uimenu(app.SegmentationMenu, 'Text', 'Edit SAT Mask', ...
                'MenuSelectedFcn', @(~,~) app.EditMaskCallback('SAT'));
            uimenu(app.SegmentationMenu, 'Text', 'Accept All Masks', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.AcceptAllMasksCallback());
            uimenu(app.SegmentationMenu, 'Text', 'Reset Masks for This Study', ...
                'MenuSelectedFcn', @(~,~) app.ResetMasksCallback());

            % FEATURES ----------------------------------------------------
            app.FeaturesMenu = uimenu(app.UIFigure, 'Text', 'Features');
            uimenu(app.FeaturesMenu, 'Text', 'View Full Feature Table', ...
                'MenuSelectedFcn', @(~,~) app.ViewFeatureTableCallback());
            uimenu(app.FeaturesMenu, 'Text', 'Plot Stiffness Histogram', ...
                'MenuSelectedFcn', @(~,~) app.PlotStiffnessHistCallback());
            uimenu(app.FeaturesMenu, 'Text', 'Plot PDFF Distribution', ...
                'MenuSelectedFcn', @(~,~) app.PlotPDFFDistCallback());
            uimenu(app.FeaturesMenu, 'Text', 'Plot Stiffness Heterogeneity Map', ...
                'MenuSelectedFcn', @(~,~) app.PlotHetMapCallback());
            uimenu(app.FeaturesMenu, 'Text', 'Cross-Organ Ratio Summary', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.CrossOrganSummaryCallback());

            % L1-L2 ------------------------------------------------------
            app.L12Menu = uimenu(app.UIFigure, 'Text', 'L1–L2');
            uimenu(app.L12Menu, 'Text', 'Auto-Locate L1–L2 in Scout', ...
                'MenuSelectedFcn', @(~,~) app.L12LocateCallback());
            uimenu(app.L12Menu, 'Text', 'Manual Landmark Adjustment', ...
                'MenuSelectedFcn', @(~,~) app.L12ManualAdjustCallback());
            uimenu(app.L12Menu, 'Text', 'Propagate to Dixon + MRE', ...
                'MenuSelectedFcn', @(~,~) app.L12PropagateCallback());
            uimenu(app.L12Menu, 'Text', 'Measure Muscle + SAT Area', ...
                'MenuSelectedFcn', @(~,~) app.L12MeasureCallback());
            uimenu(app.L12Menu, 'Text', 'L1–L2 Summary Report', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.L12ReportCallback());

            % QC ----------------------------------------------------------
            app.QCMenu = uimenu(app.UIFigure, 'Text', 'QC');
            uimenu(app.QCMenu, 'Text', 'Run All QC Checks', ...
                'MenuSelectedFcn', @(~,~) app.RunQCCallback());
            uimenu(app.QCMenu, 'Text', 'Flag Study for Manual Review', ...
                'MenuSelectedFcn', @(~,~) app.FlagStudyCallback());
            uimenu(app.QCMenu, 'Text', 'Unflag Study', ...
                'MenuSelectedFcn', @(~,~) app.UnflagStudyCallback());
            uimenu(app.QCMenu, 'Text', 'QC Summary — All Studies', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.QCSummaryCallback());
            uimenu(app.QCMenu, 'Text', 'Reproducibility Report', ...
                'MenuSelectedFcn', @(~,~) app.ReproducibilityReportCallback());

            % REGISTRATION -----------------------------------------------
            app.RegistrationMenu = uimenu(app.UIFigure, 'Text', 'Registration');
            uimenu(app.RegistrationMenu, 'Text', 'Dixon → MRE  (Rigid)', ...
                'MenuSelectedFcn', @(~,~) app.RegisterDixonMRECallback('rigid'));
            uimenu(app.RegistrationMenu, 'Text', 'Dixon → MRE  (Deformable)', ...
                'MenuSelectedFcn', @(~,~) app.RegisterDixonMRECallback('deformable'));
            uimenu(app.RegistrationMenu, 'Text', 'Scout → Dixon  (L1–L2 propagation)', ...
                'MenuSelectedFcn', @(~,~) app.RegisterScoutDixonCallback());
            uimenu(app.RegistrationMenu, 'Text', 'Check Registration Overlay', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.CheckRegistrationCallback());

            % EXPORT ------------------------------------------------------
            app.ExportMenu = uimenu(app.UIFigure, 'Text', 'Export');
            uimenu(app.ExportMenu, 'Text', 'Export Features (CSV)...', ...
                'Accelerator', 'E', ...
                'MenuSelectedFcn', @(~,~) app.ExportCSVCallback());
            uimenu(app.ExportMenu, 'Text', 'Export Subject Report (PDF)...', ...
                'MenuSelectedFcn', @(~,~) app.ExportPDFCallback());
            uimenu(app.ExportMenu, 'Text', 'Export Segmentation Masks (NIfTI)...', ...
                'MenuSelectedFcn', @(~,~) app.ExportMasksCallback());
            uimenu(app.ExportMenu, 'Text', 'Export Platform Config (JSON)...', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.ExportConfigCallback());

            % HELP --------------------------------------------------------
            app.HelpMenu = uimenu(app.UIFigure, 'Text', 'Help');
            uimenu(app.HelpMenu, 'Text', 'Platform Documentation', ...
                'MenuSelectedFcn', @(~,~) app.OpenDocCallback());
            uimenu(app.HelpMenu, 'Text', 'Feature Definitions', ...
                'MenuSelectedFcn', @(~,~) app.FeatureDefsCallback());
            uimenu(app.HelpMenu, 'Text', 'About', ...
                'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) app.AboutCallback());
        end

        % -----------------------------------------------------------------
        function createToolbar(app, parentGrid)
            app.ToolbarPanel = uipanel(parentGrid);
            app.ToolbarPanel.Layout.Row    = 1;
            app.ToolbarPanel.Layout.Column = 1;
            app.ToolbarPanel.BorderType    = 'none';
            app.ToolbarPanel.BackgroundColor = [0.95 0.95 0.95];

            tg = uigridlayout(app.ToolbarPanel, [1 10]);
            tg.ColumnWidth  = {110, 90, 90, 90, 80, 90, 8, 100, 90, '1x'};
            tg.RowHeight    = {'1x'};
            tg.Padding      = [6 6 6 6];
            tg.ColumnSpacing = 4;

            % Load Study
            app.BtnLoadStudy = uibutton(tg, 'push');
            app.BtnLoadStudy.Layout.Column     = 1;
            app.BtnLoadStudy.Text              = '📂  Load Study';
            app.BtnLoadStudy.FontSize          = 12;
            app.BtnLoadStudy.BackgroundColor   = [0.20 0.45 0.75];
            app.BtnLoadStudy.FontColor         = [1 1 1];
            app.BtnLoadStudy.ButtonPushedFcn   = @(~,~) app.LoadStudyCallback();
            app.BtnLoadStudy.Tooltip           = 'Load a DICOM study folder';

            % Run Stage 1
            app.BtnRunStage1 = uibutton(tg, 'push');
            app.BtnRunStage1.Layout.Column   = 2;
            app.BtnRunStage1.Text            = 'Stage 1';
            app.BtnRunStage1.Tooltip         = 'Sequence recognition & harmonization';
            app.BtnRunStage1.ButtonPushedFcn = @(~,~) app.RunStage1Callback();

            % Run Stage 2
            app.BtnRunStage2 = uibutton(tg, 'push');
            app.BtnRunStage2.Layout.Column   = 3;
            app.BtnRunStage2.Text            = 'Stage 2';
            app.BtnRunStage2.Tooltip         = 'AI organ segmentation';
            app.BtnRunStage2.ButtonPushedFcn = @(~,~) app.RunStage2Callback();

            % Run Stage 3
            app.BtnRunStage3 = uibutton(tg, 'push');
            app.BtnRunStage3.Layout.Column   = 4;
            app.BtnRunStage3.Text            = 'Stage 3';
            app.BtnRunStage3.Tooltip         = 'Automated feature extraction';
            app.BtnRunStage3.ButtonPushedFcn = @(~,~) app.RunStage3Callback();

            % Run QC
            app.BtnRunQC = uibutton(tg, 'push');
            app.BtnRunQC.Layout.Column   = 5;
            app.BtnRunQC.Text            = 'QC';
            app.BtnRunQC.Tooltip         = 'Technical quality control';
            app.BtnRunQC.ButtonPushedFcn = @(~,~) app.RunQCCallback();

            % L1-L2 Locate
            app.BtnL12Locate = uibutton(tg, 'push');
            app.BtnL12Locate.Layout.Column   = 6;
            app.BtnL12Locate.Text            = 'L1–L2 Locate';
            app.BtnL12Locate.Tooltip         = 'Auto-locate L1-L2 vertebral levels in Scout';
            app.BtnL12Locate.BackgroundColor = [0.55 0.27 0.07];
            app.BtnL12Locate.FontColor       = [1 1 1];
            app.BtnL12Locate.ButtonPushedFcn = @(~,~) app.L12LocateCallback();

            % Separator (empty label)
            sep = uilabel(tg);
            sep.Layout.Column = 7;
            sep.Text = '│';
            sep.FontColor = [0.7 0.7 0.7];
            sep.HorizontalAlignment = 'center';

            % Run All
            app.BtnRunAll = uibutton(tg, 'push');
            app.BtnRunAll.Layout.Column   = 8;
            app.BtnRunAll.Text            = '▶  Run All';
            app.BtnRunAll.Tooltip         = 'Run all pipeline stages sequentially';
            app.BtnRunAll.BackgroundColor = [0.18 0.62 0.36];
            app.BtnRunAll.FontColor       = [1 1 1];
            app.BtnRunAll.FontWeight      = 'bold';
            app.BtnRunAll.ButtonPushedFcn = @(~,~) app.RunAllStagesCallback();

            % Export CSV
            app.BtnExportCSV = uibutton(tg, 'push');
            app.BtnExportCSV.Layout.Column   = 9;
            app.BtnExportCSV.Text            = '⬇  Export CSV';
            app.BtnExportCSV.Tooltip         = 'Export all features to CSV';
            app.BtnExportCSV.ButtonPushedFcn = @(~,~) app.ExportCSVCallback();
        end

        % -----------------------------------------------------------------
        function createLeftPanel(app)
            app.LeftPanel = uipanel(app.BodyGrid);
            app.LeftPanel.Layout.Row    = 1;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Title         = 'Study Browser';
            app.LeftPanel.FontWeight    = 'bold';
            app.LeftPanel.BorderType    = 'line';

            app.LeftGrid = uigridlayout(app.LeftPanel, [2 1]);
            app.LeftGrid.RowHeight    = {'1x', 40};
            app.LeftGrid.ColumnWidth  = {'1x'};
            app.LeftGrid.Padding      = [4 4 4 4];
            app.LeftGrid.RowSpacing   = 4;

            % Study tree
            app.StudyTree = uitree(app.LeftGrid, 'checkbox');
            app.StudyTree.Layout.Row    = 1;
            app.StudyTree.Layout.Column = 1;
            app.StudyTree.SelectionChangedFcn = @(~,e) app.StudySelectionCallback(e);

            % Populate tree with placeholder nodes (replaced on load)
            siteNode = uitreenode(app.StudyTree, ...
                'Text', 'Site: Mayo Clinic', ...
                'NodeData', struct('type','site','name','Mayo'));
            s1 = uitreenode(siteNode, 'Text', 'Subject 001');
            uitreenode(s1, 'Text', 'Session 2024-03  [pending]', ...
                'NodeData', struct('type','session','id','001-2024-03'));
            uitreenode(s1, 'Text', 'Session 2024-09  [pending]', ...
                'NodeData', struct('type','session','id','001-2024-09'));
            expand(siteNode);
            expand(s1);

            % Stats label
            app.LblStudyStats = uilabel(app.LeftGrid);
            app.LblStudyStats.Layout.Row    = 2;
            app.LblStudyStats.Layout.Column = 1;
            app.LblStudyStats.Text          = 'Loaded: 0 / 0  |  Flagged: 0';
            app.LblStudyStats.FontSize      = 10;
            app.LblStudyStats.FontColor     = [0.5 0.5 0.5];
            app.LblStudyStats.HorizontalAlignment = 'center';
        end

        % -----------------------------------------------------------------
        function createCenterPanel(app)
            app.CenterPanel = uipanel(app.BodyGrid);
            app.CenterPanel.Layout.Row    = 1;
            app.CenterPanel.Layout.Column = 2;
            app.CenterPanel.BorderType    = 'none';

            app.CenterGrid = uigridlayout(app.CenterPanel, [2 1]);
            app.CenterGrid.RowHeight   = {'1x', 44};
            app.CenterGrid.ColumnWidth = {'1x'};
            app.CenterGrid.Padding     = [0 0 0 0];
            app.CenterGrid.RowSpacing  = 0;

            % Tab group
            app.ImageTabGroup = uitabgroup(app.CenterGrid);
            app.ImageTabGroup.Layout.Row    = 1;
            app.ImageTabGroup.Layout.Column = 1;
            app.ImageTabGroup.SelectionChangedFcn = @(~,e) app.TabChangedCallback(e);

            createScoutTab(app);
            createDixonTab(app);
            createMRETab(app);
            createL12Tab(app);
            createOverlayTab(app);

            % Image controls below tabs
            createImageControls(app);
        end

        % --- Scout tab ---------------------------------------------------
        function createScoutTab(app)
            app.ScoutTab = uitab(app.ImageTabGroup, 'Title', '3-Plane Scout');

            app.ScoutGrid = uigridlayout(app.ScoutTab, [1 3]);
            app.ScoutGrid.ColumnWidth  = {'1x','1x','1x'};
            app.ScoutGrid.RowHeight    = {'1x'};
            app.ScoutGrid.Padding      = [4 4 4 4];
            app.ScoutGrid.ColumnSpacing = 6;

            app.AxScoutAxial = uiaxes(app.ScoutGrid);
            app.AxScoutAxial.Layout.Column = 1;
            setupImageAxes(app, app.AxScoutAxial, 'Axial');

            app.AxScoutCoronal = uiaxes(app.ScoutGrid);
            app.AxScoutCoronal.Layout.Column = 2;
            setupImageAxes(app, app.AxScoutCoronal, 'Coronal');

            app.AxScoutSagittal = uiaxes(app.ScoutGrid);
            app.AxScoutSagittal.Layout.Column = 3;
            setupImageAxes(app, app.AxScoutSagittal, 'Sagittal');
        end

        % --- Dixon tab ---------------------------------------------------
        function createDixonTab(app)
            app.DixonTab = uitab(app.ImageTabGroup, 'Title', 'Dixon MRI');

            app.DixonGrid = uigridlayout(app.DixonTab, [1 4]);
            app.DixonGrid.ColumnWidth  = {'1x','1x','1x','1x'};
            app.DixonGrid.RowHeight    = {'1x'};
            app.DixonGrid.Padding      = [4 4 4 4];
            app.DixonGrid.ColumnSpacing = 6;

            app.AxDixonWater = uiaxes(app.DixonGrid);
            app.AxDixonWater.Layout.Column = 1;
            setupImageAxes(app, app.AxDixonWater, 'Water');

            app.AxDixonFat = uiaxes(app.DixonGrid);
            app.AxDixonFat.Layout.Column = 2;
            setupImageAxes(app, app.AxDixonFat, 'Fat');

            app.AxDixonFF = uiaxes(app.DixonGrid);
            app.AxDixonFF.Layout.Column = 3;
            setupImageAxes(app, app.AxDixonFF, 'Fat Fraction (%)');

            app.AxDixonInPhase = uiaxes(app.DixonGrid);
            app.AxDixonInPhase.Layout.Column = 4;
            setupImageAxes(app, app.AxDixonInPhase, 'In-Phase');
        end

        % --- MRE tab -----------------------------------------------------
        function createMRETab(app)
            app.MRETab = uitab(app.ImageTabGroup, 'Title', '2D MRE');

            app.MREGrid = uigridlayout(app.MRETab, [1 3]);
            app.MREGrid.ColumnWidth  = {'1x','1x','1x'};
            app.MREGrid.RowHeight    = {'1x'};
            app.MREGrid.Padding      = [4 4 4 4];
            app.MREGrid.ColumnSpacing = 6;

            app.AxMREMagnitude = uiaxes(app.MREGrid);
            app.AxMREMagnitude.Layout.Column = 1;
            setupImageAxes(app, app.AxMREMagnitude, 'MRE Magnitude');

            app.AxMREStiffness = uiaxes(app.MREGrid);
            app.AxMREStiffness.Layout.Column = 2;
            setupImageAxes(app, app.AxMREStiffness, 'Stiffness Map (kPa)');
            colormap(app.AxMREStiffness, 'jet');

            app.AxMREWave = uiaxes(app.MREGrid);
            app.AxMREWave.Layout.Column = 3;
            setupImageAxes(app, app.AxMREWave, 'Wave Image');
        end

        % --- L1-L2 tab ---------------------------------------------------
        function createL12Tab(app)
            app.L12Tab = uitab(app.ImageTabGroup, 'Title', 'L1–L2 View');

            app.L12Grid = uigridlayout(app.L12Tab, [1 2]);
            app.L12Grid.ColumnWidth  = {'1x','1x'};
            app.L12Grid.RowHeight    = {'1x'};
            app.L12Grid.Padding      = [4 4 4 4];
            app.L12Grid.ColumnSpacing = 6;

            app.AxL12Axial = uiaxes(app.L12Grid);
            app.AxL12Axial.Layout.Column = 1;
            setupImageAxes(app, app.AxL12Axial, 'Axial — L1 level');

            app.AxL12Coronal = uiaxes(app.L12Grid);
            app.AxL12Coronal.Layout.Column = 2;
            setupImageAxes(app, app.AxL12Coronal, 'Coronal — L1–L2 span');
        end

        % --- Overlay tab -------------------------------------------------
        function createOverlayTab(app)
            app.OverlayTab = uitab(app.ImageTabGroup, 'Title', 'Overlay / Fusion');

            app.OverlayGrid = uigridlayout(app.OverlayTab, [1 2]);
            app.OverlayGrid.ColumnWidth  = {'1x','1x'};
            app.OverlayGrid.RowHeight    = {'1x'};
            app.OverlayGrid.Padding      = [4 4 4 4];
            app.OverlayGrid.ColumnSpacing = 6;

            app.AxOverlayDixon = uiaxes(app.OverlayGrid);
            app.AxOverlayDixon.Layout.Column = 1;
            setupImageAxes(app, app.AxOverlayDixon, 'Dixon (reference)');

            app.AxOverlayMRE = uiaxes(app.OverlayGrid);
            app.AxOverlayMRE.Layout.Column = 2;
            setupImageAxes(app, app.AxOverlayMRE, 'MRE (registered)');
        end

        % --- Shared axes setup ------------------------------------------
        function setupImageAxes(~, ax, titleStr)
            ax.XTick = [];
            ax.YTick = [];
            ax.Box   = 'on';
            ax.Color = [0 0 0];
            ax.XColor = [0.4 0.4 0.4];
            ax.YColor = [0.4 0.4 0.4];
            title(ax, titleStr, 'FontSize', 10, 'Color', [0.85 0.85 0.85], ...
                'FontWeight', 'normal');
            colormap(ax, 'gray');
        end

        % --- Image controls below the tab group -------------------------
        function createImageControls(app)
            app.ControlPanel = uipanel(app.CenterGrid);
            app.ControlPanel.Layout.Row    = 2;
            app.ControlPanel.Layout.Column = 1;
            app.ControlPanel.BorderType    = 'line';
            app.ControlPanel.BackgroundColor = [0.94 0.94 0.94];

            app.ControlGrid = uigridlayout(app.ControlPanel, [1 8]);
            app.ControlGrid.ColumnWidth  = {95, 80, 110, 80, 8, 70, 120, '1x'};
            app.ControlGrid.RowHeight    = {'1x'};
            app.ControlGrid.Padding      = [4 4 4 4];
            app.ControlGrid.ColumnSpacing = 4;

            % Toggle overlay buttons
            app.BtnSegOverlay = uibutton(app.ControlGrid, 'state');
            app.BtnSegOverlay.Layout.Column = 1;
            app.BtnSegOverlay.Text          = 'Seg. overlay';
            app.BtnSegOverlay.Value         = false;
            app.BtnSegOverlay.Tooltip       = 'Show segmentation contours';
            app.BtnSegOverlay.ValueChangedFcn = @(~,~) app.ToggleOverlayCallback('seg');

            app.BtnL12Lines = uibutton(app.ControlGrid, 'state');
            app.BtnL12Lines.Layout.Column = 2;
            app.BtnL12Lines.Text          = 'L1–L2 lines';
            app.BtnL12Lines.Value         = false;
            app.BtnL12Lines.Tooltip       = 'Show L1 and L2 level lines';
            app.BtnL12Lines.ValueChangedFcn = @(~,~) app.ToggleOverlayCallback('l12');

            app.BtnStiffnessMap = uibutton(app.ControlGrid, 'state');
            app.BtnStiffnessMap.Layout.Column = 3;
            app.BtnStiffnessMap.Text          = 'Stiffness overlay';
            app.BtnStiffnessMap.Value         = false;
            app.BtnStiffnessMap.Tooltip       = 'Overlay stiffness colormap';
            app.BtnStiffnessMap.ValueChangedFcn = @(~,~) app.ToggleOverlayCallback('stiffness');

            app.BtnPDFFMap = uibutton(app.ControlGrid, 'state');
            app.BtnPDFFMap.Layout.Column = 4;
            app.BtnPDFFMap.Text          = 'PDFF overlay';
            app.BtnPDFFMap.Value         = false;
            app.BtnPDFFMap.Tooltip       = 'Overlay fat fraction colormap';
            app.BtnPDFFMap.ValueChangedFcn = @(~,~) app.ToggleOverlayCallback('pdff');

            % Separator
            sep = uilabel(app.ControlGrid);
            sep.Layout.Column = 5;
            sep.Text = '│';
            sep.HorizontalAlignment = 'center';
            sep.FontColor = [0.7 0.7 0.7];

            % Colormap selector
            app.DropColormap = uidropdown(app.ControlGrid);
            app.DropColormap.Layout.Column = 6;
            app.DropColormap.Items         = {'gray','jet','hot','parula','bone'};
            app.DropColormap.Value         = 'gray';
            app.DropColormap.Tooltip       = 'Image colormap';
            app.DropColormap.ValueChangedFcn = @(~,e) app.ColormapChangedCallback(e);

            % Slice slider
            app.SldrSlice = uislider(app.ControlGrid);
            app.SldrSlice.Layout.Column = 7;
            app.SldrSlice.Limits        = [1 100];
            app.SldrSlice.Value         = 1;
            app.SldrSlice.MajorTicks    = [];
            app.SldrSlice.MinorTicks    = [];
            app.SldrSlice.Tooltip       = 'Navigate slices';
            app.SldrSlice.ValueChangedFcn = @(~,e) app.SliceChangedCallback(e);

            % Image info label
            app.LblImageInfo = uilabel(app.ControlGrid);
            app.LblImageInfo.Layout.Column = 8;
            app.LblImageInfo.Text          = 'No study loaded';
            app.LblImageInfo.FontSize      = 10;
            app.LblImageInfo.FontColor     = [0.5 0.5 0.5];
        end

        % -----------------------------------------------------------------
        function createRightPanel(app)
            app.RightPanel = uipanel(app.BodyGrid);
            app.RightPanel.Layout.Row    = 1;
            app.RightPanel.Layout.Column = 3;
            app.RightPanel.Title         = 'Feature Results';
            app.RightPanel.FontWeight    = 'bold';

            app.RightGrid = uigridlayout(app.RightPanel, [5 1]);
            app.RightGrid.RowHeight    = {110, 100, 110, 130, 100};
            app.RightGrid.ColumnWidth  = {'1x'};
            app.RightGrid.Padding      = [2 2 2 2];
            app.RightGrid.RowSpacing   = 2;

            createFeatureSection(app, app.RightGrid, 1, ...
                'Organ size & composition', ...
                {'Liver vol.','Spleen vol.','Liver:spleen ratio','Liver PDFF'}, ...
                {'—','—','—','—'}, ...
                {'LiverVol','SpleenVol','LSRatio','LiverPDFF'});

            createFeatureSection(app, app.RightGrid, 2, ...
                'Mechanical (MRE)', ...
                {'Liver stiffness','Spleen stiffness','Stiff. ratio','Het. IQR'}, ...
                {'—','—','—','—'}, ...
                {'LiverStiff','SpleenStiff','StiffRatio','HetIQR'});

            createFeatureSection(app, app.RightGrid, 3, ...
                'Body composition', ...
                {'Muscle area','SAT area','Muscle:fat ratio','Muscle PDFF'}, ...
                {'—','—','—','—'}, ...
                {'MuscleArea','SATArea','MuscleFatRatio','MusclePDFF'});

            createFeatureSection(app, app.RightGrid, 4, ...
                'L1–L2 measures', ...
                {'L1 located','L2 located','Muscle area L1–L2', ...
                 'SAT area L1–L2','Muscle:fat L1–L2','PDFF at L1–L2'}, ...
                {'—','—','—','—','—','—'}, ...
                {'L1Status','L2Status','L12MuscleArea', ...
                 'L12SATArea','L12MuscleFat','L12PDFF'});

            createFeatureSection(app, app.RightGrid, 5, ...
                'QC status', ...
                {'Seg. confidence','Coverage check','Range check','Manual review'}, ...
                {'—','—','—','—'}, ...
                {'SegConf','Coverage','RangeCheck','ManualReview'});
        end

        % --- Generic feature section builder ----------------------------
        function createFeatureSection(app, parentGrid, row, title, labels, defaults, propNames)
            pnl = uipanel(parentGrid);
            pnl.Layout.Row    = row;
            pnl.Layout.Column = 1;
            pnl.Title         = title;
            pnl.FontSize      = 10;
            pnl.FontWeight    = 'bold';

            n   = numel(labels);
            g   = uigridlayout(pnl, [n 2]);
            g.ColumnWidth  = {'1x', '1x'};
            g.RowHeight    = repmat({18}, 1, n);
            g.Padding      = [4 2 4 2];
            g.ColumnSpacing = 4;
            g.RowSpacing    = 1;

            for k = 1:n
                lbl = uilabel(g);
                lbl.Layout.Row    = k;
                lbl.Layout.Column = 1;
                lbl.Text          = labels{k};
                lbl.FontSize      = 10;
                lbl.FontColor     = [0.45 0.45 0.45];

                val = uilabel(g);
                val.Layout.Row    = k;
                val.Layout.Column = 2;
                val.Text          = defaults{k};
                val.FontSize      = 10;
                val.FontWeight    = 'bold';
                val.HorizontalAlignment = 'right';

                % Store handle in app property by name
                app.(['Val' propNames{k}]) = val;
                app.(['Lbl' propNames{k}]) = lbl;
            end
        end

        % -----------------------------------------------------------------
        function createBottomBar(app, parentGrid)
            app.BottomPanel = uipanel(parentGrid);
            app.BottomPanel.Layout.Row    = 3;
            app.BottomPanel.Layout.Column = 1;
            app.BottomPanel.BorderType    = 'line';
            app.BottomPanel.BackgroundColor = [0.93 0.93 0.93];

            app.BottomGrid = uigridlayout(app.BottomPanel, [2 7]);
            app.BottomGrid.RowHeight    = {'1x', 18};
            app.BottomGrid.ColumnWidth  = {'1x','1x','1x','1x',8,'1x','2x'};
            app.BottomGrid.Padding      = [6 4 6 4];
            app.BottomGrid.ColumnSpacing = 4;
            app.BottomGrid.RowSpacing    = 2;

            stageLabels  = {'S1  Harmonize', 'S2  Segment', 'S3  Features', 'S4  QC'};
            stageProps   = {'Stage1Status','Stage2Status','Stage3Status','Stage4Status'};
            stageCBs     = {@(~,~)app.RunStage1Callback(), ...
                            @(~,~)app.RunStage2Callback(), ...
                            @(~,~)app.RunStage3Callback(), ...
                            @(~,~)app.RunQCCallback()};

            for k = 1:4
                btn = uibutton(app.BottomGrid, 'push');
                btn.Layout.Row    = 1;
                btn.Layout.Column = k;
                btn.Text          = stageLabels{k};
                btn.FontSize      = 10;
                btn.BackgroundColor = [0.82 0.82 0.82];
                btn.Tooltip       = ['Run ' stageLabels{k}];
                btn.ButtonPushedFcn = stageCBs{k};
                app.(stageProps{k}) = btn;
            end

            % Separator
            sep = uilabel(app.BottomGrid);
            sep.Layout.Row    = 1;
            sep.Layout.Column = 5;
            sep.Text = '│';
            sep.HorizontalAlignment = 'center';
            sep.FontColor = [0.6 0.6 0.6];

            % L1-L2 button
            app.BtnL12Status = uibutton(app.BottomGrid, 'push');
            app.BtnL12Status.Layout.Row    = 1;
            app.BtnL12Status.Layout.Column = 6;
            app.BtnL12Status.Text          = 'L1–L2  Module';
            app.BtnL12Status.FontSize      = 10;
            app.BtnL12Status.BackgroundColor = [0.82 0.70 0.55];
            app.BtnL12Status.ButtonPushedFcn = @(~,~) app.L12LocateCallback();

            % Status message (spans whole second row)
            app.LblStatusMsg = uilabel(app.BottomGrid);
            app.LblStatusMsg.Layout.Row    = 2;
            app.LblStatusMsg.Layout.Column = [1 7];
            app.LblStatusMsg.Text          = '●  Ready — no study loaded';
            app.LblStatusMsg.FontSize      = 10;
            app.LblStatusMsg.FontColor     = [0.4 0.4 0.4];
        end

    end % private methods (createComponents)

    % =====================================================================
    %  INITIALIZATION
    % =====================================================================
    methods (Access = private)

        function startupFcn(app)
            % Called after createComponents — set initial state.
            updatePipelineStatus(app, 'S1', 'idle');
            updatePipelineStatus(app, 'S2', 'idle');
            updatePipelineStatus(app, 'S3', 'idle');
            updatePipelineStatus(app, 'S4', 'idle');
            updatePipelineStatus(app, 'L12','idle');
            setStatus(app, 'Ready — please load a study to begin.');
        end

    end

    % =====================================================================
    %  CALLBACK STUBS  (filled in by later phases)
    % =====================================================================
    methods (Access = public)

        % --- File / I-O --------------------------------------------------
        function LoadStudyCallback(app)
            % PHASE 2: Open DICOM folder, identify Scout / Dixon / MRE
            % series, populate AppData, refresh tree and image axes.
            setStatus(app, '[Phase 2] LoadStudyCallback — not yet implemented.');
        end

        function LoadStudyListCallback(app)
            % PHASE 2: Load a CSV of study folder paths for batch processing.
            setStatus(app, '[Phase 2] LoadStudyListCallback — not yet implemented.');
        end

        function SaveSessionCallback(app)
            % Save AppData to a .mat file.
            setStatus(app, '[Phase 7] SaveSessionCallback — not yet implemented.');
        end

        function LoadSessionCallback(app)
            % Restore AppData from a previously saved .mat file.
            setStatus(app, '[Phase 7] LoadSessionCallback — not yet implemented.');
        end

        % --- Pipeline stages ---------------------------------------------
        function RunAllStagesCallback(app)
            % Run stages 1-4 plus L1-L2 module sequentially.
            setStatus(app, 'Running all stages…');
            RunStage1Callback(app);
            RunStage2Callback(app);
            L12LocateCallback(app);
            RunStage3Callback(app);
            RunQCCallback(app);
        end

        function RunStage1Callback(app)
            % PHASE 2: Sequence recognition, DICOM metadata parsing,
            % voxel-size harmonization, spatial alignment of Scout/Dixon/MRE.
            updatePipelineStatus(app, 'S1', 'running');
            setStatus(app, '[Phase 2] Stage 1 — Harmonization running…');
            % TODO: call harmonizeSequences(app)
            updatePipelineStatus(app, 'S1', 'idle');
        end

        function RunStage2Callback(app)
            % PHASE 4: AI-assisted organ segmentation:
            %   liver, spleen, abdominal muscle groups, SAT.
            % Also performs Dixon→MRE co-registration.
            updatePipelineStatus(app, 'S2', 'running');
            setStatus(app, '[Phase 4] Stage 2 — Segmentation running…');
            % TODO: call segmentOrgans(app)
            updatePipelineStatus(app, 'S2', 'idle');
        end

        function RunStage3Callback(app)
            % PHASE 5: Extract all pre-specified quantitative phenotypes:
            %   organ volumes, PDFF, mean stiffness, ratios,
            %   body-composition measures, spatial heterogeneity.
            updatePipelineStatus(app, 'S3', 'running');
            setStatus(app, '[Phase 5] Stage 3 — Feature extraction running…');
            % TODO: call extractFeatures(app)
            updatePipelineStatus(app, 'S3', 'idle');
        end

        function RunQCCallback(app)
            % PHASE 6: Compute confidence scores, coverage checks,
            % range checks; flag studies for manual review.
            updatePipelineStatus(app, 'S4', 'running');
            setStatus(app, '[Phase 6] Stage 4 — QC running…');
            % TODO: call runQualityControl(app)
            updatePipelineStatus(app, 'S4', 'idle');
        end

        % --- L1-L2 module ------------------------------------------------
        function L12LocateCallback(app)
            % PHASE 3: Auto-detect L1 and L2 vertebral levels in 3D Scout.
            updatePipelineStatus(app, 'L12', 'running');
            setStatus(app, '[Phase 3] L1–L2 — Vertebral localization running…');
            % TODO: call localizeL1L2(app)
            updatePipelineStatus(app, 'L12', 'idle');
        end

        function L12ManualAdjustCallback(app)
            % PHASE 3: Allow user to drag L1/L2 level lines interactively.
            setStatus(app, '[Phase 3] L12ManualAdjustCallback — not yet implemented.');
        end

        function L12PropagateCallback(app)
            % PHASE 3: Propagate Scout L1-L2 landmarks to Dixon and MRE
            % via rigid registration transform.
            setStatus(app, '[Phase 3] L12PropagateCallback — not yet implemented.');
        end

        function L12MeasureCallback(app)
            % PHASE 5: Measure muscle area, SAT area, muscle:fat ratio,
            % and PDFF at L1-L2 level on Dixon images.
            setStatus(app, '[Phase 5] L12MeasureCallback — not yet implemented.');
        end

        function L12ReportCallback(app)
            % PHASE 7: Generate and display L1-L2 summary table.
            setStatus(app, '[Phase 7] L12ReportCallback — not yet implemented.');
        end

        % --- Segmentation ------------------------------------------------
        function EditMaskCallback(app, organ)
            % PHASE 4: Launch interactive mask editor for specified organ.
            setStatus(app, sprintf('[Phase 4] EditMaskCallback (%s) — not yet implemented.', organ));
        end

        function AcceptAllMasksCallback(app)
            setStatus(app, '[Phase 4] AcceptAllMasksCallback — not yet implemented.');
        end

        function ResetMasksCallback(app)
            app.AppData.LiverMask  = [];
            app.AppData.SpleenMask = [];
            app.AppData.MuscleMask = [];
            app.AppData.SATMask    = [];
            setStatus(app, 'Masks cleared for active study.');
        end

        % --- Registration ------------------------------------------------
        function RegisterDixonMRECallback(app, mode)
            % PHASE 3: Register Dixon to MRE using rigid or deformable transform.
            setStatus(app, sprintf('[Phase 3] RegisterDixonMRE (%s) — not yet implemented.', mode));
        end

        function RegisterScoutDixonCallback(app)
            setStatus(app, '[Phase 3] RegisterScoutDixon — not yet implemented.');
        end

        function CheckRegistrationCallback(app)
            setStatus(app, '[Phase 3] CheckRegistration — not yet implemented.');
        end

        % --- Features / plots --------------------------------------------
        function ViewFeatureTableCallback(app)
            setStatus(app, '[Phase 5] ViewFeatureTable — not yet implemented.');
        end

        function PlotStiffnessHistCallback(app)
            setStatus(app, '[Phase 5] PlotStiffnessHist — not yet implemented.');
        end

        function PlotPDFFDistCallback(app)
            setStatus(app, '[Phase 5] PlotPDFFDist — not yet implemented.');
        end

        function PlotHetMapCallback(app)
            setStatus(app, '[Phase 5] PlotHetMap — not yet implemented.');
        end

        function CrossOrganSummaryCallback(app)
            setStatus(app, '[Phase 5] CrossOrganSummary — not yet implemented.');
        end

        % --- QC ----------------------------------------------------------
        function FlagStudyCallback(app)
            setStatus(app, '[Phase 6] FlagStudy — not yet implemented.');
        end

        function UnflagStudyCallback(app)
            setStatus(app, '[Phase 6] UnflagStudy — not yet implemented.');
        end

        function QCSummaryCallback(app)
            setStatus(app, '[Phase 6] QCSummary — not yet implemented.');
        end

        function ReproducibilityReportCallback(app)
            setStatus(app, '[Phase 6] ReproducibilityReport — not yet implemented.');
        end

        % --- Export ------------------------------------------------------
        function ExportCSVCallback(app)
            % PHASE 7: Write AppData.Features struct to a tidy CSV.
            setStatus(app, '[Phase 7] ExportCSV — not yet implemented.');
        end

        function ExportPDFCallback(app)
            setStatus(app, '[Phase 7] ExportPDF — not yet implemented.');
        end

        function ExportMasksCallback(app)
            setStatus(app, '[Phase 7] ExportMasks (NIfTI) — not yet implemented.');
        end

        function ExportConfigCallback(app)
            setStatus(app, '[Phase 7] ExportConfig (JSON) — not yet implemented.');
        end

        % --- Help --------------------------------------------------------
        function OpenDocCallback(~)
            web('https://github.com/MengYinMayo/HepatosplenicMRE', '-browser');
        end

        function FeatureDefsCallback(app)
            setStatus(app, '[Help] FeatureDefs — not yet implemented.');
        end

        function AboutCallback(~)
            msgbox( ...
                sprintf(['HepatosplenicMRE Analysis Platform\n' ...
                         'Version 1.0  (Phase 1 — GUI skeleton)\n\n' ...
                         'Mayo Clinic / UCSD R01 Collaboration\n' ...
                         'Principal Investigator: Meng Yin, PhD\n\n' ...
                         'Phases 2–7 in development.']), ...
                'About', 'help');
        end

        % --- Image / display ---------------------------------------------
        function StudySelectionCallback(app, event)
            % Update displayed images when a study node is selected.
            node = event.SelectedNodes;
            if isempty(node), return; end
            setStatus(app, sprintf('Selected: %s', node.Text));
            % PHASE 2: load and display images for selected study.
        end

        function TabChangedCallback(app, ~)
            % Refresh slice slider range when tab changes.
            updateSliceSlider(app);
        end

        function SliceChangedCallback(app, event)
            app.AppData.CurrentSlice = round(event.Value);
            app.LblImageInfo.Text    = sprintf('Slice %d', app.AppData.CurrentSlice);
            refreshDisplayedSlice(app);
        end

        function ToggleOverlayCallback(app, type)
            refreshDisplayedSlice(app);
            setStatus(app, sprintf('Overlay toggled: %s', type));
        end

        function ColormapChangedCallback(app, event)
            cm = event.Value;
            for ax = [app.AxScoutAxial, app.AxScoutCoronal, app.AxScoutSagittal, ...
                      app.AxDixonWater, app.AxDixonFat, app.AxDixonInPhase, ...
                      app.AxMREMagnitude, app.AxMREWave, ...
                      app.AxL12Axial, app.AxL12Coronal, ...
                      app.AxOverlayDixon, app.AxOverlayMRE]
                colormap(ax, cm);
            end
        end

        % --- Close -------------------------------------------------------
        function CloseFcn(app)
            selection = uiconfirm(app.UIFigure, ...
                'Close HepatosplenicMRE Platform?', ...
                'Confirm Exit', ...
                'Options', {'Close','Cancel'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption',  'Cancel');
            if strcmp(selection, 'Close')
                delete(app.UIFigure);
            end
        end

    end % public callbacks

    % =====================================================================
    %  HELPER UTILITIES  (internal)
    % =====================================================================
    methods (Access = private)

        function setStatus(app, msg)
            % Update bottom status bar message.
            timestamp = datestr(now, 'HH:MM:SS');
            app.LblStatusMsg.Text = sprintf('●  [%s]  %s', timestamp, msg);
            drawnow limitrate;
        end

        function updatePipelineStatus(app, stage, status)
            % Update pipeline button color based on stage status.
            %   status: 'idle' | 'running' | 'done' | 'error' | 'flagged'
            colorMap = struct( ...
                'idle',    [0.82 0.82 0.82], ...
                'running', [0.98 0.80 0.20], ...
                'done',    [0.22 0.65 0.30], ...
                'error',   [0.80 0.18 0.18], ...
                'flagged', [0.85 0.50 0.10]);

            app.AppData.PipelineStatus.(stage) = status;
            clr = colorMap.(status);

            switch stage
                case 'S1',  btn = app.BtnStage1Status;
                case 'S2',  btn = app.BtnStage2Status;
                case 'S3',  btn = app.BtnStage3Status;
                case 'S4',  btn = app.BtnStage4Status;
                case 'L12', btn = app.BtnL12Status;
                otherwise,  return
            end
            btn.BackgroundColor = clr;
        end

        function updateSliceSlider(app)
            % Set slider max to the number of slices in the active tab.
            tab = app.ImageTabGroup.SelectedTab;
            nSlices = 1;
            if ~isempty(app.AppData.ScoutVolume) && tab == app.ScoutTab
                nSlices = size(app.AppData.ScoutVolume, 3);
            elseif ~isempty(app.AppData.DixonWater) && tab == app.DixonTab
                nSlices = size(app.AppData.DixonWater, 3);
            elseif ~isempty(app.AppData.MREStiffness) && tab == app.MRETab
                nSlices = size(app.AppData.MREStiffness, 3);
            end
            app.SldrSlice.Limits = [1 max(nSlices,2)];
            app.SldrSlice.Value  = min(app.AppData.CurrentSlice, nSlices);
        end

        function refreshDisplayedSlice(app)
            % PHASE 2: Render the current slice + any active overlays.
            % Placeholder: axes are black until images are loaded.
            s = app.AppData.CurrentSlice;
            tab = app.ImageTabGroup.SelectedTab;

            if tab == app.ScoutTab && ~isempty(app.AppData.ScoutVolume)
                V = app.AppData.ScoutVolume;
                s = min(s, size(V,3));
                imshow(V(:,:,s), [], 'Parent', app.AxScoutAxial);
                % Coronal and sagittal reconstructions would be added here.
            end
            % Additional cases for Dixon / MRE / L1-L2 / Overlay to be
            % implemented in Phase 2.
        end

        function updateFeatureDisplay(app)
            % Update all Val* labels from AppData.Features.
            % Called after RunStage3Callback completes.
            F = app.AppData.Features;
            if isfield(F,'LiverVolume_mL')
                app.ValLiverVol.Text  = sprintf('%.0f mL', F.LiverVolume_mL);
            end
            if isfield(F,'SpleenVolume_mL')
                app.ValSpleenVol.Text = sprintf('%.0f mL', F.SpleenVolume_mL);
            end
            if isfield(F,'LiverSpleenRatio')
                app.ValLSRatio.Text   = sprintf('%.2f', F.LiverSpleenRatio);
            end
            if isfield(F,'LiverPDFF_pct')
                app.ValLiverPDFF.Text = sprintf('%.1f %%', F.LiverPDFF_pct);
            end
            if isfield(F,'LiverStiffness_kPa')
                app.ValLiverStiff.Text  = sprintf('%.1f kPa', F.LiverStiffness_kPa);
            end
            if isfield(F,'SpleenStiffness_kPa')
                app.ValSpleenStiff.Text = sprintf('%.1f kPa', F.SpleenStiffness_kPa);
            end
            if isfield(F,'StiffnessRatio')
                app.ValStiffRatio.Text  = sprintf('%.2f', F.StiffnessRatio);
            end
            if isfield(F,'StiffnessIQR_kPa')
                app.ValHetIQR.Text      = sprintf('%.1f kPa', F.StiffnessIQR_kPa);
            end
            if isfield(F,'MuscleArea_cm2')
                app.ValMuscleArea.Text      = sprintf('%.1f cm²', F.MuscleArea_cm2);
            end
            if isfield(F,'SATArea_cm2')
                app.ValSATArea.Text         = sprintf('%.1f cm²', F.SATArea_cm2);
            end
            if isfield(F,'MuscleFatRatio')
                app.ValMuscleFatRatio.Text  = sprintf('%.2f', F.MuscleFatRatio);
            end
            if isfield(F,'MusclePDFF_pct')
                app.ValMusclePDFF.Text      = sprintf('%.1f %%', F.MusclePDFF_pct);
            end
            if isfield(F,'L12MuscleArea_cm2')
                app.ValL12MuscleArea.Text   = sprintf('%.1f cm²', F.L12MuscleArea_cm2);
            end
            if isfield(F,'L12SATArea_cm2')
                app.ValL12SATArea.Text      = sprintf('%.1f cm²', F.L12SATArea_cm2);
            end
            if isfield(F,'L12MuscleFatRatio')
                app.ValL12MuscleFat.Text    = sprintf('%.2f', F.L12MuscleFatRatio);
            end
            if isfield(F,'L12PDFF_pct')
                app.ValL12PDFF.Text         = sprintf('%.1f %%', F.L12PDFF_pct);
            end
        end

        function updateQCDisplay(app)
            % Update QC labels from AppData.QCResults.
            Q = app.AppData.QCResults;
            if isfield(Q,'SegmentationConfidence')
                score = Q.SegmentationConfidence;
                app.ValSegConf.Text = sprintf('%.2f', score);
                if score >= 0.85
                    app.ValSegConf.FontColor = [0.10 0.55 0.20];
                else
                    app.ValSegConf.FontColor = [0.75 0.35 0.00];
                end
            end
            if isfield(Q,'CoveragePass')
                app.ValCoverage.Text = ternary(Q.CoveragePass, 'Pass ✓', 'FAIL ✗');
                app.ValCoverage.FontColor = ternary(Q.CoveragePass, ...
                    [0.10 0.55 0.20], [0.75 0.10 0.10]);
            end
            if isfield(Q,'RangePass')
                app.ValRangeCheck.Text = ternary(Q.RangePass, 'Pass ✓', 'FAIL ✗');
                app.ValRangeCheck.FontColor = ternary(Q.RangePass, ...
                    [0.10 0.55 0.20], [0.75 0.10 0.10]);
            end
            if isfield(Q,'NeedsManualReview')
                app.ValManualReview.Text = ternary(Q.NeedsManualReview, ...
                    'Required ⚠', 'Not needed');
                app.ValManualReview.FontColor = ternary(Q.NeedsManualReview, ...
                    [0.75 0.35 0.00], [0.45 0.45 0.45]);
            end
        end

    end % private helpers

    % =====================================================================
    %  STATIC UTILITIES
    % =====================================================================
    methods (Static, Access = private)
        function out = ternary(cond, a, b)
            if cond; out = a; else; out = b; end
        end
    end

    % =====================================================================
    %  APP CONSTRUCTOR  (called by matlab.apps.AppBase infrastructure)
    % =====================================================================
    methods (Access = public)
        function app = HepatosplenicMRE_App()
            % Create and configure components
            createComponents(app);

            % Register with App Designer infrastructure
            registerApp(app, app.UIFigure);

            % Run startup
            runStartupFcn(app, @startupFcn);

            % Show the figure
            app.UIFigure.Visible = 'on';

            if nargout == 0
                clear app;
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end

end % classdef

classdef HepatosplenicMRE_App < matlab.apps.AppBase
% HepatosplenicMRE_App  Simplified GUI — HepatosplenicMRE platform v1.1
%
%   Changes from v1.0:
%     - Font sizes increased to 12-14 pt throughout
%     - Toolbar reduced to 4 essential buttons
%     - Overlay toggles moved to View menu (removed from image panel)
%     - Colormap selector moved to View menu
%     - Slice bar reduced to slider + label only
%     - Right panel section fonts enlarged
%     - Bottom bar simplified (2 rows: stage buttons + status text)
%
%   USAGE
%     app = HepatosplenicMRE_App;
%
%   AUTHOR  HepatosplenicMRE Platform  v1.1
%   DATE    2026-04

    % =====================================================================
    %  UI PROPERTIES
    % =====================================================================
    properties (Access = public)
        UIFigure            matlab.ui.Figure

        % Menus
        FileMenu            matlab.ui.container.Menu
        ViewMenu            matlab.ui.container.Menu
        ProcessMenu         matlab.ui.container.Menu
        SegmentationMenu    matlab.ui.container.Menu
        L12Menu             matlab.ui.container.Menu
        QCMenu              matlab.ui.container.Menu
        ExportMenu          matlab.ui.container.Menu
        HelpMenu            matlab.ui.container.Menu

        % Toolbar
        ToolbarPanel        matlab.ui.container.Panel
        BtnLoadStudy        matlab.ui.control.Button
        BtnRunAll           matlab.ui.control.Button
        BtnL12Locate        matlab.ui.control.Button
        BtnExportCSV        matlab.ui.control.Button
        LblPatientInfo      matlab.ui.control.Label

        % Layout
        BodyGrid            matlab.ui.container.GridLayout

        % Left panel
        LeftPanel           matlab.ui.container.Panel
        StudyTree           matlab.ui.container.CheckBoxTree
        LblStudyStats       matlab.ui.control.Label

        % Center panel
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

        % Slice bar
        SlicePanel          matlab.ui.container.Panel
        SliceGrid           matlab.ui.container.GridLayout
        SldrSlice           matlab.ui.control.Slider
        LblSliceNum         matlab.ui.control.Label
        LblImageInfo        matlab.ui.control.Label

        % Right panel — feature labels
        RightPanel          matlab.ui.container.Panel
        RightGrid           matlab.ui.container.GridLayout
        LblLiverVol         matlab.ui.control.Label
        ValLiverVol         matlab.ui.control.Label
        LblSpleenVol        matlab.ui.control.Label
        ValSpleenVol        matlab.ui.control.Label
        LblLSRatio          matlab.ui.control.Label
        ValLSRatio          matlab.ui.control.Label
        LblLiverPDFF        matlab.ui.control.Label
        ValLiverPDFF        matlab.ui.control.Label
        LblLiverStiff       matlab.ui.control.Label
        ValLiverStiff       matlab.ui.control.Label
        LblSpleenStiff      matlab.ui.control.Label
        ValSpleenStiff      matlab.ui.control.Label
        LblStiffRatio       matlab.ui.control.Label
        ValStiffRatio       matlab.ui.control.Label
        LblHetIQR           matlab.ui.control.Label
        ValHetIQR           matlab.ui.control.Label
        LblMuscleArea       matlab.ui.control.Label
        ValMuscleArea       matlab.ui.control.Label
        LblSATArea          matlab.ui.control.Label
        ValSATArea          matlab.ui.control.Label
        LblMuscleFatRatio   matlab.ui.control.Label
        ValMuscleFatRatio   matlab.ui.control.Label
        LblMusclePDFF       matlab.ui.control.Label
        ValMusclePDFF       matlab.ui.control.Label
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
        LblSegConf          matlab.ui.control.Label
        ValSegConf          matlab.ui.control.Label
        LblCoverage         matlab.ui.control.Label
        ValCoverage         matlab.ui.control.Label
        LblRangeCheck       matlab.ui.control.Label
        ValRangeCheck       matlab.ui.control.Label
        LblManualReview     matlab.ui.control.Label
        ValManualReview     matlab.ui.control.Label

        % Bottom bar
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
    %  APP DATA
    % =====================================================================
    properties (Access = public)
        AppData struct = struct( ...
            'ActiveStudy',    [], ...
            'L1SliceDixon',   [], ...
            'L2SliceDixon',   [], ...
            'Features',       struct(), ...
            'QCResults',      struct(), ...
            'CurrentSlice',   1, ...
            'PipelineStatus', struct( ...
                'S1','idle','S2','idle', ...
                'S3','idle','S4','idle','L12','idle'))
    end

    % =====================================================================
    %  BUILD UI
    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position = [30 30 1400 820];
            app.UIFigure.Name     = 'HepatosplenicMRE  v1.1';
            app.UIFigure.Resize   = 'on';
            app.UIFigure.CloseRequestFcn = @(~,~) app.CloseFcn();

            createMenus(app);

            outer = uigridlayout(app.UIFigure, [3 1]);
            outer.RowHeight   = {54,'1x',60};
            outer.ColumnWidth = {'1x'};
            outer.Padding     = [0 0 0 0];
            outer.RowSpacing  = 0;

            createToolbar(app, outer);

            app.BodyGrid = uigridlayout(outer, [1 3]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {210,'1x',245};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;

            createLeftPanel(app);
            createCenterPanel(app);
            createRightPanel(app);
            createBottomBar(app, outer);
        end

        % ----- MENUS -----------------------------------------------------
        function createMenus(app)
            % FILE
            app.FileMenu = uimenu(app.UIFigure,'Text','File');
            uimenu(app.FileMenu,'Text','Load Study (DICOM)...', ...
                'Accelerator','O','MenuSelectedFcn',@(~,~)app.LoadStudyCallback());
            uimenu(app.FileMenu,'Text','Load Study List (.csv)...', ...
                'MenuSelectedFcn',@(~,~)app.LoadStudyListCallback());
            uimenu(app.FileMenu,'Text','Save Session...','Separator','on', ...
                'Accelerator','S','MenuSelectedFcn',@(~,~)app.SaveSessionCallback());
            uimenu(app.FileMenu,'Text','Load Session...', ...
                'MenuSelectedFcn',@(~,~)app.LoadSessionCallback());
            uimenu(app.FileMenu,'Text','Exit','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.CloseFcn());

            % VIEW  — overlay controls live here
            app.ViewMenu = uimenu(app.UIFigure,'Text','View');
            uimenu(app.ViewMenu,'Text','Segmentation Overlay','Checked','off', ...
                'MenuSelectedFcn',@(s,~)app.ToggleMenuOverlay(s,'seg'));
            uimenu(app.ViewMenu,'Text','L1-L2 Level Lines','Checked','off', ...
                'MenuSelectedFcn',@(s,~)app.ToggleMenuOverlay(s,'l12'));
            uimenu(app.ViewMenu,'Text','Stiffness Colormap','Checked','off', ...
                'MenuSelectedFcn',@(s,~)app.ToggleMenuOverlay(s,'stiffness'));
            uimenu(app.ViewMenu,'Text','PDFF Colormap','Checked','off', ...
                'MenuSelectedFcn',@(s,~)app.ToggleMenuOverlay(s,'pdff'));
            uimenu(app.ViewMenu,'Text','Colormap: Gray','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.SetColormapCallback('gray'));
            uimenu(app.ViewMenu,'Text','Colormap: Jet', ...
                'MenuSelectedFcn',@(~,~)app.SetColormapCallback('jet'));
            uimenu(app.ViewMenu,'Text','Colormap: Hot', ...
                'MenuSelectedFcn',@(~,~)app.SetColormapCallback('hot'));
            uimenu(app.ViewMenu,'Text','Colormap: Parula', ...
                'MenuSelectedFcn',@(~,~)app.SetColormapCallback('parula'));

            % PROCESS
            app.ProcessMenu = uimenu(app.UIFigure,'Text','Process');
            uimenu(app.ProcessMenu,'Text','Run All Stages','Accelerator','R', ...
                'MenuSelectedFcn',@(~,~)app.RunAllStagesCallback());
            uimenu(app.ProcessMenu,'Text','Stage 1 — Harmonization','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.RunStage1Callback());
            uimenu(app.ProcessMenu,'Text','Stage 2 — Segmentation', ...
                'MenuSelectedFcn',@(~,~)app.RunStage2Callback());
            uimenu(app.ProcessMenu,'Text','Stage 3 — Feature Extraction', ...
                'MenuSelectedFcn',@(~,~)app.RunStage3Callback());
            uimenu(app.ProcessMenu,'Text','Stage 4 — Quality Control', ...
                'MenuSelectedFcn',@(~,~)app.RunQCCallback());

            % SEGMENTATION
            app.SegmentationMenu = uimenu(app.UIFigure,'Text','Segmentation');
            uimenu(app.SegmentationMenu,'Text','Edit Liver Mask', ...
                'MenuSelectedFcn',@(~,~)app.EditMaskCallback('liver'));
            uimenu(app.SegmentationMenu,'Text','Edit Spleen Mask', ...
                'MenuSelectedFcn',@(~,~)app.EditMaskCallback('spleen'));
            uimenu(app.SegmentationMenu,'Text','Edit Muscle Mask', ...
                'MenuSelectedFcn',@(~,~)app.EditMaskCallback('muscle'));
            uimenu(app.SegmentationMenu,'Text','Edit SAT Mask', ...
                'MenuSelectedFcn',@(~,~)app.EditMaskCallback('SAT'));
            uimenu(app.SegmentationMenu,'Text','Reset All Masks','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.ResetMasksCallback());
            uimenu(app.SegmentationMenu,'Text','Dixon to MRE (Rigid)','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.RegisterDixonMRECallback('rigid'));
            uimenu(app.SegmentationMenu,'Text','Dixon to MRE (Deformable)', ...
                'MenuSelectedFcn',@(~,~)app.RegisterDixonMRECallback('deformable'));
            uimenu(app.SegmentationMenu,'Text','Check Registration Overlay', ...
                'MenuSelectedFcn',@(~,~)app.CheckRegistrationCallback());

            % L1-L2
            app.L12Menu = uimenu(app.UIFigure,'Text','L1-L2');
            uimenu(app.L12Menu,'Text','Auto-Locate L1-L2 in Scout', ...
                'MenuSelectedFcn',@(~,~)app.L12LocateCallback());
            uimenu(app.L12Menu,'Text','Manual Landmark Adjustment', ...
                'MenuSelectedFcn',@(~,~)app.L12ManualAdjustCallback());
            uimenu(app.L12Menu,'Text','Propagate to Dixon + MRE', ...
                'MenuSelectedFcn',@(~,~)app.L12PropagateCallback());
            uimenu(app.L12Menu,'Text','Measure Muscle + SAT Area', ...
                'MenuSelectedFcn',@(~,~)app.L12MeasureCallback());
            uimenu(app.L12Menu,'Text','L1-L2 Summary Report','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.L12ReportCallback());

            % QC
            app.QCMenu = uimenu(app.UIFigure,'Text','QC');
            uimenu(app.QCMenu,'Text','Run All QC Checks', ...
                'MenuSelectedFcn',@(~,~)app.RunQCCallback());
            uimenu(app.QCMenu,'Text','Flag Study for Manual Review', ...
                'MenuSelectedFcn',@(~,~)app.FlagStudyCallback());
            uimenu(app.QCMenu,'Text','Unflag Study', ...
                'MenuSelectedFcn',@(~,~)app.UnflagStudyCallback());
            uimenu(app.QCMenu,'Text','QC Summary — All Studies','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.QCSummaryCallback());
            uimenu(app.QCMenu,'Text','Reproducibility Report', ...
                'MenuSelectedFcn',@(~,~)app.ReproducibilityReportCallback());
            uimenu(app.QCMenu,'Text','Feature Plots','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.ViewFeatureTableCallback());

            % EXPORT
            app.ExportMenu = uimenu(app.UIFigure,'Text','Export');
            uimenu(app.ExportMenu,'Text','Export Features (CSV)...','Accelerator','E', ...
                'MenuSelectedFcn',@(~,~)app.ExportCSVCallback());
            uimenu(app.ExportMenu,'Text','Export Report (PDF)...', ...
                'MenuSelectedFcn',@(~,~)app.ExportPDFCallback());
            uimenu(app.ExportMenu,'Text','Export Masks (NIfTI)...', ...
                'MenuSelectedFcn',@(~,~)app.ExportMasksCallback());
            uimenu(app.ExportMenu,'Text','Export Config (JSON)...','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.ExportConfigCallback());

            % HELP
            app.HelpMenu = uimenu(app.UIFigure,'Text','Help');
            uimenu(app.HelpMenu,'Text','Documentation', ...
                'MenuSelectedFcn',@(~,~)app.OpenDocCallback());
            uimenu(app.HelpMenu,'Text','Feature Definitions', ...
                'MenuSelectedFcn',@(~,~)app.FeatureDefsCallback());
            uimenu(app.HelpMenu,'Text','About','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.AboutCallback());
        end

        % ----- TOOLBAR ---------------------------------------------------
        function createToolbar(app, parentGrid)
            app.ToolbarPanel = uipanel(parentGrid);
            app.ToolbarPanel.Layout.Row    = 1;
            app.ToolbarPanel.Layout.Column = 1;
            app.ToolbarPanel.BorderType    = 'none';
            app.ToolbarPanel.BackgroundColor = [0.93 0.93 0.93];

            tg = uigridlayout(app.ToolbarPanel, [1 6]);
            tg.ColumnWidth   = {144,124,144,124,8,'1x'};
            tg.RowHeight     = {'1x'};
            tg.Padding       = [8 7 8 7];
            tg.ColumnSpacing = 6;

            app.BtnLoadStudy = makeToolBtn(tg,1,'Load Study', ...
                [0.18 0.44 0.74],[1 1 1],14,'Load a DICOM study folder  [Ctrl+O]');
            app.BtnLoadStudy.ButtonPushedFcn = @(~,~)app.LoadStudyCallback();

            app.BtnRunAll = makeToolBtn(tg,2,'Run All', ...
                [0.18 0.60 0.34],[1 1 1],14,'Run all pipeline stages  [Ctrl+R]');
            app.BtnRunAll.ButtonPushedFcn = @(~,~)app.RunAllStagesCallback();

            app.BtnL12Locate = makeToolBtn(tg,3,'L1-L2 Locate', ...
                [0.58 0.29 0.07],[1 1 1],14,'Auto-locate L1-L2 vertebral levels');
            app.BtnL12Locate.ButtonPushedFcn = @(~,~)app.L12LocateCallback();

            app.BtnExportCSV = makeToolBtn(tg,4,'Export CSV', ...
                [0.88 0.88 0.88],[0.20 0.20 0.20],14,'Export features to CSV  [Ctrl+E]');
            app.BtnExportCSV.ButtonPushedFcn = @(~,~)app.ExportCSVCallback();

            sep = uilabel(tg); sep.Layout.Column = 5;
            sep.Text = '|'; sep.FontColor = [0.70 0.70 0.70];
            sep.HorizontalAlignment = 'center';

            app.LblPatientInfo = uilabel(tg);
            app.LblPatientInfo.Layout.Column = 6;
            app.LblPatientInfo.Text      = 'No study loaded';
            app.LblPatientInfo.FontSize  = 13;
            app.LblPatientInfo.FontColor = [0.45 0.45 0.45];
            app.LblPatientInfo.FontAngle = 'italic';
        end

        % ----- LEFT PANEL ------------------------------------------------
        function createLeftPanel(app)
            app.LeftPanel = uipanel(app.BodyGrid);
            app.LeftPanel.Layout.Row    = 1;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Title         = 'Study Browser';
            app.LeftPanel.FontSize      = 13;
            app.LeftPanel.FontWeight    = 'bold';

            lg = uigridlayout(app.LeftPanel,[2 1]);
            lg.RowHeight   = {'1x',26};
            lg.ColumnWidth = {'1x'};
            lg.Padding     = [4 4 4 4];
            lg.RowSpacing  = 4;

            app.StudyTree = uitree(lg,'checkbox');
            app.StudyTree.Layout.Row    = 1;
            app.StudyTree.Layout.Column = 1;
            app.StudyTree.FontSize      = 12;
            app.StudyTree.SelectionChangedFcn = @(~,e)app.StudySelectionCallback(e);

            siteNode = uitreenode(app.StudyTree,'Text','Site: Mayo Clinic', ...
                'NodeData',struct('type','site'));
            s1 = uitreenode(siteNode,'Text','Subject 001');
            uitreenode(s1,'Text','Session 2024-03  [pending]', ...
                'NodeData',struct('type','session','id','001-2024-03'));
            uitreenode(s1,'Text','Session 2024-09  [pending]', ...
                'NodeData',struct('type','session','id','001-2024-09'));
            expand(siteNode,'all');
            expand(s1,'all');

            app.LblStudyStats = uilabel(lg);
            app.LblStudyStats.Layout.Row = 2; app.LblStudyStats.Layout.Column = 1;
            app.LblStudyStats.Text = 'Loaded: 0 / 0    Flagged: 0';
            app.LblStudyStats.FontSize  = 11;
            app.LblStudyStats.FontColor = [0.50 0.50 0.50];
            app.LblStudyStats.HorizontalAlignment = 'center';
        end

        % ----- CENTER PANEL ----------------------------------------------
        function createCenterPanel(app)
            app.CenterPanel = uipanel(app.BodyGrid);
            app.CenterPanel.Layout.Row    = 1;
            app.CenterPanel.Layout.Column = 2;
            app.CenterPanel.BorderType    = 'none';

            app.CenterGrid = uigridlayout(app.CenterPanel,[2 1]);
            app.CenterGrid.RowHeight   = {'1x',36};
            app.CenterGrid.ColumnWidth = {'1x'};
            app.CenterGrid.Padding     = [0 0 0 0];
            app.CenterGrid.RowSpacing  = 0;

            app.ImageTabGroup = uitabgroup(app.CenterGrid);
            app.ImageTabGroup.Layout.Row    = 1;
            app.ImageTabGroup.Layout.Column = 1;
            app.ImageTabGroup.FontSize      = 13;
            app.ImageTabGroup.SelectionChangedFcn = @(~,e)app.TabChangedCallback(e);

            buildScoutTab(app);
            buildDixonTab(app);
            buildMRETab(app);
            buildL12Tab(app);
            buildOverlayTab(app);

            % Slim dark slice bar
            app.SlicePanel = uipanel(app.CenterGrid);
            app.SlicePanel.Layout.Row    = 2;
            app.SlicePanel.Layout.Column = 1;
            app.SlicePanel.BorderType    = 'line';
            app.SlicePanel.BackgroundColor = [0.12 0.12 0.12];

            app.SliceGrid = uigridlayout(app.SlicePanel,[1 3]);
            app.SliceGrid.ColumnWidth  = {90,'1x',220};
            app.SliceGrid.RowHeight    = {'1x'};
            app.SliceGrid.Padding      = [6 3 6 3];
            app.SliceGrid.ColumnSpacing = 8;

            app.LblSliceNum = uilabel(app.SliceGrid);
            app.LblSliceNum.Layout.Column = 1;
            app.LblSliceNum.Text       = 'Slice  1';
            app.LblSliceNum.FontSize   = 13;
            app.LblSliceNum.FontWeight = 'bold';
            app.LblSliceNum.FontColor  = [0.88 0.88 0.88];

            app.SldrSlice = uislider(app.SliceGrid);
            app.SldrSlice.Layout.Column = 2;
            app.SldrSlice.Limits        = [1 100];
            app.SldrSlice.Value         = 1;
            app.SldrSlice.MajorTicks    = [];
            app.SldrSlice.MinorTicks    = [];
            app.SldrSlice.ValueChangedFcn = @(~,e)app.SliceChangedCallback(e);

            app.LblImageInfo = uilabel(app.SliceGrid);
            app.LblImageInfo.Layout.Column = 3;
            app.LblImageInfo.Text      = 'No study loaded';
            app.LblImageInfo.FontSize  = 11;
            app.LblImageInfo.FontColor = [0.58 0.58 0.58];
            app.LblImageInfo.HorizontalAlignment = 'right';
        end

        function buildScoutTab(app)
            app.ScoutTab  = uitab(app.ImageTabGroup,'Title','3-Plane Scout');
            app.ScoutGrid = uigridlayout(app.ScoutTab,[1 3]);
            app.ScoutGrid.ColumnWidth = {'1x','1x','1x'};
            app.ScoutGrid.RowHeight   = {'1x'};
            app.ScoutGrid.Padding     = [3 3 3 3];
            app.ScoutGrid.ColumnSpacing = 4;
            app.AxScoutAxial    = imgAx(app.ScoutGrid, 1, 'Axial');
            app.AxScoutCoronal  = imgAx(app.ScoutGrid, 2, 'Coronal');
            app.AxScoutSagittal = imgAx(app.ScoutGrid, 3, 'Sagittal');
        end

        function buildDixonTab(app)
            app.DixonTab  = uitab(app.ImageTabGroup,'Title','Dixon MRI');
            app.DixonGrid = uigridlayout(app.DixonTab,[1 4]);
            app.DixonGrid.ColumnWidth = {'1x','1x','1x','1x'};
            app.DixonGrid.RowHeight   = {'1x'};
            app.DixonGrid.Padding     = [3 3 3 3];
            app.DixonGrid.ColumnSpacing = 4;
            app.AxDixonWater   = imgAx(app.DixonGrid, 1, 'Water');
            app.AxDixonFat     = imgAx(app.DixonGrid, 2, 'Fat');
            app.AxDixonFF      = imgAx(app.DixonGrid, 3, 'Fat Fraction (%)');
            app.AxDixonInPhase = imgAx(app.DixonGrid, 4, 'In-Phase');
        end

        function buildMRETab(app)
            app.MRETab  = uitab(app.ImageTabGroup,'Title','2D MRE');
            app.MREGrid = uigridlayout(app.MRETab,[1 3]);
            app.MREGrid.ColumnWidth = {'1x','1x','1x'};
            app.MREGrid.RowHeight   = {'1x'};
            app.MREGrid.Padding     = [3 3 3 3];
            app.MREGrid.ColumnSpacing = 4;
            app.AxMREMagnitude = imgAx(app.MREGrid, 1, 'MRE Magnitude');
            app.AxMREStiffness = imgAx(app.MREGrid, 2, 'Stiffness (kPa)');
            app.AxMREWave      = imgAx(app.MREGrid, 3, 'Wave Image');
            colormap(app.AxMREStiffness,'jet');
        end

        function buildL12Tab(app)
            app.L12Tab  = uitab(app.ImageTabGroup,'Title','L1-L2 View');
            app.L12Grid = uigridlayout(app.L12Tab,[1 2]);
            app.L12Grid.ColumnWidth = {'1x','1x'};
            app.L12Grid.RowHeight   = {'1x'};
            app.L12Grid.Padding     = [3 3 3 3];
            app.L12Grid.ColumnSpacing = 4;
            app.AxL12Axial   = imgAx(app.L12Grid, 1, 'Axial — L1 level');
            app.AxL12Coronal = imgAx(app.L12Grid, 2, 'Coronal — L1-L2 span');
        end

        function buildOverlayTab(app)
            app.OverlayTab  = uitab(app.ImageTabGroup,'Title','Overlay');
            app.OverlayGrid = uigridlayout(app.OverlayTab,[1 2]);
            app.OverlayGrid.ColumnWidth = {'1x','1x'};
            app.OverlayGrid.RowHeight   = {'1x'};
            app.OverlayGrid.Padding     = [3 3 3 3];
            app.OverlayGrid.ColumnSpacing = 4;
            app.AxOverlayDixon = imgAx(app.OverlayGrid, 1, 'Dixon (reference)');
            app.AxOverlayMRE   = imgAx(app.OverlayGrid, 2, 'MRE (registered)');
        end

        % ----- RIGHT PANEL -----------------------------------------------
        function createRightPanel(app)
            app.RightPanel = uipanel(app.BodyGrid);
            app.RightPanel.Layout.Row    = 1;
            app.RightPanel.Layout.Column = 3;
            app.RightPanel.Title         = 'Feature Results';
            app.RightPanel.FontSize      = 13;
            app.RightPanel.FontWeight    = 'bold';

            app.RightGrid = uigridlayout(app.RightPanel,[5 1]);
            app.RightGrid.RowHeight   = {108,100,108,138,100};
            app.RightGrid.ColumnWidth = {'1x'};
            app.RightGrid.Padding     = [2 2 2 2];
            app.RightGrid.RowSpacing  = 2;

            addSection(app,1,'Organ size & composition', ...
                {'Liver vol.','Spleen vol.','LS ratio','Liver PDFF'}, ...
                {'LiverVol','SpleenVol','LSRatio','LiverPDFF'});

            addSection(app,2,'Mechanical (MRE)', ...
                {'Liver stiffness','Spleen stiffness','Stiff. ratio','Het. IQR'}, ...
                {'LiverStiff','SpleenStiff','StiffRatio','HetIQR'});

            addSection(app,3,'Body composition', ...
                {'Muscle area','SAT area','Muscle:fat','Muscle PDFF'}, ...
                {'MuscleArea','SATArea','MuscleFatRatio','MusclePDFF'});

            addSection(app,4,'L1-L2 measures', ...
                {'L1 located','L2 located','Muscle L1-L2','SAT L1-L2', ...
                 'Musc:fat L1-L2','PDFF L1-L2'}, ...
                {'L1Status','L2Status','L12MuscleArea','L12SATArea', ...
                 'L12MuscleFat','L12PDFF'});

            addSection(app,5,'QC status', ...
                {'Seg. confidence','Coverage','Range check','Manual review'}, ...
                {'SegConf','Coverage','RangeCheck','ManualReview'});
        end

        function addSection(app, row, title, labels, props)
            pnl = uipanel(app.RightGrid);
            pnl.Layout.Row = row; pnl.Layout.Column = 1;
            pnl.Title = title; pnl.FontSize = 12; pnl.FontWeight = 'bold';

            n = numel(labels);
            g = uigridlayout(pnl,[n 2]);
            g.ColumnWidth = {'1x','1x'};
            g.RowHeight   = repmat({21},1,n);
            g.Padding     = [6 2 6 2];
            g.ColumnSpacing = 4; g.RowSpacing = 2;

            for k = 1:n
                lbl = uilabel(g);
                lbl.Layout.Row = k; lbl.Layout.Column = 1;
                lbl.Text = labels{k};
                lbl.FontSize = 12; lbl.FontColor = [0.40 0.40 0.40];

                val = uilabel(g);
                val.Layout.Row = k; val.Layout.Column = 2;
                val.Text = '—';
                val.FontSize = 13; val.FontWeight = 'bold';
                val.FontColor = [0.25 0.25 0.25];
                val.HorizontalAlignment = 'right';

                app.(['Val' props{k}]) = val;
                app.(['Lbl' props{k}]) = lbl;
            end
        end

        % ----- BOTTOM BAR ------------------------------------------------
        function createBottomBar(app, parentGrid)
            app.BottomPanel = uipanel(parentGrid);
            app.BottomPanel.Layout.Row    = 3;
            app.BottomPanel.Layout.Column = 1;
            app.BottomPanel.BorderType    = 'line';
            app.BottomPanel.BackgroundColor = [0.90 0.90 0.90];

            app.BottomGrid = uigridlayout(app.BottomPanel,[2 7]);
            app.BottomGrid.RowHeight    = {'1x',18};
            app.BottomGrid.ColumnWidth  = {'1x','1x','1x','1x',10,'1x','2x'};
            app.BottomGrid.Padding      = [6 4 6 2];
            app.BottomGrid.ColumnSpacing = 4;
            app.BottomGrid.RowSpacing   = 2;

            stageLabels = {'S1  Harmonize','S2  Segment','S3  Features','S4  QC'};
            stageProps  = {'BtnStage1Status','BtnStage2Status', ...
                           'BtnStage3Status','BtnStage4Status'};
            stageCBs    = {@(~,~)app.RunStage1Callback(), ...
                           @(~,~)app.RunStage2Callback(), ...
                           @(~,~)app.RunStage3Callback(), ...
                           @(~,~)app.RunQCCallback()};

            for k = 1:4
                btn = uibutton(app.BottomGrid,'push');
                btn.Layout.Row = 1; btn.Layout.Column = k;
                btn.Text = stageLabels{k}; btn.FontSize = 12;
                btn.BackgroundColor = [0.80 0.80 0.80];
                btn.ButtonPushedFcn = stageCBs{k};
                app.(stageProps{k}) = btn;
            end

            sp = uilabel(app.BottomGrid);
            sp.Layout.Row = 1; sp.Layout.Column = 5;
            sp.Text = '|'; sp.HorizontalAlignment = 'center';
            sp.FontColor = [0.60 0.60 0.60];

            app.BtnL12Status = uibutton(app.BottomGrid,'push');
            app.BtnL12Status.Layout.Row = 1; app.BtnL12Status.Layout.Column = 6;
            app.BtnL12Status.Text = 'L1-L2 Module';
            app.BtnL12Status.FontSize = 12;
            app.BtnL12Status.BackgroundColor = [0.84 0.72 0.56];
            app.BtnL12Status.ButtonPushedFcn = @(~,~)app.L12LocateCallback();

            app.LblStatusMsg = uilabel(app.BottomGrid);
            app.LblStatusMsg.Layout.Row = 2; app.LblStatusMsg.Layout.Column = [1 7];
            app.LblStatusMsg.Text = 'Ready — no study loaded';
            app.LblStatusMsg.FontSize = 11; app.LblStatusMsg.FontColor = [0.40 0.40 0.40];
        end

    end % createComponents

    % =====================================================================
    %  STARTUP
    % =====================================================================
    methods (Access = private)
        function startupFcn(app)
            for s = {'S1','S2','S3','S4','L12'}
                updatePipelineStatus(app, s{1}, 'idle');
            end
            setStatus(app,'Ready — please load a study to begin.');
        end
    end

    % =====================================================================
    %  PUBLIC CALLBACKS (stubs)
    % =====================================================================
    methods (Access = public)
        function LoadStudyCallback(app),    setStatus(app,'[Phase 2] LoadStudy — not yet implemented.'); end
        function LoadStudyListCallback(app),setStatus(app,'[Phase 2] LoadStudyList — not yet implemented.'); end
        function SaveSessionCallback(app),  setStatus(app,'[Phase 7] SaveSession — not yet implemented.'); end
        function LoadSessionCallback(app),  setStatus(app,'[Phase 7] LoadSession — not yet implemented.'); end
        function RunAllStagesCallback(app)
            RunStage1Callback(app); RunStage2Callback(app);
            L12LocateCallback(app); RunStage3Callback(app); RunQCCallback(app);
        end
        function RunStage1Callback(app)
            updatePipelineStatus(app,'S1','running');
            setStatus(app,'[Phase 2] Stage 1 — Harmonization running...');
            updatePipelineStatus(app,'S1','idle');
        end
        function RunStage2Callback(app)
            updatePipelineStatus(app,'S2','running');
            setStatus(app,'[Phase 4] Stage 2 — Segmentation running...');
            updatePipelineStatus(app,'S2','idle');
        end
        function RunStage3Callback(app)
            updatePipelineStatus(app,'S3','running');
            setStatus(app,'[Phase 5] Stage 3 — Feature extraction running...');
            updatePipelineStatus(app,'S3','idle');
        end
        function RunQCCallback(app)
            updatePipelineStatus(app,'S4','running');
            setStatus(app,'[Phase 6] Stage 4 — QC running...');
            updatePipelineStatus(app,'S4','idle');
        end
        function L12LocateCallback(app)
            updatePipelineStatus(app,'L12','running');
            setStatus(app,'[Phase 3] L1-L2 localization running...');
            updatePipelineStatus(app,'L12','idle');
        end
        function L12ManualAdjustCallback(app),  setStatus(app,'[Phase 3] L12ManualAdjust — stub.'); end
        function L12PropagateCallback(app),     setStatus(app,'[Phase 3] L12Propagate — stub.'); end
        function L12MeasureCallback(app),       setStatus(app,'[Phase 5] L12Measure — stub.'); end
        function L12ReportCallback(app),        setStatus(app,'[Phase 7] L12Report — stub.'); end
        function EditMaskCallback(app,organ),   setStatus(app,sprintf('[Phase 4] EditMask(%s) — stub.',organ)); end
        function ResetMasksCallback(app),       setStatus(app,'Masks cleared.'); end
        function RegisterDixonMRECallback(app,mode), setStatus(app,sprintf('[Phase 3] RegisterDixonMRE(%s) — stub.',mode)); end
        function CheckRegistrationCallback(app),setStatus(app,'[Phase 3] CheckRegistration — stub.'); end
        function ViewFeatureTableCallback(app), setStatus(app,'[Phase 5] ViewFeatureTable — stub.'); end
        function FlagStudyCallback(app),        setStatus(app,'[Phase 6] FlagStudy — stub.'); end
        function UnflagStudyCallback(app),      setStatus(app,'[Phase 6] UnflagStudy — stub.'); end
        function QCSummaryCallback(app),        setStatus(app,'[Phase 6] QCSummary — stub.'); end
        function ReproducibilityReportCallback(app), setStatus(app,'[Phase 6] Reproducibility — stub.'); end
        function ExportCSVCallback(app),        setStatus(app,'[Phase 7] ExportCSV — stub.'); end
        function ExportPDFCallback(app),        setStatus(app,'[Phase 7] ExportPDF — stub.'); end
        function ExportMasksCallback(app),      setStatus(app,'[Phase 7] ExportMasks — stub.'); end
        function ExportConfigCallback(app),     setStatus(app,'[Phase 7] ExportConfig — stub.'); end
        function OpenDocCallback(~), web('https://github.com/MengYinMayo/HepatosplenicMRE','-browser'); end
        function FeatureDefsCallback(app), setStatus(app,'[Help] FeatureDefs — stub.'); end
        function AboutCallback(~)
            msgbox(sprintf(['HepatosplenicMRE Platform  v1.1\n\n' ...
                'Mayo Clinic R01 Collaboration\nPI: Meng Yin, PhD']),'About','help');
        end

        function ToggleMenuOverlay(app, menuItem, ~)
            menuItem.Checked = ternary(strcmp(menuItem.Checked,'on'),'off','on');
            refreshDisplayedSlice(app);
        end
        function SetColormapCallback(app, cm)
            for ax = [app.AxScoutAxial,app.AxScoutCoronal,app.AxScoutSagittal, ...
                      app.AxDixonWater,app.AxDixonFat,app.AxDixonInPhase, ...
                      app.AxMREMagnitude,app.AxMREWave, ...
                      app.AxL12Axial,app.AxL12Coronal, ...
                      app.AxOverlayDixon,app.AxOverlayMRE]
                colormap(ax,cm);
            end
        end

        function StudySelectionCallback(app,event)
            n = event.SelectedNodes;
            if ~isempty(n), setStatus(app,sprintf('Selected: %s',n.Text)); end
        end
        function TabChangedCallback(app,~),   updateSliceSlider(app); end
        function SliceChangedCallback(app,e)
            app.AppData.CurrentSlice = round(e.Value);
            app.LblSliceNum.Text = sprintf('Slice  %d', app.AppData.CurrentSlice);
            refreshDisplayedSlice(app);
        end
        function CloseFcn(app)
            sel = uiconfirm(app.UIFigure,'Close HepatosplenicMRE?','Exit', ...
                'Options',{'Close','Cancel'},'DefaultOption','Cancel','CancelOption','Cancel');
            if strcmp(sel,'Close'), delete(app.UIFigure); end
        end
    end

    % =====================================================================
    %  PRIVATE HELPERS
    % =====================================================================
    methods (Access = private)
        function setStatus(app,msg)
            app.LblStatusMsg.Text = sprintf('[%s]  %s', datestr(now,'HH:MM:SS'), msg);
            drawnow limitrate;
        end

        function updatePipelineStatus(app,stage,status)
            c = struct('idle',[.80 .80 .80],'running',[.97 .80 .18], ...
                       'done',[.20 .62 .28],'error',[.78 .16 .16],'flagged',[.84 .48 .10]);
            app.AppData.PipelineStatus.(stage) = status;
            switch stage
                case 'S1',  b = app.BtnStage1Status;
                case 'S2',  b = app.BtnStage2Status;
                case 'S3',  b = app.BtnStage3Status;
                case 'S4',  b = app.BtnStage4Status;
                case 'L12', b = app.BtnL12Status;
                otherwise, return
            end
            b.BackgroundColor = c.(status);
        end

        function updateSliceSlider(app)
            nS = 2;
            if ~isempty(app.AppData.ActiveStudy) && ...
               isfield(app.AppData.ActiveStudy,'Harmonized')
                H = app.AppData.ActiveStudy.Harmonized;
                tab = app.ImageTabGroup.SelectedTab;
                if tab == app.ScoutTab && ~isempty(H.Scout)
                    nS = size(H.Scout,3);
                elseif tab == app.DixonTab && ~isempty(H.DixonWater)
                    nS = size(H.DixonWater,3);
                elseif tab == app.MRETab && ~isempty(H.MREStiffness)
                    nS = size(H.MREStiffness,3);
                end
            end
            app.SldrSlice.Limits = [1 max(nS,2)];
            app.SldrSlice.Value  = min(app.AppData.CurrentSlice, max(nS,1));
        end

        function refreshDisplayedSlice(~)
            % Filled in by Phase 2 app_integratePhase2.m
        end
    end

    % =====================================================================
    %  STATIC HELPERS
    % =====================================================================
    methods (Static, Access = private)
        function out = ternary(cond,a,b)
            if cond; out=a; else; out=b; end
        end
    end

    % =====================================================================
    %  CONSTRUCTOR / DESTRUCTOR
    % =====================================================================
    methods (Access = public)
        function app = HepatosplenicMRE_App()
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            app.UIFigure.Visible = 'on';
            if nargout == 0, clear app; end
        end
        function delete(app), delete(app.UIFigure); end
    end

end

% =========================================================================
%  MODULE-LEVEL HELPERS  (outside classdef — visible within same file)
% =========================================================================
function btn = makeToolBtn(parent, col, txt, bg, fg, fs, tip)
    btn = uibutton(parent,'push');
    btn.Layout.Column   = col;
    btn.Text            = txt;
    btn.FontSize        = fs;
    btn.FontWeight      = 'bold';
    btn.BackgroundColor = bg;
    btn.FontColor       = fg;
    btn.Tooltip         = tip;
end

function ax = imgAx(parent, col, titleStr)
    ax = uiaxes(parent);
    ax.Layout.Column = col;
    ax.XTick = []; ax.YTick = [];
    ax.Box = 'on';
    ax.Color = [0.06 0.06 0.06];
    ax.XColor = [0.28 0.28 0.28];
    ax.YColor = [0.28 0.28 0.28];
    ax.BackgroundColor = [0.06 0.06 0.06];
    title(ax, titleStr, 'FontSize', 12, 'Color', [0.72 0.72 0.72], 'FontWeight','normal');
    colormap(ax,'gray');
end

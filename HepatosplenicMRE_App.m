classdef HepatosplenicMRE_App < matlab.apps.AppBase
% HepatosplenicMRE_App  v2.0 — Unified single-window analysis platform.
%
%   All processing, image viewing, and ROI placement occurs inside this
%   one window. No separate pop-up figures.
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
%   AUTHOR  HepatosplenicMRE Platform  v2.0

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
        BtnRunPipeline      matlab.ui.control.Button
        BtnConfirmL12       matlab.ui.control.Button
        BtnExportCSV        matlab.ui.control.Button
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
        BtnPlaceL1          matlab.ui.control.Button
        BtnPlaceL2          matlab.ui.control.Button
        BtnClearL12         matlab.ui.control.Button
        LblL12Status        matlab.ui.control.Label

        % Dixon tab
        DixonTab            matlab.ui.container.Tab
        DixonGrid           matlab.ui.container.GridLayout
        AxDixonWater        matlab.ui.control.UIAxes
        AxDixonPDFF         matlab.ui.control.UIAxes
        AxDixonIP           matlab.ui.control.UIAxes
        SldrDixon           matlab.ui.control.Slider
        LblDixonSlice       matlab.ui.control.Label
        LblDixonInfo        matlab.ui.control.Label
        % Dixon ROI buttons
        BtnROI_LiverDixon   matlab.ui.control.Button
        BtnROI_SpleenDixon  matlab.ui.control.Button
        BtnROI_MuscleL1     matlab.ui.control.Button
        BtnROI_MuscleL2     matlab.ui.control.Button
        BtnROI_SATL1        matlab.ui.control.Button
        BtnROI_SATL2        matlab.ui.control.Button
        BtnClearDixonROIs   matlab.ui.control.Button

        % MRE tab
        MRETab              matlab.ui.container.Tab
        MREGrid             matlab.ui.container.GridLayout
        AxMREMag            matlab.ui.control.UIAxes
        AxMREWave           matlab.ui.control.UIAxes
        AxMREStiff          matlab.ui.control.UIAxes
        SldrMRE             matlab.ui.control.Slider
        LblMRESlice         matlab.ui.control.Label
        LblMREInfo          matlab.ui.control.Label
        BtnMREPlay          matlab.ui.control.Button
        BtnStiff8           matlab.ui.control.Button
        BtnStiff20          matlab.ui.control.Button
        BtnConfMap          matlab.ui.control.StateButton
        BtnROI_LiverMRE     matlab.ui.control.Button
        BtnROI_SpleenMRE    matlab.ui.control.Button
        BtnClearMREROIs     matlab.ui.control.Button

        % Results tab
        ResultsTab          matlab.ui.container.Tab
        ResultsGrid         matlab.ui.container.GridLayout
        ResultsTable        matlab.ui.control.Table

        % ── RIGHT: Feature results ──
        RightPanel          matlab.ui.container.Panel
        RightGrid           matlab.ui.container.GridLayout

        % Feature value labels (generated dynamically — see buildRightPanel)
        ValLiverDixonVol    matlab.ui.control.Label
        ValLiverDixonPDFF   matlab.ui.control.Label
        ValSpleenDixonVol   matlab.ui.control.Label
        ValSpleenDixonPDFF  matlab.ui.control.Label
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
        ValLiverStiffIQR    matlab.ui.control.Label
        ValSpleenStiffIQR   matlab.ui.control.Label
        ValSegConf          matlab.ui.control.Label
        ValCoverage         matlab.ui.control.Label

        % Bottom bar
        BottomPanel         matlab.ui.container.Panel
        BottomGrid          matlab.ui.container.GridLayout
        BtnStepLoc          matlab.ui.control.Button
        BtnStepDixon        matlab.ui.control.Button
        BtnStepMRE          matlab.ui.control.Button
        BtnStepResults      matlab.ui.control.Button
        LblStatusMsg        matlab.ui.control.Label
    end

    % =====================================================================
    %  APP DATA
    % =====================================================================
    properties (Access = public)
        AppData struct = struct( ...
            'Exam',         [], ...
            'Selection',    [], ...
            'MATPath',      '', ...
            'Localizer',    [], ...   % from loc_loadLocalizer
            'Dixon',        [], ...   % from seg_buildDixonVolume
            'MRE',          [], ...   % struct: M,W,W_raw,S,LapC,H
            'L12',          [], ...   % from loc_detectL1L2
            'L12_Dixon',    [], ...   % propagated to Dixon space
            'L12_MRE',      [], ...   % propagated to MRE space
            'L1_CorRow',    NaN, ...  % row index in coronal localizer
            'L2_CorRow',    NaN, ...  % row index in coronal localizer
            'L1_SagRow',    NaN, ...  % row index in sagittal localizer
            'L2_SagRow',    NaN, ...
            'LocHoverAxes', '', ...   % 'cor' | 'sag' | '' for scroll-wheel routing
            'AwaitingClick','', ...   % 'L1' | 'L2' | '' placement mode
            'CorSlice',     1, ...    % current coronal slice index
            'SagSlice',     1, ...    % current sagittal slice index
            'DixonSlice',   1, ...
            'MRESlice',     1, ...
            'MREPhase',     1, ...
            'MREPlaying',   false, ...
            'MRETimer',     [], ...
            'StiffCLim',    [0 8], ...
            'ShowConfMask', false, ...
            'ROIs',         struct( ...   % all ROI masks
                'LiverDixon',  struct('Slices',struct()), ...
                'SpleenDixon', struct('Slices',struct()), ...
                'MuscleL1',    [], ...
                'MuscleL2',    [], ...
                'SATL1',       [], ...
                'SATL2',       [], ...
                'LiverMRE',    struct('Slices',struct()), ...
                'SpleenMRE',   struct('Slices',struct())))
    end

    % =====================================================================
    %  COMPONENT CREATION
    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position  = [20 20 1440 860];
            app.UIFigure.Name      = 'HepatosplenicMRE Analysis Platform  v2.0';
            app.UIFigure.Resize    = 'on';
            app.UIFigure.CloseRequestFcn = @(~,~) app.onClose();

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
            app.BodyGrid.ColumnWidth   = {200,'1x',230};
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
            uimenu(app.ExportMenu,'Text','Export Features (CSV)...', ...
                'Accelerator','E','MenuSelectedFcn',@(~,~)app.exportCSV());
            uimenu(app.ExportMenu,'Text','Export ROI Masks (MAT)...', ...
                'MenuSelectedFcn',@(~,~)app.exportROIs());
            uimenu(app.ExportMenu,'Text','Export Report (PDF)...', ...
                'MenuSelectedFcn',@(~,~)app.exportPDF());

            app.HelpMenu = uimenu(app.UIFigure,'Text','Help');
            uimenu(app.HelpMenu,'Text','About', ...
                'MenuSelectedFcn',@(~,~)app.showAbout());
        end

        % -----------------------------------------------------------------
        function createToolbar(app, parentGrid)
            app.ToolbarPanel = uipanel(parentGrid);
            app.ToolbarPanel.Layout.Row    = 1;
            app.ToolbarPanel.Layout.Column = 1;
            app.ToolbarPanel.BorderType    = 'none';
            app.ToolbarPanel.BackgroundColor = [0.93 0.93 0.93];

            tg = uigridlayout(app.ToolbarPanel,[1 6]);
            tg.ColumnWidth   = {150,150,160,140,8,'1x'};
            tg.RowHeight     = {'1x'};
            tg.Padding       = [8 7 8 7];
            tg.ColumnSpacing = 6;

            app.BtnLoadStudy = mkBtn(tg,1,'Load Study', ...
                [0.18 0.44 0.74],[1 1 1],14);
            app.BtnLoadStudy.ButtonPushedFcn = @(~,~)app.loadStudy();
            app.BtnLoadStudy.Tooltip = 'Load DICOM exam, select series, build MAT';

            app.BtnRunPipeline = mkBtn(tg,2,'Run Pipeline', ...
                [0.18 0.60 0.34],[1 1 1],14);
            app.BtnRunPipeline.ButtonPushedFcn = @(~,~)app.runPipeline();
            app.BtnRunPipeline.Tooltip = 'Run full analysis pipeline';
            app.BtnRunPipeline.Enable  = 'off';

            app.BtnConfirmL12 = mkBtn(tg,3,'Confirm L1-L2', ...
                [0.58 0.29 0.07],[1 1 1],14);
            app.BtnConfirmL12.ButtonPushedFcn = @(~,~)app.confirmL12();
            app.BtnConfirmL12.Tooltip = 'Confirm L1-L2 levels and propagate to Dixon/MRE';
            app.BtnConfirmL12.Enable  = 'off';

            app.BtnExportCSV = mkBtn(tg,4,'Export CSV', ...
                [0.88 0.88 0.88],[0.2 0.2 0.2],14);
            app.BtnExportCSV.ButtonPushedFcn = @(~,~)app.exportCSV();
            app.BtnExportCSV.Enable = 'off';

            sep = uilabel(tg); sep.Layout.Column=5;
            sep.Text='|'; sep.FontColor=[0.7 0.7 0.7];
            sep.HorizontalAlignment='center';

            app.LblPatientInfo = uilabel(tg);
            app.LblPatientInfo.Layout.Column = 6;
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
            app.CenterPanel = uipanel(app.BodyGrid,'BorderType','none');
            app.CenterPanel.Layout.Column = 2;

            app.ImageTabGroup = uitabgroup(app.CenterPanel, ...
                'Position',[0 0 1 1],'Units','normalized');
            app.ImageTabGroup.FontSize = 13;
            app.ImageTabGroup.SelectionChangedFcn = @(~,e)app.onTabChange(e);

            createLocalizerTab(app);
            createDixonTab(app);
            createMRETab(app);
            createResultsTab(app);
        end

        % ── LOCALIZER TAB ────────────────────────────────────────────────
        function createLocalizerTab(app)
            app.LocTab = uitab(app.ImageTabGroup,'Title','Localizer / L1-L2');

            % Grid: images row | controls row
            app.LocGrid = uigridlayout(app.LocTab,[3 2]);
            app.LocGrid.RowHeight    = {'1x',32,42};
            app.LocGrid.ColumnWidth  = {'1x','1x'};
            app.LocGrid.Padding      = [6 6 6 6];
            app.LocGrid.RowSpacing   = 4;
            app.LocGrid.ColumnSpacing = 8;

            % Coronal axis
            app.AxLocCoronal = uiaxes(app.LocGrid);
            app.AxLocCoronal.Layout.Row=1; app.AxLocCoronal.Layout.Column=1;
            setupDarkAxes(app.AxLocCoronal,'Coronal  (L1-L2 identification)');

            % Sagittal axis
            app.AxLocSagittal = uiaxes(app.LocGrid);
            app.AxLocSagittal.Layout.Row=1; app.AxLocSagittal.Layout.Column=2;
            setupDarkAxes(app.AxLocSagittal,'Sagittal  (L1-L2 verification)');

            % Sliders (row 2)
            corSliderGrid = uigridlayout(app.LocGrid,[1 3]);
            corSliderGrid.Layout.Row=2; corSliderGrid.Layout.Column=1;
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
            sagSliderGrid.Layout.Row=2; sagSliderGrid.Layout.Column=2;
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

            % L1/L2 buttons (row 3, spanning both columns)
            ctrlGrid = uigridlayout(app.LocGrid,[1 5]);
            ctrlGrid.Layout.Row=3; ctrlGrid.Layout.Column=[1 2];
            ctrlGrid.ColumnWidth={160,160,130,'1x',280}; ctrlGrid.Padding=[0 2 0 2];

            app.BtnPlaceL1 = uibutton(ctrlGrid,'push');
            app.BtnPlaceL1.Layout.Column=1;
            app.BtnPlaceL1.Text='Mark L1';
            app.BtnPlaceL1.FontSize=12; app.BtnPlaceL1.FontWeight='bold';
            app.BtnPlaceL1.BackgroundColor=[0.92 0.60 0.12];
            app.BtnPlaceL1.Tooltip='Click, then click on L1 in either the coronal or sagittal image';
            app.BtnPlaceL1.ButtonPushedFcn = @(~,~)app.placeL1();

            app.BtnPlaceL2 = uibutton(ctrlGrid,'push');
            app.BtnPlaceL2.Layout.Column=2;
            app.BtnPlaceL2.Text='Mark L2';
            app.BtnPlaceL2.FontSize=12; app.BtnPlaceL2.FontWeight='bold';
            app.BtnPlaceL2.BackgroundColor=[0.38 0.62 0.92];
            app.BtnPlaceL2.Tooltip='Click, then click on L2 in either the coronal or sagittal image';
            app.BtnPlaceL2.ButtonPushedFcn = @(~,~)app.placeL2();

            app.BtnClearL12 = uibutton(ctrlGrid,'push');
            app.BtnClearL12.Layout.Column=3;
            app.BtnClearL12.Text='Clear marks';
            app.BtnClearL12.FontSize=12;
            app.BtnClearL12.ButtonPushedFcn = @(~,~)app.clearL12();

            app.LblL12Status = uilabel(ctrlGrid);
            app.LblL12Status.Layout.Column=[4 5];
            app.LblL12Status.Text='Scroll wheel over image to navigate.  Click Mark L1/L2, then click in coronal or sagittal.';
            app.LblL12Status.FontSize=12; app.LblL12Status.FontColor=[0.4 0.4 0.4];

            % Scroll-wheel and mouse-hover tracking (figure-level, registered once)
            app.UIFigure.WindowScrollWheelFcn   = @(~,e)app.onScrollWheel(e);
            app.UIFigure.WindowButtonMotionFcn  = @(~,~)app.onMouseMove();
        end

        % ── DIXON TAB ────────────────────────────────────────────────────
        function createDixonTab(app)
            app.DixonTab = uitab(app.ImageTabGroup,'Title','Dixon / Body Comp');

            app.DixonGrid = uigridlayout(app.DixonTab,[1 2]);
            app.DixonGrid.ColumnWidth  = {'1x',180};
            app.DixonGrid.RowHeight    = {'1x'};
            app.DixonGrid.Padding      = [4 4 4 4];
            app.DixonGrid.ColumnSpacing = 6;

            % Image area (3 panels stacked vertically within left column)
            imgArea = uipanel(app.DixonGrid,'BorderType','none');
            imgArea.Layout.Column = 1;
            imgG = uigridlayout(imgArea,[2 3]);
            imgG.RowHeight   = {'1x',34}; imgG.ColumnWidth = {'1x','1x','1x'};
            imgG.Padding     = [0 0 0 0]; imgG.ColumnSpacing = 4;

            app.AxDixonWater = uiaxes(imgG);
            app.AxDixonWater.Layout.Row=1; app.AxDixonWater.Layout.Column=1;
            setupDarkAxes(app.AxDixonWater,'Water');

            app.AxDixonPDFF = uiaxes(imgG);
            app.AxDixonPDFF.Layout.Row=1; app.AxDixonPDFF.Layout.Column=2;
            setupDarkAxes(app.AxDixonPDFF,'PDFF (%)'); colormap(app.AxDixonPDFF,'hot');

            app.AxDixonIP = uiaxes(imgG);
            app.AxDixonIP.Layout.Row=1; app.AxDixonIP.Layout.Column=3;
            setupDarkAxes(app.AxDixonIP,'In-Phase');

            % Slice control
            slCtrl = uigridlayout(imgG,[1 4]);
            slCtrl.Layout.Row=2; slCtrl.Layout.Column=[1 3];
            slCtrl.ColumnWidth={70,'1x',60,180}; slCtrl.Padding=[0 4 0 4];
            lsd = uilabel(slCtrl); lsd.Layout.Column=1;
            lsd.Text='Slice:'; lsd.FontSize=13; lsd.FontWeight='bold';
            app.SldrDixon = uislider(slCtrl);
            app.SldrDixon.Layout.Column=2; app.SldrDixon.Limits=[1 28];
            app.SldrDixon.Value=14; app.SldrDixon.MajorTicks=[];
            app.SldrDixon.MinorTicks=[];
            app.SldrDixon.ValueChangedFcn = @(src,~)app.onDixonSlide(src);
            app.LblDixonSlice = uilabel(slCtrl); app.LblDixonSlice.Layout.Column=3;
            app.LblDixonSlice.Text='14/28'; app.LblDixonSlice.FontSize=12;
            app.LblDixonSlice.HorizontalAlignment='center';
            app.LblDixonInfo = uilabel(slCtrl); app.LblDixonInfo.Layout.Column=4;
            app.LblDixonInfo.Text='Pixel: 1.56mm  Slice: 8mm';
            app.LblDixonInfo.FontSize=10; app.LblDixonInfo.FontColor=[0.5 0.5 0.5];

            % ROI panel (right column)
            roiPnl = uipanel(app.DixonGrid,'Title','ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            roiPnl.Layout.Column = 2;
            rg = uigridlayout(roiPnl,[10 1]);
            rg.RowHeight   = repmat({36},1,10); rg.Padding=[4 4 4 4]; rg.RowSpacing=4;

            uilabel(rg,'Text','Organ volumes:','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);

            app.BtnROI_LiverDixon = roiBtn(rg,2,'Liver (entire)', ...
                [0.22 0.55 0.22],[1 1 1]);
            app.BtnROI_LiverDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('LiverDixon');

            app.BtnROI_SpleenDixon = roiBtn(rg,3,'Spleen (entire)', ...
                [0.20 0.50 0.70],[1 1 1]);
            app.BtnROI_SpleenDixon.ButtonPushedFcn = @(~,~)app.drawDixonROI('SpleenDixon');

            uilabel(rg,'Text','L1-L2 body comp:','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);

            app.BtnROI_MuscleL1 = roiBtn(rg,5,'Muscle @ L1', ...
                [0.78 0.22 0.12],[1 1 1]);
            app.BtnROI_MuscleL1.ButtonPushedFcn = @(~,~)app.drawDixonROI('MuscleL1');

            app.BtnROI_MuscleL2 = roiBtn(rg,6,'Muscle @ L2', ...
                [0.90 0.40 0.12],[1 1 1]);
            app.BtnROI_MuscleL2.ButtonPushedFcn = @(~,~)app.drawDixonROI('MuscleL2');

            app.BtnROI_SATL1 = roiBtn(rg,7,'SAT @ L1', ...
                [0.14 0.28 0.85],[1 1 1]);
            app.BtnROI_SATL1.ButtonPushedFcn = @(~,~)app.drawDixonROI('SATL1');

            app.BtnROI_SATL2 = roiBtn(rg,8,'SAT @ L2', ...
                [0.30 0.44 0.92],[1 1 1]);
            app.BtnROI_SATL2.ButtonPushedFcn = @(~,~)app.drawDixonROI('SATL2');

            app.BtnClearDixonROIs = roiBtn(rg,10,'Clear this slice', ...
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

            % Image area
            imgArea = uipanel(app.MREGrid,'BorderType','none');
            imgArea.Layout.Column = 1;
            imgG = uigridlayout(imgArea,[2 3]);
            imgG.RowHeight   = {'1x',44}; imgG.ColumnWidth = {'1x','1x','1x'};
            imgG.Padding     = [0 0 0 0]; imgG.ColumnSpacing = 4;

            app.AxMREMag = uiaxes(imgG);
            app.AxMREMag.Layout.Row=1; app.AxMREMag.Layout.Column=1;
            setupDarkAxes(app.AxMREMag,'Magnitude');

            app.AxMREWave = uiaxes(imgG);
            app.AxMREWave.Layout.Row=1; app.AxMREWave.Layout.Column=2;
            setupDarkAxes(app.AxMREWave,'Wave (phase 1/4)');
            colormap(app.AxMREWave, mreWaveCmap());

            app.AxMREStiff = uiaxes(imgG);
            app.AxMREStiff.Layout.Row=1; app.AxMREStiff.Layout.Column=3;
            setupDarkAxes(app.AxMREStiff,'Stiffness (kPa)');
            colormap(app.AxMREStiff, mreStiffCmap());
            colorbar(app.AxMREStiff,'FontSize',9,'Color',[0.7 0.7 0.7]);

            % Controls row
            ctrlG = uigridlayout(imgG,[1 7]);
            ctrlG.Layout.Row=2; ctrlG.Layout.Column=[1 3];
            ctrlG.ColumnWidth={56,'1x',56,90,80,80,80}; ctrlG.Padding=[0 4 0 4];

            lmr = uilabel(ctrlG); lmr.Layout.Column=1;
            lmr.Text='Slice:'; lmr.FontSize=13; lmr.FontWeight='bold';

            app.SldrMRE = uislider(ctrlG);
            app.SldrMRE.Layout.Column=2; app.SldrMRE.Limits=[1 4];
            app.SldrMRE.Value=2; app.SldrMRE.MajorTicks=[];
            app.SldrMRE.MinorTicks=[];
            app.SldrMRE.ValueChangedFcn = @(src,~)app.onMRESlide(src);

            app.LblMRESlice = uilabel(ctrlG); app.LblMRESlice.Layout.Column=3;
            app.LblMRESlice.Text='2/4'; app.LblMRESlice.FontSize=12;
            app.LblMRESlice.HorizontalAlignment='center';

            app.BtnMREPlay = uibutton(ctrlG,'push');
            app.BtnMREPlay.Layout.Column=4;
            app.BtnMREPlay.Text='▶ Play wave';
            app.BtnMREPlay.FontSize=12; app.BtnMREPlay.FontWeight='bold';
            app.BtnMREPlay.BackgroundColor=[0.18 0.60 0.34];
            app.BtnMREPlay.FontColor=[1 1 1];
            app.BtnMREPlay.ButtonPushedFcn = @(~,~)app.toggleMREPlay();

            app.BtnStiff8 = uibutton(ctrlG,'push');
            app.BtnStiff8.Layout.Column=5;
            app.BtnStiff8.Text='0-8 kPa';
            app.BtnStiff8.FontSize=12; app.BtnStiff8.FontWeight='bold';
            app.BtnStiff8.BackgroundColor=[0.25 0.55 0.85];
            app.BtnStiff8.FontColor=[1 1 1];
            app.BtnStiff8.ButtonPushedFcn = @(~,~)app.setStiffScale([0 8]);

            app.BtnStiff20 = uibutton(ctrlG,'push');
            app.BtnStiff20.Layout.Column=6;
            app.BtnStiff20.Text='0-20 kPa';
            app.BtnStiff20.FontSize=12;
            app.BtnStiff20.BackgroundColor=[0.70 0.88 0.70];
            app.BtnStiff20.FontColor=[0.1 0.3 0.1];
            app.BtnStiff20.ButtonPushedFcn = @(~,~)app.setStiffScale([0 20]);

            app.BtnConfMap = uibutton(ctrlG,'state');
            app.BtnConfMap.Layout.Column=7;
            app.BtnConfMap.Text='Conf. mask';
            app.BtnConfMap.FontSize=12;
            app.BtnConfMap.Value=false;
            app.BtnConfMap.ValueChangedFcn = @(~,~)app.toggleConfMask();

            % ROI panel
            roiPnl = uipanel(app.MREGrid,'Title','MRE ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            roiPnl.Layout.Column = 2;
            rg = uigridlayout(roiPnl,[8 1]);
            rg.RowHeight   = repmat({36},1,8); rg.Padding=[4 4 4 4]; rg.RowSpacing=4;

            uilabel(rg,'Text','Stiffness ROIs:','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);

            app.BtnROI_LiverMRE = roiBtn(rg,2,'Liver stiffness', ...
                [0.22 0.55 0.22],[1 1 1]);
            app.BtnROI_LiverMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('LiverMRE');

            app.BtnROI_SpleenMRE = roiBtn(rg,3,'Spleen stiffness', ...
                [0.20 0.50 0.70],[1 1 1]);
            app.BtnROI_SpleenMRE.ButtonPushedFcn = @(~,~)app.drawMREROI('SpleenMRE');

            uilabel(rg,'Text','ROI info:','FontSize',11, ...
                'FontWeight','bold','FontColor',[0.3 0.3 0.3]);

            app.LblMREInfo = uilabel(rg);
            app.LblMREInfo.Layout.Row=[5 7];
            app.LblMREInfo.Text='Draw ROI on wave image (inner) or magnitude (contour).  ROI saved per slice.';
            app.LblMREInfo.FontSize=11; app.LblMREInfo.WordWrap='on';
            app.LblMREInfo.FontColor=[0.45 0.45 0.45];

            app.BtnClearMREROIs = roiBtn(rg,8,'Clear this slice', ...
                [0.72 0.72 0.72],[0.2 0.2 0.2]);
            app.BtnClearMREROIs.ButtonPushedFcn = @(~,~)app.clearMRESlice();
        end

        % ── RESULTS TAB ──────────────────────────────────────────────────
        function createResultsTab(app)
            app.ResultsTab = uitab(app.ImageTabGroup,'Title','Results');
            app.ResultsGrid = uigridlayout(app.ResultsTab,[1 1]);
            app.ResultsGrid.Padding=[8 8 8 8];

            app.ResultsTable = uitable(app.ResultsGrid);
            app.ResultsTable.Layout.Row=1; app.ResultsTable.Layout.Column=1;
            app.ResultsTable.FontSize=12;
            app.ResultsTable.ColumnName = {'Measurement','Value','Unit','Notes'};
            app.ResultsTable.Data       = {'No data yet','—','—','Load a study first'};
            app.ResultsTable.ColumnWidth= {220,120,80,250};
        end

        % -----------------------------------------------------------------
        function createRightPanel(app)
            app.RightPanel = uipanel(app.BodyGrid,'Title','Measurements', ...
                'FontSize',13,'FontWeight','bold');
            app.RightPanel.Layout.Column = 3;

            app.RightGrid = uigridlayout(app.RightPanel,[6 1]);
            app.RightGrid.RowHeight   = {110,100,110,110,80,80};
            app.RightGrid.ColumnWidth = {'1x'};
            app.RightGrid.Padding     = [2 2 2 2];
            app.RightGrid.RowSpacing  = 2;

            addMeasSection(app,1,'Dixon — Organ size & PDFF', ...
                {'Liver vol.','Liver PDFF','Spleen vol.','Spleen PDFF'}, ...
                {'ValLiverDixonVol','ValLiverDixonPDFF', ...
                 'ValSpleenDixonVol','ValSpleenDixonPDFF'});

            addMeasSection(app,2,'L1-L2 — Muscle', ...
                {'Muscle area L1','Muscle PDFF L1', ...
                 'Muscle area L2','Muscle PDFF L2'}, ...
                {'ValMuscleL1Area','ValMuscleL1PDFF', ...
                 'ValMuscleL2Area','ValMuscleL2PDFF'});

            addMeasSection(app,3,'L1-L2 — SAT & ratio', ...
                {'SAT area L1','SAT PDFF L1', ...
                 'SAT area L2','SAT PDFF L2','Muscle:SAT ratio'}, ...
                {'ValSATL1Area','ValSATL1PDFF', ...
                 'ValSATL2Area','ValSATL2PDFF','ValMuscleSATRatio'});

            addMeasSection(app,4,'MRE — Stiffness', ...
                {'Liver stiffness','Liver IQR', ...
                 'Spleen stiffness','Spleen IQR'}, ...
                {'ValLiverStiff','ValLiverStiffIQR', ...
                 'ValSpleenStiff','ValSpleenStiffIQR'});

            addMeasSection(app,5,'QC', ...
                {'Seg. confidence','Coverage'}, ...
                {'ValSegConf','ValCoverage'});
        end

        function addMeasSection(app, row, sectionTitle, labels, propNames)
            pnl = uipanel(app.RightGrid,'Title',sectionTitle, ...
                'FontSize',11,'FontWeight','bold');
            pnl.Layout.Row=row;
            n = numel(labels);
            g = uigridlayout(pnl,[n 2]);
            g.ColumnWidth={'1x','1x'}; g.RowHeight=repmat({20},1,n);
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

            app.BottomGrid = uigridlayout(app.BottomPanel,[2 6]);
            app.BottomGrid.RowHeight    = {'1x',18};
            app.BottomGrid.ColumnWidth  = {'1x','1x','1x','1x',8,'2x'};
            app.BottomGrid.Padding      = [6 3 6 2]; app.BottomGrid.ColumnSpacing=4;

            stepLabels = {'Localizer / L1-L2','Dixon + ROIs','MRE + ROIs','Export'};
            stepProps  = {'BtnStepLoc','BtnStepDixon','BtnStepMRE','BtnStepResults'};
            stepCBs    = {@(~,~)app.activateTab('loc'), ...
                          @(~,~)app.activateTab('dixon'), ...
                          @(~,~)app.activateTab('mre'), ...
                          @(~,~)app.activateTab('results')};
            for k=1:4
                b = uibutton(app.BottomGrid,'push');
                b.Layout.Row=1; b.Layout.Column=k;
                b.Text=stepLabels{k}; b.FontSize=12;
                b.BackgroundColor=[0.80 0.80 0.80];
                b.ButtonPushedFcn=stepCBs{k};
                app.(stepProps{k})=b;
            end

            sep=uilabel(app.BottomGrid); sep.Layout.Row=1; sep.Layout.Column=5;
            sep.Text='|'; sep.HorizontalAlignment='center'; sep.FontColor=[0.6 0.6 0.6];

            app.LblStatusMsg = uilabel(app.BottomGrid);
            app.LblStatusMsg.Layout.Row=2; app.LblStatusMsg.Layout.Column=[1 6];
            app.LblStatusMsg.Text='Ready — click Load Study to begin.';
            app.LblStatusMsg.FontSize=11; app.LblStatusMsg.FontColor=[0.40 0.40 0.40];
        end

    end % createComponents

    % =====================================================================
    %  STARTUP
    % =====================================================================
    methods (Access = private)
        function startupFcn(app)
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

            dlg = uiprogressdlg(app.UIFigure,'Title','Loading Study', ...
                'Message','Parsing DICOM exam...','Indeterminate','on');

            try
                % 2. Parse
                setStatus(app,'Parsing DICOM exam...');
                exam = mre_parseDICOMExam(folderPath, struct('verbose',false));
                app.AppData.Exam = exam;

                close(dlg);

                % 3. Series selection GUI (inside the main figure context)
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
                                 'forceRebuild',false,'interpolateWave',true);
                matPath = '';

                % 4. Build MRE MAT (only if MRE series was selected)
                if ~isempty(selection.MRE)
                    dlg.Message = 'Building MRE MAT file...';
                    matPath = mre_buildMATFile(exam, matOpts);
                end
                app.AppData.MATPath = matPath;

                % 5. Load Localizer
                if ~isempty(selection.Localizer)
                    dlg.Message = 'Loading localizer...';
                    app.AppData.Localizer = loc_loadLocalizer( ...
                        selection.Localizer, struct('verbose',false));
                    populateLocalizerTab(app);
                end

                % 6. Build Dixon volumes
                if ~isempty(selection.DixonGroup)
                    dlg.Message = 'Building Dixon volumes...';
                    app.AppData.Dixon = seg_buildDixonVolume( ...
                        selection.DixonGroup, struct('verbose',false));
                    populateDixonTab(app);
                end

                % 7. Load MRE .mat
                if ~isempty(matPath) && isfile(matPath)
                    dlg.Message = 'Loading MRE data...';
                    tmp = load(matPath,'M','W','S','LapC','H');
                    app.AppData.MRE = tmp;
                    populateMRETab(app);
                end

                % 8. Update patient info
                app.LblPatientInfo.Text = sprintf('%s  |  %s  |  %s', ...
                    exam.PatientID, exam.StudyDate, exam.MREType);
                app.BtnRunPipeline.Enable  = 'on';
                app.BtnConfirmL12.Enable   = 'on';

                updateStudyBrowser(app, exam, selection);
                setStatus(app,sprintf('Loaded: %s — %s | %d series', ...
                    exam.PatientID, exam.StudyDate, numel(exam.Series)));

            catch ME
                if isvalid(dlg), close(dlg); end
                uialert(app.UIFigure, ME.message,'Load Error','Icon','error');
                setStatus(app,['ERROR: ' ME.message]);
            end
            if isvalid(dlg), close(dlg); end
        end

        % ── RUN FULL PIPELINE ─────────────────────────────────────────────
        function runPipeline(app)
            if isempty(app.AppData.Exam)
                uialert(app.UIFigure,'Please load a study first.','No Study');
                return
            end
            opts = struct('verbose',true,'outputDir',app.AppData.Exam.ExamRootDir, ...
                'subjectId',sprintf('%s_%s', ...
                    app.AppData.Exam.PatientID, app.AppData.Exam.StudyDate));
            results = seg_runFullPipeline(app.AppData.Exam, app.AppData.Selection, ...
                app.AppData.MATPath, opts);
            updateResultsFromStruct(app, results);
            activateTab(app,'results');
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

        function placeL1(app)
            if isempty(app.AppData.Localizer)
                uialert(app.UIFigure,'Load a study first.','No Localizer');
                return
            end
            % Cancel any pending placement first
            cancelPendingClick(app);
            app.AppData.AwaitingClick = 'L1';
            app.BtnPlaceL1.BackgroundColor = [1.0 0.95 0.2];  % highlight active
            setStatus(app,'Click on the L1 vertebra in the coronal or sagittal image…');
            app.LblL12Status.Text = 'Waiting for L1 click on either image…';
            app.AxLocCoronal.ButtonDownFcn  = @(~,e)app.onLocImageClick(e,'cor','L1');
            app.AxLocSagittal.ButtonDownFcn = @(~,e)app.onLocImageClick(e,'sag','L1');
        end

        function placeL2(app)
            if isempty(app.AppData.Localizer)
                uialert(app.UIFigure,'Load a study first.','No Localizer');
                return
            end
            % Cancel any pending placement first
            cancelPendingClick(app);
            app.AppData.AwaitingClick = 'L2';
            app.BtnPlaceL2.BackgroundColor = [0.80 0.95 1.0];  % highlight active
            setStatus(app,'Click on the L2 vertebra in the coronal or sagittal image…');
            app.LblL12Status.Text = 'Waiting for L2 click on either image…';
            app.AxLocCoronal.ButtonDownFcn  = @(~,e)app.onLocImageClick(e,'cor','L2');
            app.AxLocSagittal.ButtonDownFcn = @(~,e)app.onLocImageClick(e,'sag','L2');
        end

        function cancelPendingClick(app)
            % Clear any previously armed ButtonDownFcn on localizer axes
            try; app.AxLocCoronal.ButtonDownFcn  = ''; catch; end
            try; app.AxLocSagittal.ButtonDownFcn = ''; catch; end
            app.AppData.AwaitingClick = '';
            app.BtnPlaceL1.BackgroundColor = [0.92 0.60 0.12];
            app.BtnPlaceL2.BackgroundColor = [0.38 0.62 0.92];
        end

        function clearL12(app)
            cancelPendingClick(app);
            app.AppData.L1_CorRow = NaN;
            app.AppData.L2_CorRow = NaN;
            app.AppData.L1_SagRow = NaN;
            app.AppData.L2_SagRow = NaN;
            refreshLocCoronal(app);
            refreshLocSagittal(app);
            app.LblL12Status.Text = 'L1/L2 cleared.';
            setStatus(app,'L1-L2 cleared.');
        end

        function updateL12Status(app)
            l1r = app.AppData.L1_CorRow;
            l2r = app.AppData.L2_CorRow;
            if isnan(l1r) && isnan(l2r)
                app.LblL12Status.Text = 'No L1/L2 placed yet.';
            elseif isnan(l2r)
                app.LblL12Status.Text = sprintf('L1 placed  |  L2: not placed yet.  Click Mark L2.');
            elseif isnan(l1r)
                app.LblL12Status.Text = sprintf('L1: not placed  |  L2 placed.  Click Mark L1.');
            else
                app.LblL12Status.Text = sprintf('L1 placed  |  L2 placed  — press Confirm L1-L2 in toolbar.');
                app.BtnConfirmL12.Enable = 'on';
            end
        end

        function confirmL12(app)
            if isnan(app.AppData.L1_CorRow) || isnan(app.AppData.L2_CorRow)
                uialert(app.UIFigure,'Place both L1 and L2 markers first.','Missing Marks');
                return
            end
            % Convert row position to mm using localizer spatial info
            loc = app.AppData.Localizer;
            if isempty(loc), return; end

            sinfo = loc.Coronal.SpatialInfo;
            L12 = rowsToL12mm(app, sinfo);
            app.AppData.L12 = L12;

            % Propagate to Dixon
            if ~isempty(app.AppData.Dixon) && ~isempty(app.AppData.Dixon.SpatialInfo) && ...
               isfield(app.AppData.Dixon.SpatialInfo,'AffineMatrix')
                app.AppData.L12_Dixon = loc_propagateToSpace(L12, ...
                    app.AppData.Dixon.SpatialInfo, struct('verbose',false));
                setStatus(app,sprintf( ...
                    'L1/L2 confirmed.  Dixon: L1→sl%d  L2→sl%d.  Switch to Dixon tab.', ...
                    app.AppData.L12_Dixon.L1_sliceIdx, app.AppData.L12_Dixon.L2_sliceIdx));
            end

            % Update Dixon slider to L1 level
            if ~isempty(app.AppData.L12_Dixon) && ~isnan(app.AppData.L12_Dixon.L1_sliceIdx)
                sl = max(1, min(app.AppData.Dixon.nSlices, ...
                    round(app.AppData.L12_Dixon.L1_sliceIdx)));
                app.SldrDixon.Value = sl;
                app.AppData.DixonSlice = sl;
                refreshDixon(app);
            end

            app.BtnStepDixon.BackgroundColor = [0.70 0.88 0.70];
            activateTab(app,'dixon');
        end

        % ── DIXON ─────────────────────────────────────────────────────────
        function onDixonSlide(app, src)
            sl = round(src.Value);
            app.AppData.DixonSlice = sl;
            nZ = max(1, app.AppData.Dixon.nSlices);
            app.LblDixonSlice.Text = sprintf('%d/%d', sl, nZ);
            refreshDixon(app);
        end

        function drawDixonROI(app, roiName)
            if isempty(app.AppData.Dixon)
                uialert(app.UIFigure,'No Dixon data loaded.','No Data');
                return
            end
            sl = app.AppData.DixonSlice;

            % For L1/L2 ROIs, jump to the correct slice first
            switch roiName
                case 'MuscleL1', if ~isnan(app.AppData.L12_Dixon.L1_sliceIdx)
                    sl = round(app.AppData.L12_Dixon.L1_sliceIdx);
                    app.AppData.DixonSlice = sl;
                    app.SldrDixon.Value = sl;
                    refreshDixon(app);
                end
                case 'MuscleL2', if ~isnan(app.AppData.L12_Dixon.L2_sliceIdx)
                    sl = round(app.AppData.L12_Dixon.L2_sliceIdx);
                    app.AppData.DixonSlice = sl;
                    app.SldrDixon.Value = sl;
                    refreshDixon(app);
                end
                case 'SATL1', if ~isnan(app.AppData.L12_Dixon.L1_sliceIdx)
                    sl = round(app.AppData.L12_Dixon.L1_sliceIdx);
                    app.AppData.DixonSlice = sl;
                    app.SldrDixon.Value = sl;
                    refreshDixon(app);
                end
                case 'SATL2', if ~isnan(app.AppData.L12_Dixon.L2_sliceIdx)
                    sl = round(app.AppData.L12_Dixon.L2_sliceIdx);
                    app.AppData.DixonSlice = sl;
                    app.SldrDixon.Value = sl;
                    refreshDixon(app);
                end
            end

            setStatus(app,sprintf('Draw %s ROI on the water image (freehand).  Double-click to close.', ...
                strrep(roiName,'_',' ')));
            try
                h = drawfreehand(app.AxDixonWater,'Color',dixonROIColor(roiName), ...
                    'LineWidth',2,'FaceAlpha',0.15);
                wait(h);
                nR = size(app.AppData.Dixon.Water,1);
                nC = size(app.AppData.Dixon.Water,2);
                mask = logical(h.createMask());
                storeROI(app, roiName, sl, mask, nR, nC);
                overlayROIOnDixon(app, roiName, mask);
                computeDixonROIStats(app, roiName, mask, sl);
                setStatus(app,sprintf('%s ROI placed on slice %d.', roiName, sl));
            catch ME
                setStatus(app,['ROI error: ' ME.message]);
            end
        end

        function clearDixonSlice(app)
            sl = app.AppData.DixonSlice;
            app.AppData.ROIs.LiverDixon.Slices  = removeSlice(app.AppData.ROIs.LiverDixon.Slices,  sl);
            app.AppData.ROIs.SpleenDixon.Slices = removeSlice(app.AppData.ROIs.SpleenDixon.Slices, sl);
            app.AppData.ROIs.MuscleL1 = [];
            app.AppData.ROIs.MuscleL2 = [];
            app.AppData.ROIs.SATL1    = [];
            app.AppData.ROIs.SATL2    = [];
            refreshDixon(app);
            setStatus(app,sprintf('ROIs cleared for Dixon slice %d.',sl));
        end

        % ── MRE ───────────────────────────────────────────────────────────
        function onMRESlide(app, src)
            sl = round(src.Value);
            app.AppData.MRESlice = sl;
            nZ = max(1, size(app.AppData.MRE.S,3));
            app.LblMRESlice.Text = sprintf('%d/%d',sl,nZ);
            refreshMRE(app);
        end

        function toggleMREPlay(app)
            if app.AppData.MREPlaying
                % Stop
                if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                    stop(app.AppData.MRETimer);
                    delete(app.AppData.MRETimer);
                    app.AppData.MRETimer = [];
                end
                app.AppData.MREPlaying = false;
                app.BtnMREPlay.Text = '▶ Play wave';
                app.BtnMREPlay.BackgroundColor = [0.18 0.60 0.34];
            else
                % Start
                app.AppData.MREPlaying = true;
                app.BtnMREPlay.Text = '⏸ Pause';
                app.BtnMREPlay.BackgroundColor = [0.75 0.35 0.10];
                t = timer('ExecutionMode','fixedRate','Period',0.15, ...
                    'TimerFcn',@(~,~)app.advanceWaveFrame());
                app.AppData.MRETimer = t;
                start(t);
            end
        end

        function advanceWaveFrame(app)
            if isempty(app.AppData.MRE) || ~isfield(app.AppData.MRE,'W'), return; end
            nPh = size(app.AppData.MRE.W, 4);
            ph  = mod(app.AppData.MREPhase, nPh) + 1;
            app.AppData.MREPhase = ph;
            sl  = app.AppData.MRESlice;
            W   = app.AppData.MRE.W;
            img = double(W(:,:,min(sl,end),ph));
            imagesc(app.AxMREWave, img);
            title(app.AxMREWave, sprintf('Wave (phase %d/%d)', ph, nPh), ...
                'FontSize',12,'Color',[0.75 0.75 0.75],'FontWeight','normal');
        end

        function drawMREROI(app, roiName)
            if isempty(app.AppData.MRE)
                uialert(app.UIFigure,'No MRE data loaded.','No Data');
                return
            end
            sl = app.AppData.MRESlice;
            setStatus(app,sprintf('Draw %s ROI on the wave image.  Double-click to close.',roiName));
            try
                h = drawfreehand(app.AxMREWave,'Color',mreROIColor(roiName), ...
                    'LineWidth',2,'FaceAlpha',0.15);
                wait(h);
                nR = size(app.AppData.MRE.M,1);
                nC = size(app.AppData.MRE.M,2);
                mask = logical(h.createMask());
                storeROI(app, roiName, sl, mask, nR, nC);
                computeMREROIStats(app, roiName, mask, sl);
                setStatus(app,sprintf('%s ROI placed on slice %d.',roiName,sl));
            catch ME
                setStatus(app,['ROI error: ' ME.message]);
            end
        end

        function clearMRESlice(app)
            sl = app.AppData.MRESlice;
            app.AppData.ROIs.LiverMRE.Slices  = removeSlice(app.AppData.ROIs.LiverMRE.Slices,  sl);
            app.AppData.ROIs.SpleenMRE.Slices = removeSlice(app.AppData.ROIs.SpleenMRE.Slices, sl);
            refreshMRE(app);
            setStatus(app,sprintf('MRE ROIs cleared for slice %d.',sl));
        end

        function setStiffScale(app, clim)
            app.AppData.StiffCLim = clim;
            if ~isempty(app.AppData.MRE)
                clim(app.AxMREStiff, clim);
            end
            setStatus(app,sprintf('Stiffness scale: %.0f–%.0f kPa',clim(1),clim(2)));
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
        function exportCSV(app)
            setStatus(app,'[Phase 7] Export CSV — not yet implemented.');
        end
        function exportROIs(app)
            setStatus(app,'[Phase 7] Export ROI masks — not yet implemented.');
        end
        function exportPDF(app)
            setStatus(app,'[Phase 7] Export PDF — not yet implemented.');
        end
        function saveSession(app)
            setStatus(app,'[Phase 7] Save session — not yet implemented.');
        end
        function loadSession(app)
            setStatus(app,'[Phase 7] Load session — not yet implemented.');
        end
        function setColormap(app,~)
            % Placeholder
        end
        function showAbout(~)
            msgbox(sprintf(['HepatosplenicMRE Platform  v2.0\n\n' ...
                'Mayo Clinic R01 Collaboration\nPI: Meng Yin, PhD']), ...
                'About','help');
        end
        function onStudySelect(app,event)
            n=event.SelectedNodes;
            if ~isempty(n), setStatus(app,sprintf('Selected: %s',n.Text)); end
        end
        function onTabChange(app,~)
            % Tab changed — could trigger data load if needed
        end
        function activateTab(app, which)
            tabs = struct('loc',app.LocTab,'dixon',app.DixonTab, ...
                          'mre',app.MRETab,'results',app.ResultsTab);
            if isfield(tabs,which)
                app.ImageTabGroup.SelectedTab = tabs.(which);
            end
        end
        function onClose(app)
            % Stop any running timer
            if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                stop(app.AppData.MRETimer);
                delete(app.AppData.MRETimer);
            end
            sel = uiconfirm(app.UIFigure,'Close HepatosplenicMRE?','Exit', ...
                'Options',{'Close','Cancel'},'DefaultOption','Cancel','CancelOption','Cancel');
            if strcmp(sel,'Close'), delete(app.UIFigure); end
        end
    end

    % =====================================================================
    %  PRIVATE DISPLAY HELPERS
    % =====================================================================
    methods (Access = private)

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
            showImg(app.AxLocCoronal, img, sprintf('Coronal  slice %d',sl));
            % Draw L1/L2 lines
            hold(app.AxLocCoronal,'on');
            nC = size(img,2);
            if ~isnan(app.AppData.L1_CorRow)
                plot(app.AxLocCoronal,[1 nC],[app.AppData.L1_CorRow app.AppData.L1_CorRow], ...
                    '-','Color',[0.95 0.60 0.10],'LineWidth',2.5);
                text(app.AxLocCoronal, nC-2, app.AppData.L1_CorRow-3,'L1', ...
                    'Color',[0.95 0.60 0.10],'FontSize',12,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            if ~isnan(app.AppData.L2_CorRow)
                plot(app.AxLocCoronal,[1 nC],[app.AppData.L2_CorRow app.AppData.L2_CorRow], ...
                    '-','Color',[0.38 0.62 0.92],'LineWidth',2.5);
                text(app.AxLocCoronal, nC-2, app.AppData.L2_CorRow-3,'L2', ...
                    'Color',[0.38 0.62 0.92],'FontSize',12,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            hold(app.AxLocCoronal,'off');
        end

        function refreshLocSagittal(app)
            loc = app.AppData.Localizer;
            if isempty(loc) || isempty(loc.Sagittal.Volume), return; end
            sl  = app.AppData.SagSlice;
            nSl = size(loc.Sagittal.Volume,3);
            sl  = max(1, min(nSl, sl));
            img = double(loc.Sagittal.Volume(:,:,sl));
            showImg(app.AxLocSagittal, img, sprintf('Sagittal  %d/%d',sl,nSl));
            % Overlay L1/L2 lines, converted from coronal mm coordinates
            hold(app.AxLocSagittal,'on');
            nC = size(img,2);
            l1_sagRow = corRowToSagRow(app, app.AppData.L1_CorRow, sl);
            l2_sagRow = corRowToSagRow(app, app.AppData.L2_CorRow, sl);
            if ~isnan(l1_sagRow)
                plot(app.AxLocSagittal,[1 nC],[l1_sagRow l1_sagRow], ...
                    '-','Color',[0.95 0.60 0.10],'LineWidth',2.5);
                text(app.AxLocSagittal, nC-2, l1_sagRow-3,'L1', ...
                    'Color',[0.95 0.60 0.10],'FontSize',12,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            if ~isnan(l2_sagRow)
                plot(app.AxLocSagittal,[1 nC],[l2_sagRow l2_sagRow], ...
                    '-','Color',[0.38 0.62 0.92],'LineWidth',2.5);
                text(app.AxLocSagittal, nC-2, l2_sagRow-3,'L2', ...
                    'Color',[0.38 0.62 0.92],'FontSize',12,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            hold(app.AxLocSagittal,'off');
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
            app.SldrDixon.Limits = [1 max(nZ,2)];
            app.SldrDixon.Value  = dixMid;
            app.AppData.DixonSlice = dixMid;
            app.LblDixonSlice.Text = sprintf('%d/%d', dixMid, nZ);
            app.LblDixonInfo.Text  = sprintf('Pixel: %.2fmm  Slice: %.1fmm', ...
                dix.PixelSpacing_mm(1), dix.SliceThickness_mm);
            refreshDixon(app);
        end

        function refreshDixon(app)
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            sl = app.AppData.DixonSlice;
            nZ = max(1, dix.nSlices);
            sl = max(1, min(nZ, sl));

            % Water
            if ~isempty(dix.Water)
                img = double(dix.Water(:,:,min(sl,end)));
                showImg(app.AxDixonWater, img, sprintf('Water  sl %d',sl));
            end
            % PDFF
            if ~isempty(dix.PDFF)
                img = double(dix.PDFF(:,:,min(sl,end)));
                imagesc(app.AxDixonPDFF, img); clim(app.AxDixonPDFF,[0 100]);
                colormap(app.AxDixonPDFF,'hot'); axis(app.AxDixonPDFF,'image');
                app.AxDixonPDFF.XTick=[]; app.AxDixonPDFF.YTick=[];
                title(app.AxDixonPDFF,sprintf('PDFF (%%)  sl %d',sl),'FontSize',12, ...
                    'Color',[0.75 0.75 0.75],'FontWeight','normal');
            end
            % In-phase
            if ~isempty(dix.InPhase)
                img = double(dix.InPhase(:,:,min(sl,end)));
                showImg(app.AxDixonIP, img, sprintf('In-Phase  sl %d',sl));
            end

            % Overlay L1/L2 lines if available
            l12d = app.AppData.L12_Dixon;
            if ~isempty(l12d) && ~isnan(l12d.L1_sliceIdx)
                for ax = [app.AxDixonWater, app.AxDixonPDFF, app.AxDixonIP]
                    hold(ax,'on');
                    nC = size(app.AppData.Dixon.Water,2);
                    if sl == round(l12d.L1_sliceIdx)
                        plot(ax,[1 nC],[nC/2 nC/2],'--','Color',[0.95 0.60 0.10],'LineWidth',1.5);
                        text(ax,4,10,'L1','Color',[0.95 0.60 0.10],'FontSize',11,'FontWeight','bold');
                    end
                    if sl == round(l12d.L2_sliceIdx)
                        plot(ax,[1 nC],[nC/2 nC/2],'--','Color',[0.38 0.62 0.92],'LineWidth',1.5);
                        text(ax,4,10,'L2','Color',[0.38 0.62 0.92],'FontSize',11,'FontWeight','bold');
                    end
                    hold(ax,'off');
                end
            end
        end

        function populateMRETab(app)
            mre = app.AppData.MRE;
            if isempty(mre), return; end
            nZ = max(1, size(mre.S,3));
            mreMid = max(1, round(nZ/2));
            app.SldrMRE.Limits = [1 max(nZ,2)];
            app.SldrMRE.Value  = mreMid;
            app.AppData.MRESlice = mreMid;
            app.LblMRESlice.Text = sprintf('%d/%d', mreMid, nZ);
            refreshMRE(app);
        end

        function refreshMRE(app)
            mre = app.AppData.MRE;
            if isempty(mre) || ~isfield(mre,'M'), return; end
            sl = app.AppData.MRESlice;
            sl = max(1, min(size(mre.M,3), sl));
            ph = max(1, min(size(mre.W,4), app.AppData.MREPhase));

            % Magnitude
            showImg(app.AxMREMag, double(mre.M(:,:,sl)), ...
                sprintf('Magnitude  sl %d',sl));

            % Wave
            img = double(mre.W(:,:,sl,ph));
            imagesc(app.AxMREWave, img);
            colormap(app.AxMREWave, mreWaveCmap());
            axis(app.AxMREWave,'image');
            app.AxMREWave.XTick=[]; app.AxMREWave.YTick=[];
            title(app.AxMREWave,sprintf('Wave  sl %d  ph %d/%d',sl,ph,size(mre.W,4)), ...
                'FontSize',12,'Color',[0.75 0.75 0.75],'FontWeight','normal');

            % Stiffness
            S = double(mre.S(:,:,sl));
            if app.AppData.ShowConfMask && isfield(mre,'LapC') && ~isempty(mre.LapC)
                LapC = double(mre.LapC(:,:,min(sl,end)));
                S(LapC < 0.95) = 0;
            end
            imagesc(app.AxMREStiff, S); clim(app.AxMREStiff, app.AppData.StiffCLim);
            colormap(app.AxMREStiff, mreStiffCmap()); axis(app.AxMREStiff,'image');
            app.AxMREStiff.XTick=[]; app.AxMREStiff.YTick=[];
            title(app.AxMREStiff,sprintf('Stiffness (kPa)  sl %d',sl), ...
                'FontSize',12,'Color',[0.75 0.75 0.75],'FontWeight','normal');
        end

        function storeROI(app, roiName, sl, mask, nR, nC)
            if nargin < 5, nR=256; nC=256; end
            mask = imresize(logical(mask),[nR nC],'nearest');
            key = sprintf('sl%d',sl);
            switch roiName
                case 'LiverDixon',  app.AppData.ROIs.LiverDixon.Slices.(key)  = mask;
                case 'SpleenDixon', app.AppData.ROIs.SpleenDixon.Slices.(key) = mask;
                case 'MuscleL1',    app.AppData.ROIs.MuscleL1 = mask;
                case 'MuscleL2',    app.AppData.ROIs.MuscleL2 = mask;
                case 'SATL1',       app.AppData.ROIs.SATL1    = mask;
                case 'SATL2',       app.AppData.ROIs.SATL2    = mask;
                case 'LiverMRE',    app.AppData.ROIs.LiverMRE.Slices.(key)  = mask;
                case 'SpleenMRE',   app.AppData.ROIs.SpleenMRE.Slices.(key) = mask;
            end
        end

        function computeDixonROIStats(app, roiName, mask, sl)
            dix = app.AppData.Dixon;
            if isempty(dix), return; end
            dx = dix.PixelSpacing_mm(1); dy = dix.PixelSpacing_mm(2);
            pixA = dx*dy/100;   % mm² → cm²
            area = sum(mask(:)) * pixA;

            pdff = [];
            if ~isempty(dix.PDFF) && sl <= size(dix.PDFF,3)
                ff = dix.PDFF(:,:,sl); pdff = nanmean(ff(mask));
            end

            switch roiName
                case 'LiverDixon'
                    app.ValLiverDixonVol.Text  = sprintf('%.0f cm²',area);
                    if ~isempty(pdff), app.ValLiverDixonPDFF.Text = sprintf('%.1f%%',pdff); end
                case 'SpleenDixon'
                    app.ValSpleenDixonVol.Text  = sprintf('%.0f cm²',area);
                    if ~isempty(pdff), app.ValSpleenDixonPDFF.Text = sprintf('%.1f%%',pdff); end
                case 'MuscleL1'
                    app.ValMuscleL1Area.Text = sprintf('%.1f cm²',area);
                    if ~isempty(pdff), app.ValMuscleL1PDFF.Text = sprintf('%.1f%%',pdff); end
                case 'MuscleL2'
                    app.ValMuscleL2Area.Text = sprintf('%.1f cm²',area);
                    if ~isempty(pdff), app.ValMuscleL2PDFF.Text = sprintf('%.1f%%',pdff); end
                case 'SATL1'
                    app.ValSATL1Area.Text = sprintf('%.1f cm²',area);
                    if ~isempty(pdff), app.ValSATL1PDFF.Text = sprintf('%.1f%%',pdff); end
                case 'SATL2'
                    app.ValSATL2Area.Text = sprintf('%.1f cm²',area);
                    if ~isempty(pdff), app.ValSATL2PDFF.Text = sprintf('%.1f%%',pdff); end
            end
            updateMuscleSATRatio(app);
        end

        function computeMREROIStats(app, roiName, mask, sl)
            mre = app.AppData.MRE;
            if isempty(mre) || ~isfield(mre,'S'), return; end
            S = double(mre.S(:,:,min(sl,end)));
            if app.AppData.ShowConfMask && isfield(mre,'LapC')
                LapC = double(mre.LapC(:,:,min(sl,end)));
                S(LapC < 0.95) = NaN;
            end
            validPx = S(mask & isfinite(S));
            if isempty(validPx), return; end
            stiff = nanmean(validPx);
            iqr_  = iqr(validPx);
            switch roiName
                case 'LiverMRE'
                    app.ValLiverStiff.Text   = sprintf('%.1f kPa',stiff);
                    app.ValLiverStiffIQR.Text = sprintf('%.1f kPa',iqr_);
                case 'SpleenMRE'
                    app.ValSpleenStiff.Text   = sprintf('%.1f kPa',stiff);
                    app.ValSpleenStiffIQR.Text = sprintf('%.1f kPa',iqr_);
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
            for ax = [app.AxDixonWater, app.AxDixonPDFF, app.AxDixonIP]
                hold(ax,'on');
                for b=1:numel(bnd)
                    plot(ax,bnd{b}(:,2),bnd{b}(:,1),'-','Color',clr,'LineWidth',2);
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
                uitreenode(root,'Text',sprintf('[Localizer] S%d  %s', ...
                    selection.Localizer.SeriesNumber, selection.Localizer.SeriesDescription));
            end
            if ~isempty(selection.Dixon)
                uitreenode(root,'Text',sprintf('[Dixon anchor] S%d  %s', ...
                    selection.Dixon.SeriesNumber, selection.Dixon.SeriesDescription));
            end
            if ~isempty(selection.MRE)
                uitreenode(root,'Text',sprintf('[MRE anchor] S%d  %s', ...
                    selection.MRE.SeriesNumber, selection.MRE.SeriesDescription));
                for k=1:numel(selection.MREGroup)
                    s=selection.MREGroup(k);
                    uitreenode(root,'Text',sprintf('  S%d  %-22s %s', ...
                        s.SeriesNumber, s.Role, s.SeriesDescription));
                end
            end
            expand(root,'all');
            app.LblStudyStats.Text = sprintf('%d series loaded', numel(exam.Series));
        end

        function updateResultsFromStruct(app, results)
            rows = {};
            if isfield(results,'L12') && isfield(results.L12,'L1')
                L1 = results.L12.L1; L2 = results.L12.L2;
                rows{end+1} = {'Muscle area L1',  sprintf('%.1f',L1.MuscleArea_cm2), 'cm²',  ''};
                rows{end+1} = {'Muscle PDFF L1',  sprintf('%.1f',L1.MusclePDFF_pct), '%',    ''};
                rows{end+1} = {'SAT area L1',      sprintf('%.1f',L1.SATArea_cm2),   'cm²',  ''};
                rows{end+1} = {'SAT PDFF L1',      sprintf('%.1f',L1.SAT_PDFF_pct),  '%',    ''};
                rows{end+1} = {'Muscle area L2',  sprintf('%.1f',L2.MuscleArea_cm2), 'cm²',  ''};
                rows{end+1} = {'Muscle:SAT ratio', sprintf('%.3f',L1.MuscleSATRatio),'',     ''};
            end
            if ~isempty(rows)
                app.ResultsTable.Data = vertcat(rows{:});
            end
        end

        function setStatus(app, msg)
            ts = datestr(now,'HH:MM:SS');
            app.LblStatusMsg.Text = sprintf('[%s]  %s', ts, msg);
            drawnow limitrate;
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
                rowDir = iop(1:3);
                imgPos = app.AppData.Localizer.Coronal.ImagePositions( ...
                    app.AppData.CorSlice,:);
                L1pos = imgPos + (app.AppData.L1_CorRow-1)*ps*rowDir;
                L2pos = imgPos + (app.AppData.L2_CorRow-1)*ps*rowDir;
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
            % Determine which localizer axes the mouse is hovering over.
            % Uses CurrentPoint in data-space compared to axis limits.
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
        function onLocImageClick(app, event, plane, level)
            if ~strcmp(app.AppData.AwaitingClick, level), return; end

            % Clear armed state immediately
            cancelPendingClick(app);

            pt   = event.IntersectionPoint;
            rowY = pt(2);   % y in image data coordinates = row

            if strcmp(plane, 'cor')
                % Clicked on coronal — store directly as coronal row
                corRow = rowY;
                sagRow = corRowToSagRow(app, corRow);
            else
                % Clicked on sagittal — convert to coronal row via mm
                corRow = sagRowToCorRow(app, rowY, app.AppData.SagSlice);
                sagRow = rowY;
            end

            if strcmp(level, 'L1')
                app.AppData.L1_CorRow = corRow;
                app.AppData.L1_SagRow = sagRow;
            else
                app.AppData.L2_CorRow = corRow;
                app.AppData.L2_SagRow = sagRow;
            end

            refreshLocCoronal(app);
            refreshLocSagittal(app);
            updateL12Status(app);
        end

        % -----------------------------------------------------------------
        %  COORDINATE CONVERSION HELPERS
        % -----------------------------------------------------------------
        function sagRow = corRowToSagRow(app, corRow, sagSliceOverride)
            % Convert a coronal row index to the equivalent sagittal row index
            % using patient-coordinate Z positions.
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
                rowDir = iop(1:3);
                imgPos = cor.ImagePositions(corSl, :);
                ptMm   = imgPos + (corRow - 1) * ps * rowDir;
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
                sagSl  = max(1, min(size(sag.Volume,3), sagSl));
                ps2    = sag.SpatialInfo.PixelSpacing(1);
                iop2   = sag.SpatialInfo.ImageOrientationPatient;
                rowDir2= iop2(1:3);
                imgPos2= sag.ImagePositions(sagSl, :);
                dz     = rowDir2(3);
                if abs(dz) < 1e-6, return; end
                sagRow = round(1 + (z_mm - imgPos2(3)) / (ps2 * dz));
                nRows  = size(sag.Volume, 1);
                if sagRow < 1 || sagRow > nRows, sagRow = NaN; end
            catch
                return
            end
        end

        function corRow = sagRowToCorRow(app, sagRow, sagSlice)
            % Convert a sagittal row index (on given slice) to a coronal row index.
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
                rowDir = iop(1:3);
                imgPos = sag.ImagePositions(sagSl, :);
                ptMm   = imgPos + (sagRow - 1) * ps * rowDir;
                z_mm   = ptMm(3);
            catch
                return
            end

            % --- Z mm → coronal row ---
            try
                cor    = loc.Coronal;
                corSl  = app.AppData.CorSlice;
                corSl  = max(1, min(size(cor.Volume,3), corSl));
                ps2    = cor.SpatialInfo.PixelSpacing(1);
                iop2   = cor.SpatialInfo.ImageOrientationPatient;
                rowDir2= iop2(1:3);
                imgPos2= cor.ImagePositions(corSl, :);
                dz     = rowDir2(3);
                if abs(dz) < 1e-6, return; end
                corRow = round(1 + (z_mm - imgPos2(3)) / (ps2 * dz));
                nRows  = size(cor.Volume, 1);
                if corRow < 1 || corRow > nRows, corRow = NaN; end
            catch
                return
            end
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
        function delete(app)
            if ~isempty(app.AppData.MRETimer) && isvalid(app.AppData.MRETimer)
                stop(app.AppData.MRETimer); delete(app.AppData.MRETimer);
            end
            delete(app.UIFigure);
        end
    end

end % classdef


% =========================================================================
%  MODULE-LEVEL HELPERS
% =========================================================================

function setupDarkAxes(ax, titleStr)
    ax.XTick=[]; ax.YTick=[]; ax.Box='on';
    ax.Color=[0.06 0.06 0.06];
    ax.XColor=[0.28 0.28 0.28]; ax.YColor=[0.28 0.28 0.28];
    ax.BackgroundColor=[0.06 0.06 0.06];
    colormap(ax,'gray');
    title(ax,titleStr,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function showImg(ax, img, titleStr)
    lo=min(img(:)); hi=max(img(:));
    if hi>lo, img=(img-lo)./(hi-lo); end
    imagesc(ax,img); colormap(ax,'gray'); axis(ax,'image');
    ax.XTick=[]; ax.YTick=[];
    title(ax,titleStr,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
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
    switch name
        case {'LiverDixon','MuscleL1','MuscleL2'}
            clr=[0.15 0.75 0.15];
        case {'SpleenDixon'}
            clr=[0.15 0.55 0.90];
        case {'SATL1','SATL2'}
            clr=[0.95 0.65 0.10];
        otherwise
            clr=[1 1 0];
    end
end

function clr = mreROIColor(name)
    if contains(name,'Liver'),  clr=[0.15 0.85 0.15];
    else,                       clr=[0.15 0.65 0.95];
    end
end

function cmap = mreWaveCmap()
    if exist('awave','file') == 2
        try
            cmap = awave(256);
            if size(cmap,2)==3, return; end
        catch
        end
    end
    % Symmetric blue→white→red colormap (256×3)
    n = 128;
    top    = [linspace(0,1,n)', linspace(0,1,n)', ones(n,1)];   % blue→white
    bottom = [ones(n,1), linspace(1,0,n)', linspace(1,0,n)'];   % white→red
    cmap   = [top; bottom];
end

function cmap = mreStiffCmap()
    if exist('aaasmo','file')==2
        cmap = aaasmo(256);
    else
        cmap = hot(256);
    end
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

function slices = removeSlice(slices, sl)
    key = sprintf('sl%d',sl);
    if isfield(slices,key)
        slices = rmfield(slices,key);
    end
end

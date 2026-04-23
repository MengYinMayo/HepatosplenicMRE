classdef HepatosplenicMRE_App < matlab.apps.AppBase
% HepatosplenicMRE_App  v2.1 — Integrated single-window platform.
%
%   USAGE:  app = HepatosplenicMRE_App;
%
%   LAYOUT
%     Left   Study browser (site/subject/session tree + filter + QC badges)
%     Center Tabbed viewer: Localizer | Dixon | MRE | Results
%     Right  Live ROI results panel (always visible)
%     Bottom Pipeline steps S1-S5 + status bar

    % =================================================================
    %  UI COMPONENTS
    % =================================================================
    properties (Access = public)
        UIFigure        matlab.ui.Figure

        % Menus
        MenuFile        matlab.ui.container.Menu
        MenuView        matlab.ui.container.Menu
        MenuProcess     matlab.ui.container.Menu
        MenuExport      matlab.ui.container.Menu
        MenuHelp        matlab.ui.container.Menu

        % Toolbar panel
        PnlToolbar      matlab.ui.container.Panel
        BtnLoad         matlab.ui.control.Button
        BtnPipeline     matlab.ui.control.Button
        BtnConfirmL12   matlab.ui.control.Button
        BtnExportCSV    matlab.ui.control.Button

        % Main body grid
        GridMain        matlab.ui.container.GridLayout

        % ── LEFT: Study Browser ──────────────────────────────────────
        PnlBrowser      matlab.ui.container.Panel
        GridBrowser     matlab.ui.container.GridLayout
        EditFilter      matlab.ui.control.EditField
        TreeStudy       matlab.ui.container.Tree
        LblBrowserFoot  matlab.ui.control.Label

        % ── CENTER: Tab group ────────────────────────────────────────
        PnlCenter       matlab.ui.container.Panel
        TabGroup        matlab.ui.container.TabGroup

        %  Localizer tab
        TabLoc          matlab.ui.container.Tab
        GridLoc         matlab.ui.container.GridLayout
        BtnPlaceL1      matlab.ui.control.Button
        BtnPlaceL2      matlab.ui.control.Button
        BtnLocConfirm   matlab.ui.control.Button
        BtnSyncDixon    matlab.ui.control.Button
        AxCoronal       matlab.ui.control.UIAxes
        AxSagittal      matlab.ui.control.UIAxes
        SldrCor         matlab.ui.control.Slider
        SldrSag         matlab.ui.control.Slider
        LblCorSlice     matlab.ui.control.Label
        LblSagSlice     matlab.ui.control.Label
        LblL12Status    matlab.ui.control.Label
        PnlParallelHint matlab.ui.container.Panel

        %  Dixon tab
        TabDixon        matlab.ui.container.Tab
        GridDixon       matlab.ui.container.GridLayout
        AxDixonW        matlab.ui.control.UIAxes
        AxDixonPDFF     matlab.ui.control.UIAxes
        AxDixonIP       matlab.ui.control.UIAxes
        SldrDixon       matlab.ui.control.Slider
        LblDixonSlice   matlab.ui.control.Label
        BtnLiverDixon   matlab.ui.control.Button
        BtnSpleenDixon  matlab.ui.control.Button
        BtnMuscleL1     matlab.ui.control.Button
        BtnMuscleL2     matlab.ui.control.Button
        BtnSATL1        matlab.ui.control.Button
        BtnSATL2        matlab.ui.control.Button
        BtnClearDixon   matlab.ui.control.Button

        %  MRE tab
        TabMRE          matlab.ui.container.Tab
        GridMRE         matlab.ui.container.GridLayout
        AxMREMag        matlab.ui.control.UIAxes
        AxMREWave       matlab.ui.control.UIAxes
        AxMREStiff      matlab.ui.control.UIAxes
        SldrMRE         matlab.ui.control.Slider
        LblMRESlice     matlab.ui.control.Label
        BtnMREPlay      matlab.ui.control.Button
        BtnStiff8       matlab.ui.control.Button
        BtnStiff20      matlab.ui.control.Button
        BtnConfMask     matlab.ui.control.StateButton
        BtnLiverMRE     matlab.ui.control.Button
        BtnSpleenMRE    matlab.ui.control.Button
        BtnClearMRE     matlab.ui.control.Button

        %  Results tab
        TabResults      matlab.ui.container.Tab
        TblResults      matlab.ui.control.Table

        % ── RIGHT: Live results ──────────────────────────────────────
        PnlRight        matlab.ui.container.Panel
        GridRight       matlab.ui.container.GridLayout

        % L1-L2 measures
        ValL1Level      matlab.ui.control.Label
        ValL2Level      matlab.ui.control.Label
        ValMuscAreaL12  matlab.ui.control.Label
        ValSATAreaL12   matlab.ui.control.Label
        ValBodyWall     matlab.ui.control.Label

        % Body composition
        ValMuscArea     matlab.ui.control.Label
        ValSATArea      matlab.ui.control.Label
        ValVAT          matlab.ui.control.Label
        ValMuscleFat    matlab.ui.control.Label
        ValMusclePDFF   matlab.ui.control.Label

        % Liver
        ValLiverVol     matlab.ui.control.Label
        ValLiverPDFF    matlab.ui.control.Label
        ValLiverStiff   matlab.ui.control.Label
        ValLiverIQR     matlab.ui.control.Label

        % Spleen
        ValSpleenVol    matlab.ui.control.Label
        ValSpleenStiff  matlab.ui.control.Label
        ValLSRatio      matlab.ui.control.Label

        % QC
        ValSegConf      matlab.ui.control.Label
        ValCoverage     matlab.ui.control.Label
        ValRange        matlab.ui.control.Label
        ValManual       matlab.ui.control.Label

        % ── BOTTOM pipeline bar ──────────────────────────────────────
        PnlBottom       matlab.ui.container.Panel
        GridBottom      matlab.ui.container.GridLayout
        BtnS1           matlab.ui.control.Button
        BtnS2           matlab.ui.control.Button
        BtnS3           matlab.ui.control.Button
        BtnS4           matlab.ui.control.Button
        BtnS5           matlab.ui.control.Button
        LblStatus       matlab.ui.control.Label
    end

    % =================================================================
    %  APP DATA
    % =================================================================
    properties (Access = public)
        AD   % AppData struct — initialised in startupFcn
    end

    % =================================================================
    %  CONSTRUCTION
    % =================================================================
    methods (Access = private)

        function initUI(app)
            %% Figure
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position = [20 20 1440 860];
            app.UIFigure.Name = 'Integrated Hepatosplenic MRI/MRE Analysis Platform';
            app.UIFigure.Resize = 'on';
            app.UIFigure.CloseRequestFcn = @(~,~)app.onClose();

            buildMenus(app);

            %% Outer grid: toolbar | body | bottom
            og = uigridlayout(app.UIFigure,[3 1]);
            og.RowHeight = {50,'1x',54};
            og.ColumnWidth = {'1x'};
            og.Padding = [0 0 0 0];
            og.RowSpacing = 0;

            buildToolbar(app, og);

            %% Body grid: left(220) | center(1x) | right(240)
            app.GridMain = uigridlayout(og,[1 3]);
            app.GridMain.Layout.Row = 2;
            app.GridMain.ColumnWidth = {220,'1x',240};
            app.GridMain.RowHeight = {'1x'};
            app.GridMain.Padding = [0 0 0 0];
            app.GridMain.ColumnSpacing = 0;

            buildBrowser(app);
            buildCenter(app);
            buildRight(app);
            buildBottom(app, og);
        end

        % -----------------------------------------------------------------
        function buildMenus(app)
            app.MenuFile    = uimenu(app.UIFigure,'Text','File');
            uimenu(app.MenuFile,'Text','Load Study...','Accelerator','O', ...
                'MenuSelectedFcn',@(~,~)app.loadStudy());
            uimenu(app.MenuFile,'Text','Save Session...','Separator','on', ...
                'Accelerator','S','MenuSelectedFcn',@(~,~)app.doSaveSession());
            uimenu(app.MenuFile,'Text','Load Session...', ...
                'MenuSelectedFcn',@(~,~)app.doLoadSession());
            uimenu(app.MenuFile,'Text','Exit','Separator','on', ...
                'MenuSelectedFcn',@(~,~)app.onClose());

            app.MenuView = uimenu(app.UIFigure,'Text','View');
            uimenu(app.MenuView,'Text','Stiffness  0–8 kPa', ...
                'MenuSelectedFcn',@(~,~)app.setStiff([0 8]));
            uimenu(app.MenuView,'Text','Stiffness  0–20 kPa', ...
                'MenuSelectedFcn',@(~,~)app.setStiff([0 20]));
            uimenu(app.MenuView,'Text','Stiffness  custom...', ...
                'MenuSelectedFcn',@(~,~)app.setStiffCustom());

            app.MenuProcess = uimenu(app.UIFigure,'Text','Process');
            uimenu(app.MenuProcess,'Text','Run Full Pipeline', ...
                'MenuSelectedFcn',@(~,~)app.showWorkflowGuide());

            app.MenuExport = uimenu(app.UIFigure,'Text','Export');
            uimenu(app.MenuExport,'Text','Export Features (CSV)...','Accelerator','E', ...
                'MenuSelectedFcn',@(~,~)app.doExportCSV());
            uimenu(app.MenuExport,'Text','Export ROI Masks (MAT)...', ...
                'MenuSelectedFcn',@(~,~)app.doExportROIs());
            uimenu(app.MenuExport,'Text','Export Report (PDF)...', ...
                'MenuSelectedFcn',@(~,~)app.doExportPDF());

            app.MenuHelp = uimenu(app.UIFigure,'Text','Help');
            uimenu(app.MenuHelp,'Text','About', ...
                'MenuSelectedFcn',@(~,~)msgbox( ...
                'HepatosplenicMRE Platform v2.1\nMayo Clinic R01','About','help'));
        end

        % -----------------------------------------------------------------
        function buildToolbar(app, parentGrid)
            app.PnlToolbar = uipanel(parentGrid);
            app.PnlToolbar.Layout.Row = 1;
            app.PnlToolbar.BorderType = 'none';
            app.PnlToolbar.BackgroundColor = [0.95 0.95 0.95];

            g = uigridlayout(app.PnlToolbar,[1 5]);
            g.ColumnWidth = {150,150,160,140,'1x'};
            g.RowHeight   = {'1x'};
            g.Padding     = [8 6 8 6];
            g.ColumnSpacing = 6;

            app.BtnLoad = tb(g,1,'● Load Study',[0.20 0.55 0.28],[1 1 1]);
            app.BtnLoad.ButtonPushedFcn = @(~,~)app.loadStudy();

            app.BtnPipeline = tb(g,2,'Run Pipeline',[0.88 0.88 0.88],[0.2 0.2 0.2]);
            app.BtnPipeline.ButtonPushedFcn = @(~,~)app.showWorkflowGuide();
            app.BtnPipeline.Enable = 'off';

            app.BtnConfirmL12 = tb(g,3,'● L1-L2 Confirm',[0.85 0.48 0.10],[1 1 1]);
            app.BtnConfirmL12.ButtonPushedFcn = @(~,~)app.confirmL12();
            app.BtnConfirmL12.Enable = 'off';

            app.BtnExportCSV = tb(g,4,'Export CSV',[0.88 0.88 0.88],[0.2 0.2 0.2]);
            app.BtnExportCSV.ButtonPushedFcn = @(~,~)app.doExportCSV();
            app.BtnExportCSV.Enable = 'off';
        end

        % -----------------------------------------------------------------
        function buildBrowser(app)
            app.PnlBrowser = uipanel(app.GridMain,'Title','Study Browser', ...
                'FontSize',13,'FontWeight','bold');
            app.PnlBrowser.Layout.Column = 1;
            app.PnlBrowser.BackgroundColor = [0.97 0.97 0.97];

            app.GridBrowser = uigridlayout(app.PnlBrowser,[3 1]);
            app.GridBrowser.RowHeight = {26,'1x',20};
            app.GridBrowser.Padding   = [4 4 4 4];
            app.GridBrowser.RowSpacing = 4;

            app.EditFilter = uieditfield(app.GridBrowser,'text');
            app.EditFilter.Layout.Row = 1;
            app.EditFilter.Placeholder = 'Filter by site / subject / status';
            app.EditFilter.FontSize = 11;
            app.EditFilter.ValueChangedFcn = @(src,~)app.filterBrowser(src.Value);

            app.TreeStudy = uitree(app.GridBrowser,'checkbox');
            app.TreeStudy.Layout.Row = 2;
            app.TreeStudy.FontSize   = 11;
            app.TreeStudy.SelectionChangedFcn = @(~,e)app.onNodeSelect(e);

            % Placeholder root node
            nd = uitreenode(app.TreeStudy,'Text','Load a study to begin...');
            nd.NodeData = [];

            app.LblBrowserFoot = uilabel(app.GridBrowser);
            app.LblBrowserFoot.Layout.Row = 3;
            app.LblBrowserFoot.Text = 'No studies loaded';
            app.LblBrowserFoot.FontSize = 10;
            app.LblBrowserFoot.FontColor = [0.5 0.5 0.5];
            app.LblBrowserFoot.HorizontalAlignment = 'center';
        end

        % -----------------------------------------------------------------
        function buildCenter(app)
            app.PnlCenter = uipanel(app.GridMain,'BorderType','none');
            app.PnlCenter.Layout.Column = 2;

            app.TabGroup = uitabgroup(app.PnlCenter, ...
                'Units','normalized','Position',[0 0 1 1],'FontSize',13);
            app.TabGroup.SelectionChangedFcn = @(~,e)app.onTabChange(e);

            buildLocTab(app);
            buildDixonTab(app);
            buildMRETab(app);
            buildResultsTab(app);
        end

        % ── LOCALIZER TAB ────────────────────────────────────────────
        function buildLocTab(app)
            app.TabLoc = uitab(app.TabGroup,'Title','Localizer');

            app.GridLoc = uigridlayout(app.TabLoc,[4 2]);
            app.GridLoc.RowHeight    = {36,'1x',28,90};
            app.GridLoc.ColumnWidth  = {'1x','1x'};
            app.GridLoc.Padding      = [6 6 6 6];
            app.GridLoc.RowSpacing   = 4;
            app.GridLoc.ColumnSpacing = 8;

            %% Row 1: compact button bar (spans both columns)
            btnBar = uigridlayout(app.GridLoc,[1 5]);
            btnBar.Layout.Row = 1; btnBar.Layout.Column = [1 2];
            btnBar.ColumnWidth = {120,120,110,160,'1x'};
            btnBar.Padding = [0 2 0 2]; btnBar.ColumnSpacing = 6;

            app.BtnPlaceL1 = locBtn(btnBar,1,'● Place L1',[0.92 0.56 0.10],[1 1 1]);
            app.BtnPlaceL1.ButtonPushedFcn = @(~,~)app.placeL1();

            app.BtnPlaceL2 = locBtn(btnBar,2,'● Place L2',[0.20 0.44 0.86],[1 1 1]);
            app.BtnPlaceL2.ButtonPushedFcn = @(~,~)app.placeL2();

            app.BtnLocConfirm = locBtn(btnBar,3,'✓ Confirm',[0.18 0.60 0.34],[1 1 1]);
            app.BtnLocConfirm.ButtonPushedFcn = @(~,~)app.confirmL12();

            app.BtnSyncDixon = locBtn(btnBar,4,'⇄ Sync to Dixon/MRE',[0.88 0.88 0.88],[0.2 0.2 0.2]);
            app.BtnSyncDixon.ButtonPushedFcn = @(~,~)app.syncTabs();

            app.LblL12Status = uilabel(btnBar);
            app.LblL12Status.Layout.Column = 5;
            app.LblL12Status.Text = 'Place L1 and L2 on the coronal image, then click Confirm.';
            app.LblL12Status.FontSize = 11;
            app.LblL12Status.FontColor = [0.45 0.45 0.45];
            app.LblL12Status.FontAngle = 'italic';

            %% Row 2: Image panels
            % Coronal
            pCoronal = uipanel(app.GridLoc,'BorderType','none');
            pCoronal.Layout.Row = 2; pCoronal.Layout.Column = 1;
            gC = uigridlayout(pCoronal,[2 1]);
            gC.RowHeight = {'1x',14}; gC.Padding = [0 0 0 0]; gC.RowSpacing = 2;

            app.AxCoronal = uiaxes(gC);
            app.AxCoronal.Layout.Row = 1;
            darkAx(app.AxCoronal,'Coronal');

            app.SldrCor = uislider(gC);
            app.SldrCor.Layout.Row = 2;
            app.SldrCor.Limits = [1 9]; app.SldrCor.Value = 5;
            app.SldrCor.MajorTicks = []; app.SldrCor.MinorTicks = [];
            app.SldrCor.ValueChangedFcn = @(s,~)app.onCorSlide(s);

            % Sagittal
            pSag = uipanel(app.GridLoc,'BorderType','none');
            pSag.Layout.Row = 2; pSag.Layout.Column = 2;
            gS = uigridlayout(pSag,[2 1]);
            gS.RowHeight = {'1x',14}; gS.Padding = [0 0 0 0]; gS.RowSpacing = 2;

            app.AxSagittal = uiaxes(gS);
            app.AxSagittal.Layout.Row = 1;
            darkAx(app.AxSagittal,'Sagittal');

            app.SldrSag = uislider(gS);
            app.SldrSag.Layout.Row = 2;
            app.SldrSag.Limits = [1 9]; app.SldrSag.Value = 5;
            app.SldrSag.MajorTicks = []; app.SldrSag.MinorTicks = [];
            app.SldrSag.ValueChangedFcn = @(s,~)app.onSagSlide(s);

            %% Row 3: slice labels
            app.LblCorSlice = uilabel(app.GridLoc);
            app.LblCorSlice.Layout.Row=3; app.LblCorSlice.Layout.Column=1;
            app.LblCorSlice.Text='Slice 5 / 9';
            app.LblCorSlice.HorizontalAlignment='center';
            app.LblCorSlice.FontSize=11; app.LblCorSlice.FontColor=[0.5 0.5 0.5];

            app.LblSagSlice = uilabel(app.GridLoc);
            app.LblSagSlice.Layout.Row=3; app.LblSagSlice.Layout.Column=2;
            app.LblSagSlice.Text='Slice 5 / 9';
            app.LblSagSlice.HorizontalAlignment='center';
            app.LblSagSlice.FontSize=11; app.LblSagSlice.FontColor=[0.5 0.5 0.5];

            %% Row 4: parallel analysis hint panel (spans both columns)
            app.PnlParallelHint = uipanel(app.GridLoc, ...
                'Title','Parallel analysis tabs — activate anytime', ...
                'FontSize',11,'FontWeight','bold', ...
                'BackgroundColor',[0.94 0.94 0.94]);
            app.PnlParallelHint.Layout.Row = 4;
            app.PnlParallelHint.Layout.Column = [1 2];

            hg = uigridlayout(app.PnlParallelHint,[1 3]);
            hg.ColumnWidth = {'1x','1x','1x'};
            hg.Padding = [6 4 6 4]; hg.ColumnSpacing = 8;

            hintCard(hg,1,'Dixon tab',[0.92 0.56 0.10], ...
                'Water • PDFF • In-Phase', ...
                'ROI: Liver | Spleen | Muscle L1/L2 | SAT L1/L2');
            hintCard(hg,2,'MRE tab',[0.20 0.44 0.86], ...
                'Magnitude • Wave • Stiffness', ...
                'Liver / spleen ROIs on wave panel | 0-8 / 0-20 kPa | confidence mask');
            hintCard(hg,3,'Results tab',[0.18 0.60 0.34], ...
                'Live measurements update in-place', ...
                'Volumes • PDFF • ratios • stiffness IQR | QC status and export-ready output');
        end

        % ── DIXON TAB ───────────────────────────────────────────────
        function buildDixonTab(app)
            app.TabDixon = uitab(app.TabGroup,'Title','Dixon');

            app.GridDixon = uigridlayout(app.TabDixon,[1 2]);
            app.GridDixon.ColumnWidth  = {'1x',170};
            app.GridDixon.Padding      = [4 4 4 4];
            app.GridDixon.ColumnSpacing = 6;

            % Images area
            imgPnl = uipanel(app.GridDixon,'BorderType','none');
            imgPnl.Layout.Column = 1;
            ig = uigridlayout(imgPnl,[2 3]);
            ig.RowHeight = {'1x',30}; ig.ColumnWidth = {'1x','1x','1x'};
            ig.Padding = [0 0 0 0]; ig.ColumnSpacing = 4;

            app.AxDixonW = uiaxes(ig);
            app.AxDixonW.Layout.Row=1; app.AxDixonW.Layout.Column=1;
            darkAx(app.AxDixonW,'Water');

            app.AxDixonPDFF = uiaxes(ig);
            app.AxDixonPDFF.Layout.Row=1; app.AxDixonPDFF.Layout.Column=2;
            darkAx(app.AxDixonPDFF,'PDFF (%)');
            colormap(app.AxDixonPDFF,'hot');

            app.AxDixonIP = uiaxes(ig);
            app.AxDixonIP.Layout.Row=1; app.AxDixonIP.Layout.Column=3;
            darkAx(app.AxDixonIP,'In-Phase');

            % Slice control
            sc = uigridlayout(ig,[1 4]);
            sc.Layout.Row=2; sc.Layout.Column=[1 3];
            sc.ColumnWidth={60,'1x',60,150}; sc.Padding=[0 4 0 4];

            uilabel(sc,'Text','Slice:','FontSize',13,'FontWeight','bold', ...
                'Layout',struct('Column',1));
            app.SldrDixon = uislider(sc);
            app.SldrDixon.Layout.Column = 2;
            app.SldrDixon.Limits=[1 28]; app.SldrDixon.Value=14;
            app.SldrDixon.MajorTicks=[]; app.SldrDixon.MinorTicks=[];
            app.SldrDixon.ValueChangedFcn = @(s,~)app.onDixonSlide(s);

            app.LblDixonSlice = uilabel(sc);
            app.LblDixonSlice.Layout.Column=3;
            app.LblDixonSlice.Text='14/28'; app.LblDixonSlice.FontSize=12;
            app.LblDixonSlice.HorizontalAlignment='center';

            ldi = uilabel(sc);
            ldi.Layout.Column=4; ldi.Text='Pixel: 1.56mm  Slice: 8mm';
            ldi.FontSize=10; ldi.FontColor=[0.5 0.5 0.5];

            % ROI sidebar
            rPnl = uipanel(app.GridDixon,'Title','ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            rPnl.Layout.Column = 2;
            rg = uigridlayout(rPnl,[10 1]);
            rg.RowHeight = {18,34,34,18,34,34,34,34,8,34};
            rg.Padding=[4 4 4 4]; rg.RowSpacing=3;

            uilabel(rg,'Text','Organ volumes:','FontSize',11,'FontWeight','bold', ...
                'FontColor',[0.35 0.35 0.35]);
            app.BtnLiverDixon  = roiB(rg,2,'Liver (all slices)',[0.18 0.55 0.20],[1 1 1]);
            app.BtnSpleenDixon = roiB(rg,3,'Spleen (all slices)',[0.16 0.46 0.72],[1 1 1]);
            uilabel(rg,'Text','L1-L2 body comp:','FontSize',11,'FontWeight','bold', ...
                'FontColor',[0.35 0.35 0.35]);
            app.BtnMuscleL1 = roiB(rg,5,'Muscle @ L1',[0.76 0.22 0.10],[1 1 1]);
            app.BtnMuscleL2 = roiB(rg,6,'Muscle @ L2',[0.88 0.40 0.10],[1 1 1]);
            app.BtnSATL1    = roiB(rg,7,'SAT @ L1',[0.14 0.26 0.84],[1 1 1]);
            app.BtnSATL2    = roiB(rg,8,'SAT @ L2',[0.28 0.42 0.90],[1 1 1]);
            app.BtnClearDixon = roiB(rg,10,'Clear this slice',[0.72 0.72 0.72],[0.2 0.2 0.2]);

            app.BtnLiverDixon.ButtonPushedFcn  = @(~,~)app.drawDixon('LiverDixon');
            app.BtnSpleenDixon.ButtonPushedFcn = @(~,~)app.drawDixon('SpleenDixon');
            app.BtnMuscleL1.ButtonPushedFcn    = @(~,~)app.drawDixon('MuscleL1');
            app.BtnMuscleL2.ButtonPushedFcn    = @(~,~)app.drawDixon('MuscleL2');
            app.BtnSATL1.ButtonPushedFcn       = @(~,~)app.drawDixon('SATL1');
            app.BtnSATL2.ButtonPushedFcn       = @(~,~)app.drawDixon('SATL2');
            app.BtnClearDixon.ButtonPushedFcn  = @(~,~)app.clearDixonSlice();
        end

        % ── MRE TAB ─────────────────────────────────────────────────
        function buildMRETab(app)
            app.TabMRE = uitab(app.TabGroup,'Title','MRE');

            app.GridMRE = uigridlayout(app.TabMRE,[1 2]);
            app.GridMRE.ColumnWidth  = {'1x',170};
            app.GridMRE.Padding      = [4 4 4 4];
            app.GridMRE.ColumnSpacing = 6;

            imgPnl = uipanel(app.GridMRE,'BorderType','none');
            imgPnl.Layout.Column = 1;
            ig = uigridlayout(imgPnl,[2 3]);
            ig.RowHeight = {'1x',42}; ig.ColumnWidth = {'1x','1x','1x'};
            ig.Padding = [0 0 0 0]; ig.ColumnSpacing = 4;

            app.AxMREMag = uiaxes(ig);
            app.AxMREMag.Layout.Row=1; app.AxMREMag.Layout.Column=1;
            darkAx(app.AxMREMag,'Magnitude');

            app.AxMREWave = uiaxes(ig);
            app.AxMREWave.Layout.Row=1; app.AxMREWave.Layout.Column=2;
            darkAx(app.AxMREWave,'Wave');
            colormap(app.AxMREWave, waveCmap());

            app.AxMREStiff = uiaxes(ig);
            app.AxMREStiff.Layout.Row=1; app.AxMREStiff.Layout.Column=3;
            darkAx(app.AxMREStiff,'Stiffness (kPa)');
            colormap(app.AxMREStiff, stiffCmap());
            colorbar(app.AxMREStiff,'FontSize',9,'Color',[0.65 0.65 0.65]);

            % Controls row
            cg = uigridlayout(ig,[1 7]);
            cg.Layout.Row=2; cg.Layout.Column=[1 3];
            cg.ColumnWidth={50,'1x',52,100,80,80,90};
            cg.Padding=[0 4 0 4]; cg.ColumnSpacing=4;

            uilabel(cg,'Text','Slice:','FontSize',13,'FontWeight','bold', ...
                'Layout',struct('Column',1));

            app.SldrMRE = uislider(cg);
            app.SldrMRE.Layout.Column=2;
            app.SldrMRE.Limits=[1 4]; app.SldrMRE.Value=2;
            app.SldrMRE.MajorTicks=[]; app.SldrMRE.MinorTicks=[];
            app.SldrMRE.ValueChangedFcn = @(s,~)app.onMRESlide(s);

            app.LblMRESlice = uilabel(cg);
            app.LblMRESlice.Layout.Column=3;
            app.LblMRESlice.Text='2/4'; app.LblMRESlice.FontSize=12;
            app.LblMRESlice.HorizontalAlignment='center';

            app.BtnMREPlay = uibutton(cg,'push');
            app.BtnMREPlay.Layout.Column=4; app.BtnMREPlay.Text='▶ Play wave';
            app.BtnMREPlay.FontSize=12; app.BtnMREPlay.FontWeight='bold';
            app.BtnMREPlay.BackgroundColor=[0.18 0.60 0.34];
            app.BtnMREPlay.FontColor=[1 1 1];
            app.BtnMREPlay.ButtonPushedFcn=@(~,~)app.togglePlay();

            app.BtnStiff8 = uibutton(cg,'push');
            app.BtnStiff8.Layout.Column=5; app.BtnStiff8.Text='0-8 kPa';
            app.BtnStiff8.FontSize=12; app.BtnStiff8.FontWeight='bold';
            app.BtnStiff8.BackgroundColor=[0.24 0.52 0.84]; app.BtnStiff8.FontColor=[1 1 1];
            app.BtnStiff8.ButtonPushedFcn=@(~,~)app.setStiff([0 8]);

            app.BtnStiff20 = uibutton(cg,'push');
            app.BtnStiff20.Layout.Column=6; app.BtnStiff20.Text='0-20 kPa';
            app.BtnStiff20.FontSize=12;
            app.BtnStiff20.BackgroundColor=[0.68 0.86 0.68]; app.BtnStiff20.FontColor=[0.1 0.3 0.1];
            app.BtnStiff20.ButtonPushedFcn=@(~,~)app.setStiff([0 20]);

            app.BtnConfMask = uibutton(cg,'state');
            app.BtnConfMask.Layout.Column=7; app.BtnConfMask.Text='Conf. mask';
            app.BtnConfMask.FontSize=12; app.BtnConfMask.Value=false;
            app.BtnConfMask.ValueChangedFcn=@(~,~)app.toggleConf();

            % ROI sidebar
            rPnl = uipanel(app.GridMRE,'Title','MRE ROI Tools', ...
                'FontSize',12,'FontWeight','bold');
            rPnl.Layout.Column = 2;
            rg = uigridlayout(rPnl,[7 1]);
            rg.RowHeight = {18,34,34,18,34,34,34};
            rg.Padding=[4 4 4 4]; rg.RowSpacing=3;

            uilabel(rg,'Text','Stiffness ROIs:','FontSize',11,'FontWeight','bold', ...
                'FontColor',[0.35 0.35 0.35]);
            app.BtnLiverMRE  = roiB(rg,2,'Liver stiffness',[0.18 0.55 0.20],[1 1 1]);
            app.BtnSpleenMRE = roiB(rg,3,'Spleen stiffness',[0.16 0.46 0.72],[1 1 1]);
            uilabel(rg,'Text','Draw on wave panel.','FontSize',11, ...
                'FontColor',[0.45 0.45 0.45]);
            uilabel(rg,'Text','ROI saved per slice.','FontSize',11, ...
                'FontColor',[0.45 0.45 0.45]);
            uilabel(rg,'Text','','FontSize',11);
            app.BtnClearMRE = roiB(rg,7,'Clear this slice',[0.72 0.72 0.72],[0.2 0.2 0.2]);

            app.BtnLiverMRE.ButtonPushedFcn  = @(~,~)app.drawMRE('LiverMRE');
            app.BtnSpleenMRE.ButtonPushedFcn = @(~,~)app.drawMRE('SpleenMRE');
            app.BtnClearMRE.ButtonPushedFcn  = @(~,~)app.clearMRESlice();
        end

        % ── RESULTS TAB ─────────────────────────────────────────────
        function buildResultsTab(app)
            app.TabResults = uitab(app.TabGroup,'Title','Results');
            g = uigridlayout(app.TabResults,[1 1]);
            g.Padding=[8 8 8 8];
            app.TblResults = uitable(g);
            app.TblResults.FontSize = 12;
            app.TblResults.ColumnName = {'Measurement','Value','Unit','Notes'};
            app.TblResults.Data = {'No data yet','—','—','Load a study first'};
            app.TblResults.ColumnWidth = {220,120,80,260};
        end

        % -----------------------------------------------------------------
        function buildRight(app)
            app.PnlRight = uipanel(app.GridMain,'Title','Live ROI Results', ...
                'FontSize',13,'FontWeight','bold');
            app.PnlRight.Layout.Column = 3;

            app.GridRight = uigridlayout(app.PnlRight,[5 1]);
            app.GridRight.RowHeight = {130,140,110,100,100};
            app.GridRight.Padding = [4 2 4 2];
            app.GridRight.RowSpacing = 2;

            % ── L1-L2 measures ───────────────────────────────────────
            [app.ValL1Level,app.ValL2Level,app.ValMuscAreaL12, ...
             app.ValSATAreaL12,app.ValBodyWall] = measSection(app.GridRight,1, ...
                'L1-L2 measures',[0.92 0.56 0.10], ...
                {'L1 level','L2 level','Muscle area L1-L2','SAT area L1-L2','Body wall circ.'}, ...
                {'—','—','— cm²','— cm²','— cm'});

            % ── Body composition ──────────────────────────────────────
            [app.ValMuscArea,app.ValSATArea,app.ValVAT, ...
             app.ValMuscleFat,app.ValMusclePDFF] = measSection(app.GridRight,2, ...
                'Body composition',[0.92 0.56 0.10], ...
                {'Muscle area','SAT area','VAT (exploratory)','Muscle:fat ratio','Muscle PDFF'}, ...
                {'— cm²','— cm²','—','—','—'});

            % ── Liver ─────────────────────────────────────────────────
            [app.ValLiverVol,app.ValLiverPDFF, ...
             app.ValLiverStiff,app.ValLiverIQR] = measSection(app.GridRight,3, ...
                'Liver',[0.25 0.25 0.25], ...
                {'Dixon volume','Liver PDFF','MRE stiffness','Heterogeneity IQR'}, ...
                {'— mL','— %','— kPa','— kPa'});

            % ── Spleen ───────────────────────────────────────────────
            [app.ValSpleenVol,app.ValSpleenStiff,app.ValLSRatio] = ...
                measSection(app.GridRight,4, ...
                'Spleen',[0.25 0.25 0.25], ...
                {'Dixon volume','MRE stiffness','Liver:spleen ratio'}, ...
                {'— mL','— kPa','—'});

            % ── QC status ────────────────────────────────────────────
            [app.ValSegConf,app.ValCoverage, ...
             app.ValRange,app.ValManual] = measSection(app.GridRight,5, ...
                'QC status',[0.25 0.25 0.25], ...
                {'Seg. confidence','Coverage check','Range check','Manual review'}, ...
                {'—','—','—','—'});
        end

        % -----------------------------------------------------------------
        function buildBottom(app, parentGrid)
            app.PnlBottom = uipanel(parentGrid);
            app.PnlBottom.Layout.Row = 3;
            app.PnlBottom.BorderType = 'none';
            app.PnlBottom.BackgroundColor = [0.91 0.91 0.91];

            app.GridBottom = uigridlayout(app.PnlBottom,[2 6]);
            app.GridBottom.RowHeight    = {'1x',18};
            app.GridBottom.ColumnWidth  = {'1x','1x','1x','1x','1x',6};
            app.GridBottom.Padding      = [4 2 4 0];
            app.GridBottom.ColumnSpacing = 2;

            stepColors = {[0.80 0.80 0.80],[0.80 0.80 0.80], ...
                          [0.80 0.80 0.80],[0.80 0.80 0.80],[0.80 0.80 0.80]};
            stepLabels = {'S1  Study load','S2  Localizer / L1-L2', ...
                          'S3  Segmentation + features','S4  QC','S5  Export'};
            stepBtns   = {'BtnS1','BtnS2','BtnS3','BtnS4','BtnS5'};
            stepCBs    = {@(~,~)app.goTab('loc'),  @(~,~)app.goTab('loc'), ...
                          @(~,~)app.goTab('dixon'),@(~,~)app.goTab('results'), ...
                          @(~,~)app.doExportCSV()};
            for k=1:5
                b = uibutton(app.GridBottom,'push');
                b.Layout.Row=1; b.Layout.Column=k;
                b.Text=stepLabels{k}; b.FontSize=12;
                b.BackgroundColor=stepColors{k};
                b.ButtonPushedFcn=stepCBs{k};
                app.(stepBtns{k}) = b;
            end

            app.LblStatus = uilabel(app.GridBottom);
            app.LblStatus.Layout.Row=2; app.LblStatus.Layout.Column=[1 6];
            app.LblStatus.Text='Ready — click Load Study to begin.';
            app.LblStatus.FontSize=11;
            app.LblStatus.FontColor=[0.40 0.40 0.40];
        end

    end % createComponents

    % =================================================================
    %  STARTUP
    % =================================================================
    methods (Access = private)
        function startupFcn(app)
            % Initialise app data struct (avoids nested-struct property issues)
            app.AD = struct( ...
                'Exam',       [], 'Selection', [], 'MATPath',    '', ...
                'Localizer',  [], 'Dixon',      [], 'MRE',        [], ...
                'L12',        [], 'L12_Dixon',  [], 'L12_MRE',    [], ...
                'L1_Row',    NaN, 'L2_Row',    NaN, ...
                'CorSlice',    1, 'SagSlice',   1, ...
                'DixonSlice',  1, 'MRESlice',   1, ...
                'MREPhase',    1, 'MREPlaying', false, ...
                'MRETimer',   [], 'StiffCLim', [0 8], 'ConfMask', false);
            app.AD.ROIs = struct( ...
                'LiverDixon',  struct('Slices',struct()), ...
                'SpleenDixon', struct('Slices',struct()), ...
                'MuscleL1', [], 'MuscleL2', [], ...
                'SATL1',    [], 'SATL2',    [], ...
                'LiverMRE',  struct('Slices',struct()), ...
                'SpleenMRE', struct('Slices',struct()));

            % Self-register all platform subfolders
            appDir = fileparts(mfilename('fullpath'));
            addpath(appDir);
            addpath(genpath(fullfile(appDir,'functions')));

            status(app,'Ready — click Load Study to begin.');
            markStep(app,1,'pending');
        end
    end

    % =================================================================
    %  CALLBACKS
    % =================================================================
    methods (Access = public)

        % ── LOAD STUDY ───────────────────────────────────────────────
        function loadStudy(app)
            folder = uigetdir(pwd,'Select DICOM Exam Folder');
            if isequal(folder,0), return; end

            dlg = uiprogressdlg(app.UIFigure,'Title','Loading Study', ...
                'Message','Parsing DICOM exam...','Indeterminate','on');
            try
                status(app,'Parsing DICOM exam...');
                exam = mre_parseDICOMExam(folder, struct('verbose',false));
                app.AD.Exam = exam;
                close(dlg);

                status(app,'Select series...');
                sel = mre_selectSeriesGUI(exam);
                if ~sel.Confirmed
                    status(app,'Series selection cancelled.');
                    return
                end
                app.AD.Selection = sel;

                dlg = uiprogressdlg(app.UIFigure,'Title','Building Data', ...
                    'Indeterminate','on');

                dlg.Message = 'Building MRE MAT file...';
                matPath = mre_buildMATFile(sel, struct('outputDir',folder, ...
                    'verbose',false,'forceRebuild',false,'interpolateWave',true));
                app.AD.MATPath = matPath;

                if ~isempty(sel.Localizer)
                    dlg.Message = 'Loading localizer...';
                    app.AD.Localizer = loc_loadLocalizer(sel.Localizer, ...
                        struct('verbose',false));
                    populateLoc(app);
                end

                if ~isempty(sel.DixonGroup)
                    dlg.Message = 'Building Dixon volumes...';
                    app.AD.Dixon = seg_buildDixonVolume(sel.DixonGroup, ...
                        struct('verbose',false));
                    populateDixon(app);
                end

                if isfile(matPath)
                    dlg.Message = 'Loading MRE data...';
                    tmp = load(matPath,'M','W','S','LapC','H');
                    app.AD.MRE = tmp;
                    populateMRE(app);
                end

                % Update study browser
                buildBrowserTree(app, exam, sel);

                app.PnlRight.Title = sprintf('Live ROI Results — %s', exam.PatientID);
                app.BtnPipeline.Enable  = 'on';
                app.BtnConfirmL12.Enable = 'on';
                app.BtnExportCSV.Enable  = 'on';

                markStep(app,1,'done');
                markStep(app,2,'active');
                status(app,sprintf('Loaded: %s  %s  |  %d series  |  MRE: %s', ...
                    exam.PatientID, exam.StudyDate, numel(exam.Series), exam.MREType));

                close(dlg);
                goTab(app,'loc');

            catch ME
                if isvalid(dlg), close(dlg); end
                uialert(app.UIFigure, ME.message,'Load Error','Icon','error');
                status(app,['ERROR: ' ME.message]);
            end
        end

        % ── WORKFLOW GUIDE ────────────────────────────────────────────
        function showWorkflowGuide(app)
            uialert(app.UIFigure, sprintf([...
                '1.  Localizer tab — scroll coronal & sagittal,\n' ...
                '    click Place L1 / Place L2, then Confirm.\n\n' ...
                '2.  Dixon tab — draw organ ROIs on Water image:\n' ...
                '    Liver (all slices), Spleen (all slices),\n' ...
                '    Muscle @ L1, Muscle @ L2, SAT @ L1, SAT @ L2.\n\n' ...
                '3.  MRE tab — draw Liver / Spleen stiffness ROIs\n' ...
                '    on the wave image, per slice.\n\n' ...
                '4.  Export menu or S5 button — CSV / MAT / session.']), ...
                'Workflow Guide','Icon','info');
        end

        % ── LOCALIZER ─────────────────────────────────────────────────
        function onCorSlide(app, src)
            sl = round(src.Value);
            app.AD.CorSlice = sl;
            nZ = size(app.AD.Localizer.Coronal.Volume,3);
            app.LblCorSlice.Text = sprintf('Slice %d / %d',sl,nZ);
            refreshCor(app);
        end

        function onSagSlide(app, src)
            sl = round(src.Value);
            app.AD.SagSlice = sl;
            nZ = size(app.AD.Localizer.Sagittal.Volume,3);
            app.LblSagSlice.Text = sprintf('Slice %d / %d',sl,nZ);
            refreshSag(app);
        end

        function placeL1(app)
            if isempty(app.AD.Localizer)
                uialert(app.UIFigure,'Load a study first.','No Data'); return
            end
            status(app,'Click on the L1 vertebra in the coronal image...');
            [~, ry] = clickOnAx(app.AxCoronal);
            if ~isnan(ry)
                app.AD.L1_Row = ry;
                refreshCor(app);
                app.LblL12Status.Text = sprintf('L1 marked (row %.0f).  Now place L2.',ry);
                app.ValL1Level.Text = 'Located';
                app.ValL1Level.FontColor = [0.18 0.60 0.34];
                status(app,'L1 placed.  Now click Place L2.');
            end
        end

        function placeL2(app)
            if isempty(app.AD.Localizer)
                uialert(app.UIFigure,'Load a study first.','No Data'); return
            end
            status(app,'Click on the L2 vertebra in the coronal image...');
            [~, ry] = clickOnAx(app.AxCoronal);
            if ~isnan(ry)
                app.AD.L2_Row = ry;
                refreshCor(app);
                app.LblL12Status.Text = sprintf( ...
                    'L1 @ row %.0f  |  L2 @ row %.0f  — click Confirm.', ...
                    app.AD.L1_Row, ry);
                app.ValL2Level.Text = 'Located';
                app.ValL2Level.FontColor = [0.18 0.60 0.34];
                status(app,'L2 placed.  Click Confirm L1-L2.');
            end
        end

        function confirmL12(app)
            if isnan(app.AD.L1_Row) || isnan(app.AD.L2_Row)
                uialert(app.UIFigure,'Place both L1 and L2 markers first.','Incomplete');
                return
            end
            L12 = rowsToL12(app);
            app.AD.L12 = L12;

            % Propagate to Dixon
            if ~isempty(app.AD.Dixon) && isfield(app.AD.Dixon.SpatialInfo,'AffineMatrix')
                try
                    app.AD.L12_Dixon = loc_propagateToSpace(L12, ...
                        app.AD.Dixon.SpatialInfo, struct('verbose',false));
                catch
                end
            end

            markStep(app,2,'done');
            markStep(app,3,'active');
            app.LblL12Status.Text = sprintf( ...
                'L1-L2 confirmed.  Dixon: L1→sl%d  L2→sl%d.  Proceed to Dixon tab.', ...
                safeIdx(app.AD.L12_Dixon,'L1_sliceIdx'), ...
                safeIdx(app.AD.L12_Dixon,'L2_sliceIdx'));
            status(app,'L1-L2 confirmed — switching to Dixon tab.');
            markStep(app,2,'done');

            % Jump Dixon slider to L1 slice
            if ~isempty(app.AD.L12_Dixon) && isfield(app.AD.L12_Dixon,'L1_sliceIdx')
                sl = max(1,min(app.AD.Dixon.nSlices, ...
                    round(app.AD.L12_Dixon.L1_sliceIdx)));
                app.SldrDixon.Value = sl;
                app.AD.DixonSlice   = sl;
                refreshDixon(app);
            end
            syncTabs(app);
            goTab(app,'dixon');
        end

        function syncTabs(app)
            % Jump MRE slider to middle slice
            if ~isempty(app.AD.MRE) && isfield(app.AD.MRE,'S')
                nZ = size(app.AD.MRE.S,3);
                app.SldrMRE.Value = max(1,round(nZ/2));
                app.AD.MRESlice   = round(nZ/2);
                refreshMRE(app);
            end
        end

        % ── DIXON ─────────────────────────────────────────────────────
        function onDixonSlide(app, src)
            sl = round(src.Value);
            app.AD.DixonSlice = sl;
            nZ = max(1,app.AD.Dixon.nSlices);
            app.LblDixonSlice.Text = sprintf('%d/%d',sl,nZ);
            refreshDixon(app);
        end

        function drawDixon(app, roiName)
            if isempty(app.AD.Dixon)
                uialert(app.UIFigure,'No Dixon data.','No Data'); return
            end
            sl = jumpToLevel(app, roiName);
            status(app,sprintf('Magnified window opened — draw %s ROI, then press Enter or A to confirm.', ...
                strrep(roiName,'_',' ')));
            try
                % Choose source image for the magnified window
                switch roiName
                    case {'SATL1','SATL2'}
                        % Show PDFF for SAT (fat is bright)
                        if ~isempty(app.AD.Dixon.PDFF)
                            img = double(app.AD.Dixon.PDFF(:,:,min(sl,end)));
                            cmap = 'hot'; climVals = [0 100];
                        else
                            img = double(app.AD.Dixon.Water(:,:,min(sl,end)));
                            cmap = 'gray'; climVals = [];
                        end
                    otherwise
                        % Water image for liver/spleen/muscle
                        img = double(app.AD.Dixon.Water(:,:,min(sl,end)));
                        cmap = 'gray'; climVals = [];
                end
                nR = size(img,1); nC = size(img,2);
                mask = openMagnifiedROIWindow(img, cmap, climVals, ...
                    sprintf('%s  —  slice %d  |  Draw ROI, then press Enter or A', ...
                        strrep(roiName,'_',' '), sl), ...
                    dxColor(roiName));
                if isempty(mask), status(app,'ROI cancelled.'); return; end
                storeROI(app,roiName,sl,logical(mask));
                overlayDixon(app,roiName,logical(mask));
                calcDixonStats(app,roiName,logical(mask),sl);
                status(app,sprintf('%s ROI placed on slice %d.',roiName,sl));
            catch ME
                status(app,['ROI error: ' ME.message]);
            end
        end

        function clearDixonSlice(app)
            sl = app.AD.DixonSlice;
            k  = sprintf('sl%d',sl);
            if isfield(app.AD.ROIs.LiverDixon.Slices,k)
                app.AD.ROIs.LiverDixon.Slices  = rmfield(app.AD.ROIs.LiverDixon.Slices,k);
            end
            if isfield(app.AD.ROIs.SpleenDixon.Slices,k)
                app.AD.ROIs.SpleenDixon.Slices = rmfield(app.AD.ROIs.SpleenDixon.Slices,k);
            end
            app.AD.ROIs.MuscleL1=[];app.AD.ROIs.MuscleL2=[];
            app.AD.ROIs.SATL1=[];app.AD.ROIs.SATL2=[];
            refreshDixon(app);
            status(app,sprintf('ROIs cleared for slice %d.',sl));
        end

        % ── MRE ───────────────────────────────────────────────────────
        function onMRESlide(app, src)
            sl = round(src.Value);
            app.AD.MRESlice = sl;
            nZ = size(app.AD.MRE.S,3);
            app.LblMRESlice.Text = sprintf('%d/%d',sl,nZ);
            refreshMRE(app);
        end

        function togglePlay(app)
            if app.AD.MREPlaying
                stop(app.AD.MRETimer);
                delete(app.AD.MRETimer);
                app.AD.MRETimer   = [];
                app.AD.MREPlaying = false;
                app.BtnMREPlay.Text = '▶ Play wave';
                app.BtnMREPlay.BackgroundColor = [0.18 0.60 0.34];
            else
                app.AD.MREPlaying = true;
                app.BtnMREPlay.Text = '⏸ Pause';
                app.BtnMREPlay.BackgroundColor = [0.74 0.34 0.10];
                t = timer('ExecutionMode','fixedRate','Period',0.15, ...
                    'TimerFcn',@(~,~)app.stepWave());
                app.AD.MRETimer = t; start(t);
            end
        end

        function stepWave(app)
            if isempty(app.AD.MRE)||~isfield(app.AD.MRE,'W'), return; end
            nPh = size(app.AD.MRE.W,4);
            ph  = mod(app.AD.MREPhase,nPh)+1;
            app.AD.MREPhase = ph;
            sl = app.AD.MRESlice;
            img = double(app.AD.MRE.W(:,:,min(sl,end),ph));
            imagesc(app.AxMREWave, img);
            title(app.AxMREWave,sprintf('Wave (ph %d/%d)',ph,nPh), ...
                'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
        end

        function setStiff(app, clim)
            app.AD.StiffCLim = clim;
            if ~isempty(app.AD.MRE)
                app.AxMREStiff.CLim = clim;
            end
            status(app,sprintf('Stiffness scale: %.0f–%.0f kPa',clim(1),clim(2)));
        end

        function setStiffCustom(app)
            a = inputdlg({'Min (kPa):','Max (kPa):'},'Custom Scale',1,{'0','8'});
            if isempty(a), return; end
            lo=str2double(a{1}); hi=str2double(a{2});
            if isnan(lo)||isnan(hi)||lo>=hi
                uialert(app.UIFigure,'Invalid range.','Error'); return
            end
            setStiff(app,[lo hi]);
        end

        function toggleConf(app)
            app.AD.ConfMask = app.BtnConfMask.Value;
            refreshMRE(app);
        end

        function drawMRE(app, roiName)
            if isempty(app.AD.MRE)
                uialert(app.UIFigure,'No MRE data.','No Data'); return
            end
            sl = app.AD.MRESlice;
            status(app,sprintf('Magnified window opened — draw %s ROI, then press Enter or A to confirm.', ...
                roiName));
            try
                % Show magnitude for contour, wave for stiffness context
                % We show magnitude (anatomy) for ROI drawing
                img = double(app.AD.MRE.M(:,:,min(sl,end)));
                % Overlay stiffness as colorised hint if available
                S = double(app.AD.MRE.S(:,:,min(sl,end)));
                if app.AD.ConfMask && isfield(app.AD.MRE,'LapC')
                    LapC = double(app.AD.MRE.LapC(:,:,min(sl,end)));
                    S(LapC < 0.95) = 0;
                end
                mask = openMagnifiedROIWindow(img, 'gray', [], ...
                    sprintf('%s  —  slice %d  |  Draw ROI on magnitude, then press Enter or A', ...
                        roiName, sl), ...
                    mreColor(roiName));
                if isempty(mask), status(app,'ROI cancelled.'); return; end
                storeROI(app,roiName,sl,logical(mask));
                calcMREStats(app,roiName,logical(mask),sl);
                status(app,sprintf('%s ROI placed on slice %d.',roiName,sl));
            catch ME
                status(app,['ROI error: ' ME.message]);
            end
        end

        function clearMRESlice(app)
            sl = app.AD.MRESlice;
            k  = sprintf('sl%d',sl);
            if isfield(app.AD.ROIs.LiverMRE.Slices,k)
                app.AD.ROIs.LiverMRE.Slices  = rmfield(app.AD.ROIs.LiverMRE.Slices,k);
            end
            if isfield(app.AD.ROIs.SpleenMRE.Slices,k)
                app.AD.ROIs.SpleenMRE.Slices = rmfield(app.AD.ROIs.SpleenMRE.Slices,k);
            end
            refreshMRE(app);
            status(app,sprintf('MRE ROIs cleared for slice %d.',sl));
        end

        % ── EXPORT ────────────────────────────────────────────────────
        function doExportCSV(app)
            if isempty(app.AD.Exam)
                uialert(app.UIFigure,'Load a study first.','No Data'); return
            end
            outDir = app.AD.Exam.ExamRootDir;
            sid    = cleanId(app.AD.Exam.PatientID, app.AD.Exam.StudyDate);
            try
                data = app.AD;
                data.AppData_ShowConfMask = app.AD.ConfMask;
                csvPath = exp_exportCSV(data, outDir, sid);
                status(app,sprintf('CSV exported: %s',csvPath));
                uialert(app.UIFigure,sprintf('Saved:\n%s',csvPath), ...
                    'Export Complete','Icon','success');
                markStep(app,5,'done');
            catch ME
                uialert(app.UIFigure,ME.message,'Export Error','Icon','error');
            end
        end

        function doExportROIs(app)
            if isempty(app.AD.Exam)
                uialert(app.UIFigure,'Load a study first.','No Data'); return
            end
            outDir = app.AD.Exam.ExamRootDir;
            sid    = cleanId(app.AD.Exam.PatientID, app.AD.Exam.StudyDate);
            try
                exp_exportROIs(app.AD, outDir, sid);
                status(app,sprintf('ROI masks saved to %s',outDir));
            catch ME
                uialert(app.UIFigure,ME.message,'Export Error','Icon','error');
            end
        end

        function doExportPDF(app)
            uialert(app.UIFigure,'PDF export will be added in Phase 7.', ...
                'Coming Soon','Icon','info');
        end

        function doSaveSession(app)
            if isempty(app.AD.Exam)
                uialert(app.UIFigure,'Load a study first.','No Data'); return
            end
            outDir = app.AD.Exam.ExamRootDir;
            sid    = cleanId(app.AD.Exam.PatientID, app.AD.Exam.StudyDate);
            try
                exp_saveSession(app.AD, outDir, sid);
                status(app,sprintf('Session saved to %s',outDir));
            catch ME
                uialert(app.UIFigure,ME.message,'Save Error','Icon','error');
            end
        end

        function doLoadSession(app)
            [f,d] = uigetfile('*_session.mat','Load Session File');
            if isequal(f,0), return; end
            try
                [appData,meta] = exp_loadSession(fullfile(d,f));
                app.AD = appData;
                app.PnlRight.Title = sprintf('Live ROI Results — %s', ...
                    appData.Exam.PatientID);
                status(app,sprintf('Session loaded (saved %s)',meta.SaveTime));
            catch ME
                uialert(app.UIFigure,ME.message,'Load Error','Icon','error');
            end
        end

        % ── MISC ──────────────────────────────────────────────────────
        function goTab(app, which)
            tabs = struct('loc',app.TabLoc,'dixon',app.TabDixon, ...
                          'mre',app.TabMRE,'results',app.TabResults);
            if isfield(tabs,which)
                app.TabGroup.SelectedTab = tabs.(which);
            end
        end

        function onTabChange(app,~)
            % Refresh active tab
        end

        function onNodeSelect(app, event)
            n = event.SelectedNodes;
            if ~isempty(n) && ~isempty(n.NodeData)
                status(app,sprintf('Selected: %s',n.Text));
            end
        end

        function filterBrowser(app,~)
            % Filter tree — placeholder for multi-subject browser
        end

        function onClose(app)
            if ~isempty(app.AD.MRETimer) && isvalid(app.AD.MRETimer)
                stop(app.AD.MRETimer); delete(app.AD.MRETimer);
            end
            sel = uiconfirm(app.UIFigure,'Close platform?','Exit', ...
                'Options',{'Close','Cancel'},'DefaultOption','Cancel', ...
                'CancelOption','Cancel');
            if strcmp(sel,'Close'), delete(app.UIFigure); end
        end
    end

    % =================================================================
    %  PRIVATE DISPLAY HELPERS
    % =================================================================
    methods (Access = private)

        function populateLoc(app)
            loc = app.AD.Localizer;
            if isempty(loc), return; end
            nC = size(loc.Coronal.Volume,3);
            nS = size(loc.Sagittal.Volume,3);
            app.SldrCor.Limits = [1 max(nC,2)];
            app.SldrSag.Limits = [1 max(nS,2)];
            app.SldrCor.Value  = round(nC/2);
            app.SldrSag.Value  = round(nS/2);
            app.AD.CorSlice    = round(nC/2);
            app.AD.SagSlice    = round(nS/2);
            app.LblCorSlice.Text = sprintf('Slice %d / %d',round(nC/2),nC);
            app.LblSagSlice.Text = sprintf('Slice %d / %d',round(nS/2),nS);
            refreshCor(app);
            refreshSag(app);
        end

        function refreshCor(app)
            loc = app.AD.Localizer;
            if isempty(loc)||isempty(loc.Coronal.Volume), return; end
            sl  = max(1,min(size(loc.Coronal.Volume,3),app.AD.CorSlice));
            img = double(loc.Coronal.Volume(:,:,sl));
            showImg(app.AxCoronal,img,sprintf('Coronal  %d',sl));
            nC = size(img,2);
            hold(app.AxCoronal,'on');
            if ~isnan(app.AD.L1_Row)
                plot(app.AxCoronal,[1 nC],[app.AD.L1_Row app.AD.L1_Row], ...
                    '-','Color',[0.96 0.58 0.11],'LineWidth',2.5);
                text(app.AxCoronal,nC-4,app.AD.L1_Row-4,'L1', ...
                    'Color',[0.96 0.58 0.11],'FontSize',11,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            if ~isnan(app.AD.L2_Row)
                plot(app.AxCoronal,[1 nC],[app.AD.L2_Row app.AD.L2_Row], ...
                    '-','Color',[0.22 0.46 0.88],'LineWidth',2.5);
                text(app.AxCoronal,nC-4,app.AD.L2_Row-4,'L2', ...
                    'Color',[0.22 0.46 0.88],'FontSize',11,'FontWeight','bold', ...
                    'HorizontalAlignment','right');
            end
            hold(app.AxCoronal,'off');
        end

        function refreshSag(app)
            loc = app.AD.Localizer;
            if isempty(loc)||isempty(loc.Sagittal.Volume), return; end
            sl  = max(1,min(size(loc.Sagittal.Volume,3),app.AD.SagSlice));
            img = double(loc.Sagittal.Volume(:,:,sl));
            showImg(app.AxSagittal,img,sprintf('Sagittal  %d',sl));
        end

        function populateDixon(app)
            dix = app.AD.Dixon;
            if isempty(dix), return; end
            nZ = max(1,dix.nSlices);
            app.SldrDixon.Limits = [1 max(nZ,2)];
            app.SldrDixon.Value  = round(nZ/2);
            app.AD.DixonSlice    = round(nZ/2);
            app.LblDixonSlice.Text = sprintf('%d/%d',round(nZ/2),nZ);
            refreshDixon(app);
        end

        function refreshDixon(app)
            dix = app.AD.Dixon;
            if isempty(dix), return; end
            sl = max(1,min(max(1,dix.nSlices),app.AD.DixonSlice));

            if ~isempty(dix.Water)
                showImg(app.AxDixonW, double(dix.Water(:,:,min(sl,end))), ...
                    sprintf('Water  sl%d',sl));
            end
            if ~isempty(dix.PDFF)
                imagesc(app.AxDixonPDFF, double(dix.PDFF(:,:,min(sl,end))));
                app.AxDixonPDFF.CLim=[0 100]; colormap(app.AxDixonPDFF,'hot');
                axis(app.AxDixonPDFF,'image');
                app.AxDixonPDFF.XTick=[]; app.AxDixonPDFF.YTick=[];
                title(app.AxDixonPDFF,sprintf('PDFF (%%)  sl%d',sl), ...
                    'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
            end
            if ~isempty(dix.InPhase)
                showImg(app.AxDixonIP, double(dix.InPhase(:,:,min(sl,end))), ...
                    sprintf('In-Phase  sl%d',sl));
            end

            % L1/L2 indicators
            l12d = app.AD.L12_Dixon;
            if ~isempty(l12d)
                for ax = [app.AxDixonW app.AxDixonPDFF app.AxDixonIP]
                    hold(ax,'on');
                    if isfield(l12d,'L1_sliceIdx') && sl==round(l12d.L1_sliceIdx)
                        nC=size(app.AD.Dixon.Water,2);
                        plot(ax,[1 nC],[nC/2 nC/2],'--', ...
                            'Color',[0.96 0.58 0.11],'LineWidth',1.5);
                        text(ax,6,12,'L1','Color',[0.96 0.58 0.11], ...
                            'FontSize',11,'FontWeight','bold');
                    end
                    if isfield(l12d,'L2_sliceIdx') && sl==round(l12d.L2_sliceIdx)
                        nC=size(app.AD.Dixon.Water,2);
                        plot(ax,[1 nC],[nC/2 nC/2],'--', ...
                            'Color',[0.22 0.46 0.88],'LineWidth',1.5);
                        text(ax,6,12,'L2','Color',[0.22 0.46 0.88], ...
                            'FontSize',11,'FontWeight','bold');
                    end
                    hold(ax,'off');
                end
            end
        end

        function populateMRE(app)
            mre = app.AD.MRE;
            if isempty(mre)||~isfield(mre,'S'), return; end
            nZ = max(1,size(mre.S,3));
            app.SldrMRE.Limits = [1 max(nZ,2)];
            app.SldrMRE.Value  = max(1,round(nZ/2));
            app.AD.MRESlice    = round(nZ/2);
            app.LblMRESlice.Text = sprintf('%d/%d',round(nZ/2),nZ);
            refreshMRE(app);
        end

        function refreshMRE(app)
            mre = app.AD.MRE;
            if isempty(mre)||~isfield(mre,'M'), return; end
            sl = max(1,min(size(mre.M,3),app.AD.MRESlice));
            ph = max(1,min(size(mre.W,4),app.AD.MREPhase));

            showImg(app.AxMREMag,double(mre.M(:,:,sl)), ...
                sprintf('Magnitude  sl%d',sl));

            img = double(mre.W(:,:,sl,ph));
            imagesc(app.AxMREWave,img); colormap(app.AxMREWave,waveCmap());
            axis(app.AxMREWave,'image');
            app.AxMREWave.XTick=[]; app.AxMREWave.YTick=[];
            title(app.AxMREWave,sprintf('Wave  sl%d  ph%d/%d',sl,ph,size(mre.W,4)), ...
                'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');

            S = double(mre.S(:,:,sl));
            if app.AD.ConfMask && isfield(mre,'LapC')
                LapC=double(mre.LapC(:,:,min(sl,end)));
                S(LapC<0.95)=0;
            end
            imagesc(app.AxMREStiff,S);
            app.AxMREStiff.CLim = app.AD.StiffCLim;
            colormap(app.AxMREStiff,stiffCmap());
            axis(app.AxMREStiff,'image');
            app.AxMREStiff.XTick=[]; app.AxMREStiff.YTick=[];
            title(app.AxMREStiff,sprintf('Stiffness (kPa)  sl%d',sl), ...
                'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
        end

        function storeROI(app, name, sl, mask)
            key = sprintf('sl%d',sl);
            switch name
                case 'LiverDixon',  app.AD.ROIs.LiverDixon.Slices.(key)  = mask;
                case 'SpleenDixon', app.AD.ROIs.SpleenDixon.Slices.(key) = mask;
                case 'MuscleL1',    app.AD.ROIs.MuscleL1 = mask;
                case 'MuscleL2',    app.AD.ROIs.MuscleL2 = mask;
                case 'SATL1',       app.AD.ROIs.SATL1    = mask;
                case 'SATL2',       app.AD.ROIs.SATL2    = mask;
                case 'LiverMRE',    app.AD.ROIs.LiverMRE.Slices.(key)   = mask;
                case 'SpleenMRE',   app.AD.ROIs.SpleenMRE.Slices.(key)  = mask;
            end
        end

        function overlayDixon(app, name, mask)
            bnd = bwboundaries(mask);
            clr = dxColor(name);
            for ax = [app.AxDixonW app.AxDixonPDFF app.AxDixonIP]
                hold(ax,'on');
                for b=1:numel(bnd)
                    plot(ax,bnd{b}(:,2),bnd{b}(:,1),'-','Color',clr,'LineWidth',2);
                end
                hold(ax,'off');
            end
        end

        function calcDixonStats(app, name, mask, sl)
            dix = app.AD.Dixon;
            if isempty(dix), return; end
            dx=dix.PixelSpacing_mm(1); dy=dix.PixelSpacing_mm(2);
            pA = dx*dy/100;   % cm²/pixel
            area = sum(mask(:))*pA;

            pdff = NaN;
            if ~isempty(dix.PDFF) && sl<=size(dix.PDFF,3)
                ff=dix.PDFF(:,:,sl); v=ff(mask); pdff=nanmean(v(isfinite(v)));
            end

            thk = dix.SliceThickness_mm;

            function vol = orgVol(slStruct)
                vol=NaN;
                if isempty(slStruct)||isempty(fieldnames(slStruct)),return;end
                ks=fieldnames(slStruct); tot=0;
                for ki=1:numel(ks)
                    m=slStruct.(ks{ki}); tot=tot+sum(m(:))*pA;
                end
                vol=tot*(thk/10);
            end

            switch name
                case 'LiverDixon'
                    vol=orgVol(app.AD.ROIs.LiverDixon.Slices);
                    if isnan(vol), app.ValLiverVol.Text=sprintf('%.0f cm²',area);
                    else,          app.ValLiverVol.Text=sprintf('%.0f mL',vol); end
                    if ~isnan(pdff), app.ValLiverPDFF.Text=sprintf('%.1f%%',pdff); end
                case 'SpleenDixon'
                    vol=orgVol(app.AD.ROIs.SpleenDixon.Slices);
                    if isnan(vol), app.ValSpleenVol.Text=sprintf('%.0f cm²',area);
                    else,          app.ValSpleenVol.Text=sprintf('%.0f mL',vol); end
                case 'MuscleL1'
                    app.ValMuscArea.Text    = sprintf('%.1f cm²',area);
                    app.ValMuscAreaL12.Text = sprintf('%.1f cm²',area);
                    if ~isnan(pdff), app.ValMusclePDFF.Text=sprintf('%.1f%%',pdff); end
                case 'MuscleL2'
                    app.ValMuscArea.Text = sprintf('%.1f cm²',area);
                case 'SATL1'
                    app.ValSATArea.Text    = sprintf('%.1f cm²',area);
                    app.ValSATAreaL12.Text = sprintf('%.1f cm²',area);
                case 'SATL2'
                    app.ValSATArea.Text = sprintf('%.1f cm²',area);
            end

            % Muscle:fat ratio
            mStr=app.ValMuscArea.Text; sStr=app.ValSATArea.Text;
            mV=str2double(strrep(mStr,' cm²','')); sV=str2double(strrep(sStr,' cm²',''));
            if isfinite(mV)&&isfinite(sV)&&sV>0
                app.ValMuscleFat.Text=sprintf('%.2f',mV/sV);
            end
            syncResultsTable(app);
        end

        function calcMREStats(app, name, mask, sl)
            mre = app.AD.MRE;
            if isempty(mre)||~isfield(mre,'S'), return; end
            S = double(mre.S(:,:,min(sl,end)));
            if app.AD.ConfMask && isfield(mre,'LapC')
                LapC=double(mre.LapC(:,:,min(sl,end)));
                S(LapC<0.95)=NaN;
            end
            v = S(mask & isfinite(S));
            if isempty(v), return; end
            med=nanmedian(v); iqr_=iqr(v);
            conf=NaN;
            if isfield(mre,'LapC')
                LapC=double(mre.LapC(:,:,min(sl,end)));
                conf=nanmean(LapC(mask));
            end
            switch name
                case 'LiverMRE'
                    app.ValLiverStiff.Text = sprintf('%.1f kPa',med);
                    app.ValLiverIQR.Text   = sprintf('%.1f kPa',iqr_);
                    if ~isnan(conf)
                        app.ValSegConf.Text = sprintf('%.2f',conf);
                        setQCColor(app.ValSegConf,conf>=0.90);
                    end
                case 'SpleenMRE'
                    app.ValSpleenStiff.Text = sprintf('%.1f kPa',med);
                    if ~isnan(conf), setQCColor(app.ValSegConf,conf>=0.90); end
            end
            % Liver:spleen ratio
            lStr=app.ValLiverStiff.Text; sStr=app.ValSpleenStiff.Text;
            lV=str2double(strrep(lStr,' kPa','')); sV=str2double(strrep(sStr,' kPa',''));
            if isfinite(lV)&&isfinite(sV)&&sV>0
                app.ValLSRatio.Text=sprintf('%.2f',lV/sV);
            end
            syncResultsTable(app);
        end

        function syncResultsTable(app)
            rows = {
                'Liver volume',         app.ValLiverVol.Text,      'mL',   'Dixon all slices'
                'Liver PDFF',           app.ValLiverPDFF.Text,     '%',    'IDEAL-IQ'
                'Liver MRE stiffness',  app.ValLiverStiff.Text,    'kPa',  'Median'
                'Liver stiffness IQR',  app.ValLiverIQR.Text,      'kPa',  ''
                'Spleen volume',        app.ValSpleenVol.Text,     'mL',   'Dixon all slices'
                'Spleen MRE stiffness', app.ValSpleenStiff.Text,   'kPa',  'Median'
                'Liver:spleen ratio',   app.ValLSRatio.Text,       '',     'Stiffness ratio'
                'Muscle area (L1-L2)',  app.ValMuscArea.Text,      'cm²',  'Mean L1+L2'
                'SAT area (L1-L2)',     app.ValSATArea.Text,       'cm²',  'Mean L1+L2'
                'Muscle:fat ratio',     app.ValMuscleFat.Text,     '',     ''
                'Muscle PDFF',          app.ValMusclePDFF.Text,    '%',    ''
                'Seg. confidence',      app.ValSegConf.Text,       '',     'LapC'
            };
            try, app.TblResults.Data = rows; catch, end
        end

        function markStep(app, n, state)
            btns = {app.BtnS1,app.BtnS2,app.BtnS3,app.BtnS4,app.BtnS5};
            switch state
                case 'pending', btns{n}.BackgroundColor=[0.80 0.80 0.80];
                case 'active',  btns{n}.BackgroundColor=[0.92 0.76 0.14];
                case 'done',    btns{n}.BackgroundColor=[0.65 0.88 0.65];
            end
        end

        function buildBrowserTree(app, exam, sel)
            delete(app.TreeStudy.Children);
            % Site node
            site = uitreenode(app.TreeStudy,'Text', ...
                sprintf('Site: %s', getSite(exam)));
            site.NodeData = [];
            % Subject node
            subj = uitreenode(site,'Text', ...
                sprintf('Subject: %s',exam.PatientID));
            subj.NodeData = exam;
            % Session node (selected, highlighted)
            sess = uitreenode(subj,'Text', ...
                sprintf('Session %s  ✓',exam.StudyDate));
            sess.NodeData = sel;
            expand(site,'all'); expand(subj,'all');
            app.TreeStudy.SelectedNodes = sess;
            app.LblBrowserFoot.Text = sprintf( ...
                'Loaded: 1 / 1 study  |  MRE: %s',exam.MREType);
        end

        function status(app, msg)
            ts = datestr(now,'HH:MM:SS');
            app.LblStatus.Text = sprintf('[%s]  %s',ts,msg);
            drawnow limitrate;
        end

        function L12 = rowsToL12(app)
            L12 = struct('L1_mm',NaN,'L2_mm',NaN,'L1_L2_mid_mm',NaN, ...
                'L1_row_coronal',app.AD.L1_Row, ...
                'L2_row_coronal',app.AD.L2_Row, ...
                'Confidence',1.0,'DetectionMethod','manual', ...
                'SourcePlane','Coronal','PixelSpacing_mm',[1 1]);
            try
                sinfo = app.AD.Localizer.Coronal.SpatialInfo;
                ps  = sinfo.PixelSpacing(1);
                iop = sinfo.ImageOrientationPatient;
                rDir= iop(1:3);
                imgPos = app.AD.Localizer.Coronal.ImagePositions( ...
                    app.AD.CorSlice,:);
                L1pos = imgPos + (app.AD.L1_Row-1)*ps*rDir;
                L2pos = imgPos + (app.AD.L2_Row-1)*ps*rDir;
                L12.L1_mm = L1pos(3); L12.L2_mm = L2pos(3);
                L12.L1_L2_mid_mm = (L12.L1_mm+L12.L2_mm)/2;
                L12.PixelSpacing_mm = [ps ps];
            catch
            end
        end

        function sl = jumpToLevel(app, roiName)
            sl = app.AD.DixonSlice;
            l12d = app.AD.L12_Dixon;
            if isempty(l12d), return; end
            switch roiName
                case {'MuscleL1','SATL1'}
                    if isfield(l12d,'L1_sliceIdx') && ~isnan(l12d.L1_sliceIdx)
                        sl=max(1,min(app.AD.Dixon.nSlices,round(l12d.L1_sliceIdx)));
                        app.AD.DixonSlice=sl; app.SldrDixon.Value=sl;
                        app.LblDixonSlice.Text=sprintf('%d/%d',sl,app.AD.Dixon.nSlices);
                        refreshDixon(app);
                    end
                case {'MuscleL2','SATL2'}
                    if isfield(l12d,'L2_sliceIdx') && ~isnan(l12d.L2_sliceIdx)
                        sl=max(1,min(app.AD.Dixon.nSlices,round(l12d.L2_sliceIdx)));
                        app.AD.DixonSlice=sl; app.SldrDixon.Value=sl;
                        app.LblDixonSlice.Text=sprintf('%d/%d',sl,app.AD.Dixon.nSlices);
                        refreshDixon(app);
                    end
            end
        end
    end

    % =================================================================
    %  CONSTRUCTOR / DESTRUCTOR
    % =================================================================
    methods (Access = public)
        function app = HepatosplenicMRE_App()
            initUI(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            app.UIFigure.Visible = 'on';
            if nargout == 0, clear app; end
        end
        function delete(app)
            try
                if ~isempty(app.AD) && isfield(app.AD,'MRETimer') && ...
                   ~isempty(app.AD.MRETimer) && isvalid(app.AD.MRETimer)
                    stop(app.AD.MRETimer); delete(app.AD.MRETimer);
                end
            catch
            end
            delete(app.UIFigure);
        end
    end
end


% =========================================================================
%  MODULE-LEVEL UTILITIES
% =========================================================================

function darkAx(ax, ttl)
    ax.XTick=[]; ax.YTick=[]; ax.Box='on';
    ax.Color=[0.06 0.06 0.06];
    ax.XColor=[0.28 0.28 0.28]; ax.YColor=[0.28 0.28 0.28];
    colormap(ax,'gray');
    title(ax,ttl,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function showImg(ax, img, ttl)
    lo=min(img(:)); hi=max(img(:));
    if hi>lo, img=(img-lo)/(hi-lo); end
    imagesc(ax,img); colormap(ax,'gray'); axis(ax,'image');
    ax.XTick=[]; ax.YTick=[];
    title(ax,ttl,'FontSize',12,'Color',[0.72 0.72 0.72],'FontWeight','normal');
end

function b = tb(parent, col, txt, bg, fg)
    b = uibutton(parent,'push');
    b.Layout.Column=col; b.Text=txt;
    b.FontSize=13; b.FontWeight='bold';
    b.BackgroundColor=bg; b.FontColor=fg;
end

function b = locBtn(parent, col, txt, bg, fg)
    b = uibutton(parent,'push');
    b.Layout.Column=col; b.Text=txt;
    b.FontSize=12; b.FontWeight='bold';
    b.BackgroundColor=bg; b.FontColor=fg;
end

function b = roiB(parent, row, txt, bg, fg)
    b = uibutton(parent,'push');
    b.Layout.Row=row; b.Text=txt;
    b.FontSize=12; b.FontWeight='bold';
    b.BackgroundColor=bg; b.FontColor=fg;
end

function hintCard(parent, col, title_, accentClr, line1, line2)
    p = uipanel(parent,'BorderType','line','BackgroundColor',[0.98 0.98 0.98]);
    p.Layout.Column = col;
    g = uigridlayout(p,[3 1]);
    g.RowHeight={20,18,18}; g.Padding=[6 2 6 2]; g.RowSpacing=1;

    lt = uilabel(g); lt.Layout.Row=1;
    lt.Text=title_; lt.FontSize=12; lt.FontWeight='bold';
    lt.FontColor=accentClr;

    l1 = uilabel(g); l1.Layout.Row=2;
    l1.Text=line1; l1.FontSize=10; l1.FontColor=[0.35 0.35 0.35];

    l2 = uilabel(g); l2.Layout.Row=3;
    l2.Text=line2; l2.FontSize=10; l2.FontColor=[0.45 0.45 0.45];
    l2.WordWrap='on';
end

function varargout = measSection(parent, row, title_, accentClr, labels, defaults)
    pnl = uipanel(parent,'Title',title_,'FontSize',11,'FontWeight','bold', ...
        'ForegroundColor',accentClr,'BackgroundColor',[0.97 0.97 0.97]);
    pnl.Layout.Row = row;
    n = numel(labels);
    g = uigridlayout(pnl,[n 2]);
    g.ColumnWidth={'1x','1x'}; g.RowHeight=repmat({18},1,n);
    g.Padding=[4 2 4 2]; g.ColumnSpacing=2; g.RowSpacing=1;
    varargout = cell(1,n);
    for k=1:n
        lbl=uilabel(g); lbl.Layout.Row=k; lbl.Layout.Column=1;
        lbl.Text=labels{k}; lbl.FontSize=10; lbl.FontColor=[0.42 0.42 0.42];
        val=uilabel(g); val.Layout.Row=k; val.Layout.Column=2;
        val.Text=defaults{k}; val.FontSize=11; val.FontWeight='bold';
        val.HorizontalAlignment='right'; val.FontColor=[0.20 0.20 0.20];
        varargout{k}=val;
    end
end

function clr = dxColor(name)
    switch name
        case {'LiverDixon','MuscleL1','MuscleL2'}, clr=[0.15 0.75 0.15];
        case 'SpleenDixon',                         clr=[0.15 0.55 0.90];
        case {'SATL1','SATL2'},                     clr=[0.95 0.65 0.10];
        otherwise,                                  clr=[1 1 0];
    end
end

function clr = mreColor(name)
    if contains(name,'Liver'), clr=[0.15 0.85 0.15];
    else,                      clr=[0.15 0.65 0.95]; end
end

function cmap = waveCmap()
    if exist('awave','file')==2
        try, cmap=awave(256); if size(cmap,2)==3,return;end, catch,end
    end
    n=128;
    cmap=[[linspace(0,1,n)', linspace(0,1,n)', ones(n,1)]; ...
          [ones(n,1), linspace(1,0,n)', linspace(1,0,n)']];
end

function cmap = stiffCmap()
    if exist('aaasmo','file')==2
        try, cmap=aaasmo(256); if size(cmap,2)==3,return;end, catch,end
    end
    cmap=hot(256);
end

function mask = createMask(h, nR, nC)
    try, mask=h.createMask();
    catch
        pos=h.Position; mask=poly2mask(pos(:,1),pos(:,2),nR,nC);
    end
    mask=logical(mask);
end

function [x,y] = clickOnAx(ax)
    x=NaN; y=NaN;
    try
        fig=ancestor(ax,'figure');
        ax.ButtonDownFcn=@(~,e)assignin('base','_click_',[e.IntersectionPoint(1) e.IntersectionPoint(2)]);
        uiwait(fig,5);
        pt=evalin('base','_click_');
        x=pt(1); y=pt(2);
        evalin('base','clear _click_');
    catch
    end
    ax.ButtonDownFcn='';
end

function v = safeIdx(st, field)
    if ~isempty(st) && isfield(st,field) && ~isnan(st.(field))
        v = round(st.(field));
    else
        v = 0;
    end
end

function s = getSite(exam)
    if ~isempty(exam.ScannerModel), s=exam.ScannerModel;
    else, s='Unknown site'; end
end

function s = cleanId(pid, date_)
    s = strrep(sprintf('%s_%s',pid,date_),' ','_');
end

function setQCColor(lbl, pass)
    if pass, lbl.FontColor=[0.10 0.60 0.20];
    else,     lbl.FontColor=[0.80 0.15 0.10]; end
end

function mask = openMagnifiedROIWindow(img, cmap, climVals, titleStr, roiColor)
% OPENMAGNIFIEDROIWINDOW  Open a large figure for precise ROI drawing.
%
%   Opens a maximised figure showing IMG, lets the user draw a freehand ROI,
%   and returns the binary mask when the user presses Enter or 'A'.
%   Pressing Escape or closing the window cancels and returns [].
%
%   INPUTS
%     img       [nR x nC] double  image to display
%     cmap      char              colormap name ('gray','hot',...)
%     climVals  [lo hi] or []     colour limits; [] = auto
%     titleStr  char              window title / instruction string
%     roiColor  [1x3]             RGB colour for ROI outline
%
%   OUTPUT
%     mask      logical [nR x nC]  ROI mask, or [] if cancelled

    mask = [];

    % ── Create maximised figure ───────────────────────────────────────
    hFig = figure('Name', titleStr, ...
        'NumberTitle',    'off', ...
        'MenuBar',        'none', ...
        'ToolBar',        'figure', ...
        'WindowState',    'maximized', ...
        'Color',          [0.08 0.08 0.08], ...
        'CloseRequestFcn',@(~,~)onClose());

    % ── Axes fills the window ─────────────────────────────────────────
    ax = axes(hFig, 'Position',[0.02 0.08 0.96 0.88]);
    ax.Color  = [0.06 0.06 0.06];
    ax.XColor = [0.3 0.3 0.3];
    ax.YColor = [0.3 0.3 0.3];

    % Display image
    imagesc(ax, img);
    colormap(ax, cmap);
    if ~isempty(climVals)
        clim(ax, climVals);
    end
    axis(ax, 'image');
    ax.XTick = []; ax.YTick = [];
    colorbar(ax, 'Color',[0.65 0.65 0.65]);

    % ── Instruction bar at bottom ─────────────────────────────────────
    annotation(hFig, 'textbox', [0 0 1 0.06], ...
        'String', ['  ' titleStr '   |   Press  Enter  or  A  to confirm  —  Esc to cancel'], ...
        'FitBoxToText', 'off', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'Color', [0.95 0.85 0.20], ...
        'BackgroundColor', [0.12 0.12 0.12], ...
        'EdgeColor', 'none', ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'middle');

    % ── State ─────────────────────────────────────────────────────────
    confirmed = false;
    cancelled = false;
    hROI      = [];

    % ── Key handler ───────────────────────────────────────────────────
    hFig.KeyPressFcn = @onKey;

    % ── Draw ROI ──────────────────────────────────────────────────────
    try
        hROI = drawfreehand(ax, 'Color', roiColor, ...
            'LineWidth', 2.5, 'FaceAlpha', 0.18);
        % Non-blocking: use listener so window stays interactive
        addlistener(hROI, 'ROIClicked',  @(~,~)[] );   % keep alive
    catch
        if ishandle(hFig), close(hFig); end
        return
    end

    % ── Wait for confirm / cancel ─────────────────────────────────────
    uiwait(hFig);

    % ── Extract mask ──────────────────────────────────────────────────
    if confirmed && ~cancelled && isvalid(hROI)
        try
            nR = size(img,1); nC = size(img,2);
            mask = logical(createMask(hROI, nR, nC));
        catch
            mask = [];
        end
    end

    if ishandle(hFig), delete(hFig); end

    % ==================================================================
    %  NESTED CALLBACKS
    % ==================================================================
    function onKey(~, event)
        key = lower(event.Key);
        if strcmp(key,'return') || strcmp(key,'a')
            confirmed = true;
            uiresume(hFig);
        elseif strcmp(key,'escape')
            cancelled = true;
            uiresume(hFig);
        end
    end

    function onClose()
        cancelled = true;
        uiresume(hFig);
        delete(hFig);
    end
end

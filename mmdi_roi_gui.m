function status = mmdi_roi_gui(matPath, meta)
% MMDI_ROI_GUI Interactive 3-panel viewer (Magnitdue/Wave/Stiffness) + per-slice ROI.
%
% Post-processing *.MAT data structure from Kevin:
% P is the "mmdi.phs" file.
% M is the "mmdi.mag" file. 
% G is the "mmdi.mu" (complex shear modulus) file.
% S is the "mmdi.stiff" file.
% MuC is the "mmdi.mu_conf" file.
% LapC is the "mmdi.lap_conf" file.
% ATN is the "mmdi.atn" file.
% W is the "mmdi.waves" file.
% There is also a DICOM header "H" in there, but MRE-Lab can't load or handle Matlab structures, as far as I know, so one would have to load that into Matlab to cross-check any information (e.g., load(input_file,'H')).
%
% Current workflow (two-stage ROI per slice):
%   1) Seed CIRCLE on Magnitude (time-averaged) -> auto mask -> OUTER contour ROI (editable)
%       Optional manual free-hand ROI with hotkey "f" on magnitude image
%      Double-click to commit OUTER contour for organ volume and shape quantifications.
%   2) INNER stiffness measurement ROI initialized by 3-pixel erosion (editable, +/- to increase/decrease)
%       Optoinal manual free-hand ROI with hotkey "f" on wave image
%      Double-click to commit INNER ROI * LapC for valid stiffness measurement.
%      Complex ROI with inclusion ("i") or exclusion ("x") options
%
% Saved outputs per series:
%   <organ>_contour.roi   (outer boundary; binary mask per slice)
%   <organ>.roi           (inner measurement ROI; binary mask per slice)
%   <organ>.xlsx          (measurement export including stiffness, 3D and 2D shape metrics)
%
% Display:
%   - Magnitude has its own grayscale colorbar.
%   - Drag the MAG colorbar to adjust window/level (W/L).
%       left/right = level, up/down = window
%     Right-click the MAG colorbar to reset to auto window/level.
%   - Stiffness uses two optional ranges: 0-8 kPa or 0-20 kPa (colorbar shown).
%   - Cursor readout shows Stiffness value in GREEN or RED (LapC=0.95) color under mouse on stiffness panel.
%   - Use hotkey "z" to zoom in/out either one of the M/W/S images
%   - Use hotkey "a" to skip ROI drowing if no targeted organ
%   - Use hotkey "s" to skip ROI drawing if no waves in the targeted organ
%   - Use hotkey "n" to proceed ROI drawing on the next pending slice
%   - Use hotkey "e" to edit vertice position of polygon ROIs
%   - Use hotkey "c" to clear all ROIs on the current slice
%   - Use hotkey "d" to place circular seed on magnitude for automated ROI
%   - Use hotkey "f" to engage freehand ROIs, "i" for inclusion, "e" for exclusion of an isolated ROI for complex ROI drawing
%   
% Saving:
%   - Use "g" to export current M/W/S in GIF animation (interpolated up to 8 offsets)
%   - Use "Finish & Save" botton to save ROIs and measures in excel spreadsheets 
%
% Meng Yin, Last modification on February 13, 2026
% Radiology, Mayo Clinic Rochester Minnesota

status = 'abort';
statusLocked = false;  % Prevent onClose from changing status after successful save
hasUnsavedChanges = false;

if ~isfile(matPath)
    error('MAT not found: %s', matPath);
end

% ---------- Series directory ----------
% Prefer meta.SeriesDir if provided; otherwise derive from matPath.
seriesDir = fileparts(matPath);
if nargin >= 2 && isstruct(meta) && isfield(meta,'SeriesDir') && isfolder(meta.SeriesDir)
    seriesDir = meta.SeriesDir;
end

% ---------- Organ selection ----------
% If exactly ONE organ already has ROI files, auto-select it (no dialog).
organ = '';
try
    hasSpleen = isfile(fullfile(seriesDir,'spleen.roi')) && isfile(fullfile(seriesDir,'spleen_contour.roi'));
    hasLiver  = isfile(fullfile(seriesDir,'liver.roi'))  && isfile(fullfile(seriesDir,'liver_contour.roi'));
    if hasSpleen && ~hasLiver
        organ = 'spleen';
    elseif hasLiver && ~hasSpleen
        organ = 'liver';
    end
catch
end

if isempty(organ)
    choice = questdlg('Select target organ for ROI:', 'Organ', 'Liver', 'Spleen', 'Skip series', 'Liver');
    if isempty(choice) || strcmpi(choice, 'Skip series')
        status = 'skipped';
        return;
    end
    organ = lower(choice); % 'liver' | 'spleen'
end

% ---------- Measurement ROI erosion (hotkeys +/- for user adjustment) ----------
minErodePx = 3;     % cannot go below this
erodePx    = 3;     % default

% ---------- Laplacian confidence cutoff (LapC) ----------
lapCutoff      = 0.95;   % rule out pixels with LapC < 0.95
lapHatchAlpha  = 0.35;  % hatch opacity (0..1)
hasLapC        = false; % set true if LapC exists in MAT
lapPattern     = [];    % precomputed hatch pattern (logical)
hLapHatch      = [];    % graphics handle for hatch overlay

% ---------- Vertex count for polygon simplification (NEW) ----------
vertexCount = 120;      % default vertex count
minVertexCount = 30;    % minimum allowed
maxVertexCount = 300;   % maximum allowed

seriesDir = meta.SeriesDir;

roiPathMeas    = fullfile(seriesDir, sprintf('%s.roi', organ));          % inner ROI for stiffness measurement
roiPathContour = fullfile(seriesDir, sprintf('%s_contour.roi', organ));  % outer boundary
xlsxPath       = fullfile(seriesDir, sprintf('%s.xlsx', organ));

% If ROI exists for this series, ask user whether to review/edit or export-only
exportOnly = false;
loadExistingROIs = false;
isReviewMode = false;

if isfile(roiPathMeas) && isfile(roiPathContour)

    choice = questdlg( ...
        sprintf('ROI files already exist for:\
%s / %s\
\
What would you like to do?', meta.ExamId, meta.SeriesId), ...
        'ROIs found', ...
        'Review/Edit ROIs', 'Export only', 'Skip', ...
        'Review/Edit ROIs');

    switch choice
        case 'Review/Edit ROIs'
            loadExistingROIs = true;    % load ROI masks/vertices then open GUI
            isReviewMode = true;
        case 'Export only'
            exportOnly = true;          % current behavior: overwrite spreadsheets
        otherwise
            status = 'skipped';
            return;
    end

elseif isfile(roiPathMeas) || isfile(roiPathContour)
    warndlg(sprintf(['ROI file exists but is incomplete:\
%s\
%s\
' ...
        'Delete both to redraw, or ensure both are present.'], roiPathMeas, roiPathContour), 'ROI exists');
    status = 'skipped';
    return;
end


% ---------- Load variables ----------
vars = who('-file', matPath);
hasLapC = ismember('LapC', vars);   % Laplacian confidence (0..1)

if ~hasLapC
    warning('LapC not found in %s. LapC cutoff masking/hatched overlay disabled.', matPath);
end
need = {'M','W','S','H'};
for k = 1:numel(need)
    if ~ismember(need{k}, vars)
        error('Missing variable "%s" in %s', need{k}, matPath);
    end
end

matIsV73 = isMatV73(matPath);

useMatfile = matIsV73;
if useMatfile
    mobj = matfile(matPath);   % true partial loading works
else
    % NOT v7.3 -> do NOT use matfile indexing (it triggers the warning repeatedly)
    % Load once instead (no warning spam)
    if hasLapC
        tmp = load(matPath, 'M','W','S','H','LapC');
    else
        tmp = load(matPath, 'M','W','S','H');
    end
    M = tmp.M; W = tmp.W; S = tmp.S;
    if hasLapC, LapC = tmp.LapC; else, LapC = []; end
    if isfield(tmp,'H'), H = tmp.H; else, H = []; end
end

if useMatfile
    szM = size(mobj, 'M');  % [row col z t]
    szW = size(mobj, 'W');
    szS = size(mobj, 'S');
else
    tmp = load(matPath, 'M','W','S');
    M = tmp.M; W = tmp.W; S = tmp.S;
    szM = size(M);
    szW = size(W);
    szS = size(S);
end

% Fixed dimensions from known acquisition parameters
nRow = 256;  % Always 256x256 in-plane resolution
nCol = 256;
nZ   = szM(3);  % Number of slices (same for M, W, S)

% Precompute a simple cross-hatch pattern
[xg, yg] = meshgrid(1:nCol, 1:nRow);
period = 4;
width  = 2;
lapPattern = (mod(xg + yg, period) < width) | (mod(xg - yg, period) < width);
clear xg yg

% Time dimension: M has original (3), W is interpolated (8)
nT_M = 1; if numel(szM) >= 4, nT_M = szM(4); end
nT_W = 1; if numel(szW) >= 4, nT_W = szW(4); end

% Use W's time dimension for GUI (smoother animation with 8 frames)
nT = nT_W;  

fprintf('Data loaded: M[%d\u00d7%d\u00d7%d\u00d7%d], W[%d\u00d7%d\u00d7%d\u00d7%d], using nT=%d for display\
', ...
    nRow, nCol, nZ, nT_M, nRow, nCol, nZ, nT_W, nT);

isS4D = (numel(szS) >= 4) && (szS(4) > 1);

% ----------  DICOM header (H) ----------
% Used for physical voxel spacing (radiomics/shape metrics)
Hhdr = [];
if ismember('H', vars)
    try
        if useMatfile
            Hhdr = mobj.H;
        else
            tmpH = load(matPath, 'H');
            Hhdr = tmpH.H;
        end
    catch
        Hhdr = [];
    end
end

% ---------- Custom colormaps ----------
% Waves colormap (awave)
if exist('awave','file') == 2
    waveCmap = awave(256);
else
    warning('awave.m not found on MATLAB path. Using gray for waves.');
    waveCmap = gray(256);
end

% Stiffness colormap (aaasmo)
if exist('aaasmo','file') == 2
    stiffCmap = aaasmo(256);
else
    warning('aaasmo.m not found on MATLAB path. Using parula for stiffness.');
    stiffCmap = parula(256);
end

% Fixed stiffness display range (kPa) -- using 0-8kPa in this project
stiffCLim = [0 8];

% ---------- UI font style ----------
UI_FS = 16;          % increase if needed
UI_FW = 'bold';

% Cap polygon vertex counts to keep manual editing responsive.
MAX_POLY_VERTS = 150;

% ---------- ROI storage per slice ----------
% OUTER contour ROI (organ boundary)
roiMaskContour     = false(nRow, nCol, nZ);
roiVerticesContour = cell(nZ, 1);

% Anatomy status per slice (OUTER contour workflow)
%   0 = unprocessed
%   1 = contour ROI confirmed
%  -1 = skip anatomy (no spleen/organ on this slice)
sliceStateContour  = zeros(nZ, 1, 'int8');

% INNER measurement ROI (used for stiffness export)
roiMask     = false(nRow, nCol, nZ);
roiVertices = cell(nZ, 1);

% MRE/measurement status per slice (INNER ROI workflow)
%   0 = unprocessed (contour exists, but no measurement ROI / not marked failed)
%   1 = measurement ROI confirmed (used for stiffness export)
%  -1 = skip MRE (technical failure / unreliable stiffness)
sliceState  = zeros(nZ, 1, 'int8');

% ---------- Viewer state ----------
state.z = max(1, round(nZ/2));
state.t = 1;
state.isPlaying = false;
% Flag to ignore time-slider listener during programmatic updates (timer/setTime)
isUpdatingT = false;

pos_axM = []; pos_axW = []; pos_axS = [];  % remember original positions
pos_pnl = [];

% Magnitude W/L (manual)
state.useManualClimM = false;
state.manualClimM = [0 1];
state.isWLDragging = false;
state.wlStartPt = [0 0];
state.wlStartCLim = [0 1];
state.seedToolActive = false; % true while drawing the seed circle (prevents WL drag)

% Cache slice data
cache = struct('z', NaN, 'M', [], 'W', [], 'S', [], 'LapC', [], 'climM', [], 'climW', []);

% ---------- Live ROI (edit/copy) objects ----------
hLiveRoi = [];
liveListeners = event.listener.empty(0,1);
liveStage = "";   % "contour" or "meas"

% ---------- Zoom mode (overlay, works with tiledlayout) ----------
isZoom    = false;   % toggled by hotkey 'z'
zoomTarget = 'S';    % 'M' / 'W' / 'S' (which image is shown in zoom)

pnlZoom = [];        % overlay panel (covers the tiledlayout area)
axZ     = [];        % zoom axes
hImZ    = [];        % zoom image handle

% Zoom overlay boundary handles
hContourBoundZ = gobjects(0);   % outer contour boundaries on zoom
hRoiBoundZ     = gobjects(0);   % inner ROI boundaries on zoom

% ---------- Export-only mode (ROIs already exist) ----------
if exportOnly
    fprintf('ROI exists (%s): %s/%s -- exporting reports only...\
', upper(organ), meta.ExamId, meta.SeriesId);

    % Load existing ROI MAT-files (saved with .roi extension)
    tmpMeas = tryLoadMat(roiPathMeas);
    if isfield(tmpMeas,'roiMask'),     roiMask     = tmpMeas.roiMask; end
    if isfield(tmpMeas,'roiVertices'), roiVertices = tmpMeas.roiVertices; end
    if isfield(tmpMeas,'sliceState'),  sliceState  = tmpMeas.sliceState; end

    tmpC = tryLoadMat(roiPathContour);
    if isfield(tmpC,'roiMaskContour'),     roiMaskContour     = tmpC.roiMaskContour; end
    if isfield(tmpC,'roiVerticesContour'), roiVerticesContour = tmpC.roiVerticesContour; end
    if isfield(tmpC,'sliceStateContour'),  sliceStateContour  = tmpC.sliceStateContour; end

    % Run exports (overwrite the xlsx so it stays in sync with ROI files)
    try
        export_summary_and_voxels_ROIonly();
    catch ME
        warning('Stiffness export failed: %s', ME.message);
    end
    try
        export_contour_shape_metrics();
    catch ME
        warning('Contour metrics export failed: %s', ME.message);
    end

    status = 'saved';
    return;
end

% ---------- Review/Edit mode (ROIs already exist) ----------
if loadExistingROIs
    fprintf('ROI exists (%s): %s/%s -- opening GUI for review/edit...\
', upper(organ), meta.ExamId, meta.SeriesId);

    % Load existing INNER ROI
    tmpMeas = tryLoadMat(roiPathMeas);
    if isfield(tmpMeas,'roiMask'),     roiMask     = tmpMeas.roiMask; end
    if isfield(tmpMeas,'roiVertices'), roiVertices = tmpMeas.roiVertices; end
    if isfield(tmpMeas,'sliceState'),  sliceState  = tmpMeas.sliceState; end

    % Load existing OUTER ROI
    tmpC = tryLoadMat(roiPathContour);
    if isfield(tmpC,'roiMaskContour'),      roiMaskContour      = tmpC.roiMaskContour; end
    if isfield(tmpC,'roiVerticesContour'),  roiVerticesContour  = tmpC.roiVerticesContour; end
    if isfield(tmpC,'sliceStateContour'),   sliceStateContour   = tmpC.sliceStateContour; end
end


% ---------- UI ----------
fig = figure('Name', sprintf('%s ROI: %s/%s', upper(organ), meta.ExamId, meta.SeriesId), ...
    'NumberTitle','off', 'Color','w', 'Toolbar','none', 'MenuBar','none');
try
    fig.WindowState = 'maximized';
catch
    set(fig, 'Units','normalized', 'OuterPosition', [0 0 1 1]);
end

% Apply defaults (helps axes/text created after this point)
set(fig, ...
    'DefaultUIControlFontSize', UI_FS, ...
    'DefaultUIControlFontWeight', UI_FW, ...
    'DefaultTextFontSize', UI_FS, ...
    'DefaultTextFontWeight', UI_FW, ...
    'DefaultAxesFontSize', UI_FS, ...
    'DefaultAxesFontWeight', UI_FW);

% Leave room left (MAG colorbar) and right (S colorbar)
tl = tiledlayout(fig, 1, 3, 'Padding','compact', 'TileSpacing','compact');
tl.Position = [0.06 0.22 0.88 0.78];

axM = nexttile(tl, 1); setupAx(axM); title(axM, 'M (Magnitude)');
axW = nexttile(tl, 2); setupAx(axW); title(axW, 'W (Waves)');
axS = nexttile(tl, 3); setupAx(axS); title(axS, 'S (Stiffness)');

% Track the last axes the user interacted with (used for context-sensitive hotkeys)
lastClickedAx = axM;

loadSlice(state.z);
updateLapCHatch();

hImM = imagesc(axM, getMframe(state.t));
hImW = imagesc(axW, getWframe(state.t));
hImS = imagesc(axS, getSframe(state.t));

% Cursor readout overlay on the stiffness axis (superimposed)
txtCursor = text(axS, 0.02, 0.98, '', ...
    'Units','normalized', ...
    'HorizontalAlignment','left', ...
    'VerticalAlignment','top', ...
    'FontWeight','bold', ...
    'FontSize', 16, ...
    'Color', [1 0 0], ...              % will be set green/red dynamically
    'BackgroundColor', [1 1 1], ...
    'Margin', 4, ...
    'HitTest','off');
try, uistack(txtCursor, 'top'); catch, end

% --- LapC hatch overlay (drawn on top of stiffness image) ---
% Use a truecolor image so it does NOT affect the stiffness colormap.
if hasLapC
    hold(axS, 'on');
    hLapHatch = image(axS, uint8(zeros(nRow, nCol, 3))); % black hatch via AlphaData
    set(hLapHatch, ...
        'AlphaData', zeros(nRow, nCol), ...
        'AlphaDataMapping', 'none', ...
        'HitTest', 'off');
    try, hLapHatch.PickableParts = 'none'; catch, end
    hold(axS, 'off');
end

% Hatch overlay for low LapC regions (LapC < lapCutoff)
% Truecolor image so it does NOT affect colormap.
hLapHatch = image(axS, ...
    'XData',[1 nCol], 'YData',[1 nRow], ...
    'CData', uint8(zeros(nRow, nCol, 3)), ...   % black hatch lines (via AlphaData)
    'AlphaData', zeros(nRow, nCol), ...
    'AlphaDataMapping','none', ...
    'HitTest','off');
updateLapCHatch();

try
    hLapHatch.PickableParts = 'none';
catch
end

colormap(axM, gray(256));
colormap(axW, waveCmap);
colormap(axS, stiffCmap);

% Fixed stiffness display range
set(axS, 'CLim', stiffCLim);

% --- Stiffness colorbar (0-8kPa) ---
cbS = colorbar(axS, 'Location', 'eastoutside');
cbS.Label.String = 'kPa';
cbS.Ticks = 0:1:8;
cbS.TickDirection = 'out';
try
    cbS.Layout.Tile = 'east';
catch
end

% --- Magnitude grayscale colorbar (for W/L) ---
% Put it on the far LEFT side of the magnitude axis.
cbM = colorbar(axM, 'Location', 'westoutside');
cbM.Label.String = 'MAG (a.u.)';
cbM.TickDirection = 'out';
try
    set(cbM, 'FontSize', UI_FS, 'FontWeight', UI_FW);
    set(cbM.Label, 'FontSize', UI_FS, 'FontWeight', UI_FW);
catch
end

% Make sure the colorbar is clickable (for WL drag)
try
    cbM.HitTest = 'on';
    cbM.PickableParts = 'all';
    cbM.ButtonDownFcn = @(~,~) onMagColorbarDown();
catch
    % Older MATLAB may not support PickableParts
    try
        cbM.ButtonDownFcn = @(~,~) onMagColorbarDown();
    catch
    end
end

axis(axM,'image'); axis(axW,'image'); axis(axS,'image');
axis(axM,'off'); axis(axW,'off'); axis(axS,'off');

applyClim(axM, cache.climM);
applyClim(axW, cache.climW);
set(axS, 'CLim', stiffCLim);

% Init manual clim from auto
try
    state.manualClimM = get(axM,'CLim');
    state.wlStartCLim = state.manualClimM;
catch
end

% Stored OUTER contour overlay lines (yellow)
hContourM = line(axM, NaN, NaN, 'LineWidth', 1.8, 'Color',[1 1 0], 'HitTest','off');
hContourW = line(axW, NaN, NaN, 'LineWidth', 1.8, 'Color',[1 1 0], 'HitTest','off');
hContourS = line(axS, NaN, NaN, 'LineWidth', 1.8, 'Color',[1 1 0], 'HitTest','off');

% Stored INNER measurement overlay lines (cyan)
hRoiM = line(axM, NaN, NaN, 'LineWidth', 1.8, 'Color',[0 1 1], 'HitTest','off');
hRoiW = line(axW, NaN, NaN, 'LineWidth', 1.8, 'Color',[0 1 1], 'HitTest','off');
hRoiS = line(axS, NaN, NaN, 'LineWidth', 1.8, 'Color',[0 1 1], 'HitTest','off');

% Multi-boundary overlays for INNER ROI (holes/islands)
hRoiBoundM = gobjects(0);
hRoiBoundW = gobjects(0);
hRoiBoundS = gobjects(0);

lastDrawZ = NaN;
lastMaskNNZ = NaN;   % simple cache to avoid redrawing too often

% Controls panel
pnl = uipanel(fig, 'Units','normalized', 'Position',[0 0 1 0.22], 'BorderType','none');

% ===== Zoom overlay panel (covers the tiledlayout area) =====
% Use the tiledlayout position so the zoom occupies the same region as M/W/S.
tlPos = tl.Position;  % [x y w h] normalized

pnlZoom = uipanel(fig, 'Units','normalized', ...
    'Position', tlPos, ...
    'BorderType','none', ...
    'BackgroundColor', 'w', ...
    'Visible','off');

axZ = axes('Parent', pnlZoom, 'Units','normalized', 'Position', [0.02 0.02 0.96 0.96]);
set(axZ, 'YDir','reverse');
set(axZ, 'XLim',[0.5 nCol+0.5], 'YLim',[0.5 nRow+0.5]);
set(axZ, 'XTick',[], 'YTick',[]);

axis(axZ, 'image');                 % enforces equal scaling in x/y
set(axZ, 'DataAspectRatio', [1 1 1]);
set(axZ, 'PlotBoxAspectRatioMode', 'auto');
set(axZ, 'YDir', 'reverse');        % keep image coordinate system consistent
set(axZ, 'XLimMode','manual', 'YLimMode','manual');  % prevent autoscale surprises
set(axZ, 'XLim', [0.5 nCol+0.5], 'YLim', [0.5 nRow+0.5]);

% Create zoom image placeholder (we will swap CData)
hImZ = imagesc(axZ, getSframe(state.t));

% Cache original positions for restoring after zoom
pos_axM = get(axM, 'Position');
pos_axW = get(axW, 'Position');
pos_axS = get(axS, 'Position');
pos_pnl = get(pnl, 'Position');

txt = uicontrol(pnl, 'Style','text', 'Units','normalized', ...
    'Position',[0.01 0.56 0.98 0.42], 'HorizontalAlignment','left', ...
    'BackgroundColor', get(pnl,'BackgroundColor'), 'String','');

% Slice controls
uicontrol(pnl, 'Style','text', 'Units','normalized', 'Position',[0.01 0.31 0.06 0.16], ...
    'String','Slice', 'HorizontalAlignment','left');
sldZ = uicontrol(pnl, 'Style','slider', 'Units','normalized', ...
    'Position',[0.08 0.33 0.30 0.13], 'Min',1,'Max',nZ,'Value',state.z, ...
    'Callback', @onZSliderChanged);
try
    addlistener(sldZ, 'Value', 'PostSet', @(~,~) onZSliderChanged(sldZ, []));
catch
end

edtZ = uicontrol(pnl, 'Style','edit', 'Units','normalized', ...
    'Position',[0.39 0.33 0.06 0.14], 'String',num2str(state.z), ...
    'Callback', @(~,~) setSlice(round(str2double(get(edtZ,'String')))));

% Time controls
uicontrol(pnl, 'Style','text', 'Units','normalized', 'Position',[0.48 0.31 0.06 0.16], ...
    'String','Time', 'HorizontalAlignment','left');

sldT = uicontrol(pnl, 'Style','slider', 'Units','normalized', ...
    'Position',[0.55 0.33 0.30 0.13], 'Min',1,'Max',max(1,nT),'Value',state.t, ...
    'Callback', @onTSliderChanged);

% Make TIME slider interactive while dragging (like slice slider)
tValueListener = [];
try
    tValueListener = addlistener(sldT, 'Value', 'PostSet', @(~,~) onTSliderChanged(sldT, []));
catch
end

edtT = uicontrol(pnl, 'Style','edit', 'Units','normalized', ...
    'Position',[0.86 0.33 0.06 0.14], 'String',num2str(state.t), ...
    'Callback', @(~,~) setTime(round(str2double(get(edtT,'String')))));

% ========== NEW: Vertex count control ==========
uicontrol(pnl, 'Style','text', 'Units','normalized',...
    'Position',[0.93 0.50 0.06 0.16], 'String','# of Vertices', 'HorizontalAlignment','left', 'FontSize', UI_FS-2);

edtVertices = uicontrol(pnl, 'Style','edit', 'Units','normalized', ...
    'Position',[0.93 0.33 0.06 0.14], 'String',num2str(vertexCount), 'Callback', @onVertexCountChanged, 'FontSize', UI_FS);

% Buttons row layout (single row, GIF at far right)
btnY = 0.08;
btnH = 0.18;
gap  = 0.003;
x    = 0.01;  % left margin

btnPlay = uicontrol(pnl, 'Style','togglebutton', 'Units','normalized', ...
    'Position',[x btnY 0.05 btnH], 'String','Play', ...
    'Callback', @(~,~) onPlayToggle());
x = x + 0.05 + gap;

btnDraw = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.08 btnH], 'String','Seed+Auto (d)', ...
    'Callback', @(~,~) onDrawNewROI());
x = x + 0.08 + gap;

% Add freehand bottons for outer contour and inner measurement ROIs
btnFreeRoiO = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.05 btnH], 'String','Freehand Organ', ...
    'Callback', @(~,~) onManualContour());
x = x + 0.05 + gap;

btnfreeRoiI = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.05 btnH], 'String','Freehand MRE', ...
    'Callback', @(~,~) onManualInnerROI());
x = x + 0.05 + gap;

btnAdd = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.07 btnH], 'String','Complex ROI (Include)', ...
    'Callback', @(~,~) onComplexAdd());
x = x + 0.07 + gap;

btnExclude = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.07 btnH], 'String','Complex ROI (Exclude)', ...
    'Callback', @(~,~) onComplexExclude());
x = x + 0.07 + gap;

btnEdit = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.06 btnH], 'String','Edit (e)', ...
    'Callback', @(~,~) onEditCurrentROI());
x = x + 0.06 + gap;

btnNext = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.08 btnH], 'String','NextPend (n)', ...
    'Callback', @(~,~) gotoNextUnprocessed());
x = x + 0.08 + gap;

btnNoOrgan = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.065 btnH], 'String','NoOrgan (a)', ...
    'Callback', @(~,~) onSkipAnatomy());
x = x + 0.065 + gap;

btnSkip = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.065 btnH], 'String','SkipMRE (s)', ...
    'Callback', @(~,~) onSkipSlice());
x = x + 0.065 + gap;

btnClear = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.055 btnH], 'String','Clear (c)', ...
    'Callback', @(~,~) onClearSlice());
x = x + 0.055 + gap;

% ========= Stiffness scale toggle (0-8 / 0-20 kPa) ==========
btnStiffScale = uicontrol(pnl, 'Style','togglebutton', 'Units','normalized', ...
    'Position',[x btnY 0.065 btnH], 'String','0-8 kPa', ...
    'Value', 0, ...
    'Callback', @(~,~) onStiffScaleToggle());
x = x + 0.065 + gap;

% ========= NEW: Export GIF animations ==========
btnGif = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.07 btnH], 'String','Export GIF (g)', ...
    'Callback', @(~,~) onExportGifs());
x = x + 0.07 + gap;

btnFinish = uicontrol(pnl, 'Style','pushbutton', 'Units','normalized', ...
    'Position',[x btnY 0.09 btnH], 'String','Finish & Save', ...
    'Callback', @(~,~) onFinishSave());

% Force font size/bold on all UI controls in the panel
try
    set(findall(pnl, 'Type', 'uicontrol'), 'FontSize', UI_FS, 'FontWeight', UI_FW);
catch
end

% Slider steps
setSliderSteps(sldZ, nZ);
setSliderSteps(sldT, nT);
if nT <= 1
    set(btnPlay,'Enable','off'); set(sldT,'Enable','off'); set(edtT,'Enable','off');
end

% Animation timer
tmr = timer('ExecutionMode','fixedSpacing', 'Period',0.18, 'TimerFcn', @(~,~) onTick());

% Window callbacks
fig.WindowScrollWheelFcn   = @(~,evt) onScroll(evt);
fig.KeyPressFcn            = @(~,evt) onKey(evt);
fig.WindowButtonDownFcn    = @(~,~) onMouseDown();
fig.WindowButtonUpFcn      = @(~,~) onMouseUp();
fig.WindowButtonMotionFcn  = @(~,~) onMouseMove();
fig.CloseRequestFcn        = @(~,~) onClose();

% Initial update
updateAll();
uiwait(fig);

% =================== Nested functions ===================

    function h = awave(m)
        % AWAVE    MRE Displacement Look-Up table
        %   AWAVE(M) returns an M-by-3 matrix containing an "awave" colormap.
        if (nargin < 1)
            m = size(get(gcf,'colormap'),1);
        end

        aw = [ 'ff'; 'ff'; '00'; 'ff'; 'fc'; '00'; 'ff'; 'fa'; '00'; 'ff'; 'f7'; '00';
            'ff'; 'f4'; '00'; 'ff'; 'f2'; '00'; 'ff'; 'ef'; '00'; 'ff'; 'ec'; '00';
            'ff'; 'ea'; '00'; 'ff'; 'e7'; '00'; 'ff'; 'e4'; '00'; 'ff'; 'e1'; '00';
            'ff'; 'df'; '00'; 'ff'; 'dc'; '00'; 'ff'; 'd9'; '00'; 'ff'; 'd7'; '00';
            'ff'; 'd4'; '00'; 'ff'; 'd1'; '00'; 'ff'; 'cf'; '00'; 'ff'; 'cc'; '00';
            'ff'; 'c9'; '00'; 'ff'; 'c7'; '00'; 'ff'; 'c4'; '00'; 'ff'; 'c1'; '00';
            'ff'; 'bf'; '00'; 'ff'; 'bc'; '00'; 'ff'; 'b9'; '00'; 'ff'; 'b7'; '00';
            'ff'; 'b4'; '00'; 'ff'; 'b1'; '00'; 'ff'; 'ae'; '00'; 'ff'; 'ac'; '00';
            'ff'; 'a9'; '00'; 'ff'; 'a6'; '00'; 'ff'; 'a4'; '00'; 'ff'; 'a1'; '00';
            'ff'; '9e'; '00'; 'ff'; '9c'; '00'; 'ff'; '99'; '00'; 'ff'; '96'; '00';
            'ff'; '94'; '00'; 'ff'; '91'; '00'; 'ff'; '8e'; '00'; 'ff'; '8c'; '00';
            'ff'; '89'; '00'; 'ff'; '86'; '00'; 'ff'; '84'; '00'; 'ff'; '81'; '00';
            'ff'; '7e'; '00'; 'ff'; '7b'; '00'; 'ff'; '79'; '00'; 'ff'; '76'; '00';
            'ff'; '73'; '00'; 'ff'; '71'; '00'; 'ff'; '6e'; '00'; 'ff'; '6b'; '00';
            'ff'; '69'; '00'; 'ff'; '66'; '00'; 'ff'; '63'; '00'; 'ff'; '61'; '00';
            'ff'; '5e'; '00'; 'ff'; '5b'; '00'; 'ff'; '59'; '00'; 'ff'; '56'; '00';
            'ff'; '53'; '00'; 'ff'; '51'; '00'; 'ff'; '4e'; '00'; 'ff'; '4b'; '00';
            'ff'; '48'; '00'; 'ff'; '46'; '00'; 'ff'; '43'; '00'; 'ff'; '40'; '00';
            'ff'; '3e'; '00'; 'ff'; '3b'; '00'; 'ff'; '38'; '00'; 'ff'; '36'; '00';
            'ff'; '33'; '00'; 'ff'; '30'; '00'; 'ff'; '2e'; '00'; 'ff'; '2b'; '00';
            'ff'; '28'; '00'; 'ff'; '26'; '00'; 'ff'; '23'; '00'; 'ff'; '20'; '00';
            'ff'; '1e'; '00'; 'ff'; '1b'; '00'; 'ff'; '18'; '00'; 'ff'; '15'; '00';
            'ff'; '13'; '00'; 'ff'; '10'; '00'; 'ff'; '0d'; '00'; 'ff'; '0b'; '00';
            'ff'; '08'; '00'; 'ff'; '05'; '00'; 'ff'; '03'; '00'; 'ff'; '00'; '00';
            'f7'; '00'; '00'; 'ef'; '00'; '00'; 'e7'; '00'; '00'; 'df'; '00'; '00';
            'd7'; '00'; '00'; 'cf'; '00'; '00'; 'c7'; '00'; '00'; 'bf'; '00'; '00';
            'b7'; '00'; '00'; 'af'; '00'; '00'; 'a7'; '00'; '00'; '9f'; '00'; '00';
            '97'; '00'; '00'; '8f'; '00'; '00'; '87'; '00'; '00'; '80'; '00'; '00';
            '78'; '00'; '00'; '70'; '00'; '00'; '68'; '00'; '00'; '60'; '00'; '00';
            '58'; '00'; '00'; '50'; '00'; '00'; '48'; '00'; '00'; '40'; '00'; '00';
            '38'; '00'; '00'; '30'; '00'; '00'; '28'; '00'; '00'; '20'; '00'; '00';
            '18'; '00'; '00'; '10'; '00'; '00'; '08'; '00'; '00'; '00'; '00'; '00';
            '00'; '00'; '00'; '00'; '00'; '08'; '00'; '00'; '10'; '00'; '00'; '18';
            '00'; '00'; '20'; '00'; '00'; '28'; '00'; '00'; '30'; '00'; '00'; '38';
            '00'; '00'; '40'; '00'; '00'; '48'; '00'; '00'; '50'; '00'; '00'; '58';
            '00'; '00'; '60'; '00'; '00'; '68'; '00'; '00'; '70'; '00'; '00'; '78';
            '00'; '00'; '80'; '00'; '00'; '87'; '00'; '00'; '8f'; '00'; '00'; '97';
            '00'; '00'; '9f'; '00'; '00'; 'a7'; '00'; '00'; 'af'; '00'; '00'; 'b7';
            '00'; '00'; 'bf'; '00'; '00'; 'c7'; '00'; '00'; 'cf'; '00'; '00'; 'd7';
            '00'; '00'; 'df'; '00'; '00'; 'e7'; '00'; '00'; 'ef'; '00'; '00'; 'f7';
            '00'; '00'; 'ff'; '00'; '03'; 'ff'; '00'; '05'; 'ff'; '00'; '08'; 'ff';
            '00'; '0b'; 'ff'; '00'; '0d'; 'ff'; '00'; '10'; 'ff'; '00'; '13'; 'ff';
            '00'; '15'; 'ff'; '00'; '18'; 'ff'; '00'; '1b'; 'ff'; '00'; '1e'; 'ff';
            '00'; '20'; 'ff'; '00'; '23'; 'ff'; '00'; '26'; 'ff'; '00'; '28'; 'ff';
            '00'; '2b'; 'ff'; '00'; '2e'; 'ff'; '00'; '30'; 'ff'; '00'; '33'; 'ff';
            '00'; '36'; 'ff'; '00'; '38'; 'ff'; '00'; '3b'; 'ff'; '00'; '3e'; 'ff';
            '00'; '40'; 'ff'; '00'; '43'; 'ff'; '00'; '46'; 'ff'; '00'; '48'; 'ff';
            '00'; '4b'; 'ff'; '00'; '4e'; 'ff'; '00'; '51'; 'ff'; '00'; '53'; 'ff';
            '00'; '56'; 'ff'; '00'; '59'; 'ff'; '00'; '5b'; 'ff'; '00'; '5e'; 'ff';
            '00'; '61'; 'ff'; '00'; '63'; 'ff'; '00'; '66'; 'ff'; '00'; '69'; 'ff';
            '00'; '6b'; 'ff'; '00'; '6e'; 'ff'; '00'; '71'; 'ff'; '00'; '73'; 'ff';
            '00'; '76'; 'ff'; '00'; '79'; 'ff'; '00'; '7b'; 'ff'; '00'; '7e'; 'ff';
            '00'; '81'; 'ff'; '00'; '84'; 'ff'; '00'; '86'; 'ff'; '00'; '89'; 'ff';
            '00'; '8c'; 'ff'; '00'; '8e'; 'ff'; '00'; '91'; 'ff'; '00'; '94'; 'ff';
            '00'; '96'; 'ff'; '00'; '99'; 'ff'; '00'; '9c'; 'ff'; '00'; '9e'; 'ff';
            '00'; 'a1'; 'ff'; '00'; 'a4'; 'ff'; '00'; 'a6'; 'ff'; '00'; 'a9'; 'ff';
            '00'; 'ac'; 'ff'; '00'; 'ae'; 'ff'; '00'; 'b1'; 'ff'; '00'; 'b4'; 'ff';
            '00'; 'b7'; 'ff'; '00'; 'b9'; 'ff'; '00'; 'bc'; 'ff'; '00'; 'bf'; 'ff';
            '00'; 'c1'; 'ff'; '00'; 'c4'; 'ff'; '00'; 'c7'; 'ff'; '00'; 'c9'; 'ff';
            '00'; 'cc'; 'ff'; '00'; 'cf'; 'ff'; '00'; 'd1'; 'ff'; '00'; 'd4'; 'ff';
            '00'; 'd7'; 'ff'; '00'; 'd9'; 'ff'; '00'; 'dc'; 'ff'; '00'; 'df'; 'ff';
            '00'; 'e1'; 'ff'; '00'; 'e4'; 'ff'; '00'; 'e7'; 'ff'; '00'; 'ea'; 'ff';
            '00'; 'ec'; 'ff'; '00'; 'ef'; 'ff'; '00'; 'f2'; 'ff'; '00'; 'f4'; 'ff';
            '00'; 'f7'; 'ff'; '00'; 'fa'; 'ff'; '00'; 'fc'; 'ff'; '00'; 'ff'; 'ff'];

        aw = hex2dec(aw);
        naw = reshape(aw,3,256);
        naw = naw./255;

        r = [naw(1,:)'];
        g = [naw(2,:)'];
        b = [naw(3,:)'];

        h = [r g b];
        h = flipdim(h,1);
        indx = round(linspace(1,256,m));
        h = h(indx,:);
    end

    function h = aaasmo(m)
        % AAASMO    LFE Look-Up table
        %   AAASMO(M) returns an M-by-3 matrix containing an "aaasmo" colormap.
        if (nargin < 1)
            m = size(get(gcf,'colormap'),1);
        end

        aw = [ '00'; '00'; '00'; '22'; '00'; '55'; '24'; '00'; '55'; '26'; '00'; '56';
            '28'; '00'; '56'; '29'; '00'; '57'; '2b'; '00'; '57'; '2d'; '00'; '58';
            '2f'; '00'; '58'; '31'; '00'; '59'; '33'; '00'; '59'; '34'; '00'; '5a';
            '36'; '00'; '5a'; '38'; '00'; '5b'; '3a'; '00'; '5b'; '3c'; '00'; '5b';
            '3e'; '00'; '5c'; '3f'; '00'; '5c'; '41'; '00'; '5d'; '43'; '00'; '5d';
            '45'; '00'; '5e'; '47'; '00'; '5e'; '49'; '00'; '5f'; '4a'; '00'; '5f';
            '4c'; '00'; '60'; '4e'; '00'; '60'; '50'; '00'; '60'; '52'; '00'; '61';
            '54'; '00'; '61'; '55'; '00'; '62'; '57'; '00'; '62'; '59'; '00'; '63';
            '5b'; '00'; '63'; '5d'; '00'; '64'; '5f'; '00'; '64'; '60'; '00'; '65';
            '62'; '00'; '65'; '64'; '00'; '66'; '66'; '00'; '66'; '66'; '00'; '6a';
            '66'; '00'; '6f'; '66'; '00'; '73'; '66'; '00'; '77'; '66'; '00'; '7b';
            '66'; '00'; '80'; '66'; '00'; '84'; '66'; '00'; '88'; '66'; '00'; '8c';
            '66'; '00'; '91'; '66'; '00'; '95'; '66'; '00'; '99'; '5e'; '00'; '9c';
            '56'; '00'; '9e'; '4e'; '00'; 'a1'; '47'; '00'; 'a3'; '3f'; '00'; 'a6';
            '37'; '00'; 'a9'; '2f'; '00'; 'ab'; '27'; '00'; 'ae'; '1f'; '00'; 'b1';
            '18'; '00'; 'b3'; '10'; '00'; 'b6'; '08'; '00'; 'b8'; '00'; '00'; 'bb';
            '00'; '06'; 'c1'; '00'; '0b'; 'c6'; '00'; '11'; 'cc'; '00'; '17'; 'd2';
            '00'; '1c'; 'd7'; '00'; '22'; 'dd'; '00'; '28'; 'e3'; '00'; '2d'; 'e8';
            '00'; '33'; 'ee'; '00'; '39'; 'f4'; '00'; '3e'; 'f9'; '00'; '44'; 'ff';
            '00'; '48'; 'fb'; '00'; '4d'; 'f7'; '00'; '51'; 'f2'; '00'; '55'; 'ee';
            '00'; '59'; 'ea'; '00'; '5e'; 'e6'; '00'; '62'; 'e1'; '00'; '66'; 'dd';
            '00'; '6a'; 'd9'; '00'; '6f'; 'd5'; '00'; '73'; 'd0'; '00'; '77'; 'cc';
            '00'; '7b'; 'c8'; '00'; '7e'; 'c5'; '00'; '82'; 'c1'; '00'; '86'; 'bd';
            '00'; '89'; 'ba'; '00'; '8d'; 'b6'; '00'; '91'; 'b3'; '00'; '94'; 'af';
            '00'; '98'; 'ab'; '00'; '9b'; 'a8'; '00'; '9f'; 'a4'; '00'; 'a3'; 'a0';
            '00'; 'a6'; '9d'; '00'; 'aa'; '99'; '00'; 'aa'; '8c'; '00'; 'aa'; '80';
            '00'; 'aa'; '73'; '00'; 'aa'; '66'; '00'; 'aa'; '59'; '00'; 'aa'; '4d';
            '00'; 'aa'; '40'; '00'; 'aa'; '33'; '00'; 'aa'; '26'; '00'; 'aa'; '1a';
            '00'; 'aa'; '0d'; '00'; 'aa'; '00'; '00'; 'ae'; '00'; '00'; 'b3'; '00';
            '00'; 'b7'; '00'; '00'; 'bb'; '00'; '00'; 'bf'; '00'; '00'; 'c4'; '00';
            '00'; 'c8'; '00'; '00'; 'cc'; '00'; '00'; 'd0'; '00'; '00'; 'd5'; '00';
            '00'; 'd9'; '00'; '00'; 'dd'; '00'; '0a'; 'e0'; '00'; '15'; 'e2'; '00';
            '1f'; 'e5'; '00'; '2a'; 'e7'; '00'; '34'; 'ea'; '00'; '3f'; 'ed'; '00';
            '49'; 'ef'; '00'; '54'; 'f2'; '00'; '5e'; 'f5'; '00'; '69'; 'f7'; '00';
            '73'; 'fa'; '00'; '7e'; 'fc'; '00'; '88'; 'ff'; '00'; '8d'; 'ff'; '00';
            '92'; 'ff'; '00'; '98'; 'ff'; '00'; '9d'; 'ff'; '00'; 'a2'; 'ff'; '00';
            'a7'; 'ff'; '00'; 'ad'; 'ff'; '00'; 'b2'; 'ff'; '00'; 'b7'; 'ff'; '00';
            'bc'; 'ff'; '00'; 'c2'; 'ff'; '00'; 'c7'; 'ff'; '00'; 'cc'; 'ff'; '00';
            'd0'; 'ff'; '00'; 'd5'; 'ff'; '00'; 'd9'; 'ff'; '00'; 'dd'; 'ff'; '00';
            'e1'; 'ff'; '00'; 'e6'; 'ff'; '00'; 'ea'; 'ff'; '00'; 'ee'; 'ff'; '00';
            'f2'; 'ff'; '00'; 'f7'; 'ff'; '00'; 'fb'; 'ff'; '00'; 'ff'; 'ff'; '00';
            'ff'; 'fd'; '00'; 'ff'; 'fb'; '00'; 'ff'; 'f9'; '00'; 'ff'; 'f7'; '00';
            'ff'; 'f5'; '00'; 'ff'; 'f3'; '00'; 'ff'; 'f1'; '00'; 'ff'; 'ef'; '00';
            'ff'; 'ed'; '00'; 'ff'; 'eb'; '00'; 'ff'; 'e9'; '00'; 'ff'; 'e7'; '00';
            'ff'; 'e4'; '00'; 'ff'; 'e2'; '00'; 'ff'; 'e0'; '00'; 'ff'; 'de'; '00';
            'ff'; 'dc'; '00'; 'ff'; 'da'; '00'; 'ff'; 'd8'; '00'; 'ff'; 'd6'; '00';
            'ff'; 'd4'; '00'; 'ff'; 'd2'; '00'; 'ff'; 'd0'; '00'; 'ff'; 'ce'; '00';
            'ff'; 'cc'; '00'; 'ff'; 'c9'; '00'; 'ff'; 'c7'; '00'; 'ff'; 'c4'; '00';
            'ff'; 'c2'; '00'; 'ff'; 'bf'; '00'; 'ff'; 'bc'; '00'; 'ff'; 'ba'; '00';
            'ff'; 'b7'; '00'; 'ff'; 'b4'; '00'; 'ff'; 'b2'; '00'; 'ff'; 'af'; '00';
            'ff'; 'ad'; '00'; 'ff'; 'aa'; '00'; 'ff'; 'a7'; '00'; 'ff'; 'a4'; '00';
            'ff'; 'a2'; '00'; 'ff'; '9f'; '00'; 'ff'; '9c'; '00'; 'ff'; '99'; '00';
            'ff'; '96'; '00'; 'ff'; '93'; '00'; 'ff'; '91'; '00'; 'ff'; '8e'; '00';
            'ff'; '8b'; '00'; 'ff'; '88'; '00'; 'fe'; '80'; '00'; 'fc'; '78'; '00';
            'fb'; '70'; '00'; 'fa'; '69'; '00'; 'f8'; '61'; '00'; 'f7'; '59'; '00';
            'f6'; '51'; '00'; 'f5'; '49'; '00'; 'f3'; '41'; '00'; 'f2'; '3a'; '00';
            'f1'; '32'; '00'; 'ef'; '2a'; '00'; 'ee'; '22'; '00'; 'ef'; '1f'; '00';
            'f1'; '1c'; '00'; 'f2'; '1a'; '00'; 'f4'; '17'; '00'; 'f5'; '14'; '00';
            'f7'; '11'; '00'; 'f8'; '0e'; '00'; 'f9'; '0b'; '00'; 'fb'; '09'; '00';
            'fc'; '06'; '00'; 'fe'; '03'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00';
            'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00';
            'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00';
            'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00';
            'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00'; 'ff'; '00'; '00';];

        aw = hex2dec(aw);
        naw = reshape(aw,3,256);
        naw = naw./255;

        r = [naw(1,:)'];
        g = [naw(2,:)'];
        b = [naw(3,:)'];

        h = [r g b];
        indx = round(linspace(1,256,m));
        h = h(indx,:);
    end

    function onVertexCountChanged(~,~)
        % Callback for vertex count edit box
        val = round(str2double(get(edtVertices,'String')));
        if isnan(val) || val < minVertexCount || val > maxVertexCount
            % Invalid input, reset to current value
            set(edtVertices,'String',num2str(vertexCount));
            beep;
            fprintf('Vertex count must be between %d and %d\
', minVertexCount, maxVertexCount);
            return;
        end
        vertexCount = val;
        fprintf('Vertex count set to %d\
', vertexCount);
        updateStatus();  % Update display to show new value
    end

    function seeIfPause()
        % Pause animation while user is drawing/editing ROIs (prevents frame updates fighting ROI tools)
        if state.isPlaying
            try
                set(btnPlay,'Value',0);
            catch
            end
            onPlayToggle();
        end
    end

    function pos2 = decimatePolyline(pos, maxPts)
        % Simple vertex decimation (keeps order, keeps shape reasonably well)
        if nargin < 2, maxPts = 150; end
        n = size(pos,1);
        if n <= maxPts
            pos2 = pos;
            return;
        end
        idx = round(linspace(1, n, maxPts));
        idx = unique(idx);          % safety
        pos2 = pos(idx, :);
    end

    function setupAx(ax)
        set(ax, 'YDir','reverse');
        set(ax, 'XLim',[0.5 nCol+0.5], 'YLim',[0.5 nRow+0.5]);
    end

    function setSliderSteps(sl, n)
        if n <= 1, sl.SliderStep = [1 1]; return; end
        sl.SliderStep = [1/(n-1) min(10/(n-1),1)];
    end

    function onScroll(evt)
        setSlice(state.z + evt.VerticalScrollCount);
    end

    function onKey(evt)
        % ---- Hotkeys for erosion: + / - (min = 3) ----
        % --- FIRST: handle +/- using evt.Character (works for main keyboard + -) ---
        if isfield(evt,'Character') && ~isempty(evt.Character)
            if strcmp(evt.Character, '+')
                changeErodePx(+1);
                return;
            elseif strcmp(evt.Character, '-')
                changeErodePx(-1);
                return;
            end
        end

        % --- ALSO handle numpad keys for +/- erosion size ---
        switch lower(evt.Key)

            case 'add'       % numpad +
                changeErodePx(+1);
                return;

            case 'subtract'  % numpad -
                changeErodePx(-1);
                return;

                % --- Other hotkeys below ---

            case {'uparrow','pageup'}
                setSlice(state.z - 1);
            case {'downarrow','pagedown'}
                setSlice(state.z + 1);

            case 'space'
                if strcmp(get(btnPlay,'Enable'),'on')
                    set(btnPlay,'Value', ~get(btnPlay,'Value'));
                    onPlayToggle();
                end

            case 'z'
                toggleZoom();

            case 'd'
                onDrawNewROI();

            case 'x'
                onComplexExclude();

            case 'i'
                onComplexAdd();

                % Outer contour (manual): click Magnitude (left) \u2192 press f \u2192 draw \u2192 double-click to finish
                % Inner ROI (manual): click Wave (middle) \u2192 press f \u2192 draw \u2192 double-click to finish
                % This creates/starts the INNER ROI (meas stage). Then you can adjust/commit as usual.
            case 'f'
                if ~isempty(lastClickedAx) && isequal(lastClickedAx, axW)
                    onManualInnerROI();
                else
                    onManualContour();
                end

            case 'v'
                onCopyPrevROI();
            case 'e'
                onEditCurrentROI();
                % case 'r'  % (removed) use +/- to change erosion
            case 'n'
                gotoNextUnprocessed();
            case 'b'
                gotoPrevUnprocessed();

                % Two skip types:
                %   a : anatomy skip (no spleen/organ)
                %   s/m : MRE skip (technical failure / unreliable stiffness)
            case 'a'
                onSkipAnatomy(); % no anatomy for organ, skip contour ROI drawing
                onSkipSlice(); % no anatomy for organ, directly means no valid MRE either
            case {'s'}
                onSkipSlice(); % no valid MRE measurement, either due to no anatomy or technical failure
            case 'c'
                onClearSlice();

            case 'g'
                onExportGifs();

            case 'escape'
                if isLiveRoiActive()
                    cancelLiveROI();
                else
                    onClose();
                end
        end
    end

    function changeErodePx(delta)
        old = erodePx;
        erodePx = max(minErodePx, erodePx + delta);

        if erodePx ~= old
            % show updated value immediately
            updateStatus();

            % OPTIONAL: if you are currently editing INNER ROI,
            % regenerate it from the stored contour using the new erosion.
            if strcmp(liveStage,'meas') && any(roiMaskContour(:,:,state.z),'all') && isLiveRoiActive()
                innerMask = makeInnerMaskFromContour(state.z, erodePx);
                posInner  = maskToPolygon(innerMask);
                if ~isempty(posInner)
                    hLiveRoi.Position = posInner;   % update editable ROI
                    syncLiveStage(posInner);         % update overlays on M/W/S
                end
            end
        end
    end

% --- Magnitude colorbar drag (window/level) ---
    function onMagColorbarDown()
        if state.seedToolActive
            return;
        end

        % Right-click resets to auto
        if strcmpi(get(fig,'SelectionType'), 'alt')
            state.useManualClimM = false;
            updateFramesOnly();
            updateStatus();
            return;
        end

        state.isWLDragging = true;
        state.wlStartPt = get(fig,'CurrentPoint');
        try
            state.wlStartCLim = get(axM,'CLim');
        catch
            state.wlStartCLim = cache.climM;
        end
        state.useManualClimM = true;
        state.manualClimM = state.wlStartCLim;

        try
            set(fig,'Pointer','fleur');
        catch
        end
    end

    function onMouseUp()
        if state.isWLDragging
            state.isWLDragging = false;
            try
                set(fig,'Pointer','arrow');
            catch
            end
            updateStatus();
        end
    end

    function onMouseMove()
        % 1) If dragging MAG colorbar, update W/L
        if state.isWLDragging
            cp = get(fig,'CurrentPoint');
            dx = cp(1) - state.wlStartPt(1);
            dy = cp(2) - state.wlStartPt(2);

            clim0 = state.wlStartCLim;
            c0 = mean(clim0);
            w0 = diff(clim0);
            if ~isfinite(w0) || w0 <= 0
                w0 = 1;
            end

            % Sensitivity (tweak if you want faster/slower)
            % Horizontal drag: level
            c = c0 + dx * (w0/300);
            % Vertical drag: window (dy>0 widens; dy<0 narrows)
            w = w0 * exp(dy/300);
            w = max(w, eps);

            clim = [c - w/2, c + w/2];
            state.manualClimM = clim;
            set(axM,'CLim',clim);
            return;
        end

        % 2) Otherwise show stiffness under mouse on axS
        h = hittest(fig);
        if isempty(h)
            return;
        end

        % Ignore UI controls
        try
            if ishghandle(h) && strcmpi(get(h,'Type'), 'uicontrol')
                return;
            end
        catch
        end

        ax = ancestor(h, 'axes');
        if isempty(ax) || ax ~= axS
            txtCursor.String = '';
            return;
        end

        cp = axS.CurrentPoint;
        x = round(cp(1,1));
        y = round(cp(1,2));

        if x < 1 || x > nCol || y < 1 || y > nRow
            txtCursor.String = '';
            return;
        end

        val = cache.S(y, x);

        % --- Confidence (LapC) at cursor ---
        conf = NaN;
        if hasLapC && ~isempty(cache.LapC) && isequal(size(cache.LapC), [nRow nCol])
            conf = cache.LapC(y, x);
        end

        % Decide color based on confidence cutoff (GREEN if >= cutoff, else RED)
        if isfinite(conf) && (conf >= lapCutoff)
            txtCursor.Color = [0 0.6 0];   % green
        else
            txtCursor.Color = [1 0 0];     % red
        end

        % Build message
        if ~isfinite(val)
            if isfinite(conf)
                txtCursor.String = sprintf('Stiffness = NaN kPa,  Conf = %.3f  (cutoff %.2f)', conf, lapCutoff);
            else
                txtCursor.String = sprintf('Stiffness = NaN kPa,  Conf = N/A  (cutoff %.2f)', lapCutoff);
            end
        else
            if isfinite(conf)
                txtCursor.String = sprintf('Stiffness = %.3f kPa,  Conf = %.3f  (cutoff %.2f)', val, conf, lapCutoff);
            else
                txtCursor.String = sprintf('Stiffness = %.3f kPa,  Conf = N/A  (cutoff %.2f)', val, lapCutoff);
            end
        end

    end

    function onMouseDown()
        % Unified mouse handler for LIVE ROI editing on the stiffness panel (axS):
        %   - RIGHT click (SelectionType='alt')  : erase nearest vertex (no popup menu)
        %   - DOUBLE click (SelectionType='open'): commit ROI to the current slice

        h = hittest(fig);
        if isempty(h) || ~ishghandle(h)
            return;
        end

        % Ignore clicks on UI controls (sliders/buttons/etc.)
        try
            if strcmpi(get(h,'Type'), 'uicontrol')
                return;
            end
        catch
        end

        clickedAx = ancestor(h, 'axes');

        if ~isempty(clickedAx)
            lastClickedAx = clickedAx;
        end

        if isempty(clickedAx) || clickedAx ~= axS
            return;
        end

        if ~isLiveRoiActive()
            return;
        end

        sel = get(fig,'SelectionType');

        % ---- RIGHT CLICK: erase nearest vertex ----
        if strcmpi(sel, 'alt')
            eraseNearestVertexAtCursor();
            return;
        end

        % ---- DOUBLE CLICK: commit ROI ----
        if strcmpi(sel, 'open')
            commitLiveROI();
            return;
        end
    end

    function eraseNearestVertexAtCursor()
        % Remove the vertex closest to the current cursor position on axS.
        % Guardrails:
        %   - Only works while a LIVE ROI exists
        %   - Keeps at least 3 vertices
        %   - Requires the cursor to be within ERASE_RADIUS pixels of a vertex

        if ~isLiveRoiActive()
            return;
        end

        pos = hLiveRoi.Position; % Nx2 [x y]
        if size(pos,1) <= 3
            beep;
            return;
        end

        cp = axS.CurrentPoint;
        x0 = cp(1,1);
        y0 = cp(1,2);

        d = hypot(pos(:,1) - x0, pos(:,2) - y0);
        [dMin, idx] = min(d);

        ERASE_RADIUS = 25;  % pixels; increase if you want a larger eraser radius
        if ~isfinite(dMin) || dMin > ERASE_RADIUS
            beep;
            return;
        end

        % Delete that vertex
        pos(idx,:) = [];

        % Apply + keep overlays synced
        try
            hLiveRoi.Position = pos;
        catch
            beep;
            return;
        end

        % Our overlays on M/W/S are driven by liveStage
        syncLiveStage(pos);

        drawnow limitrate;
    end

    function onPlayToggle()
        if get(btnPlay,'Value')
            state.isPlaying = true;
            set(btnPlay,'String','Pause');
            if strcmp(tmr.Running,'off'), start(tmr); end
        else
            state.isPlaying = false;
            set(btnPlay,'String','Play');
            if strcmp(tmr.Running,'on'), stop(tmr); end
        end
    end

    function onTick()
        if nT <= 1, return; end
        state.t = state.t + 1;
        if state.t > nT, state.t = 1; end
        isUpdatingT = true;
        if abs(get(sldT,'Value') - state.t) > 1e-6
            set(sldT,'Value',state.t);
        end
        set(edtT,'String',num2str(state.t));
        isUpdatingT = false;
        updateFramesOnly();
    end

    function setTime(t)
        if nT <= 1
            state.t = 1;
            return;
        end
        t = max(1, min(nT, round(t)));
        state.t = t;
        isUpdatingT = true;
        if abs(get(sldT,'Value') - state.t) > 1e-6
            set(sldT,'Value',state.t);
        end
        set(edtT,'String',num2str(state.t));
        isUpdatingT = false;
        updateFramesOnly();
    end

    function setSlice(z)
        if isnan(z), return; end
        z = max(1, min(nZ, round(z)));

        if isLiveRoiActive()
            cancelLiveROI();
        end

        if z == state.z
            updateAll();
            return;
        end

        state.z = z;

        if abs(sldZ.Value - state.z) > 1e-6
            sldZ.Value = state.z;
        end
        edtZ.String = num2str(state.z);

        loadSlice(state.z);
        updateAll();
        drawnow limitrate;
    end

    function loadSlice(z)

        LapCsl = [];   % ALWAYS define, so it exists even if LapC is missing

        if cache.z == z, return; end

        if useMatfile
            Msl = squeeze(mobj.M(:,:,z,:));
            Wsl = squeeze(mobj.W(:,:,z,:));
            if ~isS4D
                Ssl = double(mobj.S(:,:,z));
                if hasLapC
                    LapCsl = double(mobj.LapC(:,:,z));
                else
                    LapCsl = [];
                end
            else
                tmpS = squeeze(mobj.S(:,:,z,:));
                Ssl = mean(double(tmpS), 3, 'omitnan');
                if hasLapC
                    LapCsl = double(mobj.LapC(:,:,z));
                else
                    LapCsl = [];
                end
            end
        else
            Msl = squeeze(M(:,:,z,:));
            Wsl = squeeze(W(:,:,z,:));

            if ~isS4D
                Ssl = double(S(:,:,z));
            else
                tmpS = squeeze(S(:,:,z,:));
                Ssl = mean(double(tmpS), 3, 'omitnan');
            end

            % ---- ADD THIS: LapC slice loading for non-matfile mode ----
            if hasLapC && ~isempty(LapC)
                if ndims(LapC) == 4
                    tmpL = squeeze(LapC(:,:,z,:));
                    LapCsl = mean(double(tmpL), 3, 'omitnan');
                else
                    LapCsl = double(LapC(:,:,z));
                end
            else
                LapCsl = [];
            end
        end

        if ndims(Msl) == 2, Msl = reshape(Msl, nRow, nCol, 1); end
        if ndims(Wsl) == 2, Wsl = reshape(Wsl, nRow, nCol, 1); end

        % Synchronize M and W to have same time dimension (use max)
        nT_slice_M = size(Msl, 3);
        nT_slice_W = size(Wsl, 3);

        if nT_slice_M < nT_slice_W
            % Interpolate M to match W (e.g., 3 \u2192 8 frames)
            fprintf('  Slice %d: Interpolating M from %d to %d frames to match W\
', ...
                z, nT_slice_M, nT_slice_W);
            Msl = interpolateTimeDim(Msl, nT_slice_W);
        elseif nT_slice_W < nT_slice_M
            % Interpolate W to match M (unlikely but handle it)
            fprintf('  Slice %d: Interpolating W from %d to %d frames to match M\
', ...
                z, nT_slice_W, nT_slice_M);

            % For wave data, use complex reconstruction if possible
            if nT_slice_M == nT_slice_W
                waveComplex = Msl .* exp(1i * Wsl);
                waveComplexInterp = interpolateTimeDim(waveComplex, nT_slice_M);
                Wsl = angle(waveComplexInterp);
            else
                Wsl = interpolateTimeDim(Wsl, nT_slice_M);
            end
        end

        cache.M = double(Msl);
        cache.W = double(Wsl);
        cache.S = double(Ssl);
        cache.LapC = LapCsl;

        cache.z = z;

        cache.climM = robustClim(cache.M, 1, 99);

        Wdisp = realIfComplex(cache.W);
        wlim = robustClim(Wdisp, 1, 99);
        lim = max(abs(wlim));
        cache.climW = [-lim lim];

        function dataOut = interpolateTimeDim(dataIn, nTarget)
            % FFT-based temporal interpolation for M/W synchronization
            % dataIn: [nRow x nCol x nOrig] (real or complex)
            % Returns: [nRow x nCol x nTarget]

            [nR, nC, nOrig] = size(dataIn);

            if nTarget <= nOrig
                dataOut = dataIn;
                return;
            end

            % FFT along time dimension
            F = fft(dataIn, [], 3);

            % Zero-pad in frequency domain
            nPad = nTarget - nOrig;
            halfOrig = ceil(nOrig / 2);

            lowFreq = F(:, :, 1:halfOrig);
            highFreq = F(:, :, halfOrig+1:end);
            zeroPad = zeros(nR, nC, nPad);

            F_padded = cat(3, lowFreq, zeroPad, highFreq);
            F_padded = F_padded * (nTarget / nOrig);  % Preserve energy

            % Inverse FFT
            dataOut = ifft(F_padded, [], 3);

            % Keep real if input was real
            if isreal(dataIn)
                dataOut = real(dataOut);
            end
        end
    end

    function onZSliderChanged(src, ~)
        z = round(src.Value);
        setSlice(z);
    end

    function onTSliderChanged(src, ~)
        % Interactive TIME slider while dragging + on release
        if isUpdatingT
            return;
        end
        t = round(get(src,'Value'));
        setTime(t);
    end

    function frame = getMframe(t)
        t = max(1, min(size(cache.M,3), t));
        frame = cache.M(:,:,t);
    end

    function frame = getWframe(t)
        t = max(1, min(size(cache.W,3), t));
        frame = realIfComplex(cache.W(:,:,t));
    end

    function frame = getSframe(~)
        frame = cache.S;
    end

    function pickZoomTarget()
        % If actively drawing: pick the relevant view
        if isLiveRoiActive()
            if strcmp(liveStage,'contour')
                zoomTarget = 'M';   % outer contour work
            else
                zoomTarget = 'S';   % inner/meas work
            end
            return;
        end

        % Otherwise choose axis under mouse if possible
        try
            h = hittest(fig);
            ax = ancestor(h,'axes');
            if isequal(ax, axM), zoomTarget = 'M'; return; end
            if isequal(ax, axW), zoomTarget = 'W'; return; end
            if isequal(ax, axS), zoomTarget = 'S'; return; end
        catch
        end

        zoomTarget = 'S';
    end

    function refreshZoom()
        if ~isZoom || isempty(axZ) || ~isgraphics(axZ)
            return;
        end

        switch zoomTarget
            case 'M'
                set(hImZ, 'CData', getMframe(state.t));
                try, set(axZ,'CLim', get(axM,'CLim')); end
                try, colormap(axZ, colormap(axM)); end
            case 'W'
                set(hImZ, 'CData', getWframe(state.t));
                try, set(axZ,'CLim', get(axW,'CLim')); end
                try, colormap(axZ, colormap(axW)); end

            otherwise % 'S'
                set(hImZ, 'CData', getSframe(state.t));
                try, set(axZ,'CLim', get(axS,'CLim')); end
                try, colormap(axZ, colormap(axS)); end
        end

        % ---- Draw OUTER + INNER ROI boundaries on zoom ----
        % Outer contour mask (yellow)
        if exist('roiMaskContour','var') && ~isempty(roiMaskContour)
            hContourBoundZ = drawMaskBoundaries(axZ, hContourBoundZ, roiMaskContour(:,:,state.z), [1 1 0]);
        end

        % Inner ROI mask (cyan) - includes holes/islands after complex add/exclude
        hRoiBoundZ = drawMaskBoundaries(axZ, hRoiBoundZ, roiMask(:,:,state.z), [0 1 1]);

        try
            title(axZ, sprintf('ZOOM (%s)  z=%d/%d  t=%d/%d   [press 4 to exit]', zoomTarget, state.z, nZ, state.t, max(1,nT)));
        catch
        end

        drawnow limitrate;

        axis(axZ, 'image');
        set(axZ, 'DataAspectRatio', [1 1 1]);
        set(axZ, 'XLim', [0.5 nCol+0.5], 'YLim', [0.5 nRow+0.5]);

    end

    function toggleZoom()
        if ~isZoom
            pickZoomTarget();
            set(pnlZoom,'Visible','on');
            isZoom = true;

            % If a live ROI is active, recreate it on the zoom axes so you draw/edit on the big view
            if isLiveRoiActive()
                pos   = hLiveRoi.Position;
                stage = liveStage;
                cancelLiveROI();                 % deletes old ROI object on axS
                startLiveROI(pos, stage);        % will draw on axZ (we modify startLiveROI below)
            end

            refreshZoom();
        else
            set(pnlZoom,'Visible','off');
            isZoom = false;
            % After closing zoom, overlays are shown in the normal 3 views
            try, delete(hContourBoundZ(ishghandle(hContourBoundZ))); catch, end
            try, delete(hRoiBoundZ(ishghandle(hRoiBoundZ))); catch, end
            hContourBoundZ = gobjects(0);
            hRoiBoundZ     = gobjects(0);
            updateAll();
        end
    end


    function updateAll()
        updateFramesOnly();
        updateOverlay();
        updateStatus();
        if isZoom
            refreshZoom();
        end
    end

    function updateFramesOnly()
        set(hImM,'CData', getMframe(state.t));
        set(hImW,'CData', getWframe(state.t));
        set(hImS,'CData', getSframe(state.t));
        updateLapCHatch();

        % Magnitude clim: auto or manual
        if state.useManualClimM
            try
                set(axM, 'CLim', state.manualClimM);
            catch
            end
        else
            applyClim(axM, cache.climM);
            try
                state.manualClimM = get(axM,'CLim');
            catch
            end
        end

        applyClim(axW, cache.climW);
        set(axS, 'CLim', stiffCLim);

        title(axM, sprintf('M (Magnitude)  z=%d/%d  t=%d/%d', state.z, nZ, state.t, max(1,nT)));
        title(axW, sprintf('W (Waves)      z=%d/%d  t=%d/%d', state.z, nZ, state.t, max(1,nT)));
        title(axS, sprintf('S (Stiffness)  z=%d/%d', state.z, nZ));

        % Enforce title font (titles get recreated)
        try
            set(get(axM,'Title'), 'FontSize', UI_FS, 'FontWeight', UI_FW);
            set(get(axW,'Title'), 'FontSize', UI_FS, 'FontWeight', UI_FW);
            set(get(axS,'Title'), 'FontSize', UI_FS, 'FontWeight', UI_FW);
        catch
        end

        drawnow limitrate;
        if isZoom
            refreshZoom();
        end

    end

    function updateLapCHatch()
        if ~hasLapC || isempty(hLapHatch) || ~isgraphics(hLapHatch)
            return;
        end
        if isempty(cache.LapC) || ~isequal(size(cache.LapC), [nRow nCol])
            set(hLapHatch, 'AlphaData', zeros(nRow, nCol));
            return;
        end
        bad = ~(isfinite(cache.LapC) & (cache.LapC >= lapCutoff));
        A = lapHatchAlpha * double(bad & lapPattern);  % hatch lines only in bad region
        set(hLapHatch, 'AlphaData', A);
    end

    function updateOverlay()
        if isLiveRoiActive()
            return;
        end

        % OUTER contour
        posC = roiVerticesContour{state.z};
        if isempty(posC)
            set(hContourM,'XData',NaN,'YData',NaN);
            set(hContourW,'XData',NaN,'YData',NaN);
            set(hContourS,'XData',NaN,'YData',NaN);
        else
            syncOverlayToPos_specific(posC, hContourM, hContourW, hContourS);
        end

        % INNER measurement: draw from MASK so holes/islands show correctly
        % Hide the single-outline ROI lines (we will use multi-boundary)
        set(hRoiM,'XData',NaN,'YData',NaN);
        set(hRoiW,'XData',NaN,'YData',NaN);
        set(hRoiS,'XData',NaN,'YData',NaN);

        maskMeas = roiMask(:,:,state.z);
        nn = nnz(maskMeas);

        % Redraw boundaries only when needed (slice change or mask changed)
        if state.z ~= lastDrawZ || nn ~= lastMaskNNZ
            hRoiBoundM = drawMaskBoundaries(axM, hRoiBoundM, maskMeas, [0 1 1]);  % cyan
            hRoiBoundW = drawMaskBoundaries(axW, hRoiBoundW, maskMeas, [0 1 1]);
            hRoiBoundS = drawMaskBoundaries(axS, hRoiBoundS, maskMeas, [0 1 1]);

            lastDrawZ = state.z;
            lastMaskNNZ = nn;
        end

        if isZoom
            refreshZoom();
        end
    end

    function syncOverlayToPos_specific(pos, h1, h2, h3)
        x = pos(:,1); y = pos(:,2);
        x = [x; x(1)]; y = [y; y(1)];
        set(h1,'XData',x,'YData',y);
        set(h2,'XData',x,'YData',y);
        set(h3,'XData',x,'YData',y);
    end

    function setRoiBoundaryVisible(tf)
        % tf = true/false
        try
            if ~isempty(hRoiBoundM)
                set(hRoiBoundM(isgraphics(hRoiBoundM)), 'Visible', onOff(tf));
            end
            if ~isempty(hRoiBoundW)
                set(hRoiBoundW(isgraphics(hRoiBoundW)), 'Visible', onOff(tf));
            end
            if ~isempty(hRoiBoundS)
                set(hRoiBoundS(isgraphics(hRoiBoundS)), 'Visible', onOff(tf));
            end
        catch
            % ignore (graphics handles may not exist yet)
        end
    end

    function s = onOff(tf)
        if tf, s = 'on'; else, s = 'off'; end
    end


    function updateStatus()
        % --- Per-slice status is now two-layer ---
        %   Contour (anatomy): sliceStateContour
        %   Measurement (MRE): sliceState

        % Contour counts
        nC_done = nnz(sliceStateContour == 1);
        nC_skip = nnz(sliceStateContour == -1);
        nC_pend = nnz(sliceStateContour == 0);

        % MRE counts
        nM_done = nnz(sliceState == 1);
        nM_skip = nnz(sliceState == -1);
        % "Pending MRE" means contour exists but MRE decision not done yet
        nM_pend = nnz(sliceStateContour == 1 & sliceState == 0);

        % Current slice tag
        stC = sliceStateContour(state.z);
        if stC == 1
            tagC = 'CONTOUR DONE';
        elseif stC == -1
            tagC = 'NO ORGAN (ANAT SKIP)';
        else
            tagC = 'PENDING CONTOUR';
        end

        stM = sliceState(state.z);
        if stC == -1
            tagM = 'MRE: N/A';
        elseif stM == 1
            tagM = 'MRE: MEAS ROI DONE';
        elseif stM == -1
            tagM = 'MRE: TECH SKIP';
        else
            if stC == 1
                tagM = 'MRE: PENDING';
            else
                tagM = 'MRE: WAIT CONTOUR';
            end
        end

        tag = sprintf('%s | %s', tagC, tagM);

        liveMsg = "";
        if isLiveRoiActive()
            if strcmp(liveStage,'contour')
                liveMsg = " | LIVE OUTER: drag vertices, DOUBLE-CLICK on S to commit";
            elseif strcmp(liveStage,'meas')
                liveMsg = " | LIVE INNER: drag vertices, DOUBLE-CLICK on S to commit";
            else
                liveMsg = " | LIVE ROI: drag vertices, DOUBLE-CLICK on S to commit";
            end
        else
            liveMsg = "";
        end

        % Magnitude W/L readout
        climM = cache.climM;
        if state.useManualClimM
            climM = state.manualClimM;
            wlTag = 'MANUAL';
        else
            wlTag = 'AUTO';
        end

        if exist('hasUnsavedChanges','var') && hasUnsavedChanges
            unsavedMsg = '  *** UNSAVED CHANGES ***';
        else
            unsavedMsg = '';
        end

        set(txt,'String',sprintf([ ...
            'Workflow: Draw OUTER organ contour on M (yellow) then INNER roi on W/S (cyan)\
' ...
            'Hotkeys: z=zoom | d=seed | f=freehand | i=include | x=exclude | v=copyPrev | e=edit | n=next pending | a=skip anatomy | s=skip MRE | c=clear | space=play/pause | ESC=cancel/abort\
' ...
            'Organ: %s | %s/%s | z=%d/%d (%s)%s%s|| Contour: done=%d | No-organ=%d | Pending=%d  ||  MRE: done=%d | TechSkip=%d\
' ...
            'MAG W/L (%s): [%.3g  %.3g] Polygon vertices = %d (range: %d-%d). Edit box in bottom-right to change. Inner ROI erosion = %d pixels (min %d). Use + / - to adjust.\
' ...
            'Finish outputs: %s\
'], ...
            upper(organ), meta.ExamId, meta.SeriesId, state.z, nZ, tag, liveMsg, unsavedMsg, ...
            nC_done, nC_skip, nC_pend, nM_done, nM_skip, ...
            wlTag, climM(1), climM(2),vertexCount, minVertexCount, maxVertexCount, erodePx, minErodePx, ...
            roiPathMeas));

    end

% ---------- ROI actions ----------
    function onDrawNewROI()
        if isLiveRoiActive()
            cancelLiveROI();
        end

        % Instruction: draw seed circle in magnitude panel
        set(txt,'String',sprintf([ ...
            'Step 1: Draw a SEED CIRCLE inside %s on MAG panel (slice z=%d).\
' ...
            'Tip: First drag the MAG colorbar to adjust W/L if needed.\
' ...
            'Double-click the circle to accept.'], upper(organ), state.z));
        drawnow;

        state.seedToolActive = true;

        % Prefer drawcircle (R2018b+ with Image Processing Toolbox). Fallback to drawellipse.
        hSeed = [];
        try
            hSeed = drawcircle(axM, 'LineWidth', 1.5, 'Color', [1 0 0]);
        catch
            try
                hSeed = drawellipse(axM, 'LineWidth', 1.5, 'Color', [1 0 0]);
            catch
                state.seedToolActive = false;
                warndlg('drawcircle/drawellipse not available. Please update MATLAB or install Image Processing Toolbox.', 'Seed Tool');
                updateAll();
                return;
            end
        end

        if isempty(hSeed) || ~isvalid(hSeed)
            state.seedToolActive = false;
            updateAll();
            return;
        end

        % Wait for user to finalize the seed ROI
        try
            wait(hSeed);
        catch
            uiwait(msgbox('Adjust the seed circle/ellipse, then click OK to continue.', 'Seed ROI', 'modal'));
        end

        % Build time-averaged magnitude image for segmentation (NOT stiffness)
        I = mean(cache.M, 3);
        I = mat2gray(I);

        % Convert seed ROI to a binary mask
        seedMask = false(nRow, nCol);
        try
            if isprop(hSeed,'Center') && isprop(hSeed,'Radius')
                cx = hSeed.Center(1);
                cy = hSeed.Center(2);
                rr = hSeed.Radius;
                seedMask = circleMaskFromGeom(cx, cy, rr, nRow, nCol);
            elseif isprop(hSeed,'Center') && isprop(hSeed,'SemiAxes')
                % ellipse fallback: approximate by mean radius
                cx = hSeed.Center(1);
                cy = hSeed.Center(2);
                rr = mean(hSeed.SemiAxes);
                seedMask = circleMaskFromGeom(cx, cy, rr, nRow, nCol);
            else
                % final fallback
                seedMask = createMask(hSeed, hImM);
            end
        catch
            % as a last resort, try createMask without specifying image
            try
                seedMask = createMask(hSeed);
            catch
            end
        end

        try
            delete(hSeed);
        catch
        end

        state.seedToolActive = false;

        if ~any(seedMask(:))
            warndlg('Seed mask is empty. Please try drawing a larger seed circle.', 'Seed Tool');
            updateAll();
            return;
        end

        % Auto segment using intensity distribution from the seed circle
        mask = autoMaskFromSeedCircle(I, seedMask);

        if ~any(mask(:))
            warndlg('Auto contour failed on this slice. Try a larger seed circle, adjust W/L, or skip the slice.', 'Auto contour');
            updateAll();
            return;
        end

        posOuter = maskToPolygon(mask);
        if isempty(posOuter)
            warndlg('Could not extract polygon boundary from mask. Try another seed circle.', 'Auto contour');
            updateAll();
            return;
        end

        % Start OUTER live ROI (editable). Double-click on elastogram (S) to commit.
        startLiveROI(posOuter, 'contour');
        updateStatus();
    end

    function onManualContour()
        seeIfPause();

        % Don't allow starting manual contour while a live ROI is active
        if isLiveRoiActive()
            beep;
            return;
        end

        % Instruction for user
        try
            set(txt,'String',sprintf([ ...
                'FREEHAND OUTER CONTOUR (Slice z=%d)\
' ...
                'Draw on magnitude panel (far left image). release to finish.\
' ...
                'Then adjust on elastogram panel (far right image) and double-click on elastogram to commit.' ], state.z));
            drawnow;
        catch
        end

        % Freehand draw on Magnitude axis
        hFH = [];
        if exist('drawfreehand','file') == 2
            hFH = drawfreehand(axM, 'LineWidth', 1.8);
        else
            % Fallback if drawfreehand is unavailable
            hFH = drawpolygon(axM, 'LineWidth', 1.8);
        end

        if isempty(hFH) || ~isvalid(hFH)
            updateAll();
            return;
        end

        posOuter = hFH.Position;
        delete(hFH);

        if isempty(posOuter) || size(posOuter,1) < 3
            updateAll();
            return;
        end

        % Reduce vertex count to make editing manageable
        posOuter = decimatePolyline(posOuter, vertexCount);   % Uses adjustable vertex count min=30, max=300

        % Start your existing contour editing/commit flow on S
        startLiveROI(posOuter, 'contour');
        updateStatus();
    end

    function onManualInnerROI()
        % Manual freehand INNER ROI (measurement ROI) drawn on the W (wave) panel.
        seeIfPause();

        % Inner ROI only makes sense after an outer contour exists for this slice
        if isempty(roiVerticesContour{state.z})
            beep;
            fprintf(2,'No outer contour on this slice. Draw OUTER contour first (d or f on M panel).\
');
            updateStatus();
            return;
        end

        cancelLiveROI();

        % fprintf('Manual INNER ROI: draw on W panel (double-click to finish).\
');
        try
            hFH = drawfreehand(axW,'Color',[1 1 0],'LineWidth',1.5);
            pos = hFH.Position;
            delete(hFH);
        catch
            updateStatus();
            return;
        end

        if isempty(pos) || size(pos,1) < 3
            updateStatus();
            return;
        end

        pos = decimatePolyline(pos, vertexCount);
        startLiveROI(pos, 'meas');
        updateStatus();
    end

    function onCopyPrevROI()
        % Copy previous INNER (measurement) ROI
        zPrev = findPrevRoiSlice(state.z);
        if isempty(zPrev)
            beep;
            return;
        end
        posPrev = roiVertices{zPrev};
        if isempty(posPrev)
            beep;
            return;
        end
        startLiveROI(posPrev, 'meas');
    end

    function onEditCurrentROI()
        pos = roiVertices{state.z};
        if isempty(pos)
            beep;
            return;
        end
        startLiveROI(pos, 'meas');
    end

    function onComplexAdd()
        % Add a freehand region into INNER ROI on the current slice (union).
        if ~any(roiMask(:,:,state.z), 'all')
            warndlg('No INNER ROI on this slice yet. Create/confirm INNER ROI first, then use Add/Exclude.', 'Complex ROI');
            return;
        end

        applyComplexFreehand('add');
    end

    function onComplexExclude()
        % Exclude a freehand region from INNER ROI on the current slice (subtract).
        if ~any(roiMask(:,:,state.z), 'all')
            warndlg('No INNER ROI on this slice yet. Create/confirm INNER ROI first, then use Add/Exclude.', 'Complex ROI');
            return;
        end

        applyComplexFreehand('exclude');
    end

    function applyComplexFreehand(mode)
        % mode: 'add' or 'exclude'
        z = state.z;

        % Snapshot current ROI mask so preview is non-destructive until finish
        mBase = roiMask(:,:,z);

        % Draw on stiffness map for speed
        ax = axS;
        if isZoom
            ax = axZ;     % draw complex ROI on zoomed view
        end

        % Choose colors for clarity
        if strcmp(mode,'add')
            col = [0 1 0];      % green
            ttl = 'Draw freehand region to ADD (double-click to finish)';
        else
            col = [1 0 1];      % magenta
            ttl = 'Draw freehand region to EXCLUDE (double-click to finish)';
        end

        % Optional: message
        try, title(axS, ttl); catch, end

        % Draw freehand ROI (fallback to polygon if drawfreehand not available)
        if exist('drawfreehand','file') == 2
            hFH = drawfreehand(ax, 'Color', col, 'LineWidth', 1.8);
        else
            hFH = drawpolygon(ax, 'Color', col, 'LineWidth', 1.8);
        end

        % --- LIVE PREVIEW DURING DRAWING (sync all 3 panels) ---
        lMove = [];
        lDone = [];
        try
            % Update continuously while drawing/moving
            lMove = addlistener(hFH,'MovingROI', @(~,~) previewComplexMask());
            % Also update after each "edit step" (vertex add/remove/end move)
            lDone = addlistener(hFH,'ROIMoved',  @(~,~) previewComplexMask());
        catch
            % If listener events are not supported, preview will just update at the end.
        end

        % Draw an initial preview immediately
        previewComplexMask();

        % Wait until user completes (double-click)
        try
            wait(hFH);
            % Remove listeners (avoid leaks)
            try, if ~isempty(lMove), delete(lMove); end, catch, end
            try, if ~isempty(lDone), delete(lDone); end, catch, end
        catch
            % older versions sometimes do not support wait well; just proceed
        end

        % If deleted/cancelled, bail
        if isempty(hFH) || ~isvalid(hFH)
            return;
        end

        pos = hFH.Position;
        try, delete(hFH); catch, end
        if isempty(pos) || size(pos,1) < 3
            return;
        end

        % Convert to mask
        x = min(max(pos(:,1), 1), nCol);
        y = min(max(pos(:,2), 1), nRow);
        mNew = poly2mask(x, y, nRow, nCol);

        % Keep edits inside OUTER contour if present (recommended)
        if any(roiMaskContour(:,:,z), 'all')
            mNew = mNew & roiMaskContour(:,:,z);
        end

        % Apply LapC reliability mask if your code has it enabled
        % (This prevents "Add" from re-introducing invalid pixels)
        if exist('hasLapC','var') && hasLapC
            mNew = mNew & getLapCgoodMask(z);
        end

        % Update INNER ROI mask
        mOld = roiMask(:,:,z);
        if strcmp(mode,'add')
            mFinal = mOld | mNew;
        else
            mFinal = mOld & ~mNew;
        end

        roiMask(:,:,z) = mFinal;
        sliceState(z) = int8(1);

        % Update displayed INNER ROI polygon to match the new mask (best-effort)
        pos2 = maskToPolygon(mFinal);
        if ~isempty(pos2)
            roiVertices{z} = pos2;
        else
            roiVertices{z} = [];
        end

        forceOverlayRedraw();
        updateAll();

        hasUnsavedChanges = true;
        fprintf('[ComplexROI] z=%d %s applied. ROI pixels now = %d\
', z, mode, nnz(mFinal));

        function previewComplexMask()
            if isempty(hFH) || ~isvalid(hFH)
                return;
            end

            posP = hFH.Position;
            if isempty(posP) || size(posP,1) < 3
                return;
            end

            % Convert current freehand to mask (in image pixel coordinates)
            xP = min(max(posP(:,1), 1), nCol);
            yP = min(max(posP(:,2), 1), nRow);
            mNewP = poly2mask(xP, yP, nRow, nCol);

            % Restrict inside OUTER contour if present
            if any(roiMaskContour(:,:,z), 'all')
                mNewP = mNewP & roiMaskContour(:,:,z);
            end

            % Restrict by LapC-good mask if enabled
            if exist('hasLapC','var') && hasLapC
                mNewP = mNewP & getLapCgoodMask(z);
            end

            % Preview final mask relative to baseline
            if strcmp(mode,'add')
                mPrev = mBase | mNewP;
            else
                mPrev = mBase & ~mNewP;
            end

            % Write preview into the displayed mask + polygon so overlays refresh
            roiMask(:,:,z) = mPrev;

            posPrev = maskToPolygon(mPrev);
            if ~isempty(posPrev)
                roiVertices{z} = posPrev;
            else
                roiVertices{z} = [];
            end

            % Force overlay refresh + keep UI responsive
            updateOverlay();
            updateStatus();
            drawnow limitrate nocallbacks;
        end
    end

    function onSkipSlice()
        if isLiveRoiActive()
            cancelLiveROI();
        end
        % MRE skip (technical failure / unreliable stiffness):
        % keep OUTER contour (anatomy) if present, clear INNER ROI.
        roiVertices{state.z}   = [];
        roiMask(:,:,state.z)  = false(nRow,nCol);
        sliceState(state.z)   = int8(-1);
        updateAll();
    end

    function onSkipAnatomy()
        if isLiveRoiActive()
            cancelLiveROI();
        end
        % Anatomy skip (no spleen/organ): clear BOTH contour + measurement.
        roiVerticesContour{state.z} = [];
        roiMaskContour(:,:,state.z) = false(nRow,nCol);
        sliceStateContour(state.z)  = int8(-1);

        roiVertices{state.z}  = [];
        roiMask(:,:,state.z) = false(nRow,nCol);
        sliceState(state.z)  = int8(0);   % MRE becomes N/A for anatomy-skip slices
        updateAll();
    end

    function onClearSlice()
        if isLiveRoiActive()
            cancelLiveROI();
        end
        roiVerticesContour{state.z} = [];
        roiMaskContour(:,:,state.z) = false(nRow,nCol);

        sliceStateContour(state.z)  = int8(0);

        roiVertices{state.z} = [];
        roiMask(:,:,state.z) = false(nRow,nCol);
        sliceState(state.z)  = int8(0);
        updateAll();
    end

    function startLiveROI(posInit, stage)
        liveStage = stage;

        % --- NEW: when editing inner ROI, show live polyline overlays on all 3 axes
        if strcmp(stage,'meas')
            setRoiBoundaryVisible(false);     % hide mask boundaries during live editing
            set([hRoiM hRoiW hRoiS], 'Visible','on');  % ensure polylines show
        end

        % set ROI color
        if strcmp(stage,'contour')
            roiColor = [1 1 0];   % yellow
        else
            roiColor = [0 1 1];   % cyan
        end

        cancelLiveROI();

        % Choose which axes to draw the editable ROI on
        axDraw = axS;   % default

        if strcmp(stage,'contour')
            axDraw = axM;   % outer contour is on magnitude
        else
            axDraw = axS;   % inner/meas/complex is on stiffness
        end

        % If zoom is active, draw on zoom axes instead (so you edit on big view)
        if isZoom
            axDraw = axZ;
        end


        % Create editable polygon
        hLiveRoi = drawpolygon(axDraw, 'Position', posInit, 'LineWidth', 1.8, 'Color', roiColor);

        if isempty(hLiveRoi) || ~isvalid(hLiveRoi)
            cancelLiveROI();
            updateAll();
            return;
        end
        % Disable built-in ROI context menu ("Delete vertex") so RIGHT click can be used as an eraser.
        % (MATLAB otherwise pops up the ROI's default context menu on right-click.)
        try
            cm = uicontextmenu(fig);   % empty menu (no items)
            try
                set(cm,'Visible','off');  % keep hidden (we don't want any popup)
            catch
            end

            % Some releases expose ROI menus via 'ContextMenu', some via 'UIContextMenu' (set both if present)
            if isprop(hLiveRoi,'ContextMenu')
                hLiveRoi.ContextMenu = cm;
            end
            if isprop(hLiveRoi,'UIContextMenu')
                hLiveRoi.UIContextMenu = cm;
            end
        catch
        end

        % Immediately show on M/W/S
        syncLiveStage(hLiveRoi.Position);

        liveListeners(1) = addlistener(hLiveRoi, 'MovingROI', @(src,~) syncLiveStage(src.Position));
        liveListeners(2) = addlistener(hLiveRoi, 'ROIMoved',  @(src,~) syncLiveStage(src.Position));

        updateStatus();
    end

    function syncLiveStage(pos)
        if strcmp(liveStage,'contour')
            syncOverlayToPos_specific(pos, hContourM, hContourW, hContourS);
        else
            set([hRoiM hRoiW hRoiS], 'Visible','on');  % NEW: ensure visible
            syncOverlayToPos_specific(pos, hRoiM, hRoiW, hRoiS);
        end
    end

    function tf = isLiveRoiActive()
        tf = ~isempty(hLiveRoi) && isvalid(hLiveRoi);
    end

    function cancelLiveROI()
        try
            if ~isempty(liveListeners)
                delete(liveListeners);
            end
        catch
        end
        liveListeners = event.listener.empty(0,1);

        try
            if isLiveRoiActive()
                delete(hLiveRoi);
            end
        catch
        end
        hLiveRoi = [];

        % --- NEW: restore boundary overlays after live editing ends
        setRoiBoundaryVisible(true);

        updateOverlay();
        updateStatus();
    end

    function commitLiveROI()
        if ~isLiveRoiActive()
            return;
        end

        pos = hLiveRoi.Position;
        stage = liveStage;

        cancelLiveROI();

        if isempty(pos) || size(pos,1) < 3
            updateAll();
            return;
        end

        if strcmp(stage,'contour')
            % store OUTER contour
            storeContourForSlice(state.z, pos);

            % Anatomy status: contour confirmed
            sliceStateContour(state.z) = int8(1);

            % Reset MRE/measurement state for this slice (contour just changed)
            roiVertices{state.z}    = [];
            roiMask(:,:,state.z)    = false(nRow,nCol);
            if sliceState(state.z) ~= 0
                sliceState(state.z) = int8(0);
            end

            % auto-generate INNER via erosion by 3 (default) or selected px number
            innerMask = makeInnerMaskFromContour(state.z, erodePx);
            posInner = maskToPolygon(innerMask);
            if isempty(posInner)
                posInner = roiVerticesContour{state.z};
            end

            % Start editable INNER ROI
            startLiveROI(posInner, 'meas');
            updateStatus();
            return;
        end

        % stage == 'meas'
        storeROIForSlice(state.z, pos);
        % IMPORTANT: clear the live editable polygon so navigation buttons work
        cancelLiveROI();   % deletes hLiveRoi + listeners and refreshes overlays/status
        updateAll();

    end

    function storeContourForSlice(z, pos)
        x = min(max(pos(:,1), 1), nCol);
        y = min(max(pos(:,2), 1), nRow);
        roiVerticesContour{z} = [x(:) y(:)];
        roiMaskContour(:,:,z) = poly2mask(x, y, nRow, nCol);
        forceOverlayRedraw();
    end

    function good = getLapCgoodMask(z)
        if ~hasLapC
            good = true(nRow, nCol);
            return;
        end

        % Prefer cached slice if it matches
        if cache.z == z && ~isempty(cache.LapC)
            lap = cache.LapC;
        else
            if useMatfile
                lap = double(mobj.LapC(:,:,z));
            else
                lap = double(LapC(:,:,z));
            end
        end

        good = isfinite(lap) & (lap >= lapCutoff);
    end

    function storeROIForSlice(z, pos)
        x = min(max(pos(:,1), 1), nCol);
        y = min(max(pos(:,2), 1), nRow);

        % Original (user drawn) mask
        mask0 = poly2mask(x, y, nRow, nCol);

        % Apply LapC cutoff for reliable stiffness measurement
        mask = mask0;
        if hasLapC
            mask = mask & getLapCgoodMask(z);
        end

        % Update stored mask
        roiMask(:,:,z) = mask;

        % Update displayed polygon to match the final (intersection) mask
        if any(mask(:))
            pos2 = maskToPolygon(mask);
            if ~isempty(pos2)
                roiVertices{z} = pos2;   % <- THIS makes the cyan ROI update
            else
                % Fallback: keep original vertices if boundary extraction fails
                roiVertices{z} = [x(:) y(:)];
            end
            sliceState(z) = int8(1);

            % Optional feedback
            if hasLapC
                fprintf('[LapC] z=%d: ROI pixels %d -> %d after LapC >= %.2f\
', ...
                    z, nnz(mask0), nnz(mask), lapCutoff);
            end
        else
            % If LapC removed everything, mark as NOT processed and clear ROI
            roiVertices{z} = [];
            sliceState(z)  = int8(0);

            if hasLapC
                fprintf('[LapC] z=%d: ROI became empty after LapC >= %.2f (original %d px). Redraw ROI.\
', ...
                    z, lapCutoff, nnz(mask0));
            end
            beep;
        end
        forceOverlayRedraw();
    end


    function innerMask = makeInnerMaskFromContour(z, erodePx)
        outerMask = roiMaskContour(:,:,z);
        innerMask = outerMask;

        if any(outerMask(:))
            try
                se = strel('disk', erodePx, 0);
            catch
                se = strel('disk', erodePx);
            end
            innerMask = imerode(outerMask, se);
        end

        if ~any(innerMask(:))
            innerMask = outerMask;
        end
    end

    function pos = maskToPolygon(mask)
        pos = [];
        if ~any(mask(:)), return; end
        B = bwboundaries(mask);
        if isempty(B), return; end
        [~,idx] = max(cellfun(@(c) size(c,1), B));
        b = B{idx}; % [row col]
        % Downsample boundary vertices to make manual editing practical.
        % The cap is controlled by MAX_POLY_VERTS.
        step = max(1, ceil(size(b,1)/MAX_POLY_VERTS));
        b = b(1:step:end, :);
        pos = [b(:,2) b(:,1)];
    end

    function forceOverlayRedraw()
        % Force updateOverlay() to redraw ROI overlays on all axes
        lastDrawZ   = NaN;
        lastMaskNNZ = NaN;
    end

    function hList = drawMaskBoundaries(ax, hList, mask, colorRGB)
        % Remove old boundaries
        if ~isempty(hList)
            try, delete(hList(ishghandle(hList))); catch, end
        end
        hList = gobjects(0);

        if isempty(mask) || ~any(mask(:))
            return;
        end

        if exist('bwboundaries','file') == 2
            B = bwboundaries(mask, 8, 'holes');   % includes holes + multiple islands
            for k = 1:numel(B)
                b = B{k};              % [row col]
                hList(end+1) = line(ax, b(:,2), b(:,1), ...
                    'Color', colorRGB, 'LineWidth', 1.5, 'HitTest','off'); %#ok<AGROW>
            end
        else
            % Fallback if Image Processing Toolbox isn't available
            C = contourc(double(mask), [0.5 0.5]);
            j = 1;
            while j < size(C,2)
                n = C(2,j);
                pts = C(:, j+1:j+n);
                hList(end+1) = line(ax, pts(1,:), pts(2,:), ...
                    'Color', colorRGB, 'LineWidth', 1.5, 'HitTest','off'); %#ok<AGROW>
                j = j + n + 1;
            end
        end
    end

    function pos = decimatePos(pos, maxVerts)
        % Uniformly downsample a polyline/polygon to at most maxVerts points.
        % (Keeps the first and last point.)
        if isempty(pos) || size(pos,1) <= maxVerts
            return;
        end
        n = size(pos,1);
        idx = round(linspace(1, n, maxVerts));
        idx = unique(idx(:));
        pos = pos(idx, :);
    end

    function zPrev = findPrevRoiSlice(zNow)
        zPrev = [];
        for z = (zNow-1):-1:1
            if sliceState(z) == 1 && ~isempty(roiVertices{z})
                zPrev = z; return;
            end
        end
        for z = nZ:-1:(zNow+1)
            if sliceState(z) == 1 && ~isempty(roiVertices{z})
                zPrev = z; return;
            end
        end
    end

    function tf = isSlicePending(z)
        % A slice is considered "pending" if:
        %   - anatomy is not marked as "no organ" AND
        %   - contour is not confirmed yet, OR
        %   - contour is confirmed but MRE/measurement not decided yet.
        if sliceStateContour(z) == -1
            tf = false;
            return;
        end
        if sliceStateContour(z) == 0
            tf = true;   % need contour
            return;
        end
        % contour is done -> pending only if measurement not done/skipped
        tf = (sliceState(z) == 0);
    end

    function gotoNextUnprocessed()
        if isLiveRoiActive()
            fprintf('[NextPend] blocked: live ROI active (commit/cancel it first)\
'); % DEBUG beep source
            beep; return;
        end
        z0 = state.z;
        for z = (z0+1):nZ
            if isSlicePending(z)
                setSlice(z); return;
            end
        end
        for z = 1:(z0-1)
            if isSlicePending(z)
                setSlice(z); return;
            end
        end
        % No pending slice found
        if isReviewMode
            % In review/edit mode, treat NextPend as Next Slice
            z = state.z + 1;
            if z > nZ, z = 1; end
            setSlice(z);
        else
            fprintf('[NextPend] no pending slice found. isReviewMode=%d\
', isReviewMode); % DEBUG beep source
            beep;
        end
    end

    function gotoPrevUnprocessed()
        if isLiveRoiActive()
            beep; return;
        end
        z0 = state.z;
        for z = (z0-1):-1:1
            if isSlicePending(z)
                setSlice(z); return;
            end
        end
        for z = nZ:-1:(z0+1)
            if isSlicePending(z)
                setSlice(z); return;
            end
        end
        % No pending slice found
        if isReviewMode
            % In review/edit mode, treat PrevPend as Prev Slice
            z = state.z - 1;
            if z < 1, z = nZ; end
            setSlice(z);
        else
            beep;
        end
    end

% --- Auto mask from SEED CIRCLE/ELLIPSE on time-averaged magnitude ---
    function mask = autoMaskFromSeedCircle(I, seedMask)
        % I should be normalized 0..1
        mask = false(size(I));

        seedVals = double(I(seedMask));
        seedVals = seedVals(isfinite(seedVals));
        if numel(seedVals) < 20
            return;
        end

        % Use robust percentiles to estimate a "broad but organ-specific" range
        lo0 = prctile(seedVals, 10);
        hi0 = prctile(seedVals, 90);
        w0  = hi0 - lo0;
        if ~isfinite(w0) || w0 <= 0
            w0 = 0.05;
        end

        % Heuristics
        minA = 200;              % reject tiny
        maxA = 0.60 * numel(I);  % reject huge leakage

        best = false(size(I));
        bestScore = -inf;

        expandList = [0.20 0.35 0.50 0.75 1.00];
        for ex = expandList
            lo = max(0, lo0 - ex*w0 - 0.02);
            hi = min(1, hi0 + ex*w0 + 0.02);

            cand = (I >= lo) & (I <= hi);

            % Clean up
            cand = imfill(cand, 'holes');
            cand = bwareaopen(cand, 100);
            try
                cand = imclose(cand, strel('disk', 2, 0));
            catch
                cand = imclose(cand, strel('disk', 2));
            end

            CC = bwconncomp(cand, 8);
            if CC.NumObjects < 1
                continue;
            end

            % Choose the component that overlaps the seedMask the most
            ov = zeros(CC.NumObjects, 1);
            sz = zeros(CC.NumObjects, 1);
            for iCC = 1:CC.NumObjects
                pix = CC.PixelIdxList{iCC};
                ov(iCC) = nnz(seedMask(pix));
                sz(iCC) = numel(pix);
            end

            [ovBest, idx] = max(ov);
            if ovBest == 0
                % If nothing overlaps, fall back to largest component
                [~, idx] = max(sz);
                ovBest = 0;
            end

            m = false(size(I));
            m(CC.PixelIdxList{idx}) = true;
            m = imfill(m, 'holes');

            a = nnz(m);
            if a < minA
                score = ovBest - 1e6;
            elseif a > maxA
                score = ovBest - 1e6;
            else
                score = ovBest - 0.001*a; % prefer high overlap, not too big
            end

            if score > bestScore
                bestScore = score;
                best = m;
            end

            % If it overlaps and passes size, accept early
            if ovBest > 0 && a >= minA && a <= maxA
                mask = m;
                return;
            end
        end

        mask = best;

        if any(mask(:))
            % final cleanup
            mask = bwareafilt(mask, 1);
        end
    end

% ---------- Save / close ----------
    function onFinishSave()
        if isLiveRoiActive()
            beep;
            return;
        end

        stopTimerSafe();

        createdOn = datestr(now, 31);
        metaOut = meta;
        metaOut.matPath = matPath;
        metaOut.organ = organ;
        metaOut.createdOn = createdOn;

        % Save INNER measurement ROI
        save(roiPathMeas, 'organ','roiMask','roiVertices','sliceState','metaOut','-v7.3');

        % Save OUTER contour ROI
        % NOTE: sliceStateContour is maintained independently from sliceState.
        save(roiPathContour, 'organ','roiMaskContour','roiVerticesContour','sliceStateContour','metaOut','-v7.3');

        try
            export_summary_and_voxels_ROIonly();
        catch ME
            warning('Export failed: %s', ME.message);
        end

        % Also export contour-based shape/geometry metrics (3D + per-slice 2D)
        % into additional sheets in the same Excel workbook.
        try
            export_contour_shape_metrics();
        catch ME
            warning('Contour metrics export failed: %s', ME.message);
        end

        hasUnsavedChanges = false;
        status = 'saved';
        statusLocked = true;  % add this line to avoid overwriting issue

        % Close the figure directly without calling closeUi() to avoid any callbacks
        stopTimerSafe();
        try
            set(fig,'CloseRequestFcn','');  % Remove close callback entirely
        catch
        end
        try
            uiresume(fig);  % Release uiwait
        catch
        end
        try
            delete(fig);  % Delete figure directly (not close)
        catch
        end
    end

    function onExportGifs()
        % Hotkey: 'g'
        % Writes one animated GIF for the CURRENT slice (state.z) only.
        % Animation loops over time phase offsets (t = 1..nT).
        % Output: three pure images side-by-side (magnitude, wave, stiffness)
        %         -- no axes, no colorbar, no titles, no edges.
        try
            exportGifCurrentSlice();
        catch ME
            warning('GIF export failed: %s', ME.message);
        end
    end

    function exportGifCurrentSlice()
        % Export animated GIF for the CURRENT Z-slice only.
        % Frames = time phase offsets. Output: pure pixel triptych (M | W | S).

        % Pause animation while exporting
        wasRunning = false;
        if exist('tmr','var') && isa(tmr,'timer') && isvalid(tmr)
            wasRunning = strcmpi(tmr.Running,'on');
            if wasRunning, stop(tmr); end
        end
        cleanObj = onCleanup(@() restartTimerIfNeeded(wasRunning));

        outDir = fullfile(seriesDir, 'gif_exports');
        if ~exist(outDir,'dir'), mkdir(outDir); end

        z = state.z;   % current slice only

        % Force reload of current slice
        savedCacheZ = cache.z;
        cache.z = NaN;
        loadSlice(z);

        % ===== Get synchronized data from cache =====
        % loadSlice has already synchronized M and W to same time dimension
        magRaw    = cache.M;    % Already interpolated to match W
        waveRaw   = cache.W;    % Original W (8 frames)
        stiffRaw  = cache.S;    % Static
        nTimeFinal = size(magRaw, 3);  % Should be 8

        fprintf('=== GIF Export ===\
');
        fprintf('magRaw:  %s\
', mat2str(size(magRaw)));
        fprintf('waveRaw: %s\
', mat2str(size(waveRaw)));
        fprintf('Frames for GIF: %d\
', nTimeFinal);

        % Check for animation viability
        if nTimeFinal <= 1
            fprintf('Slice %d has only 1 time phase -- nothing to animate.\
', z);
            return;
        end

        % No interpolation needed - cache already has synchronized M and W
        magInterp = magRaw;
        waveInterp = waveRaw;

        % ===== Check if ROI files exist =====
        hasROIfiles = isfile(roiPathMeas) && isfile(roiPathContour);

        % ===== Extract ROI boundaries (only if ROI files exist) =====
        if hasROIfiles
            [xContour, yContour] = boundaryFromMask(getMaskSafe(roiMaskContour, z));
            [xMeas, yMeas]       = boundaryFromMask(getMaskSafe(roiMask, z));
            fprintf('ROI files found - will overlay boundaries on GIF\
');
        else
            xContour = []; yContour = [];
            xMeas = []; yMeas = [];
            fprintf('No ROI files - GIF will be created without ROI overlays\
');
        end

        % ===== Display settings =====
        climMag   = get(axM, 'CLim');
        climWave  = get(axW, 'CLim');
        climStiff = stiffCLim;  % 0-8 or 0-20 kPa

        cmapMag   = gray(256);
        cmapWave  = waveCmap;
        cmapStiff = stiffCmap;

        % Pre-render static stiffness panel
        imgStiff = mat2rgb(stiffRaw, climStiff, cmapStiff);

        % ===== Generate GIF =====
        delayTime = 0.08;  % seconds per frame
        gifPath = fullfile(outDir, sprintf('%s_%s_slice%03d.gif', ...
            meta.ExamId, meta.SeriesId, z));
        if exist(gifPath, 'file'), delete(gifPath); end

        for iFrame = 1:nTimeFinal
            % Render magnitude and wave panels for this time frame
            imgMag  = mat2rgb(magInterp(:,:,iFrame), climMag, cmapMag);
            imgWave = mat2rgb(realIfComplex(waveInterp(:,:,iFrame)), climWave, cmapWave);

            % Build colorbar strip
            cbWidth = max(12, round(nCol / 10));
            cbStrip = buildColorbarStrip(nRow, cbWidth, climStiff, cmapStiff);

            % Concatenate panels: [Mag | Wave | Stiff | Colorbar]
            triptych = [imgMag, imgWave, imgStiff, cbStrip];

            % Burn ROI outlines (only if ROI files exist)
            if hasROIfiles && ~isempty(xContour) && ~isempty(xMeas)
                % Yellow = outer contour, Cyan = measurement ROI
                triptych = burnBoundary(triptych, xContour, yContour, 0,       [255 255 0]);  % Mag
                triptych = burnBoundary(triptych, xContour, yContour, nCol,    [255 255 0]);  % Wave
                triptych = burnBoundary(triptych, xContour, yContour, 2*nCol,  [255 255 0]);  % Stiff
                triptych = burnBoundary(triptych, xMeas,    yMeas,    0,       [0 255 255]);  % Mag
                triptych = burnBoundary(triptych, xMeas,    yMeas,    nCol,    [0 255 255]);  % Wave
                triptych = burnBoundary(triptych, xMeas,    yMeas,    2*nCol,  [0 255 255]);  % Stiff
            end

            % Convert to indexed color and write
            [indexed, cmap] = rgb2ind(triptych, 256);

            if iFrame == 1
                imwrite(indexed, cmap, gifPath, 'gif', ...
                    'LoopCount', inf, 'DelayTime', delayTime);
            else
                imwrite(indexed, cmap, gifPath, 'gif', ...
                    'WriteMode', 'append', 'DelayTime', delayTime);
            end
        end

        fprintf('\u2713 GIF saved (%d frames): %s\
', nTimeFinal, gifPath);

    end

    function rgb = mat2rgb(data, clim, cmap)
        % Convert a 2D matrix to uint8 RGB image using the given CLim and colormap.
        % Pure pixel output -- no axes, no borders.
        lo = clim(1); hi = clim(2);
        if hi == lo, hi = lo + 1; end
        nColors = size(cmap, 1);
        idx = round((double(data) - lo) / (hi - lo) * (nColors - 1)) + 1;
        idx = max(1, min(nColors, idx));
        rgbVals = cmap(idx(:), :);
        if max(rgbVals(:)) <= 1.0
            rgbVals = rgbVals * 255;
        end
        rgb = uint8(reshape(rgbVals, [size(data,1), size(data,2), 3]));
    end

    function img = burnBoundary(img, bx, by, colOffset, color)
        % Burn a boundary polyline onto a uint8 RGB image.
        % bx, by: boundary coordinates (pixel units, from boundaryFromMask)
        % colOffset: horizontal pixel offset for this panel (0, nCol, 2*nCol)
        % color: [R G B] uint8 triplet

        % Early return if no boundary data
        if isempty(bx) || isempty(by), return; end
        if isnan(bx(1)), return; end

        nPts = numel(bx);
        [imgH, imgW, ~] = size(img);

        for k = 1:nPts-1
            % Bresenham-lite: interpolate between consecutive boundary vertices
            x0 = round(bx(k)) + colOffset;
            y0 = round(by(k));
            x1 = round(bx(k+1)) + colOffset;
            y1 = round(by(k+1));

            nSteps = max(abs(x1-x0), abs(y1-y0));
            if nSteps == 0
                nSteps = 1;
            end

            xs = round(linspace(x0, x1, nSteps+1));
            ys = round(linspace(y0, y1, nSteps+1));

            for j = 1:numel(xs)
                cc = xs(j); rr = ys(j);
                if rr >= 1 && rr <= imgH && cc >= 1 && cc <= imgW
                    img(rr, cc, 1) = color(1);
                    img(rr, cc, 2) = color(2);
                    img(rr, cc, 3) = color(3);
                end
            end
        end
    end

    function strip = buildColorbarStrip(stripH, stripW, clim, cmap)
        % Build a vertical colorbar RGB image: top = max, bottom = min.
        % stripH: height in pixels (matches image height - MUST NOT CHANGE)
        % stripW: width in pixels
        % clim:   [lo hi]
        % cmap:   Nx3 colormap

        nColors = size(cmap, 1);

        % Vertical gradient: row 1 = max value, row end = min value
        vals = linspace(clim(2), clim(1), stripH)';  % top-to-bottom = high-to-low
        idx = round((vals - clim(1)) / (clim(2) - clim(1)) * (nColors - 1)) + 1;
        idx = max(1, min(nColors, idx));

        % Map to RGB
        rgbCol = cmap(idx, :);
        if max(rgbCol(:)) <= 1.0
            rgbCol = rgbCol * 255;
        end
        rgbCol = uint8(rgbCol);  % [stripH x 3]

        % Replicate across width
        strip = repmat(reshape(rgbCol, [stripH, 1, 3]), [1, stripW, 1]);

        % Add numeric labels at TOP and BOTTOM edges
        % Use black background rectangles for white text visibility
        labelHi = sprintf('%d', clim(2));
        labelLo = sprintf('%d', clim(1));

        % Black background rectangles for labels (small, just enough for text)
        textH = 16;  % Height for text area
        textW = stripW;  % Full width of colorbar
        
        % Create black rectangles at top and bottom edges
        % Top label area (rows 1 to textH)
        strip(1:textH, :, :) = 0;  % Black background
        
        % Bottom label area (rows end-textH+1 to end)
        strip(end-textH+1:end, :, :) = 0;  % Black background
        
        % Burn WHITE text onto black backgrounds
        strip = burnTextWhite(strip, labelHi, 2, 2);              % Top label
        strip = burnTextWhite(strip, labelLo, stripH-textH+2, 2); % Bottom label
    end

    function img = burnText(img, txt, row, col)
        % Minimal black-on-white text burner using a tiny 3x5 font.
        % Supports: 0-9, k, P, a, space, dash
        glyphs = getGlyphs();
        cx = col;
        for i = 1:numel(txt)
            ch = txt(i);
            if isKey(glyphs, ch)
                g = glyphs(ch);  % 5x3 logical
            else
                g = false(5,3);  % unknown char = blank
            end
            [gh, gw] = size(g);
            for gr = 1:gh
                for gc = 1:gw
                    rr = row + gr - 1;
                    cc = cx + gc - 1;
                    if rr >= 1 && rr <= size(img,1) && cc >= 1 && cc <= size(img,2) && g(gr,gc)
                        img(rr, cc, :) = 0;  % black pixel
                    end
                end
            end
            cx = cx + gw + 1;  % advance cursor + 1px spacing
        end
    end

    function img = burnTextWhite(img, txt, row, col)
        % WHITE text burner for black backgrounds (for GIF colorbar labels)
        % Supports: 0-9, k, P, a, space, dash
        glyphs = getGlyphs();
        cx = col;
        for i = 1:numel(txt)
            ch = txt(i);
            if isKey(glyphs, ch)
                g = glyphs(ch);  % 5x3 logical
            else
                g = false(5,3);  % unknown char = blank
            end
            [gh, gw] = size(g);
            for gr = 1:gh
                for gc = 1:gw
                    rr = row + gr - 1;
                    cc = cx + gc - 1;
                    if rr >= 1 && rr <= size(img,1) && cc >= 1 && cc <= size(img,2) && g(gr,gc)
                        img(rr, cc, :) = 255;  % WHITE pixel (instead of black)
                    end
                end
            end
            cx = cx + gw + 1;  % advance cursor + 1px spacing
        end
    end

    function g = getGlyphs()
        % Tiny 5x3 bitmap font for digits and a few letters
        g = containers.Map('KeyType','char','ValueType','any');
        g('0') = [1 1 1; 1 0 1; 1 0 1; 1 0 1; 1 1 1];
        g('1') = [0 1 0; 1 1 0; 0 1 0; 0 1 0; 1 1 1];
        g('2') = [1 1 1; 0 0 1; 1 1 1; 1 0 0; 1 1 1];
        g('3') = [1 1 1; 0 0 1; 1 1 1; 0 0 1; 1 1 1];
        g('4') = [1 0 1; 1 0 1; 1 1 1; 0 0 1; 0 0 1];
        g('5') = [1 1 1; 1 0 0; 1 1 1; 0 0 1; 1 1 1];
        g('6') = [1 1 1; 1 0 0; 1 1 1; 1 0 1; 1 1 1];
        g('7') = [1 1 1; 0 0 1; 0 0 1; 0 0 1; 0 0 1];
        g('8') = [1 1 1; 1 0 1; 1 1 1; 1 0 1; 1 1 1];
        g('9') = [1 1 1; 1 0 1; 1 1 1; 0 0 1; 1 1 1];
        g('k') = [1 0 1; 1 0 1; 1 1 0; 1 0 1; 1 0 1];
        g('P') = [1 1 1; 1 0 1; 1 1 1; 1 0 0; 1 0 0];
        g('a') = [0 0 0; 0 1 1; 1 0 1; 1 1 1; 1 0 1];
        g(' ') = [0 0 0; 0 0 0; 0 0 0; 0 0 0; 0 0 0];
        g('-') = [0 0 0; 0 0 0; 1 1 1; 0 0 0; 0 0 0];
    end

    function onStiffScaleToggle()
        if get(btnStiffScale, 'Value') == 1
            % Switched to 0-20 kPa
            stiffCLim = [0 20];
            set(btnStiffScale, 'String', '0-20 kPa');
        else
            % Switched back to 0-8 kPa
            stiffCLim = [0 8];
            set(btnStiffScale, 'String', '0-8 kPa');
        end
        % Update axes and colorbar
        set(axS, 'CLim', stiffCLim);
        if stiffCLim(2) == 20
            cbS.Ticks = 0:2:20;
        else
            cbS.Ticks = 0:1:8;
        end
        % Refresh display
        updateAll();
    end

    function restartTimerIfNeeded(wasRunning)
        % Restart animation timer after GIF export if it was running before
        if wasRunning
            try
                if exist('tmr','var') && isa(tmr,'timer') && isvalid(tmr)
                    start(tmr);
                end
            catch
            end
        end
    end

    function export_summary_and_voxels_ROIonly()
        % ---- Load S ONCE to avoid matfile partial-loading warning spam ----
        tmpS = load(matPath, 'S');     % loads whole variable once (quiet)
        Sfull = double(tmpS.S);
        clear tmpS;

        sheetName = 'Stiffness';

        if isfile(xlsxPath)
            try, delete(xlsxPath); catch, end
        end

        valsBySlice = cell(nZ,1);
        nPix = zeros(nZ,1);
        mu   = nan(nZ,1);
        med  = nan(nZ,1);
        sd   = nan(nZ,1);

        for z = 1:nZ
            if sliceState(z) ~= 1
                continue;
            end
            mask = roiMask(:,:,z);
            if hasLapC
                mask = mask & getLapCgoodMask(z);
            end
            if ~any(mask(:))
                continue;
            end

            if ndims(Sfull) == 4
                % If S is 4D, match your display logic (mean over last dim)
                tmp = squeeze(Sfull(:,:,z,:));         % [row col t]
                Sslice = mean(tmp, 3, 'omitnan');
            else
                Sslice = Sfull(:,:,z);
            end

            v = double(Sslice(mask));
            v = v(isfinite(v) & v > 0);

            valsBySlice{z} = v(:);
            nPix(z) = numel(v);

            if nPix(z) > 0
                mu(z)  = mean(v);
                med(z) = median(v);
                sd(z)  = std(v);
            end
        end

        roiZ = find(sliceState == 1 & nPix > 0);

        if isempty(roiZ)
            writecell({sprintf('No ROI slices with valid voxels for %s.', upper(organ))}, ...
                xlsxPath, 'Sheet', sheetName, 'Range', 'A1');
            return;
        end

        maxN = max(nPix(roiZ));

        nHeaderCols = 5;
        nCols = nHeaderCols + maxN;
        nRows = 4 + numel(roiZ);

        out = cell(nRows, nCols);

        out{1,1} = sprintf('ROI VOXEL VALUES BY SLICE (%s)  %s_%s', upper(organ), meta.ExamId, meta.SeriesId);

        out(3,1:nHeaderCols) = {'SliceZ','NumPixels','Mean','Median','Std'};
        for k = 1:maxN
            out{3, nHeaderCols + k} = sprintf('V%d', k);
        end

        allVals = vertcat(valsBySlice{roiZ});
        out{4,1} = 0;
        out{4,2} = numel(allVals);
        out{4,3} = mean(allVals);
        out{4,4} = median(allVals);
        out{4,5} = std(allVals);

        r = 5;
        for i = 1:numel(roiZ)
            z = roiZ(i);
            v = valsBySlice{z};

            out{r,1} = z;
            out{r,2} = nPix(z);
            out{r,3} = mu(z);
            out{r,4} = med(z);
            out{r,5} = sd(z);

            for k = 1:numel(v)
                out{r, nHeaderCols + k} = v(k);
            end

            r = r + 1;
        end

        writecell(out, xlsxPath, 'Sheet', sheetName, 'Range', 'A1');
    end


    function export_contour_shape_metrics()
        % Export shape-based radiomics + curvature metrics from OUTER contour ROI.
        % Writes into the SAME <organ>.xlsx as extra sheets:
        %   - ContourMetrics : overall 3D metrics
        %   - ContourBySlice : per-slice area/perimeter/curvature
        %
        % Uses Hhdr (optional) for voxel spacing.

        sheetMetrics = 'ContourMetrics';
        sheetBySlice = 'ContourBySlice';

        if ~any(roiMaskContour(:))
            try
                writecell({sprintf('No contour ROI found for %s.', upper(organ))}, ...
                    xlsxPath, 'Sheet', sheetMetrics, 'Range', 'A1');
            catch
            end
            return;
        end

        % --- voxel spacing (mm) ---
        if ~exist('H','var') || isempty(H)
            tmpH = load(matPath,'H');
            if isfield(tmpH,'H'), H = tmpH.H; else, H = []; end
        end

        [fov, dx, dy, dz] = voxelSizeFromH(H, nRow, nCol);

        % --- use largest connected component (robust to small islands) ---
        BW = roiMaskContour;
        try
            BW = keepLargestComponent3D(BW);
        catch
        end

        voxCount = nnz(BW);
        vol_mm3  = voxCount * dx * dy * dz;
        vol_mL   = vol_mm3 / 1000;

        % ---------- Surface area + shape metrics (robust + always-defined) ----------
        % Make sure dx_mm, dy_mm, dz_mm exist BEFORE this block.
        dx_mm = dx; dy_mm = dy; dz_mm = dz;

        % Make sure roiMaskContour (or mask3d) is a logical 3D mask.
        sa_mm2 = NaN;  % <-- critical: prevents "Unrecognized variable 'sa_mm2'"
        mask3d = logical(roiMaskContour);  % or: mask3d = logical(mask3d);

        % Volume (mm^3)
        vol_mm3 = nnz(mask3d) * dx_mm * dy_mm * dz_mm;

        % Surface area via isosurface + triangle areas
        if any(mask3d(:))
            fv = isosurface(double(mask3d), 0.5);   % use double to be safe
            if ~isempty(fv.vertices) && ~isempty(fv.faces)
                V = double(fv.vertices);
                F = double(fv.faces);

                % isosurface vertices are in voxel coordinates:
                % V(:,1)=x=col, V(:,2)=y=row, V(:,3)=z=slice
                V(:,1) = V(:,1) * dx_mm;
                V(:,2) = V(:,2) * dy_mm;
                V(:,3) = V(:,3) * dz_mm;

                sa_mm2 = triMeshSurfaceArea(V, F);
            end
        end

        % --- derived 3D shape metrics ---
        sphericity = NaN;
        compactnessSphere = NaN;  % 1 for a perfect sphere
        saToVol = NaN;
        if isfinite(sa_mm2) && sa_mm2 > 0 && vol_mm3 > 0
            sphericity = (pi^(1/3) * (6*vol_mm3)^(2/3)) / sa_mm2;
            compactnessSphere = (36*pi*(vol_mm3^2)) / (sa_mm2^3);
            saToVol = sa_mm2 / vol_mm3;
        end

        [L1, L2, L3, elongation, flatness] = principalAxesFromMask(BW, dx, dy, dz);

        % --- per-slice metrics ---
        zList = find(squeeze(any(any(BW,1),2)));
        nSlicesUsed = numel(zList);

        outBySlice = cell(nSlicesUsed + 1, 8);
        outBySlice(1,:) = {'SliceZ','Area_px','Area_mm2','Perimeter_mm', ...
            'MeanAbsCurv_1mm','MedianAbsCurv_1mm','MaxAbsCurv_1mm','NumVertices'};

        for ii = 1:nSlicesUsed
            z = zList(ii);
            m2 = BW(:,:,z);

            area_px  = nnz(m2);
            area_mm2 = area_px * dx * dy;

            pos = [];
            if z <= numel(roiVerticesContour)
                pos = roiVerticesContour{z};
            end
            if isempty(pos)
                pos = maskToPolygon(m2);
            end

            per_mm = NaN; meanK = NaN; medK = NaN; maxK = NaN; nV = 0;
            if ~isempty(pos)
                nV = size(pos,1);
                [per_mm, kstats] = boundaryPerimeterAndCurvature(pos, dx, dy);
                meanK = kstats.meanAbs;
                medK  = kstats.medianAbs;
                maxK  = kstats.maxAbs;
            end

            outBySlice(ii+1,:) = {z, area_px, area_mm2, per_mm, meanK, medK, maxK, nV};
        end

        % perimeter-weighted mean curvature across slices
        curvWmean = NaN;
        try
            perims = cell2mat(outBySlice(2:end,4));
            kmean  = cell2mat(outBySlice(2:end,5));
            ok = isfinite(perims) & isfinite(kmean) & perims > 0;
            if any(ok)
                curvWmean = sum(perims(ok) .* kmean(ok)) / sum(perims(ok));
            end
        catch
        end

        outMetrics = {
            'ExamId', meta.ExamId;
            'SeriesId', meta.SeriesId;
            'Organ', upper(organ);
            'FOV_mm', fov;
            'dx_mm', dx;
            'dy_mm', dy;
            'dz_mm', dz;
            'NumSlicesContour', nSlicesUsed;
            'VoxelCount', voxCount;
            'Volume_mm3', vol_mm3;
            'Volume_mL', vol_mL;
            'SurfaceArea_mm2', sa_mm2;
            'SurfaceToVolume_1_per_mm', saToVol;
            'Sphericity', sphericity;
            'CompactnessSphere', compactnessSphere;
            'PrincipalAxis1_mm', L1;
            'PrincipalAxis2_mm', L2;
            'PrincipalAxis3_mm', L3;
            'Elongation_L2_over_L1', elongation;
            'Flatness_L3_over_L1', flatness;
            'PerimWeightedMeanAbsCurv_1mm', curvWmean;
            };

        % Write Excel (append new sheets; file may already exist)
        try
            writecell(outMetrics, xlsxPath, 'Sheet', sheetMetrics, 'Range', 'A1');
            writecell(outBySlice, xlsxPath, 'Sheet', sheetBySlice, 'Range', 'A1');
        catch ME
            warning('Failed to write contour metrics to Excel: %s', ME.message);
        end
    end

    function onClose()
        % This is called when user clicks the X button - always abort
        stopTimerSafe();
        % Only set status to 'abort' if it hasn't already been locked as 'saved'
        if ~statusLocked && ~strcmp(status, 'saved')
            status = 'abort';
        end

        % Close the UI
        try
            set(fig,'CloseRequestFcn','');  % Remove callback to prevent recursion
        catch
        end
        try
            uiresume(fig);
        catch
        end
        try
            delete(fig);
        catch
        end
    end

    function mask = getMaskSafe(maskVol, z)
        % Safely extract a 2D slice from a 3D mask volume
        if isempty(maskVol) || z < 1 || z > size(maskVol, 3)
            mask = false(nRow, nCol);
        else
            mask = maskVol(:,:,z);
        end
    end

    function [x, y] = boundaryFromMask(mask)
        % Extract closed boundary coordinates from a binary mask
        % Returns NaN vectors if no boundary found
        x = NaN; y = NaN;
        if ~any(mask(:))
            return;
        end
        try
            B = bwboundaries(mask, 'noholes');
            if isempty(B)
                return;
            end
            % Use the largest boundary
            [~, idx] = max(cellfun(@numel, B));
            coords = B{idx};
            y = coords(:,1);   % bwboundaries returns [row col]
            x = coords(:,2);
            % Close the polygon
            x = [x; x(1)];
            y = [y; y(1)];
        catch
        end
    end

    function stopTimerSafe()
        try
            if isvalid(tmr)
                if strcmp(tmr.Running,'on'), stop(tmr); end
                delete(tmr);
            end
        catch
        end
    end

    function closeUi()
        try
            set(fig,'CloseRequestFcn','closereq');
        catch
        end
        try
            uiresume(fig);
        catch
        end
        try
            close(fig);
        catch
            try, delete(fig); catch, end
        end
    end

end

% =================== Helper functions (outside) ===================

function v = realIfComplex(v)
if ~isreal(v), v = real(v); end
end

function applyClim(ax, clim)
if isempty(clim) || any(~isfinite(clim)) || clim(1)==clim(2), return; end
set(ax,'CLim',clim);
end

function clim = robustClim(data, loPct, hiPct)
vals = double(data(:));
vals = vals(isfinite(vals));
if isempty(vals)
    clim = [0 1]; return;
end
vals = sort(vals);
n = numel(vals);
ilo = max(1, round(loPct/100*n));
ihi = min(n, round(hiPct/100*n));
lo = vals(ilo);
hi = vals(ihi);
if lo==hi
    lo = min(vals); hi = max(vals);
    if lo==hi, lo = lo-0.5; hi = hi+0.5; end
end
clim = [lo hi];
end

function mask = circleMaskFromGeom(cx, cy, r, nRow, nCol)
% cx,cy in image coordinate units (x=col, y=row)
if nargin < 5
    error('circleMaskFromGeom requires cx,cy,r,nRow,nCol');
end
[X,Y] = meshgrid(1:nCol, 1:nRow);
mask = ((X - cx).^2 + (Y - cy).^2) <= (r.^2);
end

function out = tryLoadMat(fp)
%TRYLOADMAT  Load a MAT-file robustly (even if extension is .roi).
try
    out = load(fp, '-mat');
catch
    out = load(fp);
end
end

function [fov_mm, dx_mm, dy_mm, dz_mm] = voxelSizeFromH(H, nRow, nCol)
% Robustly extract voxel size from H (DICOM header struct).
% - dx,dy computed from FOV/nCol, FOV/nRow (ignores AcquisitionMatrix)
% - dz from SliceThickness (fallback to SpacingBetweenSlices)

fov_mm = NaN; dx_mm = NaN; dy_mm = NaN; dz_mm = NaN;

if isempty(H), return; end

% Handle H being a cell array or struct array
H0 = H;
if iscell(H0)
    idx = find(~cellfun(@isempty,H0), 1, 'first');
    if isempty(idx), return; end
    H0 = H0{idx};
end
if numel(H0) > 1
    H0 = H0(1);
end
if ~isstruct(H0), return; end

% FOV (mm)
if isfield(H0,'DisplayFieldOfView') && ~isempty(H0.DisplayFieldOfView)
    fov_mm = double(H0.DisplayFieldOfView);
elseif isfield(H0,'ReconstructionDiameter') && ~isempty(H0.ReconstructionDiameter)
    fov_mm = double(H0.ReconstructionDiameter);
end

% Slice thickness (mm)
if isfield(H0,'SliceThickness') && ~isempty(H0.SliceThickness)
    dz_mm = double(H0.SliceThickness);
elseif isfield(H0,'SpacingBetweenSlices') && ~isempty(H0.SpacingBetweenSlices)
    dz_mm = double(H0.SpacingBetweenSlices);
end

% Convert string -> number if needed
if ischar(fov_mm) || isstring(fov_mm), fov_mm = str2double(fov_mm); end
if ischar(dz_mm)  || isstring(dz_mm),  dz_mm  = str2double(dz_mm);  end

if ~isfinite(fov_mm) || fov_mm <= 0
    return;
end

% IMPORTANT: ignore acquisition matrix, use your actual image size
dx_mm = fov_mm / double(nCol);
dy_mm = fov_mm / double(nRow);

if ~isfinite(dz_mm) || dz_mm <= 0
    dz_mm = 1; % fallback, but ideally never used
end
end

function BW = keepLargestComponent3D(BW)
%KEEPLARGESTCOMPONENT3D  Keep only the largest 3D connected component.

if ~any(BW(:))
    return;
end

CC = bwconncomp(BW, 26);
if CC.NumObjects <= 1
    return;
end

sizes = cellfun(@numel, CC.PixelIdxList);
[~, idx] = max(sizes);

BW2 = false(size(BW));
BW2(CC.PixelIdxList{idx}) = true;
BW = BW2;
end

function [L1, L2, L3, elongation, flatness] = principalAxesFromMask(BW, dx, dy, dz)
%PRINCIPALAXESFROMMASK  Principal axis lengths (mm) from the voxel cloud covariance.
% Uses the filled-ellipsoid relationship: full axis length = sqrt(20 * lambda),
% where lambda is an eigenvalue of the coordinate covariance matrix.

L1 = NaN; L2 = NaN; L3 = NaN; elongation = NaN; flatness = NaN;

idx = find(BW);
if isempty(idx)
    return;
end

[r, c, z] = ind2sub(size(BW), idx);

% voxel centers in mm
x = (double(c) - 0.5) * dx;
y = (double(r) - 0.5) * dy;
zz = (double(z) - 0.5) * dz;

X = [x(:) y(:) zz(:)];

if size(X,1) < 2
    return;
end

C = cov(X, 1); % normalize by N
ev = eig(C);
ev = real(ev(:));
ev(ev < 0) = 0;
ev = sort(ev, 'descend');

if numel(ev) < 3
    return;
end

L = sqrt(20 * ev); % full axis lengths (mm)
L1 = L(1); L2 = L(2); L3 = L(3);

if isfinite(L1) && L1 > 0
    elongation = L2 / L1;
    flatness   = L3 / L1;
end
end

function [perimeter_mm, stats] = boundaryPerimeterAndCurvature(pos, dx, dy)
%BOUNDARYPERIMETERANDCURVATURE  Perimeter and discrete curvature stats for a closed polygon.
% pos: [x y] in pixel units (x=col, y=row)
% returns:
%   perimeter_mm
%   stats.meanAbs / medianAbs / maxAbs (1/mm)

stats.meanAbs = NaN;
stats.medianAbs = NaN;
stats.maxAbs = NaN;

if isempty(pos) || size(pos,1) < 3
    perimeter_mm = NaN;
    return;
end

% convert to mm
x = double(pos(:,1)) * dx;
y = double(pos(:,2)) * dy;

% ensure closed
x2 = [x; x(1)];
y2 = [y; y(1)];

seg = hypot(diff(x2), diff(y2));
perimeter_mm = sum(seg);

% curvature using turning angle / arc length approximation
P = [x y];
n = size(P,1);

% wrap indices
iPrev = [n; (1:n-1)'];
iNext = [(2:n)'; 1];

v1 = P - P(iPrev,:);
v2 = P(iNext,:) - P;

n1 = hypot(v1(:,1), v1(:,2));
n2 = hypot(v2(:,1), v2(:,2));

denom = (n1 .* n2);
denom(denom == 0) = eps;

cosang = (v1(:,1).*v2(:,1) + v1(:,2).*v2(:,2)) ./ denom;
cosang = max(-1, min(1, cosang));

ang = acos(cosang); % radians

ds = (n1 + n2) / 2;
ds(ds == 0) = eps;

kappa = ang ./ ds; % 1/mm
kappa = abs(kappa);
kappa = kappa(isfinite(kappa));

if isempty(kappa)
    return;
end

stats.meanAbs   = mean(kappa);
stats.medianAbs = median(kappa);
stats.maxAbs    = max(kappa);
end

function tf = isMatV73(matPath)
% Returns true if MAT file is v7.3 (HDF5) -> supports partial loading via matfile.
tf = false;
fid = fopen(matPath, 'r');
if fid < 0, return; end
c = fread(fid, 64, '*char')';
fclose(fid);
tf = contains(c, 'MATLAB 7.3 MAT-file');
end

function SA = triMeshSurfaceArea(V, F)
% V: Nx3 vertices, F: Mx3 faces
V = double(V); F = double(F);
v1 = V(F(:,1),:);
v2 = V(F(:,2),:);
v3 = V(F(:,3),:);
SA = 0.5 * sum( sqrt(sum(cross(v2-v1, v3-v1, 2).^2, 2)) );
end
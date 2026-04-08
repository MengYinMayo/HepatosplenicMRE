function result = seg_L1L2ROIGui(dixon, L12_dixon, opts)
% SEG_L1L2ROIGUI  Interactive ROI placement for muscle and SAT at L1-L2 levels.
%
%   RESULT = SEG_L1L2ROIGUI(DIXON, L12_DIXON) opens a 4-panel figure showing
%   Dixon water and PDFF images at the L1 and L2 vertebral levels. The user
%   draws two ROIs per level — one for abdominal muscle groups and one for
%   subcutaneous adipose tissue (SAT) — then clicks Finish to compute area
%   and fat-fraction measurements.
%
%   INPUTS
%     dixon       struct from seg_buildDixonVolume
%     L12_dixon   struct from loc_propagateToSpace (L1/L2 slice indices in Dixon)
%     opts        struct (optional):
%       .roiSaveDir   char    folder to save .roi files (default: pwd)
%       .subjectId    char    label for saved files
%       .verbose      logical
%
%   DISPLAY LAYOUT (2×2 grid):
%     ┌────────────────┬────────────────┐
%     │  L1 Water      │  L1 PDFF (%)   │
%     │  [draw ROIs]   │  [auto overlay]│
%     ├────────────────┼────────────────┤
%     │  L2 Water      │  L2 PDFF (%)   │
%     │  [draw ROIs]   │  [auto overlay]│
%     └────────────────┴────────────────┘
%
%   ROI TYPES (colour-coded)
%     Muscle (red)   — paraspinal + psoas muscle groups at that level
%     SAT    (blue)  — subcutaneous adipose tissue ring
%
%   HOTKEYS
%     m   — draw muscle ROI (freehand polygon) on current panel
%     s   — draw SAT ROI on current panel
%     c   — clear ROIs on current panel
%     1/2 — switch active level (L1 / L2)
%
%   OUTPUT RESULT struct:
%     .L1.MuscleArea_cm2    double
%     .L1.SATArea_cm2       double
%     .L1.MusclePDFF_pct    double   mean PDFF within muscle ROI
%     .L1.SAT_PDFF_pct      double   mean PDFF within SAT ROI
%     .L1.MuscleSATRatio    double   area ratio
%     .L1.MuscleROI         logical [nR×nC]
%     .L1.SATROI            logical [nR×nC]
%     .L2                   (same fields as L1)
%     .PixelSpacing_mm      [1×2]
%     .Confirmed            logical
%
%   SEE ALSO  seg_buildDixonVolume, loc_detectL1L2, loc_propagateToSpace
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 3, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'roiSaveDir', pwd, ...
        'subjectId',  'subject', ...
        'verbose',    true));

    result = initResult();

    % ── Validate inputs ───────────────────────────────────────────────
    if isempty(dixon.Water) && isempty(dixon.PDFF)
        error('seg_L1L2ROIGui:noData','Dixon volume is empty.');
    end

    nZ    = max(size(dixon.Water,3), size(dixon.PDFF,3));
    L1_sl = max(1, min(nZ, round(L12_dixon.L1_sliceIdx)));
    L2_sl = max(1, min(nZ, round(L12_dixon.L2_sliceIdx)));

    if isnan(L1_sl), L1_sl = max(1, round(nZ/2));   end
    if isnan(L2_sl), L2_sl = max(1, L1_sl+1);       end

    vprint(opts, 'L1→slice %d,  L2→slice %d  (of %d Dixon slices)', L1_sl, L2_sl, nZ);

    % ── Extract 2-D slices ────────────────────────────────────────────
    W_L1   = getSlice(dixon.Water,   L1_sl);
    W_L2   = getSlice(dixon.Water,   L2_sl);
    FF_L1  = getSlice(dixon.PDFF,    L1_sl);
    FF_L2  = getSlice(dixon.PDFF,    L2_sl);

    nR = size(W_L1, 1);
    nC = size(W_L1, 2);
    dx = dixon.PixelSpacing_mm(1);   % mm per pixel (row)
    dy = dixon.PixelSpacing_mm(2);   % mm per pixel (col)
    pixArea_cm2 = (dx * dy) / 100;   % mm² → cm²

    % ── ROI storage ───────────────────────────────────────────────────
    rois = struct( ...
        'L1_Muscle', [], 'L1_SAT', [], ...
        'L2_Muscle', [], 'L2_SAT', []);

    % ── Build figure ──────────────────────────────────────────────────
    fig = uifigure('Name', 'L1-L2 Body Composition ROI', ...
                   'Position', [60 60 1120 740], ...
                   'Resize', 'on');

    % Header label
    hdrLbl = uilabel(fig, ...
        'Text', sprintf('L1-L2 Body Composition  |  Subject: %s  |  L1=slice %d  L2=slice %d', ...
            opts.subjectId, L1_sl, L2_sl), ...
        'Position', [10 710 1100 22], ...
        'FontSize', 13, 'FontWeight', 'bold');  %#ok<NASGU>

    % 2×2 image grid
    panW = 500; panH = 320; gap = 10;
    startX = 10; startY = 360;
    panPos = { ...
        [startX,         startY,          panW, panH], ...  % L1 Water
        [startX+panW+gap,startY,          panW, panH], ...  % L1 PDFF
        [startX,         startY-panH-gap, panW, panH], ...  % L2 Water
        [startX+panW+gap,startY-panH-gap, panW, panH]};     % L2 PDFF

    panTitles = {'L1 — Water (anatomy)', 'L1 — PDFF (%)', ...
                 'L2 — Water (anatomy)', 'L2 — PDFF (%)'};
    panImages  = {W_L1, FF_L1, W_L2, FF_L2};
    cmaps      = {'gray','hot','gray','hot'};

    axArr = gobjects(1,4);
    for p = 1:4
        pnl = uipanel(fig, 'Position', panPos{p}, 'BorderType','line');
        ax  = uiaxes(pnl, 'Position', [2 2 panPos{p}(3)-4 panPos{p}(4)-24]);
        ax.XTick=[]; ax.YTick=[]; ax.Box='on';
        img = panImages{p};
        if isempty(img), img = zeros(nR,nC); end
        imagesc(ax, img); colormap(ax, cmaps{p}); axis(ax,'image');
        if strcmp(cmaps{p},'hot')
            clim(ax,[0 100]);
            colorbar(ax,'FontSize',9);
        end
        title(ax, panTitles{p}, 'FontSize',11);
        axArr(p) = ax;
    end

    % ── Instruction panel ─────────────────────────────────────────────
    instrPnl = uipanel(fig, 'Position',[10 10 1100 340], ...
        'Title','ROI Controls','FontSize',12,'FontWeight','bold');

    % ROI buttons — L1
    uilabel(instrPnl,'Text','L1 Level','Position',[10 290 200 22], ...
        'FontWeight','bold','FontSize',12);
    uibutton(instrPnl,'push','Text','Draw L1 Muscle (red)', ...
        'Position',[10 260 180 28],'FontSize',11, ...
        'BackgroundColor',[0.85 0.2 0.1],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) drawROI('L1_Muscle'));
    uibutton(instrPnl,'push','Text','Draw L1 SAT (blue)', ...
        'Position',[200 260 180 28],'FontSize',11, ...
        'BackgroundColor',[0.1 0.3 0.85],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) drawROI('L1_SAT'));
    uibutton(instrPnl,'push','Text','Clear L1 ROIs', ...
        'Position',[390 260 120 28],'FontSize',11, ...
        'ButtonPushedFcn',@(~,~) clearROIs('L1'));

    % ROI buttons — L2
    uilabel(instrPnl,'Text','L2 Level','Position',[10 220 200 22], ...
        'FontWeight','bold','FontSize',12);
    uibutton(instrPnl,'push','Text','Draw L2 Muscle (red)', ...
        'Position',[10 190 180 28],'FontSize',11, ...
        'BackgroundColor',[0.85 0.2 0.1],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) drawROI('L2_Muscle'));
    uibutton(instrPnl,'push','Text','Draw L2 SAT (blue)', ...
        'Position',[200 190 180 28],'FontSize',11, ...
        'BackgroundColor',[0.1 0.3 0.85],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) drawROI('L2_SAT'));
    uibutton(instrPnl,'push','Text','Clear L2 ROIs', ...
        'Position',[390 190 120 28],'FontSize',11, ...
        'ButtonPushedFcn',@(~,~) clearROIs('L2'));

    % Slice adjustment
    uilabel(instrPnl,'Text','Adjust L1 slice:','Position',[10 150 130 22],'FontSize',11);
    L1sldr = uislider(instrPnl,'Position',[150 158 200 3], ...
        'Limits',[1 nZ],'Value',L1_sl,'MajorTicks',[],'MinorTicks',[], ...
        'ValueChangedFcn',@(src,~) onSliceChange(src,'L1'));
    L1lbl  = uilabel(instrPnl,'Text',sprintf('%d',L1_sl), ...
        'Position',[360 150 50 22],'FontSize',11,'FontWeight','bold');

    uilabel(instrPnl,'Text','Adjust L2 slice:','Position',[10 110 130 22],'FontSize',11);
    L2sldr = uislider(instrPnl,'Position',[150 118 200 3], ...
        'Limits',[1 nZ],'Value',L2_sl,'MajorTicks',[],'MinorTicks',[], ...
        'ValueChangedFcn',@(src,~) onSliceChange(src,'L2'));
    L2lbl  = uilabel(instrPnl,'Text',sprintf('%d',L2_sl), ...
        'Position',[360 110 50 22],'FontSize',11,'FontWeight','bold');

    % Results display
    resultLbl = uilabel(instrPnl,'Text','Results will appear here after ROI placement.', ...
        'Position',[540 40 540 280],'FontSize',11,'WordWrap','on', ...
        'VerticalAlignment','top');

    % Finish & Cancel buttons
    uibutton(instrPnl,'push','Text','Finish & Compute', ...
        'Position',[10 10 180 36],'FontSize',13,'FontWeight','bold', ...
        'BackgroundColor',[0.18 0.60 0.34],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) onFinish());
    uibutton(instrPnl,'push','Text','Cancel', ...
        'Position',[200 10 80 36],'FontSize',12, ...
        'ButtonPushedFcn',@(~,~) onCancel());

    confirmed = false;

    % ── Wait for user ─────────────────────────────────────────────────
    uiwait(fig);

    % ── Compute results ───────────────────────────────────────────────
    if confirmed
        result = computeResult(rois, FF_L1, FF_L2, pixArea_cm2, nR, nC);
        result.Confirmed = true;
        saveROIs(result, opts);
        printResult(result, opts);
    end

    if isvalid(fig), close(fig); end

    % ==================================================================
    %  NESTED FUNCTIONS
    % ==================================================================

    function drawROI(roiName)
    % Draw a freehand ROI on the appropriate water-image axes.
        if contains(roiName,'L1')
            ax = axArr(1);   % L1 water panel
            img = W_L1;
        else
            ax = axArr(3);   % L2 water panel
            img = W_L2;
        end

        % Bring figure to foreground and use drawfreehand
        figure(fig);
        try
            h = drawfreehand(ax, 'Color', roiColor(roiName), ...
                             'LineWidth', 2, 'FaceAlpha', 0.15);
            wait(h);
            mask = createMask(h, nR, nC);
            rois.(roiName) = mask;
            updateResultDisplay();
            refreshOverlay(roiName, mask);
        catch ME
            % drawfreehand not available — fallback to drawpolygon
            try
                h = drawpolygon(ax, 'Color', roiColor(roiName), 'LineWidth', 2);
                wait(h);
                mask = createMask(h, nR, nC);
                rois.(roiName) = mask;
                updateResultDisplay();
                refreshOverlay(roiName, mask);
            catch ME2
                uialert(fig, ME2.message, 'ROI Error', 'Icon','error');
            end
        end
    end

    function refreshOverlay(roiName, mask)
    % Overlay ROI contour on both water and PDFF panels for this level.
        if contains(roiName,'L1'), axW=axArr(1); axFF=axArr(2);
        else,                      axW=axArr(3); axFF=axArr(4);
        end
        clr = roiColor(roiName);

        % Overlay contour on water panel
        hold(axW,'on');
        bnd = bwboundaries(mask);
        for b = 1:numel(bnd)
            plot(axW, bnd{b}(:,2), bnd{b}(:,1), '-', 'Color',clr, 'LineWidth',2);
        end
        hold(axW,'off');

        % Overlay on PDFF panel
        hold(axFF,'on');
        for b = 1:numel(bnd)
            plot(axFF, bnd{b}(:,2), bnd{b}(:,1), '-', 'Color',clr, 'LineWidth',2);
        end
        hold(axFF,'off');
    end

    function clearROIs(level)
        rois.([level '_Muscle']) = [];
        rois.([level '_SAT'])    = [];
        % Redraw images without overlays
        if strcmp(level,'L1')
            imagesc(axArr(1), W_L1);  colormap(axArr(1),'gray');
            imagesc(axArr(2), FF_L1); colormap(axArr(2),'hot'); clim(axArr(2),[0 100]);
        else
            imagesc(axArr(3), W_L2);  colormap(axArr(3),'gray');
            imagesc(axArr(4), FF_L2); colormap(axArr(4),'hot'); clim(axArr(4),[0 100]);
        end
        updateResultDisplay();
    end

    function onSliceChange(src, level)
        sl = round(src.Value);
        if strcmp(level,'L1')
            L1_sl = sl; L1lbl.Text = sprintf('%d',sl);
            W_L1  = getSlice(dixon.Water, sl);
            FF_L1 = getSlice(dixon.PDFF,  sl);
            imagesc(axArr(1), W_L1);  colormap(axArr(1),'gray');
            imagesc(axArr(2), FF_L1); colormap(axArr(2),'hot'); clim(axArr(2),[0 100]);
            rois.L1_Muscle = []; rois.L1_SAT = [];
        else
            L2_sl = sl; L2lbl.Text = sprintf('%d',sl);
            W_L2  = getSlice(dixon.Water, sl);
            FF_L2 = getSlice(dixon.PDFF,  sl);
            imagesc(axArr(3), W_L2);  colormap(axArr(3),'gray');
            imagesc(axArr(4), FF_L2); colormap(axArr(4),'hot'); clim(axArr(4),[0 100]);
            rois.L2_Muscle = []; rois.L2_SAT = [];
        end
        updateResultDisplay();
    end

    function updateResultDisplay()
    % Live-update the text result panel as ROIs are placed.
        lines = {};
        for lv = {'L1','L2'}
            lvl = lv{1};
            slN = eval([lvl '_sl']);
            lines{end+1} = sprintf('%s (slice %d):', lvl, slN); %#ok<AGROW>
            mRoi = rois.([lvl '_Muscle']);
            sRoi = rois.([lvl '_SAT']);

            if ~isempty(mRoi)
                mArea = sum(mRoi(:)) * pixArea_cm2;
                FF    = eval(['FF_' lvl]);
                mPDFF = nanmean(FF(mRoi));
                lines{end+1} = sprintf('  Muscle: %.1f cm²   PDFF: %.1f%%', mArea, mPDFF);
            else
                lines{end+1} = '  Muscle: (not drawn)';
            end

            if ~isempty(sRoi)
                sArea = sum(sRoi(:)) * pixArea_cm2;
                FF    = eval(['FF_' lvl]);
                sPDFF = nanmean(FF(sRoi));
                lines{end+1} = sprintf('  SAT:    %.1f cm²   PDFF: %.1f%%', sArea, sPDFF);
            else
                lines{end+1} = '  SAT: (not drawn)';
            end

            if ~isempty(mRoi) && ~isempty(sRoi)
                ratio = sum(mRoi(:)) / sum(sRoi(:));
                lines{end+1} = sprintf('  Muscle:SAT ratio = %.3f', ratio);
            end
            lines{end+1} = '';
        end
        resultLbl.Text = strjoin(lines, newline);
    end

    function onFinish()
        confirmed = true;
        uiresume(fig);
    end

    function onCancel()
        confirmed = false;
        uiresume(fig);
    end

end   % main function


% ======================================================================
%  RESULT COMPUTATION
% ======================================================================

function result = computeResult(rois, FF_L1, FF_L2, pixArea_cm2, nR, nC)
    result = initResult();
    result.PixelSpacing_mm = [sqrt(pixArea_cm2*100) sqrt(pixArea_cm2*100)];

    result.L1 = computeLevel(rois.L1_Muscle, rois.L1_SAT, FF_L1, pixArea_cm2, nR, nC);
    result.L2 = computeLevel(rois.L2_Muscle, rois.L2_SAT, FF_L2, pixArea_cm2, nR, nC);
end

function lv = computeLevel(muscleROI, satROI, FF, pixArea_cm2, nR, nC)
    lv = struct('MuscleArea_cm2',NaN,'SATArea_cm2',NaN,'MusclePDFF_pct',NaN, ...
                'SAT_PDFF_pct',NaN,'MuscleSATRatio',NaN, ...
                'MuscleROI',false(nR,nC),'SATROI',false(nR,nC));

    if ~isempty(muscleROI) && any(muscleROI(:))
        lv.MuscleROI      = muscleROI;
        lv.MuscleArea_cm2 = sum(muscleROI(:)) * pixArea_cm2;
        if ~isempty(FF)
            vals = FF(muscleROI);
            lv.MusclePDFF_pct = nanmean(vals(isfinite(vals)));
        end
    end

    if ~isempty(satROI) && any(satROI(:))
        lv.SATROI        = satROI;
        lv.SATArea_cm2   = sum(satROI(:)) * pixArea_cm2;
        if ~isempty(FF)
            vals = FF(satROI);
            lv.SAT_PDFF_pct = nanmean(vals(isfinite(vals)));
        end
    end

    if ~isnan(lv.MuscleArea_cm2) && ~isnan(lv.SATArea_cm2) && lv.SATArea_cm2 > 0
        lv.MuscleSATRatio = lv.MuscleArea_cm2 / lv.SATArea_cm2;
    end
end

function saveROIs(result, opts)
%SAVEROIS  Save ROI masks to .mat files for audit/re-analysis.
    savePath = fullfile(opts.roiSaveDir, ...
        sprintf('%s_L1L2_bodycomp.mat', opts.subjectId));
    try
        save(savePath, '-struct', 'result', '-v7.3');
        fprintf('[seg_L1L2ROIGui] Saved: %s\n', savePath);
    catch
        warning('seg_L1L2ROIGui:saveFail','Could not save ROI file: %s', savePath);
    end
end

function printResult(result, opts)
    if ~isfield(opts,'verbose') || ~opts.verbose, return; end
    fprintf('\n=== L1-L2 Body Composition Results ===\n');
    for lv = {'L1','L2'}
        lvl = lv{1}; r = result.(lvl);
        fprintf('%s:\n', lvl);
        fprintf('  Muscle area:    %.2f cm²\n',  r.MuscleArea_cm2);
        fprintf('  SAT area:       %.2f cm²\n',  r.SATArea_cm2);
        fprintf('  Muscle PDFF:    %.1f %%\n',   r.MusclePDFF_pct);
        fprintf('  SAT PDFF:       %.1f %%\n',   r.SAT_PDFF_pct);
        fprintf('  Muscle:SAT ratio: %.3f\n',    r.MuscleSATRatio);
    end
end


% ======================================================================
%  UTILITIES
% ======================================================================

function clr = roiColor(roiName)
    if contains(roiName,'Muscle'), clr = [1 0.2 0.1];   % red
    else,                          clr = [0.1 0.3 0.9];  % blue
    end
end

function img = getSlice(vol, sl)
    if isempty(vol)
        img = [];
    else
        sl  = max(1, min(size(vol,3), sl));
        img = double(vol(:,:,sl));
    end
end

function mask = createMask(h, nR, nC)
    try
        mask = h.createMask();
    catch
        % Fallback for older MATLAB
        pos  = h.Position;
        mask = poly2mask(pos(:,1), pos(:,2), nR, nC);
    end
    mask = logical(mask);
end

function result = initResult()
    emptyLevel = struct('MuscleArea_cm2',NaN,'SATArea_cm2',NaN, ...
                        'MusclePDFF_pct',NaN,'SAT_PDFF_pct',NaN, ...
                        'MuscleSATRatio',NaN,'MuscleROI',[],'SATROI',[]);
    result = struct('L1',emptyLevel,'L2',emptyLevel, ...
                    'PixelSpacing_mm',[1 1],'Confirmed',false);
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k}), opts.(fields{k}) = defaults.(fields{k}); end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[seg_L1L2ROIGui] ' fmt '\n'], varargin{:});
    end
end

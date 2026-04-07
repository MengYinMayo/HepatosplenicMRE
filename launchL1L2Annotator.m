function S = launchL1L2Annotator(S, varargin)
% LAUNCHL1L2ANNOTATOR  Interactive GUI for L1-L2 level confirmation.
%
%   Displays sagittal scout with detected disc candidates overlaid.
%   User drags L1 superior and L2 inferior endplate lines to confirm.
%   Stores confirmed z-positions in S.landmarks.L1L2.

    p = inputParser();
    addParameter(p, 'ParentAxes', [], @(x) isa(x,'matlab.graphics.axis.Axes'));
    parse(p, varargin{:});
    opts = p.Results;

    [sagImg, sagHdr, scoutAffine] = identifySagittalScout(S);
    candidates = detectVertebralCandidates(sagImg, sagHdr, 'Verbose', false);

    % --- Build figure if no parent axes provided ---
    if isempty(opts.ParentAxes)
        fig = uifigure('Name', 'L1-L2 Vertebral Level Confirmation', ...
                       'Position', [100 100 700 600]);
        gl  = uigridlayout(fig, [2 2], ...
              'RowHeight',{'1x', 40}, 'ColumnWidth', {'1x', 200});
        ax  = uiaxes(gl); ax.Layout.Row = 1; ax.Layout.Column = 1;
    else
        ax  = opts.ParentAxes;
        fig = ax.Parent;
    end

    % --- Display sagittal scout ---
    % Normalize to [0,1] for display
    imgDisp = (sagImg - min(sagImg(:))) / (max(sagImg(:)) - min(sagImg(:)));
    imshow(imgDisp, [], 'Parent', ax);
    ax.YDir = 'normal';   % superior = top
    hold(ax, 'on');

    ps = getHeaderField(sagHdr, 'PixelSpacing', [1;1]);

    % Convert z_mm to row index for display
    function row = zToRow(z_mm, candidates)
        [~, idx] = min(abs(candidates.zPerRow - z_mm));
        row = idx;
    end

    % --- Overlay detected disc candidates ---
    if candidates.nDiscs > 0
        for d = 1:numel(candidates.sortedDiscRowIdx)
            rowD = candidates.sortedDiscRowIdx(d);
            yline(ax, rowD, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.8, ...
                  'Label', candidates.levelLabels{d}, ...
                  'LabelHorizontalAlignment', 'right', 'FontSize', 9);
        end
    end

    % --- Draggable L1 superior endplate line ---
    if ~isnan(candidates.L1_sup_z_estimated)
        initRowL1 = zToRow(candidates.L1_sup_z_estimated, candidates);
        initRowL2 = zToRow(candidates.L2_inf_z_estimated, candidates);
    else
        % Default: place in middle of image if no candidates
        initRowL1 = round(size(sagImg,1) * 0.4);
        initRowL2 = round(size(sagImg,1) * 0.6);
    end

    lineL1 = yline(ax, initRowL1, '-', 'Color', [0.09 0.43 0.33], ...
                   'LineWidth', 2, 'Label', 'L1 sup.', ...
                   'LabelHorizontalAlignment', 'left', 'FontSize', 10, ...
                   'LabelColor', [0.09 0.43 0.33]);
    lineL2 = yline(ax, initRowL2, '-', 'Color', [0.10 0.37 0.65], ...
                   'LineWidth', 2, 'Label', 'L2 inf.', ...
                   'LabelHorizontalAlignment', 'left', 'FontSize', 10, ...
                   'LabelColor', [0.10 0.37 0.65]);

    title(ax, 'Sagittal scout — drag L1 / L2 lines to confirm level', ...
          'FontSize', 11, 'FontWeight', 'normal');
    xlabel(ax, 'A-P (px)'); ylabel(ax, 'S-I (px)');

    % --- Info panel ---
    infoPanel = uipanel(gl, 'Title', 'L1-L2 slab');
    infoPanel.Layout.Row = 1; infoPanel.Layout.Column = 2;
    infoGL = uigridlayout(infoPanel, [6 1], 'RowHeight', repmat({30},1,6));

    lblL1 = uilabel(infoGL, 'Text', sprintf('L1 sup z: %.1f mm', candidates.L1_sup_z_estimated));
    lblL2 = uilabel(infoGL, 'Text', sprintf('L2 inf z: %.1f mm', candidates.L2_inf_z_estimated));
    lblThk = uilabel(infoGL, 'Text', 'Slab thickness: — mm');
    lblConf = uilabel(infoGL, 'Text', 'Status: unconfirmed', 'FontColor', [0.64 0.17 0.17]);

    % Adjust button (allows fine numeric entry)
    adjustBtn = uibutton(infoGL, 'Text', 'Enter Z manually', ...
        'ButtonPushedFcn', @(~,~) enterManualZ());

    % Confirm button
    confirmBtn = uibutton(infoGL, 'Text', 'Confirm and close', ...
        'BackgroundColor', [0.09 0.43 0.33], 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) confirmL1L2());

    % --- Callbacks ---
    % Update info panel when lines are dragged (requires R2020b+ for interactive yline)
    addlistener(lineL1, 'Value', 'PostSet', @(~,~) updateInfoPanel());
    addlistener(lineL2, 'Value', 'PostSet', @(~,~) updateInfoPanel());

    function updateInfoPanel()
        rowL1 = round(lineL1.Value);
        rowL2 = round(lineL2.Value);
        rowL1 = max(1, min(size(sagImg,1), rowL1));
        rowL2 = max(1, min(size(sagImg,1), rowL2));
        z1 = candidates.zPerRow(rowL1);
        z2 = candidates.zPerRow(rowL2);
        zSup = max(z1, z2);
        zInf = min(z1, z2);
        lblL1.Text  = sprintf('L1 sup z: %.1f mm', zSup);
        lblL2.Text  = sprintf('L2 inf z: %.1f mm', zInf);
        lblThk.Text = sprintf('Slab thickness: %.1f mm', zSup - zInf);
        lblConf.Text = 'Status: unconfirmed'; lblConf.FontColor = [0.64 0.17 0.17];
    end

    function enterManualZ()
        answer = inputdlg({'L1 superior endplate z (mm)', 'L2 inferior endplate z (mm)'}, ...
                          'Manual z entry', 1, ...
                          {num2str(candidates.L1_sup_z_estimated, '%.1f'), ...
                           num2str(candidates.L2_inf_z_estimated, '%.1f')});
        if isempty(answer), return; end
        zL1 = str2double(answer{1});
        zL2 = str2double(answer{2});
        lineL1.Value = zToRow(zL1, candidates);
        lineL2.Value = zToRow(zL2, candidates);
        updateInfoPanel();
    end

    function confirmL1L2()
        rowL1 = round(lineL1.Value);
        rowL2 = round(lineL2.Value);
        z1 = candidates.zPerRow(max(1, min(size(sagImg,1), rowL1)));
        z2 = candidates.zPerRow(max(1, min(size(sagImg,1), rowL2)));

        S.landmarks.L1L2.L1_sup_z_mm       = max(z1, z2);
        S.landmarks.L1L2.L2_inf_z_mm       = min(z1, z2);
        S.landmarks.L1L2.slab_thickness_mm  = abs(z1 - z2);
        S.landmarks.L1L2.scoutPixelRow_L1   = rowL1;
        S.landmarks.L1L2.scoutPixelRow_L2   = rowL2;
        S.landmarks.L1L2.defined            = true;
        S.landmarks.L1L2.method             = 'semi-auto';

        lblConf.Text = 'Status: confirmed'; lblConf.FontColor = [0.09 0.43 0.33];
        fprintf('[L1-L2] Slab confirmed: z=[%.1f, %.1f] mm, thickness=%.1f mm\n', ...
            S.landmarks.L1L2.L2_inf_z_mm, S.landmarks.L1L2.L1_sup_z_mm, ...
            S.landmarks.L1L2.slab_thickness_mm);

        pause(0.8);
        if isvalid(fig) && isempty(opts.ParentAxes)
            close(fig);
        end
    end

    % Block until figure is closed (modal behavior)
    if isempty(opts.ParentAxes)
        uiwait(fig);
    end
end
function L12 = loc_detectL1L2(localizer, opts)
% LOC_DETECTL1L2  Detect L1 and L2 vertebral levels from the 3-plane localizer.
%
%   L12 = LOC_DETECTL1L2(LOCALIZER) analyzes the coronal and sagittal planes
%   of the localizer struct (from loc_loadLocalizer) to automatically identify
%   the L1 and L2 vertebral body positions in patient mm coordinates.
%
%   ALGORITHM
%     1. Select the most informative plane (coronal preferred, then sagittal).
%     2. Compute a vertical intensity profile: mean intensity per row.
%     3. Intervertebral discs appear as dark horizontal bands on SSFSE.
%        Vertebral bodies appear bright. Detect alternating pattern.
%     4. Identify peaks (vertebral bodies) in the profile using findpeaks.
%     5. Count from sacrum/L5 upward:
%        - L5/S1 junction = lowest distinct disc space
%        - L4 = first vertebra above L5
%        - L3 = second
%        - L2 = third
%        - L1 = fourth
%     6. Convert row indices → superior–inferior mm positions.
%     7. Provide interactive correction: display detected levels on image,
%        allow user to drag lines to correct.
%
%   OUTPUT STRUCT (L12):
%     .L1_mm           double  superior-inferior position of L1 midpoint (mm)
%     .L2_mm           double  superior-inferior position of L2 midpoint (mm)
%     .L1_L2_mid_mm    double  midpoint between L1 and L2 (mm)
%     .L1_row_coronal  double  row index in coronal localizer image
%     .L2_row_coronal  double  row index in coronal localizer image
%     .DetectionMethod char    'auto' | 'manual' | 'manual_correction'
%     .Confidence      double  0-1 confidence of automatic detection
%     .SourcePlane     char    'Coronal' | 'Sagittal'
%     .PixelSpacing_mm [1×2]   [rowSpacing colSpacing] of source image
%
%   OPTS fields:
%     .interactive     logical  show image with detected levels, allow correction
%                              (default: true)
%     .verbose         logical  (default: true)
%     .minPeakProminence double  minimum prominence for vertebra detection
%                               (default: auto-estimated from image)
%
%   SEE ALSO  loc_loadLocalizer, loc_propagateToSpace
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'interactive',        true, ...
        'verbose',            true, ...
        'minPeakProminence',  []));

    L12 = initL12Struct();

    % ------------------------------------------------------------------
    % 1.  Select best plane: prefer coronal (clearest vertebral column)
    % ------------------------------------------------------------------
    [planeName, planeData, pixSpacing] = selectBestPlane(localizer);

    if isempty(planeData)
        warning('loc_detectL1L2:noData', ...
            'No usable localizer plane found. Returning empty L12.');
        return
    end

    L12.SourcePlane     = planeName;
    L12.PixelSpacing_mm = pixSpacing;

    vprint(opts, 'Using %s plane for vertebral detection (%d images)', ...
        planeName, size(planeData.Volume, 3));

    % ------------------------------------------------------------------
    % 2.  Use the central slice of the selected plane
    % ------------------------------------------------------------------
    vol   = planeData.Volume;
    nSl   = size(vol, 3);
    midSl = round(nSl / 2);
    img   = vol(:,:,midSl);   % [nRow × nCol]

    % ------------------------------------------------------------------
    % 3.  Compute superior-inferior intensity profile
    % ------------------------------------------------------------------
    % For coronal: rows correspond to superior-inferior axis
    % For sagittal: same (rows = sup-inf)
    % Vertebral bodies = bright rounded blobs, discs = dark gaps
    profile = mean(img, 2);   % [nRow × 1] mean intensity per row

    % Smooth profile to reduce noise
    profile_sm = smoothdata(profile, 'gaussian', max(3, round(size(img,1)/30)));

    % ------------------------------------------------------------------
    % 4.  Detect vertebral body peaks in profile
    % ------------------------------------------------------------------
    if isempty(opts.minPeakProminence)
        prom = 0.08 * (max(profile_sm) - min(profile_sm));
    else
        prom = opts.minPeakProminence;
    end

    [peakVals, peakLocs, ~, peakProm] = findpeaks(profile_sm, ...
        'MinPeakProminence', prom, ...
        'MinPeakDistance',   max(5, round(size(img,1)/20)));

    nPeaks = numel(peakLocs);
    vprint(opts, 'Detected %d vertebral body candidates.', nPeaks);

    if nPeaks < 2
        warning('loc_detectL1L2:tooFewPeaks', ...
            'Fewer than 2 peaks found (nPeaks=%d). Detection unreliable.', nPeaks);
        L12.Confidence      = 0;
        L12.DetectionMethod = 'failed';
        if opts.interactive
            L12 = manualL12Selection(img, planeData, pixSpacing, L12, opts);
        end
        return
    end

    % Sort peaks by row position (superior to inferior, i.e., small to large row)
    [peakLocs, sortIdx] = sort(peakLocs, 'ascend');
    peakVals = peakVals(sortIdx); %#ok<NASGU>
    peakProm = peakProm(sortIdx);

    % ------------------------------------------------------------------
    % 5.  Count vertebrae from inferior end (L5→L1)
    % ------------------------------------------------------------------
    % The inferior-most peaks are L5, L4, L3, L2, L1 (in ascending row order
    % for coronal plane where rows go from superior-top to inferior-bottom).
    % On SSFSE coronal localizer: superior = small row index, inferior = large.
    %
    % Strategy: take the bottom 5 peaks (most likely lumbar vertebrae L5-L1).
    % L1 = 4th from bottom, L2 = 3rd from bottom (0-indexed from bottom).

    if nPeaks >= 5
        lumbarPeaks = peakLocs(end-4:end);  % bottom 5 = L5,L4,L3,L2,L1
        confidence  = min(1, mean(peakProm(end-4:end)) / ...
                         (max(peakProm) + eps));
    elseif nPeaks >= 4
        lumbarPeaks = peakLocs(end-3:end);
        confidence  = 0.7;
    elseif nPeaks >= 2
        lumbarPeaks = peakLocs;
        confidence  = 0.4;
    else
        lumbarPeaks = peakLocs;
        confidence  = 0.2;
    end

    nLP = numel(lumbarPeaks);

    % L1 = most superior of lumbar peaks, L2 = one below L1
    L1_row = lumbarPeaks(1);                     % most superior (smallest row)
    L2_row = lumbarPeaks(min(2, nLP));           % next inferior

    % ------------------------------------------------------------------
    % 6.  Convert row → mm position
    % ------------------------------------------------------------------
    rowSpacing = pixSpacing(1);   % mm per row
    sliceLocs  = planeData.SliceLocations;   % physical positions of slices

    % Determine direction: coronal locs go from posterior to anterior
    % Superior-inferior coordinate is encoded in row pixels
    % Use ImagePositionPatient of this slice to get the S-I offset
    imgPos = planeData.ImagePositions(midSl, :);  % [X Y Z] in mm

    % For coronal plane: row direction is typically inferior→superior (or reverse)
    % The row direction cosine is in ImageOrientationPatient[1:3]
    if isfield(planeData.SpatialInfo, 'ImageOrientationPatient') && ...
       ~isempty(planeData.SpatialInfo.ImageOrientationPatient)
        iop = planeData.SpatialInfo.ImageOrientationPatient;
        rowDir = iop(1:3);
    else
        rowDir = [0 0 -1];  % assume coronal default
    end

    % Position of row k: imgPos + (k-1) × rowSpacing × rowDir
    L1_pos_mm = imgPos + (L1_row - 1) * rowSpacing * rowDir;
    L2_pos_mm = imgPos + (L2_row - 1) * rowSpacing * rowDir;

    L12.L1_mm          = L1_pos_mm(3);    % Z (superior-inferior) component
    L12.L2_mm          = L2_pos_mm(3);
    L12.L1_L2_mid_mm   = (L12.L1_mm + L12.L2_mm) / 2;
    L12.L1_row_coronal = L1_row;
    L12.L2_row_coronal = L2_row;
    L12.Confidence     = confidence;
    L12.DetectionMethod = 'auto';

    vprint(opts, 'L1 detected: row=%d  Z=%.1f mm', L1_row, L12.L1_mm);
    vprint(opts, 'L2 detected: row=%d  Z=%.1f mm', L2_row, L12.L2_mm);
    vprint(opts, 'Confidence: %.2f', confidence);

    % ------------------------------------------------------------------
    % 7.  Interactive correction
    % ------------------------------------------------------------------
    if opts.interactive
        L12 = interactiveCorrection(img, L1_row, L2_row, ...
            planeData, pixSpacing, L12, opts);
    end
end


% ======================================================================
%  INTERACTIVE CORRECTION
% ======================================================================

function L12 = interactiveCorrection(img, L1_row, L2_row, planeData, pixSpacing, L12, opts)
%INTERACTIVECORRECTION  Display detected levels with draggable lines.

    fig = figure('Name', 'L1-L2 Level Verification', ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'figure', ...
                 'Units', 'normalized', ...
                 'Position', [0.1 0.1 0.5 0.8]);

    ax = axes(fig);
    imagesc(ax, img);
    colormap(ax, 'gray');
    axis(ax, 'image');
    title(ax, sprintf('L1-L2 Detection (confidence=%.2f)\nDrag lines to correct — then press ENTER or close', ...
        L12.Confidence), 'FontSize', 12);

    nCols = size(img, 2);
    hold(ax, 'on');

    % Draw draggable lines for L1 and L2
    hL1 = drawline(ax, 'Position', [1 L1_row; nCols L1_row], ...
        'Color', [1 0.3 0.1], 'LineWidth', 2, 'Label', 'L1');
    hL2 = drawline(ax, 'Position', [1 L2_row; nCols L2_row], ...
        'Color', [0.1 0.7 1.0], 'LineWidth', 2, 'Label', 'L2');

    legend(ax, {'L1 (orange)','L2 (blue)'}, 'Location','northeast');
    colorbar(ax);

    % Wait for user
    try
        uiwait(fig);
    catch
    end

    % Read final positions
    if isvalid(hL1)
        newL1row = round(mean(hL1.Position(:,2)));
    else
        newL1row = L1_row;
    end
    if isvalid(hL2)
        newL2row = round(mean(hL2.Position(:,2)));
    else
        newL2row = L2_row;
    end

    if ishandle(fig), close(fig); end

    % Update L12
    rowSpacing = pixSpacing(1);
    imgPos     = planeData.ImagePositions(round(size(planeData.Volume,3)/2), :);
    iop        = planeData.SpatialInfo.ImageOrientationPatient;
    rowDir     = iop(1:3);

    L1_pos = imgPos + (newL1row - 1) * rowSpacing * rowDir;
    L2_pos = imgPos + (newL2row - 1) * rowSpacing * rowDir;

    changed = (newL1row ~= L1_row) || (newL2row ~= L2_row);
    if changed
        L12.DetectionMethod = 'manual_correction';
        vprint(opts, 'User corrected: L1 row %d→%d, L2 row %d→%d', ...
            L1_row, newL1row, L2_row, newL2row);
    end

    L12.L1_mm          = L1_pos(3);
    L12.L2_mm          = L2_pos(3);
    L12.L1_L2_mid_mm   = (L12.L1_mm + L12.L2_mm) / 2;
    L12.L1_row_coronal = newL1row;
    L12.L2_row_coronal = newL2row;
end

function L12 = manualL12Selection(img, planeData, pixSpacing, L12, opts)
%MANUALL12SELECTION  Fully manual selection when auto-detection fails.

    uialert([], ...
        'Automatic detection failed. Please click on L1 and L2 vertebral bodies.', ...
        'Manual L1-L2 Selection', 'Icon','warning');

    fig = figure('Name','Manual L1-L2 Selection','NumberTitle','off');
    ax  = axes(fig);
    imagesc(ax, img); colormap(ax,'gray'); axis(ax,'image');
    title(ax, 'Click L1 center, then L2 center. Press Enter when done.');

    pts = ginput(2);
    close(fig);

    if size(pts,1) < 2
        vprint(opts,'Manual selection cancelled.');
        return
    end

    L1_row = round(pts(1,2));
    L2_row = round(pts(2,2));

    rowSpacing = pixSpacing(1);
    imgPos = planeData.ImagePositions(round(size(planeData.Volume,3)/2),:);
    iop    = planeData.SpatialInfo.ImageOrientationPatient;
    rowDir = iop(1:3);

    L1_pos = imgPos + (L1_row - 1) * rowSpacing * rowDir;
    L2_pos = imgPos + (L2_row - 1) * rowSpacing * rowDir;

    L12.L1_mm          = L1_pos(3);
    L12.L2_mm          = L2_pos(3);
    L12.L1_L2_mid_mm   = (L12.L1_mm + L12.L2_mm) / 2;
    L12.L1_row_coronal = L1_row;
    L12.L2_row_coronal = L2_row;
    L12.Confidence     = 1.0;
    L12.DetectionMethod = 'manual';
end


% ======================================================================
%  UTILITIES
% ======================================================================

function [planeName, planeData, pixSpacing] = selectBestPlane(localizer)
    % Prefer coronal (clearest sagittal view of vertebral column)
    % Fall back to sagittal
    preference = {'Coronal', 'Sagittal', 'Axial'};
    planeName  = '';
    planeData  = [];
    pixSpacing = [1 1];

    for k = 1:numel(preference)
        p = preference{k};
        if isfield(localizer, p) && ~isempty(localizer.(p).Volume)
            planeName = p;
            planeData = localizer.(p);
            if isfield(planeData.SpatialInfo,'PixelSpacing') && ...
               ~isempty(planeData.SpatialInfo.PixelSpacing)
                pixSpacing = double(planeData.SpatialInfo.PixelSpacing(:)');
            end
            return
        end
    end
end

function L12 = initL12Struct()
    L12 = struct( ...
        'L1_mm',           NaN, ...
        'L2_mm',           NaN, ...
        'L1_L2_mid_mm',    NaN, ...
        'L1_row_coronal',  NaN, ...
        'L2_row_coronal',  NaN, ...
        'Confidence',      0, ...
        'DetectionMethod', 'none', ...
        'SourcePlane',     '', ...
        'PixelSpacing_mm', [1 1]);
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k})
            opts.(fields{k}) = defaults.(fields{k});
        end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[loc_detectL1L2] ' fmt '\n'], varargin{:});
    end
end

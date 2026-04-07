function candidates = detectVertebralCandidates(sagImg, sagHdr, varargin)
% DETECTVERTEBRALCANDIDATES  Find disc-space candidates on a sagittal scout.
%
%   Returns candidates struct with estimated z-positions (mm) and
%   pixel row positions for each detected disc space.

    p = inputParser();
    addParameter(p, 'SmoothSigma',   4,    @isnumeric);  % pixels
    addParameter(p, 'MinDiscGap_mm', 25,   @isnumeric);  % minimum inter-disc spacing
    addParameter(p, 'Verbose',       true, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    [nRows, nCols] = size(sagImg);
    ps  = getHeaderField(sagHdr, 'PixelSpacing', [1;1]);
    ipp = getHeaderField(sagHdr, 'ImagePositionPatient', [0;0;0]);
    iop = getHeaderField(sagHdr, 'ImageOrientationPatient', [1;0;0;0;1;0]);

    % --- 1D projection along cranio-caudal direction ---
    % Sum intensity across all columns (A-P direction)
    profile1D = mean(sagImg, 2);    % [nRows x 1]

    % Gaussian smoothing to suppress noise
    profile1D = imgaussfilt(profile1D, opts.SmoothSigma);

    % Physical z-coordinate for each row (project IPP + row*colDir onto SI axis)
    SI_axis = [0; 0; 1];    % superior-inferior in LPS
    colDir  = iop(4:6);     % column direction cosine (direction of increasing row)
    zPerRow = zeros(nRows, 1);
    for r = 1:nRows
        physPt  = ipp + (r-1) * ps(1) * colDir;
        zPerRow(r) = dot(physPt, SI_axis);
    end
    % Ensure cranio-caudal ordering (superior = smaller index)
    if zPerRow(1) < zPerRow(end)
        profile1D = flipud(profile1D);
        zPerRow   = flipud(zPerRow);
    end

    % --- Minimum disc gap in pixels ---
    mmPerPixel    = abs(zPerRow(2) - zPerRow(1));
    minGap_pixels = max(3, round(opts.MinDiscGap_mm / mmPerPixel));

    % --- Find local minima (disc spaces) ---
    [~, minLocs] = findpeaks(-profile1D, ...
        'MinPeakProminence', 0.03 * range(profile1D), ...
        'MinPeakDistance',   minGap_pixels);

    nDiscs = numel(minLocs);

    if opts.Verbose
        fprintf('[Vertebral] Detected %d disc-space candidates\n', nDiscs);
    end

    % --- Store candidates ---
    candidates.nDiscs        = nDiscs;
    candidates.discRowIdx    = minLocs;           % row on sagittal image (1-based)
    candidates.discZ_mm      = zPerRow(minLocs);  % physical z in LPS mm
    candidates.profile1D     = profile1D;
    candidates.zPerRow       = zPerRow;
    candidates.mmPerPixel    = mmPerPixel;

    % Estimate lumbar levels from bottom (L5-S1 = bottommost disc in FOV)
    % Label from bottom up: L5-S1, L4-L5, L3-L4, L2-L3, L1-L2, T12-L1
    % Note: user must confirm — this is a heuristic only
    if nDiscs >= 2
        sortedLocs = sort(minLocs, 'descend');   % most caudal first
        levelLabels = {'L5-S1','L4-L5','L3-L4','L2-L3','L1-L2','T12-L1','T11-T12'};
        candidates.levelLabels = cell(nDiscs, 1);
        for d = 1:nDiscs
            if d <= numel(levelLabels)
                candidates.levelLabels{d} = levelLabels{d};
            else
                candidates.levelLabels{d} = sprintf('Disc-%d', d);
            end
        end
        candidates.sortedDiscRowIdx = sortedLocs;
        candidates.sortedDiscZ_mm   = zPerRow(sortedLocs);
    end

    % Estimate L1 superior endplate and L2 inferior endplate
    % L1-L2 disc is the 5th from caudal end (index 5 in sortedLocs)
    % L1 sup. endplate is half a vertebral body above L1-L2 disc
    % L2 inf. endplate is half a vertebral body below L1-L2 disc
    % Approximate vertebral body height ≈ 25-30mm in adults
    approxVBheight_mm = 28;

    if nDiscs >= 5
        l1l2DiscZ = candidates.sortedDiscZ_mm(5);
        candidates.L1_sup_z_estimated = l1l2DiscZ + approxVBheight_mm / 2;
        candidates.L2_inf_z_estimated = l1l2DiscZ - approxVBheight_mm / 2;
        candidates.L1L2_confidence    = 'low';   % always low until user confirms
        if opts.Verbose
            fprintf('[Vertebral] Estimated L1-L2 slab: z=[%.1f, %.1f] mm (needs confirmation)\n', ...
                candidates.L2_inf_z_estimated, candidates.L1_sup_z_estimated);
        end
    else
        candidates.L1_sup_z_estimated = NaN;
        candidates.L2_inf_z_estimated = NaN;
        candidates.L1L2_confidence    = 'insufficient_discs';
        warning('detectVertebralCandidates:tooFewDiscs', ...
            'Only %d disc spaces detected — manual annotation required.', nDiscs);
    end
end
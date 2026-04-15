function dixon = seg_buildDixonVolume(dixonGroup, opts)
% SEG_BUILDDIXONVOLUME  Load GE IDEAL-IQ series into an organised volume struct.
%
%   DIXON = SEG_BUILDDIXONVOLUME(DIXONGROUP) reads all IDEAL-IQ series in
%   DIXONGROUP (from mre_selectSeriesGUI) and returns a struct with named
%   image volumes and spatial metadata.
%
%   GE IDEAL-IQ SERIES ROLES
%     IDEALIQ_Raw    → Water image (single contrast, nSlices images)
%     IDEALIQ_Multi  → All contrasts stacked (nContrasts × nSlices images)
%                      Contrast order by TemporalPositionIdentifier:
%                        1=Water  2=Fat  3=In-Phase  4=Out-Phase
%                        5=PDFF(%)  6=T2*(ms) or R2*(1/s)
%     IDEALIQ_PDFF   → Fat-fraction map (may be subset of slices)
%     IDEALIQ_T2s    → T2* map
%
%   OUTPUT STRUCT fields:
%     .Water      [R×C×nZ]  double  water-only image
%     .Fat        [R×C×nZ]  double  fat-only image
%     .InPhase    [R×C×nZ]  double  in-phase (W+F)
%     .OutPhase   [R×C×nZ]  double  out-of-phase (W-F)
%     .PDFF       [R×C×nZ]  double  fat fraction 0-100 (%)
%     .T2star     [R×C×nZ]  double  T2* map (ms) — may be empty
%     .SpatialInfo struct           from io_extractSpatialInfo (Water series)
%     .nSlices    double
%     .PixelSpacing_mm [1×2]
%     .SliceThickness_mm double
%     .SliceLocations [1×nZ] mm    sorted inferior→superior
%
%   PDFF SCALING (GE IDEAL-IQ)
%     The raw PDFF DICOM pixels store integer values scaled relative to the
%     WindowCenter/Width. Typical GE convention: pixel value × scale → %.
%     This function returns PDFF as 0-100 (percent fat fraction).
%
%   SEE ALSO  mre_selectSeriesGUI, seg_L1L2ROIGui, loc_propagateToSpace
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    dixon = initDixonStruct();

    if isempty(dixonGroup)
        warning('seg_buildDixonVolume:empty','DixonGroup is empty.');
        return
    end

    % ── 1.  Find the best source series for each contrast ─────────────
    % Priority: IDEALIQ_Multi (has everything) > individual series
    multiSeries = findRole(dixonGroup, 'IDEALIQ_Multi');
    rawSeries   = findRole(dixonGroup, 'IDEALIQ_Raw');
    pdffSeries  = findRole(dixonGroup, 'IDEALIQ_PDFF');
    t2sSeries   = findRole(dixonGroup, 'IDEALIQ_T2s');
    waterSeries = findBestNamedSeries(dixonGroup, {'water'});
    fatSeries   = findBestNamedSeries(dixonGroup, {'fat'}, {'fatfrac','fat frac','pdff'});

    % ── 2.  Read multi-contrast series ────────────────────────────────
    if ~isempty(multiSeries)
        vprint(opts, 'Reading IDEAL-IQ multi-contrast: S%d  (%d files)', ...
            multiSeries(1).SeriesNumber, multiSeries(1).nImages);
        dixon = readMultiContrast(multiSeries(1), dixon, opts);
    end

    % ── 3.  Fill gaps from individual series ──────────────────────────
    % Resolve which rawSeries member is water vs fat for later use.
    % GE convention: water comes first (lower SeriesNumber) among IDEALIQ_Raw.
    usedWaterSN = 0;   % SeriesNumber of the raw series used for water
    if isempty(dixon.Water) && ~isempty(rawSeries)
        % Multiple IDEALIQ_Raw entries can exist when GE creates standalone
        % Water and Fat recons alongside the main multi-contrast series.
        % Prefer the one explicitly named 'water'; otherwise infer by excluding
        % any series whose description looks like fat, then fall back to the
        % first by SeriesNumber (GE convention: water before fat).
        waterRaw = findBestNamedSeries(rawSeries, {'water'}, {});
        if isempty(waterRaw)
            fatCandidate = findBestNamedSeries(rawSeries, {'fat'}, ...
                               {'water','fatfrac','fat frac','pdff'});
            for kk = 1:numel(rawSeries)
                if isempty(fatCandidate) || ...
                   rawSeries(kk).SeriesNumber ~= fatCandidate(1).SeriesNumber
                    waterRaw = rawSeries(kk);
                    break
                end
            end
            if isempty(waterRaw), waterRaw = rawSeries(1); end
        end
        vprint(opts, 'Reading water from: S%d', waterRaw(1).SeriesNumber);
        usedWaterSN = double(waterRaw(1).SeriesNumber);
        dixon.Water = readSingleContrast(waterRaw(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, waterRaw(1).Files);
        end
    end

    % If rawSeries contains a standalone fat recon, extract it now.
    if isempty(dixon.Fat) && numel(rawSeries) > 1
        fatFromRaw = findBestNamedSeries(rawSeries, {'fat'}, ...
                         {'water','fatfrac','fat frac','pdff'});
        if isempty(fatFromRaw)
            % GE convention: second IDEALIQ_Raw by SeriesNumber is fat.
            % Use whichever rawSeries member was not used for water.
            for kk = 1:numel(rawSeries)
                if double(rawSeries(kk).SeriesNumber) ~= usedWaterSN
                    fatFromRaw = rawSeries(kk);
                    break
                end
            end
        end
        if ~isempty(fatFromRaw)
            vprint(opts, 'Reading fat from rawSeries: S%d', fatFromRaw(1).SeriesNumber);
            dixon.Fat = readSingleContrast(fatFromRaw(1).Files, opts);
        end
    end

    if isempty(dixon.PDFF) && ~isempty(pdffSeries)
        vprint(opts, 'Reading PDFF from: S%d  (%d files)', ...
            pdffSeries(1).SeriesNumber, pdffSeries(1).nImages);
        [dixon.PDFF, pdffInfo] = readPDFFSeries(pdffSeries(1), opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon.SpatialInfo = pdffInfo;
        end
    end

    % Fill explicit WATER/FAT single-contrast recons when present.
    if isempty(dixon.Water) && ~isempty(waterSeries)
        vprint(opts, 'Reading explicit WATER from: S%d', waterSeries(1).SeriesNumber);
        dixon.Water = readSingleContrast(waterSeries(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, waterSeries(1).Files);
        end
    end

    if isempty(dixon.Fat) && ~isempty(fatSeries)
        vprint(opts, 'Reading explicit FAT from: S%d', fatSeries(1).SeriesNumber);
        dixon.Fat = readSingleContrast(fatSeries(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, fatSeries(1).Files);
        end
    end

    % ── 3b. Conventional IP/OP series (EchoTime-based split) ─────────────
    % When InPhase and OutPhase are still absent, look for an IP/OP Dixon
    % series in the group and split it by EchoTime:
    %   shorter TE → Out-of-Phase (OP),  longer TE → In-Phase (IP).
    % Water and Fat are then derived from IP and OP in the next block.
    if isempty(dixon.InPhase) && isempty(dixon.OutPhase)
        ipopSeries = findIPOPSeries(dixonGroup);
        if ~isempty(ipopSeries)
            vprint(opts, 'Reading conventional IP/OP from S%d using EchoTime...', ...
                   ipopSeries(1).SeriesNumber);
            [ipVol, opVol] = readIPOPByEchoTime(ipopSeries(1), opts);
            if ~isempty(ipVol)
                dixon.InPhase = ipVol;
                if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
                    dixon = fillSpatialInfo(dixon, ipopSeries(1).Files);
                end
            end
            if ~isempty(opVol)
                dixon.OutPhase = opVol;
            end
        end
    end

    % Derive Water/Fat from InPhase/OutPhase when direct maps are unavailable.
    % For a standard GE Dixon acquisition:
    %   IP = Water + Fat,  OP = Water - Fat  (with same sign convention)
    % Therefore:  Water = (IP + OP) / 2,  Fat = (IP - OP) / 2.
    % For IDEAL-IQ or other acquisitions the echo times set the exact sign;
    % the (IP+OP)/2 formula is correct when OP = W-F (GE convention).
    % Clamp Fat to ≥ 0 to avoid negative values from noise.
    if (isempty(dixon.Water) || isempty(dixon.Fat)) && ...
       ~isempty(dixon.InPhase) && ~isempty(dixon.OutPhase)
        vprint(opts, 'Deriving Water/Fat from InPhase/OutPhase...');
        IP = double(dixon.InPhase);
        OP = double(dixon.OutPhase);
        if isempty(dixon.Water)
            dixon.Water = (IP + OP) / 2;
        end
        if isempty(dixon.Fat)
            dixon.Fat = max(0, (IP - OP) / 2);
        end
    end

    % For this platform's three-panel UI, WATER feeds the in-phase panel and
    % FAT feeds the out-of-phase panel when explicit InPhase/OutPhase images
    % are not available in the selected Dixon family.
    if isempty(dixon.InPhase) && ~isempty(dixon.Water)
        dixon.InPhase = dixon.Water;
    end
    if isempty(dixon.OutPhase) && ~isempty(dixon.Fat)
        dixon.OutPhase = dixon.Fat;
    end

    % Compute PDFF from Water/Fat if still missing
    if isempty(dixon.PDFF) && ~isempty(dixon.Water) && ~isempty(dixon.Fat)
        vprint(opts, 'Computing PDFF from Water+Fat...');
        W = double(dixon.Water); F = double(dixon.Fat);
        denom = W + F; denom(denom < eps) = 1;
        dixon.PDFF = 100 .* F ./ denom;
    end

    % ── 4.  Fill spatial info ─────────────────────────────────────────
    if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
        % Try from any available series
        for k = 1:numel(dixonGroup)
            if ~isempty(dixonGroup(k).Files)
                dixon = fillSpatialInfo(dixon, dixonGroup(k).Files);
                if isfield(dixon.SpatialInfo,'VoxelSize'), break; end
            end
        end
    end

    % ── 5.  Summary ───────────────────────────────────────────────────
    if ~isempty(dixon.Water)
        dixon.nSlices = size(dixon.Water, 3);
        if isfield(dixon.SpatialInfo,'VoxelSize')
            dixon.PixelSpacing_mm  = dixon.SpatialInfo.VoxelSize(1:2);
            dixon.SliceThickness_mm= dixon.SpatialInfo.SliceSpacing;
        end
    end

    vprint(opts, 'Dixon volumes loaded:');
    vprint(opts, '  Water:   %s', sizeStr(dixon.Water));
    vprint(opts, '  Fat:     %s', sizeStr(dixon.Fat));
    if ~isempty(dixon.PDFF)
        vprint(opts, '  PDFF:    %s  (range %.1f-%.1f%%)', ...
            sizeStr(dixon.PDFF), nanmin(dixon.PDFF(:)), nanmax(dixon.PDFF(:)));
    else
        vprint(opts, '  PDFF:    []');
    end
    vprint(opts, '  InPhase: %s', sizeStr(dixon.InPhase));
end


% ======================================================================
%  MULTI-CONTRAST READER
% ======================================================================

function dixon = readMultiContrast(series, dixon, opts)
%READMULTICONTRAST  Parse IDEAL-IQ multi-contrast series by TemporalPositionIdentifier.

    files  = series.Files;
    nFiles = numel(files);
    if nFiles == 0, return; end

    % Read all headers to get TemporalPositionIdentifier and SliceLocation
    vprint(opts, '  Reading %d headers...', nFiles);
    tempIds  = ones(1, nFiles);
    sliceLoc = zeros(1, nFiles);
    instNums = zeros(1, nFiles);

    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'TemporalPositionIdentifier') && ~isempty(info.TemporalPositionIdentifier)
                tempIds(k) = double(info.TemporalPositionIdentifier);
            end
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLoc(k) = double(info.SliceLocation);
            end
            if isfield(info,'InstanceNumber') && ~isempty(info.InstanceNumber)
                instNums(k) = double(info.InstanceNumber);
            end
        catch
            instNums(k) = k;
        end
    end

    % Determine nContrasts and nSlices.
    % TemporalPositionIdentifier may not be populated on all GE IDEAL-IQ
    % versions (all return 1). Fall back to NumberOfTemporalPositions tag,
    % then to unique slice count inversion, then to the GE standard of 6.
    nContrasts = numel(unique(tempIds));
    if nContrasts <= 1 && nFiles > 10
        % Try NumberOfTemporalPositions from first header
        try
            hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
            if isfield(hdr1,'NumberOfTemporalPositions') && ~isempty(hdr1.NumberOfTemporalPositions)
                nc = double(hdr1.NumberOfTemporalPositions);
                if nc > 1 && mod(nFiles, nc) == 0
                    nContrasts = nc;
                    vprint(opts, '  Using NumberOfTemporalPositions=%d for nContrasts.', nc);
                end
            end
        catch
        end
    end
    % Last resort: infer from unique slice locations
    if nContrasts <= 1
        nSlicesEst = numel(unique(sliceLoc));
        if nSlicesEst > 1 && mod(nFiles, nSlicesEst) == 0
            nContrasts = nFiles / nSlicesEst;
            vprint(opts, '  Inferred %d contrasts from %d unique slices.', nContrasts, nSlicesEst);
        else
            % GE IDEAL-IQ default: 6 contrasts
            nContrasts = 6;
            vprint(opts, '  Defaulting to %d contrasts (GE IDEAL-IQ standard).', nContrasts);
        end
    end
    % When TemporalPositionIdentifier was unreliable (all 1), assign by
    % ranking InstanceNumber within each unique SliceLocation.
    % This works for both contrast-interleaved and all-slices-per-contrast
    % storage orders used by different GE IDEAL-IQ software versions.
    if numel(unique(tempIds)) <= 1 && nContrasts > 1
        tempIds = assignContrastBySliceRank(sliceLoc, instNums, nContrasts);
        vprint(opts, '  TemporalPositionIdentifier absent — assigned contrast by within-slice InstanceNumber rank.');
    end

    nSlices    = round(nFiles / nContrasts);
    uniqueLocs = unique(sliceLoc);

    vprint(opts, '  Multi-contrast: %d contrasts × %d slices', nContrasts, nSlices);

    % Read spatial info from first file
    try
        hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
        dixon.SpatialInfo = io_extractSpatialInfo(files, hdr1, nSlices, nContrasts);
    catch
    end

    % Allocate volumes
    try
        img1 = double(dicomread(files{1}));
        nR   = size(img1, 1);
        nC   = size(img1, 2);
    catch
        nR = 256; nC = 256;
    end

    vols = zeros(nR, nC, nSlices, nContrasts, 'double');

    for k = 1:nFiles
        try
            pxData = double(dicomread(files{k}));
        catch
            continue
        end
        sl = find(uniqueLocs == sliceLoc(k), 1);
        tp = tempIds(k);
        if isempty(sl), sl = mod(floor((k-1)/nContrasts), nSlices)+1; end
        if tp < 1 || tp > nContrasts, tp = mod(k-1, nContrasts)+1; end
        vols(:,:,sl,tp) = pxData;
    end

    % Assign contrasts by TemporalPositionIdentifier
    % GE IDEAL-IQ standard order: 1=W 2=F 3=IP 4=OP 5=PDFF 6=T2*
    % But we verify by WindowCenter/Width of representative files
    contrastLabels = classifyContrastsByWindow(files, tempIds, nContrasts);

    for c = 1:nContrasts
        vol = vols(:,:,:,c);
        switch contrastLabels{c}
            case 'Water',    dixon.Water   = vol;
            case 'Fat',      dixon.Fat     = vol;
            case 'InPhase',  dixon.InPhase = vol;
            case 'OutPhase', dixon.OutPhase= vol;
            case 'PDFF'
                % Scale to 0-100%
                dixon.PDFF = scalePDFF(vol, files, tempIds, c);
            case 'T2star',   dixon.T2star  = vol;
        end
    end

    % Extract slice locations for this volume
    dixon.SliceLocations = sort(uniqueLocs(:)');
end

function labels = classifyContrastsByWindow(files, tempIds, nContrasts)
%CLASSIFYCONTRASTSBYWINDOW  Assign GE IDEAL-IQ contrast labels by TemporalPositionIdentifier.
%
%   GE IDEAL-IQ output order (verified on user's scanner):
%     1=InPhase  2=OutPhase  3=Water  4=Fat  5=PDFF(%)  6=T2*(ms)
%
%   Note: some GE versions swap Water/Fat with InPhase/OutPhase at positions 1-4.
%   We use WindowCenter heuristics to detect and correct misassignments.

    geOrder = {'InPhase','OutPhase','Water','Fat','PDFF','T2star'};

    % Start with GE standard order, trimmed/extended to nContrasts
    if nContrasts <= numel(geOrder)
        labels = geOrder(1:nContrasts);
    else
        labels = [geOrder, repmat({'Unknown'}, 1, nContrasts - numel(geOrder))];
    end

    % Verify PDFF position by WindowCenter heuristic
    % (only attempt if we can read at least one header per contrast)
    wcs = nan(1, nContrasts);
    for c = 1:nContrasts
        idx = find(tempIds == c, 1);
        if isempty(idx), continue; end
        try
            info = dicominfo(files{idx}, 'UseDictionaryVR', true);
            if isfield(info,'WindowCenter') && ~isempty(info.WindowCenter)
                wcs(c) = double(info.WindowCenter(1));
            end
        catch
        end
    end

    % Refine label assignments using WindowCenter heuristics:
    %   PDFF (%):   WC ≈ 20-60  (0-100% range → typical WC ~50)
    %   T2* (ms):   WC ≈ 15-50  (0-100 ms range)
    %   Anatomic (Water/Fat/IP/OP): WC >> 100
    % For each contrast, override the default label when WC strongly indicates
    % PDFF or T2*.
    for c = 1:nContrasts
        if isnan(wcs(c)), continue; end
        if wcs(c) >= 15 && wcs(c) <= 80
            % Low-range image — could be PDFF or T2*
            % Distinguish: T2* is usually position 6; PDFF is position 5.
            % Use geOrder position as tiebreaker; PDFF overrides if not already there.
            if ~strcmp(labels{c},'T2star') && ~strcmp(labels{c},'PDFF')
                labels{c} = 'PDFF';  % default low-range to PDFF
            end
        end
    end
end

function pdffVol = scalePDFF(rawVol, files, tempIds, c)
%SCALEPDFF  Convert raw PDFF pixels to 0-100 percent.
    % Find the WindowWidth to determine scale
    idx = find(tempIds == c, 1);
    scale = 1.0;
    if ~isempty(idx)
        try
            info = dicominfo(files{idx}, 'UseDictionaryVR', true);
            if isfield(info,'RescaleSlope') && ~isempty(info.RescaleSlope)
                scale = double(info.RescaleSlope);
            end
        catch
        end
    end
    pdffVol = double(rawVol) .* scale;
    % Clamp to 0-100
    pdffVol = max(0, min(100, pdffVol));
end


% ======================================================================
%  SINGLE CONTRAST READER
% ======================================================================

function vol = readSingleContrast(files, opts)
%READSINGLECONTRAST  Read all files in a single-contrast series.
    nFiles = numel(files);
    if nFiles == 0, vol = []; return; end

    sliceLocs = zeros(1, nFiles);
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            else
                sliceLocs(k) = k;
            end
        catch
            sliceLocs(k) = k;
        end
    end

    [sortedLocs, idx] = sort(sliceLocs);
    files = files(idx);
    uniqueLocs = unique(sortedLocs);
    nSlices = numel(uniqueLocs);

    try
        img1 = double(dicomread(files{1}));
        nR = size(img1,1); nC = size(img1,2);
    catch
        nR = 256; nC = 256;
    end

    vol = zeros(nR, nC, nSlices, 'double');
    for k = 1:nFiles
        try
            img = double(dicomread(files{k}));
            sl  = find(uniqueLocs == sortedLocs(k), 1);
            if ~isempty(sl), vol(:,:,sl) = img; end
        catch
        end
    end
end

function [pdffVol, sinfo] = readPDFFSeries(series, opts)
%READPDFFERIES  Read a dedicated PDFF series and scale to 0-100%.
    vprint(opts,'Reading PDFF series S%d...', series.SeriesNumber);
    files = series.Files;
    pdffVol = readSingleContrast(files, opts);
    sinfo   = struct();

    if isempty(pdffVol) || isempty(files), return; end

    try
        hdr1    = dicominfo(files{1}, 'UseDictionaryVR', true);
        sinfo   = io_extractSpatialInfo(files, hdr1, size(pdffVol,3), 1);
        % Apply rescale if present
        if isfield(hdr1,'RescaleSlope') && ~isempty(hdr1.RescaleSlope)
            pdffVol = pdffVol .* double(hdr1.RescaleSlope);
        end
        pdffVol = max(0, min(100, pdffVol));
    catch
    end
end


% ======================================================================
%  UTILITIES
% ======================================================================

function dixon = fillSpatialInfo(dixon, files)
    try
        hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
        nZ   = numel(files);
        dixon.SpatialInfo = io_extractSpatialInfo(files, hdr1, nZ, 1);
    catch
    end
end

function s = findRole(group, role)
    s = [];
    for k = 1:numel(group)
        if strcmp(group(k).Role, role)
            if isempty(s), s = group(k);
            else,          s(end+1) = group(k); end %#ok<AGROW>
        end
    end
end

function s = findBestNamedSeries(group, includeTokens, excludeTokens)
    if nargin < 3, excludeTokens = {}; end
    s = [];
    keep = [];
    for k = 1:numel(group)
        desc = lower(group(k).SeriesDescription);
        if ~all(cellfun(@(tok) contains(desc, lower(tok)), includeTokens))
            continue
        end
        if any(cellfun(@(tok) contains(desc, lower(tok)), excludeTokens))
            continue
        end
        keep(end+1) = k; %#ok<AGROW>
    end
    if isempty(keep)
        return
    end
    % Prefer slice counts consistent with the dedicated PDFF map when available,
    % then the smallest image count among named recons to avoid raw multi-series.
    nImgs = arrayfun(@(x) double(group(x).nImages), keep);
    [~, ord] = sort(nImgs, 'ascend');
    s = group(keep(ord));
end

function s = sizeStr(v)
    if isempty(v), s = '[]'; return; end
    s = mat2str(size(v));
end

function dixon = initDixonStruct()
    dixon = struct('Water',[],'Fat',[],'InPhase',[],'OutPhase',[], ...
                   'PDFF',[],'T2star',[],'SpatialInfo',struct(), ...
                   'nSlices',0,'PixelSpacing_mm',[1 1], ...
                   'SliceThickness_mm',8,'SliceLocations',[]);
end

function tempIds = assignContrastBySliceRank(sliceLoc, instNums, nContrasts)
%ASSIGNCONTRASTBYSLICERANK  Assign contrast index by ranking InstanceNumber
%   within each unique SliceLocation.  Works for both GE storage orderings:
%     - contrast-interleaved: C1S1, C2S1, ..., CnS1, C1S2, ...
%     - all-slices-per-contrast: C1S1, C1S2, ..., C1Sn, C2S1, ...
%   In both cases, within each slice the contrast order by InstanceNumber
%   is consistent (1 = first contrast, 2 = second, etc.).
    nFiles  = numel(sliceLoc);
    tempIds = ones(1, nFiles);
    uniqueLocs = unique(sliceLoc);
    for u = 1:numel(uniqueLocs)
        mask = (sliceLoc == uniqueLocs(u));
        fileIdxs = find(mask);
        [~, sortOrd] = sort(instNums(fileIdxs));
        for r = 1:numel(fileIdxs)
            tempIds(fileIdxs(sortOrd(r))) = min(r, nContrasts);
        end
    end
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k}), opts.(fields{k}) = defaults.(fields{k}); end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[seg_buildDixonVolume] ' fmt '\n'], varargin{:});
    end
end


% ======================================================================
%  CONVENTIONAL IP/OP (2-POINT DIXON) READER
% ======================================================================

function s = findIPOPSeries(group)
%FINDIPOPSERIES  Return any series in the Dixon group that looks like a
%   conventional IP/OP (2-point Dixon) acquisition.
    ipopRoles = {'IPOP_Dixon','IPOP_Family','IPOP_Fallback'};
    s = [];
    for k = 1:numel(group)
        role = char(group(k).Role);
        desc = lower(char(group(k).SeriesDescription));
        isIPOPRole = any(strcmp(role, ipopRoles));
        isIPOPDesc = contains(desc,'ip/op')        || contains(desc,'ipop')       || ...
                     contains(desc,'in-phase')      || contains(desc,'inphase')    || ...
                     contains(desc,'out-of-phase')  || contains(desc,'in phase')   || ...
                     contains(desc,'out phase')     || endsWith(strtrim(desc),' ip') || ...
                     endsWith(strtrim(desc),' op');
        if isIPOPRole || isIPOPDesc
            if isempty(s), s = group(k);
            else,          s(end+1) = group(k); end %#ok<AGROW>
        end
    end
end

function [ipVol, opVol] = readIPOPByEchoTime(series, opts)
%READIPOPBYECHOTIME  Split a combined IP/OP series into InPhase and OutPhase
%   volumes using EchoTime read from each DICOM header.
%
%   GE convention: OP (out-of-phase) has the SHORTER echo time and IP
%   (in-phase) has the LONGER echo time.  Files may be stored in any
%   interleaving order (contrast-first or slice-first).

    ipVol = []; opVol = [];
    files  = series.Files;
    nFiles = numel(files);
    if nFiles < 2, return; end

    vprint(opts, '  Reading %d headers for EchoTime...', nFiles);
    echoTimes = nan(1, nFiles);
    sliceLocs = zeros(1, nFiles);
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'EchoTime') && ~isempty(info.EchoTime)
                echoTimes(k) = double(info.EchoTime(1));
            end
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            elseif isfield(info,'InstanceNumber') && ~isempty(info.InstanceNumber)
                sliceLocs(k) = double(info.InstanceNumber);
            end
        catch
        end
    end

    validTE = echoTimes(~isnan(echoTimes));
    if isempty(validTE)
        vprint(opts, '  WARNING: No EchoTime in headers; cannot split IP/OP by TE.');
        return
    end

    uniqueTE = ipopUniqueTolerant(validTE, 0.05);   % 0.05 ms tolerance
    if numel(uniqueTE) < 2
        vprint(opts, '  WARNING: Only 1 unique EchoTime (%.2f ms); cannot split IP/OP.', uniqueTE(1));
        return
    end
    if numel(uniqueTE) > 2
        vprint(opts, '  Note: %d unique EchoTimes found; using shortest and longest.', numel(uniqueTE));
        uniqueTE = [min(uniqueTE), max(uniqueTE)];
    end

    shortTE = uniqueTE(1);
    longTE  = uniqueTE(end);
    vprint(opts, '  EchoTime: OP(short)=%.3f ms, IP(long)=%.3f ms', shortTE, longTE);

    teValid = ~isnan(echoTimes);
    opMask  = teValid & (abs(echoTimes - shortTE) <= abs(echoTimes - longTE));
    ipMask  = teValid & ~opMask;

    opVol = ipopReadByMask(files, opMask, sliceLocs);
    ipVol = ipopReadByMask(files, ipMask, sliceLocs);

    vprint(opts, '  InPhase: %s   OutPhase: %s', sizeStr(ipVol), sizeStr(opVol));
end

function vol = ipopReadByMask(files, mask, locs)
%IPOPREADBYMASK  Read files selected by logical mask, sorted by SliceLocation.
    selFiles = files(mask);
    selLocs  = locs(mask);
    if isempty(selFiles), vol = []; return; end

    [selLocs, ord] = sort(selLocs);
    selFiles = selFiles(ord);
    uniqueLocs = unique(selLocs);
    nSlices    = numel(uniqueLocs);

    try
        img1 = double(dicomread(selFiles{1}));
        nR = size(img1,1); nC = size(img1,2);
    catch
        nR = 256; nC = 256;
    end
    vol = zeros(nR, nC, nSlices, 'double');
    for k = 1:numel(selFiles)
        try
            img = double(dicomread(selFiles{k}));
            sl  = find(uniqueLocs == selLocs(k), 1);
            if ~isempty(sl), vol(:,:,sl) = img; end
        catch
        end
    end
end

function uq = ipopUniqueTolerant(vals, tol)
%IPOPUNIQUETOLERANT  Return unique values with tolerance-based clustering.
    vals = sort(vals(:)');
    uq   = vals(1);
    for k = 2:numel(vals)
        if vals(k) - uq(end) > tol
            uq(end+1) = vals(k); %#ok<AGROW>
        end
    end
end

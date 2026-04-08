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

    % ── 2.  Read multi-contrast series ────────────────────────────────
    if ~isempty(multiSeries)
        vprint(opts, 'Reading IDEAL-IQ multi-contrast: S%d  (%d files)', ...
            multiSeries(1).SeriesNumber, multiSeries(1).nImages);
        dixon = readMultiContrast(multiSeries(1), dixon, opts);
    end

    % ── 3.  Fill gaps from individual series ──────────────────────────
    if isempty(dixon.Water) && ~isempty(rawSeries)
        vprint(opts, 'Reading water from: S%d', rawSeries(1).SeriesNumber);
        dixon.Water = readSingleContrast(rawSeries(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, rawSeries(1).Files);
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
    vprint(opts, '  PDFF:    %s  (range %.1f-%.1f%%)', ...
        sizeStr(dixon.PDFF), nanmin(dixon.PDFF(:)), nanmax(dixon.PDFF(:)));
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

    % Determine nContrasts and nSlices
    nContrasts = numel(unique(tempIds));
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
%CLASSIFYCONTRASTSBYWINDOW  Identify contrast by WindowCenter heuristic.
%   Fallback to GE standard order if classification is ambiguous.
    labels = {'Water','Fat','InPhase','OutPhase','PDFF','T2star'};
    labels = labels(1:nContrasts);   % default order

    wcs = zeros(1, nContrasts);
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

    % PDFF: WindowCenter typically 50 (centred on 50% fat fraction)
    [~, pdffIdx] = min(abs(wcs - 50));
    if wcs(pdffIdx) > 20 && wcs(pdffIdx) < 100
        % Reassign the PDFF slot
        tmpLabels = {'Water','Fat','InPhase','OutPhase','T2star','Extra'};
        tmpLabels(1:nContrasts) = tmpLabels(1:nContrasts);
        % Insert PDFF at detected position
        newLabels = tmpLabels(1:nContrasts);
        newLabels{pdffIdx} = 'PDFF';
        labels = newLabels;
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

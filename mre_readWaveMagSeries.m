function [W, M, spatialInfo, phases_rad] = mre_readWaveMagSeries(seriesEntry, opts)
% MRE_READWAVEMAGSERIES  Read a combined GE MRE wave+magnitude DICOM series.
%
%   Handles both EPI (series 3001) and GRE (series 07) which store phase-contrast
%   wave images and magnitude images together in one folder:
%     - First half (by InstanceNumber): phase-contrast wave images
%     - Second half: magnitude images
%
%   [W, M, SPATIALINFO, PHASES_RAD] = MRE_READWAVEMAGSERIES(SERIESENTRY)
%
%   OUTPUTS
%     W           [nRow × nCol × nSlices × nPhases]  double, radians
%                 Phase-contrast wave images. Converted from raw GE integer
%                 encoding to radians using pixel scaling.
%     M           [nRow × nCol × nSlices]  double, arbitrary units
%                 Time-averaged magnitude image (mean across phase offsets).
%     spatialInfo struct from io_extractSpatialInfo
%     phases_rad  [1 × nPhases] double  phase offset values (0 to 2π, evenly spaced)
%
%   SPLITTING STRATEGY
%     1. Sort all files by InstanceNumber (primary) and SliceLocation (secondary).
%     2. Identify wave files: PixelRepresentation=1 (signed int → phase data)
%        OR SmallestImagePixelValue < 0.
%        Identify mag files: PixelRepresentation=0 (unsigned → magnitude).
%     3. If representation tags are ambiguous: use InstanceNumber split
%        (first nSlices×nPhases = wave, last nSlices×nPhases = magnitude).
%     4. Reshape each group into [row × col × nSlices × nPhases].
%
%   WAVE SCALING
%     GE encodes phase as integer pixels where the full ±π range spans
%     the pixel window. Raw pixel → radians:
%       radians = double(pixel) × π / (WindowWidth/2)
%     For series 3001: WindowWidth=6283 ≈ 2π×1000, so scale=π/3141.5.
%
%   SEE ALSO  mre_parseDICOMExam, mre_buildMATFile, io_extractSpatialInfo
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    W = []; M = []; spatialInfo = struct(); phases_rad = [];

    files = seriesEntry.Files;
    nFiles = numel(files);
    if nFiles == 0
        warning('mre_readWaveMagSeries:noFiles', 'No files in series.');
        return
    end

    vprint(opts, 'Reading %s: %d files', seriesEntry.Role, nFiles);

    % ------------------------------------------------------------------
    % FAST PATH: Processed wave series (no magnitude, no split needed)
    %   *_WaveMag_Proc series contain ONLY processed wave images.
    %   nPhases = nFiles / nSlices (may be 8, already interpolated).
    % ------------------------------------------------------------------
    isProcWave = contains(seriesEntry.Role, '_WaveMag_Proc') || ...
                 contains(seriesEntry.Role, '_ProcWave');
    if isProcWave
        [W, M, spatialInfo, phases_rad] = readProcWave(seriesEntry, files, opts);
        return
    end

    % ------------------------------------------------------------------
    % 1.  Read all file headers (fast — no pixel data yet)
    % ------------------------------------------------------------------
    headers = readAllHeaders(files, opts);

    % ------------------------------------------------------------------
    % 2.  Sort by InstanceNumber
    % ------------------------------------------------------------------
    instNums   = [headers.InstanceNumber];
    sliceLocs  = [headers.SliceLocation];
    pixReps    = [headers.PixelRepresentation];  % 0=unsigned, 1=signed
    minPx      = [headers.SmallestImagePixelValue];

    [~, sortIdx] = sortrows([instNums(:), sliceLocs(:)]);
    files      = files(sortIdx);
    pixReps    = pixReps(sortIdx);
    minPx      = minPx(sortIdx);
    headers    = headers(sortIdx);

    % ------------------------------------------------------------------
    % 3.  Classify each file as wave or magnitude
    % ------------------------------------------------------------------
    % EPI wave: signed int16 (PixelRepresentation=1 or SmallestPixelValue<0)
    % GRE wave: unsigned but DC-offset (PixelRepresentation=0, all positive,
    %           WindowCenter ≈ halfRange, WindowWidth ≈ fullRange)
    % Magnitude: unsigned, WindowCenter >> 0, NOT phase-contrast pattern
    %
    % Strategy: use PixelRepresentation first; if ambiguous (all unsigned),
    % fall back to InstanceNumber 50/50 split (first half=wave, second half=mag).

    isWave = (pixReps == 1) | (minPx < 0);   % signed → definitely wave

    % GRE case: all unsigned — detect wave by window pattern
    % Phase images have WindowCenter ≈ WindowWidth/2 (DC offset convention)
    if sum(isWave) == 0
        wcs = [headers.WindowCenter];
        wws = [headers.WindowWidth];
        % Wave criterion: |WindowCenter - WindowWidth/2| < 20% of WindowWidth
        isWaveByWin = abs(wcs - wws/2) < 0.20 .* wws;
        if sum(isWaveByWin) > 0 && sum(isWaveByWin) < nFiles
            isWave = isWaveByWin;
            vprint(opts, 'GRE unsigned: wave/mag split by window-center heuristic.');
        else
            % Final fallback: first half = wave, second half = mag
            vprint(opts, 'Cannot distinguish wave/mag — using 50/50 split.');
            isWave = false(1, nFiles);
            isWave(1:floor(nFiles/2)) = true;
        end
    end

    waveFiles = files(isWave);
    magFiles  = files(~isWave);
    waveHdrs  = headers(isWave);
    magHdrs   = headers(~isWave);

    % Determine whether wave data has a DC offset (GRE unsigned convention)
    % If PixelRepresentation=0 (unsigned), DC = WindowWidth/2
    isUnsignedWave = all([waveHdrs.PixelRepresentation] == 0);

    % ------------------------------------------------------------------
    % 4.  Determine geometry from wave files
    % ------------------------------------------------------------------
    % Use NumberOfTemporalPositions from header as primary source —
    % this is always reliable for GE MRE, regardless of file ordering.
    nPhasesHdr = double(headers(1).NumberOfTemporalPositions);
    if nPhasesHdr < 1 || isnan(nPhasesHdr), nPhasesHdr = 4; end

    nWaveFiles = numel(waveFiles);
    nSlices    = round(nWaveFiles / nPhasesHdr);

    % Sanity check: if nSlices doesn't divide evenly, fall back to
    % unique slice locations
    if nSlices * nPhasesHdr ~= nWaveFiles
        uniqueSliceLocs = unique([waveHdrs.SliceLocation]);
        nSlices  = numel(uniqueSliceLocs);
        nPhases  = round(nWaveFiles / max(nSlices,1));
        vprint(opts, 'Using slice-location geometry: %d slices × %d phases', nSlices, nPhases);
    else
        nPhases = nPhasesHdr;
        uniqueSliceLocs = unique([waveHdrs.SliceLocation]);
        vprint(opts, 'Using header geometry: %d slices × %d phases', nSlices, nPhases);
    end

    nPhases = round(nPhases);
    nSlices = round(nSlices);
    nRow = double(headers(1).Rows);
    nCol = double(headers(1).Columns);

    vprint(opts, 'Geometry: %d rows × %d cols × %d slices × %d phases  (unsigned=%d)', ...
        nRow, nCol, nSlices, nPhases, isUnsignedWave);

    % Wave pixel-to-radian scale + DC offset
    ww = double(waveHdrs(1).WindowWidth);
    if isempty(ww) || ww == 0, ww = 6283; end
    waveScale = pi / (ww / 2);   % raw int → radians scale factor

    if isUnsignedWave
        % GRE: pixel 0=−π, ww/2=0, ww=+π  →  subtract DC before scaling
        waveDC = ww / 2;
        vprint(opts, 'Wave DC offset: %.1f  scale: %.6f rad/DN', waveDC, waveScale);
    else
        % EPI: signed int, no DC offset needed
        waveDC = 0;
    end

    % Phase offset values (0 to 2π exclusive)
    phases_rad = linspace(0, 2*pi, nPhases+1);
    phases_rad = phases_rad(1:nPhases);

    % ------------------------------------------------------------------
    % 5.  Read wave pixels and reshape
    % ------------------------------------------------------------------
    % GE GRE-MRE uses phase-major acquisition order: all slices are acquired
    % at phase 1, then all slices at phase 2, etc.  TemporalPositionIdentifier
    % is often 0/absent.  The only reliable approach:
    %   1) For each unique SliceLocation, collect that slice's wave files.
    %   2) Sort those files by InstanceNumber → gives phase order.
    %   3) Assign phase 1,2,...,nPhases in that InstanceNumber order.
    % This works for both phase-major and slice-major GE acquisitions.

    waveSliceLocs = [waveHdrs.SliceLocation];
    waveInstNums  = [waveHdrs.InstanceNumber];

    uniqueSliceLocs = unique(waveSliceLocs);
    nSlices = numel(uniqueSliceLocs);
    nPhases = max(1, round(nWaveFiles / nSlices));

    vprint(opts, 'Wave geometry: %d slices × %d phases  (unsigned=%d)', ...
        nSlices, nPhases, isUnsignedWave);

    W = zeros(nRow, nCol, nSlices, nPhases, 'double');

    for slIdx = 1:nSlices
        % Files belonging to this slice (by SliceLocation)
        slMask      = (waveSliceLocs == uniqueSliceLocs(slIdx));
        slFiles     = waveFiles(slMask);
        slInstNums  = waveInstNums(slMask);
        % Sort by InstanceNumber → correct phase order for this slice
        [~, phSortIdx] = sort(slInstNums);
        slFiles = slFiles(phSortIdx);
        for ph = 1:min(numel(slFiles), nPhases)
            try
                pxData = double(dicomread(slFiles{ph}));
            catch
                continue
            end
            % Convert to radians: subtract DC (=0 for signed EPI; =ww/2 for unsigned GRE)
            W(:,:,slIdx,ph) = (pxData - waveDC) .* waveScale;
        end
    end

    % ------------------------------------------------------------------
    % 6.  Read magnitude pixels, average across phases
    % ------------------------------------------------------------------
    if ~isempty(magFiles)
        uniqueMagLocs = unique([magHdrs.SliceLocation]);
        nMagSlices    = numel(uniqueMagLocs);
        Mraw = zeros(nRow, nCol, nMagSlices, 'double');
        Mcnt = zeros(1, nMagSlices);

        for k = 1:numel(magFiles)
            try
                pxData = double(dicomread(magFiles{k}));
            catch
                continue
            end
            sl = find(uniqueMagLocs == magHdrs(k).SliceLocation, 1);
            if isempty(sl), continue; end
            Mraw(:,:,sl) = Mraw(:,:,sl) + pxData;
            Mcnt(sl) = Mcnt(sl) + 1;
        end
        % Average
        for sl = 1:nMagSlices
            if Mcnt(sl) > 0
                Mraw(:,:,sl) = Mraw(:,:,sl) / Mcnt(sl);
            end
        end
        M = Mraw;
    else
        % Fallback: compute magnitude from wave amplitude
        vprint(opts, 'No separate magnitude found — using wave amplitude.');
        M = mean(abs(W), 4);
    end

    % ------------------------------------------------------------------
    % 7.  Spatial info from first wave header
    % ------------------------------------------------------------------
    waveFilesCell = waveFiles;
    firstHdr = waveHdrs(1);
    spatialInfo = io_extractSpatialInfo(waveFilesCell, firstHdr, nSlices, nPhases);

    vprint(opts, 'Done. W: %s, M: %s', mat2str(size(W)), mat2str(size(M)));
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function headers = readAllHeaders(files, opts)
%READALLHEADERS  Quickly read key tags from every file header.
    nFiles = numel(files);
    % Pre-allocate struct array
    headers = repmat(struct( ...
        'InstanceNumber',          NaN, ...
        'SliceLocation',           NaN, ...
        'TemporalPositionIdentifier', 1, ...
        'NumberOfTemporalPositions',  1, ...
        'PixelRepresentation',     0, ...
        'SmallestImagePixelValue', 0, ...
        'WindowCenter',            0, ...
        'WindowWidth',             6283, ...
        'Rows',                    256, ...
        'Columns',                 256), 1, nFiles);

    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            headers(k).InstanceNumber   = getN(info,'InstanceNumber',    k);
            headers(k).SliceLocation    = getN(info,'SliceLocation',     0);
            headers(k).TemporalPositionIdentifier = ...
                                          getN(info,'TemporalPositionIdentifier', 1);
            headers(k).NumberOfTemporalPositions  = ...
                                          getN(info,'NumberOfTemporalPositions',  1);
            headers(k).PixelRepresentation = getN(info,'PixelRepresentation', 0);
            headers(k).SmallestImagePixelValue = ...
                                          getN(info,'SmallestImagePixelValue',   0);
            headers(k).WindowCenter     = getN(info,'WindowCenter',       0);
            headers(k).WindowWidth      = getN(info,'WindowWidth',        6283);
            headers(k).Rows             = getN(info,'Rows',               256);
            headers(k).Columns          = getN(info,'Columns',            256);
        catch
            headers(k).InstanceNumber = k;
        end
        if opts.verbose && mod(k, 50) == 0
            fprintf('  Headers: %d / %d\n', k, nFiles);
        end
    end
end

function v = getN(info, field, default)
    if isfield(info, field) && ~isempty(info.(field))
        v = double(info.(field)(1));
    else
        v = default;
    end
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
        fprintf(['[mre_readWaveMagSeries] ' fmt '\n'], varargin{:});
    end
end

% ======================================================================
%  PROCESSED WAVE FAST PATH
% ======================================================================
function [W, M, spatialInfo, phases_rad] = readProcWave(seriesEntry, files, opts)
%READPROCWAVE  Read a processed-wave-only series (no mag split needed).
%
%   Processed wave series (e.g. GRE s705, EPI s300105) contain:
%     - Only wave images (no magnitude)
%     - Already phase-unwrapped, filtered, and optionally interpolated
%     - nPhases = nFiles / nSlices  (may be 8 if interpolated from 4)
%
%   Wave scaling: same DC-offset logic as raw series.

    W = []; M = []; spatialInfo = struct(); phases_rad = [];

    nFiles = numel(files);
    try
        hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
    catch
        warning('mre_readWaveMagSeries:procHeader','Cannot read header: %s', files{1});
        return
    end

    nRow = double(hdr1.Rows);
    nCol = double(hdr1.Columns);

    % Determine nSlices and nPhases
    % Collect SliceLocation and InstanceNumber from every header.
    sliceLocs = zeros(1, nFiles);
    instNums  = (1:nFiles);   % fallback if tag absent
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            else
                sliceLocs(k) = k;
            end
            if isfield(info,'InstanceNumber') && ~isempty(info.InstanceNumber)
                instNums(k) = double(info.InstanceNumber);
            end
        catch
            sliceLocs(k) = k;
        end
    end

    uniqueLocs = unique(sliceLocs);
    nSlices    = numel(uniqueLocs);
    nPhases    = max(1, round(nFiles / nSlices));

    vprint(opts, 'Proc wave geometry: %d rows × %d cols × %d slices × %d phases', ...
        nRow, nCol, nSlices, nPhases);

    % Wave scaling
    ww = 10000;   % default for processed wave
    if isfield(hdr1,'WindowWidth') && ~isempty(hdr1.WindowWidth)
        ww = double(hdr1.WindowWidth(1));
    end
    % DC offset for unsigned storage
    pixRep = 0;
    if isfield(hdr1,'PixelRepresentation') && ~isempty(hdr1.PixelRepresentation)
        pixRep = double(hdr1.PixelRepresentation);
    end
    if pixRep == 0
        waveDC = ww / 2;   % unsigned with DC offset
    else
        waveDC = 0;        % signed, no DC offset needed
    end
    waveScale = pi / (ww / 2);

    phases_rad = linspace(0, 2*pi, nPhases+1);
    phases_rad = phases_rad(1:nPhases);

    % Read all files — assign phases within each slice by InstanceNumber order
    % (same phase-major-safe logic as the raw wave reader)
    W = zeros(nRow, nCol, nSlices, nPhases, 'double');

    for slIdx = 1:nSlices
        slMask     = (sliceLocs == uniqueLocs(slIdx));
        slFiles    = files(slMask);
        slInstNums = instNums(slMask);
        [~, phSortIdx] = sort(slInstNums);
        slFiles = slFiles(phSortIdx);
        for ph = 1:min(numel(slFiles), nPhases)
            try
                pxData = double(dicomread(slFiles{ph}));
            catch
                continue
            end
            W(:,:,slIdx,ph) = (pxData - waveDC) .* waveScale;
        end
    end

    % No magnitude available from proc wave — return empty
    M = [];

    % Spatial info
    try
        spatialInfo = io_extractSpatialInfo(files, hdr1, nSlices, nPhases);
    catch
        spatialInfo = struct();
    end

    vprint(opts, 'Proc wave done. W: %s  (unsigned=%d)', mat2str(size(W)), pixRep==0);
end

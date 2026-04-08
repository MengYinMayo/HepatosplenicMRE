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
    % Wave = signed phase data (PixelRepresentation=1 OR min pixel < 0)
    isWave = (pixReps == 1) | (minPx < 0);

    if sum(isWave) == 0 || sum(~isWave) == 0
        % Fallback: assume first half = wave, second half = mag
        vprint(opts, 'Cannot distinguish wave/mag by sign — using 50/50 split.');
        isWave = false(1, nFiles);
        isWave(1 : floor(nFiles/2)) = true;
    end

    waveFiles = files(isWave);
    magFiles  = files(~isWave);
    waveHdrs  = headers(isWave);
    magHdrs   = headers(~isWave);

    % ------------------------------------------------------------------
    % 4.  Determine geometry from wave files
    % ------------------------------------------------------------------
    uniqueSliceLocs = unique([waveHdrs.SliceLocation]);
    nSlices = numel(uniqueSliceLocs);
    nPhases = numel(waveFiles) / nSlices;

    if nPhases ~= round(nPhases)
        % Try with all files
        warning('mre_readWaveMagSeries:geometry', ...
            'Cannot evenly divide %d wave files into %d slices. Trying NumberOfTemporalPositions.', ...
            numel(waveFiles), nSlices);
        nPhases = double(headers(1).NumberOfTemporalPositions);
        nSlices = numel(waveFiles) / nPhases;
    end

    nPhases = round(nPhases);
    nSlices = round(nSlices);
    nRow = double(headers(1).Rows);
    nCol = double(headers(1).Columns);

    vprint(opts, 'Geometry: %d rows × %d cols × %d slices × %d phases', ...
        nRow, nCol, nSlices, nPhases);

    % Wave pixel-to-radian scale
    ww = double(waveHdrs(1).WindowWidth);
    if isempty(ww) || ww == 0, ww = 6283; end
    waveScale = pi / (ww / 2);   % scale factor: raw int → radians

    % Phase offset values (0 to 2π exclusive)
    phases_rad = linspace(0, 2*pi, nPhases+1);
    phases_rad = phases_rad(1:nPhases);

    % ------------------------------------------------------------------
    % 5.  Read wave pixels and reshape
    % ------------------------------------------------------------------
    W = zeros(nRow, nCol, nSlices, nPhases, 'double');

    for k = 1:numel(waveFiles)
        try
            pxData = double(dicomread(waveFiles{k}));
        catch
            continue
        end
        % Map InstanceNumber → (sliceIdx, phaseIdx)
        sl = find(uniqueSliceLocs == waveHdrs(k).SliceLocation, 1);
        ph = waveHdrs(k).TemporalPositionIdentifier;
        if isempty(sl) || isempty(ph) || ph < 1 || ph > nPhases
            continue
        end
        % Convert to radians
        W(:,:,sl,ph) = pxData .* waveScale;
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

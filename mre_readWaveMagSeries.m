function [W, M, spatialInfo, phases_rad, M_raw] = mre_readWaveMagSeries(seriesEntry, opts)
% MRE_READWAVEMAGSERIES  Read GE MRE raw or processed wave series.
%
% OUTPUTS
%   W           [row col slice phase]  double
%   M           [row col slice]        double (time-averaged magnitude)
%   spatialInfo struct
%   phases_rad  nominal phase offsets
%   M_raw       [row col slice phase]  double (raw magnitude phases)
%
% Notes
% - Raw GRE combined series (S7) contains wave in the first half and
%   magnitude in the second half after InstanceNumber sorting.
% - Processed GRE series (S705) is a separate derived series and must be
%   read directly in native signed pixel units. For this series, the most
%   reliable slice index is InStackPositionNumber, while phase order is
%   recovered by InstanceNumber inside each slice.

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    W = []; M = []; spatialInfo = struct(); phases_rad = []; M_raw = [];

    files = seriesEntry.Files;
    nFiles = numel(files);
    if nFiles == 0
        warning('mre_readWaveMagSeries:noFiles', 'No files in series.');
        return
    end

    vprint(opts, 'Reading %s: %d files', safeField(seriesEntry,'Role','(no role)'), nFiles);

    % ------------------------------------------------------------------
    % Fast path for processed-wave series (e.g., GRE S705)
    % ------------------------------------------------------------------
    if isProcessedWaveSeries(seriesEntry, files)
        [W, M, spatialInfo, phases_rad, M_raw] = readProcWave(seriesEntry, files, opts);
        return
    end

    % ------------------------------------------------------------------
    % Raw combined wave+magnitude path
    % ------------------------------------------------------------------
    headers = readAllHeaders(files, opts);

    instNums = [headers.InstanceNumber];
    [~, sortIdx] = sort(instNums(:), 'ascend');
    files   = files(sortIdx);
    headers = headers(sortIdx);

    % Raw GRE: first half = wave, second half = magnitude.
    nHalf = floor(numel(files) / 2);
    waveFiles = files(1:nHalf);
    magFiles  = files(nHalf+1:end);
    waveHdrs  = headers(1:nHalf);
    magHdrs   = headers(nHalf+1:end);

    if isempty(waveFiles)
        warning('mre_readWaveMagSeries:noWave', 'No wave images identified in series.');
        return
    end

    nRow = double(waveHdrs(1).Rows);
    nCol = double(waveHdrs(1).Columns);

    % Prefer slice index from InStackPositionNumber when available.
    nPhasesHdr = getNominalPhaseCount(waveHdrs);
    nSlicesExp = max(1, round(numel(waveFiles) / max(1, nPhasesHdr)));
    [waveSliceIdx, nSlices] = getSliceIndices(waveHdrs, nSlicesExp);
    nPhases = max(1, round(numel(waveFiles) / max(1, nSlices)));

    phases_rad = linspace(0, 2*pi, nPhases+1);
    phases_rad = phases_rad(1:nPhases);

    % Raw wave should stay in native signed units for QC display.
    W = zeros(nRow, nCol, nSlices, nPhases, 'double');
    for sl = 1:nSlices
        sel = (waveSliceIdx == sl);
        slFiles = waveFiles(sel);
        slHdrs  = waveHdrs(sel);
        [~, ord] = orderWithinSlice(slHdrs);
        slFiles = slFiles(ord);
        nThis = min(numel(slFiles), nPhases);
        for ph = 1:nThis
            try
                W(:,:,sl,ph) = double(dicomread(slFiles{ph}));
            catch
            end
        end
    end

    % Magnitude: second half, same slice/phase ordering rule.
    if ~isempty(magFiles)
        [magSliceIdx, nMagSlices] = getSliceIndices(magHdrs, nSlices);
        nMagPhases = max(1, round(numel(magFiles) / max(1, nMagSlices)));
        M_raw = zeros(nRow, nCol, nMagSlices, nMagPhases, 'double');
        for sl = 1:nMagSlices
            sel = (magSliceIdx == sl);
            slFiles = magFiles(sel);
            slHdrs  = magHdrs(sel);
            [~, ord] = orderWithinSlice(slHdrs);
            slFiles = slFiles(ord);
            nThis = min(numel(slFiles), nMagPhases);
            for ph = 1:nThis
                try
                    M_raw(:,:,sl,ph) = double(dicomread(slFiles{ph}));
                catch
                end
            end
        end
        M = mean(M_raw, 4);
    else
        M = mean(abs(W), 4);
        M_raw = repmat(M, [1 1 1 max(1, size(W,4))]);
    end

    try
        spatialInfo = io_extractSpatialInfo(waveFiles, waveHdrs(1), nSlices, nPhases);
    catch
        spatialInfo = struct();
    end

    vprint(opts, 'Raw path done. W: %s  M_raw: %s', mat2str(size(W)), mat2str(size(M_raw)));
end

% =====================================================================
%  PROCESSED WAVE PATH
% =====================================================================
function [W, M, spatialInfo, phases_rad, M_raw] = readProcWave(seriesEntry, files, opts)
% Read processed-wave-only series directly from native pixel values.
% For GRE S705-like data, InStackPositionNumber is reliable for slice,
% while phase order should fall back to InstanceNumber.

    W = []; M = []; spatialInfo = struct(); phases_rad = []; M_raw = [];
    headers = readAllHeaders(files, opts);

    instNums = [headers.InstanceNumber];
    [~, sortIdx] = sort(instNums(:), 'ascend');
    files   = files(sortIdx);
    headers = headers(sortIdx);

    nFiles = numel(files);
    nRow   = double(headers(1).Rows);
    nCol   = double(headers(1).Columns);

    nPhasesHdr = getNominalPhaseCount(headers);
    nSlicesExp = max(1, round(nFiles / max(1, nPhasesHdr)));
    [sliceIdx, nSlices] = getSliceIndices(headers, nSlicesExp);
    nPhases = max(1, round(nFiles / max(1, nSlices)));

    phases_rad = linspace(0, 2*pi, nPhases+1);
    phases_rad = phases_rad(1:nPhases);

    vprint(opts, 'Processed wave geometry: %d x %d x %d slices x %d phases', ...
        nRow, nCol, nSlices, nPhases);

    W = zeros(nRow, nCol, nSlices, nPhases, 'double');
    for sl = 1:nSlices
        sel = (sliceIdx == sl);
        slFiles = files(sel);
        slHdrs  = headers(sel);
        [~, ord] = orderWithinSlice(slHdrs);
        slFiles = slFiles(ord);
        nThis = min(numel(slFiles), nPhases);
        for ph = 1:nThis
            try
                W(:,:,sl,ph) = double(dicomread(slFiles{ph}));
            catch
            end
        end
    end

    try
        spatialInfo = io_extractSpatialInfo(files, headers(1), nSlices, nPhases);
    catch
        spatialInfo = struct();
    end

    % No magnitude in processed-wave series.
    M = [];
    M_raw = [];
end

% =====================================================================
%  HEADER / ORDER HELPERS
% =====================================================================
function tf = isProcessedWaveSeries(seriesEntry, files)
    role = lower(safeField(seriesEntry, 'Role', ''));
    desc = lower(safeField(seriesEntry, 'SeriesDescription', ''));
    sn   = safeField(seriesEntry, 'SeriesNumber', NaN);

    try
        h = dicominfo(files{1}, 'UseDictionaryVR', true);
    catch
        h = struct();
    end

    itype = lower(joinImageType(safeField(h,'ImageType','')));
    wc    = getN(h, 'WindowCenter', NaN);
    ww    = getN(h, 'WindowWidth',  NaN);
    bits  = getN(h, 'BitsAllocated', NaN);
    pr    = getN(h, 'PixelRepresentation', NaN);

    tf = false;

    % Explicit role/name matches first.
    if contains(role, 'proc') || contains(role, 'processed') || contains(desc, 'processed')
        tf = true;
    end

    % GE GRE processed wave marker from uploaded headers:
    %   Series xx05, DERIVED\SECONDARY\PROCESSED, 16-bit signed,
    %   WC ~ 0, WW ~ 10000.
    if ~tf
        tf = contains(itype, 'derived') && contains(itype, 'processed') && ...
             ~contains(itype, 'screen') && bits == 16 && pr == 1 && ...
             isfinite(sn) && mod(sn,100) == 5 && isfinite(ww) && ww >= 5000 && ...
             isfinite(wc) && abs(wc) <= max(500, 0.10 * ww);
    end
end

function headers = readAllHeaders(files, opts)
    nFiles = numel(files);
    headers = repmat(struct( ...
        'InstanceNumber',              NaN, ...
        'SliceLocation',               NaN, ...
        'TemporalPositionIdentifier',  1, ...
        'NumberOfTemporalPositions',   1, ...
        'PixelRepresentation',         0, ...
        'SmallestImagePixelValue',     0, ...
        'WindowCenter',                0, ...
        'WindowWidth',                 6283, ...
        'Rows',                        256, ...
        'Columns',                     256, ...
        'ImagePositionPatient',        [NaN NaN NaN], ...
        'ImageOrientationPatient',     [NaN NaN NaN NaN NaN NaN], ...
        'InStackPositionNumber',       NaN), 1, nFiles);

    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            headers(k).InstanceNumber   = getN(info,'InstanceNumber', k);
            headers(k).SliceLocation    = getN(info,'SliceLocation', NaN);
            headers(k).TemporalPositionIdentifier = getN(info,'TemporalPositionIdentifier', 1);
            headers(k).NumberOfTemporalPositions  = getN(info,'NumberOfTemporalPositions',  1);
            headers(k).PixelRepresentation = getN(info,'PixelRepresentation', 0);
            headers(k).SmallestImagePixelValue = getN(info,'SmallestImagePixelValue', 0);
            headers(k).WindowCenter     = getN(info,'WindowCenter', 0);
            headers(k).WindowWidth      = getN(info,'WindowWidth', 6283);
            headers(k).Rows             = getN(info,'Rows', 256);
            headers(k).Columns          = getN(info,'Columns', 256);
            headers(k).ImagePositionPatient = getVec(info, 'ImagePositionPatient', [NaN NaN NaN]);
            headers(k).ImageOrientationPatient = getVec(info, 'ImageOrientationPatient', [NaN NaN NaN NaN NaN NaN]);
            headers(k).InStackPositionNumber = getN(info, 'InStackPositionNumber', NaN);
        catch
            headers(k).InstanceNumber = k;
        end
        if opts.verbose && mod(k, 50) == 0
            fprintf('  Headers: %d / %d\n', k, nFiles);
        end
    end
end

function nPh = getNominalPhaseCount(headers)
    if isempty(headers), nPh = 1; return; end
    cand = double(headers(1).NumberOfTemporalPositions);
    if isempty(cand) || ~isfinite(cand) || cand < 1, cand = NaN; end
    tpos = [headers.TemporalPositionIdentifier];
    uT = unique(tpos(isfinite(tpos)));
    if isfinite(cand)
        nPh = round(cand);
    elseif numel(uT) > 1
        nPh = numel(uT);
    else
        nPh = 4;
    end
    nPh = max(1, nPh);
end

function [sliceIdx, nSlices] = getSliceIndices(headers, nExpected)
% Prefer InStackPositionNumber when informative. Otherwise fall back to
% physical coordinates clustered with tolerance.
    isp = [headers.InStackPositionNumber];
    uI = unique(isp(isfinite(isp) & isp > 0));
    if numel(uI) >= 2
        [~,~,sliceIdx] = unique(isp(:), 'stable');
        nSlices = max(sliceIdx);
        return
    end

    coords = getSliceCoords(headers);
    [sliceIdx, centers] = clusterSliceCoords(coords, nExpected); %#ok<ASGLU>
    nSlices = max(sliceIdx);
end

function coords = getSliceCoords(headers)
    n = numel(headers);
    coords = nan(1, n);
    for k = 1:n
        ipp = headers(k).ImagePositionPatient;
        iop = headers(k).ImageOrientationPatient;
        if numel(ipp) >= 3 && all(isfinite(ipp(1:3)))
            if numel(iop) >= 6 && all(isfinite(iop(1:6)))
                rowDir = double(iop(1:3));
                colDir = double(iop(4:6));
                sn = cross(rowDir, colDir);
                if all(isfinite(sn)) && norm(sn) > 0
                    sn = sn / norm(sn);
                    coords(k) = dot(double(ipp(1:3)), sn);
                    continue
                end
            end
            coords(k) = double(ipp(3));
        elseif isfinite(headers(k).SliceLocation)
            coords(k) = double(headers(k).SliceLocation);
        else
            coords(k) = double(headers(k).InstanceNumber);
        end
    end
end

function [sliceIdx, centers] = clusterSliceCoords(coords, nExpected)
    coords = double(coords(:));
    n = numel(coords);
    if n == 0
        sliceIdx = zeros(0,1); centers = zeros(1,0); return
    end
    valid = isfinite(coords);
    if ~any(valid)
        sliceIdx = ones(n,1); centers = 0; return
    end
    coords(~valid) = median(coords(valid));
    nExpected = round(nExpected);
    nExpected = max(1, min(nExpected, n));
    [sortedCoords, order] = sort(coords, 'ascend');
    if nExpected == 1
        idxSorted = ones(n,1);
    elseif nExpected >= n
        idxSorted = (1:n).';
    else
        gaps = abs(diff(sortedCoords));
        [~, gapRank] = sort(gaps, 'descend');
        cutPos = sort(gapRank(1:(nExpected-1)));
        idxSorted = zeros(n,1);
        startPos = 1; cls = 1;
        for c = 1:numel(cutPos)
            idxSorted(startPos:cutPos(c)) = cls;
            cls = cls + 1;
            startPos = cutPos(c) + 1;
        end
        idxSorted(startPos:end) = cls;
    end
    sliceIdx = zeros(n,1);
    sliceIdx(order) = idxSorted;
    nSlices = max(sliceIdx);
    centers = zeros(1, nSlices);
    for s = 1:nSlices
        centers(s) = median(coords(sliceIdx == s));
    end
end

function [sortVals, order] = orderWithinSlice(headers)
    tpos = [headers.TemporalPositionIdentifier];
    inst = [headers.InstanceNumber];
    uT = unique(tpos(isfinite(tpos)));
    if numel(uT) == numel(headers) && numel(uT) > 1
        sortVals = tpos;
    else
        sortVals = inst;
    end
    [sortVals, order] = sort(sortVals(:), 'ascend');
end

function s = joinImageType(v)
    if iscell(v)
        try
            s = strjoin(v, '\\');
        catch
            s = '';
        end
    elseif isstring(v)
        s = char(join(v, '\\'));
    else
        s = char(v);
    end
end

function v = safeField(s, field, default)
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    else
        v = default;
    end
end

function v = getN(info, field, default)
    if isfield(info, field) && ~isempty(info.(field))
        try
            v = double(info.(field)(1));
        catch
            v = default;
        end
    else
        v = default;
    end
end

function v = getVec(info, field, default)
    if isfield(info, field) && ~isempty(info.(field))
        try
            tmp = double(info.(field));
            tmp = tmp(:).';
            v = default;
            n = min(numel(default), numel(tmp));
            v(1:n) = tmp(1:n);
        catch
            v = default;
        end
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

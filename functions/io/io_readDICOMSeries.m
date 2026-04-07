function [volume, spatialInfo] = io_readDICOMSeries(files, opts)
% IO_READDICOMSERIES  Read a DICOM series file list into a 3-D (or 4-D) volume.
%
%   [VOLUME, SPATIALINFO] = IO_READDICOMSERIES(FILES) reads all DICOM files
%   in FILES (cell array of full paths, pre-sorted by InstanceNumber), stacks
%   them into a numeric 3-D array [rows × cols × slices], and returns spatial
%   metadata in SPATIALINFO.
%
%   4-D OUTPUT  If the series contains multiple temporal phases (e.g. MRE wave
%   images with 4 time offsets × N slices), the function auto-detects the
%   phase dimension and returns [rows × cols × slices × phases].
%
%   SPATIALINFO fields:
%     .VoxelSize          [1×3] mm  [rowSpacing, colSpacing, sliceSpacing]
%     .ImageOrientationPatient  [1×6] cosine vectors (row + col direction)
%     .ImagePositionFirst [1×3] mm  position of first slice origin
%     .ImagePositionLast  [1×3] mm  position of last slice origin
%     .SliceNormal        [1×3]     normal vector to slice plane
%     .NumSlices          scalar
%     .NumPhases          scalar    (1 for most series, >1 for cine/MRE)
%     .Rows               scalar
%     .Columns            scalar
%     .RescaleSlope       scalar
%     .RescaleIntercept   scalar
%     .WindowCenter       scalar
%     .WindowWidth        scalar
%     .AffineMatrix       [4×4]     voxel-to-world affine (mm, RAS)
%
%   SEE ALSO  io_loadDICOMStudy, io_recognizeSequences, io_extractSpatialInfo
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2
%   DATE    2026-04

    if nargin < 2, opts = struct('verbose', false); end
    volume     = [];
    spatialInfo = struct();

    if isempty(files)
        warning('io_readDICOMSeries:empty', 'File list is empty.');
        return
    end

    % ----------------------------------------------------------------
    % 1.  Read first header to get geometry
    % ----------------------------------------------------------------
    try
        info1 = dicominfo(files{1}, 'UseDictionaryVR', true);
    catch ME
        warning('io_readDICOMSeries:headerFail', ...
            'Cannot read header: %s\n%s', files{1}, ME.message);
        return
    end

    rows    = double(info1.Rows);
    cols    = double(info1.Columns);
    nFiles  = numel(files);

    % ----------------------------------------------------------------
    % 2.  Detect phase cycling (multi-temporal series)
    %     Heuristic: if ImagePositionPatient repeats, there are phases.
    % ----------------------------------------------------------------
    nPhases = detectPhases(files, nFiles);
    nSlices = nFiles / nPhases;
    if nSlices ~= floor(nSlices)
        % Can't evenly divide — treat as single-phase
        nPhases = 1;
        nSlices = nFiles;
    end
    nSlices = round(nSlices);

    % ----------------------------------------------------------------
    % 3.  Pre-allocate
    % ----------------------------------------------------------------
    % Determine data type from first image
    img1 = dicomread(files{1});
    dtype = class(img1);
    if nPhases == 1
        volume = zeros(rows, cols, nSlices, dtype);
    else
        volume = zeros(rows, cols, nSlices, nPhases, dtype);
    end

    % ----------------------------------------------------------------
    % 4.  Read all slices
    % ----------------------------------------------------------------
    slope     = getField(info1, 'RescaleSlope',     1);
    intercept = getField(info1, 'RescaleIntercept', 0);

    for k = 1:nFiles
        try
            img = dicomread(files{k});
        catch
            warning('io_readDICOMSeries:readFail', ...
                'Skipping unreadable file: %s', files{k});
            continue
        end

        % Apply rescale (Hounsfield / real units)
        if slope ~= 1 || intercept ~= 0
            img = cast(double(img) .* slope + intercept, dtype);
        end

        if nPhases == 1
            volume(:,:,k) = img;
        else
            % Interleaved ordering: slice varies fastest, then phase
            sl = mod(k-1, nSlices) + 1;
            ph = floor((k-1) / nSlices) + 1;
            volume(:,:,sl,ph) = img;
        end
    end

    % ----------------------------------------------------------------
    % 5.  Spatial information
    % ----------------------------------------------------------------
    spatialInfo = io_extractSpatialInfo(files, info1, nSlices, nPhases);
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function nPhases = detectPhases(files, nFiles)
%DETECTPHASES  Count temporal phases by checking if slice positions repeat.
    if nFiles < 4
        nPhases = 1; return
    end
    % Sample positions from first ~20 files
    nSample = min(20, nFiles);
    positions = zeros(nSample, 3);
    for k = 1:nSample
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info, 'ImagePositionPatient')
                positions(k,:) = double(info.ImagePositionPatient)';
            end
        catch
            positions(k,:) = NaN;
        end
    end
    % Unique positions: if fewer unique than samples → repeating → phases
    validPos = positions(~any(isnan(positions),2),:);
    if isempty(validPos)
        nPhases = 1; return
    end
    nUnique = size(unique(round(validPos), 'rows'), 1);
    % Ratio of samples to unique positions = number of phases
    ratio = nSample / nUnique;
    if ratio >= 1.9 && ratio <= 8.1   % allow 2–8 phases
        nPhases = round(ratio);
    else
        nPhases = 1;
    end
end

function v = getField(info, field, default)
    if isfield(info, field) && ~isempty(info.(field))
        v = double(info.(field)(1));
    else
        v = default;
    end
end

function series = loadSeriesPixels(series, sortByPosition)
% Load and scale pixel data for all slices in a series.
% Sorts slices by ImagePositionPatient z-coordinate.

    if nargin < 2, sortByPosition = true; end

    headers = series.headers;
    nSlices = numel(headers);

    % Pre-read one slice to get array size
    testSlice = dicomread(headers{1});
    [rows, cols] = size(testSlice);

    pixelData = zeros(rows, cols, nSlices, 'single');
    zPositions = zeros(1, nSlices);
    iop = [];

    for sl = 1:nSlices
        hdr = headers{sl};
        rawSlice = single(dicomread(hdr));

        % Apply rescale (Hounsfield / signal units)
        slope     = getHeaderField(hdr, 'RescaleSlope',     1);
        intercept = getHeaderField(hdr, 'RescaleIntercept', 0);
        pixelData(:,:,sl) = rawSlice * slope + intercept;

        % Store z-position for sorting
        ipp = getHeaderField(hdr, 'ImagePositionPatient', [0;0;0]);
        if isempty(iop)
            iop = getHeaderField(hdr, 'ImageOrientationPatient', zeros(6,1));
        end
        zPositions(sl) = ipp(3);
    end

    % Sort slices by z-position (foot-to-head)
    if sortByPosition && nSlices > 1
        [~, sortIdx] = sort(zPositions);
        pixelData = pixelData(:,:,sortIdx);
        headers   = headers(sortIdx);
        zPositions = zPositions(sortIdx);
    end

    % Voxel size
    pixSpacing = getHeaderField(headers{1}, 'PixelSpacing', [1;1]);
    if nSlices > 1
        sliceThickness = abs(zPositions(2) - zPositions(1));
    else
        sliceThickness = getHeaderField(headers{1}, 'SliceThickness', NaN);
    end

    series.pixelData        = pixelData;
    series.headers          = headers;
    series.nSlices          = nSlices;
    series.voxelSize_mm     = [pixSpacing(1), pixSpacing(2), sliceThickness];
    series.imageOrientation = iop;
end
function localizer = loc_loadLocalizer(localizerSeries, opts)
% LOC_LOADLOCALIZER  Load a GE 3-plane SSFSE localizer into organized plane stacks.
%
%   LOCALIZER = LOC_LOADLOCALIZER(LOCALIZERSERIES) reads all DICOM files from
%   a localizer series (as identified by mre_parseDICOMExam), separates them
%   into the three orthogonal planes (Axial, Coronal, Sagittal) based on
%   ImageOrientationPatient, and returns spatial metadata for each plane.
%
%   This function is the entry point for L1-L2 vertebral localization.
%   The coronal and sagittal planes are used to identify vertebral body positions.
%
%   OUTPUT STRUCT fields:
%     .Axial.Volume         [nR × nC × nAx]  double  axial images
%     .Axial.SliceLocations [1 × nAx]        mm      inferior→superior
%     .Axial.SpatialInfo    struct
%
%     .Coronal.Volume       [nR × nC × nCor] double
%     .Coronal.SliceLocations [1 × nCor]     mm
%     .Coronal.SpatialInfo  struct
%
%     .Sagittal.Volume      [nR × nC × nSag] double
%     .Sagittal.SliceLocations [1 × nSag]    mm
%     .Sagittal.SpatialInfo struct
%
%     .AllFiles             cell             all file paths
%     .PlaneOf              cell             'Axial'|'Coronal'|'Sagittal' per file
%
%   GE 3-Plane Localizer characteristics (from DICOM analysis):
%     SeriesDescription = '3-Plane Localizer'
%     Private_0019_109c = 'ssfse'
%     ImagesInAcquisition = 27  (= 9 axial + 9 coronal + 9 sagittal)
%     SliceThickness = 10 mm, SpacingBetweenSlices = 15 mm
%
%   SEE ALSO  loc_detectL1L2, loc_propagateToSpace, mre_parseDICOMExam
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    vprint(opts, 'Loading localizer: %d files', numel(localizerSeries.Files));

    files = localizerSeries.Files;
    nFiles = numel(files);

    % ------------------------------------------------------------------
    % 1.  Read all headers to classify planes
    % ------------------------------------------------------------------
    planeOf   = cell(1, nFiles);
    sliceLoc  = zeros(1, nFiles);
    iop       = zeros(nFiles, 6);   % ImageOrientationPatient [6 values]
    ipp       = zeros(nFiles, 3);   % ImagePositionPatient [3 values]

    for k = 1:nFiles
        try
            hdr = dicominfo(files{k}, 'UseDictionaryVR', true);
            sliceLoc(k) = getN(hdr, 'SliceLocation', k);
            if isfield(hdr,'ImageOrientationPatient') && ...
               ~isempty(hdr.ImageOrientationPatient)
                iop(k,:) = double(hdr.ImageOrientationPatient(:))';
            end
            if isfield(hdr,'ImagePositionPatient') && ...
               ~isempty(hdr.ImagePositionPatient)
                ipp(k,:) = double(hdr.ImagePositionPatient(:))';
            end
            planeOf{k} = classifyPlane(iop(k,:));
        catch
            planeOf{k} = 'Unknown';
        end
    end

    vprint(opts, 'Plane counts: Axial=%d  Coronal=%d  Sagittal=%d', ...
        sum(strcmp(planeOf,'Axial')), ...
        sum(strcmp(planeOf,'Coronal')), ...
        sum(strcmp(planeOf,'Sagittal')));

    % ------------------------------------------------------------------
    % 2.  Read pixel data and organize by plane
    % ------------------------------------------------------------------
    % Read first image to get dimensions
    firstImg = double(dicomread(files{1}));
    nR = size(firstImg, 1);
    nC = size(firstImg, 2);

    planes = {'Axial','Coronal','Sagittal'};
    localizer = struct();
    localizer.AllFiles = files;
    localizer.PlaneOf  = planeOf;

    for p = 1:numel(planes)
        planeName = planes{p};
        idx = find(strcmp(planeOf, planeName));

        if isempty(idx)
            localizer.(planeName) = emptyPlane();
            continue
        end

        % Sort by slice location (feet→head for axial/coronal, R→L for sagittal)
        [sortedLocs, sortIdx] = sort(sliceLoc(idx));
        sortedFiles = files(idx(sortIdx));
        sortedIPP   = ipp(idx(sortIdx), :);

        % Read images
        vol = zeros(nR, nC, numel(idx), 'double');
        for j = 1:numel(idx)
            try
                vol(:,:,j) = double(dicomread(sortedFiles{j}));
            catch
            end
        end

        % Extract spatial info from first slice header
        try
            hdr1 = dicominfo(sortedFiles{1}, 'UseDictionaryVR', true);
            sinfo = io_extractSpatialInfo(sortedFiles, hdr1, numel(idx), 1);
        catch
            sinfo = struct();
        end

        localizer.(planeName).Volume         = vol;
        localizer.(planeName).SliceLocations = sortedLocs;
        localizer.(planeName).ImagePositions = sortedIPP;
        localizer.(planeName).Files          = sortedFiles;
        localizer.(planeName).SpatialInfo    = sinfo;
    end

    vprint(opts, 'Localizer loaded: Axial[%s] Coronal[%s] Sagittal[%s]', ...
        mat2str(size(localizer.Axial.Volume)), ...
        mat2str(size(localizer.Coronal.Volume)), ...
        mat2str(size(localizer.Sagittal.Volume)));
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function planeName = classifyPlane(iop)
%CLASSIFYPLANE  Determine axial/coronal/sagittal from ImageOrientationPatient.
%
%   IOP = [Rx Ry Rz Cx Cy Cz] where R = row direction, C = column direction.
%   The slice normal = cross(R, C).
%   Compare the dominant component of the slice normal to coordinate axes.

    if all(iop == 0) || numel(iop) < 6
        planeName = 'Unknown';
        return
    end

    rowDir = iop(1:3);
    colDir = iop(4:6);
    normal = cross(rowDir, colDir);
    normal = normal / max(abs(normal) + eps);

    % The dominant axis of the normal vector determines the plane
    [~, domAxis] = max(abs(normal));

    switch domAxis
        case 3  % Z-axis dominant → axial (transverse)
            planeName = 'Axial';
        case 2  % Y-axis dominant → coronal (front-back)
            planeName = 'Coronal';
        case 1  % X-axis dominant → sagittal (left-right)
            planeName = 'Sagittal';
        otherwise
            planeName = 'Unknown';
    end
end

function s = emptyPlane()
    s.Volume         = [];
    s.SliceLocations = [];
    s.ImagePositions = zeros(0,3);
    s.Files          = {};
    s.SpatialInfo    = struct();
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
        fprintf(['[loc_loadLocalizer] ' fmt '\n'], varargin{:});
    end
end

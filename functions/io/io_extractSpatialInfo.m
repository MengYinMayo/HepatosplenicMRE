function sinfo = io_extractSpatialInfo(files, info1, nSlices, nPhases)
% IO_EXTRACTSPATIALINFO  Build spatial metadata struct from DICOM headers.
%
%   SINFO = IO_EXTRACTSPATIALINFO(FILES, INFO1, NSLICES, NPHASES) reads the
%   first and last slice headers and assembles a complete spatial description
%   of the volume including voxel size, slice spacing, orientation cosines,
%   and a 4×4 voxel-to-world affine matrix (RAS convention, mm).
%
%   The affine matrix maps [col; row; slice; 1] → [X_mm; Y_mm; Z_mm; 1]
%   using the DICOM Image Orientation / Image Position tags.
%
%   OUTPUT SINFO FIELDS
%     VoxelSize            [dr, dc, ds]  row/col/slice spacing (mm)
%     PixelSpacing         [dr, dc]      in-plane pixel spacing (mm)
%     SliceSpacing         scalar        centre-to-centre slice gap (mm)
%     SliceThickness       scalar        nominal slice thickness (mm)
%     ImageOrientationPatient  [1×6]     row cosines + col cosines
%     SliceNormal          [1×3]         cross product of row/col cosines
%     ImagePositionFirst   [1×3]         origin of first slice (mm)
%     ImagePositionLast    [1×3]         origin of last slice (mm)
%     Rows                 scalar
%     Columns              scalar
%     NumSlices            scalar
%     NumPhases            scalar
%     RescaleSlope         scalar
%     RescaleIntercept     scalar
%     WindowCenter         scalar
%     WindowWidth          scalar
%     AffineMatrix         [4×4]  voxel→world (mm, RAS)
%     AffineMatrixInv      [4×4]  world→voxel
%
%   SEE ALSO  io_readDICOMSeries, harm_resampleVolume
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu
%   DATE    April 17, 2026

    if nargin < 3, nSlices = numel(files); end
    if nargin < 4, nPhases = 1; end

    sinfo = struct();

    % ── In-plane pixel spacing ────────────────────────────────────────
    if isfield(info1, 'PixelSpacing') && ~isempty(info1.PixelSpacing)
        ps = double(info1.PixelSpacing);
        sinfo.PixelSpacing = ps(:)';          % [rowSpacing, colSpacing]
    else
        sinfo.PixelSpacing = [1 1];
    end

    sinfo.SliceThickness = 0;
    if isfield(info1, 'SliceThickness') && ~isempty(info1.SliceThickness)
        sinfo.SliceThickness = double(info1.SliceThickness);
    end

    % ── Image orientation ─────────────────────────────────────────────
    if isfield(info1, 'ImageOrientationPatient') && ...
       ~isempty(info1.ImageOrientationPatient)
        iop = double(info1.ImageOrientationPatient(:))';
    else
        iop = [1 0 0 0 1 0];   % default: axial
    end
    sinfo.ImageOrientationPatient = iop;
    rowDir = iop(1:3);
    colDir = iop(4:6);
    sinfo.SliceNormal = cross(rowDir, colDir);

    % ── First slice position ──────────────────────────────────────────
    if isfield(info1, 'ImagePositionPatient') && ...
       ~isempty(info1.ImagePositionPatient)
        pos1 = double(info1.ImagePositionPatient(:))';
    else
        pos1 = [0 0 0];
    end
    sinfo.ImagePositionFirst = pos1;

    % ── Last slice position (read last file) ──────────────────────────
    pos2 = pos1;
    if nSlices > 1 && ~isempty(files)
        lastFile = files{min(nSlices, numel(files))};
        try
            infoLast = dicominfo(lastFile, 'UseDictionaryVR', true);
            if isfield(infoLast, 'ImagePositionPatient') && ...
               ~isempty(infoLast.ImagePositionPatient)
                pos2 = double(infoLast.ImagePositionPatient(:))';
            end
        catch
            pos2 = pos1 + (nSlices-1) .* sinfo.SliceThickness .* sinfo.SliceNormal;
        end
    end
    sinfo.ImagePositionLast = pos2;

    % ── Slice spacing ─────────────────────────────────────────────────
    % Prefer SpacingBetweenSlices DICOM tag (most reliable for multi-slice 3D).
    % Fall back to geometric distance between first and last slice.
    headerSpacing = 0;
    if isfield(info1,'SpacingBetweenSlices') && ~isempty(info1.SpacingBetweenSlices)
        headerSpacing = abs(double(info1.SpacingBetweenSlices));
    end
    if headerSpacing == 0 && isfield(info1,'SliceThickness') && ~isempty(info1.SliceThickness)
        headerSpacing = abs(double(info1.SliceThickness));
    end

    if nSlices > 1
        totalDist = norm(pos2 - pos1);
        geomSpacing = totalDist / (nSlices - 1);
        % Trust header spacing when geometry gives an implausible result
        % (e.g. GE IDEAL-IQ where all DICOMs share one SliceLocation so
        % files{1} and files{nSlices} may be from the same physical slice).
        if geomSpacing > 0.5 * headerSpacing && geomSpacing < 2.0 * headerSpacing
            sinfo.SliceSpacing = geomSpacing;   % geometry looks consistent
        elseif headerSpacing > 0
            sinfo.SliceSpacing = headerSpacing; % geometry unreliable — use tag
        else
            sinfo.SliceSpacing = geomSpacing;
        end
    else
        if headerSpacing > 0
            sinfo.SliceSpacing = headerSpacing;
        else
            sinfo.SliceSpacing = sinfo.SliceThickness;
        end
    end
    if sinfo.SliceSpacing == 0
        sinfo.SliceSpacing = sinfo.SliceThickness;
    end
    % Final guard: a zero slice-spacing makes the affine matrix singular.
    if sinfo.SliceSpacing == 0 || isnan(sinfo.SliceSpacing)
        sinfo.SliceSpacing = 1.0;
    end

    % ── Combined voxel size ───────────────────────────────────────────
    sinfo.VoxelSize = [sinfo.PixelSpacing, sinfo.SliceSpacing];

    % ── Dimensions ───────────────────────────────────────────────────
    sinfo.Rows      = double(info1.Rows);
    sinfo.Columns   = double(info1.Columns);
    sinfo.NumSlices = nSlices;
    sinfo.NumPhases = nPhases;

    % ── Rescale parameters ───────────────────────────────────────────
    sinfo.RescaleSlope     = getField(info1, 'RescaleSlope',     1);
    sinfo.RescaleIntercept = getField(info1, 'RescaleIntercept', 0);
    sinfo.WindowCenter     = getField(info1, 'WindowCenter',     NaN);
    sinfo.WindowWidth      = getField(info1, 'WindowWidth',      NaN);

    % ── 4×4 Affine matrix (voxel → patient mm, RAS) ──────────────────
    %   Based on DICOM standard eq. C.7.6.2.1-1:
    %   [X]   [F11 F12 F13 F14] [i]
    %   [Y] = [F21 F22 F23 F24] [j]
    %   [Z]   [F31 F32 F33 F34] [k]
    %   [1]   [ 0   0   0   1 ] [1]
    %
    %   F1-3 = rowDir * dr,  F4-6 = colDir * dc,  F7-9 = sliceNorm * ds
    %   F10-12 = pos1
    dr = sinfo.PixelSpacing(1);   % row spacing    (mm / pixel along rows)
    dc = sinfo.PixelSpacing(2);   % column spacing (mm / pixel along cols)
    ds = sinfo.SliceSpacing;

    F = [rowDir(:)*dr, colDir(:)*dc, sinfo.SliceNormal(:)*ds, pos1(:)];
    A = [F; 0 0 0 1];
    sinfo.AffineMatrix = A;
    % Use pseudo-inverse as fallback when the matrix is ill-conditioned
    % (e.g. residual zero-slice-spacing after the guard above).
    M = A(1:3,1:3);
    if rcond(M) > 1e-10
        sinfo.AffineMatrixInv  = inv(A);
        sinfo.AffineIsSingular = false;
    else
        sinfo.AffineMatrixInv  = pinv(A);
        sinfo.AffineIsSingular = true;
    end
end


% ======================================================================
%  UTILITY
% ======================================================================
function v = getField(info, field, default)
    if isfield(info, field) && ~isempty(info.(field))
        v = double(info.(field)(1));
    else
        v = default;
    end
end

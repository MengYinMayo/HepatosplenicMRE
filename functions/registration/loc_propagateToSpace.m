function L12out = loc_propagateToSpace(L12, targetSpatialInfo, opts)
% LOC_PROPAGATETOSPACE  Map L1-L2 vertebral positions from localizer mm→target slices.
%
%   L12OUT = LOC_PROPAGATETOSPACE(L12, TARGETSPATIALINFO) takes the L1-L2
%   struct from loc_detectL1L2 (which contains positions in patient-coordinate
%   mm) and finds the corresponding slice indices in a target imaging volume
%   (IDEAL-IQ or MRE), using each volume's ImagePositionPatient and
%   ImageOrientationPatient.
%
%   PROPAGATION METHOD
%     For each target slice k with position P_k (mm), compute the dot product
%     of (P_k - L1_pos) with the slice normal vector. The slice whose dot
%     product is closest to zero is the L1 level. Same for L2.
%
%   INPUTS
%     L12               struct from loc_detectL1L2
%     targetSpatialInfo struct from io_extractSpatialInfo for the target volume
%                       OR a cell array of spatialInfo structs (one per series)
%     opts              struct (optional):
%       .verbose        logical (default: true)
%       .interpolate    logical  if true, return fractional slice index
%
%   OUTPUT L12OUT (copy of L12 with added fields):
%     .L1_sliceIdx     double  nearest slice index in target volume (1-based)
%     .L2_sliceIdx     double  nearest slice index in target volume
%     .L1_sliceFrac    double  fractional (sub-voxel) slice index for L1
%     .L2_sliceFrac    double  fractional slice index for L2
%     .L1_dist_mm      double  distance from L1 position to nearest slice (mm)
%     .L2_dist_mm      double  distance from L2 position to nearest slice (mm)
%     .nSlicesTarget   double  total slices in target volume
%     .TargetVoxelSize [1×3]   mm
%
%   USAGE
%     % After detecting L1-L2 in localizer:
%     L12 = loc_detectL1L2(localizer);
%
%     % Propagate to IDEAL-IQ space:
%     L12_dixon = loc_propagateToSpace(L12, study.Dixon.SpatialInfo);
%
%     % Propagate to MRE space:
%     L12_mre   = loc_propagateToSpace(L12, study.MRE.SpatialInfo);
%
%   SEE ALSO  loc_detectL1L2, loc_loadLocalizer, io_extractSpatialInfo
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu

    if nargin < 3, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true, 'interpolate', true));

    L12out = L12;

    % Default: propagation failed
    L12out.L1_sliceIdx   = NaN;
    L12out.L2_sliceIdx   = NaN;
    L12out.L1_sliceFrac  = NaN;
    L12out.L2_sliceFrac  = NaN;
    L12out.L1_dist_mm    = NaN;
    L12out.L2_dist_mm    = NaN;
    L12out.nSlicesTarget = 0;
    L12out.TargetVoxelSize = [NaN NaN NaN];

    if isempty(targetSpatialInfo) || ~isfield(targetSpatialInfo, 'AffineMatrix')
        warning('loc_propagateToSpace:noSpatialInfo', ...
            'Target spatial info missing AffineMatrix. Cannot propagate.');
        return
    end

    sinfo = targetSpatialInfo;
    nZ    = sinfo.NumSlices;

    L12out.nSlicesTarget   = nZ;
    L12out.TargetVoxelSize = sinfo.VoxelSize;

    if nZ < 1
        warning('loc_propagateToSpace:noSlices', 'Target has 0 slices.');
        return
    end

    % ------------------------------------------------------------------
    % 1.  Build slice position vectors for all target slices
    % ------------------------------------------------------------------
    % Affine maps [col; row; slice; 1] → [X; Y; Z; 1] (mm, patient coords)
    % Slice positions = column 3 of affine × slice indices + origin
    A = sinfo.AffineMatrix;

    slicePositions = zeros(nZ, 3);  % [nZ × 3] (X,Y,Z of each slice origin)
    for sl = 1:nZ
        % Centre of slice: col=nC/2, row=nR/2, slice=sl-1 (0-based)
        pos4 = A * [(sinfo.Columns/2-0.5); (sinfo.Rows/2-0.5); (sl-1); 1];
        slicePositions(sl,:) = pos4(1:3)';
    end

    % Slice normal = 3rd column of upper-left 3×3 of A, normalized
    sliceNormal = A(1:3, 3);
    sliceNormal = sliceNormal / (norm(sliceNormal) + eps);

    % ------------------------------------------------------------------
    % 2.  Project L1 and L2 positions onto slice normal
    % ------------------------------------------------------------------
    % We need 3D patient coordinates for L1 and L2.
    % L12 only stores the Z (superior-inferior) component.
    % For the other two components, use the center of the target FOV.
    % This is valid because the slice normal search only uses the SI component
    % for axial/near-axial acquisitions.

    % Build 3D L1 and L2 positions
    % Use the first and last slice positions to define the SI extent
    centerXY = mean(slicePositions(:,1:2), 1);  % average XY center
    L1_pos3 = [centerXY, L12.L1_mm];
    L2_pos3 = [centerXY, L12.L2_mm];

    % Compute signed distance of each slice from L1 and L2
    dists_L1 = zeros(nZ,1);
    dists_L2 = zeros(nZ,1);

    for sl = 1:nZ
        dL1 = slicePositions(sl,:) - L1_pos3;
        dL2 = slicePositions(sl,:) - L2_pos3;
        % Project onto slice normal (distance along slice stack direction)
        dists_L1(sl) = dot(dL1, sliceNormal');
        dists_L2(sl) = dot(dL2, sliceNormal');
    end

    % ------------------------------------------------------------------
    % 3.  Find nearest slice
    % ------------------------------------------------------------------
    [minD_L1, idxL1] = min(abs(dists_L1));
    [minD_L2, idxL2] = min(abs(dists_L2));

    L12out.L1_sliceIdx = idxL1;
    L12out.L2_sliceIdx = idxL2;
    L12out.L1_dist_mm  = minD_L1;
    L12out.L2_dist_mm  = minD_L2;

    % ------------------------------------------------------------------
    % 4.  Fractional (sub-voxel) slice index
    % ------------------------------------------------------------------
    if opts.interpolate && nZ >= 2
        sliceSpacing = sinfo.SliceSpacing;
        if sliceSpacing > 0
            L12out.L1_sliceFrac = idxL1 + dists_L1(idxL1) / sliceSpacing;
            L12out.L2_sliceFrac = idxL2 + dists_L2(idxL2) / sliceSpacing;
        else
            L12out.L1_sliceFrac = idxL1;
            L12out.L2_sliceFrac = idxL2;
        end
    else
        L12out.L1_sliceFrac = idxL1;
        L12out.L2_sliceFrac = idxL2;
    end

    % ------------------------------------------------------------------
    % 5.  Sanity check
    % ------------------------------------------------------------------
    maxDist = sinfo.SliceSpacing * 3;   % warn if >3 slices away
    if minD_L1 > maxDist
        warning('loc_propagateToSpace:L1farFromSlice', ...
            'L1 position %.1f mm is %.1f mm from nearest target slice. Check alignment.', ...
            L12.L1_mm, minD_L1);
    end
    if minD_L2 > maxDist
        warning('loc_propagateToSpace:L2farFromSlice', ...
            'L2 position %.1f mm is %.1f mm from nearest target slice. Check alignment.', ...
            L12.L2_mm, minD_L2);
    end

    vprint(opts, 'L1 → slice %d (frac=%.2f, dist=%.1f mm)', ...
        idxL1, L12out.L1_sliceFrac, minD_L1);
    vprint(opts, 'L2 → slice %d (frac=%.2f, dist=%.1f mm)', ...
        idxL2, L12out.L2_sliceFrac, minD_L2);
end


% ======================================================================
%  UTILITY
% ======================================================================

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
        fprintf(['[loc_propagateToSpace] ' fmt '\n'], varargin{:});
    end
end

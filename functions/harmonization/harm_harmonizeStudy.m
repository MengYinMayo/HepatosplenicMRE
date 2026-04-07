function study = harm_harmonizeStudy(study, opts)
% HARM_HARMONIZESTUDY  Harmonize Scout, Dixon, and MRE to a common spatial grid.
%
%   STUDY = HARM_HARMONIZESTUDY(STUDY) takes a STUDY struct produced by
%   io_loadDICOMStudy and resamples all image sets to a common voxel grid,
%   enabling direct voxel-wise comparison and mask transfer across modalities.
%
%   The reference grid is chosen as follows (priority order):
%     1. Dixon Water image  (highest in-plane resolution, largest FOV)
%     2. MRE Magnitude      (if Dixon unavailable)
%     3. Scout              (last resort)
%
%   After harmonization, STUDY.Harmonized contains:
%     .Scout          3-D volume on reference grid
%     .DixonWater     3-D volume on reference grid
%     .DixonFat       3-D volume on reference grid
%     .DixonFF        3-D fat-fraction map on reference grid
%     .DixonInPhase   3-D volume on reference grid
%     .DixonOutPhase  3-D volume on reference grid
%     .MREMagnitude   3-D volume on reference grid
%     .MREStiffness   3-D stiffness map on reference grid (kPa)
%     .MREWaveImages  4-D wave image stack on reference grid
%     .SpatialInfo    reference spatial info struct
%
%   OPTS fields:
%     .refModality   'Dixon'|'MRE'|'Scout'  (override auto-selection)
%     .method        'linear'|'nearest'     (interpolation, default 'linear')
%     .verbose       true/false             (default true)
%
%   SEE ALSO  io_loadDICOMStudy, harm_resampleVolume, io_extractSpatialInfo
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'refModality', 'auto', ...
        'method',      'linear', ...
        'verbose',     true));

    vprint(opts, '=== harm_harmonizeStudy ===');

    % ── 1.  Choose reference grid ─────────────────────────────────────
    sinfoRef = chooseReferenceGrid(study, opts);
    if isempty(sinfoRef)
        error('harm_harmonizeStudy:noGrid', ...
            'Cannot determine reference grid — no series loaded.');
    end
    vprint(opts, 'Reference grid: %dx%dx%d  voxel=%.2f×%.2f×%.2f mm', ...
        sinfoRef.Rows, sinfoRef.Columns, sinfoRef.NumSlices, ...
        sinfoRef.VoxelSize(1), sinfoRef.VoxelSize(2), sinfoRef.VoxelSize(3));

    H = struct();
    H.SpatialInfo = sinfoRef;
    resOpts = struct('method', opts.method, 'fillVal', 0, 'verbose', false);

    % ── 2.  Resample Scout ────────────────────────────────────────────
    H.Scout = resampleIfNeeded('Scout', study.Scout.Volume, ...
        study.Scout.SpatialInfo, sinfoRef, resOpts, opts);

    % ── 3.  Resample Dixon channels ──────────────────────────────────
    dixonFields = {'Water','Fat','FF','InPhase','OutPhase'};
    for d = 1:numel(dixonFields)
        f = dixonFields{d};
        H.(['Dixon' f]) = resampleIfNeeded( ...
            ['Dixon/' f], study.Dixon.(f), ...
            study.Dixon.SpatialInfo, sinfoRef, resOpts, opts);
    end

    % ── 4.  Resample MRE ─────────────────────────────────────────────
    H.MREMagnitude = resampleIfNeeded('MRE/Magnitude', ...
        study.MRE.Magnitude, study.MRE.SpatialInfo, sinfoRef, resOpts, opts);

    H.MREStiffness = resampleIfNeeded('MRE/Stiffness', ...
        study.MRE.Stiffness, study.MRE.SpatialInfo, sinfoRef, resOpts, opts);

    if ~isempty(study.MRE.WaveImages)
        vprint(opts, 'Resampling MRE/WaveImages (4-D)...');
        H.MREWaveImages = harm_resampleVolume( ...
            study.MRE.WaveImages, study.MRE.SpatialInfo, sinfoRef, resOpts);
    else
        H.MREWaveImages = [];
    end

    % ── 5.  Store result ─────────────────────────────────────────────
    study.Harmonized = H;
    vprint(opts, 'Harmonization complete.');
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function sinfoRef = chooseReferenceGrid(study, opts)
%CHOOSEREFERENCEGRID  Pick the best reference grid automatically.

    sinfoRef = struct();

    if ~strcmp(opts.refModality, 'auto')
        switch upper(opts.refModality)
            case 'DIXON'
                if ~isempty(study.Dixon.SpatialInfo) && ...
                   isfield(study.Dixon.SpatialInfo, 'VoxelSize')
                    sinfoRef = study.Dixon.SpatialInfo; return
                end
            case 'MRE'
                if ~isempty(study.MRE.SpatialInfo) && ...
                   isfield(study.MRE.SpatialInfo, 'VoxelSize')
                    sinfoRef = study.MRE.SpatialInfo; return
                end
            case 'SCOUT'
                if ~isempty(study.Scout.SpatialInfo) && ...
                   isfield(study.Scout.SpatialInfo, 'VoxelSize')
                    sinfoRef = study.Scout.SpatialInfo; return
                end
        end
    end

    % Auto: prefer Dixon (best in-plane res for body composition)
    if isfield(study.Dixon.SpatialInfo, 'VoxelSize') && ...
       ~isempty(study.Dixon.SpatialInfo.VoxelSize)
        sinfoRef = study.Dixon.SpatialInfo;
        if isfield(opts,'verbose') && opts.verbose
            fprintf('[harm] Reference: Dixon grid\n');
        end
        return
    end

    % Fallback to MRE
    if isfield(study.MRE.SpatialInfo, 'VoxelSize') && ...
       ~isempty(study.MRE.SpatialInfo.VoxelSize)
        sinfoRef = study.MRE.SpatialInfo;
        if isfield(opts,'verbose') && opts.verbose
            fprintf('[harm] Reference: MRE grid\n');
        end
        return
    end

    % Last resort: Scout
    if isfield(study.Scout.SpatialInfo, 'VoxelSize') && ...
       ~isempty(study.Scout.SpatialInfo.VoxelSize)
        sinfoRef = study.Scout.SpatialInfo;
        if isfield(opts,'verbose') && opts.verbose
            fprintf('[harm] Reference: Scout grid\n');
        end
    end
end

% ----------------------------------------------------------------------
function volOut = resampleIfNeeded(label, volIn, sinfoIn, sinfoRef, resOpts, opts)
%RESAMPLEIFNEEDED  Resample only if the geometry differs from the reference.

    volOut = [];
    if isempty(volIn) || ~isfield(sinfoIn,'AffineMatrix') || ...
       isempty(sinfoIn.AffineMatrix)
        return
    end

    % Check if grids already match (within 0.1 mm tolerance)
    if gridsMatch(sinfoIn, sinfoRef)
        vprint(opts, '%s  — already on reference grid, copying.', label);
        volOut = volIn;
        return
    end

    vprint(opts, 'Resampling %s...', label);
    [volOut, ~] = harm_resampleVolume(volIn, sinfoIn, sinfoRef, resOpts);
end

% ----------------------------------------------------------------------
function tf = gridsMatch(s1, s2)
%GRIDSMATCH  True if two spatial info structs describe the same voxel grid.
    tol = 0.1;   % mm
    tf = isequal([s1.Rows, s1.Columns, s1.NumSlices], ...
                 [s2.Rows, s2.Columns, s2.NumSlices]) && ...
         all(abs(s1.VoxelSize - s2.VoxelSize) < tol) && ...
         all(abs(s1.ImagePositionFirst - s2.ImagePositionFirst) < tol);
end

% ----------------------------------------------------------------------
function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[harm_harmonizeStudy] ' fmt '\n'], varargin{:});
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

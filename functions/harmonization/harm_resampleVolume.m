function [volOut, sinfoOut] = harm_resampleVolume(volIn, sinfoIn, sinfoRef, opts)
% HARM_RESAMPLEVOLUME  Resample a 3-D volume to match a reference spatial grid.
%
%   [VOLOUT, SINFOOUT] = HARM_RESAMPLEVOLUME(VOLIN, SINFOIN, SINFOREF)
%   resamples VOLIN (described by SINFOIN) onto the voxel grid defined by
%   SINFOREF, using affine mapping and trilinear interpolation.
%
%   This is the core of matrix harmonization (Stage 1): it ensures that all
%   three image sets — Scout, Dixon, MRE — share a common voxel grid so that
%   organ masks computed on Dixon can be directly applied to MRE slices.
%
%   INPUTS
%     volIn       3-D or 4-D numeric array  (source volume)
%     sinfoIn     struct from io_extractSpatialInfo  (source geometry)
%     sinfoRef    struct from io_extractSpatialInfo  (reference geometry)
%     opts        struct (optional):
%                   .method    'linear' | 'nearest' | 'cubic'  (default 'linear')
%                   .fillVal   out-of-bounds fill value  (default 0)
%                   .verbose   true/false  (default false)
%
%   OUTPUTS
%     volOut      resampled volume, same class as volIn, size matches sinfoRef
%     sinfoOut    copy of sinfoRef (the output now lives on this grid)
%
%   ALGORITHM
%     1. Build source voxel-to-world affine (sinfoIn.AffineMatrix).
%     2. Build reference world-to-voxel affine (sinfoRef.AffineMatrixInv).
%     3. Compose:  Tref→src = AffIn_inv * AffRef  (4×4)
%     4. Generate reference grid coordinates, apply Tref→src.
%     5. Interpolate sinfoIn volume at those coordinates.
%
%   NOTES
%     • 4-D volumes (e.g. MRE wave images) are resampled slice-by-slice
%       along the 4th dimension.
%     • Inputs are cast to double for interpolation; output is cast back to
%       the original class of volIn.
%
%   SEE ALSO  harm_harmonizeStudy, io_extractSpatialInfo
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2

    if nargin < 4, opts = struct(); end
    opts = applyDefaults(opts, struct( ...
        'method',  'linear', ...
        'fillVal', 0, ...
        'verbose', false));

    inClass  = class(volIn);
    is4D     = ndims(volIn) == 4;
    nPhases  = size(volIn, 4);

    % ── Build transformation: reference voxel → source voxel ─────────
    % T_world_from_ref = sinfoRef.AffineMatrix
    % T_src_from_world = sinfoRef.AffineMatrixInv (wait — need sinfoIn inv)
    A_ref = sinfoRef.AffineMatrix;          % ref voxel → world
    A_src_inv = sinfoIn.AffineMatrixInv;    % world → src voxel
    T = A_src_inv * A_ref;                  % ref voxel → src voxel (4×4)

    % ── Reference grid size ───────────────────────────────────────────
    nR = sinfoRef.Rows;
    nC = sinfoRef.Columns;
    nS = sinfoRef.NumSlices;

    % ── Generate reference voxel coordinates (0-based) ────────────────
    [Ci, Ri, Si] = meshgrid(0:nC-1, 0:nR-1, 0:nS-1);   % col, row, slice
    coords = [Ci(:)'; Ri(:)'; Si(:)'; ones(1, numel(Ci))];

    % ── Map to source voxel indices (1-based for MATLAB interp) ───────
    srcCoords = T * coords;   % 4 × N
    Xs = srcCoords(1,:) + 1;  % col in source (1-based)
    Ys = srcCoords(2,:) + 1;  % row in source
    Zs = srcCoords(3,:) + 1;  % slice in source

    % ── Source volume size ────────────────────────────────────────────
    [sR, sC, sZ] = size(volIn, 1, 2, 3);

    % ── Interpolate ───────────────────────────────────────────────────
    if ~is4D
        volOut = interpVolume(double(volIn), Xs, Ys, Zs, ...
                              sR, sC, sZ, nR, nC, nS, opts);
    else
        volOut = zeros(nR, nC, nS, nPhases, 'double');
        for ph = 1:nPhases
            slice4D = double(volIn(:,:,:,ph));
            volOut(:,:,:,ph) = interpVolume(slice4D, Xs, Ys, Zs, ...
                                            sR, sC, sZ, nR, nC, nS, opts);
        end
    end

    % Cast back to original type
    volOut = cast(volOut, inClass);

    % ── Output spatial info = reference grid ──────────────────────────
    sinfoOut = sinfoRef;
    sinfoOut.NumPhases = nPhases;

    if opts.verbose
        fprintf('[harm_resampleVolume] %dx%dx%d → %dx%dx%d  method=%s\n', ...
            sR, sC, sZ, nR, nC, nS, opts.method);
    end
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function volR = interpVolume(vol, Xs, Ys, Zs, sR, sC, sZ, nR, nC, nS, opts)
%INTERPVOLUME  Trilinear interpolation of 3-D volume at scattered coords.

    switch opts.method
        case 'nearest'
            Xi = round(Xs); Yi = round(Ys); Zi = round(Zs);
            valid = Xi >= 1 & Xi <= sC & Yi >= 1 & Yi <= sR & ...
                    Zi >= 1 & Zi <= sZ;
            vals = zeros(1, numel(Xs));
            idxSrc = sub2ind([sR sC sZ], Yi(valid), Xi(valid), Zi(valid));
            vals(valid) = vol(idxSrc);

        case 'cubic'
            % Use MATLAB's interp3 with cubic
            [Cg, Rg, Sg] = meshgrid(1:sC, 1:sR, 1:sZ);
            vals = interp3(Cg, Rg, Sg, vol, Xs, Ys, Zs, 'cubic', opts.fillVal);

        otherwise  % 'linear' — default, fast manual trilinear
            x0 = floor(Xs); x1 = x0 + 1;
            y0 = floor(Ys); y1 = y0 + 1;
            z0 = floor(Zs); z1 = z0 + 1;
            fx = Xs - x0;   fy = Ys - y0;   fz = Zs - z0;

            valid = x0>=1 & x1<=sC & y0>=1 & y1<=sR & z0>=1 & z1<=sZ;
            vals  = zeros(1, numel(Xs)) + opts.fillVal;

            % Trilinear weights
            x0v = x0(valid); x1v = x1(valid);
            y0v = y0(valid); y1v = y1(valid);
            z0v = z0(valid); z1v = z1(valid);
            fxv = fx(valid); fyv = fy(valid); fzv = fz(valid);

            % 8 corners
            c000 = vol(sub2ind([sR sC sZ], y0v, x0v, z0v));
            c100 = vol(sub2ind([sR sC sZ], y1v, x0v, z0v));
            c010 = vol(sub2ind([sR sC sZ], y0v, x1v, z0v));
            c110 = vol(sub2ind([sR sC sZ], y1v, x1v, z0v));
            c001 = vol(sub2ind([sR sC sZ], y0v, x0v, z1v));
            c101 = vol(sub2ind([sR sC sZ], y1v, x0v, z1v));
            c011 = vol(sub2ind([sR sC sZ], y0v, x1v, z1v));
            c111 = vol(sub2ind([sR sC sZ], y1v, x1v, z1v));

            vals(valid) = ...
                c000.*(1-fxv).*(1-fyv).*(1-fzv) + ...
                c100.*   fyv .*(1-fxv).*(1-fzv) + ...
                c010.*(1-fyv).*   fxv .*(1-fzv) + ...
                c110.*   fyv .*   fxv .*(1-fzv) + ...
                c001.*(1-fxv).*(1-fyv).*   fzv  + ...
                c101.*   fyv .*(1-fxv).*   fzv  + ...
                c011.*(1-fyv).*   fxv .*   fzv  + ...
                c111.*   fyv .*   fxv .*   fzv;
    end

    volR = reshape(vals, [nR nC nS]);
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k})
            opts.(fields{k}) = defaults.(fields{k});
        end
    end
end

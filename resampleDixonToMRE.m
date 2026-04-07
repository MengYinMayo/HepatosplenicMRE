function dixonResampled = resampleDixonToMRE(S, channel)
% RESAMPLEDIXONTOMRE  Resample a Dixon channel to the MRE voxel grid.
%
%   channel - 'fat' | 'water' | 'inPhase' | 'outPhase' | 'pdff'
%
%   Output: [mreRows x mreCols x nMREslices] single array in MRE grid

    if nargin < 2, channel = 'fat'; end

    % Get source (Dixon) and target (MRE magnitude) geometry
    dixonData = S.dixon.(channel).pixelData;
    dixonHdr1 = S.dixon.(channel).headers{1};
    mreHdr1   = S.mre.magnitude.headers{1};

    nMRE    = S.mre.magnitude.nSlices;
    mreRows = size(S.mre.magnitude.pixelData, 1);
    mreCols = size(S.mre.magnitude.pixelData, 2);
    nDixon  = S.dixon.(channel).nSlices;

    % Build affine transforms for both volumes
    T_dixon = buildAffineFromDICOM(dixonHdr1);
    T_mre   = buildAffineFromDICOM(mreHdr1);

    % Update T_mre slice direction using actual inter-slice spacing
    % (single-slice T_mre has unreliable slice spacing)
    if nMRE > 1
        ipp1 = getHeaderField(S.mre.magnitude.headers{1}, 'ImagePositionPatient', [0;0;0]);
        ipp2 = getHeaderField(S.mre.magnitude.headers{2}, 'ImagePositionPatient', [0;0;0]);
        T_mre(1:3, 3) = ipp2 - ipp1;   % actual inter-slice vector
    end

    dixonResampled = zeros(mreRows, mreCols, nMRE, 'single');

    % For each MRE voxel, compute the corresponding Dixon voxel coordinates
    % and interpolate. Vectorized over in-plane grid per slice.
    [colGrid, rowGrid] = meshgrid(0:mreCols-1, 0:mreRows-1);
    colGrid = colGrid(:)';
    rowGrid = rowGrid(:)';

    for sl = 1:nMRE
        sliceVec = repmat(sl-1, 1, mreRows*mreCols);   % 0-based slice index

        % MRE voxel coordinates (col, row, slice) → physical xyz
        mreIJK = [colGrid; rowGrid; sliceVec];
        xyzPhys = voxelToPhysical(T_mre, mreIJK);

        % Physical xyz → Dixon voxel coordinates
        dixonIJK = physicalToVoxel(T_dixon, xyzPhys);

        % Clamp to Dixon volume bounds for interpolation
        dixonCol   = dixonIJK(1,:) + 1;   % convert to 1-based
        dixonRow   = dixonIJK(2,:) + 1;
        dixonSlice = dixonIJK(3,:) + 1;

        % Mask: which MRE voxels fall within the Dixon volume?
        inBounds = dixonCol >= 1 & dixonCol <= size(dixonData,2) & ...
                   dixonRow >= 1 & dixonRow <= size(dixonData,1) & ...
                   dixonSlice >= 1 & dixonSlice <= nDixon;

        sliceOut = zeros(mreRows, mreCols, 'single');

        if any(inBounds)
            % Trilinear interpolation using interp3
            validCols   = dixonCol(inBounds);
            validRows   = dixonRow(inBounds);
            validSlices = dixonSlice(inBounds);

            interpolated = interp3(dixonData, validCols, validRows, validSlices, ...
                                   'linear', 0);

            sliceFlat = zeros(1, mreRows*mreCols, 'single');
            sliceFlat(inBounds) = single(interpolated);
            sliceOut = reshape(sliceFlat, mreRows, mreCols);
        end

        dixonResampled(:,:,sl) = sliceOut;
    end
end
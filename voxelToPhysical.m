function xyz = voxelToPhysical(T, ijk)
% VOXELTOPHYSICAL  Map voxel indices (0-based) to physical coordinates (mm).
%
%   T   - 4x4 affine matrix from buildAffineFromDICOM
%   ijk - [3 x N] matrix of [col; row; slice] indices (0-based)
%
%   xyz - [3 x N] matrix of [x; y; z] positions in mm (LPS)

    N   = size(ijk, 2);
    ijk_h = [ijk; ones(1,N)];   % homogeneous
    xyz_h = T * ijk_h;
    xyz   = xyz_h(1:3,:);
end
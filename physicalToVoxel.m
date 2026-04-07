function ijk = physicalToVoxel(T, xyz)
% PHYSICALTOVOXEL  Map physical coordinates (mm) to voxel indices (0-based).
%
%   Inverse of voxelToPhysical. Returns non-integer indices for interpolation.

    N     = size(xyz, 2);
    xyz_h = [xyz; ones(1,N)];
    ijk_h = T \ xyz_h;          % backslash = left-divide (T^-1 * xyz_h)
    ijk   = ijk_h(1:3,:);
end
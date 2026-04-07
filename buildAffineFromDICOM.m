function T = buildAffineFromDICOM(hdr)
% BUILDAFFINEFROMDICOM  Construct voxel-to-physical affine transform (4x4).
%
%   T maps [col; row; slice; 1] (0-indexed voxel) → [x; y; z; 1] mm (LPS).
%
%   Implements the standard DICOM affine as defined in the DICOM standard
%   PS3.3 C.7.6.2 — Image Plane Module.

    iop = getHeaderField(hdr, 'ImageOrientationPatient', [1;0;0;0;1;0]);
    ipp = getHeaderField(hdr, 'ImagePositionPatient',    [0;0;0]);
    ps  = getHeaderField(hdr, 'PixelSpacing',            [1;1]);
    st  = getHeaderField(hdr, 'SliceThickness',          1);

    % Row cosine (direction of increasing column index)
    F1 = iop(1:3) * ps(2);   % column direction, scaled by column spacing
    % Column cosine (direction of increasing row index)
    F2 = iop(4:6) * ps(1);   % row direction, scaled by row spacing
    % Slice normal (cross product of row and column cosines)
    n  = cross(iop(1:3), iop(4:6));
    F3 = n * st;              % slice direction, scaled by thickness

    T = [F1(1) F2(1) F3(1) ipp(1);
         F1(2) F2(2) F3(2) ipp(2);
         F1(3) F2(3) F3(3) ipp(3);
         0     0     0     1    ];
end
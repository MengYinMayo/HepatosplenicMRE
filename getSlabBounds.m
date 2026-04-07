function bounds = getSlabBounds(headers)
% Return [nSlices x 2] array of [zTop, zBottom] for each slice.
% z is the projection of IPP onto the slice normal.

    n = numel(headers);
    normal = getSliceNormal(headers{1});
    bounds = zeros(n, 2);

    for i = 1:n
        hdr = headers{i};
        ipp = getHeaderField(hdr, 'ImagePositionPatient', [0;0;0]);
        st  = getHeaderField(hdr, 'SliceThickness', 1);
        zCtr = dot(normal, ipp);   % project onto normal direction
        bounds(i,:) = [zCtr + st/2,  zCtr - st/2];
    end
end

function n = getSliceNormal(hdr)
% Compute slice normal from ImageOrientationPatient.
    iop = getHeaderField(hdr, 'ImageOrientationPatient', [1;0;0;0;1;0]);
    n   = cross(iop(1:3), iop(4:6));
    n   = n / norm(n);
end
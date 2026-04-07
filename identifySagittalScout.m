function [sagImg, sagHdr, scoutAffine] = identifySagittalScout(S)
% IDENTIFYSAGITTALSCOUT  Find the mid-sagittal image from the 3-plane scout.
%
%   The sagittal plane has a slice normal closest to the patient L-R axis
%   (first component of IOP cross product ≈ ±1).

    if ~S.scout.identified || isempty(S.scout.headers)
        error('identifySagittalScout:noScout', 'No scout series loaded.');
    end

    headers = S.scout.headers;
    nScout  = numel(headers);

    bestDot  = -1;
    bestIdx  = 1;
    LR_axis  = [1; 0; 0];    % patient left-right = x in LPS

    for i = 1:nScout
        iop = getHeaderField(headers{i}, 'ImageOrientationPatient', [1;0;0;0;1;0]);
        n   = cross(iop(1:3), iop(4:6));
        n   = n / norm(n);
        d   = abs(dot(n, LR_axis));
        if d > bestDot
            bestDot = d;
            bestIdx = i;
        end
    end

    if bestDot < 0.85
        warning('identifySagittalScout:notSagittal', ...
            'Best scout plane has dot=%.2f with L-R axis — may not be truly sagittal.', bestDot);
    end

    sagHdr     = headers{bestIdx};
    rawImg     = dicomread(sagHdr);
    slope      = getHeaderField(sagHdr, 'RescaleSlope',     1);
    intercept  = getHeaderField(sagHdr, 'RescaleIntercept', 0);
    sagImg     = single(rawImg) * slope + intercept;
    scoutAffine = buildAffineFromDICOM(sagHdr);
end
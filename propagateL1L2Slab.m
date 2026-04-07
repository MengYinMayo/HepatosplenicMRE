function S = propagateL1L2Slab(S, varargin)
% PROPAGATEL1L2SLAB  Find Dixon and MRE slices within the L1-L2 slab.
%
%   Populates:
%     S.landmarks.L1L2.dixonSlices  - Dixon slice indices overlapping slab
%     S.landmarks.L1L2.mreSlices    - MRE slice indices overlapping slab
%     S.landmarks.L1L2.mreCoverage  - fraction of slab covered by MRE FOV

    p = inputParser();
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    if ~S.landmarks.L1L2.defined
        error('propagateL1L2Slab:notDefined', 'L1-L2 slab not yet confirmed.');
    end

    zSup = S.landmarks.L1L2.L1_sup_z_mm;   % superior z (larger value in LPS)
    zInf = S.landmarks.L1L2.L2_inf_z_mm;   % inferior z (smaller value)

    SI_axis = [0; 0; 1];

    %% --- Dixon propagation ---
    dixonHdrs = S.dixon.fat.headers;   % all channels have identical geometry
    nDixon    = numel(dixonHdrs);
    dixonBounds = zeros(nDixon, 2);   % [zTop, zBot] per slice

    for sl = 1:nDixon
        hdr = dixonHdrs{sl};
        ipp = getHeaderField(hdr, 'ImagePositionPatient', [0;0;0]);
        st  = getHeaderField(hdr, 'SliceThickness', 1);
        iop = getHeaderField(hdr, 'ImageOrientationPatient', [1;0;0;0;1;0]);
        n   = cross(iop(1:3), iop(4:6)); n = n / norm(n);
        zCtr = dot(n, ipp);
        dixonBounds(sl,:) = [zCtr + st/2,  zCtr - st/2];
    end

    % Find Dixon slices with any overlap with [zInf, zSup]
    dixonOverlap = zeros(1, nDixon);
    for sl = 1:nDixon
        slTop = dixonBounds(sl,1);
        slBot = dixonBounds(sl,2);
        overlapTop = min(zSup, slTop);
        overlapBot = max(zInf, slBot);
        dixonOverlap(sl) = max(0, overlapTop - overlapBot);
    end

    dixonIdx = find(dixonOverlap > 0);
    S.landmarks.L1L2.dixonSlices        = dixonIdx;
    S.landmarks.L1L2.dixonSliceWeights  = dixonOverlap(dixonIdx) / sum(dixonOverlap(dixonIdx));
    S.landmarks.L1L2.nDixonSlices       = numel(dixonIdx);

    if opts.Verbose
        fprintf('[L1-L2] Dixon slices in slab: %s (n=%d)\n', ...
            mat2str(dixonIdx), numel(dixonIdx));
    end

    if isempty(dixonIdx)
        S.qc.flags{end+1} = 'L1-L2 slab: no overlapping Dixon slices — check FOV';
        S.qc.reviewNeeded = true;
        warning('propagateL1L2Slab:noDixon', 'No Dixon slices overlap L1-L2 slab.');
    end

    %% --- MRE propagation ---
    if ~S.mre.stiffness.identified || isempty(S.mre.stiffness.headers)
        S.landmarks.L1L2.mreSlices   = [];
        S.landmarks.L1L2.mreCoverage = 0;
        S.qc.flags{end+1} = 'L1-L2: MRE stiffness series not available — stiffness at L1-L2 not extractable';
        if opts.Verbose
            fprintf('[L1-L2] MRE stiffness not found — skipping MRE propagation\n');
        end
        return
    end

    mreHdrs   = S.mre.stiffness.headers;
    nMRE      = numel(mreHdrs);
    mreBounds = zeros(nMRE, 2);

    for sl = 1:nMRE
        hdr = mreHdrs{sl};
        ipp = getHeaderField(hdr, 'ImagePositionPatient', [0;0;0]);
        st  = getHeaderField(hdr, 'SliceThickness', 1);
        iop = getHeaderField(hdr, 'ImageOrientationPatient', [1;0;0;0;1;0]);
        n   = cross(iop(1:3), iop(4:6)); n = n / norm(n);
        zCtr = dot(n, ipp);
        mreBounds(sl,:) = [zCtr + st/2, zCtr - st/2];
    end

    mreOverlap = zeros(1, nMRE);
    for sl = 1:nMRE
        overlapTop = min(zSup, mreBounds(sl,1));
        overlapBot = max(zInf, mreBounds(sl,2));
        mreOverlap(sl) = max(0, overlapTop - overlapBot);
    end

    mreIdx   = find(mreOverlap > 0);
    slabThk  = S.landmarks.L1L2.slab_thickness_mm;
    coverage = min(1, sum(mreOverlap) / slabThk);

    S.landmarks.L1L2.mreSlices         = mreIdx;
    S.landmarks.L1L2.mreSliceWeights   = mreOverlap(mreIdx) / max(1, sum(mreOverlap(mreIdx)));
    S.landmarks.L1L2.mreCoverage       = coverage;

    if opts.Verbose
        fprintf('[L1-L2] MRE slices in slab: %s (n=%d, coverage=%.0f%%)\n', ...
            mat2str(mreIdx), numel(mreIdx), coverage*100);
    end

    if coverage < 0.5
        msg = sprintf('L1-L2: MRE coverage only %.0f%% — stiffness at this level unreliable', coverage*100);
        S.qc.flags{end+1} = msg;
        S.qc.reviewNeeded = true;
        if opts.Verbose, fprintf('[L1-L2] WARNING: %s\n', msg); end
    end
end
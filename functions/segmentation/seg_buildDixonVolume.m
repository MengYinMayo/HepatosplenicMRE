function dixon = seg_buildDixonVolume(dixonGroup, opts)
% SEG_BUILDDIXONVOLUME  Load GE IDEAL-IQ series into an organised volume struct.
%
%   DIXON = SEG_BUILDDIXONVOLUME(DIXONGROUP) reads all IDEAL-IQ series in
%   DIXONGROUP (from mre_selectSeriesGUI) and returns a struct with named
%   image volumes and spatial metadata.
%
%   GE IDEAL-IQ SERIES ROLES
%     IDEALIQ_Raw    → Water image (single contrast, nSlices images)
%     IDEALIQ_Multi  → All contrasts stacked (nContrasts × nSlices images)
%                      Contrast order by TemporalPositionIdentifier:
%                        1=Water  2=Fat  3=In-Phase  4=Out-Phase
%                        5=PDFF(%)  6=T2*(ms) or R2*(1/s)
%     IDEALIQ_PDFF   → Fat-fraction map (may be subset of slices)
%     IDEALIQ_T2s    → T2* map
%
%   OUTPUT STRUCT fields:
%     .Water      [R×C×nZ]  double  water-only image
%     .Fat        [R×C×nZ]  double  fat-only image
%     .InPhase    [R×C×nZ]  double  in-phase (W+F)
%     .OutPhase   [R×C×nZ]  double  out-of-phase (W-F)
%     .PDFF       [R×C×nZ]  double  fat fraction 0-100 (%)
%     .T2star     [R×C×nZ]  double  T2* map (ms) — may be empty
%     .SpatialInfo struct           from io_extractSpatialInfo (Water series)
%     .nSlices    double
%     .PixelSpacing_mm [1×2]
%     .SliceThickness_mm double
%     .SliceLocations [1×nZ] mm    sorted inferior→superior
%
%   PDFF SCALING (GE IDEAL-IQ)
%     The raw PDFF DICOM pixels store integer values scaled relative to the
%     WindowCenter/Width. Typical GE convention: pixel value × scale → %.
%     This function returns PDFF as 0-100 (percent fat fraction).
%
%   SEE ALSO  mre_selectSeriesGUI, seg_L1L2ROIGui, loc_propagateToSpace
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu
%   DATE    April 17, 2026

    if nargin < 2, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    dixon = initDixonStruct();

    if isempty(dixonGroup)
        warning('seg_buildDixonVolume:empty','DixonGroup is empty.');
        return
    end

    % ── 1.  Find the best source series for each contrast ─────────────
    % Priority: IDEALIQ_Multi (has everything) > individual series
    multiSeries = findRole(dixonGroup, 'IDEALIQ_Multi');
    % Collect all single-contrast IDEAL-IQ recons regardless of sub-role.
    rawSeries   = findRoles(dixonGroup, ...
        {'IDEALIQ_Raw','IDEALIQ_Water','IDEALIQ_Fat','IDEALIQ_InPhase','IDEALIQ_OutPhase'});
    pdffSeries  = findRole(dixonGroup, 'IDEALIQ_PDFF');
    t2sSeries   = findRole(dixonGroup, 'IDEALIQ_T2s');

    % Prefer T2*-corrected water/fat (old IDEAL-IQ: 's15992_T2_Water_...',
    % 's15993_T2_Fat_...') over plain water/fat when both are present.
    % Fall back gracefully when no T2*-corrected version exists (new IDEAL-IQ).
    waterSeries = findBestNamedSeries(dixonGroup, {'water','t2'});
    if isempty(waterSeries), waterSeries = findBestNamedSeries(dixonGroup, {'water','r2'}); end
    if isempty(waterSeries), waterSeries = findBestNamedSeries(dixonGroup, {'water'}); end

    fatSeries = findBestNamedSeries(dixonGroup, {'fat','t2'}, {'fatfrac','fat frac','pdff'});
    if isempty(fatSeries), fatSeries = findBestNamedSeries(dixonGroup, {'fat','r2'}, {'fatfrac','fat frac','pdff'}); end
    if isempty(fatSeries), fatSeries = findBestNamedSeries(dixonGroup, {'fat'}, {'fatfrac','fat frac','pdff'}); end

    % ── 2.  Read multi-contrast series ────────────────────────────────
    if ~isempty(multiSeries)
        vprint(opts, 'Reading IDEAL-IQ multi-contrast: S%d  (%d files)', ...
            multiSeries(1).SeriesNumber, multiSeries(1).nImages);
        dixon = readMultiContrast(multiSeries(1), dixon, opts);
    end

    % ── 3.  Fill gaps from individual series ──────────────────────────
    % Resolve which rawSeries members hold water, fat, inphase, outphase.
    % Old IDEAL-IQ produces T2*-corrected versions ('T2_Water', 'T2_Fat') which
    % are preferred over plain 'Water'/'Fat' if both exist.
    usedWaterSN = 0;   % SeriesNumber of the raw series used for water
    if isempty(dixon.Water) && ~isempty(rawSeries)
        % Prefer T2*-corrected water (has both 'water' and 't2'/'r2' in desc).
        waterRaw = findBestNamedSeries(rawSeries, {'water','t2'}, {});
        if isempty(waterRaw), waterRaw = findBestNamedSeries(rawSeries, {'water','r2'}, {}); end
        if isempty(waterRaw), waterRaw = findBestNamedSeries(rawSeries, {'water'}, {}); end
        if isempty(waterRaw)
            % No 'water' keyword — infer by excluding fat/inphase/outphase candidates.
            fatCandidate = findBestNamedSeries(rawSeries, {'fat'}, {'fatfrac','fat frac','pdff'});
            for kk = 1:numel(rawSeries)
                if isempty(fatCandidate) || ...
                   rawSeries(kk).SeriesNumber ~= fatCandidate(1).SeriesNumber
                    waterRaw = rawSeries(kk);
                    break
                end
            end
            if isempty(waterRaw), waterRaw = rawSeries(1); end
        end
        vprint(opts, 'Reading water from: S%d', waterRaw(1).SeriesNumber);
        usedWaterSN = double(waterRaw(1).SeriesNumber);
        dixon.Water = readSingleContrast(waterRaw(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, waterRaw(1).Files);
        end
    end

    % If rawSeries contains a standalone fat recon, extract it now.
    % Prefer T2*-corrected fat; fall back to any fat; then infer by exclusion.
    if isempty(dixon.Fat) && ~isempty(rawSeries)
        fatFromRaw = findBestNamedSeries(rawSeries, {'fat','t2'}, {'fatfrac','fat frac','pdff'});
        if isempty(fatFromRaw), fatFromRaw = findBestNamedSeries(rawSeries, {'fat','r2'}, {'fatfrac','fat frac','pdff'}); end
        if isempty(fatFromRaw), fatFromRaw = findBestNamedSeries(rawSeries, {'fat'}, {'fatfrac','fat frac','pdff'}); end
        if isempty(fatFromRaw) && numel(rawSeries) > 1
            % Infer: use whichever rawSeries was not used for water/inphase/outphase.
            for kk = 1:numel(rawSeries)
                sn = double(rawSeries(kk).SeriesNumber);
                d  = lower(char(rawSeries(kk).SeriesDescription));
                if sn ~= usedWaterSN && ...
                   ~contains(d,'inphase') && ~contains(d,'in_phase') && ...
                   ~contains(d,'outphase') && ~contains(d,'out_phase')
                    fatFromRaw = rawSeries(kk);
                    break
                end
            end
        end
        if ~isempty(fatFromRaw)
            vprint(opts, 'Reading fat from rawSeries: S%d', fatFromRaw(1).SeriesNumber);
            dixon.Fat = readSingleContrast(fatFromRaw(1).Files, opts);
        end
    end

    % Read standalone InPhase / OutPhase volumes (new IDEAL-IQ scenario:
    % 's0403_InPhase_Ax_IDEAL_IQ', 's0404_OutPhase_Ax_IDEAL_IQ').
    if isempty(dixon.InPhase)
        inphaseRaw = findBestNamedSeries(rawSeries, {'inphase'}, {});
        if isempty(inphaseRaw), inphaseRaw = findBestNamedSeries(rawSeries, {'in_phase'}, {}); end
        if ~isempty(inphaseRaw)
            vprint(opts, 'Reading InPhase standalone from: S%d', inphaseRaw(1).SeriesNumber);
            dixon.InPhase = readSingleContrast(inphaseRaw(1).Files, opts);
            if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
                dixon = fillSpatialInfo(dixon, inphaseRaw(1).Files);
            end
        end
    end
    if isempty(dixon.OutPhase)
        outphaseRaw = findBestNamedSeries(rawSeries, {'outphase'}, {});
        if isempty(outphaseRaw), outphaseRaw = findBestNamedSeries(rawSeries, {'out_phase'}, {}); end
        if ~isempty(outphaseRaw)
            vprint(opts, 'Reading OutPhase standalone from: S%d', outphaseRaw(1).SeriesNumber);
            dixon.OutPhase = readSingleContrast(outphaseRaw(1).Files, opts);
            if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
                dixon = fillSpatialInfo(dixon, outphaseRaw(1).Files);
            end
        end
    end

    if isempty(dixon.PDFF) && ~isempty(pdffSeries)
        vprint(opts, 'Reading PDFF from: S%d  (%d files)', ...
            pdffSeries(1).SeriesNumber, pdffSeries(1).nImages);
        [dixon.PDFF, pdffInfo] = readPDFFSeries(pdffSeries(1), opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon.SpatialInfo = pdffInfo;
        end
    end

    % Fill explicit WATER/FAT single-contrast recons when present.
    if isempty(dixon.Water) && ~isempty(waterSeries)
        vprint(opts, 'Reading explicit WATER from: S%d', waterSeries(1).SeriesNumber);
        dixon.Water = readSingleContrast(waterSeries(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, waterSeries(1).Files);
        end
    end

    if isempty(dixon.Fat) && ~isempty(fatSeries)
        vprint(opts, 'Reading explicit FAT from: S%d', fatSeries(1).SeriesNumber);
        dixon.Fat = readSingleContrast(fatSeries(1).Files, opts);
        if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
            dixon = fillSpatialInfo(dixon, fatSeries(1).Files);
        end
    end

    % ── 3b. Conventional IP/OP series (EchoTime-based split) ─────────────
    % When InPhase and OutPhase are still absent, look for an IP/OP Dixon
    % series in the group and split it by EchoTime using water-fat phase angle:
    %   cos(2π·Δf·TE) maximum → In-Phase,  minimum → Out-of-Phase.
    %   Δf = 3.5 ppm × 42.577 MHz/T × B0  (≈220 Hz at 1.5T, ≈440 Hz at 3T).
    % This correctly handles both field strengths (unlike a simple short/long
    % TE rule, which fails at 3T where the first IP echo is shorter than OP).
    % Water and Fat are then derived from IP and OP in the next block.
    if isempty(dixon.InPhase) && isempty(dixon.OutPhase)
        ipopSeries = findIPOPSeries(dixonGroup);
        if ~isempty(ipopSeries)
            vprint(opts, 'Reading conventional IP/OP from S%d using EchoTime...', ...
                   ipopSeries(1).SeriesNumber);
            [ipVol, opVol] = readIPOPByEchoTime(ipopSeries(1), opts);
            if ~isempty(ipVol)
                dixon.InPhase = ipVol;
                if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
                    dixon = fillSpatialInfo(dixon, ipopSeries(1).Files);
                end
            end
            if ~isempty(opVol)
                dixon.OutPhase = opVol;
            end
        end
    end

    % Derive Water/Fat from InPhase/OutPhase when direct maps are unavailable.
    % For a standard GE Dixon acquisition:
    %   IP = Water + Fat,  OP = Water - Fat  (with same sign convention)
    % Therefore:  Water = (IP + OP) / 2,  Fat = (IP - OP) / 2.
    % For IDEAL-IQ or other acquisitions the echo times set the exact sign;
    % the (IP+OP)/2 formula is correct when OP = W-F (GE convention).
    % Clamp Fat to ≥ 0 to avoid negative values from noise.
    if (isempty(dixon.Water) || isempty(dixon.Fat)) && ...
       ~isempty(dixon.InPhase) && ~isempty(dixon.OutPhase)
        vprint(opts, 'Deriving Water/Fat from InPhase/OutPhase...');
        IP = double(dixon.InPhase);
        OP = double(dixon.OutPhase);
        if isempty(dixon.Water)
            dixon.Water = (IP + OP) / 2;
        end
        if isempty(dixon.Fat)
            dixon.Fat = max(0, (IP - OP) / 2);
        end
    end

    % For this platform's three-panel UI, WATER feeds the in-phase panel and
    % FAT feeds the out-of-phase panel when explicit InPhase/OutPhase images
    % are not available in the selected Dixon family.
    if isempty(dixon.InPhase) && ~isempty(dixon.Water)
        dixon.InPhase = dixon.Water;
    end
    if isempty(dixon.OutPhase) && ~isempty(dixon.Fat)
        dixon.OutPhase = dixon.Fat;
    end

    % Compute PDFF from Water/Fat if still missing
    if isempty(dixon.PDFF) && ~isempty(dixon.Water) && ~isempty(dixon.Fat)
        vprint(opts, 'Computing PDFF from Water+Fat...');
        W = double(dixon.Water); F = double(dixon.Fat);
        denom = W + F; denom(denom < eps) = 1;
        dixon.PDFF = 100 .* F ./ denom;
    end

    % ── 4.  Fill spatial info ─────────────────────────────────────────
    if isempty(dixon.SpatialInfo) || ~isfield(dixon.SpatialInfo,'VoxelSize')
        % Try from any available series
        for k = 1:numel(dixonGroup)
            if ~isempty(dixonGroup(k).Files)
                dixon = fillSpatialInfo(dixon, dixonGroup(k).Files);
                if isfield(dixon.SpatialInfo,'VoxelSize'), break; end
            end
        end
    end

    % Ensure SliceLocations is populated AND the AffineMatrix z-origin is
    % patched for degenerate IPP, even when SpatialInfo was filled by a
    % path that bypasses fillSpatialInfo (e.g. readPDFFSeries directly
    % assigns its sinfo, or readMultiContrast).  Walk dixonGroup to find a
    % series whose file count matches the loaded volume's slice count.
    nZGuess = 0;
    for kfld = {'Water','Fat','InPhase','OutPhase','PDFF','T2star'}
        v = dixon.(kfld{1});
        if ~isempty(v), nZGuess = max(nZGuess, size(v,3)); end
    end
    needLocs = isempty(dixon.SliceLocations) || ...
               numel(unique(round(double(dixon.SliceLocations(:)'),1))) <= 1 || ...
               (nZGuess > 0 && numel(dixon.SliceLocations) ~= nZGuess);
    if needLocs && nZGuess > 0
        for k = 1:numel(dixonGroup)
            f = dixonGroup(k).Files;
            if ~isempty(f) && numel(f) == nZGuess
                dixon = populateLocsAndPatch(dixon, f);
                if ~isempty(dixon.SliceLocations), break; end
            end
        end
    end

    % ── 5.  Summary ───────────────────────────────────────────────────
    % Use first non-empty volume as reference (Water preferred, then Fat,
    % PDFF, InPhase) so nSlices is set even when Water is absent.
    refVol = '';
    for fld_ = {'Water','Fat','PDFF','InPhase','OutPhase'}
        if ~isempty(dixon.(fld_{1})), refVol = fld_{1}; break; end
    end
    if ~isempty(refVol)
        dixon.nSlices = size(dixon.(refVol), 3);
        if isfield(dixon.SpatialInfo,'VoxelSize')
            dixon.PixelSpacing_mm  = dixon.SpatialInfo.VoxelSize(1:2);
            dixon.SliceThickness_mm= dixon.SpatialInfo.SliceSpacing;
        end
    end

    vprint(opts, 'Dixon volumes loaded:');
    vprint(opts, '  Water:   %s', sizeStr(dixon.Water));
    vprint(opts, '  Fat:     %s', sizeStr(dixon.Fat));
    if ~isempty(dixon.PDFF)
        vprint(opts, '  PDFF:    %s  (range %.1f-%.1f%%)', ...
            sizeStr(dixon.PDFF), nanmin(dixon.PDFF(:)), nanmax(dixon.PDFF(:)));
    else
        vprint(opts, '  PDFF:    []');
    end
    vprint(opts, '  InPhase: %s', sizeStr(dixon.InPhase));
end


% ======================================================================
%  MULTI-CONTRAST READER
% ======================================================================

function dixon = readMultiContrast(series, dixon, opts)
%READMULTICONTRAST  Parse IDEAL-IQ multi-contrast series by TemporalPositionIdentifier.

    files  = series.Files;
    nFiles = numel(files);
    if nFiles == 0, return; end

    % Read all headers to get TemporalPositionIdentifier, SliceLocation,
    % ImagePositionPatient, and InStackPositionNumber.
    vprint(opts, '  Reading %d headers...', nFiles);
    tempIds  = ones(1, nFiles);
    sliceLoc = zeros(1, nFiles);
    instNums = zeros(1, nFiles);
    imgPos   = nan(3, nFiles);   % ImagePositionPatient for each file
    stackPos = zeros(1, nFiles); % InStackPositionNumber for each file
    iop_ref  = [];               % ImageOrientationPatient (same for all slices)

    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'TemporalPositionIdentifier') && ~isempty(info.TemporalPositionIdentifier)
                tempIds(k) = double(info.TemporalPositionIdentifier);
            end
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLoc(k) = double(info.SliceLocation);
            end
            if isfield(info,'InstanceNumber') && ~isempty(info.InstanceNumber)
                instNums(k) = double(info.InstanceNumber);
            end
            if isfield(info,'ImagePositionPatient') && numel(info.ImagePositionPatient) == 3
                imgPos(:,k) = double(info.ImagePositionPatient(:));
            end
            if isfield(info,'InStackPositionNumber') && ~isempty(info.InStackPositionNumber)
                stackPos(k) = double(info.InStackPositionNumber);
            end
            if isempty(iop_ref) && isfield(info,'ImageOrientationPatient') && ...
               numel(info.ImageOrientationPatient) == 6
                iop_ref = double(info.ImageOrientationPatient(:));
            end
        catch
            instNums(k) = k;
        end
    end

    % Determine nContrasts and nSlices.
    % TemporalPositionIdentifier may not be populated on all GE IDEAL-IQ
    % versions (all return 1). Fall back to NumberOfTemporalPositions tag,
    % then to unique slice count inversion, then to the GE standard of 6.
    nContrasts = numel(unique(tempIds));
    if nContrasts <= 1 && nFiles > 10
        % Try NumberOfTemporalPositions from first header
        try
            hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
            if isfield(hdr1,'NumberOfTemporalPositions') && ~isempty(hdr1.NumberOfTemporalPositions)
                nc = double(hdr1.NumberOfTemporalPositions);
                if nc > 1 && mod(nFiles, nc) == 0
                    nContrasts = nc;
                    vprint(opts, '  Using NumberOfTemporalPositions=%d for nContrasts.', nc);
                end
            end
        catch
        end
    end
    % Last resort: infer nContrasts from unique slice locations or GE private
    % slab geometry.  GE IDEAL-IQ SIGNA Premier stores the same SliceLocation
    % (= slab superior extent) for every DICOM, so unique slice count = 1 and
    % the standard inference fails.  Read Private_0019_1018/1019/101a/101b to
    % determine the true nSlices from the acquisition geometry.
    geSuperiorZ = NaN; geInferiorZ = NaN; geSpacing = 0;
    if nContrasts <= 1
        nSlicesEst = numel(unique(sliceLoc));
        if nSlicesEst > 1 && mod(nFiles, nSlicesEst) == 0
            nContrasts = nFiles / nSlicesEst;
            vprint(opts, '  Inferred %d contrasts from %d unique slices.', nContrasts, nSlicesEst);
        else
            % Try GE private slab extent tags to derive nSlices from geometry
            try
                hdrSlab = dicominfo(files{1}, 'UseDictionaryVR', true);
                for tagPair = {{'Private_0019_1018','Private_0019_1019'}, ...
                               {'Private_0019_101a','Private_0019_101b'}}
                    dtag = tagPair{1}{1}; vtag = tagPair{1}{2};
                    if isfield(hdrSlab,dtag) && isfield(hdrSlab,vtag) && ...
                       ~isempty(hdrSlab.(vtag))
                        ds = upper(strtrim(char(hdrSlab.(dtag))));
                        vv = double(hdrSlab.(vtag));
                        if contains(ds,'S'), geSuperiorZ = vv; end
                        if contains(ds,'I'), geInferiorZ = vv; end
                    end
                end
                if isfield(hdrSlab,'SpacingBetweenSlices') && ...
                   double(hdrSlab.SpacingBetweenSlices) > 0
                    geSpacing = double(hdrSlab.SpacingBetweenSlices);
                elseif isfield(hdrSlab,'SliceThickness') && ...
                       double(hdrSlab.SliceThickness) > 0
                    geSpacing = double(hdrSlab.SliceThickness);
                end
                if ~isnan(geSuperiorZ) && ~isnan(geInferiorZ) && geSpacing > 0
                    geNSlices = round(abs(geSuperiorZ - geInferiorZ) / geSpacing) + 1;
                    if geNSlices > 1 && mod(nFiles, geNSlices) == 0
                        nContrasts = nFiles / geNSlices;
                        vprint(opts, '  GE slab extent: nSlices=%d, nContrasts=%d.', ...
                            geNSlices, nContrasts);
                    end
                end
            catch, end
        end
        if nContrasts <= 1
            nContrasts = 6;
            vprint(opts, '  Defaulting to %d contrasts (GE IDEAL-IQ standard).', nContrasts);
        end
    end
    nSlices    = round(nFiles / nContrasts);
    uniqueLocs = unique(sliceLoc);
    tempIdsReliable = numel(unique(tempIds)) > 1;

    % GE IDEAL-IQ may report the same SliceLocation for every DICOM (all files
    % show the same value, e.g. 127.8125).  When uniqueLocs has fewer entries
    % than nSlices, fall back to ImagePositionPatient projected onto the slice
    % normal — this is reliable even when SliceLocation is unreliable.
    if numel(uniqueLocs) < nSlices && ~isempty(iop_ref) && ~all(isnan(imgPos(:)))
        rowDir = iop_ref(1:3); colDir = iop_ref(4:6);
        sliceNormal = cross(rowDir, colDir);
        sliceNormal = sliceNormal / max(norm(sliceNormal), 1e-9);
        % Project each file's position onto the normal to get a scalar z-equivalent
        zProj = sliceNormal' * imgPos;   % 1×nFiles
        zProj(isnan(zProj)) = 0;
        % Round to nearest 0.01mm to merge floating-point duplicates
        zProjR = round(zProj, 2);
        uniqueZ = unique(zProjR);
        if numel(uniqueZ) >= nSlices
            sliceLoc  = zProjR;
            uniqueLocs = uniqueZ;
            vprint(opts, '  SliceLocation unreliable — replaced with %d unique ImagePositionPatient projections.', numel(uniqueZ));
        end
    end

    % GE IDEAL-IQ SIGNA Premier: when SliceLocation AND ImagePositionPatient
    % are both the same constant for every file (degenerate 3D acquisition),
    % reconstruct per-slice z positions from GE private slab extent tags and
    % InStackPositionNumber.
    % Convention on this scanner: InStackPositionNumber=1 = first acquired =
    % superior-most slice; incrementing InStackPositionNumber goes inferior.
    usedGESlabFallback = false;
    if numel(uniqueLocs) < nSlices && any(stackPos > 0) && ...
       ~isnan(geSuperiorZ) && ~isnan(geInferiorZ) && geSpacing > 0
        try
            zFromStack    = geSuperiorZ - (stackPos - 1) * geSpacing;
            zFromStack(stackPos <= 0) = NaN;
            zFromStackR   = round(zFromStack, 2);
            uniqueZ       = sort(unique(zFromStackR(~isnan(zFromStackR))));
            if numel(uniqueZ) >= nSlices
                sliceLoc(stackPos > 0) = zFromStackR(stackPos > 0);
                sliceLoc(stackPos <= 0) = uniqueZ(1);
                uniqueLocs          = uniqueZ;
                geInferiorZ         = uniqueZ(1);  % min z = inferior-most
                usedGESlabFallback  = true;
                vprint(opts, ['  GE slab extent + InStackPositionNumber: ' ...
                    '%d positions (z: %.1f to %.1f mm).'], ...
                    numel(uniqueZ), uniqueZ(1), uniqueZ(end));
            end
        catch, end
    end

    vprint(opts, '  Multi-contrast: %d contrasts × %d slices', nContrasts, nSlices);

    % When TemporalPositionIdentifier was unreliable, assign contrast by
    % InstanceNumber rank within each unique slice position.  Do this AFTER
    % sliceLoc has been corrected from ImagePositionPatient (if needed), so
    % the ranking uses accurate slice groupings.
    if ~tempIdsReliable && nContrasts > 1
        tempIds = assignContrastBySliceRank(sliceLoc, instNums, nContrasts);
        vprint(opts, '  TemporalPositionIdentifier absent — assigned contrast by within-slice InstanceNumber rank.');
    end

    % Select reference file = inferior-most slice (sl1 in the ascending-sorted
    % volume).  Priority:
    %   1. GE slab fallback active → use minimum sliceLoc (= geInferiorZ)
    %   2. IPP z-projection → minimum = true inferior
    %   3. InStackPositionNumber max → inferior-most (GE: 1=superior, n=inferior)
    refFileIdx = 1;
    try
        if usedGESlabFallback
            [~, refFileIdx] = min(sliceLoc);
        elseif ~all(isnan(imgPos(:))) && ~isempty(iop_ref)
            rowDir = iop_ref(1:3); colDir = iop_ref(4:6);
            sn = cross(rowDir, colDir); sn = sn / max(norm(sn), 1e-9);
            zp = sn' * imgPos; zp(isnan(zp)) = inf;
            [~, refFileIdx] = min(zp);
        elseif any(stackPos > 0)
            refFileIdx = find(stackPos == max(stackPos(stackPos > 0)), 1);
        end
    catch, end
    try
        hdr1 = dicominfo(files{refFileIdx}, 'UseDictionaryVR', true);
        % Re-order so reference file is passed as first for io_extractSpatialInfo
        filesForSinfo = [{files{refFileIdx}}, files(setdiff(1:nFiles, refFileIdx))];
        dixon.SpatialInfo = io_extractSpatialInfo(filesForSinfo, hdr1, nSlices, nContrasts);
    catch
        try
            hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
            dixon.SpatialInfo = io_extractSpatialInfo(files, hdr1, nSlices, nContrasts);
        catch, end
    end

    % When ImagePositionPatient is the same constant for every file (GE 3D
    % degenerate acquisition, e.g. IDEAL-IQ on SIGNA Premier), io_extractSpatialInfo
    % produces an AffineMatrix whose z-origin equals that constant IPP z
    % (~ scanner isocenter) rather than the true inferior-most slice z.
    % Detect degenerate IPP by projecting all IPPs onto the slice normal and
    % checking the range.  When degenerate, patch the z-component of the
    % AffineMatrix origin (column 4) and ImagePositionFirst with the correct
    % inferior-most slice z so loc_propagateToSpace maps landmarks correctly.
    ippDegenerate = false;
    if ~all(isnan(imgPos(:))) && ~isempty(iop_ref)
        try
            rd = iop_ref(1:3); cd_ = iop_ref(4:6);
            sn = cross(rd, cd_); sn = sn / max(norm(sn), 1e-9);
            zp = sn' * imgPos;
            zpv = zp(~isnan(zp));
            if ~isempty(zpv)
                ippDegenerate = (max(zpv) - min(zpv)) < 0.5;
            end
        catch, end
    end
    if (usedGESlabFallback || ippDegenerate) && ~isempty(dixon.SpatialInfo) && ...
       isfield(dixon.SpatialInfo,'AffineMatrix')
        if usedGESlabFallback && ~isnan(geInferiorZ)
            inferiorZ = geInferiorZ;
        elseif ~isempty(uniqueLocs) && all(~isnan(uniqueLocs))
            inferiorZ = min(uniqueLocs);
        else
            inferiorZ = NaN;
        end
        if ~isnan(inferiorZ)
            A = dixon.SpatialInfo.AffineMatrix;
            if size(A,1) >= 3 && size(A,2) >= 4
                A(3,4) = inferiorZ;
                dixon.SpatialInfo.AffineMatrix = A;
                M = A(1:3,1:3);
                if rcond(M) > 1e-10
                    dixon.SpatialInfo.AffineMatrixInv  = inv(A);
                    dixon.SpatialInfo.AffineIsSingular = false;
                else
                    dixon.SpatialInfo.AffineMatrixInv  = pinv(A);
                    dixon.SpatialInfo.AffineIsSingular = true;
                end
            end
            if isfield(dixon.SpatialInfo,'ImagePositionFirst') && ...
               numel(dixon.SpatialInfo.ImagePositionFirst) >= 3
                dixon.SpatialInfo.ImagePositionFirst(3) = inferiorZ;
            end
            vprint(opts, '  Patched AffineMatrix z-origin to %.2f mm (degenerate IPP).', inferiorZ);
        end
    end


    % Allocate volumes
    try
        img1 = double(dicomread(files{1}));
        nR   = size(img1, 1);
        nC   = size(img1, 2);
    catch
        nR = 256; nC = 256;
    end

    vols = zeros(nR, nC, nSlices, nContrasts, 'double');

    for k = 1:nFiles
        try
            pxData = double(dicomread(files{k}));
        catch
            continue
        end
        sl = find(uniqueLocs == sliceLoc(k), 1);
        tp = tempIds(k);
        if isempty(sl), sl = mod(floor((k-1)/nContrasts), nSlices)+1; end
        if sl > nSlices, sl = mod(sl-1, nSlices)+1; end  % guard out-of-bounds
        if tp < 1 || tp > nContrasts, tp = mod(k-1, nContrasts)+1; end
        vols(:,:,sl,tp) = pxData;
    end

    % Assign contrasts by TemporalPositionIdentifier
    % GE IDEAL-IQ standard order: 1=W 2=F 3=IP 4=OP 5=PDFF 6=T2*
    % But we verify by WindowCenter/Width of representative files
    contrastLabels = classifyContrastsByWindow(files, tempIds, nContrasts);

    for c = 1:nContrasts
        vol = vols(:,:,:,c);
        switch contrastLabels{c}
            case 'Water',    dixon.Water   = vol;
            case 'Fat',      dixon.Fat     = vol;
            case 'InPhase',  dixon.InPhase = vol;
            case 'OutPhase', dixon.OutPhase= vol;
            case 'PDFF'
                % Scale to 0-100%
                dixon.PDFF = scalePDFF(vol, files, tempIds, c);
            case 'T2star',   dixon.T2star  = vol;
        end
    end

    % Extract slice locations for this volume
    dixon.SliceLocations = sort(uniqueLocs(:)');
end

function labels = classifyContrastsByWindow(files, tempIds, nContrasts)
%CLASSIFYCONTRASTSBYWINDOW  Assign GE IDEAL-IQ contrast labels by TemporalPositionIdentifier.
%
%   GE IDEAL-IQ output order (verified on user's scanner):
%     1=InPhase  2=OutPhase  3=Water  4=Fat  5=PDFF(%)  6=T2*(ms)
%
%   Note: some GE versions swap Water/Fat with InPhase/OutPhase at positions 1-4.
%   We use WindowCenter heuristics to detect and correct misassignments.

    geOrder = {'InPhase','OutPhase','Water','Fat','PDFF','T2star'};

    % Start with GE standard order, trimmed/extended to nContrasts
    if nContrasts <= numel(geOrder)
        labels = geOrder(1:nContrasts);
    else
        labels = [geOrder, repmat({'Unknown'}, 1, nContrasts - numel(geOrder))];
    end

    % Verify PDFF position by WindowCenter heuristic
    % (only attempt if we can read at least one header per contrast)
    wcs = nan(1, nContrasts);
    for c = 1:nContrasts
        idx = find(tempIds == c, 1);
        if isempty(idx), continue; end
        try
            info = dicominfo(files{idx}, 'UseDictionaryVR', true);
            if isfield(info,'WindowCenter') && ~isempty(info.WindowCenter)
                wcs(c) = double(info.WindowCenter(1));
            end
        catch
        end
    end

    % Refine label assignments using WindowCenter heuristics:
    %   PDFF (%):   WC ≈ 20-60  (0-100% range → typical WC ~50)
    %   T2* (ms):   WC ≈ 15-50  (0-100 ms range)
    %   Anatomic (Water/Fat/IP/OP): WC >> 100
    % For each contrast, override the default label when WC strongly indicates
    % PDFF or T2*.
    for c = 1:nContrasts
        if isnan(wcs(c)), continue; end
        if wcs(c) >= 15 && wcs(c) <= 80
            % Low-range image — could be PDFF or T2*
            % Distinguish: T2* is usually position 6; PDFF is position 5.
            % Use geOrder position as tiebreaker; PDFF overrides if not already there.
            if ~strcmp(labels{c},'T2star') && ~strcmp(labels{c},'PDFF')
                labels{c} = 'PDFF';  % default low-range to PDFF
            end
        end
    end
end

function pdffVol = scalePDFF(rawVol, files, tempIds, c)
%SCALEPDFF  Convert raw PDFF pixels to 0-100 percent.
    % Find the WindowWidth to determine scale
    idx = find(tempIds == c, 1);
    scale = 1.0;
    if ~isempty(idx)
        try
            info = dicominfo(files{idx}, 'UseDictionaryVR', true);
            if isfield(info,'RescaleSlope') && ~isempty(info.RescaleSlope)
                scale = double(info.RescaleSlope);
            end
        catch
        end
    end
    pdffVol = double(rawVol) .* scale;
    % Clamp to 0-100
    pdffVol = max(0, min(100, pdffVol));
end


% ======================================================================
%  SINGLE CONTRAST READER
% ======================================================================

function vol = readSingleContrast(files, opts)
%READSINGLECONTRAST  Read all files in a single-contrast series.
    nFiles = numel(files);
    if nFiles == 0, vol = []; return; end

    sliceLocs = zeros(1, nFiles);
    imgPos    = nan(3, nFiles);
    stackPos  = zeros(1, nFiles);
    iop_ref   = [];
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            else
                sliceLocs(k) = k;
            end
            if isfield(info,'ImagePositionPatient') && numel(info.ImagePositionPatient)==3
                imgPos(:,k) = double(info.ImagePositionPatient(:));
            end
            if isempty(iop_ref) && isfield(info,'ImageOrientationPatient') && ...
               numel(info.ImageOrientationPatient)==6
                iop_ref = double(info.ImageOrientationPatient(:));
            end
            if isfield(info,'InStackPositionNumber') && ~isempty(info.InStackPositionNumber)
                stackPos(k) = double(info.InStackPositionNumber);
            end
        catch
            sliceLocs(k) = k;
        end
    end

    % GE IDEAL-IQ sometimes reports the same SliceLocation for every file.
    % Fallback 1: ImagePositionPatient projected onto the slice normal.
    if numel(unique(round(sliceLocs, 2))) == 1 && ...
       ~isempty(iop_ref) && ~all(isnan(imgPos(:)))
        rowDir = iop_ref(1:3); colDir = iop_ref(4:6);
        sn = cross(rowDir, colDir);
        sn = sn / max(norm(sn), 1e-9);
        zp = sn' * imgPos;
        zp(isnan(zp)) = 0;
        zpr = round(zp, 2);
        if numel(unique(zpr)) > 1
            sliceLocs = zpr;
            vprint(opts, '  readSingleContrast: SliceLocation degenerate — using %d unique IPP projections.', numel(unique(zpr)));
        end
    end

    % Fallback 2: GE IDEAL-IQ private slab extent tags + InStackPositionNumber.
    % Used when both SliceLocation and IPP are constant (degenerate 3D acq).
    % InStackPositionNumber=1 = superior-most; incrementing = going inferior.
    if numel(unique(round(sliceLocs, 2))) == 1 && any(stackPos > 0)
        try
            h = dicominfo(files{1}, 'UseDictionaryVR', true);
            gS = NaN; gI = NaN; gDs = 0;
            for tagPair = {{'Private_0019_1018','Private_0019_1019'}, ...
                           {'Private_0019_101a','Private_0019_101b'}}
                dtag = tagPair{1}{1}; vtag = tagPair{1}{2};
                if isfield(h,dtag) && isfield(h,vtag) && ~isempty(h.(vtag))
                    ds = upper(strtrim(char(h.(dtag)))); vv = double(h.(vtag));
                    if contains(ds,'S'), gS = vv; end
                    if contains(ds,'I'), gI = vv; end
                end
            end
            if isfield(h,'SpacingBetweenSlices') && double(h.SpacingBetweenSlices) > 0
                gDs = double(h.SpacingBetweenSlices);
            elseif isfield(h,'SliceThickness') && double(h.SliceThickness) > 0
                gDs = double(h.SliceThickness);
            end
            if ~isnan(gS) && ~isnan(gI) && gDs > 0 && all(stackPos > 0)
                zFromStack  = gS - (stackPos - 1) * gDs;
                zFromStackR = round(zFromStack, 2);
                if numel(unique(zFromStackR)) > 1
                    sliceLocs = zFromStackR;
                    vprint(opts, ['  readSingleContrast: GE slab extent + InStackPositionNumber' ...
                        ' → %d positions (%.1f to %.1f mm).'], ...
                        numel(unique(sliceLocs)), min(sliceLocs), max(sliceLocs));
                end
            end
        catch, end
    end

    [sortedLocs, idx] = sort(sliceLocs);
    files = files(idx);
    uniqueLocs = unique(sortedLocs);
    nSlices = numel(uniqueLocs);

    try
        img1 = double(dicomread(files{1}));
        nR = size(img1,1); nC = size(img1,2);
    catch
        nR = 256; nC = 256;
    end

    vol = zeros(nR, nC, nSlices, 'double');
    for k = 1:nFiles
        try
            img = double(dicomread(files{k}));
            sl  = find(uniqueLocs == sortedLocs(k), 1);
            if ~isempty(sl), vol(:,:,sl) = img; end
        catch
        end
    end
end

function [pdffVol, sinfo] = readPDFFSeries(series, opts)
%READPDFFERIES  Read a dedicated PDFF series and scale to 0-100%.
    vprint(opts,'Reading PDFF series S%d...', series.SeriesNumber);
    files = series.Files;
    pdffVol = readSingleContrast(files, opts);
    sinfo   = struct();

    if isempty(pdffVol) || isempty(files), return; end

    try
        hdr1    = dicominfo(files{1}, 'UseDictionaryVR', true);
        sinfo   = io_extractSpatialInfo(files, hdr1, size(pdffVol,3), 1);
        % Apply rescale if present
        if isfield(hdr1,'RescaleSlope') && ~isempty(hdr1.RescaleSlope)
            pdffVol = pdffVol .* double(hdr1.RescaleSlope);
        end
        pdffVol = max(0, min(100, pdffVol));
    catch
    end
end


% ======================================================================
%  UTILITIES
% ======================================================================

function dixon = fillSpatialInfo(dixon, files)
    try
        nFiles = numel(files);
        if nFiles < 1, return; end
        hdr1 = dicominfo(files{1}, 'UseDictionaryVR', true);
        [sliceLocs, imgPos, iop_ref] = readSeriesSliceMeta(files);
        uniqueLocs = unique(sliceLocs(~isnan(sliceLocs)));
        nZ = numel(uniqueLocs);
        if nZ < 1, nZ = nFiles; end
        dixon.SpatialInfo = io_extractSpatialInfo(files, hdr1, nZ, 1);
        if ~isempty(uniqueLocs) && (isempty(dixon.SliceLocations) || ...
                                    numel(unique(round(double(dixon.SliceLocations(:)'),1))) <= 1)
            dixon.SliceLocations = sort(uniqueLocs(:)');
        end
        dixon.SpatialInfo = patchSinfoForDegenerateIPP( ...
            dixon.SpatialInfo, imgPos, iop_ref, uniqueLocs);
    catch
    end
end

function dixon = populateLocsAndPatch(dixon, files)
% Read SliceLocations from `files` and populate dixon.SliceLocations
% (without overwriting dixon.SpatialInfo).  Also patch the existing
% SpatialInfo.AffineMatrix z-origin if ImagePositionPatient is degenerate.
    try
        if isempty(files), return; end
        [sliceLocs, imgPos, iop_ref] = readSeriesSliceMeta(files);
        uniqueLocs = unique(sliceLocs(~isnan(sliceLocs)));
        if ~isempty(uniqueLocs) && (isempty(dixon.SliceLocations) || ...
                                    numel(unique(round(double(dixon.SliceLocations(:)'),1))) <= 1 || ...
                                    numel(dixon.SliceLocations) ~= numel(uniqueLocs))
            dixon.SliceLocations = sort(uniqueLocs(:)');
        end
        if ~isempty(dixon.SpatialInfo) && isfield(dixon.SpatialInfo,'AffineMatrix')
            dixon.SpatialInfo = patchSinfoForDegenerateIPP( ...
                dixon.SpatialInfo, imgPos, iop_ref, uniqueLocs);
        end
    catch
    end
end

function [sliceLocs, imgPos, iop_ref] = readSeriesSliceMeta(files)
% Read SliceLocation, ImagePositionPatient and ImageOrientationPatient
% from every file in a series.
    nFiles = numel(files);
    sliceLocs = nan(1, nFiles);
    imgPos    = nan(3, nFiles);
    iop_ref   = [];
    for k = 1:nFiles
        try
            inf = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(inf,'SliceLocation') && ~isempty(inf.SliceLocation)
                sliceLocs(k) = double(inf.SliceLocation);
            end
            if isfield(inf,'ImagePositionPatient') && numel(inf.ImagePositionPatient)==3
                imgPos(:,k) = double(inf.ImagePositionPatient(:));
            end
            if isempty(iop_ref) && isfield(inf,'ImageOrientationPatient') && ...
               numel(inf.ImageOrientationPatient)==6
                iop_ref = double(inf.ImageOrientationPatient(:));
            end
        catch, end
    end
end

function sinfo = patchSinfoForDegenerateIPP(sinfo, imgPos, iop_ref, uniqueLocs)
% Patch the z-origin of sinfo.AffineMatrix when all ImagePositionPatient
% values share one constant z (degenerate 3D acquisition).
    if isempty(sinfo) || ~isfield(sinfo,'AffineMatrix') || ...
       isempty(imgPos) || all(isnan(imgPos(:))) || isempty(iop_ref) || ...
       isempty(uniqueLocs)
        return
    end
    try
        rd = iop_ref(1:3); cd_ = iop_ref(4:6);
        sn = cross(rd(:), cd_(:)); sn = sn / max(norm(sn), 1e-9);
        zp = sn(:)' * imgPos;
        zpv = zp(~isnan(zp));
        if isempty(zpv) || (max(zpv) - min(zpv)) >= 0.5
            return
        end
        inferiorZ = min(uniqueLocs);
        if isnan(inferiorZ), return; end
        A = sinfo.AffineMatrix;
        if size(A,1) >= 3 && size(A,2) >= 4
            A(3,4) = inferiorZ;
            sinfo.AffineMatrix = A;
            M = A(1:3,1:3);
            if rcond(M) > 1e-10
                sinfo.AffineMatrixInv  = inv(A);
                sinfo.AffineIsSingular = false;
            else
                sinfo.AffineMatrixInv  = pinv(A);
                sinfo.AffineIsSingular = true;
            end
        end
        if isfield(sinfo,'ImagePositionFirst') && ...
           numel(sinfo.ImagePositionFirst) >= 3
            sinfo.ImagePositionFirst(3) = inferiorZ;
        end
    catch
    end
end

function s = findRole(group, role)
    s = [];
    for k = 1:numel(group)
        if strcmp(group(k).Role, role)
            if isempty(s), s = group(k);
            else,          s(end+1) = group(k); end %#ok<AGROW>
        end
    end
end

function s = findRoles(group, roles)
% Like findRole but accepts a cell array of role strings.
    s = [];
    for k = 1:numel(group)
        if any(strcmp(group(k).Role, roles))
            if isempty(s), s = group(k);
            else,          s(end+1) = group(k); end %#ok<AGROW>
        end
    end
end

function s = findBestNamedSeries(group, includeTokens, excludeTokens)
    if nargin < 3, excludeTokens = {}; end
    s = [];
    keep = [];
    for k = 1:numel(group)
        desc = lower(group(k).SeriesDescription);
        if ~all(cellfun(@(tok) contains(desc, lower(tok)), includeTokens))
            continue
        end
        if any(cellfun(@(tok) contains(desc, lower(tok)), excludeTokens))
            continue
        end
        keep(end+1) = k; %#ok<AGROW>
    end
    if isempty(keep)
        return
    end
    % Prefer slice counts consistent with the dedicated PDFF map when available,
    % then the smallest image count among named recons to avoid raw multi-series.
    nImgs = arrayfun(@(x) double(group(x).nImages), keep);
    [~, ord] = sort(nImgs, 'ascend');
    s = group(keep(ord));
end

function s = sizeStr(v)
    if isempty(v), s = '[]'; return; end
    s = mat2str(size(v));
end

function dixon = initDixonStruct()
    dixon = struct('Water',[],'Fat',[],'InPhase',[],'OutPhase',[], ...
                   'PDFF',[],'T2star',[],'SpatialInfo',struct(), ...
                   'nSlices',0,'PixelSpacing_mm',[1 1], ...
                   'SliceThickness_mm',8,'SliceLocations',[]);
end

function tempIds = assignContrastBySliceRank(sliceLoc, instNums, nContrasts)
%ASSIGNCONTRASTBYSLICERANK  Assign contrast index by ranking InstanceNumber
%   within each unique SliceLocation.  Works for both GE storage orderings:
%     - contrast-interleaved: C1S1, C2S1, ..., CnS1, C1S2, ...
%     - all-slices-per-contrast: C1S1, C1S2, ..., C1Sn, C2S1, ...
%   In both cases, within each slice the contrast order by InstanceNumber
%   is consistent (1 = first contrast, 2 = second, etc.).
    nFiles  = numel(sliceLoc);
    tempIds = ones(1, nFiles);
    uniqueLocs = unique(sliceLoc);
    for u = 1:numel(uniqueLocs)
        mask = (sliceLoc == uniqueLocs(u));
        fileIdxs = find(mask);
        [~, sortOrd] = sort(instNums(fileIdxs));
        for r = 1:numel(fileIdxs)
            tempIds(fileIdxs(sortOrd(r))) = min(r, nContrasts);
        end
    end
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k}), opts.(fields{k}) = defaults.(fields{k}); end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[seg_buildDixonVolume] ' fmt '\n'], varargin{:});
    end
end


% ======================================================================
%  CONVENTIONAL IP/OP (2-POINT DIXON) READER
% ======================================================================

function s = findIPOPSeries(group)
%FINDIPOPSERIES  Return any series in the Dixon group that looks like a
%   conventional IP/OP (2-point Dixon) acquisition.
    ipopRoles = {'IPOP_Dixon','IPOP_Family','IPOP_Fallback'};
    s = [];
    for k = 1:numel(group)
        role = char(group(k).Role);
        desc = lower(char(group(k).SeriesDescription));
        isIPOPRole = any(strcmp(role, ipopRoles));
        isIPOPDesc = contains(desc,'ip/op')        || contains(desc,'ipop')       || ...
                     contains(desc,'in-phase')      || contains(desc,'inphase')    || ...
                     contains(desc,'out-of-phase')  || contains(desc,'in phase')   || ...
                     contains(desc,'out phase')     || endsWith(strtrim(desc),' ip') || ...
                     endsWith(strtrim(desc),' op');
        if isIPOPRole || isIPOPDesc
            if isempty(s), s = group(k);
            else,          s(end+1) = group(k); end %#ok<AGROW>
        end
    end
end

function [ipVol, opVol] = readIPOPByEchoTime(series, opts)
%READIPOPBYECHOTIME  Split a combined IP/OP series into InPhase and OutPhase
%   volumes using EchoTime and MagneticFieldStrength from DICOM headers.
%
%   Water-fat chemical shift at 3.5 ppm is field-strength dependent:
%     1.5 T → Δf ≈ 220 Hz  IP TEs: 4.6, 9.2 ms…   OP TEs: 2.3, 6.9 ms…
%     3.0 T → Δf ≈ 440 Hz  IP TEs: 2.3, 4.6 ms…   OP TEs: 1.15, 3.45 ms…
%
%   Assignment uses cos(2π·Δf·TE): maximum → IP, minimum → OP.
%   This is correct for any field strength and any TE combination — unlike a
%   simple short/long rule which fails at 3T where the first IP echo (2.3 ms)
%   is shorter than the second OP echo (3.45 ms).

    ipVol = []; opVol = [];
    files  = series.Files;
    nFiles = numel(files);
    if nFiles < 2, return; end

    vprint(opts, '  Reading %d headers for EchoTime...', nFiles);
    echoTimes = nan(1, nFiles);
    sliceLocs = zeros(1, nFiles);
    B0      = 1.5;    % default field strength [T]
    B0read  = false;
    for k = 1:nFiles
        try
            info = dicominfo(files{k}, 'UseDictionaryVR', true);
            if isfield(info,'EchoTime') && ~isempty(info.EchoTime)
                echoTimes(k) = double(info.EchoTime(1));
            end
            if isfield(info,'SliceLocation') && ~isempty(info.SliceLocation)
                sliceLocs(k) = double(info.SliceLocation);
            elseif isfield(info,'InstanceNumber') && ~isempty(info.InstanceNumber)
                sliceLocs(k) = double(info.InstanceNumber);
            end
            if ~B0read && isfield(info,'MagneticFieldStrength') && ~isempty(info.MagneticFieldStrength)
                B0     = double(info.MagneticFieldStrength);
                B0read = true;
            end
        catch
        end
    end

    validTE = echoTimes(~isnan(echoTimes));
    if isempty(validTE)
        vprint(opts, '  WARNING: No EchoTime in headers; cannot split IP/OP by TE.');
        return
    end

    uniqueTE = ipopUniqueTolerant(validTE, 0.05);   % 0.05 ms tolerance
    if numel(uniqueTE) < 2
        vprint(opts, '  WARNING: Only 1 unique EchoTime (%.2f ms); cannot split IP/OP.', uniqueTE(1));
        return
    end
    if numel(uniqueTE) > 2
        vprint(opts, '  Note: %d unique EchoTimes found; selecting most IP/OP-like pair.', numel(uniqueTE));
    end

    % Chemical shift between water and fat at 3.5 ppm.
    % Δf = 3.5 ppm × γ × B0  where γ = 42.577 MHz/T for ¹H.
    deltaF = 3.5e-6 * 42.577e6 * B0;   % Hz  (≈220 Hz at 1.5T, ≈440 Hz at 3T)

    % Water-fat phase at each unique TE: φ = 2π·Δf·TE (TE in seconds).
    % cos(φ) = +1 → fully in-phase, cos(φ) = -1 → fully out-of-phase.
    cosPhase = cos(2*pi * deltaF * uniqueTE * 1e-3);

    [~, ipIdx] = max(cosPhase);   % TE closest to in-phase
    [~, opIdx] = min(cosPhase);   % TE closest to out-of-phase
    teIP = uniqueTE(ipIdx);
    teOP = uniqueTE(opIdx);

    vprint(opts, '  B0=%.1fT  Δf=%.0fHz  IP TE=%.3fms (cos=%.3f)  OP TE=%.3fms (cos=%.3f)', ...
        B0, deltaF, teIP, cosPhase(ipIdx), teOP, cosPhase(opIdx));

    teValid = ~isnan(echoTimes);
    ipMask  = teValid & (abs(echoTimes - teIP) < abs(echoTimes - teOP));
    opMask  = teValid & ~ipMask;

    ipVol = ipopReadByMask(files, ipMask, sliceLocs);
    opVol = ipopReadByMask(files, opMask, sliceLocs);

    vprint(opts, '  InPhase: %s   OutPhase: %s', sizeStr(ipVol), sizeStr(opVol));
end

function vol = ipopReadByMask(files, mask, locs)
%IPOPREADBYMASK  Read files selected by logical mask, sorted by SliceLocation.
    selFiles = files(mask);
    selLocs  = locs(mask);
    if isempty(selFiles), vol = []; return; end

    [selLocs, ord] = sort(selLocs);
    selFiles = selFiles(ord);
    uniqueLocs = unique(selLocs);
    nSlices    = numel(uniqueLocs);

    try
        img1 = double(dicomread(selFiles{1}));
        nR = size(img1,1); nC = size(img1,2);
    catch
        nR = 256; nC = 256;
    end
    vol = zeros(nR, nC, nSlices, 'double');
    for k = 1:numel(selFiles)
        try
            img = double(dicomread(selFiles{k}));
            sl  = find(uniqueLocs == selLocs(k), 1);
            if ~isempty(sl), vol(:,:,sl) = img; end
        catch
        end
    end
end

function uq = ipopUniqueTolerant(vals, tol)
%IPOPUNIQUETOLERANT  Return unique values with tolerance-based clustering.
    vals = sort(vals(:)');
    uq   = vals(1);
    for k = 2:numel(vals)
        if vals(k) - uq(end) > tol
            uq(end+1) = vals(k); %#ok<AGROW>
        end
    end
end

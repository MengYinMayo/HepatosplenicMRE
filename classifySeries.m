function label = classifySeries(hdr)
% Classify a series into one of:
%   'scout_localizer'
%   'dixon_inPhase' | 'dixon_outPhase' | 'dixon_fat' | 'dixon_water'
%   'dixon_pdff'
%   'mre_magnitude' | 'mre_stiffness' | 'mre_wave'
%   'unknown'
%
% Uses DICOM tag priority: ImageType > SequenceName > SeriesDescription

    label = 'unknown';

    imageType   = getHeaderField(hdr, 'ImageType', '');
    seqName     = lower(getHeaderField(hdr, 'SequenceName', ''));
    seriesDesc  = lower(getHeaderField(hdr, 'SeriesDescription', ''));
    nSlices     = getHeaderField(hdr, 'ImagesInAcquisition', NaN);
    rows        = getHeaderField(hdr, 'Rows', NaN);
    cols        = getHeaderField(hdr, 'Columns', NaN);

    % --- 1. Scout/localizer (most reliable: ImageType contains LOCALIZER) ---
    if containsAny(imageType, {'LOCALIZER','LOCAL'})
        label = 'scout_localizer';
        return
    end

    % --- 2. MRE stiffness map (parametric map, tagged in ImageType or Units) ---
    units = lower(getHeaderField(hdr, 'RealWorldValueMappingSequence', ''));
    if containsAny(seriesDesc, {'stiffness','kpa','elastogram'}) || ...
       containsAny(units, {'kpa','pascal'})
        label = 'mre_stiffness';
        return
    end

    % --- 3. MRE wave image ---
    if containsAny(seriesDesc, {'wave image','wave_image','phase mre','mre wave'})
        label = 'mre_wave';
        return
    end

    % --- 4. MRE magnitude ---
    if containsAny(seriesDesc, {'mre mag','mre magnitude','mre_mag'}) || ...
       (containsAny(seriesDesc, {'mre'}) && containsAny(imageType, {'MAGNITUDE'}))
        label = 'mre_magnitude';
        return
    end

    % --- 5. PDFF map (Dixon-derived quantitative fat fraction) ---
    if containsAny(seriesDesc, {'pdff','fat fraction','fat_fraction','proton density fat'})
        label = 'dixon_pdff';
        return
    end

    % --- 6. Dixon channels — ImageType encoding (most reliable) ---
    if containsAny(imageType, {'IN_PHASE','INPHASE','IN PHASE'})
        label = 'dixon_inPhase'; return
    end
    if containsAny(imageType, {'OUT_PHASE','OUTPHASE','OUT_OF_PHASE','OPPOSED_PHASE'})
        label = 'dixon_outPhase'; return
    end
    if containsAny(imageType, {'FAT_ONLY','FATONLY','FAT ONLY','FAT'}) && ...
       ~containsAny(imageType, {'WATER'})
        label = 'dixon_fat'; return
    end
    if containsAny(imageType, {'WATER_ONLY','WATERONLY','WATER ONLY','WATER'}) && ...
       ~containsAny(imageType, {'FAT'})
        label = 'dixon_water'; return
    end

    % --- 7. Dixon channels — SeriesDescription fallback ---
    dixonKeywords = {
        {'in.phase','in_phase','inphase'},     'dixon_inPhase';
        {'out.phase','out_phase','outphase','opposed'}, 'dixon_outPhase';
        {'fat only','fat_only','\bfat\b'},    'dixon_fat';
        {'water only','water_only','\bwater\b'}, 'dixon_water';
    };
    for k = 1:size(dixonKeywords,1)
        if containsAny(seriesDesc, dixonKeywords{k,1})
            label = dixonKeywords{k,2};
            return
        end
    end

    % --- 8. Generic Dixon container (multi-echo gradient echo, 4-ch) ---
    if containsAny(seqName, {'dixon','lava','vibe','mDIXON','ideal'})
        label = 'dixon_container';   % needs sub-classification by echo/phase
        return
    end

    % label remains 'unknown'
end
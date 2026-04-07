function seriesList = io_recognizeSequences(seriesList, opts)
% IO_RECOGNIZESEQUENCES  Classify DICOM series as Scout, Dixon, or MRE.
%
%   SERIESLIST = IO_RECOGNIZESEQUENCES(SERIESLIST) takes the raw series
%   struct array produced by io_loadDICOMStudy and populates the .Class
%   and .SubClass fields of each entry:
%
%     Class      SubClass          Description
%     ─────────  ────────────────  ──────────────────────────────────────
%     'Scout'    ''                3-plane localizer / survey
%     'Dixon'    'Water'           Dixon water-only image
%     'Dixon'    'Fat'             Dixon fat-only image
%     'Dixon'    'FF'              Pre-computed fat-fraction map (0-100%)
%     'Dixon'    'InPhase'         In-phase (W+F) image
%     'Dixon'    'OutPhase'        Out-of-phase (W-F) image
%     'MRE'      'Magnitude'       MRE magnitude (anatomic) image
%     'MRE'      'Wave'            MRE wave/phase image at one time offset
%     'MRE'      'Stiffness'       Pre-computed stiffness map (kPa)
%     'unknown'  ''                Not recognized
%
%   Recognition uses a multi-pass strategy:
%     Pass 1  SeriesDescription keyword matching (highest specificity)
%     Pass 2  ImageType field analysis
%     Pass 3  Echo time / sequence heuristics (vendor-specific)
%     Pass 4  Manual fallback prompting (for GUI use — currently no-op stub)
%
%   VENDOR SUPPORT   Siemens (mDixon, VIBE Dixon, MRE), GE (IDEAL, BRAVO),
%                    Philips (mDixon, MultiVane MRE).
%
%   SEE ALSO  io_loadDICOMStudy, io_readDICOMSeries
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 2
%   DATE    2026-04

    if nargin < 2, opts = struct('verbose', true); end

    for k = 1:numel(seriesList)
        s = seriesList(k);
        desc  = lower(s.SeriesDescription);
        itype = lower(s.ImageType);

        % ── Pass 1: SeriesDescription keywords ───────────────────────
        [cls, sub] = classifyByDescription(desc);

        % ── Pass 2: ImageType refinement ─────────────────────────────
        if strcmp(cls, 'unknown') || strcmp(cls, 'MRE')
            [cls2, sub2] = classifyByImageType(itype, cls, sub);
            if ~strcmp(cls2, 'unknown')
                cls = cls2; sub = sub2;
            end
        end

        % ── Pass 3: Heuristic (TE, sequence name, nFiles) ────────────
        if strcmp(cls, 'unknown')
            [cls, sub] = classifyByHeuristic(s);
        end

        % ── Pass 4: Dixon sub-class disambiguation (Water vs Fat) ─────
        if strcmp(cls, 'Dixon') && isempty(sub)
            sub = disambiguateDixon(s);
        end

        seriesList(k).Class    = cls;
        seriesList(k).SubClass = sub;

        if isfield(opts,'verbose') && opts.verbose
            fprintf('[io_recognizeSequences] S%02d  %-40s → %s/%s\n', ...
                k, s.SeriesDescription, cls, sub);
        end
    end
end


% ======================================================================
%  PASS 1 — SeriesDescription keyword matching
% ======================================================================
function [cls, sub] = classifyByDescription(desc)
    cls = 'unknown'; sub = '';

    % ── Scout / Localizer ─────────────────────────────────────────────
    scoutKW = {'localizer','localiser','scout','survey','loc_','3-plane', ...
               'survey_ax','surv','aahscout','3plane','plane loc', ...
               'multiplane','multi-plane'};
    if anyContains(desc, scoutKW)
        cls = 'Scout'; return
    end

    % ── MRE — stiffness ──────────────────────────────────────────────
    stiffKW = {'stiffness','mre_stiff','mre stiff','elastogram','elasto'};
    if anyContains(desc, stiffKW)
        cls = 'MRE'; sub = 'Stiffness'; return
    end

    % ── MRE — wave images ─────────────────────────────────────────────
    waveKW = {'mre_wave','mre wave','phase_mre','phasemre','mre_ph', ...
              'mre phase','wave_mre','wave mre'};
    if anyContains(desc, waveKW)
        cls = 'MRE'; sub = 'Wave'; return
    end

    % ── MRE — magnitude ───────────────────────────────────────────────
    mreMagKW = {'mre_mag','mre mag','mre magnitude','magnitude_mre', ...
                'mre_m_','mre m '};
    if anyContains(desc, mreMagKW) || ...
       (contains(desc,'mre') && contains(desc,'mag'))
        cls = 'MRE'; sub = 'Magnitude'; return
    end

    % ── MRE — generic (unsubclassed) ─────────────────────────────────
    mreGenKW = {' mre','mre ','_mre','mre_','liver mre','spleen mre', ...
                'hepatic mre','abdom mre','abdominal mre','mrelas'};
    if anyContains(desc, mreGenKW)
        cls = 'MRE'; return
    end

    % ── Dixon — fat fraction ──────────────────────────────────────────
    ffKW = {'fat_fraction','fat fraction','fatfraction','ff_map','ff map', ...
            'pdff','proton density fat','fat%','fat pct'};
    if anyContains(desc, ffKW)
        cls = 'Dixon'; sub = 'FF'; return
    end

    % ── Dixon — water ─────────────────────────────────────────────────
    waterKW = {'_w ','_w_','water','h2o',' w ',' w_','dixon_w','dixon w', ...
               'lava_w','ideal_w','vibe_w','mdixon_w','dixon-w'};
    if anyContains(desc, waterKW)
        cls = 'Dixon'; sub = 'Water'; return
    end

    % ── Dixon — fat ───────────────────────────────────────────────────
    fatKW = {'_f ','_f_',' fat','dixon_f','lava_f','ideal_f','vibe_f', ...
             'mdixon_f','dixon-f','dixon_fat','dixon fat'};
    if anyContains(desc, fatKW)
        cls = 'Dixon'; sub = 'Fat'; return
    end

    % ── Dixon — in-phase ──────────────────────────────────────────────
    ipKW = {'in_phase','in-phase','inphase','_ip','ip_','in phase', ...
            'dixon_ip','lava_ip','ideal_ip','vibe_ip'};
    if anyContains(desc, ipKW)
        cls = 'Dixon'; sub = 'InPhase'; return
    end

    % ── Dixon — out-of-phase ──────────────────────────────────────────
    opKW = {'out_phase','out-phase','outphase','_op','op_','out phase', ...
            'opp_phase','opposed','opp phase'};
    if anyContains(desc, opKW)
        cls = 'Dixon'; sub = 'OutPhase'; return
    end

    % ── Dixon — generic ───────────────────────────────────────────────
    dixonKW = {'dixon','mdixon','m-dixon','ideal','lava flex','lavaflex', ...
               'vibe dixon','dixon vibe','3pt dixon','2pt dixon', ...
               'flex_','t1_flex','t1flex','mrac'};
    if anyContains(desc, dixonKW)
        cls = 'Dixon'; return
    end
end


% ======================================================================
%  PASS 2 — ImageType field analysis
% ======================================================================
function [cls, sub] = classifyByImageType(itype, cls, sub)
    % ImageType is a backslash-delimited string, e.g.
    % "ORIGINAL\PRIMARY\M_FFE\M\FFE" or "DERIVED\PRIMARY\MRSCP\NONE"

    parts = strsplit(itype, '\');
    parts = strtrim(parts);

    % Scout
    if anyContains(itype, {'localizer','survey','scout'})
        cls = 'Scout'; sub = ''; return
    end

    % MRE wave (phase image)
    if anyContains(itype, {'phase','p_mre','mre_p'}) && ...
       anyContains(itype, {'mre','elast'})
        cls = 'MRE'; sub = 'Wave'; return
    end

    % MRE magnitude
    if anyContains(itype, {'magnitude','m_mre','mre_m'}) && ...
       anyContains(itype, {'mre','elast'})
        cls = 'MRE'; sub = 'Magnitude'; return
    end

    % Dixon sub-class from ImageType (GE IDEAL / Philips mDixon convention)
    %  Common patterns: W, F, IP, OP, WF, IN, OPP
    for p = parts
        switch upper(strtrim(p{1}))
            case {'W','WATER','WATER_ONLY','H2O'}
                cls = 'Dixon'; sub = 'Water'; return
            case {'F','FAT','FAT_ONLY'}
                cls = 'Dixon'; sub = 'Fat'; return
            case {'IP','IN','INPHASE','IN_PHASE','IN-PHASE','WF','SUM'}
                cls = 'Dixon'; sub = 'InPhase'; return
            case {'OP','OPP','OUTPHASE','OUT_PHASE','OPPOSED','OPP_PHASE','DIFF'}
                cls = 'Dixon'; sub = 'OutPhase'; return
            case {'FF','FAT_FRACTION','PDFF'}
                cls = 'Dixon'; sub = 'FF'; return
        end
    end
end


% ======================================================================
%  PASS 3 — Heuristic classification
% ======================================================================
function [cls, sub] = classifyByHeuristic(s)
    cls = 'unknown'; sub = '';
    desc = lower(s.SeriesDescription);

    % Very few files, orthogonal planes → likely scout
    nFiles = numel(s.Files);
    if nFiles <= 30 && (s.Rows <= 256 || s.Columns <= 256)
        if contains(desc,'ax') || contains(desc,'cor') || contains(desc,'sag')
            cls = 'Scout'; return
        end
    end

    % Multi-echo or dual-echo → likely Dixon
    if ~isnan(s.EchoTime)
        if s.EchoTime < 3.0  % very short TE typical of dual-echo Dixon
            cls = 'Dixon'; return
        end
    end

    % Large number of files + no other match → might be MRE wave images
    if nFiles >= 40 && contains(desc, 'mre')
        cls = 'MRE'; sub = 'Wave'; return
    end
end


% ======================================================================
%  Dixon sub-class disambiguation
% ======================================================================
function sub = disambiguateDixon(s)
%DISAMBIGUATEDIXON  Attempt to determine Water/Fat/IP/OP from pixel stats.
%   Reads one representative DICOM slice and uses intensity statistics.
    sub = '';
    if isempty(s.Files), return; end
    try
        img = double(dicomread(s.Files{round(end/2)}));
        mn  = mean(img(:));
        % Water images tend to be brighter (higher mean) than fat images
        % at typical abdominal acquisition parameters — very rough heuristic
        if mn > 200
            sub = 'Water';
        else
            sub = 'Fat';
        end
    catch
        sub = '';
    end
end


% ======================================================================
%  Utility
% ======================================================================
function tf = anyContains(str, kwList)
    tf = false;
    for k = 1:numel(kwList)
        if contains(str, kwList{k})
            tf = true; return
        end
    end
end

function selection = mre_selectSeriesGUI(exam)
% MRE_SELECTSERIESGUI  Interactive panel for selecting Localizer, Dixon, and MRE series.
%
%   SELECTION = MRE_SELECTSERIESGUI(EXAM) opens a modal uifigure showing all
%   detected series grouped by category. The user selects one entry per group
%   and clicks Confirm. Related series (same drive frequency / same base series
%   number) are auto-included when any one series in the group is chosen.
%
%   RETURNS selection struct:
%     .Localizer      struct  — selected localizer series entry (or [])
%     .Dixon          struct  — selected Dixon/IDEALIQ/IPOP series entry (or [])
%     .DixonGroup     struct array — all related Dixon series auto-included
%     .MRE            struct  — selected MRE anchor series entry (or [])
%     .MREGroup       struct array — all related MRE series auto-included
%     .Confirmed      logical — false if user cancelled
%
%   AUTO-GROUPING
%     MRE:   series with the same drive frequency (e.g. "30Hz", "60Hz") and
%            same base reconstruction set (e.g. S000700–S000717) are grouped.
%     IDEAL-IQ: series with the same SeriesDescription prefix and consecutive
%            numbers (e.g. S000599, S015992, S015993, S015997, S015998) are grouped.
%
%   FALLBACK DIXON
%     If no IDEAL-IQ series exists, IP/OP images (role='Unknown' but description
%     contains 'ip','op','in-phase','out') are shown in the Dixon section so
%     the user can select them for PDFF estimation.
%
%   AUTHOR  Meng Yin, PhD
%           Department of Radiology, Mayo Clinic
%           Email: Yin.Meng@mayo.edu
%   DATE    April 17, 2026

    % Default return on cancel
    selection = struct('Localizer',[],'Dixon',[],'DixonGroup',[], ...
                       'MRE',[],'MREGroup',[],'Confirmed',false);

    if isempty(exam) || isempty(exam.Series)
        uialert(gcf,'No series found in exam.','Empty Exam','Icon','warning');
        return
    end

    % ------------------------------------------------------------------
    % 1.  Organise series into display groups
    % ------------------------------------------------------------------
    groups = buildGroups(exam.Series);

    % ------------------------------------------------------------------
    % 2.  Build the UI
    % ------------------------------------------------------------------
    fig = uifigure('Name','Series Selection','NumberTitle','off', ...
                   'Position',[80 80 1060 680], ...
                   'Resize','on','WindowStyle','modal');

    % Title bar
    titleLbl = uilabel(fig,'Text', ...
        sprintf('Study: %s   |   Date: %s   |   Scanner: %s   |   MRE type: %s', ...
            exam.PatientID, exam.StudyDate, exam.ScannerModel, exam.MREType), ...
        'Position',[10 648 1040 24], ...
        'FontSize',12,'FontWeight','bold', ...
        'HorizontalAlignment','left');  %#ok<NASGU>

    % Three column panels
    panelW = 320; panelH = 560; panelTop = 78;
    colX = [10, 340, 670];
    colTitles = {'Localizer','Dixon / IDEAL-IQ','MRE Series'};
    colFields = {'localizer','dixon','mre'};

    panels = gobjects(1,3);
    trees  = cell(1,3);
    for c = 1:3
        panels(c) = uipanel(fig,'Title',colTitles{c}, ...
            'Position',[colX(c) panelTop panelW panelH], ...
            'FontSize',13,'FontWeight','bold');
        trees{c} = uitree(panels(c),'Position',[6 6 panelW-16 panelH-36]);
        trees{c}.SelectionChangedFcn = @(src,e) onSelect(src,e,c);
    end

    % Detail panel (bottom)
    detailPanel = uipanel(fig,'Title','Series detail', ...
        'Position',[10 8 1040 62],'FontSize',11);
    detailLbl = uilabel(detailPanel,'Text','Select a series to see details.', ...
        'Position',[6 4 1028 44],'WordWrap','on','FontSize',11);

    % Buttons
    btnConfirm = uibutton(fig,'push','Text','Confirm Selection', ...
        'Position',[790 650 180 28],'FontSize',12,'FontWeight','bold', ...
        'BackgroundColor',[0.18 0.60 0.34],'FontColor',[1 1 1], ...
        'ButtonPushedFcn',@(~,~) onConfirm());
    btnCancel = uibutton(fig,'push','Text','Cancel', ...
        'Position',[980 650 72 28],'FontSize',12, ...
        'ButtonPushedFcn',@(~,~) onCancel());

    % Selection state
    selectedNode = cell(1,3);   % stores selected node in each column
    confirmed    = false;

    % ------------------------------------------------------------------
    % 3.  Populate trees
    % ------------------------------------------------------------------
    populateTree(trees{1}, groups.localizer, 'localizer');
    populateTree(trees{2}, groups.dixon,     'dixon');
    populateTree(trees{3}, groups.mre,       'mre');

    % ------------------------------------------------------------------
    % 4.  Wait for user
    % ------------------------------------------------------------------
    uiwait(fig);

    % ------------------------------------------------------------------
    % 5.  Build output
    % ------------------------------------------------------------------
    if ~confirmed || ~isvalid(fig)
        if isvalid(fig), close(fig); end
        return
    end

    selection.Confirmed = true;

    % Localizer
    if ~isempty(selectedNode{1}) && isvalid(selectedNode{1})
        selection.Localizer = selectedNode{1}.NodeData;
    end

    % Dixon + auto-group
    if ~isempty(selectedNode{2}) && isvalid(selectedNode{2})
        anchor = selectedNode{2}.NodeData;
        selection.Dixon = anchor;
        selection.DixonGroup = findRelatedDixon(exam.Series, anchor);
    end

    % MRE + auto-group
    if ~isempty(selectedNode{3}) && isvalid(selectedNode{3})
        anchor = selectedNode{3}.NodeData;
        selection.MRE = anchor;
        selection.MREGroup = findRelatedMRE(exam.Series, anchor);
    end

    if isvalid(fig), close(fig); end

    % ==================================================================
    %  NESTED CALLBACKS
    % ==================================================================

    function onSelect(src, event, col)
        node = event.SelectedNodes;
        if isempty(node) || isempty(node.NodeData), return; end
        selectedNode{col} = node;
        % Update detail label
        s = node.NodeData;
        detailLbl.Text = buildDetailText(s);
        % Highlight selected node in its column
        for other = setdiff(1:3, col)
            % No cross-column interference needed
        end
    end

    function onConfirm()
        % Validate at least MRE selected
        if isempty(selectedNode{3}) || ...
           (isvalid(selectedNode{3}) && isempty(selectedNode{3}.NodeData))
            uialert(fig,'Please select an MRE series.','Selection Required','Icon','warning');
            return
        end
        confirmed = true;
        uiresume(fig);
    end

    function onCancel()
        confirmed = false;
        uiresume(fig);
    end

end  % main function


% ======================================================================
%  GROUP BUILDER
% ======================================================================

function groups = buildGroups(seriesList)
%BUILDGROUPS  Sort series list into localizer / dixon / mre display groups.

    % Use cell arrays for accumulation, convert to struct arrays at end
    locCell  = {};
    dixCell  = {};
    mreCell  = {};

    % ── Localizer ─────────────────────────────────────────────────────
    for k = 1:numel(seriesList)
        if strcmp(seriesList(k).Role,'Localizer')
            locCell{end+1} = seriesList(k); %#ok<AGROW>
        end
    end

    % ── Dixon: resolve acquisition families independently from MRE ────
    try
        dixonExam = dixon_parseDICOMExam(struct('Series', seriesList));
    catch
        dixonExam = struct('Families', struct([]));
    end
    if isfield(dixonExam,'Families') && ~isempty(dixonExam.Families)
        % Separate IDEALIQ and IPOP families.
        idealFamList = {};
        ipopFamList  = {};
        for k = 1:numel(dixonExam.Families)
            if strcmpi(dixonExam.Families(k).Type,'IPOP')
                ipopFamList{end+1} = dixonExam.Families(k); %#ok<AGROW>
            else
                idealFamList{end+1} = dixonExam.Families(k); %#ok<AGROW>
            end
        end

        % Classify IDEALIQ families as "processed" (has PDFF or T2s member)
        % or "raw-only" (only raw/multi acquisition images).  Old GE exams
        % produce a separate raw family (e.g. S5 "WATER:1.5T IDEAL-IQ
        % Abdomen") whose processed recons land in a different family (e.g.
        % S15992-S15998).  Merge raw-only members into all processed families
        % so any family member the user selects loads the complete set.
        procFams    = {};
        rawOnlyFams = {};
        for k = 1:numel(idealFamList)
            if idealFamilyHasProcessed(idealFamList{k})
                procFams{end+1} = idealFamList{k}; %#ok<AGROW>
            else
                rawOnlyFams{end+1} = idealFamList{k}; %#ok<AGROW>
            end
        end

        % Collect all series numbers from raw-only families.
        rawOnlyNums = [];
        for k = 1:numel(rawOnlyFams)
            rawOnlyNums = [rawOnlyNums, double([rawOnlyFams{k}.Members.SeriesNumber])]; %#ok<AGROW>
        end

        % Build dixCell entries for processed IDEALIQ families (all members).
        for k = 1:numel(procFams)
            fam     = procFams{k};
            famNums = unique([double([fam.Members.SeriesNumber]), rawOnlyNums]);
            for m = 1:numel(fam.Members)
                entry = fam.Members(m);
                entry.Role = 'IDEALIQ_Family';
                entry.FamilySeriesNums = famNums;
                dixCell{end+1} = entry; %#ok<AGROW>
            end
        end

        % If no processed families exist, fall back to showing raw families.
        if isempty(procFams)
            for k = 1:numel(idealFamList)
                fam     = idealFamList{k};
                famNums = double([fam.Members.SeriesNumber]);
                for m = 1:numel(fam.Members)
                    entry = fam.Members(m);
                    entry.Role = 'IDEALIQ_Family';
                    entry.FamilySeriesNums = famNums;
                    dixCell{end+1} = entry; %#ok<AGROW>
                end
            end
        end

        % IPOP families: one anchor entry per family.
        for k = 1:numel(ipopFamList)
            fam    = ipopFamList{k};
            anchor = fam.Anchor;
            anchor.Role = 'IPOP_Family';
            anchor.FamilySeriesNums = double([fam.Members.SeriesNumber]);
            dixCell{end+1} = anchor; %#ok<AGROW>
        end
    else
        % Last resort: preserve historical behavior if family resolver fails.
        idealRoles = {'IDEALIQ_PDFF','IDEALIQ_Multi','IDEALIQ_T2s','IDEALIQ_Raw'};
        for k = 1:numel(seriesList)
            if any(strcmp(seriesList(k).Role, idealRoles))
                dixCell{end+1} = seriesList(k); %#ok<AGROW>
            end
        end
        for k = 1:numel(seriesList)
            s = seriesList(k);
            if isIPOP(s)
                entry      = s;
                entry.Role = 'IPOP_Fallback';
                dixCell{end+1} = entry; %#ok<AGROW>
            end
        end
    end

    % ── MRE: one anchor per inferred raw-series family ───────────────
    mreRoles = {'EPI_WaveMag_Raw','EPI_WaveMag_Proc','EPI_WaveMag','EPI_Stiffness','EPI_ConfMap','EPI_ProcWave','EPI_RawIQ', ...
                'GRE_WaveMag_Raw','GRE_WaveMag_Proc','GRE_WaveMag','GRE_Stiffness','GRE_ConfMap','GRE_ProcWave'};
    seen = containers.Map();
    for k = 1:numel(seriesList)
        s = seriesList(k);
        if ~any(strcmp(s.Role, mreRoles)), continue; end
        famAnchor = inferMREFamilyAnchor(seriesList, s);
        key = sprintf('%s|%d', s.Role(1:3), famAnchor);
        if ~isKey(seen, key)
            seen(key) = true;
            anchorSeries = findSeriesByNumber(seriesList, famAnchor, s.Role(1:3));
            if isempty(anchorSeries)
                mreCell{end+1} = s; %#ok<AGROW>
            else
                mreCell{end+1} = anchorSeries; %#ok<AGROW>
            end
        end
    end
    
    % ── Convert cells → struct arrays, sorted by SeriesNumber ─────────
    groups.localizer = cellToSortedStructArray(locCell);
    groups.dixon     = cellToSortedStructArray(dixCell);
    groups.mre       = cellToSortedStructArray(mreCell);
end

function arr = cellToSortedStructArray(c)
    if isempty(c)
        arr = struct([]);
        return
    end
    arr = c{1};
    for k = 2:numel(c)
        arr(end+1) = c{k}; %#ok<AGROW>
    end
    [~,i] = sort([arr.SeriesNumber]);
    arr   = arr(i);
end


% ======================================================================
%  TREE POPULATION
% ======================================================================

function populateTree(tree, seriesList, colType)
%POPULATETREE  Fill a uitree with series entries, grouped by sub-category.

    delete(tree.Children);
    if isempty(seriesList), return; end

    % Sub-category labels and ordering
    switch colType
        case 'localizer'
            cats = {'Localizer'};
            labels = {'3-Plane Localizer'};
        case 'dixon'
            cats   = {'IDEALIQ_Family','IPOP_Family','IPOP_Dixon', ...
                      'IDEALIQ_PDFF','IDEALIQ_Multi','IDEALIQ_T2s','IDEALIQ_Raw', ...
                      'IPOP_Fallback','Unknown'};
            labels = {'IDEAL-IQ / mDixon family','Conventional IP/OP family','IP/OP Dixon (2-point)', ...
                      'PDFF Map','Multi-contrast stack','R2*/T2* Map','Single-contrast recon', ...
                      'IP/OP (PDFF fallback)','Other (manual)'};
        case 'mre'
            cats   = {'EPI_WaveMag_Raw','GRE_WaveMag_Raw', ...
                      'EPI_WaveMag_Proc','GRE_WaveMag_Proc', ...
                      'EPI_WaveMag','GRE_WaveMag', ...        % legacy
                      'EPI_Stiffness','GRE_Stiffness', ...
                      'EPI_ConfMap','GRE_ConfMap', ...
                      'EPI_ProcWave','GRE_ProcWave','EPI_RawIQ'};
            labels = {'EPI Wave+Mag (raw 4-phase)', ...
                      'GRE Wave+Mag (raw 4-phase)', ...
                      'EPI Wave processed (8-phase)', ...
                      'GRE Wave processed (8-phase)', ...
                      'EPI Wave+Mag','GRE Wave+Mag', ...
                      'EPI Stiffness (Pa)','GRE Stiffness (Pa)', ...
                      'EPI Confidence','GRE Confidence', ...
                      'EPI Processed','GRE Processed','EPI Raw I/Q'};
    end

    % Insert uncategorised entries under 'Other'
    usedIdx = false(1, numel(seriesList));

    for g = 1:numel(cats)
        % Find matching series
        matchIdx = [];
        for k = 1:numel(seriesList)
            if strcmp(seriesList(k).Role, cats{g})
                matchIdx(end+1) = k; %#ok<AGROW>
                usedIdx(k) = true;
            end
        end
        if isempty(matchIdx), continue; end

        % Create group node
        groupNode = uitreenode(tree, 'Text', ...
            sprintf('%s  (%d)', labels{g}, numel(matchIdx)));
        groupNode.NodeData = [];   % group nodes carry no data

        for k = matchIdx
            s = seriesList(k);
            nodeText = buildNodeText(s);
            leaf = uitreenode(groupNode, 'Text', nodeText);
            leaf.NodeData = s;
        end
        expand(groupNode, 'all');
    end

    % Any remaining
    remaining = find(~usedIdx);
    if ~isempty(remaining)
        groupNode = uitreenode(tree, 'Text', sprintf('Other  (%d)', numel(remaining)));
        groupNode.NodeData = [];
        for k = remaining
            s = seriesList(k);
            leaf = uitreenode(groupNode, 'Text', buildNodeText(s));
            leaf.NodeData = s;
        end
        expand(groupNode, 'all');
    end
end

function txt = buildNodeText(s)
    freq = extractFreq(s.SeriesDescription);
    if freq > 0
        freqStr = sprintf('[%dHz] ', round(freq));
    else
        freqStr = '';
    end
    txt = sprintf('S%06d  %s%s  (%d img)', ...
        s.SeriesNumber, freqStr, truncate(s.SeriesDescription, 45), s.nImages);
end

function txt = buildDetailText(s)
    freq = extractFreq(s.SeriesDescription);
    freqStr = '';
    if freq > 0, freqStr = sprintf('%d Hz  |  ', round(freq)); end
    txt = sprintf('S%06d  |  %s  |  Role: %s  |  %sBits: %d  |  Phases: %d  |  nImages: %d  |  SeqTag: %s  |  Folder: %s', ...
        s.SeriesNumber, s.SeriesDescription, s.Role, freqStr, ...
        s.BitDepth, s.nPhases, s.nImages, s.SeqName, s.Folder);
end


% ======================================================================
%  AUTO-GROUPING
% ======================================================================

function group = findRelatedMRE(seriesList, anchor)
%FINDRELATEDMRE  Return all series belonging to the same MRE family.
%   Uses prefix-based series-number derivation with 2-digit steps so it
%   safely handles S7->S700-S707, S30->S3001->S300101-S300107, and
%   S401->S40100-S40107 without mixing in sibling families.

    group = struct([]);
    if isempty(anchor)
        return
    end

    anchorNum  = inferMREFamilyAnchor(seriesList, anchor);
    anchorType = anchor.Role(1:3);
    anchorFreq = extractFreq(anchor.SeriesDescription);

    for k = 1:numel(seriesList)
        s = seriesList(k);
        if numel(s.Role) < 3 || ~strcmp(s.Role(1:3), anchorType)
            continue
        end
        if inferMREFamilyAnchor(seriesList, s) ~= anchorNum
            continue
        end
        sFreq = extractFreq(s.SeriesDescription);
        if anchorFreq > 0 && sFreq > 0 && abs(anchorFreq - sFreq) >= 1
            continue
        end
        if isempty(group)
            group = s;
        else
            group(end+1) = s; %#ok<AGROW>
        end
    end

    if isempty(group)
        group = anchor;
    else
        [~, ord] = sort([group.SeriesNumber]);
        group = group(ord);
    end
end

function anchorNum = inferMREFamilyAnchor(seriesList, s)
%INFERMREFAMILYANCHOR  Assign an MRE series to the correct family anchor.
%
% EPI:
%   Use the raw IQ parent as the true family root.
%   Examples:
%     S4 (2D) -> root 4
%     S401    -> root 4
%     S40100  -> root 4
%     S40105  -> root 4
%     S40107  -> root 4
%
%     S5 (3D) -> root 5
%     S501    -> root 5
%     S502    -> root 5
%     S503    -> root 5
%     S504    -> root 5
%     S505    -> root 5
%     S506    -> root 5
%     S508    -> root 5
%     S515    -> root 5
%
% GRE:
%   Keep existing raw-anchor behavior unchanged.

    anchorNum = s.SeriesNumber;
    if isempty(seriesList) || isempty(s) || ~isfield(s,'Role') || numel(s.Role) < 3
        return
    end

    typePrefix = s.Role(1:3);
    freq       = extractFreq(s.SeriesDescription);
    sNumStr    = sprintf('%d', s.SeriesNumber);

    % -------- EPI: anchor to raw IQ root only --------
    if strcmp(typePrefix, 'EPI')
        rawIQNums = [];
        for ii = 1:numel(seriesList)
            g = seriesList(ii);
            if ~strcmp(g.Role, 'EPI_RawIQ')
                continue
            end
            gFreq = extractFreq(g.SeriesDescription);
            if freq > 0 && gFreq > 0 && abs(freq - gFreq) >= 1
                continue
            end
            rawIQNums(end+1) = g.SeriesNumber; %#ok<AGROW>
        end

        if ~isempty(rawIQNums)
            bestLen = -inf;
            bestNum = anchorNum;
            for ii = 1:numel(rawIQNums)
                cand = rawIQNums(ii);
                cStr = sprintf('%d', cand);
                if isSeriesNumberDescendant(cStr, sNumStr)
                    if numel(cStr) > bestLen
                        bestLen = numel(cStr);
                        bestNum = cand;
                    end
                end
            end
            anchorNum = bestNum;
            return
        end
    end

    % -------- GRE (unchanged) --------
    rawNums = [];
    for ii = 1:numel(seriesList)
        g = seriesList(ii);
        if numel(g.Role) < 3 || ~strcmp(g.Role(1:3), typePrefix)
            continue
        end
        gFreq = extractFreq(g.SeriesDescription);
        if freq > 0 && gFreq > 0 && abs(freq - gFreq) >= 1
            continue
        end
        if isRawMREAnchorRole(g.Role)
            rawNums(end+1) = g.SeriesNumber; %#ok<AGROW>
        end
    end
    if isempty(rawNums)
        return
    end

    bestLen = -inf;
    bestNum = anchorNum;
    for ii = 1:numel(rawNums)
        cand = rawNums(ii);
        cStr = sprintf('%d', cand);
        if isSeriesNumberDescendant(cStr, sNumStr)
            if numel(cStr) > bestLen
                bestLen = numel(cStr);
                bestNum = cand;
            end
        end
    end
    anchorNum = bestNum;
end

function tf = isSeriesNumberDescendant(parentStr, childStr)
    parentStr = regexprep(char(parentStr), '^0+', '');
    childStr  = regexprep(char(childStr),  '^0+', '');
    if isempty(parentStr), parentStr = '0'; end
    if isempty(childStr),  childStr  = '0'; end
    if length(parentStr) > length(childStr)
        tf = false;
        return
    end
    if ~strncmp(childStr, parentStr, length(parentStr))
        tf = false;
        return
    end
    remLen = length(childStr) - length(parentStr);
    tf = ismember(remLen, [0 2 4]);
end

function tf = isRawMREAnchorRole(role)
    tf = any(strcmp(role, {'EPI_WaveMag_Raw','GRE_WaveMag_Raw','EPI_WaveMag','GRE_WaveMag'}));
end

function s = findSeriesByNumber(seriesList, seriesNumber, typePrefix)
    s = [];
    for ii = 1:numel(seriesList)
        g = seriesList(ii);
        if g.SeriesNumber == seriesNumber && numel(g.Role) >= 3 && strcmp(g.Role(1:3), typePrefix)
            s = g;
            return
        end
    end
end

function group = findRelatedDixon(seriesList, anchor)
%FINDRELATEDDIXON  Return all series belonging to the same Dixon family.
%
% Primary path (preferred): when the anchor carries FamilySeriesNums
%   (embedded by buildGroups from dixon_parseDICOMExam), look up those
%   exact series numbers in seriesList.  This handles both old-convention
%   exams (arbitrary recon numbers, e.g. anchor S5 → S15992/S15993/S15998)
%   and new-convention exams (GE prefix descendants, e.g. S12 → S1201/S1202)
%   correctly, and keeps duplicate acquisitions separated by construction.
%
% Fallback path: when FamilySeriesNums is absent (e.g. fallback tree or
%   a series selected directly), collect all IDEAL-IQ series that contain
%   useful content (water/fat/pdff) — the April-18 logic that is known to
%   work for single-acquisition exams.

    group = struct([]);

    anchorDesc = lower(char(anchor.SeriesDescription));

    isIdealAnchor = strcmp(anchor.Role,'IDEALIQ_Family') || ...
                    strcmp(anchor.Role,'IDEALIQ_PDFF')   || ...
                    strcmp(anchor.Role,'IDEALIQ_Multi')  || ...
                    strcmp(anchor.Role,'IDEALIQ_T2s')    || ...
                    strcmp(anchor.Role,'IDEALIQ_Raw')    || ...
                    contains(anchorDesc,'ideal');

    if isIdealAnchor
        % ── Primary: use pre-resolved family membership ──────────────────
        if isfield(anchor,'FamilySeriesNums') && ~isempty(anchor.FamilySeriesNums)
            famNums = double(anchor.FamilySeriesNums);
            for k = 1:numel(seriesList)
                if ismember(double(seriesList(k).SeriesNumber), famNums)
                    if isempty(group), group = seriesList(k);
                    else, group(end+1) = seriesList(k); end %#ok<AGROW>
                end
            end
            if ~isempty(group)
                [~, idx] = sort([group.SeriesNumber]);
                group = group(idx);
                return
            end
        end

        % ── Fallback: collect all qualifying IDEAL-IQ series (Apr-18 logic) ─
        targetN = double(anchor.nImages);
        for k = 1:numel(seriesList)
            s = seriesList(k);
            sdesc = lower(char(s.SeriesDescription));
            sRole = char(s.Role);

            isIdealRole = startsWith(sRole, 'IDEALIQ_');
            isIdeal     = contains(sdesc,'ideal') || contains(sdesc,'dixon') || isIdealRole;

            isUseful  = contains(sdesc,'fatfrac') || contains(sdesc,'water') || ...
                        contains(sdesc,'fat') || ...
                        contains(sdesc,'inphase') || contains(sdesc,'in phase') || ...
                        contains(sdesc,'outphase') || contains(sdesc,'out phase') || ...
                        contains(sdesc,'in-phase') || contains(sdesc,'out-of-phase');

            isRawRecon = strcmp(sRole, 'IDEALIQ_Raw');
            sameCount  = double(s.nImages) == targetN;
            countOK    = sameCount || (isIdealRole && ~strcmp(sRole,'IDEALIQ_Multi'));

            if isIdeal && (isUseful || isRawRecon) && countOK
                if isempty(group), group = s; else, group(end+1) = s; end %#ok<AGROW>
            end
        end

        if ~isempty(group)
            [~, idx] = sort([group.SeriesNumber]);
            group = group(idx);
            return
        end
    end

    isIPOPAnchor = strcmp(anchor.Role,'IPOP_Family') || ...
                   strcmp(anchor.Role,'IPOP_Fallback') || ...
                   strcmp(anchor.Role,'IPOP_Dixon') || ...
                   isIPOP(anchor);

    if isIPOPAnchor
        % Primary: use pre-resolved family membership when available.
        if isfield(anchor,'FamilySeriesNums') && ~isempty(anchor.FamilySeriesNums)
            famNums = double(anchor.FamilySeriesNums);
            for k = 1:numel(seriesList)
                if ismember(double(seriesList(k).SeriesNumber), famNums)
                    if isempty(group), group = seriesList(k);
                    else, group(end+1) = seriesList(k); end %#ok<AGROW>
                end
            end
            if ~isempty(group)
                [~, idx] = sort([group.SeriesNumber]);
                group = group(idx);
                return
            end
        end

        % Fallback: collect all IPOP-looking series.
        for k = 1:numel(seriesList)
            s = seriesList(k);
            if isIPOP(s) || strcmp(char(s.Role),'IPOP_Dixon')
                if isempty(group)
                    group = s;
                else
                    group(end+1) = s; %#ok<AGROW>
                end
            end
        end

        if ~isempty(group)
            [~, idx] = sort([group.SeriesNumber]);
            group = group(idx);
            return
        end
    end

    group = anchor;
end

% ======================================================================
%  UTILITY
% ======================================================================

function freq = extractFreq(descStr)
%EXTRACTFREQ  Parse drive frequency from series description string.
    tok = regexp(char(descStr), '(\d+)\s*[Hh][Zz]', 'tokens');
    if ~isempty(tok)
        freq = str2double(tok{1}{1});
    else
        freq = 0;
    end
end

function tf = isIPOP(s)
%ISIPOP  True if series looks like GE IP/OP in-phase/out-of-phase.
    % Explicitly-tagged IP/OP roles are always accepted.
    if isfield(s,'Role') && any(strcmp(char(s.Role), ...
            {'IPOP_Dixon','IPOP_Family','IPOP_Fallback'}))
        tf = true; return
    end
    desc = lower(char(s.SeriesDescription));
    tf = s.IsGrayscale && (s.BitDepth == 16) && ...
         (anyContains(desc, {'ip/op','ip op','in-phase','inphase', ...
                             'out-of-phase','out of phase','ipop', ...
                             'in phase','ax ip','ax op'}) || ...
          anyContains(desc, {'ip','op'}) );
end

function tf = anyContains(str, kwList)
    tf = false;
    for k = 1:numel(kwList)
        if contains(str, kwList{k}), tf = true; return; end
    end
end

function s = truncate(str, maxLen)
    str = char(str);
    if numel(str) > maxLen
        s = [str(1:maxLen-1) '…'];
    else
        s = str;
    end
end

function tf = idealFamilyHasProcessed(fam)
% True when a Dixon IDEALIQ family contains at least one series with a
% processed-recon role (PDFF map or T2*/R2* map).  Used to distinguish
% "processed" families from "raw-only" acquisition families (e.g. old GE
% IDEAL-IQ where the raw series S5 is in its own family separate from the
% processed recons S15992-S15998).
    tf = false;
    processedRoles = {'IDEALIQ_PDFF','IDEALIQ_T2s'};
    for k = 1:numel(fam.Members)
        if any(strcmp(char(fam.Members(k).Role), processedRoles))
            tf = true; return;
        end
    end
end

function sig = idealDescSig(s)
% Description signature used to group IDEAL-IQ recons across naming conventions.
% Mirrors the idealSignature logic in dixon_parseDICOMExam: normalise to
% alphanumerics, then strip the contrast-type keywords so that Water/Fat/FatFrac/
% T2/R2* products of the same acquisition share one signature while acquisitions
% of different body parts (e.g. Abdomen vs Pelvis) remain distinct.
    desc = lower(char(s.SeriesDescription));
    % Strip parenthesised unit annotations before normalising, e.g. "(1/s)",
    % "(%)", "(ms)", so that "R2*(1/s)" and "FatFrac(%)" produce the same
    % family signature as plain "R2*" and "FatFrac".
    desc = regexprep(desc, '\([^)]{0,15}\)', ' ');
    sig  = regexprep(desc, '[^a-z0-9]+', ' ');
    sig  = regexprep(sig, '\bfatfrac\b|\bpdff\b|\bwater\b|\bfat\b|\bt2\b|\br2\*?\b|\braw\b', ' ');
    sig  = regexprep(sig, '\s+', ' ');
    sig  = strtrim(sig);
end

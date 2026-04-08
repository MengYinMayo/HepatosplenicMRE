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
%   AUTHOR  HepatosplenicMRE Platform — Phase 3
%   DATE    2026-04

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

    % ── Dixon: IDEAL-IQ preferred; IP/OP always shown as fallback ─────
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
    % Last resort: show any grayscale 16-bit series that isn't noise
    if isempty(dixCell)
        for k = 1:numel(seriesList)
            s = seriesList(k);
            if s.IsGrayscale && s.BitDepth==16 && ...
               ~ismember(s.Role,{'EPI_RawIQ','GRE_WaveMag','EPI_WaveMag','Localizer'})
                dixCell{end+1} = s; %#ok<AGROW>
            end
        end
    end

    % ── MRE: one anchor per (type × drive-frequency) group ───────────
    mreRoles = {'EPI_WaveMag_Raw','EPI_WaveMag_Proc','EPI_WaveMag','EPI_Stiffness','EPI_ConfMap','EPI_ProcWave','EPI_RawIQ', ...
                'GRE_WaveMag_Raw','GRE_WaveMag_Proc','GRE_WaveMag','GRE_Stiffness','GRE_ConfMap','GRE_ProcWave'};
    seen = containers.Map();
    for k = 1:numel(seriesList)
        s = seriesList(k);
        if ~any(strcmp(s.Role, mreRoles)), continue; end
        freq    = extractFreq(s.SeriesDescription);
        baseNum = floor(s.SeriesNumber / 100) * 100;
        key     = sprintf('%s|%.0f|%d', s.Role(1:3), freq, baseNum);
        if ~isKey(seen, key)
            seen(key)    = true;
            mreCell{end+1} = s; %#ok<AGROW>
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
            cats   = {'IDEALIQ_PDFF','IDEALIQ_Multi','IDEALIQ_T2s','IDEALIQ_Raw', ...
                      'IPOP_Fallback','Unknown'};
            labels = {'PDFF Map','Multi-contrast (all)','T2* Map','Water (raw)', ...
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
%FINDRELATEDMRE  Return all series belonging to the same MRE acquisition group.
%   Criteria: same drive frequency AND same base series number block.

    freq    = extractFreq(anchor.SeriesDescription);
    baseNum = floor(anchor.SeriesNumber / 100) * 100;
    mreType = anchor.Role(1:3);   % 'EPI' or 'GRE'

    mreRoles = {'EPI_WaveMag_Raw','EPI_WaveMag_Proc','EPI_WaveMag','EPI_Stiffness','EPI_ConfMap','EPI_ProcWave','EPI_RawIQ', ...
                'GRE_WaveMag_Raw','GRE_WaveMag_Proc','GRE_WaveMag','GRE_Stiffness','GRE_ConfMap','GRE_ProcWave'};

    group = struct([]);
    for k = 1:numel(seriesList)
        s = seriesList(k);
        if ~any(strcmp(s.Role, mreRoles)), continue; end

        sFreq    = extractFreq(s.SeriesDescription);
        sBase    = floor(s.SeriesNumber / 100) * 100;
        sMREType = s.Role(1:3);

        % Match on: same type prefix AND (same freq OR same base block)
        if strcmp(sMREType, mreType) && ...
           (abs(sFreq - freq) < 1 || sBase == baseNum)
            if isempty(group)
                group = s;
            else
                group(end+1) = s; %#ok<AGROW>
            end
        end
    end

    if isempty(group)
        group = anchor;   % at minimum return anchor
    end
end

function group = findRelatedDixon(seriesList, anchor)
%FINDRELATEDDIXON  Return all IDEAL-IQ series that belong to the same acquisition.

    idealRoles = {'IDEALIQ_PDFF','IDEALIQ_Multi','IDEALIQ_T2s','IDEALIQ_Raw','IPOP_Fallback'};
    group = struct([]);
    for k = 1:numel(seriesList)
        s = seriesList(k);
        if any(strcmp(s.Role, idealRoles))
            if isempty(group)
                group = s;
            else
                group(end+1) = s; %#ok<AGROW>
            end
        end
    end
    if isempty(group)
        group = anchor;
    end
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
    desc = lower(s.SeriesDescription);
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

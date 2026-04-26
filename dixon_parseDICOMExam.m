function dixonExam = dixon_parseDICOMExam(exam)
% DIXON_PARSEDICOMEXAM  Resolve Dixon acquisition families from an exam.
% Keeps Dixon grouping independent from the MRE parser.
%
% Family rules:
%   - IDEAL-IQ / mDixon family: grouped by a normalized description
%     signature so WATER / FAT / FatFrac / raw products from the same
%     acquisition stay together, even when series numbers are far apart.
%   - Conventional 2-point Dixon family: grouped separately from IDEAL-IQ,
%     and a single combined IP/OP series is allowed to be its own family.

    dixonExam = struct('Families', struct([]));
    if nargin < 1 || isempty(exam) || ~isfield(exam,'Series') || isempty(exam.Series)
        return
    end

    series = exam.Series;
    fams = struct([]);

    % ---------- IDEAL-IQ / mDixon families ----------
    idealSigs = containers.Map('KeyType','char','ValueType','any');
    for k = 1:numel(series)
        s = series(k);
        if ~isLikelyIdealMember(s)
            continue
        end
        sig = idealSignature(s);
        if isempty(sig)
            sig = sprintf('ideal_%d', floor(double(s.SeriesNumber)/100));
        end
        if isKey(idealSigs, sig)
            nums = idealSigs(sig);
            nums(end+1) = k; %#ok<AGROW>
            idealSigs(sig) = nums;
        else
            idealSigs(sig) = k;
        end
    end
    sigKeys = keys(idealSigs);
    for i = 1:numel(sigKeys)
        idx = idealSigs(sigKeys{i});
        members = orderBySeriesNumber(series(idx));
        anchor = chooseIdealAnchor(members);
        fam = buildFamilyStruct('IDEALIQ', members, anchor);
        fams = appendFamily(fams, fam);
    end

    % ---------- Conventional IP/OP families ----------
    ipopSigs = containers.Map('KeyType','char','ValueType','any');
    for k = 1:numel(series)
        s = series(k);
        if ~isLikelyIPOPMember(s)
            continue
        end
        sig = ipopSignature(s);
        if isempty(sig)
            sig = sprintf('ipop_%d', floor(double(s.SeriesNumber)/100));
        end
        if isKey(ipopSigs, sig)
            nums = ipopSigs(sig);
            nums(end+1) = k; %#ok<AGROW>
            ipopSigs(sig) = nums;
        else
            ipopSigs(sig) = k;
        end
    end
    sigKeys = keys(ipopSigs);
    for i = 1:numel(sigKeys)
        idx = ipopSigs(sigKeys{i});
        members = orderBySeriesNumber(series(idx));
        anchor = chooseIPOPAnchor(members);
        fam = buildFamilyStruct('IPOP', members, anchor);
        fams = appendFamily(fams, fam);
    end

    if ~isempty(fams)
        [~, ord] = sort(arrayfun(@(f) double(f.Anchor.SeriesNumber), fams));
        fams = fams(ord);
    end
    dixonExam.Families = fams;
end

function fam = buildFamilyStruct(typeName, members, anchor)
    fam = struct();
    fam.Type = typeName;
    fam.Anchor = anchor;
    fam.Members = orderBySeriesNumber(members);
    fam.SeriesNums = [fam.Members.SeriesNumber];
    fam.Label = sprintf('%s  S%06d  %s', typeName, double(anchor.SeriesNumber), strtrim(char(anchor.SeriesDescription)));
end

function anchor = chooseIdealAnchor(family)
    anchor = family(1);
    best = -inf;
    for i = 1:numel(family)
        s = family(i);
        desc = lower(char(s.SeriesDescription));
        score = 0;
        if isFatFracDesc(desc), score = score + 100; end
        if isPreferredWaterDesc(desc), score = score + 80; end
        if isPreferredFatDesc(desc),   score = score + 70; end
        if strcmp(s.Role,'IDEALIQ_PDFF'), score = score + 30; end
        if strcmp(s.Role,'IDEALIQ_Raw'),  score = score - 30; end
        score = score - 1e-3 * double(s.SeriesNumber);
        if score > best
            best = score;
            anchor = s;
        end
    end
end

function anchor = chooseIPOPAnchor(family)
    anchor = family(1);
    best = -inf;
    for i = 1:numel(family)
        s = family(i);
        desc = lower(char(s.SeriesDescription));
        score = 0;
        if contains(desc,'ip/op') || contains(desc,'ip_op') || contains(desc,'ipop')
            score = score + 25;
        end
        if looksLikeInPhase(desc), score = score + 15; end
        if looksLikeOutPhase(desc), score = score + 10; end
        score = score - 1e-3 * double(s.SeriesNumber);
        if score > best
            best = score;
            anchor = s;
        end
    end
end

function tf = isLikelyIdealMember(s)
    desc = lower(char(s.SeriesDescription));
    role = ''; try, role = char(s.Role); catch, end
    % Series whose description contains both an MRE keyword and water/fat
    % (e.g. "Water MRE", "FAT_MRE") are MRE-specific images, not Dixon.
    if isMREWaterOrFat(desc), tf = false; return; end
    tf = startsWith(role,'IDEALIQ_') || contains(desc,'ideal') || contains(desc,'dixon') || ...
         isFatFracDesc(desc) || isWaterDesc(desc) || isFatDesc(desc);
    % Keep pure conventional IP/OP out of IDEAL families.
    if tf && isLikelyIPOPText(desc) && ~contains(desc,'ideal') && ~contains(desc,'dixon')
        tf = false;
    end
end

function tf = isLikelyIPOPMember(s)
    % Series explicitly classified as IPOP_Dixon by mre_parseDICOMExam
    role = ''; try, role = char(s.Role); catch, end
    if strcmp(role, 'IPOP_Dixon')
        tf = true; return
    end
    desc = lower(char(s.SeriesDescription));
    tf = isLikelyIPOPText(desc);
    if tf && (contains(desc,'ideal') || contains(desc,'dixon') || isFatFracDesc(desc) || isWaterDesc(desc) || isFatDesc(desc))
        tf = false;
    end
end

function tf = isLikelyIPOPText(desc)
    tf = contains(desc,'ip/op') || contains(desc,'ip_op') || contains(desc,'ipop') || ...
         looksLikeInPhase(desc) || looksLikeOutPhase(desc);
end

function sig = idealSignature(s)
    desc = lower(char(s.SeriesDescription));
    % Strip parenthesised unit annotations before normalising, e.g. "(1/s)",
    % "(%)", "(ms)", so that "R2*(1/s)" and "FatFrac(%)" produce the same
    % family signature as plain "R2*" and "FatFrac" respectively.
    desc = regexprep(desc, '\([^)]{0,15}\)', ' ');
    sig = normalizeSignature(desc);
    sig = regexprep(sig, '\bfatfrac\b|\bpdff\b|\bwater\b|\bfat\b|\bt2\b|\br2\*?\b|\braw\b', ' ');
    sig = regexprep(sig, '\s+', ' ');
    sig = strtrim(sig);
end

function sig = ipopSignature(s)
    desc = lower(char(s.SeriesDescription));
    sig = normalizeSignature(desc);
    sig = regexprep(sig, '\bin\b|\bout\b|\bphase\b|\bip\b|\bop\b|\bip op\b|\bipop\b', ' ');
    sig = regexprep(sig, '\s+', ' ');
    sig = strtrim(sig);
end

function sig = normalizeSignature(desc)
    sig = regexprep(desc, '[^a-z0-9]+', ' ');
    sig = regexprep(sig, '\s+', ' ');
    sig = strtrim(sig);
end

function tf = isFatFracDesc(desc)
    tf = contains(desc,'fatfrac') || contains(desc,'fat frac') || contains(desc,'pdff');
end

function tf = isWaterDesc(desc)
    tf = contains(desc,'water') && ~isFatFracDesc(desc) && ~isMREWaterOrFat(desc);
end

function tf = isFatDesc(desc)
    tf = (contains(desc,' fat') || contains(desc,'_fat') || startsWith(strtrim(desc),'fat') || contains(desc,'fat image')) && ...
         ~isFatFracDesc(desc) && ~isMREWaterOrFat(desc);
end

function tf = isMREWaterOrFat(desc)
% True when the description simultaneously contains an MRE identifier and a
% water/fat identifier (e.g. "Water MRE", "FAT_MRE"), indicating an
% MRE-specific image rather than a Dixon/IDEAL-IQ series.
% desc must already be lower-cased.
    hasMRE = contains(desc, 'mre') || contains(desc, 'elastograph');
    hasWF  = contains(desc, 'water') || contains(desc, 'fat');
    tf = hasMRE && hasWF;
end

function tf = isPreferredWaterDesc(desc)
    tf = isWaterDesc(desc) && (contains(desc,'t2') || contains(desc,'r2'));
end

function tf = isPreferredFatDesc(desc)
    tf = isFatDesc(desc) && (contains(desc,'t2') || contains(desc,'r2'));
end

function tf = looksLikeInPhase(desc)
    tf = contains(desc,'in phase') || contains(desc,'in-phase') || contains(desc,' ax ip') || ...
         endsWith(strtrim(desc),' ip') || contains(desc,' ip ') || contains(desc,'opp in');
end

function tf = looksLikeOutPhase(desc)
    tf = contains(desc,'out phase') || contains(desc,'out-of-phase') || contains(desc,' ax op') || ...
         endsWith(strtrim(desc),' op') || contains(desc,' op ') || contains(desc,'opp out');
end

function out = orderBySeriesNumber(in)
    out = in;
    if isempty(out), return; end
    [~, ord] = sort(double([out.SeriesNumber]));
    out = out(ord);
end

function fams = appendFamily(fams, fam)
    if isempty(fams)
        fams = fam;
    else
        fams(end+1) = fam; %#ok<AGROW>
    end
end

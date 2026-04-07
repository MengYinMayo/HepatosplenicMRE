function val = getHeaderField(hdr, field, default)
% Safely extract a DICOM header field with a fallback default.
    if isfield(hdr, field) && ~isempty(hdr.(field))
        val = hdr.(field);
    else
        val = default;
    end
end

function result = containsAny(str, keywords)
% Return true if str contains any keyword (case-insensitive).
    result = false;
    if isempty(str), return; end
    str = lower(char(str));
    for k = 1:numel(keywords)
        if ~isempty(regexp(str, lower(keywords{k}), 'once'))
            result = true;
            return
        end
    end
end
function [seriesMap, studyMeta] = groupSeriesByUID(files, verbose)
% Read one header per file, group by SeriesInstanceUID.
% Returns a containers.Map:  UID → {header1, header2, ...}

    seriesMap = containers.Map('KeyType','char','ValueType','any');
    studyMeta = struct('patientID','','studyDate','','studyUID','');
    metaSet   = false;

    nFiles = numel(files);
    if verbose
        fprintf('[Import] Reading headers (%d files)...\n', nFiles);
    end

    for i = 1:nFiles
        try
            hdr = dicominfo(files{i}, 'UseDictionaryVIP', false);
        catch
            continue   % skip non-conformant files silently
        end

        % Extract study-level metadata on first valid file
        if ~metaSet
            studyMeta.patientID = getHeaderField(hdr, 'PatientID', 'UNKNOWN');
            studyMeta.studyDate = getHeaderField(hdr, 'StudyDate', '');
            studyMeta.studyUID  = getHeaderField(hdr, 'StudyInstanceUID', '');
            metaSet = true;
        end

        uid = getHeaderField(hdr, 'SeriesInstanceUID', sprintf('UNKNOWN_%d', i));

        if isKey(seriesMap, uid)
            existing = seriesMap(uid);
            existing{end+1} = hdr;
            seriesMap(uid) = existing;
        else
            seriesMap(uid) = {hdr};
        end
    end
end
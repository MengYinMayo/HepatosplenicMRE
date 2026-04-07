function files = collectDICOMFiles(rootDir)
% Recursively find all DICOM files. Handles both flat and nested layouts.

    allFiles = dir(fullfile(rootDir, '**', '*'));
    allFiles = allFiles(~[allFiles.isdir]);

    files = {};
    for i = 1:numel(allFiles)
        fpath = fullfile(allFiles(i).folder, allFiles(i).name);
        % isdicom is fast — reads only the preamble
        if isdicom(fpath)
            files{end+1} = fpath; %#ok<AGROW>
        end
    end
end
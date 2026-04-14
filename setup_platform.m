%% SETUP_PLATFORM  Configure MATLAB path for the HepatosplenicMRE platform.
%
% Use this version instead of addpath(genpath(...)). It avoids accidentally
% adding old patch folders or extracted ZIP folders that contain duplicate
% copies of HepatosplenicMRE_App.m.

clc;
fprintf('============================================================\n');
fprintf('  HepatosplenicMRE Analysis Platform — Clean Setup\n');
fprintf('============================================================\n\n');

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
fprintf('Repo root: %s\n\n', scriptDir);

% Reset search path to avoid stale duplicate app files.
restoredefaultpath;
rehash toolboxcache;

% Add ONLY canonical project folders.
pathsToAdd = { ...
    scriptDir, ...
    fullfile(scriptDir,'functions'), ...
    fullfile(scriptDir,'functions','io'), ...
    fullfile(scriptDir,'functions','registration'), ...
    fullfile(scriptDir,'functions','segmentation')};

for k = 1:numel(pathsToAdd)
    p = pathsToAdd{k};
    if isfolder(p)
        addpath(p);
        fprintf('  + %s\n', p);
    end
end

fprintf('\nActive app copy:\n');
which HepatosplenicMRE_App -all

fprintf('\nActive setup copy:\n');
which setup_platform -all

fprintf('\n============================================================\n');
fprintf('Run next: clear classes; rehash; app = HepatosplenicMRE_App;\n');
fprintf('============================================================\n');

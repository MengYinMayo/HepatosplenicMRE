%% SETUP_PLATFORM  Configure MATLAB path and verify dependencies.
%
%   Run this script once after cloning the repository.
%   It adds all platform subfolders to the MATLAB path and checks that
%   required toolboxes are available.
%
%   USAGE
%     run('setup_platform.m')   % from the repo root folder
%
%   AUTHOR  HepatosplenicMRE Platform

clc;
fprintf('============================================================\n');
fprintf('  HepatosplenicMRE Analysis Platform — Setup\n');
fprintf('============================================================\n\n');

% ── 1.  Determine repo root ───────────────────────────────────────────
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;   % called from command window
end
fprintf('Repo root: %s\n\n', scriptDir);

% ── 2.  Add all subfolders to path ───────────────────────────────────
addpath(genpath(scriptDir));
fprintf('✓  Added to MATLAB path:\n');
subDirs = {'functions/io','functions/harmonization','functions/registration', ...
           'functions/segmentation','functions/features','functions/qc', ...
           'functions/export','config'};
for k = 1:numel(subDirs)
    p = fullfile(scriptDir, subDirs{k});
    if isfolder(p)
        fprintf('     %s\n', p);
    end
end

% ── 3.  Check MATLAB version ──────────────────────────────────────────
fprintf('\nMATLAB version: %s\n', version);
verNum = str2double(regexp(version, '\d+\.\d+', 'match', 'once'));
if verNum < 9.7   % R2019b = 9.7
    warning('setup_platform:oldMatlab', ...
        'MATLAB R2019b or later is required. Some features may not work.');
else
    fprintf('✓  MATLAB version OK\n');
end

% ── 4.  Check toolboxes ───────────────────────────────────────────────
fprintf('\nToolbox status:\n');
checkToolbox('Image Processing Toolbox', 'Image_Toolbox',      true);
checkToolbox('Deep Learning Toolbox',    'Neural_Network_Toolbox', true);
checkToolbox('Statistics and Machine Learning Toolbox', ...
                                         'Statistics_Toolbox',  false);
checkToolbox('Signal Processing Toolbox','Signal_Toolbox',      false);

% ── 5.  Verify key functions exist ───────────────────────────────────
fprintf('\nKey platform functions:\n');
checkFunction('io_loadDICOMStudy');
checkFunction('io_recognizeSequences');
checkFunction('io_readDICOMSeries');
checkFunction('io_extractSpatialInfo');
checkFunction('harm_harmonizeStudy');
checkFunction('harm_resampleVolume');
checkFunction('HepatosplenicMRE_App');

% ── 6.  Save path ─────────────────────────────────────────────────────
try
    savepath;
    fprintf('\n✓  Path saved (permanent across MATLAB sessions).\n');
catch
    fprintf('\n⚠  Could not save path (may need admin rights).\n');
    fprintf('   Run: pathtool  to manage path manually.\n');
end

fprintf('\n============================================================\n');
fprintf('  Setup complete. Launch with:  app = HepatosplenicMRE_App;\n');
fprintf('============================================================\n');


% ======================================================================
%  HELPER FUNCTIONS
% ======================================================================
function checkToolbox(name, licName, required)
    licensed = license('test', licName);
    if licensed
        fprintf('  ✓  %s\n', name);
    elseif required
        fprintf('  ✗  %s  — REQUIRED but not found!\n', name);
        fprintf('       Install via: Home → Add-Ons → Get Add-Ons\n');
    else
        fprintf('  ○  %s  — optional, not installed\n', name);
    end
end

function checkFunction(fname)
    if exist(fname, 'file') >= 2
        fprintf('  ✓  %s\n', fname);
    else
        fprintf('  ✗  %s  — NOT FOUND (check path)\n', fname);
    end
end

repoRoot = fileparts(which('HepatosplenicMRE_App'));

addpath(repoRoot);
addpath(fullfile(repoRoot,'functions','io'));
addpath(fullfile(repoRoot,'functions','registration'));
addpath(fullfile(repoRoot,'functions','segmentation'));

clear classes
close all force
rehash

app = HepatosplenicMRE_App;

% In your App Designer — L1-L2 panel button callback
function l1l2Button_Pushed(app, ~)
    if ~app.StudyData.coregistration.applied && ...
       isempty(app.StudyData.coregistration.sliceMap)
        uialert(app.UIFigure, 'Run co-registration first.', 'Prerequisite');
        return
    end

    height_m = NaN;
    if ~isempty(app.PatientHeightField.Value)
        height_m = str2double(app.PatientHeightField.Value) / 100;   % cm → m
    end

    app.L1L2StatusLabel.Text = 'Annotating...';
    drawnow;

    try
        app.StudyData = runL1L2Analysis(app.StudyData, ...
            'PatientHeight_m', height_m, ...
            'HeadlessMode',    false, ...
            'Verbose',         true);

        % Update feature table panel
        updateL1L2FeaturePanel(app);
        updateQCFlags(app);

        if app.StudyData.landmarks.L1L2.defined
            app.L1L2StatusLabel.Text  = sprintf('Done (%.0f%% MRE coverage)', ...
                app.StudyData.landmarks.L1L2.mreCoverage * 100);
        else
            app.L1L2StatusLabel.Text = 'Cancelled';
        end

    catch ME
        app.L1L2StatusLabel.Text = 'Failed';
        rethrow(ME);
    end
end

function updateL1L2FeaturePanel(app)
% Populate the body composition sub-panel in your GUI feature table
    f  = app.StudyData.features.l1l2;
    lm = app.StudyData.landmarks.L1L2;

    rows = {
        'Muscle area (L1-L2)',    sprintf('%.2f cm²', f.muscleArea_cm2),      'area';
        'SAT area (L1-L2)',       sprintf('%.2f cm²', f.satArea_cm2),         'area';
        'Muscle:SAT ratio',       sprintf('%.3f',     f.muscleSATratio),       'ratio';
        'Muscle PDFF',            sprintf('%.1f %%',  f.musclePDFF_pct),       'pdff';
        'Muscle stiffness',       ternary(~isnan(f.muscleStiffness_kPa), ...
                                    sprintf('%.2f kPa', f.muscleStiffness_kPa), 'N/A (FOV)'), 'stiff';
        'SMI',                    ternary(~isnan(f.SMI), ...
                                    sprintf('%.2f cm²/m²', f.SMI), 'N/A (height?)'), 'smi';
        'MRE coverage',           sprintf('%.0f%%', lm.mreCoverage * 100),     'qc';
        'Dixon slices used',      num2str(lm.nDixonSlices),                    'qc';
    };

    % Populate your UI table here — implementation depends on your table component
    app.L1L2FeatureTable.Data = rows;
end

function v = ternary(cond, a, b)
    if cond, v = a; else, v = b; end
end
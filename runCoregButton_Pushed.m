% In your GUI — called after import, before segmentation
function runCoregButton_Pushed(app, ~)
    if isempty(app.StudyData.mre.magnitude.pixelData)
        uialert(app.UIFigure, 'Load a study first.', 'No data');
        return
    end

    app.PipelineStep2Status.Text = 'Running...';
    app.PipelineStep2Status.FontColor = [0.10, 0.37, 0.65];
    drawnow;

    try
        threshold = app.MotionThresholdSpinner.Value;   % mm, user-editable
        app.StudyData = runCoregistration(app.StudyData, ...
            'MotionThreshold_mm', threshold, ...
            'Verbose', true);

        updateViewerOverlays(app);    % refresh image viewer with aligned data
        updateQCFlags(app);

        if app.StudyData.coregistration.applied
            app.PipelineStep2Status.Text = 'Done (motion corrected)';
        else
            app.PipelineStep2Status.Text = 'Done (geometric)';
        end
        app.PipelineStep2Status.FontColor = [0.06, 0.43, 0.34];

    catch ME
        app.PipelineStep2Status.Text = 'Failed';
        app.PipelineStep2Status.FontColor = [0.64, 0.17, 0.17];
        rethrow(ME);
    end
end
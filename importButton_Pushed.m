% In your GUI callback (e.g., importButton_Pushed):
function importButton_Pushed(app, ~)
    dicomDir = uigetdir('', 'Select DICOM study folder');
    if isequal(dicomDir, 0), return; end

    site = app.SiteDropDown.Value;   % 'Mayo' or 'UCSD'

    app.StatusLabel.Text = 'Importing...';
    drawnow;

    try
        app.StudyData = importDICOM(dicomDir, site, 'Verbose', true);
        updateSeriesBrowser(app);       % refresh left panel
        updateQCFlags(app);             % refresh status bar
        app.StatusLabel.Text = sprintf('Imported: %s (%s)', ...
            app.StudyData.patientID, app.StudyData.qc.status);
    catch ME
        app.StatusLabel.Text = 'Import failed — see console';
        rethrow(ME);
    end
end
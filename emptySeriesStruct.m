function s = emptySeriesStruct()
    s.seriesUID    = '';
    s.description  = '';
    s.modality     = '';
    s.nSlices      = 0;
    s.pixelData    = [];       % [rows x cols x slices], physical units
    s.voxelSize_mm = [NaN NaN NaN];   % [row col slice] spacing
    s.imagePosition = [];      % [3 x nSlices] IPP vectors
    s.imageOrientation = [];   % [6 x 1] IOP cosines
    s.headers      = {};       % cell array of per-slice dicominfo structs
    s.seriesType   = '';       % assigned by classifier
    s.identified   = false;
end

function s = emptyDixonStruct()
    % Dixon has 4 named channels
    channels = {'inPhase','outPhase','fat','water'};
    for i = 1:numel(channels)
        s.(channels{i}) = emptySeriesStruct();
    end
    s.nSlices     = 0;
    s.voxelSize_mm = [NaN NaN NaN];
    s.allFound    = false;
end

function s = emptyMREStruct()
    s.magnitude   = emptySeriesStruct();
    s.stiffness   = emptySeriesStruct();   % kPa map
    s.wave        = emptySeriesStruct();   % wave image (if present)
    s.nSlices     = 0;
    s.frequency_Hz = NaN;
    s.allFound    = false;
end
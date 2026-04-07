function S = computeL1L2AreaRatios(S, varargin)
% COMPUTEL1L2AREARATIOS  Compute muscle:SAT ratio and SMI.
%
%   muscleToSATratio  = muscleArea_cm2 / satArea_cm2
%   SMI (skeletal muscle index) = muscleArea_cm2 / height_m^2
%
%   SMI requires patient height — passed as optional parameter or
%   read from DICOM PatientSize field if available.

    p = inputParser();
    addParameter(p, 'PatientHeight_m', NaN, @isnumeric);
    addParameter(p, 'Verbose',         true, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    f = S.features.l1l2;

    if isnan(f.muscleArea_cm2) || isnan(f.satArea_cm2)
        warning('computeL1L2AreaRatios:missingFeatures', ...
            'Muscle or SAT area is NaN — run extractBodyCompAtL1L2 first.');
        return
    end

    %% --- Muscle:SAT area ratio ---
    if f.satArea_cm2 > 0
        S.features.l1l2.muscleSATratio = f.muscleArea_cm2 / f.satArea_cm2;
    else
        S.features.l1l2.muscleSATratio = NaN;
        S.qc.flags{end+1} = 'L1-L2: SAT area is zero — ratio undefined';
    end

    %% --- Skeletal muscle index ---
    height_m = opts.PatientHeight_m;

    % Try to read from DICOM if not supplied
    if isnan(height_m) && ~isempty(S.dixon.fat.headers)
        heightDICOM = getHeaderField(S.dixon.fat.headers{1}, 'PatientSize', NaN);
        if ~isnan(heightDICOM) && heightDICOM > 0
            height_m = heightDICOM;   % DICOM stores height in meters
        end
    end

    if ~isnan(height_m) && height_m > 0
        S.features.l1l2.SMI            = f.muscleArea_cm2 / (height_m^2);
        S.features.l1l2.patientHeight_m = height_m;
    else
        S.features.l1l2.SMI = NaN;
        if opts.Verbose
            fprintf('[L1-L2] Patient height not available — SMI cannot be computed\n');
        end
    end

    %% --- Sarcopenia flag (reference thresholds — sex-specific, adjust for your cohort) ---
    % Newman et al. thresholds (approximate — for flagging only, not diagnosis)
    sarcoThresh_male   = 7.26;   % cm2/m2
    sarcoThresh_female = 5.45;   % cm2/m2
    sex = '';   % would come from DICOM PatientSex field
    if ~isempty(S.dixon.fat.headers)
        sex = lower(getHeaderField(S.dixon.fat.headers{1}, 'PatientSex', ''));
    end

    S.features.l1l2.sarcopeniaFlag = false;
    if ~isnan(S.features.l1l2.SMI)
        if strcmp(sex,'m') && S.features.l1l2.SMI < sarcoThresh_male
            S.features.l1l2.sarcopeniaFlag = true;
        elseif strcmp(sex,'f') && S.features.l1l2.SMI < sarcoThresh_female
            S.features.l1l2.sarcopeniaFlag = true;
        end
    end

    if opts.Verbose
        fprintf('[L1-L2] Muscle:SAT ratio: %.3f\n', S.features.l1l2.muscleSATratio);
        if ~isnan(S.features.l1l2.SMI)
            fprintf('[L1-L2] SMI: %.2f cm²/m² (sarcopenia flag: %d)\n', ...
                S.features.l1l2.SMI, S.features.l1l2.sarcopeniaFlag);
        end
    end
end
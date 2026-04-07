function S = validateSeriesCompleteness(S, verbose)
% Check that all required series were identified. Flag gaps.

    required = {
        'scout',          S.scout.identified,       'warning';
        'dixon_inPhase',  S.dixon.inPhase.identified,'error';
        'dixon_fat',      S.dixon.fat.identified,    'error';
        'dixon_water',    S.dixon.water.identified,  'error';
        'dixon_pdff',     S.dixon_pdff.identified,   'warning';  % optional
        'mre_magnitude',  S.mre.magnitude.identified, 'error';
        'mre_stiffness',  S.mre.stiffness.identified, 'error';
    };

    hasError = false;
    for r = 1:size(required,1)
        name    = required{r,1};
        found   = required{r,2};
        severity = required{r,3};
        if ~found
            S.qc.flags{end+1} = sprintf('[%s] Missing: %s', upper(severity), name);
            if strcmp(severity, 'error'), hasError = true; end
            if verbose
                fprintf('[Validate] %-8s Missing series: %s\n', upper(severity), name);
            end
        end
    end

    if hasError
        S.qc.status       = 'failed';
        S.qc.reviewNeeded = true;
    elseif ~isempty(S.qc.flags)
        S.qc.status       = 'flagged';
        S.qc.reviewNeeded = true;
    else
        S.qc.status = 'import_passed';
    end
end
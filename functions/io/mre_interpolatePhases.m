function W_interp = mre_interpolatePhases(W_raw, nPhasesOut, opts)
% MRE_INTERPOLATEPHASES  Interpolate MRE wave images from nPhasesIn → nPhasesOut.
%
%   W_INTERP = MRE_INTERPOLATEPHASES(W_RAW, NOUT) interpolates the wave image
%   stack along the phase (4th) dimension, increasing temporal resolution for
%   smoother animation in mmdi_roi_gui.
%
%   Default usage: 4 acquired phase offsets → 8 interpolated offsets.
%
%   ALGORITHM
%     Wave images represent cyclic mechanical displacement. The phase offsets
%     are equally spaced in [0, 2π). Interpolation is performed in the complex
%     domain (magnitude × exp(iφ)) to preserve the circular nature of the phase:
%
%       W_complex = exp(1i × W_raw)        % unit-circle phasor per voxel
%       Interpolate real and imaginary parts separately along phase dim
%       W_interp  = angle(W_interp_complex) × amplitude
%
%     For W in radians (already converted by mre_readWaveMagSeries), the above
%     reduces to a simple sinusoidal interpolation. A fast alternative:
%     DFT zero-padding — equivalent to sinc interpolation, optimal for
%     band-limited wave signals.
%
%   INPUTS
%     W_raw       [nRow × nCol × nSlices × nPhasesIn]  double, radians
%     nPhasesOut  desired number of output phase offsets (default: 8)
%     opts        struct (optional): .verbose logical
%
%   OUTPUT
%     W_interp    [nRow × nCol × nSlices × nPhasesOut]  double, radians
%
%   EXAMPLE
%     W8 = mre_interpolatePhases(W4, 8);  % 4 → 8 phases
%
%   SEE ALSO  mre_buildMATFile, mmdi_roi_gui
%
%   AUTHOR  HepatosplenicMRE Platform — Phase 3

    if nargin < 2 || isempty(nPhasesOut), nPhasesOut = 8; end
    if nargin < 3, opts = struct(); end
    opts = applyDefaults(opts, struct('verbose', true));

    [nR, nC, nZ, nPhasesIn] = size(W_raw);

    if nPhasesIn == nPhasesOut
        W_interp = W_raw;
        return
    end

    vprint(opts, 'Interpolating wave: %d → %d phases [%d×%d×%d]', ...
        nPhasesIn, nPhasesOut, nR, nC, nZ);

    % ── DFT zero-padding interpolation ────────────────────────────────
    % Operates slice-by-slice to save memory.
    W_interp = zeros(nR, nC, nZ, nPhasesOut, 'double');

    for sl = 1:nZ
        % Extract [nR × nC × nPhasesIn] for this slice
        Wsl = W_raw(:,:,sl,:);                % [nR × nC × 1 × nPhasesIn]
        Wsl = reshape(Wsl, nR*nC, nPhasesIn); % [nR*nC × nPhasesIn]

        % DFT along phase dimension
        Wf = fft(Wsl, [], 2);                 % [nR*nC × nPhasesIn]

        % Zero-pad spectrum to nPhasesOut (equivalent to sinc interpolation)
        Wf_pad = zeroPadSpectrum(Wf, nPhasesIn, nPhasesOut);

        % IFFT and scale
        Wout = real(ifft(Wf_pad, [], 2)) * (nPhasesOut / nPhasesIn);

        W_interp(:,:,sl,:) = reshape(Wout, nR, nC, 1, nPhasesOut);
    end

    vprint(opts, 'Done. Output: %s', mat2str(size(W_interp)));
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function Wf_pad = zeroPadSpectrum(Wf, nIn, nOut)
%ZEROPADSPECTRUM  Insert zeros in the middle of an FFT spectrum.
%   Standard sinc-interpolation: preserve DC and positive frequencies,
%   insert zeros in the Nyquist/negative half.

    nPx = size(Wf, 1);
    Wf_pad = zeros(nPx, nOut);

    nHalf = floor(nIn / 2);

    % Copy positive frequencies (DC + lower half)
    Wf_pad(:, 1 : nHalf+1) = Wf(:, 1 : nHalf+1);

    % Copy negative frequencies (upper half) to end of new spectrum
    negStart = nIn - nHalf + 1;       % first negative freq index in input
    padNeg   = nOut - nHalf + 1;      % where to put them in output
    Wf_pad(:, padNeg : end) = Wf(:, negStart : end);

    % For even nIn, split the Nyquist bin equally
    if mod(nIn, 2) == 0
        niq = nHalf + 1;
        Wf_pad(:, niq) = Wf_pad(:, niq) / 2;
        Wf_pad(:, nOut - nHalf + 1) = Wf_pad(:, niq);
    end
end

function opts = applyDefaults(opts, defaults)
    fields = fieldnames(defaults);
    for k = 1:numel(fields)
        if ~isfield(opts, fields{k})
            opts.(fields{k}) = defaults.(fields{k});
        end
    end
end

function vprint(opts, fmt, varargin)
    if isfield(opts,'verbose') && opts.verbose
        fprintf(['[mre_interpolatePhases] ' fmt '\n'], varargin{:});
    end
end

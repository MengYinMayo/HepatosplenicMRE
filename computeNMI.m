function nmi = computeNMI(A, B, nBins)
% COMPUTENMI  Normalized mutual information between two images.
%
%   Both images should be normalized to [0,1].
%   NMI = (H(A) + H(B)) / H(A,B) — Studholme formulation.

    if nargin < 3, nBins = 64; end

    A = A(:);
    B = B(:);

    % Remove pairs where either image is zero (outside FOV)
    valid = A > 0 & B > 0;
    A = A(valid);
    B = B(valid);

    if numel(A) < 100
        nmi = 0;
        return
    end

    % Joint histogram
    edges = linspace(0, 1, nBins+1);
    jointHist = histcounts2(A, B, edges, edges);
    jointHist = jointHist / sum(jointHist(:));

    % Marginals
    pA = sum(jointHist, 2);
    pB = sum(jointHist, 1);

    % Entropies
    H_A  = -sum(pA(pA>0) .* log2(pA(pA>0)));
    H_B  = -sum(pB(pB>0) .* log2(pB(pB>0)));
    pJnt = jointHist(jointHist>0);
    H_AB = -sum(pJnt .* log2(pJnt));

    if H_AB == 0
        nmi = 0;
    else
        nmi = (H_A + H_B) / H_AB;
    end
end

function img = normalizeImage(img)
% Normalize image to [0,1], ignoring zeros (outside FOV).
    img = single(img);
    valid = img(:) ~= 0;
    if ~any(valid)
        return
    end
    lo = min(img(valid));
    hi = max(img(valid));
    if hi > lo
        img = (img - lo) / (hi - lo);
    end
    img(~valid) = 0;
end
classdef AcasV1_ExternalFunctions
% Copyright 2015 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11
%
% Static class container for external functions for use by ACAS block.

  methods (Static)

    function guideOut = processGuidance(guideIn, hrzRecoverDir, vrtRecoverDir, useSingleDir)
    % Process raw guidance output from the ACAS s-function for consistency
    % with MOPS display requirements.
      assert(length(guideIn) == 311);
      guideOut = guideIn;

      idxs_hrz = 1:271;
      idxs_vrt = 273:2:283;

      % Replace any band levels of 999 (outside altitude range).
      idxs = find(guideOut(idxs_vrt) == 999);
      if ~isempty(idxs) && length(idxs) < length(idxs_vrt)
        guideOut(idxs_vrt(idxs)) = guideOut(idxs_vrt(max(idxs)+1));
      elseif ~isempty(idxs) && length(idxs) == length(idxs_vrt)
        guideOut(idxs_vrt) = 4;
      end

      isRecoverHrz = any(guideOut(idxs_hrz) == 1);
      isRecoverVrt = any(guideOut(idxs_vrt) == 1);

      maxHrz = max(guideOut(idxs_hrz));
      maxVert = max(guideOut(idxs_vrt));

      if isRecoverHrz && isRecoverVrt && useSingleDir

        if hrzRecoverDir == 1 % go right
          guideOut(1:136) = maxHrz;
        else
          guideOut(136:271) = maxHrz;
        end

        if vrtRecoverDir == 1 % climb
          guideOut(273:2:277) = maxVert;
        else
          guideOut(277:2:283) = maxVert;
        end

      elseif (isRecoverHrz || isRecoverVrt) && ~(isRecoverHrz && isRecoverVrt)

        forceVerticalOnly = strcmpi(getenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY'), '1');
        if forceVerticalOnly && isRecoverVrt && ~isRecoverHrz
          % Preserve vertical recovery bands in the vertical-only example so
          % the pilot model can see and follow the climb/descend guidance.
          return;
        end

        idxs_rcv = guideOut(idxs_hrz) == 1;
        guideOut(idxs_hrz(idxs_rcv)) = maxHrz;

        idxs_rcv = guideOut(idxs_vrt) == 1;
        guideOut(idxs_vrt(idxs_rcv)) = maxVert;

      end

    end

  end

end


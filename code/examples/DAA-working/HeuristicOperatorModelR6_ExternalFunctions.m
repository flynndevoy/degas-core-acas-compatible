classdef HeuristicOperatorModelR6_ExternalFunctions
% Copyright 2015 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11
%
%HeuristicOperatorModelR6_ExternalFunctions
%Class wrapper for external functions called from the UAS Pilot Model for
%Traffic Avoidance Release 6.0. Assumes maneuver guidance from DAIDALUS.

    methods (Static)
    
    function [turns, wc_flag] = getMinimumTurns(bands)
    %Identifies the minimum turns to the left and right that achieve the
    %lowest possible alert level.  Returns two-element arrays of turn
    %magnitude (left, right) and corresponding alert level.
      
      turns = [0; 0]; %#ok<NASGU>
      wc_flag = [0; 0]; %#ok<NASGU>
      levels = [0, 1, 2, 3, 4];

      % find minimum turn at lowest alert level to the left 
      best = 5;
      idx_left = 136;
      left = bands(1:136);
      for ii=1:136
        if left(ii) <= best
          idx_left = ii;
          best = left(ii);
        end
      end
      
      % find minimum turn at lowest alert level to the right
      best = 5;
      idx_right = 1;
      right = bands(136:271);
      for ii=1:136
        if right(ii) < best 
          idx_right = ii;
          best = right(ii);
        end
      end
      
      % set output variables
      turns = [ idx_left - 136; idx_right - 1 ];
      wc_flag = [levels(left(idx_left)+1); levels(right(idx_right)+1)];
      
    end %getMinimumTurns
    
    
    
            function [alts, wc_flag] = getMinimumAltitudes(bands, currAlt)
    %Identifies minimum altitudes for climb and descend to achieve the
    %lowest possible alert level. Returns two-element arrays of altitudes
    %(descend, climb) and corresponding alert levels.
    %
    % The vertical-only example uses directional handling relative to the
    % current altitude instead of rounding to the nearest 500 ft bin. This
    % preserves the backend''s stronger Section 3 vertical guidance.

      levels = [0, 1, 2, 3, 4];
      altBands = bands(272:2:283);
      levelBands = bands(273:2:284);

      alts = [currAlt; currAlt];
      wc_flag = [0; 0];

      [~, nearestIdx] = min(abs(altBands - currAlt));
      currentLevel = levels(levelBands(nearestIdx)+1);
      wc_flag(:) = currentLevel;

      idx_down = 0;
      idx_up = 0;
      bestdown = inf;
      bestup = inf;
      bestdownAlt = -inf;
      bestupAlt = inf;

      for ii=272:2:283
        alt = bands(ii);
        level = bands(ii+1);

        if alt < currAlt
          if level < bestdown || (level == bestdown && alt > bestdownAlt)
            bestdown = level;
            bestdownAlt = alt;
            idx_down = ii;
          end
        elseif alt > currAlt
          if level < bestup || (level == bestup && alt < bestupAlt)
            bestup = level;
            bestupAlt = alt;
            idx_up = ii;
          end
        end
      end

      if idx_down ~= 0
        alts(1) = bands(idx_down);
        wc_flag(1) = levels(bands(idx_down+1)+1);
      end

      if idx_up ~= 0
        alts(2) = bands(idx_up);
        wc_flag(2) = levels(bands(idx_up+1)+1);
      end

    end %getMinimumAltitudes
    
    
    
    function [idx, complies] = chooseMinimumManeuver(maneuvers, wc_flags, preference_min, preference_dir, max_diff, seed)
    %Given two maneuver options (delta from current state), the alert level
    %expected for each, and the strength of the preference for the minimum
    %maneuver, returns the selected maneuver.  Can also specify a threshold
    %above which the minimum will be selected regardless of the preference
    %strength.  Also returns whether selected maneuver is consistent with
    %minimum turn direction.

      idx = 0;
      complies = true;

      % set seed if not already done
      info = rng;
      if info.Seed ~= seed
        rng(seed);
      end

      nochoice = false;

      % pick direction based on preference for minimum suggestion
      maneuver_diff = abs(diff(abs(maneuvers)));
      preferMin = rand(1) < preference_min || maneuver_diff > max_diff; 
      if all(wc_flags < 2) || all(diff(wc_flags) == 0) 
        if preferMin && diff(abs(maneuvers)) ~= 0
          [~, idx] = min(abs(maneuvers));
        elseif diff(abs(maneuvers)) ~= 0
          [~, idx] = max(abs(maneuvers));
          complies = false;
        else
          nochoice = true;
        end

      % pick direction based on minimum alert  
      else
        if wc_flags(1) ~= wc_flags(2)
          [~,idx] = min(wc_flags);
        else
          nochoice = true;
        end
      end

      % otherwise resort to basic preference for direction 1 vs. direction 2
      preferOne = rand(1) < preference_dir;
      if nochoice && preferOne
        idx = 1;
      elseif nochoice
        idx = 2;
      end

    end %chooseMinimumManeuver
    
    

    function [maneuverMagnitude] = drawManeuverMagnitude(maneuver, k, theta, offset, seed)
    %Draw maneuver magnitude relative to minimum suggestion from gamma distribution

      % set seed if not already done
      info = rng;
      if info.Seed ~= seed
        rng(seed);
      end
      
      % draw maneuver magnitude and add to minimum maneuver
      delta = HeuristicOperatorModelR6_ExternalFunctions.gammaDeviate(k,theta) + offset;
      maneuverMagnitude = maneuver + sign(maneuver)*delta;
      
      % prevent magnitude draw from reversing the direction
      if maneuver ~= 0 && sign(maneuverMagnitude) ~= sign(maneuver)
        maneuverMagnitude = maneuver;
      end
      
    end %drawManeuverMagnitude
    
    
    
    function chooseTurn = chooseBetweenHorzAndVert(preferTurn, turn_flag, vert_flag)
    %Chooses between the preferred horizontal maneuver and preferred
    %vertical maneuver; returns 1 if turn is selected, 0 if climb/descend

      % choose maneuver
      if preferTurn && turn_flag <= vert_flag
        chooseTurn = 1;
      elseif ~preferTurn && turn_flag < vert_flag
        chooseTurn = 1;
      else
        chooseTurn = 0;
      end
    end %chooseBetweenHorzAndVert
    
    
    
    function [xOut, turn, climb] = interpretIntruderStates(xIn, turnThresh_rad, vertThresh, numSamp)
    % Integrates a set of state estimates to identify manevers. Returns a
    % state vector with the velocity reoriented and flags indicating
    % intruder horizontal and vertical maneuver state.

      assert(numSamp <= 10);
      assert(size(xIn,1) == 6);
      assert(size(xIn,2) >= numSamp);
    
      % parameters
      defaultTurn = 30 * pi/180;
      minVertRate = 300;  % fpm, from MOPS
      defaultClimb = 1000; 
      
      N = size(xIn,2);
      if numSamp > 1
        
        xOut = zeros(6,1);
        xIn = xIn(:,N-numSamp+1:N);

        % use most recent position report
        xOut(1:2) = xIn(1:2,numSamp);

        % estimate current altitude as mean of the samples  -- round to 100 ft?????
        xOut(3) = mean(xIn(3,:));

        % estimate airspeed as the mean of the samples
        velXY = mean(sqrt(xIn(4,:).^2 + xIn(5,:).^2));

        % estimate whether turning from linear fit of heading samples and rotate
        % horizontal airspeed accordingly
        hdgMeas = atan2(xIn(5,:), xIn(4,:));
        idxs = hdgMeas < 0;
        hdgMeas(idxs) = hdgMeas(idxs) + 2*pi;
        fit = polyfit(-numSamp+1:1:0, hdgMeas, 1);
        if fit(1) > turnThresh_rad
          turn = 1;
        elseif fit(1) < -turnThresh_rad
          turn = -1;
        else
          turn = 0;
        end
        hdgWithTurn = mean(hdgMeas) + turn * defaultTurn;

        xOut(4) = velXY * cos(hdgWithTurn);
        xOut(5) = velXY * sin(hdgWithTurn);

        % estimate vertical state from each vertical rate sample -- does each
        % exceed the minimum to display a climb/descent arrow 
        vrateMeas = xIn(6,:) .* 60;  % fps to fpm
        vrateEst = mean( sign(vrateMeas) .* (abs(vrateMeas) > minVertRate) );  % [-1, 0, 1]
        if vrateEst > vertThresh
          climb = 1;
        elseif vrateEst < -vertThresh
          climb = -1;
        else
          climb = 0;
        end

        xOut(6) = climb * defaultClimb;
        
      else
        
        xOut = xIn(:,N);
        turn = 0;
        climb = sign(xOut(6));
        
      end

    end %interpretIntruderStates
    
    function x = gammaDeviate(k, theta)
      %Generates a gamma-distributed random deviate X ~ Gamma(k,theta) for k > 1.
      %
      %Uses method of Marsaglia and Tsang, "A Simple Method for Generating Gamma
      %Variables", ACM Transations on Mathematical Software, Vol. 26, No. 3,
      %September 2000, pp. 363-372.

      x = 0;
      if k >= 1

        d = k - (1/3);
        c = 1/sqrt(9*d);
        u = 0; %#ok<NASGU>
        v = 0;

        done = false;
        while ~done

          x = randn(1);
          u = rand(1);

          v = (1+c*x)^3;

          if u < 1-0.0331*x^4 || log(u) < 0.5*x^2 + d*(1-v+log(v))
            done = true;
          end
        end

        % by the scaling property, cX ~ Gamma(k, c*theta)
        x = theta*d*v;
        
      end
      
    end %gammaDeviate
    
    function x = exponentialDeviate(beta)
      %Generates an exponential-distributed random deviate X ~ Exp(beta)
      %where E[X]=beta, beta>0.
      
      x = 0;
      if beta > 0
      
        % Exp(beta) ~ beta * -ln(U)
        x = -beta*log(rand(1));
        
      end
      
    end %exponentialDeviate
    
  end %static methods
  
end %classdef


classdef ScriptedEncounter
% Copyright 2008 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11
%
% ScriptedEncounter: An encounter between one or more aircraft

    properties
        id
        numberOfAircraft
        
        % Initial quantities - Vectors of length this.numberOfAircraft
        
        v_ftps      % Initial true airspeed
        n_ft        % Initial north coordinate
        e_ft        % Initial east coordinate
        h_ft        % Initial altitude AGL
        heading_rad % Initial heading, clockwise of True North
        pitch_rad   % Initial pitch angle
        bank_rad    % Initial bank angle
        a_ftpss     % Initial longitudinal acceleration
      
        % Subsequent controls
        
        updates     % Array of EncounterModelEvents objects
   
        % Metadata
        runTime_s   % Duration of encounter
        altLayer    % Altitude layer
        
    end
    
    methods
        function this = ScriptedEncounter(id, initial, varargin)
            % Create a new ScriptedEncounter object
            
            if nargin > 0
                this.id = id;
                this.numberOfAircraft = numel(varargin);
                
                % Preallocate (important for MATLAB 2025 stability)
                this.v_ftps = zeros(1, this.numberOfAircraft);
                this.n_ft   = zeros(1, this.numberOfAircraft);
                this.e_ft   = zeros(1, this.numberOfAircraft);
                this.h_ft   = zeros(1, this.numberOfAircraft);
                this.heading_rad = zeros(1, this.numberOfAircraft);
                this.pitch_rad   = zeros(1, this.numberOfAircraft);
                this.bank_rad    = zeros(1, this.numberOfAircraft);
                this.a_ftpss     = zeros(1, this.numberOfAircraft);
                
                this.updates = repmat(EncounterModelEvents(), 1, this.numberOfAircraft);

                for k = 1:this.numberOfAircraft
                    this.v_ftps(k) = initial.(sprintf('v%d_ftps', k));
                    this.n_ft(k)   = initial.(sprintf('n%d_ft', k));
                    this.e_ft(k)   = initial.(sprintf('e%d_ft', k));
                    this.h_ft(k)   = initial.(sprintf('h%d_ft', k));
                    this.heading_rad(k) = initial.(sprintf('psi%d_rad', k));
                    this.pitch_rad(k)   = initial.(sprintf('theta%d_rad', k));
                    this.bank_rad(k)    = initial.(sprintf('phi%d_rad', k));
                    this.a_ftpss(k)     = initial.(sprintf('a%d_ftpss', k));

                    this.updates(k) = EncounterModelEvents('event', varargin{k});
                end
            end
        end
    end
    
    % ===============================
    % Derived quantities
    % ===============================
    
    properties (Dependent)
        initialHorizontalSeparation_ft
        initialVerticalSeparation_ft
    end
    
    methods
        function v = get.initialHorizontalSeparation_ft(this)
            v = sqrt((this.n_ft(2:end) - this.n_ft(1)).^2 + ...
                     (this.e_ft(2:end) - this.e_ft(1)).^2);
        end
        
        function v = get.initialVerticalSeparation_ft(this)
            v = abs(this.h_ft(2:end) - this.h_ft(1));
        end
    end
    
end
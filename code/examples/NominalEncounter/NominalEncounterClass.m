classdef (Sealed = true) NominalEncounterClass < Simulation
% Copyright 2008 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11

    properties              
        
        % Event file names
        eventFileNames = {'event1'; 'event2'};        
        
        % Nominal Events
        ac1NominalEvents
        ac2NominalEvents

        % Aircraft Dynamics
        ac1Dynamics
        ac2Dynamics
        
        % Control flow of Simulation
        stopConditions    
        
        % Sensor models
        ac1OwnSense
        ac1IntSense   

        % Well clear metrics calculation
        wellClearParameters    
        
        % Pre and Post processing properties
        encounterFile = ''
        metadataFile = ''
        encounterNumber
        
    end
    
    methods
        function this = NominalEncounterClass() % Constructor
            this = this@Simulation('NominalEncounter');
                      
            % Nominal Event properties
            this.ac1NominalEvents = EncounterModelEvents();
            this.ac2NominalEvents = EncounterModelEvents();
            
            % Aircraft Dynamics properties
            this.ac1Dynamics = BasicAircraftDynamics('ac1dyn_');
            this.ac2Dynamics = BasicAircraftDynamics('ac2dyn_');

            % Control flow properties
            this.stopConditions = StopConditions('', ...
                'stop_range_ft', 5*DEGAS.nm2ft, ...
                'stop_altitude_ft', 5000);                        
            
            % Sensor Models
            this.ac1OwnSense = PerfectSurveillance('ac1OwnPerfSurv_');
            this.ac1IntSense = PerfectSurveillance('ac1IntPerfSurv_');
            
            % Metrics properties
            this.wellClearParameters = WellClearMetrics('wcm_');                        
                
        end       
        
        function theSim = setupEncounter(theSim, encNumber, samples)
            % Load the nominal trajectories into the simulation
            if ~exist('samples','var')
                encounters = load(theSim.encounterFile);
                encounters = encounters.samples;
            else
                encounters = samples;
            end

            enc2Load = encounters(encNumber);

            % --- Dynamics ---
            theSim.ac1Dynamics.v_ftps = enc2Load.v_ftps(1);
            theSim.ac2Dynamics.v_ftps = enc2Load.v_ftps(2);
            theSim.ac1Dynamics.N_ft = enc2Load.n_ft(1);
            theSim.ac2Dynamics.N_ft = enc2Load.n_ft(2);
            theSim.ac1Dynamics.E_ft = enc2Load.e_ft(1);
            theSim.ac2Dynamics.E_ft = enc2Load.e_ft(2);
            theSim.ac1Dynamics.h_ft = enc2Load.h_ft(1);
            theSim.ac2Dynamics.h_ft = enc2Load.h_ft(2);
            theSim.ac1Dynamics.heading_rad = enc2Load.heading_rad(1);
            theSim.ac2Dynamics.heading_rad = enc2Load.heading_rad(2);
            theSim.ac1Dynamics.pitchAngle_rad = enc2Load.pitch_rad(1);
            theSim.ac2Dynamics.pitchAngle_rad = enc2Load.pitch_rad(2);
            theSim.ac1Dynamics.bankAngle_rad = enc2Load.bank_rad(1);
            theSim.ac2Dynamics.bankAngle_rad = enc2Load.bank_rad(2);
            theSim.ac1Dynamics.a_ftpss = enc2Load.a_ftpss(1);
            theSim.ac2Dynamics.a_ftpss = enc2Load.a_ftpss(2);
            
            % --- Events ---
            theSim.ac1NominalEvents.event = NominalEncounterClass.extractNominalEvents(enc2Load.updates(1));
            theSim.ac2NominalEvents.event = NominalEncounterClass.extractNominalEvents(enc2Load.updates(2));
            
            % --- Runtime ---
            theSim.runTime_s = enc2Load.runTime_s;
            theSim.encounterNumber = encNumber;
        end       
        
        function r = isNominal(~)
            % Returns true when this is the nominal (unequipped) simulation
            r = true;
        end

        function plot(obj)
            plot@Simulation(obj);

            % use larger vertical rate limits
            h = gca;
            set(h, 'Ylim', [-3000 3000]);

            if strcmp(obj.plottype, 'none')
                % add well clear status to title when the metric exists
                h = get(gcf, 'Children');
                h = h(6);
                h = get(h, 'Title');
                titleStr = get(h, 'String');
                if isstruct(obj.outcome) && isfield(obj.outcome, 'tLossofWellClear')
                    titleStr{1} = [titleStr{1}, ', WCV = ' num2str(~isnan(obj.outcome.tLossofWellClear))];
                end
                set(h, 'String', titleStr);
            end
        end
    end

    methods(Static, Access=private)
        function eventMatrix = extractNominalEvents(update)
            eventMatrix = [];

            if isobject(update)
                if isprop(update, 'event')
                    eventMatrix = update.event;
                elseif all(isprop(update, {'time_s','verticalRate_fps','turnRate_radps','longitudeAccel_ftpss'}))
                    eventMatrix = [update.time_s(:), update.verticalRate_fps(:), update.turnRate_radps(:), update.longitudeAccel_ftpss(:)];
                end
            elseif isstruct(update)
                if isfield(update, 'event') && ~isempty(update.event)
                    eventMatrix = update.event;
                elseif all(isfield(update, {'time_s','verticalRate_fps','turnRate_radps','longitudeAccel_ftpss'}))
                    eventMatrix = [update.time_s(:), update.verticalRate_fps(:), update.turnRate_radps(:), update.longitudeAccel_ftpss(:)];
                end
            end

            if isempty(eventMatrix)
                eventMatrix = [0 0 0 0];
            end
        end
    end

    methods(Access=protected)
        function eventScripts = getEventMatrices(this)
            % Must return a cell array containing the event matrix for every aircraft
            eventScripts(1) = {this.ac1NominalEvents.event};
            eventScripts(2) = {this.ac2NominalEvents.event};
        end      
    end
    
end


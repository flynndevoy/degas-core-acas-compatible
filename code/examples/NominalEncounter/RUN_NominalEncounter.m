% NominalEncounter wrapper
% Copyright 2008 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11
%
% This script shows how to go through the complete simulation pipeline for
% running a two aircraft encounter

% Switch to the directory that conains the simulation
simDir = which('NominalEncounter.slx');
[simDir,~,~] = fileparts(simDir);
cd(simDir);

% Input encounter number to simulate (Number 8 for setup scenario)
encNum = 1;

% Instantiate the simulation object
s = NominalEncounterClass;

% Setup the file to read the encounters from
s.encounterFile = resolve_latest_nmac100_encounter_file('');
encounterData = load(s.encounterFile);
samples = normalize_scripted_encounters(encounterData.samples);

% Setup a metadata file associated with the encounters file
s.metadataFile = 'metaData.mat';

% Setup the encounter. The encounter number is usually used as the input to
% the function to set the random seed used in the simulation
s.setupEncounter(encNum, samples);

% Run the simulation
s.runSimulink(encNum);

% Plot the encounter geometry
s.plot

% Read the well clear flag
s.getSimulationOutput('WCMetrics');

function encounterFile = resolve_latest_nmac100_encounter_file(encounterFile)
    if ~isempty(encounterFile)
        return;
    end

    encToolRoot = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Encounter_Generation_Tool';
    if exist(encToolRoot, 'dir') == 7 && isempty(which('ScriptedEncounter'))
        addpath(genpath(encToolRoot));
    end

    outRoot = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs';
    candidates = dir(fullfile(outRoot, 'NMAC100_*', 'scriptedEncounters.mat'));
    candidates = candidates(~contains({candidates.folder}, 'NMAC100_batches_'));
    assert(~isempty(candidates), 'No NMAC100 scriptedEncounters.mat files found under %s.', outRoot);

    [~, idx] = max([candidates.datenum]);
    encounterFile = fullfile(candidates(idx).folder, candidates(idx).name);
    fprintf('Using encounter file: %s\n', encounterFile);
end

function samples = normalize_scripted_encounters(samplesIn)
    samples = repmat(struct( ...
        'id', [], ...
        'numberOfAircraft', [], ...
        'v_ftps', [], ...
        'n_ft', [], ...
        'e_ft', [], ...
        'h_ft', [], ...
        'heading_rad', [], ...
        'pitch_rad', [], ...
        'bank_rad', [], ...
        'a_ftpss', [], ...
        'updates', [], ...
        'runTime_s', [], ...
        'altLayer', []), size(samplesIn));

    for i = 1:numel(samplesIn)
        src = samplesIn(i);
        if ~isstruct(src)
            src = struct(src);
        end

        samples(i).id = src.id;
        samples(i).numberOfAircraft = src.numberOfAircraft;
        samples(i).v_ftps = src.v_ftps;
        samples(i).n_ft = src.n_ft;
        samples(i).e_ft = src.e_ft;
        samples(i).h_ft = src.h_ft;
        samples(i).heading_rad = src.heading_rad;
        samples(i).pitch_rad = src.pitch_rad;
        samples(i).bank_rad = src.bank_rad;
        samples(i).a_ftpss = src.a_ftpss;
        samples(i).runTime_s = src.runTime_s;
        if isfield(src, 'altLayer')
            samples(i).altLayer = src.altLayer;
        end

        updatesSrc = src.updates;
        updates = repmat(struct( ...
            'time_s', [], ...
            'verticalRate_fps', [], ...
            'turnRate_radps', [], ...
            'longitudeAccel_ftpss', [], ...
            'event', []), size(updatesSrc));

        for acIdx = 1:numel(updatesSrc)
            upd = updatesSrc(acIdx);
            if ~isstruct(upd)
                upd = struct(upd);
            end

            if isfield(upd, 'event') && ~isempty(upd.event)
                if ~isfield(upd, 'time_s') || isempty(upd.time_s)
                    upd.time_s = upd.event(:, 1);
                end
                if ~isfield(upd, 'verticalRate_fps') || isempty(upd.verticalRate_fps)
                    upd.verticalRate_fps = upd.event(:, 2);
                end
                if ~isfield(upd, 'turnRate_radps') || isempty(upd.turnRate_radps)
                    upd.turnRate_radps = upd.event(:, 3);
                end
                if ~isfield(upd, 'longitudeAccel_ftpss') || isempty(upd.longitudeAccel_ftpss)
                    upd.longitudeAccel_ftpss = upd.event(:, 4);
                end
            end

            updates(acIdx) = upd;
        end

        samples(i).updates = updates;
    end
end

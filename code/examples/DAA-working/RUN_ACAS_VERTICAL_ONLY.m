% RUN_ACAS_VERTICAL_ONLY
% Run the standard DAAEncounter model using the ACAS backend with the
% Section 3 vertical policy table enabled and horizontal ACAS actions forced to COC.
%
% This example uses the same encounter flow as RUN_ACAS / RUN_DAIDALUS,
% but disables ACAS horizontal maneuvering so we can focus on vertical logic.

% ------------------------------------------------------

% Use the local mirrored DAAEncounter model and class from this folder.
scriptDir = fileparts(mfilename('fullpath'));
assert(exist(fullfile(scriptDir,'DAAEncounter.slx'),'file') == 4, ...
    'Local DAAEncounter.slx was not found in %s.', scriptDir);
cd(scriptDir);

% Force ACAS backend path
bdclose('all');
clear classes;
clear mex;
rehash toolboxcache;

% Re-assign after reset so backend cleanup cannot drop the user settings.
% verticalPolicyCsv = '/home/flynn/projects/matlab2018/acas-vertical/scripts/section3_policy.csv';
verticalPolicyCsv = '/home/flynn/projects/matlab2018/acas-vertical/section3_policy_gpu_vertical_policy.csv';
encounterFile = resolve_latest_nmac100_encounter_file('');
encNum = 1;
stripNominalHorizontalScripts = false;

rmpath(genpath('/home/flynn/projects/matlab2018/degas-daidalus/SimulinkInterface'));
addpath(genpath('/home/flynn/projects/matlab2018/degas-acas/SimulinkInterface'));
addpath(genpath('/home/flynn/projects/matlab2018/degas-pilotmodel'));

pLogic = which('AcasV1');
pExt   = which('AcasV1_ExternalFunctions');
pMex   = which('sfnc_daidalus_alertingV201');

disp(['AcasV1 -> ' pLogic]);
disp(['AcasV1_ExternalFunctions -> ' pExt]);
disp(['sfnc_daidalus_alertingV201 -> ' pMex]);

assert(~isempty(pLogic), 'AcasV1 class not found on path');
assert(~isempty(pExt),   'AcasV1_ExternalFunctions class not found on path');
assert(~isempty(pMex),   'sfnc_daidalus_alertingV201 mex not found on path');

% Preserve the existing horizontal policy path, but force horizontal actions off in the backend.
set_degas_acas_policy('/home/flynn/projects/working_model/horizontal_logic_compact/data/policy/acas_offline_policy_table.csv');
set_degas_acas_vertical_policy(verticalPolicyCsv);
setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '1');

% Instantiate the simulation object with explicit ACAS backend
s = DAAEncounterClass('backend','acas');

% Set ACAS logic params
s.daaLogic.setAcasToNoncoop;

% Set the Well Clear Boundary to the SC-228 Well-Clear Definition
s.wellClearMetricsParams.setWellClearToNoncoop;

% Force this example to use vertical avoidance only
s.enableVertMan = 1;
s.enableHorzMan = 0;

% Set the Pilot Model to follow the guidance bands directly
s.uasPilot.noBufferMode = 1;

% Set the pilot to deterministic mode
s.uasPilot.deterministicMode = 1;

% Load the encounter file. For generated NMAC sets, keep the nominal event
% scripts intact because they define the conflict geometry.
loaded = load(encounterFile);
assert(isfield(loaded, 'samples'), 'Encounter file does not contain a ''samples'' variable: %s', encounterFile);
samples = loaded.samples;
assert(encNum >= 1 && encNum <= numel(samples), 'encNum=%d is out of bounds for %s', encNum, encounterFile);
if stripNominalHorizontalScripts
    samples(encNum) = strip_horizontal_nominal_scripts(samples(encNum));
end

% Setup the encounter using the sanitized sample
s.encounterFile = encounterFile;
s.setupEncounter(encNum, samples);

% Run the simulation
s.runSimulink(encNum);

% Plot the results
s.plot

% Plot the guidance bands
acasBandViz(s);

function encounterFile = resolve_latest_nmac100_encounter_file(encounterFile)
    if ~isempty(encounterFile)
        return;
    end

    outRoot = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs';
    candidates = dir(fullfile(outRoot, 'NMAC100_*', 'scriptedEncounters.mat'));
    candidates = candidates(~contains({candidates.folder}, 'NMAC100_batches_'));
    assert(~isempty(candidates), 'No NMAC100 scriptedEncounters.mat files found under %s.', outRoot);

    [~, idx] = max([candidates.datenum]);
    encounterFile = fullfile(candidates(idx).folder, candidates(idx).name);
    fprintf('Using encounter file: %s\n', encounterFile);
end
function sample = strip_horizontal_nominal_scripts(sample)
    for idx = 1:numel(sample.updates)
        if isfield(sample.updates(idx), 'turnRate_radps')
            sample.updates(idx).turnRate_radps(:) = 0;
        end
        if isfield(sample.updates(idx), 'longitudeAccel_ftpss')
            sample.updates(idx).longitudeAccel_ftpss(:) = 0;
        end
        if isfield(sample.updates(idx), 'event') && ~isempty(sample.updates(idx).event)
            evt = sample.updates(idx).event;
            if size(evt,2) >= 4
                evt(:,3) = 0;
                evt(:,4) = 0;
                sample.updates(idx).event = evt;
            end
        end
    end
end








% RUN_ACASEncounter
% Same flow as RUN_DAAEncounter, but forces ACAS backend.

% -------------------------------------------------------

% Switch to the directory that contains the simulation
simDir = which('DAAEncounter.slx');
[simDir,~,~] = fileparts(simDir);
cd(simDir);

% Force ACAS backend path
bdclose('all');

rehash toolboxcache;
% Re-assert encounter settings after reset
encounterFile = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs/NMAC100_batches_20260413_153521/batch_001/scriptedEncounters.mat';
encNum = 101; % change as needed
verticalPolicyCsv = '/home/flynn/projects/matlab2018/acas-vertical/section3_policy_gpu_vertical_policy.csv';

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

% Optional: set ACAS policy CSV (horizontal)
% set_degas_acas_policy('/home/flynn/projects/working_model/horizontal_logic_compact/data/policy/acas_offline_policy_table.csv');

% Set ACAS vertical policy
set_degas_acas_vertical_policy('/home/flynn/projects/matlab2018/acas-vertical/section3_policy_gpu_vertical_policy.csv');
setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '1');

% Instantiate the simulation object with explicit ACAS backend
s = DAAEncounterClass('backend','acas');

% Set ACAS logic params
s.daaLogic.setAcasToNoncoop;

% Set the Well Clear Boundary to the SC-228 Well-Clear Definition
s.wellClearMetricsParams.setWellClearToNoncoop;

% Force vertical-only avoidance
s.enableVertMan = 1;
s.enableHorzMan = 0;

% Set the Pilot Model to follow the guidance bands directly
s.uasPilot.noBufferMode = 1;

% Set the pilot to deterministic mode
s.uasPilot.deterministicMode = 1;

% Enable pilot response to advisories
s.uasPilot.operatorEnabled = 1;

% Load and normalize encounters
S = load(encounterFile);
assert(isfield(S,'samples'), 'Encounter file does not contain samples');
samples = normalize_samples(S.samples);

% Setup the file to read the encounters from
s.encounterFile = encounterFile;

% Setup the encounter
s.setupEncounter(encNum, samples);

% Run the simulation
s.runSimulink(encNum);

% Plot the results
s.plot

% Plot the guidance bands
acasBandViz(s);

%% ---------------- Local helpers ----------------
function samples = normalize_samples(samples)
for i = 1:numel(samples)
    samples(i) = normalize_sample(samples(i));
end
end

function sample = normalize_sample(sample)
if ~isfield(sample, 'updates') || isempty(sample.updates)
    sample.updates = default_updates();
    return;
end

if iscell(sample.updates)
    if numel(sample.updates) == 2 && isstruct(sample.updates{1}) && isstruct(sample.updates{2})
        sample.updates = [sample.updates{1}, sample.updates{2}];
    else
        sample.updates = sample.updates{1};
    end
end

for idx = 1:numel(sample.updates)
    up = sample.updates(idx);
    if ~isfield(up, 'event')
        up.event = [];
    end

    evt = up.event;
    if isempty(evt)
        evt = zeros(0, 4);
    elseif size(evt, 2) ~= 4
        if size(evt, 1) == 4
            evt = evt.';
        elseif numel(evt) == 4
            evt = reshape(evt, 1, 4);
        elseif size(evt, 2) < 4
            evt = [evt, zeros(size(evt,1), 4 - size(evt,2))];
        else
            evt = evt(:,1:4);
        end
    end
    up.event = evt;

    if ~isempty(up.event)
        up.time_s = up.event(:,1);
        up.verticalRate_fps = up.event(:,2);
        up.turnRate_radps = up.event(:,3);
        up.longitudeAccel_ftpss = up.event(:,4);
    end

    if ~isfield(up, 'time_s') || isempty(up.time_s)
        up.time_s = 0;
    end
    if ~isfield(up, 'verticalRate_fps') || isempty(up.verticalRate_fps)
        up.verticalRate_fps = zeros(size(up.time_s));
    end
    if ~isfield(up, 'turnRate_radps') || isempty(up.turnRate_radps)
        up.turnRate_radps = zeros(size(up.time_s));
    end
    if ~isfield(up, 'longitudeAccel_ftpss') || isempty(up.longitudeAccel_ftpss)
        up.longitudeAccel_ftpss = zeros(size(up.time_s));
    end

    sample.updates(idx) = up;
end
end

function updates = default_updates()
up = struct('time_s', 0, 'verticalRate_fps', 0, 'turnRate_radps', 0, 'longitudeAccel_ftpss', 0, 'event', [0 0 0 0]);
updates = repmat(up, 1, 2);
end
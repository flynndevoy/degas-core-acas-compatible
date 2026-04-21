% RUN_ACAS_BATCH_NO_PLOT
% Run ACAS encounters in a loop with no plotting.

% -------------------- User settings --------------------
encounterFile = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs/NMAC100_batches_20260413_153521/batch_001/scriptedEncounters.mat';
numEncounters = 10; % change as needed
encounterIds = 1:numEncounters;

pathAcas  = '/home/flynn/projects/matlab2018/degas-acas/SimulinkInterface';
pathDaid  = '/home/flynn/projects/matlab2018/degas-daidalus/SimulinkInterface';
pathPilot = '/home/flynn/projects/matlab2018/degas-pilotmodel';

policyCsv = '/home/flynn/projects/working_model/horizontal_logic_compact/data/policy/acas_offline_policy_table.csv';
verticalPolicyCsv = '/home/flynn/projects/matlab2018/acas-vertical/section3_policy_gpu_vertical_policy.csv';
forceVerticalOnly = true;
% -------------------------------------------------------

% Strong reset to avoid cross-backend cache contamination
bdclose('all');
clear classes;
clear mex;
rehash toolboxcache;

% Switch to the directory that contains the simulation
simDir = which('DAAEncounter.slx');
[simDir,~,~] = fileparts(simDir);
cd(simDir);

% Output CSV path
outDir = fullfile(simDir, 'comparison_output');
if exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

ts = datestr(now, 'yyyymmdd_HHMMSS');
outCsv = fullfile(outDir, ['sep_acas_' ts '.csv']);

daaBackend = 'acas';

configure_backend_paths(pathAcas, pathDaid, pathPilot, daaBackend);

% Validate active backend bindings before object construction
reqLogic = 'AcasV1';
reqExtFn = 'AcasV1_ExternalFunctions';

pLogic = which(reqLogic);
pExt   = which(reqExtFn);
pMex   = which('sfnc_daidalus_alertingV201');

fprintf('Backend: %s\n', daaBackend);
disp([reqLogic ' -> ' pLogic]);
disp([reqExtFn ' -> ' pExt]);
disp(['sfnc_daidalus_alertingV201 -> ' pMex]);

assert(~isempty(pLogic), 'Required logic class not found: %s', reqLogic);
assert(~isempty(pExt),   'Required external function class not found: %s', reqExtFn);
assert(~isempty(pMex),   'Required mex not found: sfnc_daidalus_alertingV201');

% Optional: set ACAS policy CSV (horizontal)
if exist(policyCsv, 'file') == 2
    set_degas_acas_policy(policyCsv);
end

% Set ACAS vertical policy (if available)
if exist(verticalPolicyCsv, 'file') == 2
    set_degas_acas_vertical_policy(verticalPolicyCsv);
end

if forceVerticalOnly
    setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '1');
else
    setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '0');
end

% Instantiate simulation object with explicit ACAS backend
s = DAAEncounterClass('backend', daaBackend);

% Configure logic profile
apply_noncoop_logic(s.daaLogic, daaBackend);

% Set the Well Clear Boundary to the SC-228 Well-Clear Definition
s.wellClearMetricsParams.setWellClearToNoncoop;

% Force vertical-only avoidance (optional)
if forceVerticalOnly
    s.enableVertMan = 1;
    s.enableHorzMan = 0;
end

% Set the Pilot Model to follow the guidance bands directly
s.uasPilot.noBufferMode = 1;

% Set the pilot to deterministic mode
s.uasPilot.deterministicMode = 1;

% Enable pilot response to advisories
s.uasPilot.operatorEnabled = 1;

% Setup the file to read the encounters from
s.encounterFile = encounterFile;

S = load(encounterFile);
assert(isfield(S,'samples'), 'Encounter file does not contain samples');
samples = normalize_samples(S.samples);
encounterIds = encounterIds(encounterIds <= numel(samples));

modeName = "acas";
rows = table('Size',[0 6], ...
    'VariableTypes', {'string','double','double','double','double','double'}, ...
    'VariableNames', {'mode','encounter','time_s','hsep_ft','vsep_ft','ssep_ft'});

fprintf('\n[acas] Running %d encounters\n', numel(encounterIds));

for encNum = encounterIds
    fprintf('[acas] encounter=%d\n', encNum);
    s.setupEncounter(encNum, samples);
    warning('off','all');
    s.runSimulink(encNum);
    [t,hsep,vsep,ssep] = compute_sep_series(s.results);
    if ~isempty(t)
        n = numel(t);
        rows = [rows; table(repmat(modeName,n,1), repmat(encNum,n,1), t(:), hsep(:), vsep(:), ssep(:), ...
            'VariableNames', rows.Properties.VariableNames)];
    end
    warning('on','all');
end

if ~isempty(rows)
    writetable(rows, outCsv);
    fprintf('[acas] CSV: %s\n', outCsv);
else
    fprintf('[acas] No separation data recorded.\n');
end

fprintf('[acas] Done.\n');

%% ---------------- Local functions ----------------
function configure_backend_paths(pathAcas, pathDaid, pathPilot, backend)
    if exist(pathAcas,'dir'); rmpath(genpath(pathAcas)); end
    if exist(pathDaid,'dir'); rmpath(genpath(pathDaid)); end
    if exist(pathPilot,'dir'); rmpath(genpath(pathPilot)); end

    switch lower(backend)
        case 'acas'
            addpath(genpath(pathAcas));
            addpath(genpath(pathPilot));
        case 'daidalus'
            addpath(genpath(pathDaid));
            addpath(genpath(pathPilot));
        otherwise
            error('Unknown backend: %s', backend);
    end
end

function apply_noncoop_logic(logicObj, backend)
    switch lower(backend)
        case 'acas'
            if ismethod(logicObj,'setAcasToNoncoop')
                logicObj.setAcasToNoncoop;
            else
                error('ACAS backend selected, but setAcasToNoncoop is unavailable on %s.', class(logicObj));
            end

        case 'daidalus'
            if ismethod(logicObj,'setDaidalusToNoncoop')
                logicObj.setDaidalusToNoncoop;
            else
                error('DAIDALUS backend selected, but setDaidalusToNoncoop is unavailable on %s.', class(logicObj));
            end

        otherwise
            error('Unknown backend: %s', backend);
    end
end

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

function [t, hsep, vsep, ssep] = compute_sep_series(resultsStruct)
t = [];
hsep = [];
vsep = [];
ssep = [];

if numel(resultsStruct) < 2
    return;
end

r1 = resultsStruct(1);
r2 = resultsStruct(2);

req = {'north_ft','east_ft','up_ft','time'};
for i = 1:numel(req)
    if ~isfield(r1, req{i}) || ~isfield(r2, req{i})
        return;
    end
end

n = min([numel(r1.north_ft), numel(r2.north_ft), ...
         numel(r1.east_ft), numel(r2.east_ft), ...
         numel(r1.up_ft), numel(r2.up_ft), ...
         numel(r1.time)]);

if n <= 0
    return;
end

dn = r1.north_ft(1:n) - r2.north_ft(1:n);
de = r1.east_ft(1:n) - r2.east_ft(1:n);
dh = abs(r1.up_ft(1:n) - r2.up_ft(1:n));

hsep = hypot(dn, de);
vsep = dh;
ssep = hypot(hsep, dh);
t = r1.time(1:n);
end
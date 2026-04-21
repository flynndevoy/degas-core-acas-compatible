% DAAEncounter wrapper
% Copyright 2008 - 2020, MIT Lincoln Laboratory
% SPDX-License-Identifier: X11
%
% Run a two-aircraft encounter with explicit backend selection.
% Set daaBackend to either 'daidalus' or 'acas'.

% -------------------------------------------------------

% Switch to the directory that contains the simulation
simDir = which('DAAEncounter.slx');
[simDir,~,~] = fileparts(simDir);
cd(simDir);

% Strong reset to avoid cross-backend cache contamination
bdclose('all');
clear classes;
clear mex;
rehash toolboxcache;
% Re-assign paths after reset
pathAcas  = '/home/flynn/projects/matlab2018/degas-acas/SimulinkInterface';
pathDaid  = '/home/flynn/projects/matlab2018/degas-daidalus/SimulinkInterface';
pathPilot = '/home/flynn/projects/matlab2018/degas-pilotmodel';



if ~exist('daaBackend','var') || isempty(daaBackend)
    daaBackend = 'daidalus';
end

configure_backend_paths(pathAcas, pathDaid, pathPilot, daaBackend);

% Validate active backend bindings before object construction
switch lower(daaBackend)
    case 'acas'
        reqLogic = 'AcasV1';
        reqExtFn = 'AcasV1_ExternalFunctions';
    case 'daidalus'
        reqLogic = 'DaidalusV201';
        reqExtFn = 'DaidalusV201_ExternalFunctions';
    otherwise
        error('Unknown daaBackend: %s', daaBackend);
end

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

% Instantiate simulation object with explicit backend
s = DAAEncounterClass('backend', daaBackend);

% Configure logic profile
apply_noncoop_logic(s.daaLogic, daaBackend);

% Set the Well Clear Boundary to the SC-228 Well-Clear Definition
s.wellClearMetricsParams.setWellClearToNoncoop;

% Set the Pilot Model to follow the guidance bands directly
s.uasPilot.noBufferMode = 1;

% Set the pilot to deterministic mode
s.uasPilot.deterministicMode = 1;

% Setup the file to read the encounters from
% s.encounterFile = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs/NMAC100_batches_20260413_153521/batch_001/scriptedEncounters.mat';
s.encounterFile = resolve_latest_nmac100_encounter_file('');

encNum = 1;

% Setup the encounter
s.setupEncounter(encNum);

% Run simulation
warning('off','all')
s.runSimulink(encNum);

% Plot trajectories
s.plot

% Plot guidance bands for the selected backend
switch lower(daaBackend)
    case 'acas'
        acasBandViz(s);
    case 'daidalus'
        daidalusBandViz(s);
    otherwise
        error('Unknown daaBackend: %s', daaBackend);
end

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

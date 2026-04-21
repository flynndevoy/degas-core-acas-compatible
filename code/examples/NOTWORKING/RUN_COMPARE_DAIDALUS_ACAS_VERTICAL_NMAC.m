% RUN_COMPARE_DAIDALUS_ACAS_VERTICAL_NMAC
% Run DAIDALUS first, then ACAS vertical-only over the same encounters.
%
% Outputs:
%   comparison_output/daidalus_acas_vert_nmac_<timestamp>.csv
%
% -------------------- User settings --------------------
numEncounters = 1; % change up to however many encounters you generated
encounterIds = 1:numEncounters;

pathAcas  = '/home/flynn/projects/matlab2018/degas-acas/SimulinkInterface';
pathDaid  = '/home/flynn/projects/matlab2018/degas-daidalus/SimulinkInterface';
pathPilot = '/home/flynn/projects/matlab2018/degas-pilotmodel';

policyCsv = '/home/flynn/projects/working_model/horizontal_logic_compact/data/policy/acas_offline_policy_table.csv';
verticalPolicyCsv = '/home/flynn/projects/matlab2018/acas-vertical/section3_policy_gpu_vertical_policy.csv';

encounterFile = '/home/flynn/projects/matlab2018/em-pairing-uncor-importancesampling/Outputs/NMAC100_batches_20260413_153521/batch_001/scriptedEncounters.mat';

% -------------------------------------------------------

simDir = which('DAAEncounter.slx');
assert(~isempty(simDir), 'DAAEncounter.slx not found on path.');
[simDir,~,~] = fileparts(simDir);
cd(simDir);

outDir = fullfile(simDir, 'comparison_output');
if exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

ts = datestr(now, 'yyyymmdd_HHMMSS');
outCsv = fullfile(outDir, ['daidalus_acas_vert_nmac_' ts '.csv']);

% Debug settings
debugRethrow = true;
stopAfterFirstError = true;

S = load(encounterFile);
assert(isfield(S, 'samples'), 'Encounter file does not contain a samples variable: %s', encounterFile);
samples = normalize_samples(S.samples);
encounterIds = encounterIds(encounterIds <= numel(samples));
assert(~isempty(encounterIds), 'No encounterIds remain after bounds check.');

runOrder = {'daidalus'};

totalRuns = numel(runOrder) * numel(encounterIds);
rows = repmat(empty_row(), totalRuns, 1);
ridx = 0;

fprintf('\n[compare] Starting comparison for %d encounters (%d total runs)\n', ...
    numel(encounterIds), totalRuns);
fprintf('[compare] Output CSV: %s\n', outCsv);

for m = 1:numel(runOrder)
    mode = runOrder{m};
    fprintf('\n[compare] Mode: %s\n', mode);

    for encNum = encounterIds
        ridx = ridx + 1;
        fprintf('[compare] (%d/%d) mode=%s encounter=%d\n', ridx, totalRuns, mode, encNum);

        row = empty_row();
        row.mode = string(mode);
        row.encounter = encNum;

        try
            s = make_sim(mode, pathAcas, pathDaid, pathPilot, policyCsv, verticalPolicyCsv);
            s.encounterFile = encounterFile;
            samples(encNum).updates = sanitize_updates(samples(encNum).updates);
            s.setupEncounter(encNum, samples);
            s.runSimulink(encNum);

            row = collect_metrics_row(s, row);
            row.ok = true;
            row.error_message = "";

        catch ME
            row.ok = false;
            row.error_message = string(ME.message);
            fprintf('[compare]   ERROR mode=%s encounter=%d: %s\\n', mode, encNum, ME.message);
            fprintf('[compare]   STACK:\\n%s\\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            if debugRethrow
                rethrow(ME);
            end
            if stopAfterFirstError
                break;
            end
        end

        rows(ridx) = row;
    end
end

T = struct2table(rows);
writetable(T, outCsv);

fprintf('\n[compare] Completed.\n');
fprintf('[compare] CSV:  %s\n', outCsv);

% ---------------- Local helpers ----------------
function s = make_sim(mode, pathAcas, pathDaid, pathPilot, policyCsv, verticalPolicyCsv)
backend = resolve_backend(mode);
configure_backend_environment(pathAcas, pathDaid, pathPilot, policyCsv, verticalPolicyCsv, backend, mode);

s = DAAEncounterClass('backend', backend);
apply_noncoop_logic(s.daaLogic, backend);

s.wellClearMetricsParams.setWellClearToNoncoop;
s.uasPilot.noBufferMode = 1;
s.uasPilot.deterministicMode = 1;

s.uasPilot.operatorEnabled = 1;
s.enableHorzMan = 1;
s.enableVertMan = 0;

if strcmpi(mode, 'acas-vert')
    s.enableHorzMan = 0;
    s.enableVertMan = 1;
    setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '1');
else
    setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '0');
end
end

function backend = resolve_backend(mode)
switch lower(mode)
    case {'acas-vert','acas'}
        backend = 'acas';
    case 'daidalus'
        backend = 'daidalus';
    otherwise
        error('Unknown mode: %s', mode);
end
end

function configure_backend_environment(pathAcas, pathDaid, pathPilot, policyCsv, verticalPolicyCsv, backend, mode)
bdclose('all');
clear mex;
rehash toolboxcache;

safe_rmpath(pathAcas);
safe_rmpath(pathDaid);
safe_rmpath(pathPilot);

switch lower(backend)
    case 'acas'
        addpath(genpath(pathAcas));
        addpath(genpath(pathPilot));
        set_degas_acas_policy(policyCsv);
        if strcmpi(mode, 'acas-vert')
            set_degas_acas_vertical_policy(verticalPolicyCsv);
        end
    case 'daidalus'
        addpath(genpath(pathDaid));
        addpath(genpath(pathPilot));
    otherwise
        error('Unknown backend: %s', backend);
end

validate_backend_bindings(backend);
end

function safe_rmpath(p)
if exist(p,'dir') ~= 7
    return;
end
if contains(path, p)
    rmpath(genpath(p));
end
end

function validate_backend_bindings(backend)
switch lower(backend)
    case 'acas'
        reqLogic = 'AcasV1';
        reqExtFn = 'AcasV1_ExternalFunctions';
    case 'daidalus'
        reqLogic = 'DaidalusV201';
        reqExtFn = 'DaidalusV201_ExternalFunctions';
    otherwise
        error('Unknown backend: %s', backend);
end

pLogic = which(reqLogic);
pExt = which(reqExtFn);
pMex = which('sfnc_daidalus_alertingV201');

assert(~isempty(pLogic), 'Required logic class not found: %s', reqLogic);
assert(~isempty(pExt), 'Required external function class not found: %s', reqExtFn);
assert(~isempty(pMex), 'Required mex not found: sfnc_daidalus_alertingV201');
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

function row = collect_metrics_row(s, row)
% Outcome flags
row.alert = logical(get_outcome_field(s, 'alert', false));
row.maneuver = logical(get_outcome_field(s, 'maneuverFlag', false));
row.lowc = ~isnan(get_outcome_field(s, 'tLossofWellClear', NaN));

row.num_alerts = get_outcome_field(s, 'numAlerts', NaN);
row.t_first_alert_s = get_outcome_field(s, 'tFirstAlert', NaN);
row.t_last_alert_s = get_outcome_field(s, 'tLastAlert', NaN);
row.t_maneuver_s = get_outcome_field(s, 'tManeuver', NaN);
row.t_lowc_s = get_outcome_field(s, 'tLossofWellClear', NaN);
row.dt_lowc_s = get_outcome_field(s, 'dtLowc', NaN);

% Geometry metrics from actual trajectory
[mins, nmacFlag] = compute_sep_metrics(s.results);
row.min_horiz_sep_ft = mins.min_horiz_sep_ft;
row.min_vert_sep_ft = mins.min_vert_sep_ft;
row.min_slant_sep_ft = mins.min_slant_sep_ft;
row.t_min_horiz_sep_s = mins.t_min_horiz_sep_s;
row.nmac_500_100 = nmacFlag;
end

function [m, nmacFlag] = compute_sep_metrics(resultsStruct)
m = struct('min_horiz_sep_ft', NaN, ...
           'min_vert_sep_ft', NaN, ...
           'min_slant_sep_ft', NaN, ...
           't_min_horiz_sep_s', NaN);

nmacFlag = false;

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
ssep = hypot(hsep, dh);

[m.min_horiz_sep_ft, idx] = min(hsep);
m.min_vert_sep_ft = min(dh);
m.min_slant_sep_ft = min(ssep);
m.t_min_horiz_sep_s = r1.time(idx);

nmacFlag = any((hsep < 500) & (dh < 100));
end

function v = get_outcome_field(s, f, fallback)
v = fallback;

if isobject(s) && isprop(s, 'outcome')
    outcome = s.outcome;
elseif isstruct(s) && isfield(s, 'outcome')
    outcome = s.outcome;
else
    return;
end

if isstruct(outcome) && isfield(outcome, f)
    tmp = outcome.(f);
    if ~isempty(tmp)
        v = tmp;
    end
end
end

function row = empty_row()
row = struct();
row.mode = "";
row.encounter = NaN;
row.ok = false;
row.error_message = "";
row.alert = false;
row.maneuver = false;
row.lowc = false;
row.num_alerts = NaN;
row.t_first_alert_s = NaN;
row.t_last_alert_s = NaN;
row.t_maneuver_s = NaN;
row.t_lowc_s = NaN;
row.dt_lowc_s = NaN;
row.min_horiz_sep_ft = NaN;
row.min_vert_sep_ft = NaN;
row.min_slant_sep_ft = NaN;
row.t_min_horiz_sep_s = NaN;
row.nmac_500_100 = false;
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

function updates = sanitize_updates(updates)
if isempty(updates)
    updates = default_updates();
    return;
end

if iscell(updates)
    try
        updates = [updates{:}];
    catch
        updates = default_updates();
        return;
    end
end

if ~isstruct(updates)
    updates = default_updates();
    return;
end

if numel(updates) < 2
    updates = repmat(updates(1), 1, 2);
elseif numel(updates) > 2
    updates = updates(1:2);
end

for k = 1:numel(updates)
    up = updates(k);
    if ~isfield(up, "event")
        up.event = [];
    end
    up.event = ensure_event_matrix(up.event);
    up.time_s = up.event(:,1);
    up.verticalRate_fps = up.event(:,2);
    up.turnRate_radps = up.event(:,3);
    up.longitudeAccel_ftpss = up.event(:,4);
    updates(k) = up;
end
end

function evt = ensure_event_matrix(evt)
% Ensure numeric Nx4 matrix for EncounterModelEvents.set.event
if ~isnumeric(evt)
    evt = [];
end

if isempty(evt)
    evt = zeros(1, 4);
    return;
end

if isvector(evt) && numel(evt) == 4
    evt = reshape(evt, 1, 4);
end

if size(evt, 2) ~= 4
    if size(evt, 1) == 4
        evt = transpose(evt);
    elseif size(evt, 2) < 4
        evt = [evt, zeros(size(evt, 1), 4 - size(evt, 2))];
    else
        evt = evt(:, 1:4);
    end
end

if isempty(evt)
    evt = zeros(1, 4);
end
end

% RUN_ACAS_HORIZONTAL_ONLY
% Run the standard DAAEncounter model using the ACAS backend with the
% developed Section 3 horizontal policy table enabled and vertical ACAS
% actions disabled.
%
% This example uses the same encounter flow as RUN_ACAS / RUN_DAIDALUS,
% but disables ACAS vertical maneuvering so we can focus on horizontal logic.

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
scriptDir = fileparts(mfilename('fullpath'));

% Re-assign after reset so backend cleanup cannot drop the user settings.
horizontalPolicyCsv = '/home/flynn/projects/matlab2018/acas-horizontal/scripts/section3_policy_gpu.csv';
horizontalBackendPolicyCsv = horizontalPolicyCsv;
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

% Point the ACAS backend at the converted horizontal policy and disable
% the optional vertical Section 3 overlay for this horizontal-only run.
set_degas_acas_policy(horizontalBackendPolicyCsv);
setenv('DEGAS_ACAS_VERTICAL_POLICY_CSV', '');
setenv('DEGAS_ACAS_FORCE_VERTICAL_ONLY', '0');

% Instantiate the simulation object with explicit ACAS backend
s = DAAEncounterClass('backend','acas');

% Set ACAS logic params
s.daaLogic.setAcasToNoncoop;

% Set the Well Clear Boundary to the SC-228 Well-Clear Definition
s.wellClearMetricsParams.setWellClearToNoncoop;

% Force this example to use horizontal avoidance only
s.enableVertMan = 0;
s.enableHorzMan = 1;

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

function outputCsv = convert_horizontal_policy_for_backend(inputCsv, outputCsv)
    if exist(outputCsv, 'file') == 2
        inInfo = dir(inputCsv);
        outInfo = dir(outputCsv);
        if ~isempty(inInfo) && ~isempty(outInfo) && outInfo.datenum >= inInfo.datenum
            fprintf('Using cached horizontal backend CSV: %s\n', outputCsv);
            return;
        end
    end

    T = readtable(inputCsv, 'TextType', 'string');
    requiredCols = ["h_ft","own_vrate_fpm","int_vrate_fpm","tau_s","sra","action"];
    assert(all(ismember(requiredCols, string(T.Properties.VariableNames))), ...
        'Horizontal policy CSV is missing required columns: %s', inputCsv);

    nRows = height(T);
    relRateFtps = round((double(T.int_vrate_fpm) - double(T.own_vrate_fpm)) ./ 60.0);
    prevAdvisory = zeros(nRows, 1);
    optimalAdvisory = strings(nRows, 1);

    for rowIdx = 1:nRows
        prevAdvisory(rowIdx) = section3_sra_to_prev_code(T.sra(rowIdx));
        optimalAdvisory(rowIdx) = section3_action_to_backend_action(T.action(rowIdx));
    end

    backendRows = table( ...
        double(T.h_ft), ...
        relRateFtps, ...
        double(T.tau_s), ...
        prevAdvisory, ...
        optimalAdvisory, ...
        'VariableNames', { ...
            'relative_altitude_ft', ...
            'vertical_rate_ft_s', ...
            'tau_sec', ...
            'previous_advisory', ...
            'optimal_advisory'});

    [groupIds, keyTable] = findgroups(backendRows(:, ...
        {'relative_altitude_ft','vertical_rate_ft_s','tau_sec','previous_advisory'}));
    collapsedAction = strings(height(keyTable), 1);
    for groupIdx = 1:height(keyTable)
        actionSubset = backendRows.optimal_advisory(groupIds == groupIdx);
        hVal = keyTable.relative_altitude_ft(groupIdx);
        collapsedAction(groupIdx) = choose_collapsed_action(actionSubset, hVal);
    end

    backendTable = keyTable;
    backendTable.optimal_advisory = collapsedAction;
    backendTable = sortrows(backendTable, ...
        {'relative_altitude_ft','vertical_rate_ft_s','tau_sec','previous_advisory'});

    writetable(backendTable, outputCsv);
    fprintf('Converted horizontal policy to backend CSV: %s\n', outputCsv);
end

function action = choose_collapsed_action(actionSubset, hVal)
    actionNames = ["COC","LEFT","RIGHT"];
    counts = zeros(size(actionNames));
    for idx = 1:numel(actionNames)
        counts(idx) = sum(actionSubset == actionNames(idx));
    end

    maxCount = max(counts);
    winners = actionNames(counts == maxCount);
    if numel(winners) == 1
        action = winners(1);
        return;
    end

    nonCoc = winners(winners ~= "COC");
    if numel(nonCoc) == 1
        action = nonCoc(1);
        return;
    end

    if any(winners == "LEFT") && any(winners == "RIGHT")
        if hVal > 0
            action = "LEFT";
        elseif hVal < 0
            action = "RIGHT";
        else
            action = "COC";
        end
        return;
    end

    action = winners(1);
end

function code = section3_sra_to_prev_code(sra)
    sra = upper(string(sra));
    if sra == "COC"
        code = 0;
    elseif contains(sra, "LEF")
        code = 1;
    elseif contains(sra, "RIG")
        code = 2;
    else
        code = 0;
    end
end

function action = section3_action_to_backend_action(section3Action)
    section3Action = upper(string(section3Action));
    if section3Action == "COC"
        action = "COC";
    elseif contains(section3Action, "LEF")
        action = "LEFT";
    elseif contains(section3Action, "RIG")
        action = "RIGHT";
    else
        action = "COC";
    end
end

function rank = section3_sra_countdown_rank(sra)
    sra = string(sra);
    if sra == "COC"
        rank = 0;
        return;
    end

    parts = split(sra, "-");
    if numel(parts) < 2
        rank = 0;
        return;
    end

    rank = str2double(parts(end));
    if ~isfinite(rank)
        rank = 0;
    end
end





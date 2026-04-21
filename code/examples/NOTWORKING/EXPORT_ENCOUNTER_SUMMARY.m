% EXPORT_ENCOUNTER_SUMMARY
% Write a one-row-per-encounter summary CSV for the DEGAS unit test set.
%
% Output:
%   encounter_summary.csv

% -------------------- User settings --------------------
encounterFile = 'unitTestEncounters.mat';
outCsvName = 'encounter_summary.csv';
% -------------------------------------------------------

simDir = fileparts(which('DAAEncounter.slx'));
assert(~isempty(simDir), 'DAAEncounter.slx not found on path.');
cd(simDir);

encounterFile = resolve_encounter_file(encounterFile);
assert(~isempty(encounterFile), 'Could not locate unitTestEncounters.mat.');

S = load(encounterFile);
assert(isfield(S, 'samples'), 'Encounter file does not contain a samples variable.');
samples = S.samples;

encounterIds = 1:50;
numEncs = numel(encounterIds);
rows = repmat(empty_row(), numEncs, 1);

for i = 1:numEncs
    encId = encounterIds(i);
    enc = samples(encId);
    rows(i) = summarize_encounter(enc, encId);
end


T = struct2table(rows);
outCsv = fullfile(simDir, outCsvName);
writetable(T, outCsv);

fprintf('\n[encounter-summary] Wrote %d encounter rows\n', height(T));
fprintf('[encounter-summary] CSV: %s\n\n', outCsv);

function row = summarize_encounter(enc, encounterId)
ownIdx = 1;
intIdx = 2;

ownHeadingDeg = wrap_to_360(rad2deg_safe(enc.heading_rad(ownIdx)));
intHeadingDeg = wrap_to_360(rad2deg_safe(enc.heading_rad(intIdx)));
ownPitchDeg = rad2deg_safe(enc.pitch_rad(ownIdx));
intPitchDeg = rad2deg_safe(enc.pitch_rad(intIdx));
ownBankDeg = rad2deg_safe(enc.bank_rad(ownIdx));
intBankDeg = rad2deg_safe(enc.bank_rad(intIdx));

ownN = enc.n_ft(ownIdx);
ownE = enc.e_ft(ownIdx);
ownH = enc.h_ft(ownIdx);
intN = enc.n_ft(intIdx);
intE = enc.e_ft(intIdx);
intH = enc.h_ft(intIdx);

relN = intN - ownN;
relE = intE - ownE;
relH = intH - ownH;

initialHsepFt = hypot(relN, relE);
initialVsepFt = abs(relH);
initialSlantSepFt = hypot(initialHsepFt, initialVsepFt);

losBearingDeg = wrap_to_360(atan2d_safe(relE, relN));
relativeBearingDeg = wrap_to_180(losBearingDeg - ownHeadingDeg);
crossingAngleDeg = abs(wrap_to_180(intHeadingDeg - ownHeadingDeg));

ownVelNE = [enc.v_ftps(ownIdx) * cos(enc.heading_rad(ownIdx)), ...
            enc.v_ftps(ownIdx) * sin(enc.heading_rad(ownIdx))];
intVelNE = [enc.v_ftps(intIdx) * cos(enc.heading_rad(intIdx)), ...
            enc.v_ftps(intIdx) * sin(enc.heading_rad(intIdx))];
relPos = [relN, relE];
relVel = intVelNE - ownVelNE;

[closingSpeedFtps, tcpa_s, dcpa_ft] = compute_relative_geometry(relPos, relVel);

ownUpdates = enc.updates(ownIdx);
intUpdates = enc.updates(intIdx);

row = empty_row();
row.encounter_id = encounterId;
row.run_time_s = enc.runTime_s;

row.own_v_ftps = enc.v_ftps(ownIdx);
row.int_v_ftps = enc.v_ftps(intIdx);
row.own_heading_deg = ownHeadingDeg;
row.int_heading_deg = intHeadingDeg;
row.own_pitch_deg = ownPitchDeg;
row.int_pitch_deg = intPitchDeg;
row.own_bank_deg = ownBankDeg;
row.int_bank_deg = intBankDeg;
row.own_accel_ftpss = enc.a_ftpss(ownIdx);
row.int_accel_ftpss = enc.a_ftpss(intIdx);

row.own_n_ft = ownN;
row.own_e_ft = ownE;
row.own_h_ft = ownH;
row.int_n_ft = intN;
row.int_e_ft = intE;
row.int_h_ft = intH;

row.rel_n_ft = relN;
row.rel_e_ft = relE;
row.rel_h_ft = relH;
row.initial_hsep_ft = initialHsepFt;
row.initial_vsep_ft = initialVsepFt;
row.initial_slant_sep_ft = initialSlantSepFt;
row.los_bearing_deg = losBearingDeg;
row.relative_bearing_deg = relativeBearingDeg;
row.crossing_angle_deg = crossingAngleDeg;
row.closing_speed_ftps = closingSpeedFtps;
row.tcpa_s = tcpa_s;
row.dcpa_ft = dcpa_ft;

row.own_num_updates = get_num_updates(ownUpdates);
row.int_num_updates = get_num_updates(intUpdates);
row.own_first_update_s = get_first_value(ownUpdates.time_s);
row.int_first_update_s = get_first_value(intUpdates.time_s);
row.own_first_turn_rate_dps = rad2deg_safe(get_first_nonzero(ownUpdates.turnRate_radps));
row.int_first_turn_rate_dps = rad2deg_safe(get_first_nonzero(intUpdates.turnRate_radps));
row.own_first_vert_rate_fps = get_first_nonzero(ownUpdates.verticalRate_fps);
row.int_first_vert_rate_fps = get_first_nonzero(intUpdates.verticalRate_fps);
row.own_first_long_accel_ftpss = get_first_nonzero(ownUpdates.longitudeAccel_ftpss);
row.int_first_long_accel_ftpss = get_first_nonzero(intUpdates.longitudeAccel_ftpss);
end

function [closingSpeedFtps, tcpa_s, dcpa_ft] = compute_relative_geometry(relPos, relVel)
rangeFt = hypot(relPos(1), relPos(2));
velSq = dot(relVel, relVel);

if rangeFt <= 0
    closingSpeedFtps = NaN;
else
    closingSpeedFtps = -dot(relPos, relVel) / rangeFt;
end

if velSq <= 0
    tcpa_s = NaN;
    dcpa_ft = NaN;
    return;
end

tcpa_s = -dot(relPos, relVel) / velSq;
posAtTcpa = relPos + tcpa_s .* relVel;
dcpa_ft = hypot(posAtTcpa(1), posAtTcpa(2));
end

function n = get_num_updates(updateStruct)
if isfield(updateStruct, 'time_s') && ~isempty(updateStruct.time_s)
    n = numel(updateStruct.time_s);
else
    n = 0;
end
end

function v = get_first_value(x)
if isempty(x)
    v = NaN;
else
    v = x(1);
end
end

function v = get_first_nonzero(x)
if isempty(x)
    v = NaN;
    return;
end
idx = find(abs(x) > 0, 1, 'first');
if isempty(idx)
    v = 0;
else
    v = x(idx);
end
end

function deg = rad2deg_safe(rad)
deg = rad .* (180 / pi);
end

function ang = wrap_to_360(ang)
ang = mod(ang, 360);
if ang < 0
    ang = ang + 360;
end
end

function ang = wrap_to_180(ang)
ang = mod(ang + 180, 360) - 180;
end

function ang = atan2d_safe(y, x)
ang = atan2(y, x) .* (180 / pi);
end

function encounterFile = resolve_encounter_file(encounterFileIn)
encounterFile = '';

if ~isempty(encounterFileIn)
    if exist(encounterFileIn, 'file') == 2
        encounterFile = encounterFileIn;
        return;
    end
    warning('Requested encounterFile not found: %s', encounterFileIn);
end

byWhich = which('unitTestEncounters.mat');
if ~isempty(byWhich) && exist(byWhich, 'file') == 2
    encounterFile = byWhich;
    return;
end

degasHome = getenv('DEGAS_HOME');
if ~isempty(degasHome)
    candidates = { ...
        fullfile(degasHome, 'block_libraries', 'basic_libraries', 'unitTestUtilities', 'Encounters', 'unitTestEncounters.mat'), ...
        fullfile(fileparts(degasHome), 'code', 'block_libraries', 'basic_libraries', 'unitTestUtilities', 'Encounters', 'unitTestEncounters.mat') ...
    };

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file') == 2
            encounterFile = candidates{i};
            return;
        end
    end
end
end

function row = empty_row()
row = struct();
row.encounter_id = NaN;
row.run_time_s = NaN;

row.own_v_ftps = NaN;
row.int_v_ftps = NaN;
row.own_heading_deg = NaN;
row.int_heading_deg = NaN;
row.own_pitch_deg = NaN;
row.int_pitch_deg = NaN;
row.own_bank_deg = NaN;
row.int_bank_deg = NaN;
row.own_accel_ftpss = NaN;
row.int_accel_ftpss = NaN;

row.own_n_ft = NaN;
row.own_e_ft = NaN;
row.own_h_ft = NaN;
row.int_n_ft = NaN;
row.int_e_ft = NaN;
row.int_h_ft = NaN;

row.rel_n_ft = NaN;
row.rel_e_ft = NaN;
row.rel_h_ft = NaN;
row.initial_hsep_ft = NaN;
row.initial_vsep_ft = NaN;
row.initial_slant_sep_ft = NaN;
row.los_bearing_deg = NaN;
row.relative_bearing_deg = NaN;
row.crossing_angle_deg = NaN;
row.closing_speed_ftps = NaN;
row.tcpa_s = NaN;
row.dcpa_ft = NaN;

row.own_num_updates = NaN;
row.int_num_updates = NaN;
row.own_first_update_s = NaN;
row.int_first_update_s = NaN;
row.own_first_turn_rate_dps = NaN;
row.int_first_turn_rate_dps = NaN;
row.own_first_vert_rate_fps = NaN;
row.int_first_vert_rate_fps = NaN;
row.own_first_long_accel_ftpss = NaN;
row.int_first_long_accel_ftpss = NaN;
end
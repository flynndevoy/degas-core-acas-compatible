function outputJson = EXPORT_DEGAS_MOTION_CALIBRATION(varargin)
% Export motion-calibration parameters from DEGAS Nominal encounter data.
%
% This file is intended to be consumed by the Python ACAS VI trainer so
% transition dynamics are calibrated from DEGAS-core encounter data.
%
% Usage:
%   EXPORT_DEGAS_MOTION_CALIBRATION
%   EXPORT_DEGAS_MOTION_CALIBRATION('outputJson', '/path/to/degas_motion_calibration.json')

p = inputParser;
addParameter(p, 'encounterFile', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'outputJson', '/home/flynn/projects/working_model/horizontal_logic_compact/data/policy/degas_motion_calibration.json', @(x) ischar(x) || isstring(x));
addParameter(p, 'dtSeconds', 5.0, @isnumeric);
addParameter(p, 'turnRateDegPerSec', 3.0, @isnumeric);
addParameter(p, 'turnResponseAlpha', 0.55, @isnumeric);
addParameter(p, 'cocDamping', 0.90, @isnumeric);
addParameter(p, 'minRelRateFtps', 40.0, @isnumeric);
addParameter(p, 'maxRelRateFtps', 220.0, @isnumeric);
parse(p, varargin{:});

encounterFile = resolve_encounter_file(char(p.Results.encounterFile));
outputJson = char(p.Results.outputJson);

dtSeconds = double(p.Results.dtSeconds);
turnRateDegPerSec = double(p.Results.turnRateDegPerSec);
turnResponseAlpha = double(p.Results.turnResponseAlpha);
cocDamping = double(p.Results.cocDamping);
minRelRateFtps = double(p.Results.minRelRateFtps);
maxRelRateFtps = double(p.Results.maxRelRateFtps);

ownSpeedFtps = estimate_nominal_ownship_speed(encounterFile);
maxRelRate = ownSpeedFtps * sind(turnRateDegPerSec * dtSeconds);
maxRelRate = max(minRelRateFtps, min(maxRelRateFtps, maxRelRate));

meta = struct();
meta.source = 'degas-core nominal encounters';
meta.encounter_file = encounterFile;
meta.generated_utc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
meta.estimated_ownship_speed_ftps = ownSpeedFtps;

cal = struct();
cal.dt_seconds = dtSeconds;
cal.turn_rate_deg_per_sec = turnRateDegPerSec;
cal.turn_response_alpha = turnResponseAlpha;
cal.coc_damping = cocDamping;
cal.max_rel_rate_ft_s = maxRelRate;
cal.min_rel_rate_ft_s = minRelRateFtps;
cal.max_rel_rate_cap_ft_s = maxRelRateFtps;

payload = struct();
payload.meta = meta;
payload.calibration = cal;

outDir = fileparts(outputJson);
if ~isempty(outDir) && exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

jsonText = jsonencode(payload);
try
    jsonText = jsonencode(payload, 'PrettyPrint', true);
catch
end

fid = fopen(outputJson, 'w');
if fid < 0
    error('Could not open output JSON for writing: %s', outputJson);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonText, 'char');

fprintf('Wrote DEGAS motion calibration: %s\n', outputJson);
fprintf('  ownSpeedFtps=%.2f\n', ownSpeedFtps);
fprintf('  maxRelRateFtps=%.2f\n', maxRelRate);
end

function ownSpeedFtps = estimate_nominal_ownship_speed(encounterFile)
ownSpeedFtps = 420.0;

if isempty(encounterFile) || exist(encounterFile, 'file') ~= 2
    warning('Encounter file unavailable. Using fallback ownSpeedFtps=%.1f', ownSpeedFtps);
    return;
end

S = load(encounterFile, 'samples');
if ~isfield(S, 'samples') || isempty(S.samples)
    warning('No ''samples'' variable in %s. Using fallback ownSpeedFtps=%.1f', encounterFile, ownSpeedFtps);
    return;
end

try
    v = arrayfun(@(x) x.v_ftps(1), S.samples);
    v = v(isfinite(v) & v > 0);
    if ~isempty(v)
        ownSpeedFtps = median(v);
    end
catch
    warning('Failed to parse ownship speed from %s. Using fallback ownSpeedFtps=%.1f', encounterFile, ownSpeedFtps);
end
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

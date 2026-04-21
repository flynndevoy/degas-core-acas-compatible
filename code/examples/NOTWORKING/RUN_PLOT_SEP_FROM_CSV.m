% RUN_PLOT_SEP_FROM_CSV
% Plot ownship-intruder separation from DAIDALUS and ACAS CSV outputs.

% -------------------- User settings --------------------
daidalusCsv = '/home/flynn/projects/matlab2018/degas-core/code/examples/DAAEncounter/comparison_output/sep_daidalus_20260413_171208.csv';
acasCsv     = '/home/flynn/projects/matlab2018/degas-core/code/examples/DAAEncounter/comparison_output/sep_acas_20260414_122210.csv';

encounterIds = []; % leave empty to plot all encounters in the CSVs
plotType = 'all'; % 'slant' or 'all'
saveFig = false;
% -------------------------------------------------------

if isempty(daidalusCsv) && isempty(acasCsv)
    error('Set daidalusCsv and/or acasCsv before running.');
end

if ~isempty(daidalusCsv) && exist(daidalusCsv, 'file') ~= 2
    error('DAIDALUS CSV not found: %s', daidalusCsv);
end
if ~isempty(acasCsv) && exist(acasCsv, 'file') ~= 2
    error('ACAS CSV not found: %s', acasCsv);
end

T_d = table();
T_a = table();
if ~isempty(daidalusCsv)
    T_d = readtable(daidalusCsv);
end
if ~isempty(acasCsv)
    T_a = readtable(acasCsv);
end

if isempty(encounterIds)
    ids = [];
    if ~isempty(T_d)
        ids = [ids; unique(T_d.encounter)];
    end
    if ~isempty(T_a)
        ids = [ids; unique(T_a.encounter)];
    end
    encounterIds = unique(ids);
end

if isempty(encounterIds)
    error('No encounters found in the provided CSVs.');
end

% Output directory based on current script location
simDir = fileparts(which(mfilename));
outDir = fullfile(simDir, 'comparison_output');
if exist(outDir, 'dir') ~= 7
    mkdir(outDir);
end

for i = 1:numel(encounterIds)
    encNum = encounterIds(i);
    td = table();
    ta = table();
    if ~isempty(T_d)
        td = T_d(T_d.encounter == encNum, :);
    end
    if ~isempty(T_a)
        ta = T_a(T_a.encounter == encNum, :);
    end

    if isempty(td) && isempty(ta)
        continue;
    end

    fig = figure('Name', sprintf('encounter_%d', encNum));

    switch lower(plotType)
        case 'all'
            subplot(3,1,1);
            plot_sep_overlay(td, ta, 'hsep_ft');
            ylabel('Horiz sep (ft)');
            title(sprintf('Encounter %d', encNum));

            subplot(3,1,2);
            plot_sep_overlay(td, ta, 'vsep_ft');
            ylabel('Vert sep (ft)');

            subplot(3,1,3);
            plot_sep_overlay(td, ta, 'ssep_ft');
            ylabel('Slant sep (ft)');
            xlabel('Time (s)');

        otherwise
            plot_sep_overlay(td, ta, 'ssep_ft');
            ylabel('Slant sep (ft)');
            xlabel('Time (s)');
            title(sprintf('Encounter %d', encNum));
    end

    legend('Location','best');
    grid on;

    if saveFig
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        figName = sprintf('sep_plot_%s_enc%03d_%s.png', lower(plotType), encNum, ts);
        saveas(fig, fullfile(outDir, figName));
    end
end

fprintf('Done.\n');

%% ---------------- Local helpers ----------------
function plot_sep_overlay(td, ta, field)
cla;
hold on;
if ~isempty(td)
    plot(td.time_s, td.(field), 'b-', 'DisplayName', 'daidalus');
end
if ~isempty(ta)
    plot(ta.time_s, ta.(field), 'r-', 'DisplayName', 'acas');
end
hold off;
end
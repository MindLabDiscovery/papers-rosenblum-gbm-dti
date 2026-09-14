% Tumor Volume Heatmap — Cohort Overview
masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled_v2.xlsx';
outDir     = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Heat_Maps/';


binEdges  = [0, 20, 60, Inf];
binLabels = {'Small  (<20 cm³)', 'Medium  (20–60 cm³)', 'Large  (>60 cm³)'};
nBins     = numel(binLabels);

if ~exist(outDir, 'dir'), mkdir(outDir); end


fprintf('Reading Clinical sheet...\n');
raw = readcell(masterFile, 'Sheet', 'Clinical');

% Find header row
headers = raw(1,:);
idCol  = find(cellfun(@(h) ischar(h) && contains(lower(char(h)), 'patient'), headers), 1);
volCol = find(cellfun(@(h) ischar(h) && contains(lower(char(h)), 'volume'),  headers), 1);

if isempty(idCol),  error('Cannot find Patient ID column.'); end
if isempty(volCol), error('Cannot find Tumor Volume column.'); end
fprintf('ID column: %s  |  Volume column: %s\n', headers{idCol}, headers{volCol});

dataRows  = raw(2:end, :);
nSubjects = size(dataRows, 1);
patIDs    = cell(nSubjects, 1);
volumes   = NaN(nSubjects, 1);

for s = 1:nSubjects
    % Patient ID
    pid = dataRows{s, idCol};
    if ischar(pid) || isstring(pid)
        pid = char(pid);
        if startsWith(pid, '='), pid = sprintf('PT_%02d', s); end
        patIDs{s} = pid;
    else
        patIDs{s} = sprintf('PT_%02d', s);
    end

    % Volume
    v = dataRows{s, volCol};
    if isnumeric(v) && ~isnan(v) && v > 0
        volumes(s) = v;
    end
end


binIdx = zeros(nSubjects, 1);
for s = 1:nSubjects
    for b = 1:nBins
        if volumes(s) >= binEdges(b) && volumes(s) < binEdges(b+1)
            binIdx(s) = b;
            break;
        end
    end
end

% Sort subjects: first by bin
[~, sortOrder] = sortrows([binIdx, volumes]);
patIDs_sorted  = patIDs(sortOrder);
binIdx_sorted  = binIdx(sortOrder);

% Build presence matrix (1 = patient in this bin)
dataMatrix = NaN(nBins, nSubjects);
for s = 1:nSubjects
    b = binIdx_sorted(s);
    if b > 0
        dataMatrix(b, s) = 1;
    end
end


fig = figure('Position', [50 50 1600 320], 'Color', 'w');
ax  = axes('Parent', fig);
im  = imagesc(ax, dataMatrix);

set(im, 'AlphaData', ~isnan(dataMatrix));
set(ax, 'Color', [0.88 0.88 0.88]);

colormap(ax, [0.18 0.45 0.70]);
clim(ax, [0.9 1.1]);

set(ax, ...
    'YTick',               1:nBins, ...
    'YTickLabel',          binLabels, ...
    'XTick',               1:nSubjects, ...
    'XTickLabel',          patIDs_sorted, ...
    'XTickLabelRotation',  90, ...
    'FontSize',            8, ...
    'TickLength',          [0 0], ...
    'Box',                 'on', ...
    'XColor',              'k', ...
    'YColor',              'k', ...
    'TickLabelInterpreter','none');

xlabel(ax, 'Subject',       'FontSize', 12, 'Color', 'k', 'FontWeight', 'bold');
ylabel(ax, 'Tumor Volume',  'FontSize', 12, 'Color', 'k', 'FontWeight', 'bold');
title(ax, sprintf('Tumor Volume by Subject  |  %d Patients', nSubjects), ...
    'FontSize', 13, 'Color', 'k', 'FontWeight', 'bold');

% Grid lines
hold(ax, 'on');
for b = 0.5:1:(nBins + 0.5)
    plot(ax, [0.5, nSubjects+0.5], [b b], 'k-', 'LineWidth', 0.3);
end
for s = 0.5:1:(nSubjects + 0.5)
    plot(ax, [s s], [0.5, nBins+0.5], 'k-', 'LineWidth', 0.3);
end

% Thick dividers 
groupBounds = find(diff(binIdx_sorted) ~= 0);
for b = groupBounds'
    plot(ax, [b+0.5 b+0.5], [0.5, nBins+0.5], 'k-', 'LineWidth', 2.0);
end
hold(ax, 'off');


outFile = fullfile(outDir, 'Heatmap_TumorVolume_Cohort.png');
exportgraphics(fig, outFile, 'Resolution', 300, 'BackgroundColor', 'white');
fprintf('Saved: %s\n', outFile);

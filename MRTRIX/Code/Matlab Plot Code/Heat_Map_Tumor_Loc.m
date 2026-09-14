
% Tumor Location Heatmap — Cohort Overview
masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled_v2.xlsx';
outDir     = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Heat_Maps/';

if ~exist(outDir, 'dir'), mkdir(outDir); end

fprintf('Reading Master sheet...\n');
Tm = readtable(masterFile, 'Sheet', 'Master', 'VariableNamingRule', 'preserve');

nSubjects = height(Tm);
patIDs    = cell(nSubjects, 1);
tumorLocs = cell(nSubjects, 1);

for s = 1:nSubjects
    % Patient ID
    raw = char(Tm.Patient_ID{s});
    if startsWith(raw, '=')
        patIDs{s} = sprintf('PT_%02d', s);
    else
        patIDs{s} = raw;
    end

    % Tumor Location 
    loc = strtrim(char(Tm.("Tumor Location"){s}));
    switch loc
        case 'Fronal',  loc = 'Frontal';
        case '?',       loc = 'Unknown';
    end
    tumorLocs{s} = loc;
end


preferredOrder = {'Frontal','Parietal','Temporal','Occipital', ...
                  'Frontoparietal','Fronto-Temporal','Temporoparietal', ...
                  'Temporo-Occipital','Temporo-insular','Parieto-Occipital', ...
                  'Thalamus','Cerebellar','Unknown'};

uniqueLocs  = unique(tumorLocs);
orderedLocs = {};
for k = 1:numel(preferredOrder)
    if any(strcmpi(uniqueLocs, preferredOrder{k}))
        orderedLocs{end+1} = preferredOrder{k}; 
    end
end
extras = setdiff(uniqueLocs, orderedLocs);
orderedLocs = [orderedLocs, extras(:)'];
nLocs = numel(orderedLocs);

% Assign each subject a location index
locIdx = zeros(nSubjects, 1);
for s = 1:nSubjects
    for l = 1:nLocs
        if strcmpi(tumorLocs{s}, orderedLocs{l})
            locIdx(s) = l;
            break;
        end
    end
end

% Sort subjects by location 
[~, sortOrder]  = sort(locIdx);
patIDs_sorted   = patIDs(sortOrder);
locIdx_sorted   = locIdx(sortOrder);

% Build presence matrix (1 = tumor here, NaN = not here)
dataMatrix = NaN(nLocs, nSubjects);
for s = 1:nSubjects
    l = locIdx_sorted(s);
    if l > 0
        dataMatrix(l, s) = 1;
    end
end

% Plot
fig = figure('Position', [50 50 1600 380], 'Color', 'w');
ax  = axes('Parent', fig);
im  = imagesc(ax, dataMatrix);

set(im, 'AlphaData', ~isnan(dataMatrix));
set(ax, 'Color', [0.88 0.88 0.88]);   

colormap(ax, [0.18 0.45 0.70]);      
clim(ax, [0.9 1.1]);                 

set(ax, ...
    'YTick',               1:nLocs, ...
    'YTickLabel',          orderedLocs, ...
    'XTick',               1:nSubjects, ...
    'XTickLabel',          patIDs_sorted, ...
    'XTickLabelRotation',  90, ...
    'FontSize',            8, ...
    'TickLength',          [0 0], ...
    'Box',                 'on', ...
    'XColor',              'k', ...
    'YColor',              'k', ...
    'TickLabelInterpreter','none');

xlabel(ax, 'Subject',        'FontSize', 12, 'Color', 'k', 'FontWeight', 'bold');
ylabel(ax, 'Tumor Location', 'FontSize', 12, 'Color', 'k', 'FontWeight', 'bold');
title(ax, sprintf('Tumor Location by Subject  |  %d Patients', nSubjects), ...
    'FontSize', 13, 'Color', 'k', 'FontWeight', 'bold');

% Grid lines
hold(ax, 'on');
for l = 0.5:1:(nLocs + 0.5)
    plot(ax, [0.5, nSubjects+0.5], [l l], 'k-', 'LineWidth', 0.3);
end
for s = 0.5:1:(nSubjects + 0.5)
    plot(ax, [s s], [0.5, nLocs+0.5], 'k-', 'LineWidth', 0.3);
end

% Thick dividers 
groupBounds = find(diff(locIdx_sorted) ~= 0);
for b = groupBounds'
    plot(ax, [b+0.5 b+0.5], [0.5, nLocs+0.5], 'k-', 'LineWidth', 2.0);
end
hold(ax, 'off');


outFile = fullfile(outDir, 'Heatmap_TumorLocation_Cohort.png');
exportgraphics(fig, outFile, 'Resolution', 300, 'BackgroundColor', 'white');
fprintf('Saved: %s\n', outFile);

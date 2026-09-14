% FA Heatmap: Tracts (Y) × Subjects (X)

masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled_v2.xlsx';
outDir     = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Heat_Maps/';

valueType  = 'Asymmetry';  % 'Ipsilateral' | 'Contralateral' | 'Left' | 'Right' | 'Asymmetry'
metric     = 'RD';


if ~exist(outDir, 'dir'), mkdir(outDir); end

T = readtable(masterFile, 'Sheet', metric, 'VariableNamingRule', 'preserve');

tracts = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF', ...
          'OR','POPT','SCP','SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC', ...
          'ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM','STR', ...
          'T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

nTracts   = numel(tracts);
nSubjects = height(T);

patIDs = cell(nSubjects, 1);
for s = 1:nSubjects
    raw = T.Patient_ID{s};
    if startsWith(raw, '=')
        patIDs{s} = sprintf('PT_%02d', s);
    else
        patIDs{s} = raw;
    end
end

tumor_side = T.Tumor_Side;
for s = 1:nSubjects
    ts = tumor_side{s};
    if startsWith(ts, '=')
        tumor_side{s} = '';
    end
end

dataMatrix = NaN(nTracts, nSubjects);

for t = 1:nTracts
    leftCol  = [tracts{t} ' Left'];
    rightCol = [tracts{t} ' Right'];
    asymCol  = [tracts{t} ' Asymmetry'];
    varNames = T.Properties.VariableNames;

    for s = 1:nSubjects
        side = tumor_side{s};

        switch valueType
            case 'Left',          col = leftCol;
            case 'Right',         col = rightCol;
            case 'Asymmetry',     col = asymCol;
            case 'Ipsilateral'
                if strcmpi(side,'R'),     col = rightCol;
                elseif strcmpi(side,'L'), col = leftCol;
                else,                     col = ''; end
            case 'Contralateral'
                if strcmpi(side,'R'),     col = leftCol;
                elseif strcmpi(side,'L'), col = rightCol;
                else,                     col = ''; end
        end

        if ~isempty(col) && ismember(col, varNames)
            val = T.(col)(s);
            if isnumeric(val) && ~isnan(val)
                dataMatrix(t,s) = val;
            end
        end
    end
end

fig = figure('Position', [50 50 1500 650], 'Color', 'w');
ax  = axes('Parent', fig);
im  = imagesc(ax, dataMatrix);

set(im, 'AlphaData', ~isnan(dataMatrix));
set(ax, 'Color', [0.78 0.78 0.78]);

colormap(ax, parula);
clim_vals = [nanmin(dataMatrix(:)), nanmax(dataMatrix(:))];
if diff(clim_vals) > 0, clim(ax, clim_vals); end

cb = colorbar(ax);
cb.Label.String = sprintf('%s (%s)', metric, valueType);
cb.Label.FontSize = 11;
cb.FontSize = 9;
cb.Color = 'k';

set(ax, ...
    'YTick',              1:nTracts, ...
    'YTickLabel',         tracts, ...
    'XTick',              1:nSubjects, ...
    'XTickLabel',         patIDs, ...
    'XTickLabelRotation', 90, ...
    'FontSize',           8, ...
    'TickLength',         [0 0], ...
    'Box',                'on', ...
    'XColor',             'k', ...
    'YColor',             'k', ...
    'TickLabelInterpreter','none');   

xlabel(ax, 'Subject',  'FontSize', 12, 'Color', 'k', 'FontWeight', 'bold');
ylabel(ax, 'Tract',    'FontSize', 12, 'FontWeight', 'bold', 'Color', 'k');
title(ax, sprintf('%s Heatmap — %s\n(31 Tracts × %d Subjects)', metric, valueType, nSubjects), ...
    'FontSize', 13, 'Color', 'k', 'FontWeight', 'bold');

hold(ax, 'on');
for t = 0.5:1:(nTracts+0.5)
    plot(ax, [0.5, nSubjects+0.5], [t t], 'k-', 'LineWidth', 0.3);
end
for s = 0.5:1:(nSubjects+0.5)
    plot(ax, [s s], [0.5, nTracts+0.5], 'k-', 'LineWidth', 0.3);
end
hold(ax, 'off');

outFile = fullfile(outDir, sprintf('Heatmap_%s_%s.png', metric, valueType));
exportgraphics(fig, outFile, 'Resolution', 300, 'BackgroundColor', 'white');
fprintf('Saved: %s\n', outFile);
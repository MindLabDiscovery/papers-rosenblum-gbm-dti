% Sorted Bar Plot

metric_names = {'FA', 'MD', 'AD', 'RD'};
col_assoc = [0.2 0.4 0.8];
col_proj  = [0.9 0.4 0.2];
col_comm  = [0.4 0.75 0.4];


master_file = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
out_dir     = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Sorted_Bar_Plot_V3';

categories = containers.Map( ...
    {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP', ...
    'SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC', ...
    'ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'}, ...
    {'Association','Projection','Association','Projection','Projection','Commissural','Projection', ...
    'Association','Association','Association','Association','Projection','Projection', ...
    'Association','Association','Association','Projection','Projection','Projection','Projection','Projection', ...
    'Projection','Projection','Projection','Projection','Projection','Projection','Projection','Projection','Projection','Association'});

tract_names = categories.keys();

for m = 1:4
    data = readtable(master_file, 'Sheet', metric_names{m}, 'VariableNamingRule', 'preserve');
    n = height(data);

    mean_diffs = zeros(length(tract_names), 1);
    for t = 1:length(tract_names)
        tract = tract_names{t};
        left_col  = [tract ' Left'];
        right_col = [tract ' Right'];
        diffs = zeros(n, 1);
        for p = 1:n
            side = strtrim(data.Tumor_Side{p});
            lv = data.(left_col)(p);
            rv = data.(right_col)(p);
            if strcmp(side, 'R')
                diffs(p) = lv - rv;  
            else
                diffs(p) = rv - lv;   
            end
        end
        mean_diffs(t) = mean(diffs, 'omitnan');
    end

    % Sort descending
    [sorted_vals, idx] = sort(mean_diffs, 'descend');
    sorted_tracts = tract_names(idx);
    sorted_cats   = cellfun(@(t) categories(t), sorted_tracts, 'UniformOutput', false);

    colors = zeros(length(sorted_vals), 3);
    for i = 1:length(sorted_vals)
        switch sorted_cats{i}
            case 'Association', colors(i,:) = col_assoc;
            case 'Projection',  colors(i,:) = col_proj;
            case 'Commissural', colors(i,:) = col_comm;
        end
    end

    figure;
    b = bar(sorted_vals, 'FaceColor', 'flat');
    b.CData = colors;
    set(gca, 'XTick', 1:length(sorted_vals), 'XTickLabel', sorted_tracts, ...
        'XTickLabelRotation', 45, 'FontSize', 9);
    ylabel('Mean Difference (Contra - Ipsi)');
    title([metric_names{m} ' Contralateral - Ipsilateral by Tract (n=' num2str(n) ')']);
    yline(0, 'k--');
    hold on;
    h1 = patch(nan, nan, col_assoc);
    h2 = patch(nan, nan, col_proj);
    h3 = patch(nan, nan, col_comm);
    legend([h1 h2 h3], {'Association','Projection','Commissural'}, 'Location', 'northeast');
    saveas(gcf, fullfile(out_dir, ['ranked_bar_' metric_names{m} '.png']));
end
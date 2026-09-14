%Sorted Bar Plot

metric_names = {'FA', 'MD', 'AD', 'RD'};

col_assoc = [0.2 0.4 0.8];
col_proj  = [0.9 0.4 0.2];
col_comm  = [0.4 0.75 0.4];

for m = 1:4
    data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Mean_Difference_Per_Metric.xlsx', ...
        'Sheet', metric_names{m});

    tracts   = data.Tract;
    vals     = data.Mean_Diff;
    category = data.Category;

    colors = zeros(length(vals), 3);
    for i = 1:length(vals)
        switch category{i}
            case 'Association', colors(i,:) = col_assoc;
            case 'Projection',  colors(i,:) = col_proj;
            case 'Commissural', colors(i,:) = col_comm;
        end
    end

    figure;
    b = bar(vals, 'FaceColor', 'flat');
    b.CData = colors;
    set(gca, 'XTick', 1:length(vals), 'XTickLabel', tracts, 'XTickLabelRotation', 45, 'FontSize', 9);
    ylabel('Mean Difference (Contra - Ipsi)');
    title([metric_names{m} ' Asymmetry by Tract']);
    yline(0, 'k--');
    hold on;
    h1 = patch(nan, nan, col_assoc);
    h2 = patch(nan, nan, col_proj);
    h3 = patch(nan, nan, col_comm);
    legend([h1 h2 h3], {'Association','Projection','Commissural'}, 'Location', 'northeast');
    saveas(gcf, ['/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats/ranked_bar_' metric_names{m} '.png']);
end
% T-test FA,MD,RD,AD for ALL TRACTS

folderpath = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT TRACT STATS/Plotted Stats';
data = dir(fullfile(folderpath, '*.csv'));
tum_loc = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT TRACT STATS/Plotted Stats/PT_ID_AND_Tumor_Location.xlsx';
master = readtable(tum_loc);

tracts = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP','SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

for i = 1:length(data)
    T = readtable(fullfile(folderpath, data(i).name)); 
    tumorLocation = master{strcmp(strtrim(master.Patient_ID), data(i).name(1:end-4)), 'Tumor_Side'};

    for p = 1:length(tracts)
        try
            if strcmp(tumorLocation, 'right')
                FA_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_FA'};
                FA_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_FA'};
                MD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_MD'};
                MD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_MD'};
                AD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_AD'};
                AD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_AD'};
                RD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_RD'};
                RD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_RD'};
            else
                FA_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_FA'};
                FA_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_FA'};
                MD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_MD'};
                MD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_MD'};
                AD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_AD'};
                AD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_AD'};
                RD_IPS(i,p)  = T{strcmp(T.tract, [tracts{p}, '_left']),  'mean_RD'};
                RD_CONT(i,p) = T{strcmp(T.tract, [tracts{p}, '_right']), 'mean_RD'};
            end
        catch
            FA_IPS(i,p) = NaN; FA_CONT(i,p) = NaN;
            MD_IPS(i,p) = NaN; MD_CONT(i,p) = NaN;
            AD_IPS(i,p) = NaN; AD_CONT(i,p) = NaN;
            RD_IPS(i,p) = NaN; RD_CONT(i,p) = NaN;
        end
    end
end

% T-test 
for t = 1:length(tracts)
    fa = FA_CONT(:,t) - FA_IPS(:,t); fa = fa(~isnan(fa));
    md = MD_CONT(:,t) - MD_IPS(:,t); md = md(~isnan(md));
    ad = AD_CONT(:,t) - AD_IPS(:,t); ad = ad(~isnan(ad));
    rd = RD_CONT(:,t) - RD_IPS(:,t); rd = rd(~isnan(rd));

    [~, p_FA(t)] = ttest(fa);
    [~, p_MD(t)] = ttest(md);
    [~, p_AD(t)] = ttest(ad);
    [~, p_RD(t)] = ttest(rd);
end

figure;
histogram(FA_CONT(:, 4) - FA_IPS(:, 4), 'NumBins', 20);
xlabel('Contra - Ipsi FA');
title('CST FA Difference Distribution');

results = table(tracts', p_FA', p_MD', p_AD', p_RD', 'VariableNames', {'Tract', 'p_FA', 'p_MD', 'p_AD', 'p_RD'});
writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT TRACT STATS/Plotted Stats/T-Test_results.csv');


%%

% Ranked bar plots
association = {'AF','CG','FX','IFO','ILF','MLF','OR','SLF_I','SLF_II','SLF_III', ...
    'ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM', ...
    'T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

mean_FA = mean(FA_CONT - FA_IPS, 1, 'omitnan');
mean_MD = mean(MD_CONT - MD_IPS, 1, 'omitnan');
mean_AD = mean(AD_CONT - AD_IPS, 1, 'omitnan');
mean_RD = mean(RD_CONT - RD_IPS, 1, 'omitnan');

all_means = [mean_FA; mean_MD; mean_AD; mean_RD];
metric_names = {'FA', 'MD', 'AD', 'RD'};

for m = 1:4
    [sorted_vals, idx] = sort(all_means(m,:), 'descend');
    sorted_tracts = tracts(idx);

    is_association = ismember(sorted_tracts, association);
    colors = repmat([0.9 0.4 0.2], length(tracts), 1);
    colors(is_association, :) = repmat([0.2 0.4 0.8], sum(is_association), 1);

    figure;
    b = bar(sorted_vals, 'FaceColor', 'flat', 'HandleVisibility', 'off');
    b.CData = colors;
    set(gca, 'XTick', 1:length(tracts), 'XTickLabel', sorted_tracts, 'XTickLabelRotation', 45, 'FontSize', 9);
    ylabel(['Mean Difference (Contra - Ipsi) ' metric_names{m}]);
    title([metric_names{m} ' Asymmetry by Tract']);
    yline(0, 'k--');
    hold on;
    h1 = plot(nan, nan, 's', 'MarkerFaceColor', [0.2 0.4 0.8], 'MarkerEdgeColor', 'none');
    h2 = plot(nan, nan, 's', 'MarkerFaceColor', [0.9 0.4 0.2], 'MarkerEdgeColor', 'none');
    legend([h1 h2], {'Association', 'Projection'}, 'Location', 'best');
    saveas(gcf, ['/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT TRACT STATS/Plotted Stats/ranked_bar_' metric_names{m} '.png']);
end
%% CST Wilcoxon Sign Rank Plot
master = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V1/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';

fa_contra = NaN(height(master), 1); fa_ips = NaN(height(master), 1);
md_contra = NaN(height(master), 1); md_ips = NaN(height(master), 1);
ad_contra = NaN(height(master), 1); ad_ips = NaN(height(master), 1);
rd_contra = NaN(height(master), 1); rd_ips = NaN(height(master), 1);

for p = 1:height(master)
    pid  = char(master.Patient_ID(p));
    side = lower(char(master.Tumor_Side(p)));
    f    = fullfile(csv_dir, [pid '.csv']);
    if ~isfile(f), warning('%s not found', pid); continue; 
    end

    T = readtable(f, 'TextType', 'string');
    T.Properties.RowNames = cellstr(T.tract);

    if strcmp(side, 'right')
        ipsi_tract   = 'CST_right';
        contra_tract = 'CST_left';
    else
        ipsi_tract   = 'CST_left';
        contra_tract = 'CST_right';
    end

    fa_ips(p)    = T{ipsi_tract,  'mean_FA'};
    fa_contra(p) = T{contra_tract, 'mean_FA'};
    md_ips(p)    = T{ipsi_tract,  'mean_MD'};
    md_contra(p) = T{contra_tract, 'mean_MD'};
    ad_ips(p)    = T{ipsi_tract,  'mean_AD'};
    ad_contra(p) = T{contra_tract, 'mean_AD'};
    rd_ips(p)    = T{ipsi_tract,  'mean_RD'};
    rd_contra(p) = T{contra_tract, 'mean_RD'};
end


metrics      = {'FA', 'MD', 'AD', 'RD'};
contra_data  = {fa_contra, md_contra, ad_contra, rd_contra};
ipsi_data    = {fa_ips,    md_ips,    ad_ips,    rd_ips};

for m = 1:4
    c = contra_data{m};
    i = ipsi_data{m};

  
    mask = ~(isnan(c) | isnan(i));
    c = c(mask); i = i(mask);

   
    [p_val, ~] = signrank(c, i);

    
    outlier_mask = isoutlier(c, 'grubbs') | isoutlier(i, 'grubbs');
    c = c(~outlier_mask); i = i(~outlier_mask);

    n = numel(c);
    figure;
    vals  = [c; i];
    group = [ones(n,1); 2*ones(n,1)];
    boxplot(vals, group, 'Labels', {[metrics{m} ' Contralateral'], [metrics{m} ' Ipsilateral']});
    hold on;
    for k = 1:n
        plot([1,2], [c(k), i(k)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
    end
    scatter(ones(n,1),   c, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
    scatter(2*ones(n,1), i, 36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);
    ylabel(metrics{m});
    title(sprintf('Paired %s: Contralateral vs Ipsilateral (Corticospinal Tract)', metrics{m}));
    ylimVals = ylim;
    text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p_val));
    box on; hold off;

    saveas(gcf, sprintf('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Rank_V2/Wilcoxon_CST_%s.png', metrics{m}));
end
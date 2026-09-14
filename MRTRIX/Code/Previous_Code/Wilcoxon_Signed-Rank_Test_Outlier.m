%CST FA Wilcoxon Rank Plot

master = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';

fa_contra = NaN(height(master), 1);
fa_ips    = NaN(height(master), 1);
md_contra = NaN(height(master), 1); md_ips = NaN(height(master), 1);
ad_contra = NaN(height(master), 1); ad_ips = NaN(height(master), 1);
rd_contra = NaN(height(master), 1); rd_ips = NaN(height(master), 1);

for p = 1:height(master)
    pid  = char(master.Patient_ID(p));
    side = lower(char(master.Tumor_Side(p)));
    f    = fullfile(csv_dir, [pid '.csv']);
    if ~isfile(f), warning('%s not found', pid); continue; end

    T = readtable(f, 'TextType', 'string');
    T.Properties.RowNames = cellstr(T.tract);

    if strcmp(side, 'right')
        ipsi_tract  = 'CST_right';
        contra_tract = 'CST_left';
    else
        ipsi_tract  = 'CST_left';
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

%%

%CST MD

data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/CST.xlsx');
md_contra = data.MD_Contra_;
md_ips = data.MD_IPS_;

%Wilcoxon Signed-Rank (CST)
mask = ~(isnan(md_contra) | isnan(md_ips));
md_contra = md_contra(mask);
md_ips = md_ips(mask);
[p, stats] = signrank(md_contra, md_ips);
disp(stats)

%Outlier
outlier_mask = isoutlier(md_contra, 'grubbs') | isoutlier(md_ips, 'grubbs');
md_contra = md_contra(~outlier_mask);
md_ips = md_ips(~outlier_mask);

%Box-Whisker Plot
figure;
n = numel(md_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [md_contra; md_ips];
boxplot(vals, group, 'Labels', {'MD Contralateral', 'MD Ipsilateral'});
hold on;
xContra = ones(n,1);
xIps    = 2*ones(n,1);

for i = 1:n
    plot([1,2], [md_contra(i), md_ips(i)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

scatter(xContra, md_contra, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
scatter(xIps,    md_ips,    36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);

% Labels 
ylabel('MD');
title('Paired MD: Contralateral vs Ipsilateral (Corticospinal Tract)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_CST_MD_Outlier.png');


%%


%CST AD

data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/CST.xlsx');
ad_contra = data.AD_Contra_;
ad_ips = data.AD_Ips_;

%Wilcoxon Signed-Rank (CST)
mask = ~(isnan(ad_contra) | isnan(ad_ips));
ad_contra = ad_contra(mask);
ad_ips = ad_ips(mask);
[p, stats] = signrank(ad_contra, ad_ips);
disp(stats)

%Outlier
outlier_mask = isoutlier(ad_contra, 'grubbs') | isoutlier(ad_ips, 'grubbs');
ad_contra = ad_contra(~outlier_mask);
ad_ips = ad_ips(~outlier_mask);

%Box-Whisker Plot
figure;
n = numel(ad_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [ad_contra; ad_ips];
boxplot(vals, group, 'Labels', {'AD Contralateral', 'AD Ipsilateral'});
hold on;
xContra = ones(n,1);
xIps    = 2*ones(n,1);

for i = 1:n
    plot([1,2], [ad_contra(i), ad_ips(i)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

scatter(xContra, ad_contra, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
scatter(xIps,    ad_ips,    36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);

% Labels 
ylabel('AD');
title('Paired AD: Contralateral vs Ipsilateral (Corticospinal Tract)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_CST_AD_Outlier.png');


%%

%CST RD

data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/CST.xlsx');
rd_contra = data.RD_Contra_;
rd_ips = data.RD_Ips_;

%Wilcoxon Signed-Rank (CST)
mask = ~(isnan(rd_contra) | isnan(rd_ips));
rd_contra = rd_contra(mask);
rd_ips = rd_ips(mask);
[p, stats] = signrank(rd_contra, rd_ips);
disp(stats)

%Outlier
outlier_mask = isoutlier(rd_contra, 'grubbs') | isoutlier(rd_ips, 'grubbs');
rd_contra = rd_contra(~outlier_mask);
rd_ips = rd_ips(~outlier_mask);

%Box-Whisker Plot
figure;
n = numel(rd_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [rd_contra; rd_ips];
boxplot(vals, group, 'Labels', {'RD Contralateral', 'RD Ipsilateral'});
hold on;
xContra = ones(n,1);
xIps    = 2*ones(n,1);

for i = 1:n
    plot([1,2], [rd_contra(i), rd_ips(i)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

scatter(xContra, rd_contra, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
scatter(xIps,    rd_ips,    36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);

% Labels 
ylabel('RD');
title('Paired RD: Contralateral vs Ipsilateral (Corticospinal Tract)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_CST_RD_Outlier.png');


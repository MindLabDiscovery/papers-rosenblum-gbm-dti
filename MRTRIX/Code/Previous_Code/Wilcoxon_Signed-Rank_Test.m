%AF FA

data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/AF_FA.xlsx');
fa_contra = data.FA_Contra_;
fa_ips = data.FA_IPS_;

%Wilcoxon Signed-Rank (AF)
mask = ~(isnan(fa_contra) | isnan(fa_ips));
fa_contra = fa_contra(mask);
fa_ips = fa_ips(mask);
[p, stats] = signrank(fa_contra, fa_ips);
disp(stats)

%Box-Whisker Plot
figure;
n = numel(fa_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [fa_contra; fa_ips];
boxplot(vals, group, 'Labels', {'FA Contralateral', 'FA Ipsalateral'});
hold on;

xContra = ones(n,1); 
xIps    = 2*ones(n,1); 

for i = 1:n
    plot([1,2], [fa_contra(i), fa_ips(i)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

scatter(xContra, fa_contra, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
scatter(xIps,    fa_ips,    36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);

% Labels 
ylabel('FA');
title('Paired FA: Contralateral vs Ipsalateral (Arcuate Fasiculus)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_AF.png');



%%

%CST FA

data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats/CST_FA.xlsx');
fa_contra = data.FA_Contralateral_;
fa_ips = data.FA_Ipsalateral_;

%Wilcoxon Signed-Rank (CST)
mask = ~(isnan(fa_contra) | isnan(fa_ips));
fa_contra = fa_contra(mask);
fa_ips = fa_ips(mask);
[p, stats] = signrank(fa_contra, fa_ips);
disp(stats)

%Box-Whisker Plot
figure;
n = numel(fa_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [fa_contra; fa_ips];
boxplot(vals, group, 'Labels', {'FA Contralateral', 'FA Ipsalateral'});
hold on;
jitterAmount = 0.08;
xContra = ones(n,1);
xIps    = 2*ones(n,1);

for i = 1:n
    plot([1,2], [fa_contra(i), fa_ips(i)], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

scatter(xContra, fa_contra, 36, 'b', 'filled', 'MarkerFaceAlpha', 0.7);
scatter(xIps,    fa_ips,    36, 'r', 'filled', 'MarkerFaceAlpha', 0.7);

% Labels 
ylabel('FA');
title('Paired FA: Contralateral vs Ipsalateral (Corticospinal Tract)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_CST.png');


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

%Box-Whisker Plot
figure;
n = numel(md_contra);
group = [ones(n,1); 2*ones(n,1)];
vals = [md_contra; md_ips];
boxplot(vals, group, 'Labels', {'MD Contralateral', 'MD Ipsalateral'});
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
title('Paired MD: Contralateral vs Ipsalateral (Corticospinal Tract)');
ylimVals = ylim;
text(1.05, ylimVals(2) - 0.05*diff(ylimVals), sprintf('p = %.3g (signrank)', p));
ax = gca;
ax.XGrid = 'off';
ax.YGrid = 'off';
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';


box on;
hold off;
saveas(gcf, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Wilcoxon_Signed_Rank_CST_MD.png');
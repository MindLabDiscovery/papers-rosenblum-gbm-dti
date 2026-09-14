%Tumor Volume vs Survival Lin Reg
data = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_Tumor_Vol_vs_Survival.xlsx');

%Linear Regression
tumor_vol = data.TumorVolume_cm3_;
survival_time = data.Survival_Days_;

figure;
mdl = fitlm(tumor_vol, survival_time);
figure;
plot(mdl)                
xlabel('Tumor Volume (cm^3)');
ylabel('Survival (days)');
title('Tumor Volume vs Survival');
p_value = mdl.Coefficients.pValue(2);      
r2 = mdl.Rsquared.Ordinary;                
r = sign(mdl.Coefficients.Estimate(2))*sqrt(r2); 
txt = sprintf('p_{value}=%.3g, R^2=%.3g, r=%.3g', p_value, r2, r);
xlim = get(gca,'XLim'); ylim = get(gca,'YLim');
text(0.1*(xlim(2)-xlim(1))+xlim(1), 0.9*(ylim(2)-ylim(1))+ylim(1), txt, 'FontSize',10);
saveas(gcf, sprintf('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Tumor_Vol_Surv_V2/Tumor_Vol_VS_Survival.png'));
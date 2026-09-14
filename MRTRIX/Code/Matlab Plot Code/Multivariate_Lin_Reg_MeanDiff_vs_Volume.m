%% Multivariate Linear Regression: Tumor Volume vs DTI Mean Differences
clear;

master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
vol_tbl = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_Tumor_Vol_vs_Survival.xlsx');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';

metrics       = {'mean_FA', 'mean_MD', 'mean_AD', 'mean_RD'};
metric_labels = {'FA', 'MD', 'AD', 'RD'};
n_metrics     = numel(metrics);
n_patients    = height(master);


ref         = readtable(fullfile(csv_dir, [char(master.Patient_ID(1)) '.csv']), 'TextType', 'string');
all_tracts  = ref.tract;
left_tracts = all_tracts(endsWith(all_tracts, '_left'));
base_names  = replace(left_tracts, '_left', '');
base_names  = base_names(arrayfun(@(b) any(all_tracts == b + "_right"), base_names));
n_tracts    = numel(base_names);

% Compute mean difference (Contra - Ipsi) 
meandiff_vals = NaN(n_patients, n_metrics);

for p = 1:n_patients
    pid  = char(master.Patient_ID(p));
    side = lower(char(master.Tumor_Side(p)));
    f    = fullfile(csv_dir, [pid '.csv']);
    if ~isfile(f), warning('%s not found', pid); continue; end
    T = readtable(f, 'TextType', 'string');
    T.Properties.RowNames = cellstr(T.tract);
    if strcmp(side, 'right')
        ipsi_sfx = '_right'; contra_sfx = '_left';
    else
        ipsi_sfx = '_left';  contra_sfx = '_right';
    end
    for m = 1:n_metrics
        diffs = NaN(n_tracts, 1);
        for t = 1:n_tracts
            ipsi_name   = char(base_names(t) + ipsi_sfx);
            contra_name = char(base_names(t) + contra_sfx);
            try
                i = T{ipsi_name,   metrics{m}};
                c = T{contra_name, metrics{m}};
                diffs(t) = c - i;
            catch; end
        end
        meandiff_vals(p, m) = mean(diffs, 'omitnan');
    end
end

% Match tumor volumes to patients
tumor_vol = NaN(n_patients, 1);
for p = 1:n_patients
    pid = char(master.Patient_ID(p));
    idx = strcmp(string(vol_tbl.Patient_ID), pid);
    if any(idx)
        tumor_vol(p) = vol_tbl.TumorVolume_cm3_(idx);
    end
end

% Multivariate regression
X = meandiff_vals;
y = tumor_vol;

mask    = ~any(isnan(X), 2) & ~isnan(y);
X_clean = X(mask, :);
y_clean = y(mask);

fprintf('Patients included in multivariate model: %d\n', sum(mask));

mdl = fitlm(X_clean, y_clean, ...
    'VarNames', {'FA_MeanDiff','MD_MeanDiff','AD_MeanDiff','RD_MeanDiff','TumorVolume'});

disp(mdl);
disp(mdl.Coefficients);

% Save coefficients
coef_tbl = mdl.Coefficients;
coef_tbl.Properties.RowNames = {};
coef_tbl.Predictor = {'Intercept','FA_MeanDiff','MD_MeanDiff','AD_MeanDiff','RD_MeanDiff'}';
coef_tbl = coef_tbl(:, {'Predictor','Estimate','SE','tStat','pValue'});
writetable(coef_tbl, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Multivariate_MeanDiff_vs_Volume.xlsx', ...
    'Sheet', 'Coefficients');

% Save model summary
summary_tbl = table({'R-squared'; 'Adjusted R-squared'; 'Model p-value'; 'N patients'}, ...
    [mdl.Rsquared.Ordinary; mdl.Rsquared.Adjusted; coefTest(mdl); sum(mask)], ...
    'VariableNames', {'Statistic', 'Value'});
writetable(summary_tbl, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Multivariate_MeanDiff_vs_Volume.xlsx', ...
    'Sheet', 'Model Summary');

fprintf('Done. Results saved.\n');

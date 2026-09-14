%% Multivariate Linear Regression - DTI Asymmetry vs Survival

master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';

surv       = master.Survival_days_;
n_patients = height(master);

metrics       = {'mean_FA', 'mean_MD', 'mean_AD', 'mean_RD'};
metric_labels = {'FA', 'MD', 'AD', 'RD'};
n_metrics     = numel(metrics);

ref         = readtable(fullfile(csv_dir, [char(master.Patient_ID(1)) '.csv']), 'TextType', 'string');
all_tracts  = ref.tract;
left_tracts = all_tracts(endsWith(all_tracts, '_left'));
base_names  = replace(left_tracts, '_left', '');
base_names  = base_names(arrayfun(@(b) any(all_tracts == b + "_right"), base_names));
n_tracts    = numel(base_names);

% Asymmetry = (Contra - Ipsi) / (Contra + Ipsi)
asym_vals = NaN(n_patients, n_metrics);

for p = 1:n_patients
    pid  = char(master.Patient_ID(p));
    side = lower(char(master.Tumor_Side(p)));
    f    = fullfile(csv_dir, [pid '.csv']);
    if ~isfile(f), continue; end
    T = readtable(f, 'TextType', 'string');
    T.Properties.RowNames = cellstr(T.tract);
    if strcmp(side, 'right')
        ipsi_sfx = '_right'; contra_sfx = '_left';
    else
        ipsi_sfx = '_left';  contra_sfx = '_right';
    end
    for m = 1:n_metrics
        asym = NaN(n_tracts, 1);
        for t = 1:n_tracts
            ipsi_name   = char(base_names(t) + ipsi_sfx);
            contra_name = char(base_names(t) + contra_sfx);
            try
                i = T{ipsi_name,   metrics{m}};
                c = T{contra_name, metrics{m}};
                asym(t) = (c - i) / (0.5*(c + i));
            catch; end
        end
        asym_vals(p, m) = nanmean(asym);
    end
end

X = asym_vals;
y = surv;

mask    = ~any(isnan(X), 2) & ~isnan(y);
X_clean = X(mask, :);
y_clean = y(mask);

fprintf('Patients included in multivariate model: %d\n', sum(mask));

% Run multivariate regression
mdl = fitlm(X_clean, y_clean, ...
    'VarNames', {'FA_Asym','MD_Asym','AD_Asym','RD_Asym','Survival'});

disp(mdl)
disp(mdl.Coefficients)

coef_tbl = mdl.Coefficients;
coef_tbl.Properties.RowNames = {};
coef_tbl.Predictor = {'Intercept','FA_Asym','MD_Asym','AD_Asym','RD_Asym'}';
coef_tbl = coef_tbl(:, {'Predictor','Estimate','SE','tStat','pValue'});
writetable(coef_tbl, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Multivariate_Regression.xlsx', ...
    'Sheet', 'Coefficients');

summary_tbl = table({'R-squared'; 'Adjusted R-squared'; 'Model p-value'; 'N patients'}, ...
    [mdl.Rsquared.Ordinary; mdl.Rsquared.Adjusted; coefTest(mdl); sum(mask)], ...
    'VariableNames', {'Statistic', 'Value'});
writetable(summary_tbl, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Multivariate_Regression.xlsx', ...
    'Sheet', 'Model Summary');
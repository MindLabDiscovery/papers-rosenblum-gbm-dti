% One-sample t-test AND Wilcoxon signed-rank vs zero on Asymmetry Scores
% Asymmetry = (Contra - Ipsi) / 0.5*(Contra + Ipsi)


masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
outPath    = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Asymmetry_OneSample_Results.xlsx';

metrics = {'FA', 'MD', 'AD', 'RD'};
tracts  = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP', ...
           'SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC', ...
           'ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

if exist(outPath, 'file'), delete(outPath); end

% Collect all p-values first for FDR correction
all_p_ttest    = NaN(length(tracts), length(metrics));
all_p_wilcoxon = NaN(length(tracts), length(metrics));
all_n          = NaN(length(tracts), length(metrics));
all_mean_asym  = NaN(length(tracts), length(metrics));
all_med_asym   = NaN(length(tracts), length(metrics));
all_std_asym   = NaN(length(tracts), length(metrics));

for m = 1:length(metrics)
    metric = metrics{m};
    data = readtable(masterFile, 'Sheet', metric, 'VariableNamingRule', 'preserve');

    for t = 1:length(tracts)
        tract    = tracts{t};
        asym_col = [tract ' Asymmetry'];

        if ~ismember(asym_col, data.Properties.VariableNames)
            continue;
        end

        asym_vals = data.(asym_col);

        % Convert to numeric 
        if iscell(asym_vals)
            asym_vals = cellfun(@str2double, asym_vals);
        end
        asym_vals = double(asym_vals);

        % Remove NaN and zero-zero
        bad = isnan(asym_vals) | asym_vals == 0;
        asym_vals = asym_vals(~bad);
        n = length(asym_vals);

        all_n(t, m)        = n;
        all_mean_asym(t,m) = mean(asym_vals);
        all_med_asym(t,m)  = median(asym_vals);
        all_std_asym(t,m)  = std(asym_vals);

        if n < 5, continue; end

        % One-sample t-test vs zero
        [~, p_t] = ttest(asym_vals, 0);
        all_p_ttest(t, m) = p_t;

        % Wilcoxon signed-rank vs zero 
        p_w = signrank(asym_vals, 0);
        all_p_wilcoxon(t, m) = p_w;
    end
end

% Apply FDR correction (Benjamini-Hochberg) 
fdr_ttest    = NaN(size(all_p_ttest));
fdr_wilcoxon = NaN(size(all_p_wilcoxon));

for m = 1:length(metrics)
    % T-test FDR
    valid = ~isnan(all_p_ttest(:, m));
    if any(valid)
        pv = all_p_ttest(valid, m);
        n_tests = length(pv);
        [sorted_p, idx] = sort(pv);
        fdr_sorted = sorted_p;
        for i = n_tests:-1:1
            fdr_sorted(i) = min(sorted_p(i) * n_tests / i, 1);
            if i < n_tests
                fdr_sorted(i) = min(fdr_sorted(i), fdr_sorted(i+1));
            end
        end
        fdr_out = zeros(n_tests, 1);
        fdr_out(idx) = fdr_sorted;
        fdr_ttest(valid, m) = fdr_out;
    end

    % Wilcoxon FDR
    valid = ~isnan(all_p_wilcoxon(:, m));
    if any(valid)
        pv = all_p_wilcoxon(valid, m);
        n_tests = length(pv);
        [sorted_p, idx] = sort(pv);
        fdr_sorted = sorted_p;
        for i = n_tests:-1:1
            fdr_sorted(i) = min(sorted_p(i) * n_tests / i, 1);
            if i < n_tests
                fdr_sorted(i) = min(fdr_sorted(i), fdr_sorted(i+1));
            end
        end
        fdr_out = zeros(n_tests, 1);
        fdr_out(idx) = fdr_sorted;
        fdr_wilcoxon(valid, m) = fdr_out;
    end
end

%Output Table
varNames = {'Tract', 'N_FA', ...
            'Mean_Asym_FA', 'SD_Asym_FA', 'p_FA', 'p_FA_FDR', ...
            'Mean_Asym_MD', 'SD_Asym_MD', 'p_MD', 'p_MD_FDR', ...
            'Mean_Asym_AD', 'SD_Asym_AD', 'p_AD', 'p_AD_FDR', ...
            'Mean_Asym_RD', 'SD_Asym_RD', 'p_RD', 'p_RD_FDR'};
varTypes = repmat({'double'}, 1, length(varNames));
varTypes{1} = 'string';

T_ttest    = table('Size', [length(tracts), length(varNames)], ...
                   'VariableTypes', varTypes, 'VariableNames', varNames);
T_wilcoxon = table('Size', [length(tracts), length(varNames)], ...
                   'VariableTypes', varTypes, 'VariableNames', varNames);

for t = 1:length(tracts)
    T_ttest.Tract(t)    = tracts{t};
    T_wilcoxon.Tract(t) = tracts{t};

    T_ttest.N_FA(t)    = all_n(t, 1);
    T_wilcoxon.N_FA(t) = all_n(t, 1);

    for m = 1:length(metrics)
        mn  = metrics{m};
        T_ttest.   (['Mean_Asym_' mn])(t) = all_mean_asym(t,m);
        T_ttest.   (['SD_Asym_'   mn])(t) = all_std_asym(t,m);
        T_ttest.   (['p_' mn])(t)         = all_p_ttest(t,m);
        T_ttest.   (['p_' mn '_FDR'])(t)  = fdr_ttest(t,m);

        T_wilcoxon.(['Mean_Asym_' mn])(t) = all_med_asym(t,m);  
        T_wilcoxon.(['SD_Asym_'   mn])(t) = all_std_asym(t,m);
        T_wilcoxon.(['p_' mn])(t)         = all_p_wilcoxon(t,m);
        T_wilcoxon.(['p_' mn '_FDR'])(t)  = fdr_wilcoxon(t,m);
    end
end

writetable(T_ttest,    outPath, 'Sheet', 'OneSample_tTest');
writetable(T_wilcoxon, outPath, 'Sheet', 'OneSample_Wilcoxon');

fprintf('Done. Saved to:\n%s\n', outPath);
% Independent t-test AND Mann-Whitney U (Wilcoxon rank-sum) with FDR correction
masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
outPath    = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/IndepTTest_MannWhitney_Results_FDR.xlsx';

metrics = {'FA', 'MD', 'AD', 'RD'};
tracts  = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP', ...
           'SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC', ...
           'ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

function fdr_p = deal_fdr(pvals)
    n = length(pvals);
    [sorted_p, idx] = sort(pvals);
    fdr_p_sorted = sorted_p;
    for i = n:-1:1
        fdr_p_sorted(i) = min(sorted_p(i) * n / i, 1);
        if i < n
            fdr_p_sorted(i) = min(fdr_p_sorted(i), fdr_p_sorted(i+1));
        end
    end
    fdr_p = zeros(size(pvals));
    fdr_p(idx) = fdr_p_sorted;
end

if exist(outPath, 'file'), delete(outPath); end

all_p_ttest    = NaN(length(tracts), length(metrics));
all_p_wilcoxon = NaN(length(tracts), length(metrics));
all_n          = NaN(length(tracts), length(metrics));

for m = 1:length(metrics)
    metric = metrics{m};
    data = readtable(masterFile, 'Sheet', metric, 'VariableNamingRule', 'preserve');

    for t = 1:length(tracts)
        tract     = tracts{t};
        left_col  = [tract ' Left'];
        right_col = [tract ' Right'];

        if ~ismember(left_col, data.Properties.VariableNames) || ...
           ~ismember(right_col, data.Properties.VariableNames)
            continue;
        end

        ipsi_vals   = NaN(height(data), 1);
        contra_vals = NaN(height(data), 1);

        for p = 1:height(data)
            side = strtrim(data.Tumor_Side{p});
            if strcmpi(side, 'L')
                ipsi_vals(p)   = data.(left_col)(p);
                contra_vals(p) = data.(right_col)(p);
            elseif strcmpi(side, 'R')
                ipsi_vals(p)   = data.(right_col)(p);
                contra_vals(p) = data.(left_col)(p);
            end
        end

        bad = isnan(ipsi_vals) | isnan(contra_vals) | ...
              (ipsi_vals == 0 & contra_vals == 0);
        ipsi_vals   = ipsi_vals(~bad);
        contra_vals = contra_vals(~bad);
        n = length(ipsi_vals);
        all_n(t, m) = n;

        if n < 5, continue; end

     
        [~, p_t] = ttest2(ipsi_vals, contra_vals);

       
        p_w = ranksum(ipsi_vals, contra_vals);

        all_p_ttest(t, m)    = p_t;
        all_p_wilcoxon(t, m) = p_w;
    end
end

% FDR correction 
fdr_ttest    = NaN(size(all_p_ttest));
fdr_wilcoxon = NaN(size(all_p_wilcoxon));
for m = 1:length(metrics)
    valid = ~isnan(all_p_ttest(:, m));
    if any(valid)
        fdr_ttest(valid, m) = deal_fdr(all_p_ttest(valid, m));
    end
    valid = ~isnan(all_p_wilcoxon(:, m));
    if any(valid)
        fdr_wilcoxon(valid, m) = deal_fdr(all_p_wilcoxon(valid, m));
    end
end

% Independent T-Test with FDR

varNames = {'Tract', 'N_FA', ...
            'p_FA', 'p_FA_FDR', 'p_MD', 'p_MD_FDR', ...
            'p_AD', 'p_AD_FDR', 'p_RD', 'p_RD_FDR'};
varTypes = {'string','double', ...
            'double','double','double','double', ...
            'double','double','double','double'};

T_ttest    = table('Size', [length(tracts), length(varNames)], ...
                   'VariableTypes', varTypes, 'VariableNames', varNames);
T_wilcoxon = table('Size', [length(tracts), length(varNames)], ...
                   'VariableTypes', varTypes, 'VariableNames', varNames);

for t = 1:length(tracts)
    T_ttest.Tract(t)    = tracts{t};
    T_wilcoxon.Tract(t) = tracts{t};
    T_ttest.N_FA(t)     = all_n(t, 1);
    T_wilcoxon.N_FA(t)  = all_n(t, 1);
    T_ttest.p_FA(t)     = all_p_ttest(t, 1);    T_ttest.p_FA_FDR(t) = fdr_ttest(t, 1);
    T_ttest.p_MD(t)     = all_p_ttest(t, 2);    T_ttest.p_MD_FDR(t) = fdr_ttest(t, 2);
    T_ttest.p_AD(t)     = all_p_ttest(t, 3);    T_ttest.p_AD_FDR(t) = fdr_ttest(t, 3);
    T_ttest.p_RD(t)     = all_p_ttest(t, 4);    T_ttest.p_RD_FDR(t) = fdr_ttest(t, 4);
    T_wilcoxon.p_FA(t)     = all_p_wilcoxon(t, 1);    T_wilcoxon.p_FA_FDR(t) = fdr_wilcoxon(t, 1);
    T_wilcoxon.p_MD(t)     = all_p_wilcoxon(t, 2);    T_wilcoxon.p_MD_FDR(t) = fdr_wilcoxon(t, 2);
    T_wilcoxon.p_AD(t)     = all_p_wilcoxon(t, 3);    T_wilcoxon.p_AD_FDR(t) = fdr_wilcoxon(t, 3);
    T_wilcoxon.p_RD(t)     = all_p_wilcoxon(t, 4);    T_wilcoxon.p_RD_FDR(t) = fdr_wilcoxon(t, 4);
end

% Outputs

writetable(T_ttest,    outPath, 'Sheet', 'Indep_tTest');
writetable(T_wilcoxon, outPath, 'Sheet', 'MannWhitney');

fprintf('Done. Saved to:\n%s\n', outPath);
%% T-Test on Asymmetry Scores per Tract with FDR correction
clear;
master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';
metrics       = {'mean_FA', 'mean_MD', 'mean_AD', 'mean_RD'};
metric_labels = {'FA', 'MD', 'AD', 'RD'};
n_metrics     = numel(metrics);
n_patients    = height(master);

ref        = readtable(fullfile(csv_dir, [char(master.Patient_ID(1)) '.csv']), 'TextType', 'string');
all_tracts = ref.tract;
left_tracts = all_tracts(endsWith(all_tracts, '_left'));
base_names  = replace(left_tracts, '_left', '');
base_names  = base_names(arrayfun(@(b) any(all_tracts == b + "_right"), base_names));
n_tracts    = numel(base_names);

% Compute asymmetry scores
asym_vals = NaN(n_patients, n_tracts, n_metrics);
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
        for t = 1:n_tracts
            ipsi_name   = char(base_names(t) + ipsi_sfx);
            contra_name = char(base_names(t) + contra_sfx);
            try
                i = T{ipsi_name,   metrics{m}};
                c = T{contra_name, metrics{m}};
                asym_vals(p, t, m) = (c - i) / (0.5*(c + i));
            catch; end
        end
    end
end

% T-TEST
p_FA = NaN(1,n_tracts); p_MD = NaN(1,n_tracts);
p_AD = NaN(1,n_tracts); p_RD = NaN(1,n_tracts);

for t = 1:n_tracts
    fa = asym_vals(:, t, 1); fa = fa(~isnan(fa));
    md = asym_vals(:, t, 2); md = md(~isnan(md));
    ad = asym_vals(:, t, 3); ad = ad(~isnan(ad));
    rd = asym_vals(:, t, 4); rd = rd(~isnan(rd));

    if numel(fa) >= 3, [~, p_FA(t)] = ttest(fa, 0); end
    if numel(md) >= 3, [~, p_MD(t)] = ttest(md, 0); end
    if numel(ad) >= 3, [~, p_AD(t)] = ttest(ad, 0); end
    if numel(rd) >= 3, [~, p_RD(t)] = ttest(rd, 0); end
end

% FDR correction
p_FA_fdr = bh_fdr(p_FA);
p_MD_fdr = bh_fdr(p_MD);
p_AD_fdr = bh_fdr(p_AD);
p_RD_fdr = bh_fdr(p_RD);

% Save results
tract_names = cellstr(base_names);
results = table(tract_names, p_FA', p_FA_fdr', p_MD', p_MD_fdr', ...
    p_AD', p_AD_fdr', p_RD', p_RD_fdr', ...
    'VariableNames', {'Tract','p_FA','p_FA_FDR','p_MD','p_MD_FDR', ...
    'p_AD','p_AD_FDR','p_RD','p_RD_FDR'});
writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Asymmetry_TTest_FDR_results.csv');
fprintf('Done.\n');

function p_adj = bh_fdr(p_vals)
n = numel(p_vals);
[sorted_p, idx] = sort(p_vals);
adj = sorted_p .* n ./ (1:n);
for k = n-1:-1:1
    adj(k) = min(adj(k), adj(k+1));
end
p_adj = NaN(1,n);
p_adj(idx) = min(adj, 1);
end
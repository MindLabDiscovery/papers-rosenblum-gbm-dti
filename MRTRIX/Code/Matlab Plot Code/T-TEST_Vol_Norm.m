% Independent T-Test FA, MD, AD, RD / Tumor Volume for ALL TRACTS with FDR correction
clear;
folderpath = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';
data = dir(fullfile(folderpath, 'PT_*.csv'));
tum_loc = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx';
master = readtable(tum_loc, 'TextType', 'string');
vol_tbl = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_Tumor_Vol_vs_Survival.xlsx');
tracts = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP','SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

% Pre-allocate
n_pts = length(data); n_tracts = length(tracts);
FA_IPS  = NaN(n_pts, n_tracts); FA_CONT = NaN(n_pts, n_tracts);
MD_IPS  = NaN(n_pts, n_tracts); MD_CONT = NaN(n_pts, n_tracts);
AD_IPS  = NaN(n_pts, n_tracts); AD_CONT = NaN(n_pts, n_tracts);
RD_IPS  = NaN(n_pts, n_tracts); RD_CONT = NaN(n_pts, n_tracts);

% Tumor Vol to PT
tumor_vol = NaN(n_pts, 1);
for i = 1:n_pts
    pid = data(i).name(1:end-4);
    idx = strcmp(string(vol_tbl.Patient_ID), pid);
    if any(idx)
        tumor_vol(i) = vol_tbl.TumorVolume_cm3_(idx);
    end
end

% Load patient CSVs
for i = 1:n_pts
    T = readtable(fullfile(folderpath, data(i).name), 'TextType', 'string');
    T.tract = cellstr(T.tract);
    tumorLocation = master{strcmp(strtrim(master.Patient_ID), data(i).name(1:end-4)), 'Tumor_Side'};
    fprintf('File: %s, Side: %s\n', data(i).name, tumorLocation);
    for p = 1:n_tracts
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
        end
    end
end

% Tumor volume normalization
for i = 1:n_pts
    if ~isnan(tumor_vol(i))
        FA_IPS(i,:)  = FA_IPS(i,:)  / tumor_vol(i);
        FA_CONT(i,:) = FA_CONT(i,:) / tumor_vol(i);
        MD_IPS(i,:)  = MD_IPS(i,:)  / tumor_vol(i);
        MD_CONT(i,:) = MD_CONT(i,:) / tumor_vol(i);
        AD_IPS(i,:)  = AD_IPS(i,:)  / tumor_vol(i);
        AD_CONT(i,:) = AD_CONT(i,:) / tumor_vol(i);
        RD_IPS(i,:)  = RD_IPS(i,:)  / tumor_vol(i);
        RD_CONT(i,:) = RD_CONT(i,:) / tumor_vol(i);
    end
end

% Independent t-test
p_FA = NaN(1,n_tracts); p_MD = NaN(1,n_tracts);
p_AD = NaN(1,n_tracts); p_RD = NaN(1,n_tracts);
for t = 1:n_tracts
    fa_cont = FA_CONT(~isnan(FA_CONT(:,t)), t);
    fa_ips  = FA_IPS(~isnan(FA_IPS(:,t)), t);
    md_cont = MD_CONT(~isnan(MD_CONT(:,t)), t);
    md_ips  = MD_IPS(~isnan(MD_IPS(:,t)), t);
    ad_cont = AD_CONT(~isnan(AD_CONT(:,t)), t);
    ad_ips  = AD_IPS(~isnan(AD_IPS(:,t)), t);
    rd_cont = RD_CONT(~isnan(RD_CONT(:,t)), t);
    rd_ips  = RD_IPS(~isnan(RD_IPS(:,t)), t);

    if numel(fa_cont) >= 3 && numel(fa_ips) >= 3, [~, p_FA(t)] = ttest2(fa_cont, fa_ips); end
    if numel(md_cont) >= 3 && numel(md_ips) >= 3, [~, p_MD(t)] = ttest2(md_cont, md_ips); end
    if numel(ad_cont) >= 3 && numel(ad_ips) >= 3, [~, p_AD(t)] = ttest2(ad_cont, ad_ips); end
    if numel(rd_cont) >= 3 && numel(rd_ips) >= 3, [~, p_RD(t)] = ttest2(rd_cont, rd_ips); end
end

% FDR correction
p_FA_fdr = bh_fdr(p_FA);
p_MD_fdr = bh_fdr(p_MD);
p_AD_fdr = bh_fdr(p_AD);
p_RD_fdr = bh_fdr(p_RD);

% Save results
results = table(tracts', p_FA', p_FA_fdr', p_MD', p_MD_fdr', ...
    p_AD', p_AD_fdr', p_RD', p_RD_fdr', ...
    'VariableNames', {'Tract','p_FA','p_FA_FDR','p_MD','p_MD_FDR', ...
    'p_AD','p_AD_FDR','p_RD','p_RD_FDR'});
writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Independent_T-Test_FDR_Norm_Vol_results.csv');
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
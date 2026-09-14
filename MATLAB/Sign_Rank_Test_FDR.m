% Sign-Rank FA,MD,RD,AD for ALL TRACTS
clear;
folderpath = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';
data = dir(fullfile(folderpath, 'PT_*.csv'));
tum_loc = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx';
master = readtable(tum_loc, 'TextType', 'string');
tracts = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP','SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

% Pre-allocate
n_pts = length(data); n_tracts = length(tracts);
FA_IPS  = NaN(n_pts, n_tracts); FA_CONT = NaN(n_pts, n_tracts);
MD_IPS  = NaN(n_pts, n_tracts); MD_CONT = NaN(n_pts, n_tracts);
AD_IPS  = NaN(n_pts, n_tracts); AD_CONT = NaN(n_pts, n_tracts);
RD_IPS  = NaN(n_pts, n_tracts); RD_CONT = NaN(n_pts, n_tracts);

% PT CSV's
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

% Sign-Rank
p_FA = NaN(1,n_tracts); p_MD = NaN(1,n_tracts);
p_AD = NaN(1,n_tracts); p_RD = NaN(1,n_tracts);

for t = 1:n_tracts
    fa = FA_CONT(:,t) - FA_IPS(:,t); fa = fa(~isnan(fa));
    md = MD_CONT(:,t) - MD_IPS(:,t); md = md(~isnan(md));
    ad = AD_CONT(:,t) - AD_IPS(:,t); ad = ad(~isnan(ad));
    rd = RD_CONT(:,t) - RD_IPS(:,t); rd = rd(~isnan(rd));
    if numel(fa) >= 3, p_FA(t) = signrank(fa); end
    if numel(md) >= 3, p_MD(t) = signrank(md); end
    if numel(ad) >= 3, p_AD(t) = signrank(ad); end
    if numel(rd) >= 3, p_RD(t) = signrank(rd); end
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
writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Sign_Rank_FDR_results.csv');
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
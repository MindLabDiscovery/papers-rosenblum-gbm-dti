% Lin-Reg FDR Corrected
reg = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Regression_All_Tracts.xlsx', ...
    'VariableNamingRule', 'preserve');

tracts = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP', ...
    'SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC', ...
    'ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};
metrics = {'FA','MD','AD','RD'};
sides   = {'Ipsilateral','Contralateral'};

% FDR
p_all = reg.p_slope;
p_fdr = bh_fdr(p_all(:)');
reg.p_FDR = p_fdr';

n   = numel(tracts);
out = table(tracts', 'VariableNames', {'Tract'});

for m = 1:numel(metrics)
    for s = 1:numel(sides)
        col_p   = sprintf('p_%s_%s', metrics{m}, sides{s}(1:4));
        col_fdr = sprintf('p_%s_%s_FDR', metrics{m}, sides{s}(1:4));
        pvals = NaN(n,1);
        fdrs  = NaN(n,1);
        for t = 1:n
            mask = strcmp(reg.Tract, tracts{t}) & ...
                strcmp(reg.Metric, metrics{m}) & ...
                strcmp(reg.Side,   sides{s});
            if any(mask)
                pvals(t) = reg.p_slope(mask);
                fdrs(t)  = reg.p_FDR(mask);
            end
        end
        out.(col_p)   = pvals;
        out.(col_fdr) = fdrs;
    end
end

writetable(out, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Regression_FDR_Results.xlsx');
fprintf('Done. Significant raw p<0.05: %d | FDR p<0.05: %d\n', ...
    sum(reg.p_slope < 0.05), sum(reg.p_FDR < 0.05));

function p_adj = bh_fdr(p_vals)
n = numel(p_vals);
[sorted_p, idx] = sort(p_vals);
adj = sorted_p .* n ./ (1:n);
for k = n-1:-1:1
    adj(k) = min(adj(k), adj(k+1));
end
p_adj = NaN(1, n);
p_adj(idx) = min(adj, 1);
end
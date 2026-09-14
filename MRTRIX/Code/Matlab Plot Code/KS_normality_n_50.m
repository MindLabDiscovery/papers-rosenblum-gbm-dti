% Kolmogorov-Smirnov Normality Test (n = 50)
masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
outPath    = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/KS_Normality_Results.txt';

metrics    = {'FA', 'MD', 'AD', 'RD'};
tracts     = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF','OR','POPT','SCP', ...
    'SLF_I','SLF_II','SLF_III','ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC', ...
    'ST_PREF','ST_PREM','STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};

fid = fopen(outPath, 'w');
header  = sprintf('%-6s  %-12s  %-10s  %-8s  %-8s  %-6s  %-6s\n', ...
    'Metric','Tract','Side','D-stat','p-value','Normal?','n');
divider = [repmat('-', 1, 65) newline];
fprintf(header);      fprintf(fid, header);
fprintf(divider);     fprintf(fid, divider);

for m = 1:4
    data = readtable(masterFile, 'Sheet', metrics{m}, 'VariableNamingRule', 'preserve');
    n    = height(data);

    for t = 1:length(tracts)
        tract     = tracts{t};
        left_col  = [tract ' Left'];
        right_col = [tract ' Right'];

        
        ipsi  = zeros(n,1);
        contra = zeros(n,1);
        for p = 1:n
            side = strtrim(data.('Tumor_Side'){p});
            lv   = data.(left_col)(p);
            rv   = data.(right_col)(p);
            if strcmp(side,'R')
                ipsi(p)  = rv;
                contra(p) = lv;
            else
                ipsi(p)  = lv;
                contra(p) = rv;
            end
        end

        % KS test for ipsilateral
        ipsi   = ipsi(~isnan(ipsi));
        [h_i, p_i, ks_i] = kstest(ipsi, 'CDF', makedist('Normal','mu',mean(ipsi),'sigma',std(ipsi)));
        line = sprintf('%-6s  %-12s  %-10s  %-8.4f  %-8.4f  %-6s  %d\n', ...
            metrics{m}, tract, 'Ipsi', ks_i, p_i, string(~logical(h_i)), length(ipsi));
        fprintf(line); fprintf(fid, line);

        % KS test for contralateral
        contra = contra(~isnan(contra));
        [h_c, p_c, ks_c] = kstest(contra, 'CDF', makedist('Normal','mu',mean(contra),'sigma',std(contra)));
        line = sprintf('%-6s  %-12s  %-10s  %-8.4f  %-8.4f  %-6s  %d\n', ...
            metrics{m}, tract, 'Contra', ks_c, p_c, string(~logical(h_c)), length(contra));
        fprintf(line); fprintf(fid, line);
    end

    fprintf(divider); fprintf(fid, divider);
end

fclose(fid);
fprintf('\nResults saved to: %s\n', outPath);
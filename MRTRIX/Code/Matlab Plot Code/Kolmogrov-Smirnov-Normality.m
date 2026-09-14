% Kolomgrov-Smirnov Normality Test

dataPath = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2';  

file = fullfile(dataPath, 'Mean_Difference_Per_Metric.xlsx');

FA = readtable(file, 'Sheet', 'FA');
MD = readtable(file, 'Sheet', 'MD');
AD = readtable(file, 'Sheet', 'AD');
RD = readtable(file, 'Sheet', 'RD');

metrics = {FA, MD, AD, RD};
names   = {'FA', 'MD', 'AD', 'RD'};

% Output File
outFile = fullfile(dataPath, 'KS_Normality_Results.txt');
fid = fopen(outFile, 'w');

header = sprintf('%-6s  %-8s  %-8s  %-6s\n', 'Metric', 'D-stat', 'p-value', 'Normal?');
divider = [repmat('-', 1, 38) newline];

fprintf(header);          
fprintf(fid, header);     
fprintf(divider);
fprintf(fid, divider);

for i = 1:4
    data  = metrics{i}.Mean_Diff;
    data  = data(~isnan(data));
    mu    = mean(data);
    sigma = std(data);
    [h, p, ks] = kstest(data, 'CDF', makedist('Normal', 'mu', mu, 'sigma', sigma));
    line = sprintf('%-6s  %-8.4f  %-8.4f  %s\n', names{i}, ks, p, string(~logical(h)));
    fprintf(line);
    fprintf(fid, line);
end

fclose(fid);
fprintf('\nResults saved to: %s\n', outFile);
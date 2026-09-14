%% Asymmetry Per Tract
clear;

master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
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

%Asymmetry
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


out_path = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Asymmetry_Scores_Per_Tract.xlsx';
patient_ids = cellstr(master.Patient_ID);
tract_names = cellstr(base_names);

for m = 1:n_metrics
    
    data_matrix = squeeze(asym_vals(:, :, m))';  

    tbl = array2table(data_matrix, 'RowNames', tract_names, 'VariableNames', patient_ids);
    writetable(tbl, out_path, 'Sheet', metric_labels{m}, 'WriteRowNames', true);
    fprintf('Saved %s sheet.\n', metric_labels{m});
end

fprintf('Done. Asymmetry scores saved to:\n%s\n', out_path);

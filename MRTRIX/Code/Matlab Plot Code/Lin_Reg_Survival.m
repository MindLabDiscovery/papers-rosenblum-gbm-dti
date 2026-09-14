%% All-Tract Linear Regression vs Survival

master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V1/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';
fig_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Lin_Reg_Surv_V2';
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% Pull survival directly from master table
surv = master.Survival_days_;

ref         = readtable(fullfile(csv_dir, [char(master.Patient_ID(1)) '.csv']), 'TextType', 'string');
all_tracts  = ref.tract;
left_tracts = all_tracts(endsWith(all_tracts, '_left'));
base_names  = replace(left_tracts, '_left', '');
base_names  = base_names(arrayfun(@(b) any(all_tracts == b + "_right"), base_names));
n_tracts    = numel(base_names);

metrics       = {'mean_FA', 'mean_MD', 'mean_AD', 'mean_RD'};
metric_labels = {'FA', 'MD', 'AD', 'RD'};
n_metrics     = numel(metrics);
n_patients    = height(master);

ipsi_vals   = NaN(n_patients, n_tracts, n_metrics);
contra_vals = NaN(n_patients, n_tracts, n_metrics);

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
    for t = 1:n_tracts
        ipsi_name   = base_names(t) + ipsi_sfx;
        contra_name = base_names(t) + contra_sfx;
        for m = 1:n_metrics
            try; ipsi_vals(p,t,m)   = T{char(ipsi_name),  metrics{m}}; catch; end
            try; contra_vals(p,t,m) = T{char(contra_name), metrics{m}}; catch; end
        end
    end
end

fprintf('Patients loaded with data: %d of %d\n', ...
    sum(~all(all(isnan(ipsi_vals),3),2)), n_patients);

% Run regression
results = table();
for t = 1:n_tracts
    tract_name = char(base_names(t));
    for m = 1:n_metrics
        for s = 1:2
            if s == 1
                x          = ipsi_vals(:,t,m);
                side_label = 'Ipsilateral';
            else
                x          = contra_vals(:,t,m);
                side_label = 'Contralateral';
            end

            mask    = ~(isnan(x) | isnan(surv));
            x_clean = x(mask);
            y_clean = surv(mask);

            if numel(x_clean) < 4, continue; end

            mdl     = fitlm(x_clean, y_clean);
            p_slope = mdl.Coefficients.pValue(2);
            [Rmat, Pmat] = corrcoef(x_clean, y_clean, 'Rows', 'complete');
            r   = Rmat(1,2);
            p_r = Pmat(1,2);

            results = [results; table(string(tract_name), string(metric_labels{m}), ...
                string(side_label), p_slope, r, p_r, ...
                'VariableNames', {'Tract','Metric','Side','p_slope','r','p_r'})];

            figure('Visible', 'off');
            plot(mdl);
            legend('Location', 'northwest');
            xlabel(metric_labels{m});
            ylabel('Survival (Days)');
            title(sprintf('%s %s %s vs Survival', side_label, tract_name, metric_labels{m}));
            txt = sprintf('Slope p = %.3g\nPearson r = %.3f (p = %.3g)', p_slope, r, p_r);
            ax   = gca;
            xpos = ax.XLim(1) + 0.95*diff(ax.XLim);
            ypos = ax.YLim(1) + 0.95*diff(ax.YLim);
            text(xpos, ypos, txt, 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'top', 'FontSize', 10, ...
                'BackgroundColor', 'w', 'EdgeColor', 'k');
            fname = sprintf('%s_%s_%s.png', tract_name, metric_labels{m}, side_label);
            saveas(gcf, fullfile(fig_dir, fname));
            close;
        end
    end
end

if isempty(results)
    error('No results computed. Check patient CSVs exist in csv_dir.');
end

results = sortrows(results, 'p_slope');
writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Regression_All_Tracts.xlsx');
fprintf('Done. %d total regressions. %d significant (p<0.05).\n', height(results), sum(results.p_slope < 0.05));
disp(results(results.p_slope < 0.05, :));

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
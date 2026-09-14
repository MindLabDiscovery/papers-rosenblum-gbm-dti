%% Linear Regression: Tumor Volume vs DTI Asymmetry Index (individual metrics)
clear;

master  = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_ID_AND_Tumor_Location.xlsx', 'TextType', 'string');
vol_tbl = readtable('/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/PT_Tumor_Vol_vs_Survival.xlsx');
csv_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/PT_TRACT_STATS/Plotted_Stats';
fig_dir = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Lin_Reg_Asym_Vol';
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

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


% Asymmetry = (Contra - Ipsi) / (0.5 * (Contra + Ipsi))
asym_vals = NaN(n_patients, n_metrics);

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
        asym = NaN(n_tracts, 1);
        for t = 1:n_tracts
            ipsi_name   = char(base_names(t) + ipsi_sfx);
            contra_name = char(base_names(t) + contra_sfx);
            try
                i = T{ipsi_name,   metrics{m}};
                c = T{contra_name, metrics{m}};
                asym(t) = (c - i) / (0.5*(c + i));
            catch; end
        end
        asym_vals(p, m) = mean(asym, 'omitnan');
    end
end


tumor_vol = NaN(n_patients, 1);
for p = 1:n_patients
    pid = char(master.Patient_ID(p));
    idx = strcmp(string(vol_tbl.Patient_ID), pid);
    if any(idx)
        tumor_vol(p) = vol_tbl.TumorVolume_cm3_(idx);
    end
end


results = table();

for m = 1:n_metrics
    x    = tumor_vol;
    y    = asym_vals(:, m);
    mask = ~(isnan(x) | isnan(y));
    x_clean = x(mask);
    y_clean = y(mask);

    if numel(x_clean) < 4
        warning('Not enough data for %s', metric_labels{m});
        continue;
    end

    mdl     = fitlm(x_clean, y_clean);
    p_slope = mdl.Coefficients.pValue(2);
    [Rmat, Pmat] = corrcoef(x_clean, y_clean);
    r   = Rmat(1,2);
    p_r = Pmat(1,2);
    r2  = mdl.Rsquared.Ordinary;

    results = [results; table(string(metric_labels{m}), p_slope, r, p_r, r2, ...
        'VariableNames', {'Metric','p_slope','r','p_r','R2'})];

    % Plot
    figure('Visible', 'off');
    plot(mdl);
    legend('Location', 'northwest');
    xlabel('Tumor Volume (cm^3)');
    ylabel([metric_labels{m} ' Asymmetry Index']);
    title(sprintf('Tumor Volume vs %s Asymmetry', metric_labels{m}));
    txt = sprintf('Slope p = %.3g\nr = %.3f (p = %.3g)\nR^2 = %.3f', p_slope, r, p_r, r2);
    ax   = gca;
    xpos = ax.XLim(1) + 0.95*diff(ax.XLim);
    ypos = ax.YLim(1) + 0.95*diff(ax.YLim);
    text(xpos, ypos, txt, 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontSize', 10, ...
        'BackgroundColor', 'w', 'EdgeColor', 'k');
    saveas(gcf, fullfile(fig_dir, sprintf('Volume_vs_%s_Asym.png', metric_labels{m})));
    close;
end

writetable(results, '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/LinReg_Asym_vs_Volume.xlsx');
fprintf('Done. Results saved.\n');
disp(results);

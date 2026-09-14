%% Linear Regression: DTI Metrics vs Survival (GBM)
clear; clc;

masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
fig_dir    = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Lin_Reg_Surv_V3/';
out_xlsx   = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Regression_All_Tracts_V3.xlsx';

if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% Load master sheet
master    = readtable(masterFile, 'Sheet', 'Master', 'VariableNamingRule', 'preserve');
surv      = master.('Survival (months)');
tumorSide = master.('Tumor_Side (L/R)');   

% Helper: map L/R to Left/Right
getLR = @(ts, side) deal_hemi(ts, side);
function hemi = deal_hemi(ts, side)
    ts = strtrim(ts);
    if strcmpi(ts,'L'),     ipsiHemi = 'Left';
    elseif strcmpi(ts,'R'), ipsiHemi = 'Right';
    else,                    ipsiHemi = '';       
    end
    if strcmpi(ipsiHemi,'Left'),  contraHemi = 'Right';
    elseif strcmpi(ipsiHemi,'Right'), contraHemi = 'Left';
    else, contraHemi = '';
    end
    if strcmpi(side,'Ipsilateral'), hemi = ipsiHemi;
    else,                            hemi = contraHemi;
    end
end

% Define tracts and metrics
tracts  = {'AF','ATR','CG','CST','FPT','FX','ICP','IFO','ILF','MLF', ...
           'OR','POPT','SCP','SLF_I','SLF_II','SLF_III', ...
           'ST_FO','ST_OCC','ST_PAR','ST_POSTC','ST_PREC','ST_PREF','ST_PREM', ...
           'STR','T_OCC','T_PAR','T_POSTC','T_PREC','T_PREF','T_PREM','UF'};
metrics = {'FA','MD','AD','RD'};
sides   = {'Ipsilateral','Contralateral'};

% First pass: collect p-values for FDR
fprintf('Pass 1: collecting p-values...\n');
results = struct('Tract',{},'Metric',{},'Side',{},'N',{},...
                 'p_slope',{},'r',{},'p_r',{},'p_slope_FDR',{});
idx = 0;

for ti = 1:numel(tracts)
    tract = tracts{ti};
    for mi = 1:numel(metrics)
        metric = metrics{mi};
        try
            tbl = readtable(masterFile, 'Sheet', metric, 'VariableNamingRule', 'preserve');
        catch
            warning('Sheet %s not found', metric); continue
        end
        for si = 1:numel(sides)
            side = sides{si};

            vals = nan(height(master), 1);
            for pi = 1:height(master)
                hemi = deal_hemi(tumorSide{pi}, side);
                if isempty(hemi), continue; end
                colName = sprintf('%s %s', tract, hemi);
                if ismember(colName, tbl.Properties.VariableNames)
                    vals(pi) = tbl.(colName)(pi);
                end
            end

            x = vals; y = surv;
            bad = isnan(x) | isnan(y) | (x == 0);
            x_clean = x(~bad); y_clean = y(~bad);
            n = numel(x_clean);

            if n < 3
                p_slope = NaN; r_val = NaN; p_r = NaN;
            else
                mdl = fitlm(x_clean, y_clean);
                p_slope = mdl.Coefficients.pValue(2);
                [Rmat, Pmat] = corrcoef(x_clean, y_clean, 'Rows', 'complete');
                r_val = Rmat(1,2); p_r = Pmat(1,2);
            end

            idx = idx + 1;
            results(idx).Tract   = tract;
            results(idx).Metric  = metric;
            results(idx).Side    = side;
            results(idx).N       = n;
            results(idx).p_slope = p_slope;
            results(idx).r       = r_val;
            results(idx).p_r     = p_r;
        end
    end
end

% FDR correction (manual Benjamini-Hochberg)
pvals = [results.p_slope]';
valid = ~isnan(pvals);
p_fdr = nan(numel(pvals),1);
pv = pvals(valid);
m  = numel(pv);
[sorted_p, sort_idx] = sort(pv);
adjusted = sorted_p .* m ./ (1:m)';
for k = m-1:-1:1
    adjusted(k) = min(adjusted(k), adjusted(k+1));
end
p_fdr_valid = nan(m,1);
p_fdr_valid(sort_idx) = min(adjusted, 1);
p_fdr(valid) = p_fdr_valid;
for i = 1:numel(results)
    results(i).p_slope_FDR = p_fdr(i);
end

% Second pass: generate figures
fprintf('Pass 2: generating %d figures...\n', numel(results));

for i = 1:numel(results)
    tract   = results(i).Tract;
    metric  = results(i).Metric;
    side    = results(i).Side;
    n       = results(i).N;
    p_slope = results(i).p_slope;
    r_val   = results(i).r;
    p_r     = results(i).p_r;

    try
        tbl = readtable(masterFile, 'Sheet', metric, 'VariableNamingRule', 'preserve');
    catch
        continue
    end

    vals = nan(height(master), 1);
    for pi = 1:height(master)
        hemi = deal_hemi(tumorSide{pi}, side);
        if isempty(hemi), continue; end
        colName = sprintf('%s %s', tract, hemi);
        if ismember(colName, tbl.Properties.VariableNames)
            vals(pi) = tbl.(colName)(pi);
        end
    end

    x = vals; y = surv;
    bad = isnan(x) | isnan(y) | (x == 0);
    x_clean = x(~bad); y_clean = y(~bad);
    if numel(x_clean) < 3, continue; end

    mdl  = fitlm(x_clean, y_clean);
    xfit = linspace(min(x_clean), max(x_clean), 200)';
    [ypred, yci] = predict(mdl, xfit);

    % Figure: white background
    fig = figure('Visible','off','Color','white','Units','pixels','Position',[100 100 560 420]);
    ax  = axes(fig);
    hold(ax,'on');
    ax.Color     = 'white';
    ax.FontSize  = 10;
    ax.LineWidth = 1;
    ax.XAxis.Color = 'black';
    ax.YAxis.Color = 'black';
    box(ax,'on'); grid(ax,'on');
    ax.GridColor = [0.8 0.8 0.8]; ax.GridAlpha = 0.5;

    fill(ax, [xfit; flipud(xfit)], [yci(:,1); flipud(yci(:,2))], ...
         [0.7 0.85 1.0], 'FaceAlpha', 0.35, 'EdgeColor', 'none');
    scatter(ax, x_clean, y_clean, 40, [0.2 0.4 0.8], 'filled', ...
            'MarkerFaceAlpha', 0.75, 'MarkerEdgeColor', 'none');
    plot(ax, xfit, ypred, '-', 'Color', [0.85 0.1 0.1], 'LineWidth', 1.8);

    xlabel(ax, sprintf('%s  —  %s  (n = %d)', metric, side, n), ...
           'FontSize', 10, 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax, 'Survival (months)', ...
           'FontSize', 10, 'FontWeight', 'bold', 'Color', 'black');
    title(ax, sprintf('%s  |  %s  |  %s', tract, metric, side), ...
          'FontSize', 11, 'FontWeight', 'bold', 'Color', 'black');
    hold(ax,'off');

    % Annotation box: black background, white text
    if isnan(p_slope), pStr = 'p = N/A';
    elseif p_slope < 0.001, pStr = 'p < 0.001';
    else, pStr = sprintf('p = %.3f', p_slope); end

    if isnan(r_val), rStr = 'r = N/A';
    else, rStr = sprintf('r = %.3f', r_val); end

    if isnan(p_r), prStr = 'p_r = N/A';
    elseif p_r < 0.001, prStr = 'p_r < 0.001';
    else, prStr = sprintf('p_r = %.3f', p_r); end

    ax.Units = 'normalized';
    axPos = ax.Position;
    boxW = 0.22; boxH = 0.15;
    boxX = axPos(1) + axPos(3) - boxW - 0.01;
    boxY = axPos(2) + axPos(4) - boxH - 0.01;

    annotation(fig, 'textbox', [boxX boxY boxW boxH], ...
        'String',              sprintf('%s\n%s\n%s', pStr, rStr, prStr), ...
        'BackgroundColor',     'black', ...
        'Color',               'white', ...
        'FontSize',            9, ...
        'FontWeight',          'bold', ...
        'EdgeColor',           'white', ...
        'LineWidth',           1, ...
        'Margin',              4, ...
        'FitBoxToText',        false, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'middle', ...
        'Interpreter',         'none');

    % Save
    fname = sprintf('%s_%s_%s.png', tract, metric, side);
    exportgraphics(fig, fullfile(fig_dir, fname), 'Resolution', 150, 'BackgroundColor', 'white');

    if ~isnan(p_slope) && p_slope < 0.05
        copyfile(fullfile(fig_dir, fname), fullfile(fig_dir, ['SIG_' fname]));
        fprintf('  SIG: %s\n', fname);
    end

    close(fig);
    fprintf('  [%d/%d] %s\n', i, numel(results), fname);
end

% Save results table
writetable(struct2table(results), out_xlsx, 'Sheet', 'Regression');
fprintf('\nDone! Figures saved to: %s\n', fig_dir);
% Fornix Verification 

masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx';
outDir     = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/Fornix_Plots/';
if ~exist(outDir,'dir'), mkdir(outDir); end

metrics = {'FA','MD','AD','RD'};
tract   = 'FX';

for m = 1:length(metrics)
    metric    = metrics{m};
    data      = readtable(masterFile,'Sheet',metric,'VariableNamingRule','preserve');
    left_col  = [tract ' Left'];
    right_col = [tract ' Right'];

    left_vals  = data.(left_col);
    right_vals = data.(right_col);

    % Patient ID 
    if isnumeric(data.Patient_ID)
        pt_ids = arrayfun(@(x) sprintf('PT%d',x), data.Patient_ID, 'UniformOutput',false);
    else
        pt_ids = cellfun(@(x) strtrim(string(x)), data.Patient_ID, 'UniformOutput',false);
    end

    % Remove Zeros
    bad = isnan(left_vals) | isnan(right_vals);
    left_vals  = left_vals(~bad);
    right_vals = right_vals(~bad);
    pt_ids     = pt_ids(~bad);
    n          = length(left_vals);

  
    fig = figure('Color','k','Position',[100 100 900 750]);
    ax  = axes('Color','k','XColor','w','YColor','w','FontSize',12);
    hold on;

    % Jitter
    [~, sortL] = sort(left_vals);
    [~, sortR] = sort(right_vals);
    jL = zeros(n,1);  jR = zeros(n,1);
    for i = 1:n
        rank = find(sortL == i);
        jL(i) = (rank / (n+1) - 0.5) * 0.28;
        rank  = find(sortR == i);
        jR(i) = (rank / (n+1) - 0.5) * 0.28;
    end

    % Scatter points
    scatter(1+jL, left_vals,  26, [0.2 0.55 1.0],'filled','MarkerFaceAlpha',0.85);
    scatter(2+jR, right_vals, 26, [1.0 0.35 0.35],'filled','MarkerFaceAlpha',0.85);

    % Label every point
    for p = 1:n
        if jL(p) >= 0
            text(1+jL(p)+0.03, left_vals(p), pt_ids{p}, ...
                'Color','w','FontSize',6.5, ...
                'HorizontalAlignment','left','VerticalAlignment','middle');
        else
            text(1+jL(p)-0.03, left_vals(p), pt_ids{p}, ...
                'Color','w','FontSize',6.5, ...
                'HorizontalAlignment','right','VerticalAlignment','middle');
        end
        
        if jR(p) >= 0
            text(2+jR(p)+0.03, right_vals(p), pt_ids{p}, ...
                'Color','w','FontSize',6.5, ...
                'HorizontalAlignment','left','VerticalAlignment','middle');
        else
            text(2+jR(p)-0.03, right_vals(p), pt_ids{p}, ...
                'Color','w','FontSize',6.5, ...
                'HorizontalAlignment','right','VerticalAlignment','middle');
        end
    end

    % Box plot on top
    bp = boxplot([left_vals, right_vals],{'Left','Right'}, ...
        'Colors',      [0.2 0.55 1.0; 1.0 0.35 0.35], ...
        'BoxStyle',    'outline', ...
        'MedianStyle', 'line', ...
        'Widths',      0.2, ...
        'OutlierSize', 0.01);
    set(bp,'Color','w','LineWidth',1.8);
    set(findobj(ax,'Tag','Median'),'Color','y','LineWidth',2.5);

    % Mean ± SEM
    means = [mean(left_vals),        mean(right_vals)];
    sems  = [std(left_vals)/sqrt(n), std(right_vals)/sqrt(n)];
    errorbar([1 2], means, sems, ...
        's','Color','y','MarkerFaceColor','y', ...
        'MarkerSize',7,'LineWidth',2,'CapSize',12);

    % Auto y-axis
    pad = range([left_vals; right_vals]) * 0.12;
    if pad == 0, pad = 0.005; end
    ylim([min([left_vals; right_vals])-pad,  max([left_vals; right_vals])+pad]);

    ax.XLim       = [0.4 2.9];
    ax.XTick      = [1 2];
    ax.XTickLabel = {'Left','Right'};
    ax.YGrid      = 'on';
    ax.GridColor  = [0.3 0.3 0.3];
    ax.GridAlpha  = 0.4;
    ax.Box        = 'off';
    ax.TickDir    = 'out';

    title(sprintf('Fornix (FX) — %s   (n=%d of 50 segmented)', metric, n), ...
        'Color','w','FontSize',14,'FontWeight','bold');
    ylabel(metric,'Color','w','FontSize',13);
    xlabel('Hemisphere','Color','w','FontSize',12);

    % Save
    outFile = fullfile(outDir, sprintf('Fornix_%s.png', metric));
    exportgraphics(fig, outFile,'Resolution',300,'BackgroundColor','k');
    fprintf('Saved: %s\n', outFile);
    close(fig);
end

fprintf('\nDone. Note: n=%d reflects successful TractSeg segmentation only.\n', n);
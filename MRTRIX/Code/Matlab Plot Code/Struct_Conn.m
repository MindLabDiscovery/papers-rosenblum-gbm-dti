%Structural Connectome (301)
 c = readmatrix("connectome.csv");

 figure;
 imagesc(log1p(c));
 colorbar;
 colormap hot;
 title('301 Structural Connectome');
 xlabel('Region');
 ylabel('Region');
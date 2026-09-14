masterFile = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled_v2.xlsx';
outPath = '/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Heat_Map';

% Heat Map
t = readtable(masterFile, Sheet="FA");
h = heatmap(t, 'Patient_ID', 'Tumor_Side', 'ColorVariable', 'ColorVariable');
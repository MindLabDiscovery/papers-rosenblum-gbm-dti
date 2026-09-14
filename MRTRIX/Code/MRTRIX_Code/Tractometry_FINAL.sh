#!/usr/bin/env bash
set -euo pipefail
echo "MRtrix Full Pipeline - Ethan"
echo "----------------------------"

# ============================================================
# SETUP — Conda + ANTs
# ============================================================
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate ~/anaconda3/envs/MRTRIX
command -v N4BiasFieldCorrection >/dev/null || { echo "ERROR: N4BiasFieldCorrection not found on PATH"; exit 1; }

INPUT_DICOM="${1:-}"
OUTPUT_DIR="${2:-}"

if [[ -z "$INPUT_DICOM" ]]; then
    read -rp "Enter DICOM Folder Path: " INPUT_DICOM
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    read -rp "Enter Output Folder Path: " OUTPUT_DIR
fi

if [[ -z "$INPUT_DICOM" || -z "$OUTPUT_DIR" ]]; then
    echo "Error: Input and Output required."
    exit 1
fi

if [[ ! -d "$INPUT_DICOM" ]]; then
    echo "Error: input folder doesn't exist: $INPUT_DICOM"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================================
# PERMANENT PATH VARIABLES — set once, never overwritten
# ============================================================
# DWI_DIR holds all diffusion processing outputs (response functions,
# FODs, DTI metrics like fa.mif/md.mif/ad.mif/rd.mif, brain mask, etc.)
# This is set explicitly below once the user provides the .mif path in
# Step 2, and is used by every later step instead of a reused OUTDIR.
DWI_DIR=""

# TRACTOGRAPHY_DIR holds whole-brain tractography, 5TT/ACT, TractSeg
# bundle segmentations, per-tract .tck files, and tractometry stats.
# This is fixed to OUTPUT_DIR (the folder the user entered at the top)
# and used consistently from Step 14 onward.
TRACTOGRAPHY_DIR="$OUTPUT_DIR"
mkdir -p "$TRACTOGRAPHY_DIR"


# ============================================================
# STEP 1 — DICOM → NIFTI
# ============================================================
echo ""
echo "Step 1: DICOM to NIFTI (dcm2niix)"
echo "----------------------------------"

# Check if NIFTI files already exist in output dir
if ls "$OUTPUT_DIR"/*.nii.gz 1>/dev/null 2>&1 || ls "$OUTPUT_DIR"/*.nii 1>/dev/null 2>&1; then
    echo "Skipping Step 1: NIFTI files already exist in $OUTPUT_DIR"
else
    echo " Input DICOM: $INPUT_DICOM"
    echo " Output Dir:  $OUTPUT_DIR"
    read -rp "Press Enter to continue or Ctrl+C to cancel..." _
    dcm2niix -z y -o "$OUTPUT_DIR" "$INPUT_DICOM"
    echo "Complete: dcm2niix"
fi


# ============================================================
# STEP 2 — MRCONVERT (NIFTI + bvec/bval → .mif)
# ============================================================
echo ""
echo "Step 2: mrconvert NIFTI + Bvec + Bval"
echo "--------------------------------------"

read -rp "Enter .nii or .nii.gz path: " DWI_NIFTI
read -rp "Enter .bvec path: " BVEC
read -rp "Enter .bval path: " BVAL
read -rp "Enter output .mif path (include filename): " DWI_MIF

if [[ -z "$DWI_NIFTI" || -z "$BVEC" || -z "$BVAL" || -z "$DWI_MIF" ]]; then
    echo "Error: All paths required."
    exit 1
fi

if [[ ! -f "$DWI_NIFTI" ]]; then echo "Error: NIFTI not found: $DWI_NIFTI"; exit 1; fi
if [[ ! -f "$BVEC" ]];      then echo "Error: Bvec not found: $BVEC";       exit 1; fi
if [[ ! -f "$BVAL" ]];      then echo "Error: Bval not found: $BVAL";       exit 1; fi

OUTDIR="$(dirname "$DWI_MIF")"
mkdir -p "$OUTDIR"
DWI_DIR="$OUTDIR"   # permanent — never reassigned again after this point

if [[ -f "$DWI_MIF" ]]; then
    echo "Skipping Step 2: $DWI_MIF already exists"
else
    echo " NIFTI:  $DWI_NIFTI"
    echo " Bvec:   $BVEC"
    echo " Bval:   $BVAL"
    echo " Output: $DWI_MIF"
    read -rp "Press Enter to run mrconvert or CTRL+C to cancel..." _
    mrconvert "$DWI_NIFTI" "$DWI_MIF" -fslgrad "$BVEC" "$BVAL"
    echo "Complete: mrconvert"
fi


# ============================================================
# STEP 3 — GRADIENT QC
# ============================================================
echo ""
echo "Step 3: Gradient QC"
echo "-------------------"

GRADIENT_TXT="${DWI_MIF%.mif}_gradientchecked.txt"
DWI_MIF_GC="${DWI_MIF%.mif}_gradientchecked.mif"

if [[ -f "$DWI_MIF_GC" ]]; then
    echo "Skipping Step 3: $DWI_MIF_GC already exists"
else
    echo " Input:  $DWI_MIF"
    echo " Output: $GRADIENT_TXT"
    read -rp "Press Enter to run dwigradcheck or CTRL+C to cancel..." _
    dwigradcheck "$DWI_MIF" -export_grad_mrtrix "$GRADIENT_TXT"
    echo "Applying corrected gradients..."
    read -rp "Press Enter to write corrected .mif or CTRL+C to cancel..." _
    mrconvert "$DWI_MIF" "$DWI_MIF_GC" -grad "$GRADIENT_TXT"
    echo "Complete: Gradient QC"
    echo " Output: $DWI_MIF_GC"
fi


# ============================================================
# STEP 4 — DENOISING
# ============================================================
echo ""
echo "Step 4: Denoising"
echo "-----------------"

DWI_MIF="$DWI_MIF_GC"
DWI_DENOISED="${DWI_MIF%.mif}_denoised.mif"
NOISEMAP="${DWI_MIF%.mif}_noisemap.mif"

if [[ -f "$DWI_DENOISED" ]]; then
    echo "Skipping Step 4: $DWI_DENOISED already exists"
else
    dwidenoise "$DWI_MIF" "$DWI_DENOISED" -noise "$NOISEMAP"
    echo "Complete: Denoising"
    echo " Output: $DWI_DENOISED"
    echo " Noise:  $NOISEMAP"
fi


# ============================================================
# STEP 5 — DENOISE RESIDUAL MAP (QC)
# ============================================================
echo ""
echo "Step 5: Denoise Residual Map (QC)"
echo "---------------------------------"

RESIDUAL="${DWI_MIF%.mif}_denoise_residual.mif"

if [[ -f "$RESIDUAL" ]]; then
    echo "Skipping Step 5: $RESIDUAL already exists"
else
    mrcalc "$DWI_MIF" "$DWI_DENOISED" -subtract "$RESIDUAL"
    echo "Complete: Residual Map"
    echo " Output: $RESIDUAL"
fi


# ============================================================
# STEP 6 — DEGIBBS
# ============================================================
echo ""
echo "Step 6: Degibbs"
echo "---------------"

DWI_MIF="$DWI_DENOISED"
DWI_DEGIBBS="${DWI_MIF%.mif}_degibbs.mif"

if [[ -f "$DWI_DEGIBBS" ]]; then
    echo "Skipping Step 6: $DWI_DEGIBBS already exists"
else
    mrdegibbs "$DWI_MIF" "$DWI_DEGIBBS"
    echo "Complete: Degibbs"
    echo " Output: $DWI_DEGIBBS"
fi


# ============================================================
# STEP 7 — EDDY + MOTION CORRECTION (dwifslpreproc)
# ============================================================
echo ""
echo "Step 7: Eddy + Motion Correction"
echo "---------------------------------"

DWI_PREPROC="${DWI_DEGIBBS%.mif}_preproc.mif"

if [[ -f "$DWI_PREPROC" ]]; then
    echo "Skipping Step 7: $DWI_PREPROC already exists"
else
    read -rp "Press Enter to run dwifslpreproc or CTRL+C to cancel..." _
    dwifslpreproc "$DWI_DEGIBBS" "$DWI_PREPROC" \
        -rpe_none \
        -pe_dir PA \
        -readout_time 0.0334949
    echo "Complete: dwifslpreproc"
    echo " Output: $DWI_PREPROC"
fi


# ============================================================
# STEP 8 — BIAS CORRECTION
# ============================================================
echo ""
echo "Step 8: Bias Correction"
echo "-----------------------"

DWI_BIASCORR="${DWI_PREPROC%.mif}_biascorr.mif"
DWI_BIAS="${DWI_PREPROC%.mif}_bias.mif"

if [[ -f "$DWI_BIASCORR" ]]; then
    echo "Skipping Step 8: $DWI_BIASCORR already exists"
else
    dwibiascorrect ants "$DWI_PREPROC" "$DWI_BIASCORR" -bias "$DWI_BIAS"
    echo "Complete: Bias Correction"
    echo " Output: $DWI_BIASCORR"
fi


# ============================================================
# STEP 9 — BRAIN MASK
# ============================================================
echo ""
echo "Step 9: Brain Mask"
echo "------------------"

Brain_Mask="${DWI_BIASCORR%.mif}_brain_mask.mif"

if [[ -f "$Brain_Mask" ]]; then
    echo "Skipping Step 9: $Brain_Mask already exists"
else
    read -rp "Press Enter to run dwi2mask or CTRL+C to cancel..." _
    dwi2mask "$DWI_BIASCORR" "$Brain_Mask"
    echo "Complete: Brain Mask"
    echo " Output: $Brain_Mask"
fi


# ============================================================
# STEP 10 — RESPONSE FUNCTION ESTIMATION
# ============================================================
echo ""
echo "Step 10: Response Function Estimation"
echo "--------------------------------------"

WM_RF="$DWI_DIR/wm_rf.txt"
GM_RF="$DWI_DIR/gm_rf.txt"
CSF_RF="$DWI_DIR/csf_rf.txt"

if [[ -f "$WM_RF" && -f "$GM_RF" && -f "$CSF_RF" ]]; then
    echo "Skipping Step 10: Response function files already exist"
else
    read -rp "Press Enter to run dwi2response or CTRL+C to cancel..." _
    dwi2response dhollander "$DWI_BIASCORR" "$WM_RF" "$GM_RF" "$CSF_RF" -mask "$Brain_Mask" -force
    echo "Complete: Response Functions"
    echo " WM: $WM_RF  GM: $GM_RF  CSF: $CSF_RF"
fi


# ============================================================
# STEP 11 — FOD ESTIMATION (msmt_csd)
# ============================================================
echo ""
echo "Step 11: FOD Estimation (msmt_csd)"
echo "-----------------------------------"

WM_FOD="$DWI_DIR/wm_fod.mif"
GM_FOD="$DWI_DIR/gm_fod.mif"
CSF_FOD="$DWI_DIR/csf_fod.mif"

if [[ -f "$WM_FOD" && -f "$GM_FOD" && -f "$CSF_FOD" ]]; then
    echo "Skipping Step 11: FOD files already exist"
else
    read -rp "Press Enter to run dwi2fod or CTRL+C to cancel..." _
    dwi2fod msmt_csd "$DWI_BIASCORR" "$WM_RF" "$WM_FOD" "$GM_RF" "$GM_FOD" "$CSF_RF" "$CSF_FOD" -mask "$Brain_Mask" -force
    echo "Complete: FOD Estimation"
    echo " WM FOD: $WM_FOD"
fi


# ============================================================
# STEP 12 — INTENSITY NORMALISATION
# ============================================================
echo ""
echo "Step 12: Intensity Normalisation"
echo "---------------------------------"

WM_FOD_NORM="$DWI_DIR/wm_fod_norm.mif"
GM_FOD_NORM="$DWI_DIR/gm_fod_norm.mif"
CSF_FOD_NORM="$DWI_DIR/csf_fod_norm.mif"
NORM_USED="mtnormalise"

if [[ -f "$WM_FOD_NORM" && -f "$GM_FOD_NORM" && -f "$CSF_FOD_NORM" ]]; then
    echo "Skipping Step 12: Normalised FOD files already exist"
    NORM_USED=$(cat "$DWI_DIR/normalisation_status.txt" 2>/dev/null || echo "unknown")
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run mtnormalise or CTRL+C to cancel..." _

    if mtnormalise "$WM_FOD" "$WM_FOD_NORM" "$GM_FOD" "$GM_FOD_NORM" "$CSF_FOD" "$CSF_FOD_NORM" -mask "$Brain_Mask"; then
        WM_MIN=$(mrstats "$WM_FOD_NORM" -mask "$Brain_Mask" -output min 2>/dev/null | awk '{print $1}' || echo "0")
        NEG_CHECK=$(awk "BEGIN {print ($WM_MIN < 0) ? 1 : 0}")
        if [[ "$NEG_CHECK" -eq 1 ]]; then
            echo "WARNING: mtnormalise produced negative values — using unnormalized FODs"
            cp "$WM_FOD"  "$WM_FOD_NORM"
            cp "$GM_FOD"  "$GM_FOD_NORM"
            cp "$CSF_FOD" "$CSF_FOD_NORM"
            NORM_USED="unnormalized_fallback"
        fi
    else
        echo "WARNING: mtnormalise failed — using unnormalized FODs"
        cp "$WM_FOD"  "$WM_FOD_NORM"
        cp "$GM_FOD"  "$GM_FOD_NORM"
        cp "$CSF_FOD" "$CSF_FOD_NORM"
        NORM_USED="unnormalized_fallback"
    fi

    echo "$NORM_USED" > "$DWI_DIR/normalisation_status.txt"
    echo "Complete: Normalisation — status: $NORM_USED"
    echo " WM FOD: $WM_FOD_NORM"
fi


# ============================================================
# STEP 13 — DTI METRICS (FA, MD, AD, RD)
# ============================================================
echo ""
echo "Step 13: DTI Metrics (FA, MD, AD, RD)"
echo "--------------------------------------"

DT="$DWI_DIR/dt.mif"
FA="$DWI_DIR/fa.mif"
MD="$DWI_DIR/md.mif"
AD="$DWI_DIR/ad.mif"
RD="$DWI_DIR/rd.mif"

if [[ -f "$FA" && -f "$MD" && -f "$AD" && -f "$RD" ]]; then
    echo "Skipping Step 13: DTI metric files already exist"
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to fit tensors or CTRL+C to cancel..." _
    dwi2tensor "$DWI_BIASCORR" "$DT" -mask "$Brain_Mask" -force
    tensor2metric "$DT" -fa "$FA" -adc "$MD" -ad "$AD" -rd "$RD" -force
    echo "Complete: DTI Metrics"
    echo " FA: $FA  MD: $MD  AD: $AD  RD: $RD"
fi


# ============================================================
# STEP 14 — 5-TISSUE-TYPE IMAGE (ACT)
# ============================================================
echo ""
echo "Step 14: 5-Tissue-Type Image for ACT"
echo "-------------------------------------"

# --- FSL setup ---
if [[ -z "${FSLDIR:-}" ]]; then
    export FSLDIR=/home/salazarc/fsl
    source $FSLDIR/etc/fslconf/fsl.sh
    export PATH=$FSLDIR/bin:$PATH
fi
# -----------------

T1_MIF="$TRACTOGRAPHY_DIR/t1.mif"
FIVETT="$TRACTOGRAPHY_DIR/5tt.mif"
GMWMI="$TRACTOGRAPHY_DIR/gmwmi.mif"

if [[ -f "$FIVETT" && -f "$GMWMI" ]]; then
    echo "Skipping Step 14: 5tt.mif and gmwmi.mif already exist"
else
    if [[ -z "${T1:-}" ]]; then
        read -rp "Enter T1 image path (.nii or .nii.gz): " T1
    fi

    if [[ ! -f "$T1" ]]; then
        echo "Error: T1 not found: $T1"
        exit 1
    fi

    mrconvert "$T1" "$T1_MIF" -force
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run 5ttgen or CTRL+C to abort: "
    5ttgen fsl "$T1_MIF" "$FIVETT" -premasked -force
    5tt2gmwmi "$FIVETT" "$GMWMI" -force
    echo "Complete: 5TT + GMWMI"
    echo " 5TT: $FIVETT  GMWMI: $GMWMI"
fi


# ============================================================
# STEP 15 — WHOLE-BRAIN TRACTOGRAPHY
# ============================================================
echo ""
echo "Step 15: Whole-Brain Tractography"
echo "----------------------------------"

WHOLEBRAIN_TCK="$TRACTOGRAPHY_DIR/wholebrain.tck"

if [[ -f "$WHOLEBRAIN_TCK" ]]; then
    echo "Skipping Step 15: $WHOLEBRAIN_TCK already exists"
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run tckgen or CTRL+C to cancel..." _
    tckgen "$WM_FOD_NORM" "$WHOLEBRAIN_TCK" \
        -act "$FIVETT" \
        -seed_gmwmi "$GMWMI" \
        -select 10000000 \
        -maxlength 250 \
        -cutoff 0.06
    echo "Complete: Whole-Brain Tractography"
    echo " Output: $WHOLEBRAIN_TCK"
fi


# ============================================================
# STEP 16 — SIFT2
# ============================================================
echo ""
echo "Step 16: SIFT2 Streamline Weighting"
echo "-------------------------------------"

SIFT2_WEIGHTS="$TRACTOGRAPHY_DIR/sift2_weights.txt"

if [[ -f "$SIFT2_WEIGHTS" ]]; then
    echo "Skipping Step 16: $SIFT2_WEIGHTS already exists"
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run tcksift2 or CTRL+C to cancel..." _
    tcksift2 "$WHOLEBRAIN_TCK" "$WM_FOD_NORM" "$SIFT2_WEIGHTS" -act "$FIVETT"
    echo "Complete: SIFT2"
    echo " Weights: $SIFT2_WEIGHTS"
fi


# ============================================================
# STEP 17 — TRACTSEG: FULL WHITE MATTER BUNDLE SEGMENTATION
# ============================================================
echo ""
echo "Step 17: TractSeg Full White Matter Segmentation"
echo "---------------------------------------------------"
echo " Note: TractSeg must be installed (pip install TractSeg)"

TRACTSEG_DIR="$TRACTOGRAPHY_DIR/tractseg_output"
PEAKS="$TRACTOGRAPHY_DIR/peaks.nii.gz"

# Locate sh2peaks - prefer PATH, fall back to known install
SH2PEAKS_BIN="$(command -v sh2peaks || echo /home/imran/miniconda3/envs/mrtrix/bin/sh2peaks)"

if [[ -d "$TRACTSEG_DIR/bundle_segmentations" && -f "$PEAKS" ]]; then
    echo "Skipping Step 17: TractSeg output already exists"
else
    mkdir -p "$TRACTSEG_DIR"
    "$SH2PEAKS_BIN" "$WM_FOD_NORM" "$PEAKS" -num 3 -force
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run TractSeg or CTRL+C to cancel..." _
    # Default TractSeg run covers all major WM bundles (no -bundle flag = full set of ~72 tracts)
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type tract_segmentation
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type endings_segmentation
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type TOM
    echo "Complete: TractSeg"
    echo " Output: $TRACTSEG_DIR/bundle_segmentations/"
fi

# Build the list of all tracts TractSeg produced, by reading the bundle_segmentations folder
TRACT_LIST_FILE="$TRACTOGRAPHY_DIR/tract_list.txt"
find "$TRACTSEG_DIR/bundle_segmentations" -name "*.nii.gz" -exec basename {} .nii.gz \; | sort > "$TRACT_LIST_FILE"
NUM_TRACTS=$(wc -l < "$TRACT_LIST_FILE")
echo " Found $NUM_TRACTS white matter tracts to process:"
cat "$TRACT_LIST_FILE"


# ============================================================
# STEP 18 — TRACTOGRAPHY FOR EVERY WHITE MATTER TRACT
# ============================================================
echo ""
echo "Step 18: Tractography for All WM Tracts"
echo "-----------------------------------------"

TRACTS_TCK_DIR="$TRACTOGRAPHY_DIR/tracts_tck"
mkdir -p "$TRACTS_TCK_DIR"

while IFS= read -r TRACT_NAME; do
    TRACT_MASK="$TRACTSEG_DIR/bundle_segmentations/${TRACT_NAME}.nii.gz"
    TRACT_TCK="$TRACTS_TCK_DIR/${TRACT_NAME}.tck"

    if [[ -f "$TRACT_TCK" ]]; then
        echo " Skipping $TRACT_NAME: already exists"
        continue
    fi

    if [[ ! -f "$TRACT_MASK" ]]; then
        echo " WARNING: mask not found for $TRACT_NAME, skipping"
        continue
    fi

    echo " Generating tract: $TRACT_NAME"
    tckgen "$WM_FOD_NORM" "$TRACT_TCK" \
        -act "$FIVETT" \
        -seed_image "$TRACT_MASK" \
        -mask "$TRACT_MASK" \
        -select 2000 \
        -maxlength 250 \
        -cutoff 0.06 \
        -force \
        -quiet < /dev/null
done < "$TRACT_LIST_FILE"

echo "Complete: Tractography for all WM tracts"
echo " Output directory: $TRACTS_TCK_DIR"


# ============================================================
# STEP 19 — RESAMPLE ALL TRACTS TO UNIFORM NODE COUNT
# ============================================================
echo ""
echo "Step 19: Resample All Tracts"
echo "------------------------------"

TRACTS_RESAMPLED_DIR="$TRACTOGRAPHY_DIR/tracts_resampled"
mkdir -p "$TRACTS_RESAMPLED_DIR"

while IFS= read -r TRACT_NAME; do
    TRACT_TCK="$TRACTS_TCK_DIR/${TRACT_NAME}.tck"
    TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/${TRACT_NAME}_resampled.tck"

    if [[ -f "$TRACT_RESAMPLED" ]]; then
        echo " Skipping $TRACT_NAME: already resampled"
        continue
    fi

    if [[ ! -f "$TRACT_TCK" ]]; then
        echo " WARNING: tck not found for $TRACT_NAME, skipping resample"
        continue
    fi

    tckresample "$TRACT_TCK" "$TRACT_RESAMPLED" -num_points 100 -force -quiet < /dev/null
done < "$TRACT_LIST_FILE"

echo "Complete: Resampling for all WM tracts"
echo " Output directory: $TRACTS_RESAMPLED_DIR"


# ============================================================
# STEP 20 — TRACTOMETRY: SAMPLE FA/MD/AD/RD ALONG EVERY TRACT
# (loop-free: each tract is its own explicit block — no shared
#  file descriptor, nothing for an MRtrix subprocess to disrupt)
# ============================================================
echo ""
echo "Step 20: Tractometry - Sample FA/MD/AD/RD Along All Tracts"
echo "--------------------------------------------------------------"

STATS_DIR="$TRACTOGRAPHY_DIR/tract_stats"
mkdir -p "$STATS_DIR"
SUMMARY_CSV="$TRACTOGRAPHY_DIR/tractometry_summary.csv"
echo "tract,mean_FA,mean_MD,mean_AD,mean_RD,n_streamlines" > "$SUMMARY_CSV"

echo " Processing: AF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/AF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/AF_left.tck"
FA_TXT="$STATS_DIR/AF_left_fa.txt"
MD_TXT="$STATS_DIR/AF_left_md.txt"
AD_TXT="$STATS_DIR/AF_left_ad.txt"
RD_TXT="$STATS_DIR/AF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "AF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for AF_left, skipping"
fi

echo " Processing: AF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/AF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/AF_right.tck"
FA_TXT="$STATS_DIR/AF_right_fa.txt"
MD_TXT="$STATS_DIR/AF_right_md.txt"
AD_TXT="$STATS_DIR/AF_right_ad.txt"
RD_TXT="$STATS_DIR/AF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "AF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for AF_right, skipping"
fi

echo " Processing: ATR_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ATR_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ATR_left.tck"
FA_TXT="$STATS_DIR/ATR_left_fa.txt"
MD_TXT="$STATS_DIR/ATR_left_md.txt"
AD_TXT="$STATS_DIR/ATR_left_ad.txt"
RD_TXT="$STATS_DIR/ATR_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ATR_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ATR_left, skipping"
fi

echo " Processing: ATR_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ATR_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ATR_right.tck"
FA_TXT="$STATS_DIR/ATR_right_fa.txt"
MD_TXT="$STATS_DIR/ATR_right_md.txt"
AD_TXT="$STATS_DIR/ATR_right_ad.txt"
RD_TXT="$STATS_DIR/ATR_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ATR_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ATR_right, skipping"
fi

echo " Processing: CA"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CA_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CA.tck"
FA_TXT="$STATS_DIR/CA_fa.txt"
MD_TXT="$STATS_DIR/CA_md.txt"
AD_TXT="$STATS_DIR/CA_ad.txt"
RD_TXT="$STATS_DIR/CA_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CA,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CA, skipping"
fi

echo " Processing: CC"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC.tck"
FA_TXT="$STATS_DIR/CC_fa.txt"
MD_TXT="$STATS_DIR/CC_md.txt"
AD_TXT="$STATS_DIR/CC_ad.txt"
RD_TXT="$STATS_DIR/CC_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC, skipping"
fi

echo " Processing: CC_1"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_1_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_1.tck"
FA_TXT="$STATS_DIR/CC_1_fa.txt"
MD_TXT="$STATS_DIR/CC_1_md.txt"
AD_TXT="$STATS_DIR/CC_1_ad.txt"
RD_TXT="$STATS_DIR/CC_1_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_1,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_1, skipping"
fi

echo " Processing: CC_2"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_2_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_2.tck"
FA_TXT="$STATS_DIR/CC_2_fa.txt"
MD_TXT="$STATS_DIR/CC_2_md.txt"
AD_TXT="$STATS_DIR/CC_2_ad.txt"
RD_TXT="$STATS_DIR/CC_2_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_2,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_2, skipping"
fi

echo " Processing: CC_3"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_3_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_3.tck"
FA_TXT="$STATS_DIR/CC_3_fa.txt"
MD_TXT="$STATS_DIR/CC_3_md.txt"
AD_TXT="$STATS_DIR/CC_3_ad.txt"
RD_TXT="$STATS_DIR/CC_3_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_3,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_3, skipping"
fi

echo " Processing: CC_4"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_4_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_4.tck"
FA_TXT="$STATS_DIR/CC_4_fa.txt"
MD_TXT="$STATS_DIR/CC_4_md.txt"
AD_TXT="$STATS_DIR/CC_4_ad.txt"
RD_TXT="$STATS_DIR/CC_4_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_4,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_4, skipping"
fi

echo " Processing: CC_5"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_5_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_5.tck"
FA_TXT="$STATS_DIR/CC_5_fa.txt"
MD_TXT="$STATS_DIR/CC_5_md.txt"
AD_TXT="$STATS_DIR/CC_5_ad.txt"
RD_TXT="$STATS_DIR/CC_5_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_5,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_5, skipping"
fi

echo " Processing: CC_6"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_6_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_6.tck"
FA_TXT="$STATS_DIR/CC_6_fa.txt"
MD_TXT="$STATS_DIR/CC_6_md.txt"
AD_TXT="$STATS_DIR/CC_6_ad.txt"
RD_TXT="$STATS_DIR/CC_6_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_6,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_6, skipping"
fi

echo " Processing: CC_7"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CC_7_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CC_7.tck"
FA_TXT="$STATS_DIR/CC_7_fa.txt"
MD_TXT="$STATS_DIR/CC_7_md.txt"
AD_TXT="$STATS_DIR/CC_7_ad.txt"
RD_TXT="$STATS_DIR/CC_7_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CC_7,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CC_7, skipping"
fi

echo " Processing: CG_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CG_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CG_left.tck"
FA_TXT="$STATS_DIR/CG_left_fa.txt"
MD_TXT="$STATS_DIR/CG_left_md.txt"
AD_TXT="$STATS_DIR/CG_left_ad.txt"
RD_TXT="$STATS_DIR/CG_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CG_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CG_left, skipping"
fi

echo " Processing: CG_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CG_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CG_right.tck"
FA_TXT="$STATS_DIR/CG_right_fa.txt"
MD_TXT="$STATS_DIR/CG_right_md.txt"
AD_TXT="$STATS_DIR/CG_right_ad.txt"
RD_TXT="$STATS_DIR/CG_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CG_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CG_right, skipping"
fi

echo " Processing: CST_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CST_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CST_left.tck"
FA_TXT="$STATS_DIR/CST_left_fa.txt"
MD_TXT="$STATS_DIR/CST_left_md.txt"
AD_TXT="$STATS_DIR/CST_left_ad.txt"
RD_TXT="$STATS_DIR/CST_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CST_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CST_left, skipping"
fi

echo " Processing: CST_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/CST_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/CST_right.tck"
FA_TXT="$STATS_DIR/CST_right_fa.txt"
MD_TXT="$STATS_DIR/CST_right_md.txt"
AD_TXT="$STATS_DIR/CST_right_ad.txt"
RD_TXT="$STATS_DIR/CST_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "CST_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for CST_right, skipping"
fi

echo " Processing: FPT_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/FPT_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/FPT_left.tck"
FA_TXT="$STATS_DIR/FPT_left_fa.txt"
MD_TXT="$STATS_DIR/FPT_left_md.txt"
AD_TXT="$STATS_DIR/FPT_left_ad.txt"
RD_TXT="$STATS_DIR/FPT_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "FPT_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for FPT_left, skipping"
fi

echo " Processing: FPT_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/FPT_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/FPT_right.tck"
FA_TXT="$STATS_DIR/FPT_right_fa.txt"
MD_TXT="$STATS_DIR/FPT_right_md.txt"
AD_TXT="$STATS_DIR/FPT_right_ad.txt"
RD_TXT="$STATS_DIR/FPT_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "FPT_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for FPT_right, skipping"
fi

echo " Processing: FX_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/FX_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/FX_left.tck"
FA_TXT="$STATS_DIR/FX_left_fa.txt"
MD_TXT="$STATS_DIR/FX_left_md.txt"
AD_TXT="$STATS_DIR/FX_left_ad.txt"
RD_TXT="$STATS_DIR/FX_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "FX_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for FX_left, skipping"
fi

echo " Processing: FX_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/FX_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/FX_right.tck"
FA_TXT="$STATS_DIR/FX_right_fa.txt"
MD_TXT="$STATS_DIR/FX_right_md.txt"
AD_TXT="$STATS_DIR/FX_right_ad.txt"
RD_TXT="$STATS_DIR/FX_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "FX_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for FX_right, skipping"
fi

echo " Processing: ICP_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ICP_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ICP_left.tck"
FA_TXT="$STATS_DIR/ICP_left_fa.txt"
MD_TXT="$STATS_DIR/ICP_left_md.txt"
AD_TXT="$STATS_DIR/ICP_left_ad.txt"
RD_TXT="$STATS_DIR/ICP_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ICP_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ICP_left, skipping"
fi

echo " Processing: ICP_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ICP_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ICP_right.tck"
FA_TXT="$STATS_DIR/ICP_right_fa.txt"
MD_TXT="$STATS_DIR/ICP_right_md.txt"
AD_TXT="$STATS_DIR/ICP_right_ad.txt"
RD_TXT="$STATS_DIR/ICP_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ICP_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ICP_right, skipping"
fi

echo " Processing: IFO_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/IFO_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/IFO_left.tck"
FA_TXT="$STATS_DIR/IFO_left_fa.txt"
MD_TXT="$STATS_DIR/IFO_left_md.txt"
AD_TXT="$STATS_DIR/IFO_left_ad.txt"
RD_TXT="$STATS_DIR/IFO_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "IFO_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for IFO_left, skipping"
fi

echo " Processing: IFO_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/IFO_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/IFO_right.tck"
FA_TXT="$STATS_DIR/IFO_right_fa.txt"
MD_TXT="$STATS_DIR/IFO_right_md.txt"
AD_TXT="$STATS_DIR/IFO_right_ad.txt"
RD_TXT="$STATS_DIR/IFO_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "IFO_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for IFO_right, skipping"
fi

echo " Processing: ILF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ILF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ILF_left.tck"
FA_TXT="$STATS_DIR/ILF_left_fa.txt"
MD_TXT="$STATS_DIR/ILF_left_md.txt"
AD_TXT="$STATS_DIR/ILF_left_ad.txt"
RD_TXT="$STATS_DIR/ILF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ILF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ILF_left, skipping"
fi

echo " Processing: ILF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ILF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ILF_right.tck"
FA_TXT="$STATS_DIR/ILF_right_fa.txt"
MD_TXT="$STATS_DIR/ILF_right_md.txt"
AD_TXT="$STATS_DIR/ILF_right_ad.txt"
RD_TXT="$STATS_DIR/ILF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ILF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ILF_right, skipping"
fi

echo " Processing: MCP"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/MCP_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/MCP.tck"
FA_TXT="$STATS_DIR/MCP_fa.txt"
MD_TXT="$STATS_DIR/MCP_md.txt"
AD_TXT="$STATS_DIR/MCP_ad.txt"
RD_TXT="$STATS_DIR/MCP_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "MCP,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for MCP, skipping"
fi

echo " Processing: MLF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/MLF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/MLF_left.tck"
FA_TXT="$STATS_DIR/MLF_left_fa.txt"
MD_TXT="$STATS_DIR/MLF_left_md.txt"
AD_TXT="$STATS_DIR/MLF_left_ad.txt"
RD_TXT="$STATS_DIR/MLF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "MLF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for MLF_left, skipping"
fi

echo " Processing: MLF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/MLF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/MLF_right.tck"
FA_TXT="$STATS_DIR/MLF_right_fa.txt"
MD_TXT="$STATS_DIR/MLF_right_md.txt"
AD_TXT="$STATS_DIR/MLF_right_ad.txt"
RD_TXT="$STATS_DIR/MLF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "MLF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for MLF_right, skipping"
fi

echo " Processing: OR_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/OR_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/OR_left.tck"
FA_TXT="$STATS_DIR/OR_left_fa.txt"
MD_TXT="$STATS_DIR/OR_left_md.txt"
AD_TXT="$STATS_DIR/OR_left_ad.txt"
RD_TXT="$STATS_DIR/OR_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "OR_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for OR_left, skipping"
fi

echo " Processing: OR_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/OR_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/OR_right.tck"
FA_TXT="$STATS_DIR/OR_right_fa.txt"
MD_TXT="$STATS_DIR/OR_right_md.txt"
AD_TXT="$STATS_DIR/OR_right_ad.txt"
RD_TXT="$STATS_DIR/OR_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "OR_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for OR_right, skipping"
fi

echo " Processing: POPT_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/POPT_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/POPT_left.tck"
FA_TXT="$STATS_DIR/POPT_left_fa.txt"
MD_TXT="$STATS_DIR/POPT_left_md.txt"
AD_TXT="$STATS_DIR/POPT_left_ad.txt"
RD_TXT="$STATS_DIR/POPT_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "POPT_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for POPT_left, skipping"
fi

echo " Processing: POPT_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/POPT_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/POPT_right.tck"
FA_TXT="$STATS_DIR/POPT_right_fa.txt"
MD_TXT="$STATS_DIR/POPT_right_md.txt"
AD_TXT="$STATS_DIR/POPT_right_ad.txt"
RD_TXT="$STATS_DIR/POPT_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "POPT_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for POPT_right, skipping"
fi

echo " Processing: SCP_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SCP_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SCP_left.tck"
FA_TXT="$STATS_DIR/SCP_left_fa.txt"
MD_TXT="$STATS_DIR/SCP_left_md.txt"
AD_TXT="$STATS_DIR/SCP_left_ad.txt"
RD_TXT="$STATS_DIR/SCP_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SCP_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SCP_left, skipping"
fi

echo " Processing: SCP_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SCP_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SCP_right.tck"
FA_TXT="$STATS_DIR/SCP_right_fa.txt"
MD_TXT="$STATS_DIR/SCP_right_md.txt"
AD_TXT="$STATS_DIR/SCP_right_ad.txt"
RD_TXT="$STATS_DIR/SCP_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SCP_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SCP_right, skipping"
fi

echo " Processing: SLF_III_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_III_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_III_left.tck"
FA_TXT="$STATS_DIR/SLF_III_left_fa.txt"
MD_TXT="$STATS_DIR/SLF_III_left_md.txt"
AD_TXT="$STATS_DIR/SLF_III_left_ad.txt"
RD_TXT="$STATS_DIR/SLF_III_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_III_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_III_left, skipping"
fi

echo " Processing: SLF_III_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_III_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_III_right.tck"
FA_TXT="$STATS_DIR/SLF_III_right_fa.txt"
MD_TXT="$STATS_DIR/SLF_III_right_md.txt"
AD_TXT="$STATS_DIR/SLF_III_right_ad.txt"
RD_TXT="$STATS_DIR/SLF_III_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_III_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_III_right, skipping"
fi

echo " Processing: SLF_II_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_II_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_II_left.tck"
FA_TXT="$STATS_DIR/SLF_II_left_fa.txt"
MD_TXT="$STATS_DIR/SLF_II_left_md.txt"
AD_TXT="$STATS_DIR/SLF_II_left_ad.txt"
RD_TXT="$STATS_DIR/SLF_II_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_II_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_II_left, skipping"
fi

echo " Processing: SLF_II_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_II_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_II_right.tck"
FA_TXT="$STATS_DIR/SLF_II_right_fa.txt"
MD_TXT="$STATS_DIR/SLF_II_right_md.txt"
AD_TXT="$STATS_DIR/SLF_II_right_ad.txt"
RD_TXT="$STATS_DIR/SLF_II_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_II_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_II_right, skipping"
fi

echo " Processing: SLF_I_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_I_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_I_left.tck"
FA_TXT="$STATS_DIR/SLF_I_left_fa.txt"
MD_TXT="$STATS_DIR/SLF_I_left_md.txt"
AD_TXT="$STATS_DIR/SLF_I_left_ad.txt"
RD_TXT="$STATS_DIR/SLF_I_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_I_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_I_left, skipping"
fi

echo " Processing: SLF_I_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/SLF_I_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/SLF_I_right.tck"
FA_TXT="$STATS_DIR/SLF_I_right_fa.txt"
MD_TXT="$STATS_DIR/SLF_I_right_md.txt"
AD_TXT="$STATS_DIR/SLF_I_right_ad.txt"
RD_TXT="$STATS_DIR/SLF_I_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "SLF_I_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for SLF_I_right, skipping"
fi

echo " Processing: ST_FO_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_FO_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_FO_left.tck"
FA_TXT="$STATS_DIR/ST_FO_left_fa.txt"
MD_TXT="$STATS_DIR/ST_FO_left_md.txt"
AD_TXT="$STATS_DIR/ST_FO_left_ad.txt"
RD_TXT="$STATS_DIR/ST_FO_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_FO_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_FO_left, skipping"
fi

echo " Processing: ST_FO_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_FO_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_FO_right.tck"
FA_TXT="$STATS_DIR/ST_FO_right_fa.txt"
MD_TXT="$STATS_DIR/ST_FO_right_md.txt"
AD_TXT="$STATS_DIR/ST_FO_right_ad.txt"
RD_TXT="$STATS_DIR/ST_FO_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_FO_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_FO_right, skipping"
fi

echo " Processing: ST_OCC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_OCC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_OCC_left.tck"
FA_TXT="$STATS_DIR/ST_OCC_left_fa.txt"
MD_TXT="$STATS_DIR/ST_OCC_left_md.txt"
AD_TXT="$STATS_DIR/ST_OCC_left_ad.txt"
RD_TXT="$STATS_DIR/ST_OCC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_OCC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_OCC_left, skipping"
fi

echo " Processing: ST_OCC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_OCC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_OCC_right.tck"
FA_TXT="$STATS_DIR/ST_OCC_right_fa.txt"
MD_TXT="$STATS_DIR/ST_OCC_right_md.txt"
AD_TXT="$STATS_DIR/ST_OCC_right_ad.txt"
RD_TXT="$STATS_DIR/ST_OCC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_OCC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_OCC_right, skipping"
fi

echo " Processing: ST_PAR_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PAR_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PAR_left.tck"
FA_TXT="$STATS_DIR/ST_PAR_left_fa.txt"
MD_TXT="$STATS_DIR/ST_PAR_left_md.txt"
AD_TXT="$STATS_DIR/ST_PAR_left_ad.txt"
RD_TXT="$STATS_DIR/ST_PAR_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PAR_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PAR_left, skipping"
fi

echo " Processing: ST_PAR_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PAR_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PAR_right.tck"
FA_TXT="$STATS_DIR/ST_PAR_right_fa.txt"
MD_TXT="$STATS_DIR/ST_PAR_right_md.txt"
AD_TXT="$STATS_DIR/ST_PAR_right_ad.txt"
RD_TXT="$STATS_DIR/ST_PAR_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PAR_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PAR_right, skipping"
fi

echo " Processing: ST_POSTC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_POSTC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_POSTC_left.tck"
FA_TXT="$STATS_DIR/ST_POSTC_left_fa.txt"
MD_TXT="$STATS_DIR/ST_POSTC_left_md.txt"
AD_TXT="$STATS_DIR/ST_POSTC_left_ad.txt"
RD_TXT="$STATS_DIR/ST_POSTC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_POSTC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_POSTC_left, skipping"
fi

echo " Processing: ST_POSTC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_POSTC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_POSTC_right.tck"
FA_TXT="$STATS_DIR/ST_POSTC_right_fa.txt"
MD_TXT="$STATS_DIR/ST_POSTC_right_md.txt"
AD_TXT="$STATS_DIR/ST_POSTC_right_ad.txt"
RD_TXT="$STATS_DIR/ST_POSTC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_POSTC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_POSTC_right, skipping"
fi

echo " Processing: ST_PREC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREC_left.tck"
FA_TXT="$STATS_DIR/ST_PREC_left_fa.txt"
MD_TXT="$STATS_DIR/ST_PREC_left_md.txt"
AD_TXT="$STATS_DIR/ST_PREC_left_ad.txt"
RD_TXT="$STATS_DIR/ST_PREC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREC_left, skipping"
fi

echo " Processing: ST_PREC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREC_right.tck"
FA_TXT="$STATS_DIR/ST_PREC_right_fa.txt"
MD_TXT="$STATS_DIR/ST_PREC_right_md.txt"
AD_TXT="$STATS_DIR/ST_PREC_right_ad.txt"
RD_TXT="$STATS_DIR/ST_PREC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREC_right, skipping"
fi

echo " Processing: ST_PREF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREF_left.tck"
FA_TXT="$STATS_DIR/ST_PREF_left_fa.txt"
MD_TXT="$STATS_DIR/ST_PREF_left_md.txt"
AD_TXT="$STATS_DIR/ST_PREF_left_ad.txt"
RD_TXT="$STATS_DIR/ST_PREF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREF_left, skipping"
fi

echo " Processing: ST_PREF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREF_right.tck"
FA_TXT="$STATS_DIR/ST_PREF_right_fa.txt"
MD_TXT="$STATS_DIR/ST_PREF_right_md.txt"
AD_TXT="$STATS_DIR/ST_PREF_right_ad.txt"
RD_TXT="$STATS_DIR/ST_PREF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREF_right, skipping"
fi

echo " Processing: ST_PREM_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREM_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREM_left.tck"
FA_TXT="$STATS_DIR/ST_PREM_left_fa.txt"
MD_TXT="$STATS_DIR/ST_PREM_left_md.txt"
AD_TXT="$STATS_DIR/ST_PREM_left_ad.txt"
RD_TXT="$STATS_DIR/ST_PREM_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREM_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREM_left, skipping"
fi

echo " Processing: ST_PREM_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/ST_PREM_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/ST_PREM_right.tck"
FA_TXT="$STATS_DIR/ST_PREM_right_fa.txt"
MD_TXT="$STATS_DIR/ST_PREM_right_md.txt"
AD_TXT="$STATS_DIR/ST_PREM_right_ad.txt"
RD_TXT="$STATS_DIR/ST_PREM_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "ST_PREM_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for ST_PREM_right, skipping"
fi

echo " Processing: STR_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/STR_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/STR_left.tck"
FA_TXT="$STATS_DIR/STR_left_fa.txt"
MD_TXT="$STATS_DIR/STR_left_md.txt"
AD_TXT="$STATS_DIR/STR_left_ad.txt"
RD_TXT="$STATS_DIR/STR_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "STR_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for STR_left, skipping"
fi

echo " Processing: STR_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/STR_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/STR_right.tck"
FA_TXT="$STATS_DIR/STR_right_fa.txt"
MD_TXT="$STATS_DIR/STR_right_md.txt"
AD_TXT="$STATS_DIR/STR_right_ad.txt"
RD_TXT="$STATS_DIR/STR_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "STR_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for STR_right, skipping"
fi

echo " Processing: T_OCC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_OCC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_OCC_left.tck"
FA_TXT="$STATS_DIR/T_OCC_left_fa.txt"
MD_TXT="$STATS_DIR/T_OCC_left_md.txt"
AD_TXT="$STATS_DIR/T_OCC_left_ad.txt"
RD_TXT="$STATS_DIR/T_OCC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_OCC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_OCC_left, skipping"
fi

echo " Processing: T_OCC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_OCC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_OCC_right.tck"
FA_TXT="$STATS_DIR/T_OCC_right_fa.txt"
MD_TXT="$STATS_DIR/T_OCC_right_md.txt"
AD_TXT="$STATS_DIR/T_OCC_right_ad.txt"
RD_TXT="$STATS_DIR/T_OCC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_OCC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_OCC_right, skipping"
fi

echo " Processing: T_PAR_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PAR_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PAR_left.tck"
FA_TXT="$STATS_DIR/T_PAR_left_fa.txt"
MD_TXT="$STATS_DIR/T_PAR_left_md.txt"
AD_TXT="$STATS_DIR/T_PAR_left_ad.txt"
RD_TXT="$STATS_DIR/T_PAR_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PAR_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PAR_left, skipping"
fi

echo " Processing: T_PAR_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PAR_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PAR_right.tck"
FA_TXT="$STATS_DIR/T_PAR_right_fa.txt"
MD_TXT="$STATS_DIR/T_PAR_right_md.txt"
AD_TXT="$STATS_DIR/T_PAR_right_ad.txt"
RD_TXT="$STATS_DIR/T_PAR_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PAR_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PAR_right, skipping"
fi

echo " Processing: T_POSTC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_POSTC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_POSTC_left.tck"
FA_TXT="$STATS_DIR/T_POSTC_left_fa.txt"
MD_TXT="$STATS_DIR/T_POSTC_left_md.txt"
AD_TXT="$STATS_DIR/T_POSTC_left_ad.txt"
RD_TXT="$STATS_DIR/T_POSTC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_POSTC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_POSTC_left, skipping"
fi

echo " Processing: T_POSTC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_POSTC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_POSTC_right.tck"
FA_TXT="$STATS_DIR/T_POSTC_right_fa.txt"
MD_TXT="$STATS_DIR/T_POSTC_right_md.txt"
AD_TXT="$STATS_DIR/T_POSTC_right_ad.txt"
RD_TXT="$STATS_DIR/T_POSTC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_POSTC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_POSTC_right, skipping"
fi

echo " Processing: T_PREC_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREC_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREC_left.tck"
FA_TXT="$STATS_DIR/T_PREC_left_fa.txt"
MD_TXT="$STATS_DIR/T_PREC_left_md.txt"
AD_TXT="$STATS_DIR/T_PREC_left_ad.txt"
RD_TXT="$STATS_DIR/T_PREC_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREC_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREC_left, skipping"
fi

echo " Processing: T_PREC_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREC_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREC_right.tck"
FA_TXT="$STATS_DIR/T_PREC_right_fa.txt"
MD_TXT="$STATS_DIR/T_PREC_right_md.txt"
AD_TXT="$STATS_DIR/T_PREC_right_ad.txt"
RD_TXT="$STATS_DIR/T_PREC_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREC_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREC_right, skipping"
fi

echo " Processing: T_PREF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREF_left.tck"
FA_TXT="$STATS_DIR/T_PREF_left_fa.txt"
MD_TXT="$STATS_DIR/T_PREF_left_md.txt"
AD_TXT="$STATS_DIR/T_PREF_left_ad.txt"
RD_TXT="$STATS_DIR/T_PREF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREF_left, skipping"
fi

echo " Processing: T_PREF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREF_right.tck"
FA_TXT="$STATS_DIR/T_PREF_right_fa.txt"
MD_TXT="$STATS_DIR/T_PREF_right_md.txt"
AD_TXT="$STATS_DIR/T_PREF_right_ad.txt"
RD_TXT="$STATS_DIR/T_PREF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREF_right, skipping"
fi

echo " Processing: T_PREM_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREM_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREM_left.tck"
FA_TXT="$STATS_DIR/T_PREM_left_fa.txt"
MD_TXT="$STATS_DIR/T_PREM_left_md.txt"
AD_TXT="$STATS_DIR/T_PREM_left_ad.txt"
RD_TXT="$STATS_DIR/T_PREM_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREM_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREM_left, skipping"
fi

echo " Processing: T_PREM_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/T_PREM_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/T_PREM_right.tck"
FA_TXT="$STATS_DIR/T_PREM_right_fa.txt"
MD_TXT="$STATS_DIR/T_PREM_right_md.txt"
AD_TXT="$STATS_DIR/T_PREM_right_ad.txt"
RD_TXT="$STATS_DIR/T_PREM_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "T_PREM_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for T_PREM_right, skipping"
fi

echo " Processing: UF_left"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/UF_left_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/UF_left.tck"
FA_TXT="$STATS_DIR/UF_left_fa.txt"
MD_TXT="$STATS_DIR/UF_left_md.txt"
AD_TXT="$STATS_DIR/UF_left_ad.txt"
RD_TXT="$STATS_DIR/UF_left_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "UF_left,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for UF_left, skipping"
fi

echo " Processing: UF_right"
TRACT_RESAMPLED="$TRACTS_RESAMPLED_DIR/UF_right_resampled.tck"
TRACT_TCK="$TRACTS_TCK_DIR/UF_right.tck"
FA_TXT="$STATS_DIR/UF_right_fa.txt"
MD_TXT="$STATS_DIR/UF_right_md.txt"
AD_TXT="$STATS_DIR/UF_right_ad.txt"
RD_TXT="$STATS_DIR/UF_right_rd.txt"
if [[ -f "$TRACT_RESAMPLED" ]]; then
    tcksample "$TRACT_RESAMPLED" "$FA" "$FA_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$MD" "$MD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$AD" "$AD_TXT" -stat_tck mean -force -quiet
    tcksample "$TRACT_RESAMPLED" "$RD" "$RD_TXT" -stat_tck mean -force -quiet
    MEAN_FA=$(tr " " "\n" < "$FA_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_MD=$(tr " " "\n" < "$MD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_AD=$(tr " " "\n" < "$AD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    MEAN_RD=$(tr " " "\n" < "$RD_TXT" | awk '{s+=$1;c++} END{print (c>0)?s/c:"NA"}')
    N_STREAMLINES=$(tckinfo "$TRACT_TCK" 2>/dev/null | grep "^count:" | awk '{print $2}')
    echo "UF_right,$MEAN_FA,$MEAN_MD,$MEAN_AD,$MEAN_RD,$N_STREAMLINES" >> "$SUMMARY_CSV"
    echo "  -> FA=$MEAN_FA MD=$MEAN_MD AD=$MEAN_AD RD=$MEAN_RD N=$N_STREAMLINES"
else
    echo "  WARNING: resampled tck not found for UF_right, skipping"
fi

echo ""
echo "============================================================"
echo "Pipeline Complete."
echo " Tractometry summary for all white matter tracts saved to:"
echo "   $SUMMARY_CSV"
echo " Per-tract raw stat files saved to:"
echo "   $STATS_DIR/"
echo "============================================================"
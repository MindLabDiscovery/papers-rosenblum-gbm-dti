#!/usr/bin/env bash
set -euo pipefail
echo "MRtrix Full Pipeline - Ethan"
echo "----------------------------"

# ============================================================
# SETUP — Conda + ANTs
# ============================================================
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate ~/miniconda3/envs/mrtrix
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
OUTDIR="$OUTPUT_DIR"


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

WM_RF="$OUTDIR/wm_rf.txt"
GM_RF="$OUTDIR/gm_rf.txt"
CSF_RF="$OUTDIR/csf_rf.txt"

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

WM_FOD="$OUTDIR/wm_fod.mif"
GM_FOD="$OUTDIR/gm_fod.mif"
CSF_FOD="$OUTDIR/csf_fod.mif"

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

WM_FOD_NORM="$OUTDIR/wm_fod_norm.mif"
GM_FOD_NORM="$OUTDIR/gm_fod_norm.mif"
CSF_FOD_NORM="$OUTDIR/csf_fod_norm.mif"
NORM_USED="mtnormalise"

if [[ -f "$WM_FOD_NORM" && -f "$GM_FOD_NORM" && -f "$CSF_FOD_NORM" ]]; then
    echo "Skipping Step 12: Normalised FOD files already exist"
    NORM_USED=$(cat "$OUTDIR/normalisation_status.txt" 2>/dev/null || echo "unknown")
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

    echo "$NORM_USED" > "$OUTDIR/normalisation_status.txt"
    echo "Complete: Normalisation — status: $NORM_USED"
    echo " WM FOD: $WM_FOD_NORM"
fi


# ============================================================
# STEP 13 — DTI METRICS (FA, MD, AD, RD)
# ============================================================
echo ""
echo "Step 13: DTI Metrics (FA, MD, AD, RD)"
echo "--------------------------------------"

DT="$OUTDIR/dt.mif"
FA="$OUTDIR/fa.mif"
MD="$OUTDIR/md.mif"
AD="$OUTDIR/ad.mif"
RD="$OUTDIR/rd.mif"

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

OUTDIR="${OUTPUT_DIR}"
T1_MIF="$OUTDIR/t1.mif"
FIVETT="$OUTDIR/5tt.mif"
GMWMI="$OUTDIR/gmwmi.mif"

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

OUTDIR="${OUTPUT_DIR}"
WHOLEBRAIN_TCK="$OUTDIR/wholebrain.tck"

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

SIFT2_WEIGHTS="$OUTDIR/sift2_weights.txt"

if [[ -f "$SIFT2_WEIGHTS" ]]; then
    echo "Skipping Step 16: $SIFT2_WEIGHTS already exists"
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run tcksift2 or CTRL+C to cancel..." _
    tcksift2 "$WHOLEBRAIN_TCK" "$WM_FOD_NORM" "$SIFT2_WEIGHTS" -act "$FIVETT"
    echo "Complete: SIFT2"
    echo " Weights: $SIFT2_WEIGHTS"
fi


# ============================================================
# STEP 17 — TRACTSEG: CST SEGMENTATION
# ============================================================
echo ""
echo "Step 17: TractSeg CST Segmentation"
echo "------------------------------------"
echo " Note: TractSeg must be installed (pip install TractSeg)"

OUTDIR="${OUTPUT_DIR}"
TRACTSEG_DIR="$OUTDIR/tractseg_output"
PEAKS="$OUTDIR/peaks.nii.gz"

if [[ -d "$TRACTSEG_DIR/bundle_segmentations" && -f "$PEAKS" ]]; then
    echo "Skipping Step 17: TractSeg output already exists"
else
    mkdir -p "$TRACTSEG_DIR"
    /home/imran/miniconda3/envs/mrtrix/bin/sh2peaks "$WM_FOD_NORM" "$PEAKS" -num 3 -force
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run TractSeg or CTRL+C to cancel..." _
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type tract_segmentation
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type endings_segmentation
    TractSeg -i "$PEAKS" -o "$TRACTSEG_DIR" --output_type TOM
    echo "Complete: TractSeg"
    echo " Output: $TRACTSEG_DIR/bundle_segmentations/"
fi


# ============================================================
# STEP 18 — CST TRACTOGRAPHY (Left + Right)
# ============================================================
echo ""
echo "Step 18: CST Tractography (Left + Right)"
echo "-----------------------------------------"

LEFT_CST_TCK="$OUTDIR/left_cst.tck"
RIGHT_CST_TCK="$OUTDIR/right_cst.tck"

LEFT_CST_MASK="$TRACTSEG_DIR/bundle_segmentations/CST_left.nii.gz"
RIGHT_CST_MASK="$TRACTSEG_DIR/bundle_segmentations/CST_right.nii.gz"

if [[ -f "$LEFT_CST_TCK" && -f "$RIGHT_CST_TCK" ]]; then
    echo "Skipping Step 18: CST tck files already exist"
else
    [[ "${BATCH_MODE:-0}" == "0" ]] && read -rp "Press Enter to run CST tractography or CTRL+C to cancel..." _

    tckgen "$WM_FOD_NORM" "$LEFT_CST_TCK" \
        -act "$FIVETT" \
        -seed_image "$LEFT_CST_MASK" \
        -mask "$LEFT_CST_MASK" \
        -select 5000 \
        -maxlength 250 \
        -cutoff 0.06 \
        -force

    tckgen "$WM_FOD_NORM" "$RIGHT_CST_TCK" \
        -act "$FIVETT" \
        -seed_image "$RIGHT_CST_MASK" \
        -mask "$RIGHT_CST_MASK" \
        -select 5000 \
        -maxlength 250 \
        -cutoff 0.06 \
        -force

    echo "Complete: CST Tractography"
    echo " Left CST:  $LEFT_CST_TCK"
    echo " Right CST: $RIGHT_CST_TCK"
fi



# ============================================================
# STEP 19 — RESAMPLE TRACTS TO UNIFORM NODE COUNT
# ============================================================
echo ""
echo "Step 19: Resample Tracts"
echo "------------------------"

LEFT_CST_RESAMPLED="$OUTDIR/left_cst_resampled.tck"
RIGHT_CST_RESAMPLED="$OUTDIR/right_cst_resampled.tck"

if [[ -f "$LEFT_CST_RESAMPLED" && -f "$RIGHT_CST_RESAMPLED" ]]; then
    echo "Skipping Step 19: Resampled tck files already exist"
else
    tckresample "$LEFT_CST_TCK"  "$LEFT_CST_RESAMPLED"  -num_points 100 -force
    tckresample "$RIGHT_CST_TCK" "$RIGHT_CST_RESAMPLED" -num_points 100 -force
    echo "Complete: Resampling"
fi

# ============================================================
# STEP 20 — SAMPLE FA ALONG CST → OUTPUT TXT FILES
# ============================================================
echo ""
echo "Step 20: Sample FA Along CST"
echo "-----------------------------"

FA="/home/imran/Documents/MRTrix/307_Output_Mif/fa.mif"
LEFT_FA_TXT="$OUTDIR/left_cst_fa.txt"
RIGHT_FA_TXT="$OUTDIR/right_cst_fa.txt"

tcksample "$LEFT_CST_RESAMPLED"  "$FA" "$LEFT_FA_TXT"  -stat_tck mean -force
tcksample "$RIGHT_CST_RESAMPLED" "$FA" "$RIGHT_FA_TXT" -stat_tck mean -force

awk '{for(i=1;i<=NF;i++) {sum+=$i; count++}} END {print sum/count}' "$LEFT_FA_TXT"  > tmp_left.txt  && mv tmp_left.txt  "$LEFT_FA_TXT"
awk '{for(i=1;i<=NF;i++) {sum+=$i; count++}} END {print sum/count}' "$RIGHT_FA_TXT" > tmp_right.txt && mv tmp_right.txt "$RIGHT_FA_TXT"

echo ""
echo "============================================================"
echo "Pipeline Complete."
echo " Mean FA - Left CST:  $(cat $LEFT_FA_TXT)"
echo " Mean FA - Right CST: $(cat $RIGHT_FA_TXT)"
echo " Saved to:"
echo "   $LEFT_FA_TXT"
echo "   $RIGHT_FA_TXT"
echo "============================================================"

#!/usr/bin/env python3
"""
GBM Tractography Pipeline QC Script
=====================================
Runs quantitative checks at every stage of the MRtrix3 pipeline
and produces a PASS / WARN / FAIL report.

Usage:
    python3 gbm_pipeline_qc.py <subject_id>

    e.g.  python3 gbm_pipeline_qc.py 117

Assumes directory structure:
    MIF_DIR  = /home/rosenble/Documents/GBM_Images/MRTRIX_MIF/<subj>_MIF/
    OUT_DIR  = /home/rosenble/Documents/GBM_Images/Output/<subj>_Output/
    TRACT_DIR = /home/rosenble/Documents/GBM_Images/MRTRIX_MIF/<subj>_MIF/  (or OUT_DIR)

Edit the path constants at the top if your layout differs.
"""

import subprocess
import sys
import os
import re
from datetime import datetime

# ── Path constants ────────────────────────────────────────────────────────────
BASE_MIF  = "/home/rosenble/Documents/GBM_Images/MRTRIX_MIF"
BASE_OUT  = "/home/rosenble/Documents/GBM_Images/Output"

# ── Thresholds ────────────────────────────────────────────────────────────────
SNR_PASS        = 20.0
SNR_WARN        = 10.0
FA_MEAN_PASS    = 0.25
FA_MEAN_WARN    = 0.15
FA_MAX_PASS     = 0.60
FA_MAX_WARN     = 0.40
MD_MAX_NORMAL   = 0.004   # mm²/s  (values above this suggest CSF contamination)
WM_RESP_RATIO   = 3.0     # l=0 / l=2 for WM response; higher = more anisotropic
GMWMI_PASS      = 10000   # voxels
GMWMI_WARN      = 1000
TRACT_PASS      = 50000   # streamlines
TRACT_WARN      = 5000
FOD_AMP_MIN     = 0.05    # mean WM FOD l=0 amplitude
FOD_AMP_MAX     = 1.50

# ── Helpers ───────────────────────────────────────────────────────────────────
PASS = "✅ PASS"
WARN = "⚠️  WARN"
FAIL = "❌ FAIL"
SKIP = "⏭  SKIP"

results = []   # list of (stage, check, status, detail)

def run(cmd, capture=True):
    """Run a shell command; return (stdout, stderr, returncode)."""
    r = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
    return r.stdout.strip(), r.stderr.strip(), r.returncode

def log(stage, check, status, detail=""):
    results.append((stage, check, status, detail))
    # Live print so the user sees progress
    tag = status.split()[0] if " " in status else status
    print(f"  [{tag}] {check}: {detail}" if detail else f"  [{tag}] {check}")

def mrstats_mean(path, mask=None):
    """Return mean value of an image (optionally within a mask)."""
    cmd = f"mrstats {path} -output mean"
    if mask and os.path.exists(mask):
        cmd += f" -mask {mask}"
    out, err, rc = run(cmd)
    if rc != 0 or not out:
        return None
    try:
        return float(out.split()[0])
    except Exception:
        return None

def mrstats_max(path, mask=None):
    cmd = f"mrstats {path} -output max"
    if mask and os.path.exists(mask):
        cmd += f" -mask {mask}"
    out, err, rc = run(cmd)
    if rc != 0 or not out:
        return None
    try:
        return float(out.split()[0])
    except Exception:
        return None

def mrstats_count(path):
    """Count non-zero voxels."""
    cmd = f"mrstats {path} -output count"
    out, err, rc = run(cmd)
    if rc != 0 or not out:
        return None
    try:
        return int(float(out.split()[0]))
    except Exception:
        return None

def file_check(stage, label, path):
    """Check file exists and is non-empty; log result."""
    if os.path.exists(path) and os.path.getsize(path) > 0:
        log(stage, f"{label} exists", PASS, path)
        return True
    else:
        log(stage, f"{label} exists", FAIL, f"Missing: {path}")
        return False

def threshold(value, pass_val, warn_val, fmt=".4f", higher_is_better=True):
    """Return PASS/WARN/FAIL based on thresholds."""
    if value is None:
        return FAIL, "could not compute"
    detail = f"{value:{fmt}}"
    if higher_is_better:
        status = PASS if value >= pass_val else (WARN if value >= warn_val else FAIL)
    else:
        status = PASS if value <= pass_val else (WARN if value <= warn_val else FAIL)
    return status, detail

# ── Main QC function ──────────────────────────────────────────────────────────
def qc_subject(subj):
    mif_dir  = os.path.join(BASE_MIF, f"{subj}_MIF")
    out_dir  = os.path.join(BASE_OUT, f"{subj}_Output")

    # Common file paths — edit if your names differ
    dwi_raw       = os.path.join(mif_dir, "dwi.mif")
    dwi_prep      = os.path.join(mif_dir, "dwi_preprocessed.mif")
    noise_map     = os.path.join(mif_dir, "noise.mif")
    brain_mask    = os.path.join(mif_dir, "brain_mask.mif")
    wm_resp       = os.path.join(mif_dir, "wm.txt")
    gm_resp       = os.path.join(mif_dir, "gm.txt")
    csf_resp      = os.path.join(mif_dir, "csf.txt")
    wm_fod        = os.path.join(mif_dir, "wm_fod.mif")
    wm_fod_norm   = os.path.join(mif_dir, "wm_fod_norm.mif")
    fa            = os.path.join(mif_dir, "fa.mif")
    md            = os.path.join(mif_dir, "md.mif")
    ad            = os.path.join(mif_dir, "ad.mif")
    rd            = os.path.join(mif_dir, "rd.mif")
    ftt           = os.path.join(out_dir, "5tt.mif")
    gmwmi         = os.path.join(out_dir, "gmwmi.mif")
    # Tractography — try common names
    tck = None
    for name in ["tracks.tck", "wholebrain.tck", "tractogram.tck", "wb_tracks.tck"]:
        candidate = os.path.join(out_dir, name)
        if os.path.exists(candidate):
            tck = candidate
            break
        candidate = os.path.join(mif_dir, name)
        if os.path.exists(candidate):
            tck = candidate
            break

    print(f"\n{'='*60}")
    print(f"  QC REPORT — Subject {subj}")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"{'='*60}\n")

    # ── STEP 1: DWI file ──────────────────────────────────────────────────────
    print("STEP 1: Preprocessed DWI")
    print("-" * 40)

    # Prefer preprocessed; fall back to raw
    dwi_to_check = dwi_prep if os.path.exists(dwi_prep) else dwi_raw
    dwi_label    = "dwi_preprocessed.mif" if os.path.exists(dwi_prep) else "dwi.mif (raw)"

    if not file_check("DWI", dwi_label, dwi_to_check):
        print("  Cannot continue DWI checks without input file.\n")
    else:
        # Check b-values
        out, err, rc = run(f"mrinfo {dwi_to_check} -shell_bvalues")
        if rc == 0 and out:
            bvals = out.replace("\n", " ").strip()
            log("DWI", "b-values detected", PASS if bvals else FAIL, bvals)
        else:
            log("DWI", "b-values detected", WARN, "could not parse b-values")

        # Check number of volumes
        out, err, rc = run(f"mrinfo {dwi_to_check} -size")
        if rc == 0 and out:
            dims = out.strip().split()
            if len(dims) >= 4:
                nvols = dims[3]
                log("DWI", "number of volumes", PASS, f"{nvols} volumes")
            else:
                log("DWI", "number of volumes", WARN, f"unexpected dims: {out.strip()}")

        # Check voxel size
        out, err, rc = run(f"mrinfo {dwi_to_check} -vox")
        if rc == 0 and out:
            log("DWI", "voxel size", PASS, out.strip())

        # SNR from noise map
        if os.path.exists(noise_map) and os.path.exists(brain_mask):
            b0_tmp = "/tmp/b0_qc.mif"
            run(f"dwiextract {dwi_to_check} - -bzero | mrmath - mean {b0_tmp} -axis 3 -force")
            if os.path.exists(b0_tmp):
                b0_mean = mrstats_mean(b0_tmp, brain_mask)
                noise_mean = mrstats_mean(noise_map, brain_mask)
                if b0_mean and noise_mean and noise_mean > 0:
                    snr = b0_mean / noise_mean
                    status, detail = threshold(snr, SNR_PASS, SNR_WARN, ".1f")
                    log("DWI", "SNR (b0 / noise)", status, f"{detail}  (≥{SNR_PASS}=PASS, ≥{SNR_WARN}=WARN)")
                else:
                    log("DWI", "SNR (b0 / noise)", WARN, "could not compute SNR")
                run(f"rm -f {b0_tmp}")
        else:
            log("DWI", "SNR (b0 / noise)", SKIP, "noise map or brain mask not found")

    # ── STEP 2: Brain mask ────────────────────────────────────────────────────
    print("\nSTEP 2: Brain Mask")
    print("-" * 40)
    if file_check("Mask", "brain_mask.mif", brain_mask):
        count = mrstats_count(brain_mask)
        if count and count > 100000:
            log("Mask", "mask voxel count", PASS, f"{count:,} voxels")
        elif count and count > 20000:
            log("Mask", "mask voxel count", WARN, f"{count:,} voxels — may be too small")
        else:
            log("Mask", "mask voxel count", FAIL, f"{count} voxels — mask is likely wrong")

    # ── STEP 3: Response functions ────────────────────────────────────────────
    print("\nSTEP 3: Response Functions")
    print("-" * 40)

    for label, path in [("WM response", wm_resp), ("GM response", gm_resp), ("CSF response", csf_resp)]:
        file_check("Response", label, path)

    if os.path.exists(wm_resp):
        try:
            with open(wm_resp) as f:
                lines = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            if lines:
                coeffs = list(map(float, lines[0].split()))
                l0 = abs(coeffs[0]) if len(coeffs) > 0 else 0
                l2 = abs(coeffs[1]) if len(coeffs) > 1 else 0
                if l0 > 0 and l2 > 0:
                    ratio = l0 / l2
                    status = PASS if ratio >= WM_RESP_RATIO else (WARN if ratio >= 1.5 else FAIL)
                    log("Response", "WM anisotropy (l0/l2 ratio)", status,
                        f"{ratio:.2f}  (≥{WM_RESP_RATIO:.0f}=PASS) — higher means more anisotropic")
                elif l0 > 0:
                    log("Response", "WM anisotropy", PASS, f"l=0={l0:.4f} (single-shell, ratio N/A)")
                else:
                    log("Response", "WM anisotropy", FAIL, "l=0 coefficient is zero or missing")
        except Exception as e:
            log("Response", "WM response parse", WARN, f"could not parse: {e}")

    # ── STEP 4: FODs ─────────────────────────────────────────────────────────
    print("\nSTEP 4: FODs")
    print("-" * 40)

    # Determine which FOD to use
    fod_used = None
    normalized = False
    if os.path.exists(wm_fod_norm):
        file_check("FOD", "wm_fod_norm.mif (normalized)", wm_fod_norm)
        fod_used = wm_fod_norm
        normalized = True
    elif os.path.exists(wm_fod):
        log("FOD", "wm_fod_norm.mif", WARN, "normalized FOD missing — using unnormalized wm_fod.mif")
        file_check("FOD", "wm_fod.mif (unnormalized)", wm_fod)
        fod_used = wm_fod
    else:
        log("FOD", "WM FOD", FAIL, "neither wm_fod_norm.mif nor wm_fod.mif found")

    if fod_used and os.path.exists(brain_mask):
        # Extract l=0 volume (first volume = DC term = amplitude)
        fod0_tmp = "/tmp/fod_l0_qc.mif"
        run(f"mrconvert {fod_used} {fod0_tmp} -coord 3 0 -axes 0,1,2 -force")
        if os.path.exists(fod0_tmp):
            fod_mean = mrstats_mean(fod0_tmp, brain_mask)
            if fod_mean is not None:
                if FOD_AMP_MIN <= fod_mean <= FOD_AMP_MAX:
                    status = PASS
                elif fod_mean < FOD_AMP_MIN:
                    status = FAIL
                else:
                    status = WARN
                note = " — normalization target ~0.28" if normalized else " — unnormalized (no reference)"
                log("FOD", "Mean WM FOD amplitude (l=0)", status, f"{fod_mean:.4f}{note}")
            else:
                log("FOD", "Mean WM FOD amplitude", WARN, "could not compute")
            run(f"rm -f {fod0_tmp}")

    # ── STEP 5: DTI Metrics ───────────────────────────────────────────────────
    print("\nSTEP 5: DTI Metrics (FA, MD, AD, RD)")
    print("-" * 40)

    for label, path in [("fa.mif", fa), ("md.mif", md), ("ad.mif", ad), ("rd.mif", rd)]:
        file_check("DTI", label, path)

    if os.path.exists(fa) and os.path.exists(brain_mask):
        fa_mean = mrstats_mean(fa, brain_mask)
        fa_max  = mrstats_max(fa, brain_mask)

        s1, d1 = threshold(fa_mean, FA_MEAN_PASS, FA_MEAN_WARN, ".4f")
        log("DTI", f"Mean FA (brain mask)", s1,
            f"{d1}  (≥{FA_MEAN_PASS}=PASS, ≥{FA_MEAN_WARN}=WARN)")

        s2, d2 = threshold(fa_max, FA_MAX_PASS, FA_MAX_WARN, ".4f")
        log("DTI", f"Max FA (should reach >{FA_MAX_PASS} in WM)", s2,
            f"{d2}  — very low max FA suggests bad diffusion fit")

    if os.path.exists(md) and os.path.exists(brain_mask):
        md_mean = mrstats_mean(md, brain_mask)
        if md_mean is not None:
            # MD in brain should be ~0.001 mm²/s; values >> 0.001 suggest CSF contamination or scaling issues
            if 0.0002 < md_mean < 0.002:
                log("DTI", "Mean MD (brain mask)", PASS, f"{md_mean:.6f} mm²/s")
            elif md_mean >= 0.002:
                log("DTI", "Mean MD (brain mask)", WARN,
                    f"{md_mean:.6f} — elevated; possible CSF contamination or mask too loose")
            else:
                log("DTI", "Mean MD (brain mask)", WARN,
                    f"{md_mean:.6f} — very low; check units (may need ×10⁻³ scaling)")

    # ── STEP 6: 5TT ──────────────────────────────────────────────────────────
    print("\nSTEP 6: 5-Tissue-Type Image")
    print("-" * 40)

    if file_check("5TT", "5tt.mif", ftt):
        # Run 5ttcheck and count warnings
        out, err, rc = run(f"5ttcheck {ftt}")
        combined = out + err
        warning_lines = [l for l in combined.split("\n") if "WARNING" in l or "ERROR" in l]
        if not warning_lines:
            log("5TT", "5ttcheck", PASS, "no warnings")
        elif len(warning_lines) <= 2:
            log("5TT", "5ttcheck", WARN, f"{len(warning_lines)} warning(s): " + " | ".join(warning_lines[:2]))
        else:
            log("5TT", "5ttcheck", WARN, f"{len(warning_lines)} warnings — likely tumor/edema causing mis-classification")

        # Check WM volume (volume index 2 in 5TT = WM)
        wm_tmp = "/tmp/5tt_wm_qc.mif"
        run(f"mrconvert {ftt} {wm_tmp} -coord 3 2 -axes 0,1,2 -force")
        if os.path.exists(wm_tmp):
            wm_count = mrstats_count(wm_tmp)
            if wm_count and wm_count > 50000:
                log("5TT", "WM voxel count", PASS, f"{wm_count:,} voxels")
            elif wm_count and wm_count > 10000:
                log("5TT", "WM voxel count", WARN, f"{wm_count:,} voxels — seems low")
            else:
                log("5TT", "WM voxel count", FAIL, f"{wm_count} — 5TT WM map may be wrong")
            run(f"rm -f {wm_tmp}")

    # ── STEP 7: GMWMI ────────────────────────────────────────────────────────
    print("\nSTEP 7: GMWMI Seed Mask")
    print("-" * 40)

    if file_check("GMWMI", "gmwmi.mif", gmwmi):
        count = mrstats_count(gmwmi)
        if count:
            status = PASS if count >= GMWMI_PASS else (WARN if count >= GMWMI_WARN else FAIL)
            log("GMWMI", "seed voxel count", status,
                f"{count:,}  (≥{GMWMI_PASS:,}=PASS, ≥{GMWMI_WARN:,}=WARN) — low count = sparse seeding = empty tractogram")
        else:
            log("GMWMI", "seed voxel count", WARN, "could not compute")

    # ── STEP 8: Tractography ─────────────────────────────────────────────────
    print("\nSTEP 8: Tractography")
    print("-" * 40)

    if tck is None:
        log("Tractography", "tracks file", SKIP, "no .tck file found in expected locations")
    elif file_check("Tractography", os.path.basename(tck), tck):
        out, err, rc = run(f"tckinfo {tck}")
        if rc == 0:
            # Count
            m = re.search(r"count:\s*(\d+)", out + err)
            if m:
                count = int(m.group(1))
                status = PASS if count >= TRACT_PASS else (WARN if count >= TRACT_WARN else FAIL)
                log("Tractography", "streamline count", status,
                    f"{count:,}  (≥{TRACT_PASS:,}=PASS, ≥{TRACT_WARN:,}=WARN)")
            # Mean length
            m = re.search(r"mean streamline length.*?:\s*([\d.]+)", out + err, re.I)
            if m:
                length = float(m.group(1))
                if length > 50:
                    log("Tractography", "mean streamline length", PASS, f"{length:.1f} mm")
                elif length > 20:
                    log("Tractography", "mean streamline length", WARN, f"{length:.1f} mm — short; check ACT settings")
                else:
                    log("Tractography", "mean streamline length", FAIL, f"{length:.1f} mm — very short; likely premature termination")
        else:
            log("Tractography", "tckinfo", WARN, "could not read track file")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  SUMMARY — Subject {subj}")
    print(f"{'='*60}")

    n_pass = sum(1 for _, _, s, _ in results if "PASS" in s)
    n_warn = sum(1 for _, _, s, _ in results if "WARN" in s)
    n_fail = sum(1 for _, _, s, _ in results if "FAIL" in s)
    n_skip = sum(1 for _, _, s, _ in results if "SKIP" in s)

    print(f"  ✅ PASS: {n_pass}   ⚠️  WARN: {n_warn}   ❌ FAIL: {n_fail}   ⏭  SKIP: {n_skip}\n")

    if n_fail > 0:
        print("  FAILURES (action required):")
        for stage, check, status, detail in results:
            if "FAIL" in status:
                print(f"    [{stage}] {check}: {detail}")
        print()

    if n_warn > 0:
        print("  WARNINGS (review recommended):")
        for stage, check, status, detail in results:
            if "WARN" in status:
                print(f"    [{stage}] {check}: {detail}")
        print()

    # Overall verdict
    if n_fail == 0 and n_warn == 0:
        verdict = "✅ CLEAN — pipeline looks good for this subject"
    elif n_fail == 0:
        verdict = "⚠️  USABLE WITH CAVEATS — review warnings before including in analysis"
    elif n_fail <= 2:
        verdict = "❌ PROBLEMATIC — failures detected; results may be unreliable"
    else:
        verdict = "❌ DO NOT USE — multiple critical failures; data likely corrupted or pipeline broken"

    print(f"  Overall verdict: {verdict}")
    print(f"{'='*60}\n")

    # Write log file
    log_path = os.path.join(out_dir, f"qc_report_{subj}.txt")
    os.makedirs(out_dir, exist_ok=True)
    with open(log_path, "w") as f:
        f.write(f"QC Report — Subject {subj}\n")
        f.write(f"Run: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n")
        f.write(f"PASS: {n_pass}  WARN: {n_warn}  FAIL: {n_fail}  SKIP: {n_skip}\n")
        f.write(f"Verdict: {verdict}\n\n")
        for stage, check, status, detail in results:
            f.write(f"[{stage}] {status} — {check}: {detail}\n")
    print(f"  Log saved: {log_path}\n")


# ── Batch mode ────────────────────────────────────────────────────────────────
def batch_summary(subjects):
    """Print a one-line-per-subject summary across all subjects."""
    print(f"\n{'='*60}")
    print("  BATCH SUMMARY")
    print(f"{'='*60}")
    for subj in subjects:
        out_dir = os.path.join(BASE_OUT, f"{subj}_Output")
        log_path = os.path.join(out_dir, f"qc_report_{subj}.txt")
        if not os.path.exists(log_path):
            print(f"  {subj}: no report (run qc first)")
            continue
        with open(log_path) as f:
            content = f.read()
        verdict_line = next((l for l in content.split("\n") if "Verdict:" in l), "")
        counts_line  = next((l for l in content.split("\n") if "PASS:" in l), "")
        print(f"  {subj:>8} | {counts_line.strip()} | {verdict_line.replace('Verdict:','').strip()}")
    print()


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:  python3 gbm_pipeline_qc.py <subject_id> [subject_id2 ...]")
        print("        python3 gbm_pipeline_qc.py 117")
        print("        python3 gbm_pipeline_qc.py 117 118 119   (batch)")
        sys.exit(1)

    subjects = sys.argv[1:]
    for s in subjects:
        results = []   # reset per subject
        qc_subject(s)

    if len(subjects) > 1:
        batch_summary(subjects)

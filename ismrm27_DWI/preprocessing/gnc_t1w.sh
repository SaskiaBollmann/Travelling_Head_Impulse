#!/bin/bash
set -euo pipefail

SCRIPTNAME="$0"                 # collect the script name
STEPNAME="${SCRIPTNAME%.sh}"    # script name without extension
STEPCOUNT="$2"                  # step count
PREVIOUS_STEPNAME="$1"

echo ""
echo "========================================================================="
echo " ${STEPCOUNT}. ${SCRIPTNAME} "
echo "========================================================================="

# ==============================================================================
# Gradient nonlinearity correction
# -------------------------------
# This script applies teh gradient unwarping to a DWI dataset. The output
# is an unwarped DWI dataset, along with the voxelwise b-values and b-vectors
#
# Author:   Daniel Uher
# Email:    daniel.uher@ovgu.de
# Version:  0.1.0
# ==============================================================================


# ==============================================================================
# Source config and functions
# ==============================================================================
source pipeline.config
source pipeline.functions

INPUTDIR=${WORKDIR}/${PREVIOUS_STEPNAME}
echo " Input directory:  ${INPUTDIR}"

TMPWORKDIR=${WORKDIR}/${STEPNAME}
echo " Output directory: ${TMPWORKDIR}"

echo ""

# ==============================================================================
# Setup
# ==============================================================================

# if the directory exists, then remove it
if [[ -d ${TMPWORKDIR} ]]; then
    rm -rf ${TMPWORKDIR}
fi

# make a new one
mkdir -p ${TMPWORKDIR}


# ==============================================================================
# GNC
# ==============================================================================

echo ""
echo "  T1w Gradient non-linearity correction: "
echo "  ---------------------------------------"
# WARNING: similar as before in prefsl.sh, I am only resampling the
# masks and segmentations. In publication-ready approach, I would coregister
# the T1w to the mean b0 image via a rigid transform and then apply
# the resulting transform to the segmentation .nii file. For piloting
# DWI pipelines, this is sufficient, but in case of excessive motion or
# artifacts, it's always better to coregister

# unwarp the T1w image
gradient_unwarp.py \
    ${INITDIR}/t1w.nii \
    ${TMPWORKDIR}/t1w \
    --scanner ${SCANNER} \
    --interp_order 3

# mask the corrected T1w using synthstrip
fs mri_synthstrip \
	-i ${TMPWORKDIR}/t1w_gnc-corrected.nii \
	-m ${TMPWORKDIR}/t1w_gnc_brainmask.nii \
	-o ${TMPWORKDIR}/t1w_gnc_skullstripped.nii \
	-t ${NTHREADS}

cp ${TMPWORKDIR}/t1w_gnc-corrected.nii ${OUTDIR}/${FINAL_OUTPREFIX}_T1w.nii
cp ${TMPWORKDIR}/t1w_gnc_skullstripped.nii ${OUTDIR}/${FINAL_OUTPREFIX}_T1w_skullstripped.nii
cp ${TMPWORKDIR}/t1w_gnc_brainmask.nii ${OUTDIR}/${FINAL_OUTPREFIX}_T1w_brainmask.nii

# resample the mask file to the DWI
ants antsApplyTransforms -d 3 \
	-i ${TMPWORKDIR}/t1w_gnc_brainmask.nii \
	-r ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_meanb0.nii \
	-o ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_t1wbrainmask.nii \
	-n NearestNeighbor

# mask the corrected DWI mean b0 using synthstrip
fs mri_synthstrip \
	-i ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_meanb0.nii \
	-m ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_tmpbrainmask.nii \
	-t ${NTHREADS}

# combine the masks for increased robustness
fslmaths \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_tmpbrainmask.nii \
    -add ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_t1wbrainmask.nii \
    -bin \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_brainmask.nii

# save the final mask
cp ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_brainmask.nii \
   ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_brainmask.nii

# segment the corrected T1w
fs mri_synthseg \
	--i ${TMPWORKDIR}/t1w_gnc_skullstripped.nii \
	--o ${TMPWORKDIR}/t1w_gnc_skullstripped_seg.nii \
	--threads ${NTHREADS} \
    --parc --keepgeom --addctab

# resample the segmentation file to the DWI
ants antsApplyTransforms -d 3 \
	-i ${TMPWORKDIR}/t1w_gnc_skullstripped_seg.nii \
	-r ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_meanb0.nii \
	-o ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_seg.nii \
	-n NearestNeighbor

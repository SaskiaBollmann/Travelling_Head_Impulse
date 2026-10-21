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
# Preparation of data after denoising and degibbsing for TOPUP and EDDY
# -------------------------------
# This script concatenates, organizes, and establishes necessary formats
# for TOPUP and EDDY. This includes both the preset of DWI data and also
# the processing of the T1w anatomical data.
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
# Pre-FSL setup
# ==============================================================================
echo "  DWI pre-FSL setup: "
echo "  -------------------"

# get mean b=0
getb0 \
    ${INPUTDIR}/dwi_PA_denoise_degibbs.mif \
    ${TMPWORKDIR}/dwi_PA_denoise_degibbs_meanb0.nii

# skull strip mean b=0 image
fs mri_synthstrip \
    -i ${TMPWORKDIR}/dwi_PA_denoise_degibbs_meanb0.nii \
    -m ${TMPWORKDIR}/dwi_PA_denoise_degibbs_meanb0_brainmask.nii \
    -t 8

# skull strip echo 1 of B0 mapping seq
# fs mri_synthstrip \
#     -i ${B0e1} \
#     -m ${TMPWORKDIR}/e1_mask.nii \
#     -t 8

# skull strip echo 2 of B0 mapping seq
# fs mri_synthstrip \
#     -i ${B0e2} \
#     -m ${TMPWORKDIR}/e2_mask.nii \
#     -t 8

# add the masks and binarize
# fslmaths ${TMPWORKDIR}/e1_mask.nii -add ${TMPWORKDIR}/e2_mask.nii -bin \
#     ${TMPWORKDIR}/b0map_brainmask.nii

# apply mask to both e2 (better looking) and the B0 map
# fslmaths ${B0e2} -mas ${TMPWORKDIR}/b0map_brainmask.nii \
#     ${TMPWORKDIR}/e2_desc-masked.nii

# fslmaths ${B0} -mas ${TMPWORKDIR}/b0map_brainmask.nii \
#     ${TMPWORKDIR}/b0map_desc-masked.nii

# # prepare fieldmap via FSL
# fsl_prepare_fieldmap \
#     SIEMENS \
#     ${TMPWORKDIR}/b0map_desc-masked.nii \
#     ${TMPWORKDIR}/e2_desc-masked.nii \
#     ${TMPWORKDIR}/b0map_desc-masked-rad.nii \
#     ${B0_DELTA_TE}

# convert to Hz (divide by 2pi)
# fslmaths ${TMPWORKDIR}/b0map_desc-masked-rad.nii \
#     -div 6.2831853 \
#     ${TMPWORKDIR}/b0map_desc-masked-hz.nii

# coregister b0 map to mean b=0
# NOTE: limitation, no coregistration, consider doing coreg
# ants antsApplyTransforms -d 3 \
# 	-i ${TMPWORKDIR}/b0map_desc-masked-rad.nii \
# 	-r ${TMPWORKDIR}/dwi_PA_denoise_degibbs_meanb0.nii \
# 	-o ${TMPWORKDIR}/b0map_space-dwi_desc-masked-rad.nii

# convert .mif to .nii
mrtrix mrconvert \
    ${INPUTDIR}/dwi_PA_denoise_degibbs.mif \
    ${TMPWORKDIR}/dwi_PA_denoise_degibbs.nii \
    -export_grad_fsl ${TMPWORKDIR}/dwi_PA_denoise_degibbs.bvec \
                     ${TMPWORKDIR}/dwi_PA_denoise_degibbs.bval


# ==============================================================================
# Anatomical preprocessing
# ==============================================================================
echo "  T1w masking and coregistration to DWI: "
echo "  -------------------------------------------------"

# mask using synthstrip
fs mri_synthstrip \
	-i ${INITDIR}/t1w.nii \
	-m ${TMPWORKDIR}/t1w_brainmask.nii \
	-o ${TMPWORKDIR}/t1w_skullstripped.nii \
	-t ${NTHREADS}

# resample mask to DWI (use AP mean b0 as ref)
# NOTE: limitation, no coregistration, consider doing coreg
ants antsApplyTransforms -d 3 \
	-i ${TMPWORKDIR}/t1w_brainmask.nii \
	-r ${TMPWORKDIR}/dwi_PA_denoise_degibbs_meanb0.nii \
	-o ${TMPWORKDIR}/dwi_brainmask.nii \
	-n NearestNeighbor







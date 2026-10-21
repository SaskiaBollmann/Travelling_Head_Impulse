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
# Bias correction using MRtrix and FSL
# ----------------------------------------------------
# This script applies bias field correction to the DWI dataset using MRtrix
# dwibiascorrect and the FSL submodule. This step requires a well-aligned
# brainmask so I obtain one here using Freesurfer's synthstrip.
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
# Bias field correction
# ==============================================================================
echo "  Bias field correction "
echo "  ----------------------"

# make sure to use your own mask, because the default MRtrix behavior is
# to calculate one using the dwi2mask which in majority of cases fails
# on 7T data
# NOTE: MRtrix recommend the 'ants' version but I have had trouble running that
# on my computer for some reason. I still have to check which is better for
# our purposes specifically.

fs mri_synthstrip \
	-i ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0.nii \
	-m ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_tmpbrainmask.nii \
	-t ${NTHREADS}

mrtrix dwibiascorrect fsl \
    ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_gnc.mif \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_bias.mif \
    -mask ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0_tmpbrainmask.nii \
    -bias ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_biasfield.nii \
    -info

# get final mean b0 image
getb0 ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_bias.mif \
      ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_meanb0.nii

# output the final files
mrtrix mrconvert \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_bias.mif \
    ${OUTDIR}/${FINAL_OUTPREFIX}_DWI.nii \
    -export_grad_fsl ${OUTDIR}/${FINAL_OUTPREFIX}_DWI.bvec \
                     ${OUTDIR}/${FINAL_OUTPREFIX}_DWI.bval

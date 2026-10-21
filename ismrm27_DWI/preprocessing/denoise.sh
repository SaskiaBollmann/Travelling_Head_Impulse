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
# Denoising
# -------------------------------
# This script applies NORDIC denoising to the DWI data
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
# Denoising
# ==============================================================================

# denoising runs on PA only
for pe in ${DIRS[@]}; do

    # identify file
    fmag=${INPUTDIR}/dwi_mag_${pe}.mif

    if [[ "$pe" == "PA" ]]; then
        # run denoise if PA
        dwidenoise2 dwidenoise2 \
            ${fmag} \
            ${TMPWORKDIR}/dwi_${pe}_denoise.mif \
            -nthreads ${NTHREADS} \
            -residual_statistics ${TMPWORKDIR}/dwi_${pe}_denoise_mean.mif ${TMPWORKDIR}/dwi_${pe}_denoise_var.mif ${TMPWORKDIR}/dwi_${pe}_denoise_maxabs.mif \
            -noise_out ${TMPWORKDIR}/dwi_${pe}_denoise_noise.mif
    else
        # else just copy
        # we are skipping denoising of AP data because it is only b0 images
        echo "  Copying AP data"
        echo ""

        # NOTE: hardcoded b0 flag
        cp ${INPUTDIR}/dwi_mag_${pe}_b0.mif \
           ${TMPWORKDIR}/dwi_${pe}.mif
    fi

done








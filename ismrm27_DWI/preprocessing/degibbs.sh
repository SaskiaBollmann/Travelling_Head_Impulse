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
# Removal of Gibbs ringing
# -------------------------------
# This script applies the mrdegibbs to remove Gibbs ringing
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
# Degibbs
# ==============================================================================
count=0

PAmag=${INPUTDIR}/dwi_PA_denoise.mif
APmag=${INPUTDIR}/dwi_AP.mif

printf "\r  [....] mrdegibbs "

# run mrdegibbs
mrtrix mrdegibbs \
    ${PAmag} \
    ${TMPWORKDIR}/dwi_PA_denoise_degibbs.mif \
    -nthreads ${NTHREADS} \
    -quiet

mrtrix mrdegibbs \
    ${APmag} \
    ${TMPWORKDIR}/dwi_AP_degibbs.mif \
    -nthreads ${NTHREADS} \
    -quiet

printf "\r  [DONE] mrdegibbs \n"










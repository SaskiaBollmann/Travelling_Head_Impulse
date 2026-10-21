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
# Freesurfer
# -------------------------------
# Simple runner for Freesurfer's recon-all for the folder structure
# in the AON project
#
# Author:   Daniel Uher
# Email:    daniel.uher@ovgu.de
# Version:  0.1.0
# ==============================================================================

source pipeline.config
source pipeline.functions

# ==============================================================================
# Freesurfer recon-all
# ==============================================================================
echo ""
echo "  Sub: ${SUB}"
echo ""
echo "  Freesurfer recon-all"
echo "  --------------------"
echo ""

fs recon-all \
    -sd ${OUTDIR} \
    -threads 8 \
    -subjid fs \
    -i ${OUTDIR}/${FINAL_OUTPREFIX}_T1w_skullstripped.nii \
    -all

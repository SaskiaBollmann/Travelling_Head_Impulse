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
# eddy via FSL
# -----------------------------------------------------
# This script applies eddy for distortion and motion correction
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
# SynB0-Disco
# ==============================================================================
cp ${INPUTDIR}/dwi_PA_denoise_degibbs_meanb0.nii \
    ${SYNBO_INPUTS}/b0.nii

cp ${INPUTDIR}/t1w_skullstripped.nii \
    ${SYNBO_INPUTS}/T1.nii

gzip -f ${SYNBO_INPUTS}/b0.nii
gzip -f ${SYNBO_INPUTS}/T1.nii

# create acqparams file
cat > ${SYNBO_INPUTS}/acqparams.txt <<- EOF
	${DIR2} ${TOTAL_READOUT_TIME}
	${DIR2} 0.000
	EOF

# run synbo-disco NOTE: flags can be adjusted in pipeline.functions
synbo-disco

mv ${SYNBO_OUTPUTS}/* ${TMPWORKDIR}
cp ${SYNBO_INPUTS}/acqparams.txt ${TMPWORKDIR}/acqparams.txt
cp ${INPUTDIR}/dwi_PA_denoise_degibbs* ${TMPWORKDIR}
rm -rf ${SYNBO_INPUTS}/*  # clear the SYNBO INPUTS folder

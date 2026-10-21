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
# Pre eddy
# ==============================================================================

# NOTE: we are using only PA information currently
printf "\r  [....] getting number of volumes per PE dir "
DIR2_NVOLS=$(get_nvols ${INPUTDIR}/dwi_PA_denoise_degibbs.nii)
printf "\r  [DONE] getting number of volumes per PE dir \n"

echo "  ${DIRS[1]}: ${DIR2_NVOLS} volumes"

printf "\r  [....] creating the index.txt file for eddy "
for i in $(seq 1 ${DIR2_NVOLS}); do echo "1" >> ${TMPWORKDIR}/index.txt; done
printf "\r  [DONE] creating the index.txt file for eddy \n\n"

# ==============================================================================
# EDDY
# ==============================================================================

echo "  EDDY correction: "
echo "  -----------------"

# eddy_cuda11.0 \
#     --imain=${INPUTDIR}/dwi_PA_denoise_degibbs.nii \
#     --mask=${INPUTDIR}/dwi_brainmask.nii \
#     --acqp=${INPUTDIR}/acqparams.txt \
#     --index=${TMPWORKDIR}/index.txt \
#     --bvecs=${INPUTDIR}/dwi_PA_denoise_degibbs.bvec \
#     --bvals=${INPUTDIR}/dwi_PA_denoise_degibbs.bval \
#     --field=${INPUTDIR}/b0map_desc-masked-hz \
#     --out=${TMPWORKDIR}/dwi_denoise_degibbs_${STEPNAME} \
#     --slm=linear \
#     --niter=8 \
#     --fwhm=10,8,4,2,0,0,0,0 \
#     --mporder=16 \
#     --data_is_shelled \
#     --repol \
#     --estimate_move_by_susceptibility \
#     --verbose

# TODO try moving mporder lower, 16th order is quite high I think
eddy_cuda11.0 \
    --imain=${INPUTDIR}/dwi_PA_denoise_degibbs.nii \
    --mask=${INPUTDIR}/dwi_PA_denoise_degibbs_meanb0_brainmask.nii \
    --acqp=${INPUTDIR}/acqparams.txt \
    --index=${TMPWORKDIR}/index.txt \
    --bvecs=${INPUTDIR}/dwi_PA_denoise_degibbs.bvec \
    --bvals=${INPUTDIR}/dwi_PA_denoise_degibbs.bval \
    --topup=${INPUTDIR}/topup \
    --out=${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy \
    --slm=linear \
    --niter=8 \
    --data_is_shelled \
    --fwhm=10,8,4,2,0,0,0,0 \
    --mporder=16 \
    --repol \
    --estimate_move_by_susceptibility \
    --verbose

echo "-----------------"

printf "\r  [....] converting corrected .nii to .mif along with rotated .bvecs "
mrtrix mrconvert \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy.nii \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy.mif \
    -fslgrad ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy.eddy_rotated_bvecs \
             ${INPUTDIR}/dwi_PA_denoise_degibbs.bval \
    -quiet
printf "\r  [DONE] converting corrected .nii to .mif along with rotated .bvecs \n"


printf "\r  [....] getting an updated mean b0 reference image "
getb0 \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy.mif \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0.nii
printf "\r  [DONE] getting an updated mean b0 reference image \n"

echo ""

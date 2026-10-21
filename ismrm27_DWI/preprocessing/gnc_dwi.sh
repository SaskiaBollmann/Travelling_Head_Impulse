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
echo "  DWI Gradient non-linearity correction: "
echo "  ---------------------------------------"

# copy DWI brainmask here for this and further processing
fs mri_synthstrip \
    -i ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_meanb0.nii \
    -m ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_brainmask.nii \
    -t 8

echo "  gradunwarp:"
gradient_unwarp.py \
    ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_meanb0.nii \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0 \
    --scanner ${SCANNER} \
    --interp_order ${GNC_INTERP_ORDER}
echo ""

# Convert absolute warp to relative warp
convertwarp \
    --abs \
    --ref=${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_meanb0.nii \
    --warp1=${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_gnc-fullWarp-abs.nii \
    --relout \
    --out=${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_gnc-fullWarp-rel.nii

# split the dataset into individual volumes
mkdir ${TMPWORKDIR}/split

# get number of volumes
NVOLS=$(get_nvols ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy.mif)

# split into individual volumes and apply warp
file_list=""
for ((i=0; i<NVOLS; i++)); do
    printf "\r  [....] Unwarping volumes: %d/%d " ${i} $((NVOLS))

    mrtrix mrconvert \
        ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy.mif \
        -coord 3 ${i} \
        -axes 0,1,2 \
        -quiet \
        ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}.nii

    applywarp --rel \
        --interp=spline \
        -i ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}.nii \
        -r ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy_meanb0.nii \
        -w ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_gnc-fullWarp-rel.nii \
        -o ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}_gnc.nii \

    # multiply by the jacobian to account for intensity changes
    mrtrix mrcalc \
        ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}_gnc.nii \
        ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_gnc-jacobian.nii \
        -mult \
        ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}_gnc_jacmult.nii \
        -quiet

    file_list="${file_list} ${TMPWORKDIR}/split/dwi_denoise_degibbs_topup_eddy_${i}_gnc_jacmult.nii"

done
printf "\r  [DONE] Unwarping volumes: %d/%d \n" ${i} $((NVOLS))


printf "\r  [....] Concatenating corrected volumes into a 4D .nii "
mrtrix mrcat \
    -axis 3 \
    ${file_list} \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.nii \
    -quiet
printf "\r  [DONE] Concatenating corrected volumes into a 4D .nii \n"


printf "\r  [....] Collecting latest .bvec and .bval from previous eddy "
mrtrix mrinfo \
    ${INPUTDIR}/dwi_denoise_degibbs_topup_eddy.mif \
    -export_grad_fsl ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bvec \
                     ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bval \
    -quiet
printf "\r  [DONE] Collecting latest .bvec and .bval from previous eddy \n"


printf "\r  [....] Removing leftover split volumes "
rm -rf ${TMPWORKDIR}/split
printf "\r  [DONE] Removing leftover split volumes \n"


printf "\r  [....] Convert to .mif and get updated mean b0 "
mrtrix mrconvert \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.nii \
    ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.mif \
    -fslgrad ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bvec \
             ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bval \
    -quiet

getb0 ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.mif \
      ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_meanb0.nii
printf "\r  [DONE] Convert to .mif and get updated mean b0 \n"

# FSL's calc_grad_perc_dev
# calculates the percentual deviation from expected field - necessary for
# determing the deviations in b-values and b-vectors.
# With the setup below, this will output three files: L_x.nii,
# L_y.nii, and L_z.nii
# and *_z.nii
printf "\r  [....] Calculating the L tensor "
calc_grad_perc_dev \
    --fullwarp=${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_gnc-fullWarp-abs.nii \
    --out=${TMPWORKDIR}/L
printf "\r  [DONE] Calculating the L tensor \n"

# calculate the voxelwise gradient table
# and output the quality control, which generates
# a voxelwise deviation map for
# 1. percentual deviation map of the effective bvalue from the nominal one
# 2. deviation map of the effective bvector from the nominal one in degrees
echo "  Voxelwise b-table: "
python voxelwise_btable.py \
    ${TMPWORKDIR}/L_x.nii \
    ${TMPWORKDIR}/L_y.nii \
    ${TMPWORKDIR}/L_z.nii \
    --bvecs ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bvec \
    --bvals ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc.bval \
    --mask ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_meanb0_brainmask.nii \
    --out ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc \

printf "\r  [....] Moving the voxelwise btable .nii files to OUTDIR "
mv ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_voxelwise-bval.nii \
   ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_voxelwise-bval.nii
mv ${TMPWORKDIR}/dwi_denoise_degibbs_topup_eddy_gnc_voxelwise-bvec.nii \
   ${OUTDIR}/${FINAL_OUTPREFIX}_DWI_voxelwise-bvec.nii
printf "\r  [DONE] Moving the voxelwise btable .nii files to OUTDIR \n"

# ------------------------------------------------------------------------------



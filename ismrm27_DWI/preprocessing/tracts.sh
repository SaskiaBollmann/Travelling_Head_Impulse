#!/usr/bin/env bash
set -e

source pipeline.config
source pipeline.functions

sessions=( 'sess-MGDB01' \
           'sess-MGDB02' \
           'sess-MGDB03' \
           'sess-STAN01' \
           'sess-STAN02' \
           'sess-STAN03' )

N_SEEDS="1M"  # how many tracks will be estimated
N_SELECT="100k" # for visualization, a subset of N_SELECT is created to save mem

for sess in ${sessions[@]}; do

    echo "***************"
    echo ${sess}
    echo "***************"
    echo ""

    DATADIR=/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/01_data/sub-01/${sess}/proc
    OUTDIR=${DATADIR}/tracts
    WORKDIR=${DATADIR}/tracts/steps

    mkdir -p ${WORKDIR}

    PREFIX="sub-01_acq-ep2d_preprocessed"
    DWI=${DATADIR}/${PREFIX}_DWI.nii
    BVAL=${DATADIR}/${PREFIX}_DWI.bval
    BVEC=${DATADIR}/${PREFIX}_DWI.bvec
    SEG=${DATADIR}/${PREFIX}_DWI_seg.nii
    MASK=${DATADIR}/${PREFIX}_DWI_brainmask.nii

    # Output definitions
    DWI_MIF=${WORKDIR}/dwi.mif
    WMFOD=${WORKDIR}/wmfod.mif
    GMFOD=${WORKDIR}/gmfod.mif
    CSFFOD=${WORKDIR}/csffod.mif
    WMFOD_NORM=${WORKDIR}/wmfod_norm.mif
    GMFOD_NORM=${WORKDIR}/gmfod_norm.mif
    CSFFOD_NORM=${WORKDIR}/csffod_norm.mif
    TRACKS=${OUTDIR}/${PREFIX}_tracks-${N_SEEDS}.tck
    TRACKS_FILTERED=${OUTDIR}/${PREFIX}_tracks-${N_SELECT}.tck
    TDI_OUT=${OUTDIR}/${PREFIX}_tracks-${N_SEEDS}_TDI.nii.gz

    echo "> Converting NIfTI to MRtrix MIF format..."
    mrtrix mrconvert ${DWI} ${DWI_MIF} \
        -fslgrad ${BVEC} ${BVAL} \
        -force

    echo "> Estimating 3-tissue response functions (dhollander)..."
    mrtrix dwi2response dhollander ${DWI_MIF} \
        ${WORKDIR}/response_wm.txt \
        ${WORKDIR}/response_gm.txt \
        ${WORKDIR}/response_csf.txt \
        -mask ${MASK} -force

    echo "> Calculating Multi-Shell Multi-Tissue CSD FODs..."
    mrtrix dwi2fod msmt_csd ${DWI_MIF} \
        ${WORKDIR}/response_wm.txt ${WMFOD} \
        ${WORKDIR}/response_gm.txt ${GMFOD} \
        ${WORKDIR}/response_csf.txt ${CSFFOD} \
        -mask ${MASK} -force

    echo "> Normalizing multi-tissue FOD intensities..."
    mrtrix mtnormalise ${WMFOD} ${WMFOD_NORM} \
                ${GMFOD} ${GMFOD_NORM} \
                ${CSFFOD} ${CSFFOD_NORM} \
                -mask ${MASK} -force

    echo "> Getting WM mask from the FS seg ... "
    fs mri_binarize \
        --i ${SEG} \
        --match 41 2 \
        --o ${WORKDIR}/wm_mask.nii


    echo "> Generating deterministic WM tractogram (${N_SEEDS} streamlines)..."
    mrtrix tckgen ${WMFOD_NORM} ${TRACKS} \
        -algorithm SD_STREAM \
        -seed_image ${WORKDIR}/wm_mask.nii \
        -minlength 12 \
        -mask ${MASK} \
        -select ${N_SEEDS} -force

    echo "> Mapping streamlines to Tract Density Image (TDI)..."
    mrtrix tckmap ${TRACKS} ${TDI_OUT} \
        -template ${MASK} \
        -contrast tdi -force

    echo "> Selecting a ${N_SELECT} subset for visualizations ..."
    mrtrix tckedit ${TRACKS} ${TRACKS_FILTERED} \
        -number ${N_SELECT} -skip 500 -force

    echo "Done! MSMT-CSD TDI saved to ${TDI_OUT}"

done

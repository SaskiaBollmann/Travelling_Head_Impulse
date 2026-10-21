#!/bin/bash
source pipeline.config
source pipeline.functions

# ==============================================================================
# coregistration
# ==============================================================================

sessions=( 'sess-MGDB01' \
           'sess-MGDB02' \
           'sess-MGDB03' \
           'sess-STAN01' \
           'sess-STAN02' \
           'sess-STAN03' )




for sess in ${sessions[@]}; do

  echo "***************"
  echo ${sess}
  echo "***************"
  echo ""
  TEMPLATE=/home/duher/Tools/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz
  DATADIR=/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/01_data/sub-01

  DTIDIR=${DATADIR}/${sess}/proc/dti
  FWDTIDIR=${DATADIR}/${sess}/proc/fwdti
  NODDIDIR=${DATADIR}/${sess}/proc/noddi
  TRACTDIR=${DATADIR}/${sess}/proc/tracts

  QMETRICS=(
        ${DTIDIR}/DTI_vox_fa.nii.gz
        ${DTIDIR}/DTI_vox_md.nii.gz
        ${FWDTIDIR}/FW-DTI_vox_fa.nii.gz
        ${FWDTIDIR}/FW-DTI_vox_md.nii.gz
        ${NODDIDIR}/fit_ODI.nii.gz
        ${NODDIDIR}/fit_NDI.nii.gz
        ${NODDIDIR}/fit_FWF.nii.gz
        ${TRACTDIR}/sub-01_acq-ep2d_preprocessed_tracks-1M_TDI.nii.gz
  )

  MEAN_B0=${DATADIR}/${sess}/proc/sub-01_acq-${ACQ}_preprocessed_DWI_meanb0.nii
  T1w=${DATADIR}/${sess}/proc/sub-01_acq-${ACQ}_preprocessed_T1w_skullstripped.nii
  OUTDIR=${DATADIR}/${sess}/proc/coreg

  mkdir -p ${OUTDIR}

  # 1. Rigid registration (6 DoF): FA -> T1w
  ants antsRegistrationSyNQuick.sh -d 3 -f ${T1w} -m ${MEAN_B0} -t r -o ${OUTDIR}/dwi2t1_

  # 2. Affine+SyN registration (12 DoF): T1w -> Template
  ants antsRegistrationSyNQuick.sh -d 3 -f ${TEMPLATE} -m ${T1w} -t s -o ${OUTDIR}/t12template_ -n 16

  # 3. Apply chained transforms to maps
  for metric in ${QMETRICS[@]}; do

    tmpbase=$(basename ${metric})
    tmpfname=${tmpbase%%.*}

    ants antsApplyTransforms -d 3 \
      -i ${metric} \
      -r ${TEMPLATE} \
      -t ${OUTDIR}/t12template_1Warp.nii.gz \
      -t ${OUTDIR}/t12template_0GenericAffine.mat \
      -t ${OUTDIR}/dwi2t1_0GenericAffine.mat \
      -o ${OUTDIR}/${tmpfname}_space-mni.nii.gz

  done

  # MD
  # ants antsApplyTransforms -d 3 \
  #   -i ${DTIDIR}/DTI_vox_md.nii.gz \
  #   -r ${TEMPLATE} \
  #   -t ${OUTDIR}/t12template_1Warp.nii.gz \
  #   -t ${OUTDIR}/t12template_0GenericAffine.mat \
  #   -t ${OUTDIR}/dwi2t1_0GenericAffine.mat \
  #   -o ${OUTDIR}/DTI_vox_md_space-template.nii.gz
  #
  # # seg
  # ants antsApplyTransforms -d 3 \
  #   -i ${DATADIR}/${sess}/proc/sub-01_acq-${acq}_preprocessed_DWI_seg.nii \
  #   -r ${TEMPLATE} \
  #   -t ${OUTDIR}/t12template_1Warp.nii.gz \
  #   -t ${OUTDIR}/t12template_0GenericAffine.mat \
  #   -t ${OUTDIR}/dwi2t1_0GenericAffine.mat \
  #   -o ${OUTDIR}/seg_space-template.nii.gz \
  #   -n NearestNeighbor

  echo ""
  echo "***************"
  echo ""

done


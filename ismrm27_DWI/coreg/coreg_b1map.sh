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

  B1MAP=$(find ${DATADIR}/${sess}/fmap -type f -iname "*sag_B1Comb*.nii")
  echo "Found B1Comb: ${B1MAP}"

  MEAN_B0=${DATADIR}/${sess}/proc/sub-01_acq-${ACQ}_preprocessed_DWI_meanb0.nii
  T1w=${DATADIR}/${sess}/proc/sub-01_acq-${ACQ}_preprocessed_T1w_skullstripped.nii
  OUTDIR=${DATADIR}/${sess}/proc/coreg

  mkdir -p ${OUTDIR}

  # 1. Rigid registration (6 DoF): FA -> T1w
  ants antsApplyTransforms -d 3 \
    -i ${B1MAP} \
    -r ${T1w} \
    -o ${OUTDIR}/B1Comb_space-t1w.nii

  # 1. Rigid registration (6 DoF): FA -> T1w
  ants antsApplyTransforms -d 3 \
    -i ${B1MAP} \
    -r ${MEAN_B0} \
    -o ${OUTDIR}/B1Comb_space-dwi.nii

  # 2. Affine+SyN registration (12 DoF): T1w -> Template
  ants antsRegistrationSyNQuick.sh -d 3 -f ${TEMPLATE} -m ${T1w} -t s -o ${OUTDIR}/t12template_ -n 16

  # 3. Apply chained transforms to maps
  ants antsApplyTransforms -d 3 \
    -i ${OUTDIR}/B1Comb_space-t1w.nii \
    -r ${TEMPLATE} \
    -t ${OUTDIR}/t12template_1Warp.nii.gz \
    -t ${OUTDIR}/t12template_0GenericAffine.mat \
    -o ${OUTDIR}/B1Comb_space-mni.nii.gz

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


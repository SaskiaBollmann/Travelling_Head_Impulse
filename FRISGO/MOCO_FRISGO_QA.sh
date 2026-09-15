#!/bin/bash


#This section generates a mask for the motion correction. 
# This is just to make it faster, but you can also use the whole FOV for the motion correction.
3dAutomask -overwrite -prefix moma.nii.gz -peels 3 -dilate 2 dzne*.nii


#coutner for loop so we can align as many runs as we want.
cnt=100
echo "starting file loop across runs of BOLD"

for filename in ./dzne*.nii
do
echo $filename

#grabing a reference to to align everythign to. 
# we dont want the very first three time points (Mz steady state)
# We average a couple to make it less noisy and not biased towards one read polarity 
# we refrain from using "overwrite because we want to keep the identical across runs"
3dTstat -mean -prefix reference.nii.gz $filename'[3..4]'

#Doing the hravy lifting of motion correction. We use the moma.nii.gz mask to speed up the process and avoid edge effects (which we dont have for Whole brain
3dAllineate                                                                  \
    -1Dmatrix_save  ALLIN_bold_${cnt}.aff12.1D                                    \
    -cost           lpa                                                      \
    -prefix         moco_bold_${cnt}.nii.gz                                \
    -base           reference.nii.gz                                           \
    -source         $filename                                     \
    -weight         moma.nii.gz                                      \
    -warp           shift_rotate                                             \
    -final          wsinc5



# adjust TR in header, because 3D-EPI header that follows COBIDAS definition of shot TR is not meaningfull for fMRI. Here we use volume TR instead.
3drefit -TR 2.054 moco_bold_${cnt}.nii.gz


#Apply FRISGO to the motion corrected data.
# infor here: https://youtu.be/AWX1hHYvnbc?si=5cyKf7yI3S574hsH 
# https://layerfmri.page.link/LN2_FRISGO 
LN2_FRISGO -input moco_bold_${cnt}.nii.gz -tshift -output frisgo_bold_${cnt}.nii.gz 

#Estimating tSNR for the motion corrected data with and without FRISGO.
3dTstat -tSNR  -overwrite -prefix tSNR_frisgo_bold_${cnt}.nii.gz frisgo_bold_100_Tshift.nii.gz

3dTstat -overwrite -mean -prefix odd_mean_moco_bold_${cnt}.nii.gz moco_bold_${cnt}.nii.gz'[4..$(2)]'\n
3dTstat -overwrite -mean -prefix eve_mean_moco_bold_${cnt}.nii.gz moco_bold_${cnt}.nii.gz'[3..$(2)]'\n
3dTstat -overwrite -tSNR -prefix odd_tSNR_moco_bold_${cnt}.nii.gz moco_bold_${cnt}.nii.gz'[4..$(2)]'\n
3dTstat -overwrite -tSNR -prefix eve_tSNR_moco_bold_${cnt}.nii.gz moco_bold_${cnt}.nii.gz'[3..$(2)]'\n
3dcalc -a odd_mean_moco_bold_${cnt}.nii.gz -b eve_mean_moco_bold_${cnt}.nii.gz -prefix diff_moco_bold_${cnt}.nii.gz -expr '2*abs((a-b)/(a+b))' -overwrite
3dcalc -prefix mean_moco_bold_${cnt}.nii.gz -b eve_mean_moco_bold_${cnt}.nii.gz -a odd_mean_moco_bold_${cnt}.nii.gz -expr '(a+b)/2' -overwrite
3dcalc -a odd_mean_moco_bold_${cnt}.nii.gz -b eve_mean_moco_bold_${cnt}.nii.gz -prefix diff_moco_bold_${cnt}.nii.gz -expr '2*(a-b)/(a+b)' -overwrite
3dMean -prefix tSNRmean_moco_bold_${cnt}.nii.gz -overwrite odd_tSNR_moco_bold_${cnt}.nii.gz eve_tSNR_moco_bold_${cnt}.nii.gz


cnt=$(($cnt+1))

done 


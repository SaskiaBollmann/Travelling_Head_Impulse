#!/bin/bash


#This section generates a mask for the motion correction. 
# This is just to make it faster, but you can also use the whole FOV for the motion correction.

cnt=100
for filename in ./dzne*.nii
do
echo $filename

#3dRefit -TR 2 frisgo_bold_${cnt}_Tshift.nii.gz
./afni_GLM.sh frisgo_bold_${cnt}_Tshift.nii.gz


cnt=$(($cnt+1))
done 

#3dclust -prefix nice_act.nii -1clip 3.5 0.9 100 2_STATS_NEG_frisgo_bold_100_Tshift.nii.gz -overwrite

3dmean -overwrite -prefix activitymap.nii.gz 2_STATS_NEG_frisgo_bold_*_Tshift.nii.gz 

3dclust -prefix nice_activitymap.nii.gz -1clip 2.5 0.9 100 activitymap.nii.gz -overwrite    

#!/bin/bash


echo "It starts now"

  
3dDeconvolve -overwrite -jobs 16 -polort a -input $1 \
             -num_stimts 1 \
             -TR_times 3 \
             -stim_times 1 '1D: 0 40 80 120 160 200 240 280 320 360 400 440 480 520 560 600 640 680' 'UBLOCK(20,1)' -stim_label 1 Task \
             -tout \
             -x1D MODEL_wm \
             -iresp 1 HRF_$1 \
             -bucket STATS_$1

echo "GLM done" 



3dcalc -a HRF_$1'[1]'  -expr 'a' -prefix 1_HRF_$1 -overwrite 
3dcalc -a HRF_$1'[1]'  -expr '-1*a' -prefix 1_HRF_NEG_$1 -overwrite 


3dcalc -a STATS_$1'[0]'  -expr 'a' -prefix 0_STATS_$1 -overwrite 
3dcalc -a STATS_$1'[1]'  -expr '-1*a' -prefix 1_STATS_NEG_$1 -overwrite 
3dcalc -a STATS_$1'[2]'  -expr '-1*a' -prefix 2_STATS_NEG_$1 -overwrite 
3dcalc -a STATS_$1'[2]'  -expr 'a' -prefix 2_STATS_$1 -overwrite 

3dTstat -mean -overwrite -prefix mean.nii $1

3dcalc -a mean.nii -b 1_HRF_$1      -expr 'b/a*100' -prefix 1_HRF_percent_$1 -overwrite 
3dcalc -a mean.nii -b  1_HRF_NEG_$1 -expr 'b/a*100' -prefix 1_HRF_NEG_percent_$1 -overwrite 

rm mean.nii

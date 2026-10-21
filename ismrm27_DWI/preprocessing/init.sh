#!/bin/bash
set -euo pipefail

SCRIPTNAME="$0"          # collect the script name
INPUTDIR="$1"            # collect the directory of previous step
STEPCOUNT="$2"           # step count

echo ""
echo "========================================================================="
echo " ${STEPCOUNT}. ${SCRIPTNAME} "
echo "========================================================================="
echo "  Input directory: ${INPUTDIR}"
echo ""

# ==============================================================================
# Initialization of the pipeline
# -------------------------------
# This script runs and initializes the whole pipeline. Mainly, it copies all
# the necessary files for the pipeline to run.
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

# ==============================================================================
# Setup
# ==============================================================================

if [[ ! -d ${INITDIR} ]]; then
    mkdir -p ${INITDIR}
fi

# ==============================================================================
# Initialize the pipeline
# ==============================================================================

# ------- DWI --------
# for each PE direction
for pe in ${DIRS[@]}; do

    pe_filelist=""
    # for each b-value
    for bv in ${BVALS[@]}; do

        # for each part (magnitude/phase)
        for part in ${PARTS[@]}; do

            # find all the necessary files
            fnii=$(find ${DWIDIR} -type f -iname "${SUB}_${SESS}_acq-${ACQ}_dir-${pe}_part-${part}_desc-${bv}.nii" )
            fjson=$(find ${DWIDIR} -type f -iname "${SUB}_${SESS}_acq-${ACQ}_dir-${pe}_part-${part}_desc-${bv}.json" )
            fbval=$(find ${DWIDIR} -type f -iname "${SUB}_${SESS}_acq-${ACQ}_dir-${pe}_part-${part}_desc-${bv}.bval" )
            fbvec=$(find ${DWIDIR} -type f -iname "${SUB}_${SESS}_acq-${ACQ}_dir-${pe}_part-${part}_desc-${bv}.bvec" )

            # if the nifti file exists, then do the shenanigans
            if [[ -n "$fnii" ]]; then

                echo ""
                echo "  ************"
                echo "  ${pe} ${bv} ${part}"
                echo "  ************"
                echo ""
                echo "      ---"
                echo "      nii:   ${fnii}"
                echo "      json:  ${fjson}"
                echo "      bval:  ${fbval}"
                echo "      bvec:  ${fbvec}"
                echo "      ---"
                echo ""


                # ------- copy the files to the init dir --------
                count=0  # establish count

                # make an explicit file list
                file_list=( ${fnii} ${fjson} ${fbval} ${fbvec} )

                # loop and copy
                for file in ${file_list[@]}; do

                    count=$(($count+1))     # increment count
                    printf "\r      [....] Copying file %d/%d " ${count} ${#file_list[@]}

                    # check whether the file was found and if not, error out
                    if [[ -z ${file} ]]; then
                        echo "ERROR: Files for ${pe} ${bv} ${part} could not be found. "
                        exit 1
                    fi

                    extension="${file##*.}"  # get file extension

                    # copy the file
                    cp ${file} ${INITDIR}/dwi_${part}_${pe}_${bv}.${extension}

                done
                printf "\r      [DONE] Copying file %d/%d \n" ${count} ${#file_list[@]}
                echo ""

                printf "\r      [....] Converting to .mif "
                mrtrix mrconvert ${fnii} ${INITDIR}/dwi_${part}_${pe}_${bv}.mif \
                    -fslgrad ${fbvec} ${fbval} \
                    -json_import ${fjson} \
                    -quiet

                pe_filelist="${pe_filelist} ${INITDIR}/dwi_${part}_${pe}_${bv}.mif"
                printf "\r      [DONE] Converting to .mif\n\n"

            fi

        done

    done

    if [[ "$pe" == "PA" ]]; then
        printf "\r  [....] For PA, concatenating the b-values to a single .mif "
        mrtrix mrcat \
            -axis 3 \
            ${pe_filelist} \
            ${INITDIR}/dwi_${part}_${pe}.mif \
            -quiet
        printf "\r  [DONE] For PA, concatenating the b-values to a single .mif\n\n"
    fi

done


# ------- T1w --------
cp ${T1W} ${INITDIR}/t1w.nii  # copy t1w to the init dir

exit 1


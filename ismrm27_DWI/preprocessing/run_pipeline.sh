#!/bin/bash
set -euo pipefail
source pipeline.config

echo "========================================================================="
echo " Pipeline "
echo "========================================================================="
echo ""

# ==============================================================================
# Travelling brain 2026 pipeline runner
#
# Author:   Daniel Uher
# Email:    daniel.uher@ovgu.de
# Version:  0.1.0
# ==============================================================================
SESS="$1"
START_STEP="$2"


# ==============================================================================
# Logging
# ==============================================================================
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/pipeline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1


# ==============================================================================
# Run pipeline
# ==============================================================================
echo "  Start step:    ${START_STEP}"
echo "     Subject:    ${SUB}"
echo "     Session:    ${SESS}"

# Find index of START_STEP in STEPS
start_idx=-1
for i in "${!STEPS[@]}"; do
    if [[ "${STEPS[$i]}" == "${START_STEP}" ]]; then
        start_idx=$i
        break
    fi
done

# Check whether specified step is within the STEPS array
if [[ $start_idx -eq -1 ]]; then
    echo "ERROR: START_STEP '${START_STEP}' not found in STEPS array."
    exit 1
fi

# Determine PREVIOUS_STEP for input directory lookup
if [[ $start_idx -eq 0 ]]; then
    # in case of starting from "init"
    PREVIOUS_STEP="none"
else
    # previous step will be the one with index minus 1
    PREVIOUS_STEP="${STEPS[$((start_idx-1))]}"
    echo "  Previous step: ${PREVIOUS_STEP}"
fi

# set the step count and established tracking of applied steps
STEPCOUNT=$start_idx
STEPS_APPLIED=""

# Loop through the remaining steps
for step in "${STEPS[@]:$start_idx}"; do

    # increment step count
    STEPCOUNT=$(($STEPCOUNT+1))

    # add current step to steps applied
    STEPS_APPLIED="${STEPS_APPLIED}-${step}"

    # run step
    bash ${step}.sh ${PREVIOUS_STEP} ${STEPCOUNT} ${SESS}

    # archive this step for the next loop
    PREVIOUS_STEP=${step}

done

# remove steps if specified
if [[ ${DELETE_STEPS} == true ]]; then
    rm -rf ${WORKDIR}
fi


#!/bin/bash
#SBATCH --job-name=ants_syn
#SBATCH --time=4:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=32GB
#SBATCH --array=0-48
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/ants_syn_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/ants_syn_%A_%a.error

# 1. Parse the identifier
IDENTIFIER=$1

if [ -z "$IDENTIFIER" ]; then
    echo "Error: No identifier provided."
    echo "Usage: sbatch submit_syn_array.sh <identifier>"
    exit 1
fi

# 2. Define Paths
BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${IDENTIFIER}"

# Create the specific output directory for this identifier
mkdir -p "$OUT_DIR"

# 3. Define the full master list of 7 sessions
SESSION_DIRS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260602_THS_ses04"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)
NUM_SES=${#SESSION_DIRS[@]}

# 4. Map the Array ID (0-48) to Matrix Rows (i) and Columns (j)
i=$(( SLURM_ARRAY_TASK_ID / NUM_SES ))
j=$(( SLURM_ARRAY_TASK_ID % NUM_SES ))

MOV_SES="${SESSION_DIRS[$i]}"
FIX_SES="${SESSION_DIRS[$j]}"

# 5. Dynamically locate the specific files
REGEX_PATTERN="${IDENTIFIER}_[0-9]+\.nii(\.gz)?$"

MOVING=$(find "${BASE_DIR}/${MOV_SES}" -maxdepth 1 -type f 2>/dev/null | grep -E "$REGEX_PATTERN" | head -n 1)
FIXED=$(find "${BASE_DIR}/${FIX_SES}" -maxdepth 1 -type f 2>/dev/null | grep -E "$REGEX_PATTERN" | head -n 1)

# If either file is missing, exit cleanly but write a NaN placeholder
if [[ -z "$MOVING" || -z "$FIXED" ]]; then
    echo "Missing file for either ${MOV_SES} or ${FIX_SES}. Skipping this matrix pair."
    echo "NaN" > "${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
    exit 0
fi

# 6. Set up ANTs outputs
OUT_PREFIX="${OUT_DIR}/reg_SyN_mov_${MOV_SES}_to_fix_${FIX_SES}_"

# Tell ANTs to use the exact number of CPUs allocated by Slurm
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK

echo "Task ID ${SLURM_ARRAY_TASK_ID}: Registering ${MOV_SES} to ${FIX_SES}"

# 7. Run the Registration (SyN / Non-Linear)
antsRegistrationSyNQuick.sh -d 3 -f "$FIXED" -m "$MOVING" -o "$OUT_PREFIX" -t s

# 8. Compute cross-correlation using FSL
REGISTERED_IMG="${OUT_PREFIX}Warped.nii.gz"

if [ -f "$REGISTERED_IMG" ]; then
    CORR=$(fslcc "$FIXED" "$REGISTERED_IMG" | awk '{print $3}')
else
    CORR="NaN"
fi

# Save the extracted correlation value to a temporary individual file
echo "${CORR}" > "${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
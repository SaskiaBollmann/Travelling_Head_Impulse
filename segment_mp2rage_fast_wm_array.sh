#!/bin/bash
#SBATCH --job-name=fast_mp2rage_wm
#SBATCH --time=01:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
#SBATCH --array=0-6
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/segmentation/fast/logs/fast_mp2rage_wm_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/segmentation/fast/logs/fast_mp2rage_wm_%A_%a.error

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

if ! command -v ml >/dev/null 2>&1; then
    echo "Error: The module command is unavailable." >&2
    exit 1
fi
ml fsl

for program in fast fslmaths fslstats find sort grep; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Error: Required program not found: $program" >&2
        exit 1
    fi
done

SESSIONS=(
    260529_THS_ses01
    260601_THS_ses02
    260602_THS_ses03
    260602_THS_ses04
    260611_THS_ses05
    260618_THS_ses06
    260618_THS_ses07
)

TASK_ID=${SLURM_ARRAY_TASK_ID:-0}
if (( TASK_ID < 0 || TASK_ID >= ${#SESSIONS[@]} )); then
    echo "Error: Task ID $TASK_ID is outside the session list." >&2
    exit 1
fi

SESSION=${SESSIONS[$TASK_ID]}
BASE_DIR=/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig
SEG_ROOT=/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/segmentation/fast
COREG_DIR=/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked
OUT_DIR="${SEG_ROOT}/${SESSION}"
mkdir -p "$OUT_DIR"

if [[ "$SESSION" == *_ses01 ]]; then
    REGEX='mp2rage_0p7iso_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$'
elif [[ "$SESSION" == *_ses04 ]]; then
    REGEX='(mp2rage_0p7iso|t1_mp2rage_sag_p3_0p7mm)_(patientSpecific|PS)_UNI[-_]DEN_[0-9]+\.nii(\.gz)?$'
else
    REGEX='mp2rage_0p7iso_(patientSpecific|PS)_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$'
fi

mapfile -t MATCHES < <(
    find "${BASE_DIR}/${SESSION}" -maxdepth 1 -type f | sort | grep -E "$REGEX" || true
)
if [ "${#MATCHES[@]}" -ne 1 ]; then
    echo "Error: Expected one patient-specific MP2RAGE for $SESSION; found ${#MATCHES[@]}." >&2
    printf '%s\n' "${MATCHES[@]}" >&2
    exit 1
fi

INPUT=${MATCHES[0]}
INPUT_NAME=${INPUT##*/}
INPUT_STEM=${INPUT_NAME%.nii.gz}
INPUT_STEM=${INPUT_STEM%.nii}
BRAIN_MASK="${COREG_DIR}/mask_${SESSION}.nii.gz"
BRAIN="${OUT_DIR}/${INPUT_STEM}_brain.nii.gz"
FAST_PREFIX="${OUT_DIR}/${INPUT_STEM}_fast"
WM_MASK="${OUT_DIR}/wm_mask_fast_pve95.nii.gz"

if [ ! -f "$BRAIN_MASK" ]; then
    echo "Error: Brain mask not found: $BRAIN_MASK" >&2
    exit 1
fi

if [ -s "$WM_MASK" ]; then
    echo "Reusing existing strict FAST WM mask: $WM_MASK"
    fslstats "$WM_MASK" -V
    exit 0
fi

echo "Running FAST for $SESSION"
echo "Input: $INPUT"
fslmaths "$INPUT" -mas "$BRAIN_MASK" "$BRAIN"
fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -B -o "$FAST_PREFIX" "$BRAIN"
fslmaths "${FAST_PREFIX}_pve_2.nii.gz" -thr 0.95 -bin "$WM_MASK"

echo "Strict FAST WM mask (voxels and mm^3):"
fslstats "$WM_MASK" -V
echo "Saved: $WM_MASK"

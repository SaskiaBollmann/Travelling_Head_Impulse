#!/bin/bash

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

usage() {
    echo "Usage: bash register_mp2rage_ps_trueform_halfway.sh [ses02|ses03] [-F|--force]"
}

SESSION_LABEL="ses03"
FORCE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        ses02|ses03)
            SESSION_LABEL="$1"
            ;;
        -F|--force)
            FORCE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

case "$SESSION_LABEL" in
    ses02) SESSION="260601_THS_ses02" ;;
    ses03) SESSION="260602_THS_ses03" ;;
esac

if ! command -v ml >/dev/null 2>&1; then
    echo "Error: The 'ml' module command is unavailable." >&2
    exit 1
fi

ml freesurfer

for program in mri_robust_register mri_synthstrip find grep head sort; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Error: Required program not found: $program" >&2
        exit 1
    fi
done

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_vs_TrueForm_UNI-DEN_ND_masked"
OUT_DIR="${DERIV_DIR}/halfway"
SESSION_DIR="${BASE_DIR}/${SESSION}"

find_one() {
    local regex=$1
    local family=$2
    local matches

    matches=$(find "$SESSION_DIR" -maxdepth 1 -type f |
        sort |
        grep -E "$regex" || true)
    if [[ $(printf "%s\n" "$matches" | grep -c .) -ne 1 ]]; then
        echo "Error: Expected exactly one ${family} image in ${SESSION_DIR}." >&2
        printf "%s\n" "$matches" >&2
        exit 1
    fi
    printf "%s\n" "$matches"
}

PS_FILE=$(find_one \
    "mp2rage_0p7iso_(patientSpecific|PS)_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$" \
    "patient-specific")
TF_FILE=$(find_one \
    "mp2rage_0p7iso_(TrueForm|TF)_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$" \
    "TrueForm")

mkdir -p "$OUT_DIR"

PREFIX="${OUT_DIR}/rigid_halfway_${SESSION}"
LTA="${PREFIX}_patientSpecific_to_TrueForm.lta"
PS_HALF="${PREFIX}_patientSpecific.nii.gz"
TF_HALF="${PREFIX}_TrueForm.nii.gz"
PS_HALF_LTA="${PREFIX}_patientSpecific.lta"
TF_HALF_LTA="${PREFIX}_TrueForm.lta"
ISCALE="${PREFIX}_intensity_scale.txt"
MASK="${PREFIX}_brain_mask.nii.gz"

if [ "$FORCE" = true ]; then
    rm -f "$LTA" "$PS_HALF" "$TF_HALF" "$PS_HALF_LTA" "$TF_HALF_LTA" \
        "$ISCALE" "$MASK"
fi

if [[ ! -s "$PS_HALF" || ! -s "$TF_HALF" || ! -s "$LTA" ]]; then
    echo "Computing inverse-consistent rigid registration in halfway space..."
    mri_robust_register \
        --mov "$PS_FILE" \
        --dst "$TF_FILE" \
        --lta "$LTA" \
        --halfmov "$PS_HALF" \
        --halfdst "$TF_HALF" \
        --halfmovlta "$PS_HALF_LTA" \
        --halfdstlta "$TF_HALF_LTA" \
        --iscale \
        --iscaleout "$ISCALE" \
        --satit \
        --floattype
else
    echo "Reusing existing halfway-space images."
fi

if [[ ! -s "$MASK" ]]; then
    echo "Creating halfway-space brain mask from TrueForm..."
    mri_synthstrip -i "$TF_HALF" -m "$MASK"
fi

echo "Patient-specific halfway image: $PS_HALF"
echo "TrueForm halfway image: $TF_HALF"
echo "Halfway-space brain mask: $MASK"

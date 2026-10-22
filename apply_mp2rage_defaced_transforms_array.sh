#!/bin/bash
#SBATCH --job-name=mp2rage_defaced_xfm
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8GB
#SBATCH --array=0-13
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/mp2rage_defaced_xfm_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/mp2rage_defaced_xfm_%A_%a.error

set -euo pipefail

if ! command -v ml >/dev/null 2>&1; then
    echo "Error: the Sherlock module command is unavailable." >&2
    exit 1
fi

ml ants || {
    echo "Error: failed to load the ANTs module." >&2
    exit 1
}

if ! command -v antsApplyTransforms >/dev/null 2>&1; then
    echo "Error: antsApplyTransforms is unavailable after loading ANTs." >&2
    exit 1
fi

readonly OAK_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026"
readonly SOURCE_DIR="${OAK_ROOT}/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked"
readonly OUTPUT_DIR="${OAK_ROOT}/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_defaced"
readonly DRY_RUN="${DRY_RUN:-false}"

SESSIONS=(
    260529_THS_ses01
    260601_THS_ses02
    260602_THS_ses03
    260602_THS_ses04
    260611_THS_ses05
    260618_THS_ses06
    260618_THS_ses07
)

DEFACED_SOURCES=(
    "${OAK_ROOT}/orig/260529_THS_ses01/defaced/mp2rage_0p7iso_UNI-DEN_ND_34.nii"
    "${OAK_ROOT}/orig/260601_THS_ses02/defaced/mp2rage_0p7iso_PS_UNI-DEN_ND_36.nii"
    "${OAK_ROOT}/orig/260602_THS_ses03/defaced/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_51.nii"
    "${OAK_ROOT}/orig/260602_THS_ses04/defaced/t1_mp2rage_sag_p3_0p7mm_PS_UNI_DEN_27.nii"
    "${OAK_ROOT}/orig/260611_THS_ses05/defaced/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_30.nii"
    "${OAK_ROOT}/orig/260618_THS_ses06/defaced/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_30.nii"
    "${OAK_ROOT}/orig/260618_THS_ses07/defaced/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_29.nii"
)

TASK_ID="${SLURM_ARRAY_TASK_ID:-${1:-}}"
if [[ ! "$TASK_ID" =~ ^[0-9]+$ ]] || (( TASK_ID < 0 || TASK_ID > 13 )); then
    echo "Usage: sbatch $0, or DRY_RUN=true $0 <task-id 0-13>" >&2
    exit 2
fi

if (( TASK_ID < 7 )); then
    TRANSFORM="Rigid"
    MOVING_INDEX=$TASK_ID
else
    TRANSFORM="SyN"
    MOVING_INDEX=$((TASK_ID - 7))
fi

MOVING_SESSION="${SESSIONS[$MOVING_INDEX]}"
MOVING_IMAGE="${DEFACED_SOURCES[$MOVING_INDEX]}"
PROVENANCE_FILE="${OUTPUT_DIR}/provenance_${TRANSFORM}_mov_${MOVING_SESSION}.tsv"

for image in "${DEFACED_SOURCES[@]}"; do
    if [[ ! -s "$image" ]]; then
        echo "Error: missing defaced source: $image" >&2
        exit 1
    fi
done

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${SLURM_CPUS_PER_TASK:-1}"

if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$OUTPUT_DIR"
    printf 'transform\tmoving_session\tfixed_session\tmoving_defaced_source\tfixed_defaced_reference\taffine_transform\twarp_transform\toutput\n' > "$PROVENANCE_FILE"
fi

for fixed_index in "${!SESSIONS[@]}"; do
    FIXED_SESSION="${SESSIONS[$fixed_index]}"
    FIXED_IMAGE="${DEFACED_SOURCES[$fixed_index]}"
    STEM="reg_${TRANSFORM}_mov_${MOVING_SESSION}_to_fix_${FIXED_SESSION}"
    AFFINE_TRANSFORM="${SOURCE_DIR}/${STEM}_0GenericAffine.mat"
    WARP_TRANSFORM=""
    OUTPUT="${OUTPUT_DIR}/${STEM}_CORR_Warped.nii.gz"

    if [[ ! -s "$AFFINE_TRANSFORM" ]]; then
        echo "Error: missing affine transform: $AFFINE_TRANSFORM" >&2
        exit 1
    fi

    TRANSFORM_ARGS=(-t "$AFFINE_TRANSFORM")
    if [[ "$TRANSFORM" == "SyN" ]]; then
        WARP_TRANSFORM="${SOURCE_DIR}/${STEM}_1Warp.nii.gz"
        if [[ ! -s "$WARP_TRANSFORM" ]]; then
            echo "Error: missing nonlinear warp: $WARP_TRANSFORM" >&2
            exit 1
        fi
        TRANSFORM_ARGS=(-t "$WARP_TRANSFORM" -t "$AFFINE_TRANSFORM")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf 'antsApplyTransforms -d 3 -i %q -r %q -n Linear' "$MOVING_IMAGE" "$FIXED_IMAGE"
        printf ' %q' "${TRANSFORM_ARGS[@]}"
        printf ' -o %q\n' "$OUTPUT"
    elif [[ -s "$OUTPUT" ]]; then
        echo "Reusing completed output: $OUTPUT"
    else
        TEMP_OUTPUT="${OUTPUT%.nii.gz}.tmp.${SLURM_JOB_ID:-$$}.${TASK_ID}.nii.gz"
        trap 'rm -f "${TEMP_OUTPUT:-}"' EXIT
        echo "Applying $TRANSFORM transform: $MOVING_SESSION -> $FIXED_SESSION"
        antsApplyTransforms \
            -d 3 \
            -i "$MOVING_IMAGE" \
            -r "$FIXED_IMAGE" \
            -n Linear \
            "${TRANSFORM_ARGS[@]}" \
            -o "$TEMP_OUTPUT"
        if [[ ! -s "$TEMP_OUTPUT" ]]; then
            echo "Error: antsApplyTransforms did not create $TEMP_OUTPUT" >&2
            exit 1
        fi
        mv "$TEMP_OUTPUT" "$OUTPUT"
        trap - EXIT
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$TRANSFORM" "$MOVING_SESSION" "$FIXED_SESSION" \
            "$MOVING_IMAGE" "$FIXED_IMAGE" "$AFFINE_TRANSFORM" \
            "$WARP_TRANSFORM" "$OUTPUT" >> "$PROVENANCE_FILE"
    fi
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo "Dry run completed for $TRANSFORM moving session $MOVING_SESSION."
else
    echo "Completed $TRANSFORM outputs for moving session $MOVING_SESSION."
fi

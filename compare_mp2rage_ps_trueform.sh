#!/bin/bash

if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

print_usage() {
    echo "Usage: bash compare_mp2rage_ps_trueform.sh [-m] [-t rigid|affine|both] [-F|--force|--rerun]"
}

MASK=false
FORCE=false
TRANSFORM_MODE="both"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -m|--mask)
            MASK=true
            ;;
        -t|--transform)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo "Error: $1 requires rigid, affine, or both." >&2
                print_usage
                exit 1
            fi
            TRANSFORM_MODE="$2"
            shift
            ;;
        -F|--force|--rerun)
            FORCE=true
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            print_usage
            exit 1
            ;;
    esac
    shift
done

case "$TRANSFORM_MODE" in
    r|rigid|Rigid|RIGID)
        TRANSFORM_FLAGS=("r")
        TRANSFORM_NAMES=("Rigid")
        ;;
    a|affine|Affine|AFFINE)
        TRANSFORM_FLAGS=("a")
        TRANSFORM_NAMES=("Affine")
        ;;
    both|all|Both|BOTH|All|ALL)
        TRANSFORM_FLAGS=("r" "a")
        TRANSFORM_NAMES=("Rigid" "Affine")
        ;;
    *)
        echo "Error: Transform mode must be rigid, affine, or both." >&2
        print_usage
        exit 1
        ;;
esac

if ! command -v ml >/dev/null 2>&1; then
    echo "Error: The 'ml' module command is unavailable." >&2
    exit 1
fi

ml fsl || { echo "Error: Failed to load FSL." >&2; exit 1; }
ml ants || { echo "Error: Failed to load ANTs." >&2; exit 1; }
if [ "$MASK" = true ]; then
    ml freesurfer || { echo "Error: Failed to load FreeSurfer." >&2; exit 1; }
fi

required_programs=(
    antsRegistrationSyNQuick.sh
    antsApplyTransforms
    fslcc
    awk
    find
    grep
    head
    sort
)
[ "$MASK" = true ] && required_programs+=(mri_synthstrip)

for program in "${required_programs[@]}"; do
    if ! command -v "$program" >/dev/null 2>&1; then
        echo "Error: Required program not found: $program" >&2
        exit 1
    fi
done

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_ID="mp2rage_0p7iso_patientSpecific_vs_TrueForm_UNI-DEN_ND"
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"
OUT_DIR="${DERIV_DIR}/${OUT_ID}"
RESULTS_FILE="${OUT_DIR}/correlation_patientSpecific_vs_TrueForm.tsv"

SESSION_DIRS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260602_THS_ses04"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)

mkdir -p "$OUT_DIR"

family_regex() {
    local session=$1
    local family=$2

    if [[ "$session" == *"_ses01" ]]; then
        if [ "$family" = "patientSpecific" ]; then
            echo "mp2rage_0p7iso_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
        else
            return 1
        fi
    elif [[ "$session" == *"_ses04" ]]; then
        if [ "$family" = "patientSpecific" ]; then
            echo "(mp2rage_0p7iso_(patientSpecific|PS)_UNI[-_]DEN|t1_mp2rage_sag_p3_0p7mm_(patientSpecific|PS)_UNI[-_]DEN)_[0-9]+\.nii(\.gz)?$"
        else
            echo "(mp2rage_0p7iso_(TrueForm|TF)_UNI[-_]DEN|t1_mp2rage_sag_p3_0p7mm_(TrueForm|TF)_UNI[-_]DEN)_[0-9]+\.nii(\.gz)?$"
        fi
    elif [ "$family" = "patientSpecific" ]; then
        echo "mp2rage_0p7iso_(patientSpecific|PS)_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
    else
        echo "mp2rage_0p7iso_(TrueForm|TF)_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
    fi
}

find_family_file() {
    local session=$1
    local family=$2
    local regex

    regex=$(family_regex "$session" "$family") || return
    find "${BASE_DIR}/${session}" -maxdepth 1 -type f 2>/dev/null |
        sort |
        grep -E "$regex" |
        head -n 1
}

printf "session\tsite\ttransform\tpatientSpecific_file\tTrueForm_file\tCC\n" > "$RESULTS_FILE"

echo "Comparing patientSpecific (moving) with TrueForm (fixed) within each session."
echo "Output: $RESULTS_FILE"

for (( t=0; t<${#TRANSFORM_FLAGS[@]}; t++ )); do
    FLAG="${TRANSFORM_FLAGS[$t]}"
    NAME="${TRANSFORM_NAMES[$t]}"

    echo "Running $NAME comparisons..."
    for (( i=0; i<${#SESSION_DIRS[@]}; i++ )); do
        SESSION="${SESSION_DIRS[$i]}"
        SESSION_NUMBER=$((i + 1))
        if [ "$SESSION_NUMBER" -le 3 ]; then
            SITE="Stanford"
        elif [ "$SESSION_NUMBER" -eq 4 ]; then
            SITE="Berkeley"
        else
            SITE="Magdeburg"
        fi

        PS_FILE=$(find_family_file "$SESSION" patientSpecific)
        TF_FILE=$(find_family_file "$SESSION" TrueForm)
        TEMP_CC="${OUT_DIR}/tmp_cc_${NAME}_${SESSION}.txt"

        if [[ -z "$PS_FILE" || -z "$TF_FILE" ]]; then
            echo "  [$SESSION] Missing patientSpecific or TrueForm; CC=NaN"
            CC="NaN"
            echo "$CC" > "$TEMP_CC"
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$SESSION" "$SITE" "$NAME" \
                "${PS_FILE##*/}" "${TF_FILE##*/}" "$CC" >> "$RESULTS_FILE"
            continue
        fi

        OUT_PREFIX="${OUT_DIR}/reg_${NAME}_patientSpecific_to_TrueForm_${SESSION}_"
        TRANSFORM_MAT="${OUT_PREFIX}0GenericAffine.mat"
        WARPED_PS="${OUT_PREFIX}Warped.nii.gz"

        if [ "$FORCE" = true ]; then
            rm -f "${OUT_PREFIX}"* "$TEMP_CC"
        elif [ -s "$TEMP_CC" ]; then
            CC=$(<"$TEMP_CC")
            echo "  [$SESSION] Reusing $NAME CC=$CC"
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$SESSION" "$SITE" "$NAME" \
                "${PS_FILE##*/}" "${TF_FILE##*/}" "$CC" >> "$RESULTS_FILE"
            continue
        fi

        echo "  [$SESSION] Registering patientSpecific to TrueForm..."
        antsRegistrationSyNQuick.sh \
            -d 3 \
            -f "$TF_FILE" \
            -m "$PS_FILE" \
            -o "$OUT_PREFIX" \
            -t "$FLAG"

        if [ ! -f "$TRANSFORM_MAT" ]; then
            echo "  [$SESSION] Transform failed; CC=NaN" >&2
            CC="NaN"
        else
            antsApplyTransforms \
                -d 3 \
                -i "$PS_FILE" \
                -r "$TF_FILE" \
                -n Linear \
                -t "$TRANSFORM_MAT" \
                -o "$WARPED_PS"

            MASK_ARGS=()
            if [ "$MASK" = true ]; then
                MASK_FILE="${OUT_DIR}/mask_TrueForm_${SESSION}.nii.gz"
                if [ ! -f "$MASK_FILE" ]; then
                    mri_synthstrip -i "$TF_FILE" -m "$MASK_FILE"
                fi
                MASK_ARGS=(-m "$MASK_FILE")
            fi

            CC=$(fslcc "${MASK_ARGS[@]}" "$TF_FILE" "$WARPED_PS" | head -n 1 | awk '{print $3}')
            [ -z "$CC" ] && CC="NaN"
        fi

        echo "$CC" > "$TEMP_CC"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$SESSION" "$SITE" "$NAME" \
            "${PS_FILE##*/}" "${TF_FILE##*/}" "$CC" >> "$RESULTS_FILE"
        echo "  [$SESSION] $NAME CC=$CC"
    done
done

echo "Completed within-session patientSpecific-versus-TrueForm correlations."
echo "Results: $RESULTS_FILE"

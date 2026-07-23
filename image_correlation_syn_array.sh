#!/bin/bash
#SBATCH --job-name=ants_syn
#SBATCH --time=4:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=32GB
#SBATCH --array=0-48
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/ants_syn_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/ants_syn_%A_%a.error

if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

check_programs() {
    local missing=()
    local program

    for program in "$@"; do
        if ! command -v "$program" >/dev/null 2>&1; then
            missing+=("$program")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Error: Required programs not found after module loading: ${missing[*]}" >&2
        exit 1
    fi
}

print_usage() {
    echo "Usage: sbatch image_correlation_syn_array.sh -r <reg_id> [-R reg_suffix] [-c corr_id] [-C corr_suffix] [-m] [-F|--force|--rerun]"
    echo "Legacy: sbatch image_correlation_syn_array.sh <identifier> [suffix]"
}

require_value() {
    local option=$1
    local value=${2:-}

    if [[ -z "$value" || "$value" == -* ]]; then
        echo "Error: $option requires a value."
        print_usage
        exit 1
    fi
}

# 1. Parse command line arguments. Positional arguments are kept for older calls.
MASK=false
FORCE=false
if [[ "$#" -gt 0 && "$1" != -* ]]; then
    REG_ID="$1"
    shift
    if [[ "$#" -gt 0 && "$1" != -* ]]; then
        REG_SUFFIX="$1"
        shift
    fi
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--reg-id)
            require_value "$1" "${2:-}"
            REG_ID="$2"
            shift 2
            ;;
        -R|--reg-suffix)
            require_value "$1" "${2:-}"
            REG_SUFFIX="$2"
            shift 2
            ;;
        -c|--corr-id)
            require_value "$1" "${2:-}"
            CORR_ID="$2"
            shift 2
            ;;
        -C|--corr-suffix)
            require_value "$1" "${2:-}"
            CORR_SUFFIX="$2"
            shift 2
            ;;
        -m|--mask)
            MASK=true
            shift
            ;;
        -F|--force|--rerun)
            FORCE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown parameter passed: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [ -z "$REG_ID" ]; then
    echo "Error: Registration ID (-r) is required."
    print_usage
    exit 1
fi

if [ -z "$CORR_ID" ]; then CORR_ID="$REG_ID"; fi
if [ -z "$CORR_SUFFIX" ]; then CORR_SUFFIX="$REG_SUFFIX"; fi

strip_leading_underscores() {
    local value=$1
    while [[ "$value" == _* ]]; do
        value="${value#_}"
    done
    echo "$value"
}

[ -n "$REG_SUFFIX" ] && REG_SUFFIX=$(strip_leading_underscores "$REG_SUFFIX")
[ -n "$CORR_SUFFIX" ] && CORR_SUFFIX=$(strip_leading_underscores "$CORR_SUFFIX")

# Load required software modules after parsing so --help works in any shell.
if ! command -v ml >/dev/null 2>&1; then
    echo "Error: The 'ml' module command is not available. Run this script in an environment with modules initialized." >&2
    exit 1
fi

ml fsl || { echo "Error: Failed to load FSL module." >&2; exit 1; }
ml ants || { echo "Error: Failed to load ANTs module." >&2; exit 1; }
ml freesurfer || { echo "Error: Failed to load FreeSurfer module." >&2; exit 1; }

REQUIRED_PROGRAMS=(antsRegistrationSyNQuick.sh antsApplyTransforms fslcc fslmaths fslstats awk find grep head sort mv rm sleep rmdir)
[ "$MASK" = true ] && REQUIRED_PROGRAMS+=(mri_synthstrip)
check_programs "${REQUIRED_PROGRAMS[@]}"

# 2. Build output IDs and paths.
OUT_ID="${CORR_ID}"
[ -n "$CORR_SUFFIX" ] && OUT_ID="${OUT_ID}_${CORR_SUFFIX}"
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${OUT_ID}"

# Create the specific output directory for this scan type
mkdir -p "$OUT_DIR"

# 3. Define the full master list of 7 sessions.
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
TOTAL_PAIRS=$((NUM_SES * NUM_SES))

build_regex() {
    local id=$1 suffix=$2
    if [ -n "$suffix" ]; then
        echo "${id}_[0-9]+_${suffix}\.nii(\.gz)?$"
    else
        echo "${id}_[0-9]+\.nii(\.gz)?$"
    fi
}

requested_mp2rage_uniden() {
    local id=$1 suffix=$2
    local request="${id}"
    [ -n "$suffix" ] && request="${request}_${suffix}"

    [[ "$request" == *mp2rage* && ( "$request" == *UNI-DEN* || "$request" == *UNI_DEN* ) ]]
}

mp2rage_uniden_family_regex() {
    local id=$1 suffix=$2
    local request="${id}"
    [ -n "$suffix" ] && request="${request}_${suffix}"

    case "$request" in
        *patientSpecific*|*_PS_*|*_PS|*PS_UNI-DEN*|*PS_UNI_DEN*)
            echo "(patientSpecific|PS)"
            ;;
        *TrueForm*|*_TF_*|*_TF|*TF_UNI-DEN*|*TF_UNI_DEN*)
            echo "(TrueForm|TF)"
            ;;
        *)
            echo ""
            ;;
    esac
}

build_mp2rage_uniden_regex() {
    local ses=$1 id=$2 suffix=$3
    local family_regex
    family_regex=$(mp2rage_uniden_family_regex "$id" "$suffix")

    if [ -z "$family_regex" ]; then
        return 1
    fi

    # Session 1 is the patientSpecific acquisition, but the filename lacks that flag.
    if [[ "$ses" == *"_ses01" ]]; then
        if [[ "$family_regex" == *patientSpecific* ]]; then
            echo "mp2rage_0p7iso_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
        else
            return 1
        fi
    elif [[ "$ses" == *"_ses04" ]]; then
        # Session 4 uses the Berkeley naming convention and does not include _ND.
        echo "(mp2rage_0p7iso_${family_regex}_UNI[-_]DEN|t1_mp2rage_sag_p3_0p7mm_${family_regex}_UNI[-_]DEN)_[0-9]+\.nii(\.gz)?$"
    else
        echo "mp2rage_0p7iso_${family_regex}_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
    fi
}

find_matching_file() {
    local search_path=$1 id=$2 suffix=$3 ses=$4 fallback_regex=$5
    local regex match no_nd_id

    if requested_mp2rage_uniden "$id" "$suffix"; then
        regex=$(build_mp2rage_uniden_regex "$ses" "$id" "$suffix")
        if [ -n "$regex" ]; then
            match=$(find "$search_path" -maxdepth 1 -type f 2>/dev/null | sort | grep -E "$regex" | head -n 1)

            if [ -n "$match" ]; then
                echo "$match"
                return
            fi
        fi
    fi

    # Session 4 has matching images without the ND token for some acquisitions.
    if [[ "$ses" == *"_ses04" && "$id" == *"_ND"* ]]; then
        no_nd_id="${id/_ND/}"
        regex=$(build_regex "$no_nd_id" "$suffix")
        match=$(find "$search_path" -maxdepth 1 -type f 2>/dev/null | sort | grep -E "$regex" | head -n 1)

        if [ -n "$match" ]; then
            echo "$match"
            return
        fi
    fi

    find "$search_path" -maxdepth 1 -type f 2>/dev/null | sort | grep -E "$fallback_regex" | head -n 1
}

REG_REGEX=$(build_regex "$REG_ID" "$REG_SUFFIX")
CORR_REGEX=$(build_regex "$CORR_ID" "$CORR_SUFFIX")

# 4. Map the array ID (0-48) to matrix rows (i) and columns (j).
TASK_ID=${SLURM_ARRAY_TASK_ID:-0}
if ! [[ "$TASK_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: SLURM_ARRAY_TASK_ID must be a non-negative integer; got '$TASK_ID'."
    exit 1
fi

if [ "$TASK_ID" -ge "$TOTAL_PAIRS" ]; then
    echo "Task ID $TASK_ID is outside the $TOTAL_PAIRS SyN session pairs. Exiting."
    exit 0
fi

i=$(( TASK_ID / NUM_SES ))
j=$(( TASK_ID % NUM_SES ))

MOV_SES="${SESSION_DIRS[$i]}"
FIX_SES="${SESSION_DIRS[$j]}"

OUT_PREFIX="${OUT_DIR}/reg_SyN_mov_${MOV_SES}_to_fix_${FIX_SES}_"
AFFINE_TRANSFORM="${OUT_PREFIX}0GenericAffine.mat"
WARP_TRANSFORM="${OUT_PREFIX}1Warp.nii.gz"
WARPED_CORR="${OUT_PREFIX}CORR_Warped.nii.gz"
TEMP_CORR="${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
TEMP_RMSE="${OUT_DIR}/tmp_rmse_SyN_${i}_${j}.txt"

if [ "$FORCE" = true ]; then
    echo "Force re-run requested for ${MOV_SES} -> ${FIX_SES}; removing existing pair outputs."
    rm -f "${OUT_PREFIX}"* "$TEMP_CORR" "$TEMP_RMSE"
elif [[ -s "$TEMP_CORR" && -s "$TEMP_RMSE" ]]; then
    echo "Completed SyN metrics already exist for ${MOV_SES} -> ${FIX_SES}. Skipping."
    exit 0
fi

# 5. Dynamically locate the registration and correlation/RMSE images.
MOVING_REG=$(find_matching_file "${BASE_DIR}/${MOV_SES}" "$REG_ID" "$REG_SUFFIX" "$MOV_SES" "$REG_REGEX")
FIXED_REG=$(find_matching_file "${BASE_DIR}/${FIX_SES}" "$REG_ID" "$REG_SUFFIX" "$FIX_SES" "$REG_REGEX")
MOVING_CORR=$(find_matching_file "${BASE_DIR}/${MOV_SES}" "$CORR_ID" "$CORR_SUFFIX" "$MOV_SES" "$CORR_REGEX")
FIXED_CORR=$(find_matching_file "${BASE_DIR}/${FIX_SES}" "$CORR_ID" "$CORR_SUFFIX" "$FIX_SES" "$CORR_REGEX")

# If any required file is missing, exit cleanly but write NaN placeholders.
if [[ -z "$MOVING_REG" || -z "$FIXED_REG" || -z "$MOVING_CORR" || -z "$FIXED_CORR" ]]; then
    echo "Missing required file for either ${MOV_SES} or ${FIX_SES}. Skipping this matrix pair."
    echo "NaN" > "$TEMP_CORR"
    echo "NaN" > "$TEMP_RMSE"
    exit 0
fi

# Tell ANTs to use the exact number of CPUs allocated by Slurm.
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${SLURM_CPUS_PER_TASK:-1}

echo "Task ID ${TASK_ID}: Registering moving ${MOV_SES} to fixed ${FIX_SES}"
echo "Registration images: ${MOVING_REG##*/} -> ${FIXED_REG##*/}"
echo "Correlation/RMSE images: ${MOVING_CORR##*/} -> ${FIXED_CORR##*/}"

# 7. Run the registration (SyN / non-linear).
if [ "$FORCE" = false ] && [[ -f "$AFFINE_TRANSFORM" && -f "$WARP_TRANSFORM" ]]; then
    echo "Reusing existing SyN transforms."
else
    antsRegistrationSyNQuick.sh -d 3 -f "$FIXED_REG" -m "$MOVING_REG" -o "$OUT_PREFIX" -t s
fi

# 8. Optionally build a mask from the fixed registration image.
MASK_CMD=""
if [ "$MASK" = true ]; then
    MASK_FILE="${OUT_DIR}/mask_${FIX_SES}.nii.gz"
    if [ ! -f "$MASK_FILE" ]; then
        LOCK_DIR="${MASK_FILE}.lock"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            if [ ! -f "$MASK_FILE" ]; then
                TMP_MASK="${MASK_FILE}.${SLURM_JOB_ID:-$$}.${TASK_ID}.tmp.nii.gz"
                echo "Creating mask for fixed session ${FIX_SES} with mri_synthstrip..."
                mri_synthstrip -i "$FIXED_REG" -m "$TMP_MASK"
                if [ ! -f "$TMP_MASK" ]; then
                    echo "Error: mri_synthstrip did not create expected mask: $TMP_MASK" >&2
                    rmdir "$LOCK_DIR" 2>/dev/null
                    exit 1
                fi
                mv "$TMP_MASK" "$MASK_FILE"
            fi
            rmdir "$LOCK_DIR" 2>/dev/null
        else
            echo "Waiting for mask for fixed session ${FIX_SES}..."
            while [ -d "$LOCK_DIR" ] && [ ! -f "$MASK_FILE" ]; do
                sleep 5
            done
            if [ ! -f "$MASK_FILE" ]; then
                echo "Error: Mask lock disappeared before mask was created: $MASK_FILE" >&2
                exit 1
            fi
        fi
    else
        echo "Reusing existing mask for fixed session ${FIX_SES}."
    fi
    MASK_CMD="-m $MASK_FILE"
fi

# 9. Apply the SyN transforms to the correlation/RMSE image.
if [ "$FORCE" = false ] && [ -f "$WARPED_CORR" ]; then
    echo "Reusing existing transformed correlation/RMSE image."
elif [[ -f "$AFFINE_TRANSFORM" && -f "$WARP_TRANSFORM" ]]; then
    antsApplyTransforms -d 3 -i "$MOVING_CORR" -r "$FIXED_CORR" -n Linear -t "$WARP_TRANSFORM" -t "$AFFINE_TRANSFORM" -o "$WARPED_CORR"
else
    echo "Warning: SyN transform files not found; writing NaN for this pair."
    echo "NaN" > "$TEMP_CORR"
    echo "NaN" > "$TEMP_RMSE"
    exit 0
fi

# 10. Compute cross-correlation and RMSE using FSL.
if [ -f "$WARPED_CORR" ]; then
    CORR=$(fslcc $MASK_CMD "$FIXED_CORR" "$WARPED_CORR" | awk '{print $3}')
    [ -z "$CORR" ] && CORR="NaN"

    TMP_SQR="${OUT_DIR}/tmp_sqr_SyN_${MOV_SES}_to_${FIX_SES}.nii.gz"
    if [ "$MASK" = true ]; then
        fslmaths "$FIXED_CORR" -sub "$WARPED_CORR" -sqr -mas "$MASK_FILE" "$TMP_SQR"
        MSE=$(fslstats "$TMP_SQR" -k "$MASK_FILE" -m)
    else
        fslmaths "$FIXED_CORR" -sub "$WARPED_CORR" -sqr "$TMP_SQR"
        MSE=$(fslstats "$TMP_SQR" -m)
    fi

    if [[ -n "$MSE" && "$MSE" != "NaN" ]]; then
        RMSE=$(awk -v mse="$MSE" 'BEGIN {printf "%.4f", sqrt(mse)}')
    else
        RMSE="NaN"
    fi
    rm "$TMP_SQR" 2>/dev/null
else
    CORR="NaN"
    RMSE="NaN"
fi

# Save the extracted metric values to temporary individual files.
echo "${CORR}" > "$TEMP_CORR"
echo "${RMSE}" > "$TEMP_RMSE"
echo "Result: correlation=${CORR} rmse=${RMSE}"

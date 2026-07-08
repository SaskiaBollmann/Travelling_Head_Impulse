#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi


# Load required software modules
if ! command -v ml >/dev/null 2>&1; then
    echo "Error: The 'ml' module command is not available. Run this script in an environment with modules initialized." >&2
    exit 1
fi

ml fsl || { echo "Error: Failed to load FSL module." >&2; exit 1; }
ml ants || { echo "Error: Failed to load ANTs module." >&2; exit 1; }
ml freesurfer || { echo "Error: Failed to load FreeSurfer module." >&2; exit 1; }

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

# 1. Parse Command Line Arguments
MASK=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--reg-id) REG_ID="$2"; shift ;;
        -R|--reg-suffix) REG_SUFFIX="$2"; shift ;;
        -c|--corr-id) CORR_ID="$2"; shift ;;
        -C|--corr-suffix) CORR_SUFFIX="$2"; shift ;;
        -m|--mask) MASK=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$REG_ID" ]; then
    echo "Error: Registration ID (-r) is required."
    echo "Usage: ./run_dynamic_linear.sh -r <reg_id> [-R reg_suffix] [-c corr_id] [-C corr_suffix] [-m]"
    exit 1
fi

if [ -z "$CORR_ID" ]; then CORR_ID="$REG_ID"; fi
if [ -z "$CORR_SUFFIX" ]; then CORR_SUFFIX="$REG_SUFFIX"; fi

REQUIRED_PROGRAMS=(antsRegistrationSyNQuick.sh antsApplyTransforms fslcc fslmaths fslstats awk find grep head sort)
[ "$MASK" = true ] && REQUIRED_PROGRAMS+=(mri_synthstrip)
check_programs "${REQUIRED_PROGRAMS[@]}"

# 2. Build Output IDs and Paths
OUT_ID="${CORR_ID}"
[ -n "$CORR_SUFFIX" ] && OUT_ID="${OUT_ID}_${CORR_SUFFIX}"
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${OUT_ID}"
mkdir -p "$OUT_DIR"

SESSION_DIRS=("260529_THS_ses01" "260601_THS_ses02" "260602_THS_ses03" "260602_THS_ses04" "260611_THS_ses05" "260618_THS_ses06" "260618_THS_ses07")

build_regex() {
    local id=$1 suffix=$2
    if [ -n "$suffix" ]; then echo "${id}_[0-9]+_${suffix}\.nii(\.gz)?$"
    else echo "${id}_[0-9]+\.nii(\.gz)?$"; fi
}

requested_mp2rage_uniden() {
    local id=$1 suffix=$2
    local request="${id}"
    [ -n "$suffix" ] && request="${request}_${suffix}"

    [[ "$request" == *mp2rage* && ( "$request" == *UNI-DEN* || "$request" == *UNI_DEN* ) ]]
}

build_mp2rage_uniden_regex() {
    local ses=$1
    local flag_regex="_(TrueForm|TF)"

    # Session 1 is the TrueForm acquisition, but the filename lacks that flag.
    if [[ "$ses" == *"_ses01" ]]; then
        flag_regex="(_(TrueForm|TF))?"
    fi

    # Session 4 uses the Berkeley naming convention and does not include _ND.
    if [[ "$ses" == *"_ses04" ]]; then
        echo "(mp2rage_0p7iso${flag_regex}_UNI[-_]DEN|t1_mp2rage_sag_p3_0p7mm${flag_regex}_UNI[-_]DEN)_[0-9]+\.nii(\.gz)?$"
    else
        echo "mp2rage_0p7iso${flag_regex}_UNI[-_]DEN_ND_[0-9]+\.nii(\.gz)?$"
    fi
}

find_matching_file() {
    local search_path=$1 id=$2 suffix=$3 ses=$4 fallback_regex=$5
    local regex match

    if requested_mp2rage_uniden "$id" "$suffix"; then
        regex=$(build_mp2rage_uniden_regex "$ses")
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

VALID_SES=()
REG_FILES=()
CORR_FILES=()

echo "Validating sessions for Registration ($REG_ID) and Correlation/RMSE ($CORR_ID)..."

for ses in "${SESSION_DIRS[@]}"; do
    search_path="${BASE_DIR}/${ses}"
    [ ! -d "$search_path" ] && continue
    
    R_FILE=$(find_matching_file "$search_path" "$REG_ID" "$REG_SUFFIX" "$ses" "$REG_REGEX")
    C_FILE=$(find_matching_file "$search_path" "$CORR_ID" "$CORR_SUFFIX" "$ses" "$CORR_REGEX")
    
    if [[ -n "$R_FILE" && -f "$R_FILE" && -n "$C_FILE" && -f "$C_FILE" ]]; then
        VALID_SES+=("$ses")
        REG_FILES+=("$R_FILE")
        CORR_FILES+=("$C_FILE")
        echo "  [Ready] $ses"
    else
        echo "  [Skipping] Missing required files in $ses"
    fi
done

NUM_VALID=${#VALID_SES[@]}
if [ "$NUM_VALID" -lt 2 ]; then
    echo "Error: Found less than 2 valid sessions."
    exit 1
fi

echo "Validated $NUM_VALID sessions."
echo "Output directory: $OUT_DIR"
if [ "$MASK" = true ]; then
    echo "Masking: enabled. SynthStrip masks will be generated from each fixed registration image."
else
    echo "Masking: disabled."
fi

TRANSFORM_FLAGS=("r" "a")
TRANSFORM_NAMES=("Rigid" "Affine")
TOTAL_PAIRS=$((NUM_VALID * NUM_VALID))

for (( t=0; t<${#TRANSFORM_FLAGS[@]}; t++ )); do
    FLAG="${TRANSFORM_FLAGS[$t]}"
    NAME="${TRANSFORM_NAMES[$t]}"
    
    CORR_MATRIX_FILE="${OUT_DIR}/correlation_matrix_${NAME}_${OUT_ID}.txt"
    RMSE_MATRIX_FILE="${OUT_DIR}/rmse_matrix_${NAME}_${OUT_ID}.txt"
    > "$CORR_MATRIX_FILE"
    > "$RMSE_MATRIX_FILE"
    
    echo "Executing $NAME Pipeline with transform flag $FLAG across $TOTAL_PAIRS session pairs..."
    for (( i=0; i<$NUM_VALID; i++ )); do
        ROW_CORR=""
        ROW_RMSE=""
        echo "  Matrix row $((i + 1))/$NUM_VALID: moving session ${VALID_SES[$i]}"
        
        for (( j=0; j<$NUM_VALID; j++ )); do
            MOV_SES="${VALID_SES[$i]}"
            FIX_SES="${VALID_SES[$j]}"
            
            OUT_PREFIX="${OUT_DIR}/reg_${NAME}_mov_${MOV_SES}_to_fix_${FIX_SES}_"
            PAIR_NUM=$((i * NUM_VALID + j + 1))

            echo "    [$NAME $PAIR_NUM/$TOTAL_PAIRS] Registering moving ${MOV_SES} to fixed ${FIX_SES}"
            echo "      Registration images: ${REG_FILES[$i]##*/} -> ${REG_FILES[$j]##*/}"
            echo "      Correlation/RMSE images: ${CORR_FILES[$i]##*/} -> ${CORR_FILES[$j]##*/}"
            
            # 1. Registration 
            echo "      Running ANTs registration..."
            antsRegistrationSyNQuick.sh -d 3 -f "${REG_FILES[$j]}" -m "${REG_FILES[$i]}" -o "$OUT_PREFIX" -t "$FLAG" >/dev/null 2>&1
            
            # 2. Masking with FreeSurfer (mri_synthstrip)
            MASK_CMD=""
            if [ "$MASK" = true ]; then
                MASK_FILE="${OUT_DIR}/mask_${FIX_SES}.nii.gz"
                if [ ! -f "$MASK_FILE" ]; then
                    echo "      Creating mask for fixed session ${FIX_SES} with mri_synthstrip..."
                    mri_synthstrip -i "${REG_FILES[$j]}" -m "$MASK_FILE" >/dev/null 2>&1
                else
                    echo "      Reusing existing mask for fixed session ${FIX_SES}."
                fi
                MASK_CMD="-m $MASK_FILE"
            fi
            
            # 3. Apply Transform
            WARPED_CORR="${OUT_PREFIX}CORR_Warped.nii.gz"
            TRANSFORM_MAT="${OUT_PREFIX}0GenericAffine.mat"
            
            if [ -f "$TRANSFORM_MAT" ]; then
                echo "      Applying transform to correlation/RMSE image..."
                antsApplyTransforms -d 3 -i "${CORR_FILES[$i]}" -r "${CORR_FILES[$j]}" -n Linear -t "$TRANSFORM_MAT" -o "$WARPED_CORR" >/dev/null 2>&1
                
                # 4a. Compute Correlation
                echo "      Computing FSL correlation..."
                CORR=$(fslcc $MASK_CMD "${CORR_FILES[$j]}" "$WARPED_CORR" | awk '{print $3}')
                [ -z "$CORR" ] && CORR="NaN"
                
                # 4b. Compute RMSE
                echo "      Computing RMSE..."
                TMP_SQR="${OUT_DIR}/tmp_sqr_${MOV_SES}_to_${FIX_SES}.nii.gz"
                
                if [ "$MASK" = true ]; then
                    fslmaths "${CORR_FILES[$j]}" -sub "$WARPED_CORR" -sqr -mas "$MASK_FILE" "$TMP_SQR"
                    # Use lowercase -m to get the mean of all voxels inside the mask (including true zeros)
                    MSE=$(fslstats "$TMP_SQR" -k "$MASK_FILE" -m) 
                else
                    fslmaths "${CORR_FILES[$j]}" -sub "$WARPED_CORR" -sqr "$TMP_SQR"
                    MSE=$(fslstats "$TMP_SQR" -m)
                fi
                
                if [[ -n "$MSE" && "$MSE" != "NaN" ]]; then
                    # Use awk to calculate the square root
                    RMSE=$(awk -v mse="$MSE" 'BEGIN {printf "%.4f", sqrt(mse)}')
                else
                    RMSE="NaN"
                fi
                rm "$TMP_SQR" 2>/dev/null
                echo "      Result: correlation=$CORR rmse=$RMSE"
                
            else
                echo "      Warning: transform matrix not found; writing NaN for this pair."
                CORR="NaN"
                RMSE="NaN"
            fi
            
            ROW_CORR="$ROW_CORR $CORR"
            ROW_RMSE="$ROW_RMSE $RMSE"
        done
        echo "$ROW_CORR" >> "$CORR_MATRIX_FILE"
        echo "$ROW_RMSE" >> "$RMSE_MATRIX_FILE"
    done
done
echo "Linear matrices completed: Correlation and RMSE."
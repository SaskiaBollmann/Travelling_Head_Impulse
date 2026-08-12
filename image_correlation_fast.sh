#!/bin/bash
#SBATCH --job-name=image_corr_fast
#SBATCH --time=24:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=32GB
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/image_corr_fast_%j.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/image_corr_fast_%j.error

if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

resolve_plot_script() {
    local source_dir candidate
    source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    for candidate in \
        "${THI_SCRIPT_DIR:-}" \
        "$source_dir" \
        "${SLURM_SUBMIT_DIR:-}" \
        "/home/users/sasbo/code/Travelling_Head_Impulse"; do
        if [ -n "$candidate" ] &&
           [ -f "${candidate}/plot_image_correlation.py" ]; then
            printf '%s\n' "${candidate}/plot_image_correlation.py"
            return 0
        fi
    done

    return 1
}

PLOT_SCRIPT=$(resolve_plot_script) || {
    echo "Error: Could not locate plot_image_correlation.py." >&2
    exit 1
}
PERCENT_DIFF_SCRIPT="$(dirname "$PLOT_SCRIPT")/compute_percent_difference.py"
PLOT_PYTHON="/home/users/sasbo/miniconda3/envs/THS_env/bin/python3"
PERCENT_DIFF_PYTHON="/home/users/sasbo/miniconda3/bin/python3"
ORIGINAL_ARGS=("$@")


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
print_usage() {
    echo "Usage: sbatch image_correlation_fast.sh (-r <reg_id> | --afni-epi ep2d [--afni-corr mean|tsnr]) [-R reg_suffix] [-c corr_id] [-C corr_suffix] [--corr-romeo standard|nd] [-m] [-t rigid|affine|both] [--physical-values | --wm-mean-scale | --legacy-percentile-scale] [--recompute-metrics] [-F|--force|--rerun]"
}

MASK=false
FORCE=false
PHYSICAL_VALUES=false
WM_MEAN_SCALE=false
LEGACY_PERCENTILE_SCALE=false
RECOMPUTE_METRICS=false
TRANSFORM_MODE="both"
ROMEO_FAMILY=""
AFNI_EPI=""
AFNI_CORR_METRIC="tsnr"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--reg-id) REG_ID="$2"; shift ;;
        -R|--reg-suffix) REG_SUFFIX="$2"; shift ;;
        -c|--corr-id) CORR_ID="$2"; shift ;;
        -C|--corr-suffix) CORR_SUFFIX="$2"; shift ;;
        --corr-romeo) ROMEO_FAMILY="${2,,}"; shift ;;
        --afni-epi) AFNI_EPI="${2,,}"; shift ;;
        --afni-corr) AFNI_CORR_METRIC="${2,,}"; shift ;;
        -m|--mask) MASK=true ;;
        -t|--transform) TRANSFORM_MODE="$2"; shift ;;
        --physical-values) PHYSICAL_VALUES=true ;;
        --wm-mean-scale) WM_MEAN_SCALE=true ;;
        --legacy-percentile-scale) LEGACY_PERCENTILE_SCALE=true ;;
        --recompute-metrics) RECOMPUTE_METRICS=true ;;
        -F|--force|--rerun) FORCE=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
    esac
    shift
done

if [ -n "$AFNI_EPI" ]; then
    case "$AFNI_EPI" in
        ep2d) ;;
        *) echo "Error: --afni-epi currently supports ep2d." >&2; exit 2 ;;
    esac
    case "$AFNI_CORR_METRIC" in
        mean|tsnr) ;;
        *) echo "Error: --afni-corr must be mean or tsnr." >&2; exit 2 ;;
    esac
    REG_ID="${AFNI_EPI}_bold_mean"
    CORR_ID="${AFNI_EPI}_bold_${AFNI_CORR_METRIC}"
    REG_SUFFIX=""
    CORR_SUFFIX=""
fi

if [ -z "$REG_ID" ]; then
    echo "Error: Registration ID (-r) is required."
    print_usage
    exit 1
fi

if [ "$PHYSICAL_VALUES" = true ] && [ "$WM_MEAN_SCALE" = true ]; then
    echo "Error: --physical-values and --wm-mean-scale are mutually exclusive." >&2
    exit 2
fi

if [ -n "$ROMEO_FAMILY" ]; then
    case "$ROMEO_FAMILY" in
        standard) CORR_ID="gre_b0map_4iso_sag_romeo_unwrapped" ;;
        nd) CORR_ID="gre_b0map_4iso_sag_ND_romeo_unwrapped" ;;
        *)
            echo "Error: --corr-romeo must be standard or nd." >&2
            exit 2
            ;;
    esac
    CORR_SUFFIX=""
else
    if [ -z "$CORR_ID" ]; then CORR_ID="$REG_ID"; fi
    if [ -z "$CORR_SUFFIX" ]; then CORR_SUFFIX="$REG_SUFFIX"; fi
fi

strip_leading_underscores() {
    local value=$1
    while [[ "$value" == _* ]]; do
        value="${value#_}"
    done
    echo "$value"
}

[ -n "$REG_SUFFIX" ] && REG_SUFFIX=$(strip_leading_underscores "$REG_SUFFIX")
[ -n "$CORR_SUFFIX" ] && CORR_SUFFIX=$(strip_leading_underscores "$CORR_SUFFIX")

dataset_id() {
    local id=$1 suffix=$2
    if [ -n "$suffix" ]; then
        echo "${id}_${suffix}"
    else
        echo "$id"
    fi
}

REG_DATASET_ID=$(dataset_id "$REG_ID" "$REG_SUFFIX")
CORR_DATASET_ID=$(dataset_id "$CORR_ID" "$CORR_SUFFIX")

if [ "$WM_MEAN_SCALE" = true ] && [ "$LEGACY_PERCENTILE_SCALE" = true ]; then
    echo "Error: --wm-mean-scale and --legacy-percentile-scale are mutually exclusive." >&2
    exit 2
fi
if [ "$LEGACY_PERCENTILE_SCALE" = false ] && [ "$PHYSICAL_VALUES" = false ] &&
   [[ "$CORR_DATASET_ID" == *mp2rage* ]] &&
   [[ "$CORR_DATASET_ID" == *UNI-DEN* || "$CORR_DATASET_ID" == *UNI_DEN* ]]; then
    WM_MEAN_SCALE=true
fi

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
        echo "Error: Transform mode must be one of: rigid, affine, both."
        print_usage
        exit 1
        ;;
esac

REQUIRED_PROGRAMS=(antsRegistrationSyNQuick.sh antsApplyTransforms fslcc fslmaths fslstats awk find grep head sort env rm)
[ "$MASK" = true ] && REQUIRED_PROGRAMS+=(mri_synthstrip)
check_programs "${REQUIRED_PROGRAMS[@]}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${SLURM_CPUS_PER_TASK:-1}
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
if [ ! -f "$PLOT_SCRIPT" ]; then
    echo "Error: Plotting script not found: $PLOT_SCRIPT" >&2
    exit 1
fi
if [ ! -f "$PERCENT_DIFF_SCRIPT" ]; then
    echo "Error: Percent-difference script not found: $PERCENT_DIFF_SCRIPT" >&2
    exit 1
fi
if [ ! -x "$PLOT_PYTHON" ]; then
    echo "Error: Plotting Python not found or not executable: $PLOT_PYTHON" >&2
    exit 1
fi
if [ ! -x "$PERCENT_DIFF_PYTHON" ]; then
    echo "Error: Percent-difference Python not found or not executable: $PERCENT_DIFF_PYTHON" >&2
    exit 1
fi
if ! env -u PYTHONPATH -u PYTHONHOME "$PERCENT_DIFF_PYTHON" -c \
    "import nibabel, numpy"; then
    echo "Error: Percent-difference Python requires nibabel and numpy." >&2
    exit 1
fi

# 2. Build Output IDs and Paths
if [ "$REG_DATASET_ID" = "$CORR_DATASET_ID" ]; then
    OUT_ID="$CORR_DATASET_ID"
else
    OUT_ID="reg-${REG_DATASET_ID}__corr-${CORR_DATASET_ID}"
fi
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
AFNI_EPI_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/realignment_afni"
[ -n "$AFNI_EPI" ] && BASE_DIR="$AFNI_EPI_ROOT"
ROMEO_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/b0_romeo"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
WM_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/segmentation/fast"
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

find_romeo_file() {
    local session=$1 family=$2
    local session_dir="${ROMEO_ROOT}/${session}"
    local path_regex match

    if [ "$family" = "nd" ]; then
        if [[ "$session" == *"_ses04" ]]; then
            # The session-4 ND acquisition omits the _ND token.
            path_regex='/gre_b0map_4iso_sag_[0-9]+_e2_ph_romeo/unwrapped\.nii(\.gz)?$'
        else
            path_regex='/gre_b0map_4iso_sag_ND_[0-9]+_e2_ph_romeo/unwrapped\.nii(\.gz)?$'
        fi
    else
        path_regex='/gre_b0map_4iso_sag_[0-9]+_e2_ph_romeo/unwrapped\.nii(\.gz)?$'
    fi

    match=$(find "$session_dir" -mindepth 2 -maxdepth 2 -type f 2>/dev/null |
        sort | grep -E "$path_regex" || true)
    if [ "$(printf '%s\n' "$match" | sed '/^$/d' | wc -l)" -gt 1 ]; then
        echo "Error: Multiple ${family} ROMEO outputs found for ${session}." >&2
        printf '%s\n' "$match" >&2
        return 2
    fi
    [ -n "$match" ] && printf '%s\n' "$match"
}

find_afni_epi_file() {
    local session=$1 metric=$2
    local session_dir="${AFNI_EPI_ROOT}/${session}"
    local matches count
    matches=$(find "$session_dir" -mindepth 2 -maxdepth 2 -type f 2>/dev/null |
        sort | grep -E "/${AFNI_EPI}_bold.*_afni/${AFNI_EPI}_bold.*_${metric}\.nii(\.gz)?$" || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)
    if [ "$count" -gt 1 ]; then
        echo "Error: Multiple ${AFNI_EPI} ${metric} images found for ${session}." >&2
        printf '%s\n' "$matches" >&2
        return 2
    fi
    [ -n "$matches" ] && printf '%s\n' "$matches"
}

REG_REGEX=$(build_regex "$REG_ID" "$REG_SUFFIX")
CORR_REGEX=$(build_regex "$CORR_ID" "$CORR_SUFFIX")

if [ "$WM_MEAN_SCALE" = true ] && ! requested_mp2rage_uniden "$CORR_ID" "$CORR_SUFFIX"; then
    echo "Error: --wm-mean-scale is only supported for MP2RAGE UNI-DEN comparisons." >&2
    exit 2
fi

REG_FILES=()
CORR_FILES=()
SESSION_AVAILABLE=()
NUM_VALID=0
NUM_SES=${#SESSION_DIRS[@]}

echo "Validating sessions for Registration ($REG_ID) and Correlation/RMSE ($CORR_ID)..."

for (( ses_idx=0; ses_idx<NUM_SES; ses_idx++ )); do
    ses="${SESSION_DIRS[$ses_idx]}"
    search_path="${BASE_DIR}/${ses}"
    R_FILE=""
    C_FILE=""

    if [ -d "$search_path" ]; then
        if [ -n "$AFNI_EPI" ]; then
            R_FILE=$(find_afni_epi_file "$ses" mean)
            C_FILE=$(find_afni_epi_file "$ses" "$AFNI_CORR_METRIC")
        else
            R_FILE=$(find_matching_file "$search_path" "$REG_ID" "$REG_SUFFIX" "$ses" "$REG_REGEX")
        fi
        if [ -z "$AFNI_EPI" ] && [ -n "$ROMEO_FAMILY" ]; then
            C_FILE=$(find_romeo_file "$ses" "$ROMEO_FAMILY")
        elif [ -z "$AFNI_EPI" ]; then
            C_FILE=$(find_matching_file "$search_path" "$CORR_ID" "$CORR_SUFFIX" "$ses" "$CORR_REGEX")
        fi
    fi

    if [[ -n "$R_FILE" && -f "$R_FILE" && -n "$C_FILE" && -f "$C_FILE" ]]; then
        REG_FILES[$ses_idx]="$R_FILE"
        CORR_FILES[$ses_idx]="$C_FILE"
        SESSION_AVAILABLE[$ses_idx]=true
        NUM_VALID=$((NUM_VALID + 1))
        echo "  [Ready] $ses"
    else
        REG_FILES[$ses_idx]=""
        CORR_FILES[$ses_idx]=""
        SESSION_AVAILABLE[$ses_idx]=false
        echo "  [Missing] $ses (matrix row and column will be NaN)"
    fi
done

if [ "$NUM_VALID" -lt 2 ]; then
    echo "Error: Found less than 2 valid sessions."
    exit 1
fi

echo "Validated $NUM_VALID of $NUM_SES sessions."
if [ "$NUM_VALID" -lt "$NUM_SES" ]; then
    echo "Missing sessions will remain in the 7-session matrices as NaN rows and columns."
fi
echo "Output directory: $OUT_DIR"
if [ "$MASK" = true ]; then
    echo "Masking: enabled. SynthStrip masks will be generated from each fixed registration image."
else
    echo "Masking: disabled."
fi
echo "Transform mode: $TRANSFORM_MODE."
if [ "$FORCE" = true ]; then
    echo "Resume mode: disabled. Complete re-run requested for selected transforms."
else
    echo "Resume mode: enabled. Existing pair metric files and transform outputs will be reused."
fi
[ "$PHYSICAL_VALUES" = true ] && echo "Percent difference: physical input values (no normalization)."
[ "$WM_MEAN_SCALE" = true ] && echo "Percent difference: fixed and warped images scaled to WM mean 1.0."
[ "$RECOMPUTE_METRICS" = true ] && echo "Metric refresh: enabled; existing transforms and warped images will be reused."

TOTAL_PAIRS=$((NUM_SES * NUM_SES))

# Older runs numbered temp metrics after dropping missing sessions. Use
# session-based names whenever a session is missing to avoid reusing a compact
# matrix entry for the wrong row or column.
USE_SESSION_TEMP_NAMES=false
[ "$NUM_VALID" -lt "$NUM_SES" ] && USE_SESSION_TEMP_NAMES=true

printf -v RUN_COMMAND '%q ' "$0" "${ORIGINAL_ARGS[@]}"
RUN_COMMAND=${RUN_COMMAND% }
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

write_matrix_provenance() {
    local matrix_file=$1
    local transform=$2
    local provenance_file="${matrix_file%.txt}_provenance.tsv"
    local idx status
    local row

    printf "script\tgenerated_at\tcommand\ttransform\tmasked\tregistration_id\tregistration_suffix\tcorrelation_id\tcorrelation_suffix\toutput_id\tsession\tstatus\tregistration_file\tcorrelation_file\n" > "$provenance_file"
    for (( idx=0; idx<NUM_SES; idx++ )); do
        status="missing"
        [ "${SESSION_AVAILABLE[$idx]}" = true ] && status="ready"
        row=("$0" "$GENERATED_AT" "$RUN_COMMAND" "$transform" "$MASK" "$REG_ID" "${REG_SUFFIX:-}" "$CORR_ID" "${CORR_SUFFIX:-}" "$OUT_ID" "${SESSION_DIRS[$idx]}" "$status" "${REG_FILES[$idx]:-}" "${CORR_FILES[$idx]:-}")
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${row[@]}" >> "$provenance_file"
    done
}

if [ "$FORCE" = true ] && [ "$MASK" = true ]; then
    echo "Clearing existing masks for complete re-run..."
    rm -f "${OUT_DIR}"/mask_*.nii.gz
fi

for (( t=0; t<${#TRANSFORM_FLAGS[@]}; t++ )); do
    FLAG="${TRANSFORM_FLAGS[$t]}"
    NAME="${TRANSFORM_NAMES[$t]}"
    
    CORR_MATRIX_FILE="${OUT_DIR}/correlation_matrix_${NAME}_${OUT_ID}.txt"
    RMSE_MATRIX_FILE="${OUT_DIR}/rmse_matrix_${NAME}_${OUT_ID}.txt"
    MAPD_MATRIX_FILE="${OUT_DIR}/mapd_matrix_${NAME}_${OUT_ID}.txt"
    > "$CORR_MATRIX_FILE"
    > "$RMSE_MATRIX_FILE"
    > "$MAPD_MATRIX_FILE"
    write_matrix_provenance "$CORR_MATRIX_FILE" "$NAME"
    write_matrix_provenance "$RMSE_MATRIX_FILE" "$NAME"
    write_matrix_provenance "$MAPD_MATRIX_FILE" "$NAME"

    if [ "$FORCE" = true ]; then
        echo "Clearing existing $NAME pair outputs for complete re-run..."
        rm -f "${OUT_DIR}/tmp_corr_${NAME}_"*.txt "${OUT_DIR}/tmp_rmse_${NAME}_"*.txt \
            "${OUT_DIR}/tmp_mapd_${NAME}_"*.txt "${OUT_DIR}/reg_${NAME}_mov_"*
    fi

    echo "Executing $NAME Pipeline with transform flag $FLAG across $TOTAL_PAIRS session pairs..."
    for (( i=0; i<NUM_SES; i++ )); do
        ROW_CORR=""
        ROW_RMSE=""
        ROW_MAPD=""
        MOV_SES="${SESSION_DIRS[$i]}"
        echo "  Matrix row $((i + 1))/$NUM_SES: moving session $MOV_SES"

        for (( j=0; j<NUM_SES; j++ )); do
            FIX_SES="${SESSION_DIRS[$j]}"

            OUT_PREFIX="${OUT_DIR}/reg_${NAME}_mov_${MOV_SES}_to_fix_${FIX_SES}_"
            WARPED_CORR="${OUT_PREFIX}CORR_Warped.nii.gz"
            PERCENT_DIFF="${OUT_PREFIX}PERCENT_DIFF.nii.gz"
            TRANSFORM_MAT="${OUT_PREFIX}0GenericAffine.mat"
            if [ "$USE_SESSION_TEMP_NAMES" = true ]; then
                TEMP_CORR="${OUT_DIR}/tmp_corr_${NAME}_${MOV_SES}_to_${FIX_SES}.txt"
                TEMP_RMSE="${OUT_DIR}/tmp_rmse_${NAME}_${MOV_SES}_to_${FIX_SES}.txt"
                TEMP_MAPD="${OUT_DIR}/tmp_mapd_${NAME}_${MOV_SES}_to_${FIX_SES}.txt"
            else
                TEMP_CORR="${OUT_DIR}/tmp_corr_${NAME}_${i}_${j}.txt"
                TEMP_RMSE="${OUT_DIR}/tmp_rmse_${NAME}_${i}_${j}.txt"
                TEMP_MAPD="${OUT_DIR}/tmp_mapd_${NAME}_${i}_${j}.txt"
            fi
            PAIR_NUM=$((i * NUM_SES + j + 1))

            echo "    [$NAME $PAIR_NUM/$TOTAL_PAIRS] Moving ${MOV_SES} to fixed ${FIX_SES}"

            if [[ "${SESSION_AVAILABLE[$i]}" != true || "${SESSION_AVAILABLE[$j]}" != true ]]; then
                echo "      Missing acquisition; writing NaN for this matrix pair."
                CORR="NaN"
                RMSE="NaN"
                MAPD="NaN"
                echo "$CORR" > "$TEMP_CORR"
                echo "$RMSE" > "$TEMP_RMSE"
                echo "$MAPD" > "$TEMP_MAPD"
                ROW_CORR="$ROW_CORR $CORR"
                ROW_RMSE="$ROW_RMSE $RMSE"
                ROW_MAPD="$ROW_MAPD $MAPD"
                continue
            fi

            echo "      Registration images: ${REG_FILES[$i]##*/} -> ${REG_FILES[$j]##*/}"
            echo "      Correlation/RMSE images: ${CORR_FILES[$i]##*/} -> ${CORR_FILES[$j]##*/}"

            if [ "$FORCE" = true ]; then
                rm -f "${OUT_PREFIX}"* "$TEMP_CORR" "$TEMP_RMSE" "$TEMP_MAPD"
            elif [ "$RECOMPUTE_METRICS" = false ] && [[ -s "$TEMP_CORR" && -s "$TEMP_RMSE" && -s "$TEMP_MAPD" && -s "$PERCENT_DIFF" ]]; then
                CORR=$(<"$TEMP_CORR")
                RMSE=$(<"$TEMP_RMSE")
                MAPD=$(<"$TEMP_MAPD")
                echo "      Reusing completed metrics: correlation=$CORR rmse=$RMSE mapd=${MAPD}%"
                ROW_CORR="$ROW_CORR $CORR"
                ROW_RMSE="$ROW_RMSE $RMSE"
                ROW_MAPD="$ROW_MAPD $MAPD"
                continue
            fi

            # 1. Registration
            if [ "$FORCE" = false ] && [ -f "$TRANSFORM_MAT" ]; then
                echo "      Reusing existing ANTs transform."
            else
                echo "      Running ANTs registration..."
                antsRegistrationSyNQuick.sh -d 3 -f "${REG_FILES[$j]}" -m "${REG_FILES[$i]}" -o "$OUT_PREFIX" -t "$FLAG" >/dev/null 2>&1
            fi

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
            if [ "$FORCE" = false ] && [ -f "$WARPED_CORR" ]; then
                echo "      Reusing existing transformed correlation/RMSE image."
            elif [ -f "$TRANSFORM_MAT" ]; then
                echo "      Applying transform to correlation/RMSE image..."
                antsApplyTransforms -d 3 -i "${CORR_FILES[$i]}" -r "${CORR_FILES[$j]}" -n Linear -t "$TRANSFORM_MAT" -o "$WARPED_CORR" >/dev/null 2>&1
            else
                echo "      Warning: transform matrix not found; writing NaN for this pair."
                echo "NaN" > "$TEMP_CORR"
                echo "NaN" > "$TEMP_RMSE"
                echo "NaN" > "$TEMP_MAPD"
            fi

            if [ -f "$WARPED_CORR" ]; then
                # 4a. Compute Correlation
                echo "      Computing FSL correlation..."
                CORR=$(fslcc $MASK_CMD "${CORR_FILES[$j]}" "$WARPED_CORR" | awk '{print $3}')
                [ -z "$CORR" ] && CORR="NaN"

                # 4b. Compute RMSE
                echo "      Computing RMSE..."
                TMP_SQR="${OUT_DIR}/tmp_sqr_${NAME}_${MOV_SES}_to_${FIX_SES}.nii.gz"

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

                # 4c. Compute the percent-difference image and its mean absolute value.
                echo "      Computing percent-difference image..."
                PERCENT_DIFF_ARGS=(
                    --fixed "${CORR_FILES[$j]}"
                    --moving "$WARPED_CORR"
                    --output "$PERCENT_DIFF"
                    --metric-output "$TEMP_MAPD"
                )
                if [ "$MASK" = true ]; then
                    PERCENT_DIFF_ARGS+=(--mask "$MASK_FILE")
                fi
                if [ "$PHYSICAL_VALUES" = true ]; then
                    PERCENT_DIFF_ARGS+=(--physical-values)
                fi
                if [ "$WM_MEAN_SCALE" = true ]; then
                    WM_SCALE_MASK="${WM_ROOT}/${FIX_SES}/wm_mask_fast_pve95.nii.gz"
                    if [ ! -f "$WM_SCALE_MASK" ]; then
                        echo "      Error: WM mean-scale mask not found: $WM_SCALE_MASK" >&2
                        exit 1
                    fi
                    PERCENT_DIFF_ARGS+=(--mean-scale-mask "$WM_SCALE_MASK")
                fi
                if env -u PYTHONPATH -u PYTHONHOME "$PERCENT_DIFF_PYTHON" \
                    "$PERCENT_DIFF_SCRIPT" "${PERCENT_DIFF_ARGS[@]}"; then
                    MAPD=$(<"$TEMP_MAPD")
                else
                    echo "      Warning: percent-difference computation failed; writing NaN." >&2
                    MAPD="NaN"
                    echo "$MAPD" > "$TEMP_MAPD"
                    rm -f "$PERCENT_DIFF"
                fi

                echo "$CORR" > "$TEMP_CORR"
                echo "$RMSE" > "$TEMP_RMSE"
                echo "      Result: correlation=$CORR rmse=$RMSE mapd=${MAPD}%"
            else
                echo "      Warning: transformed correlation/RMSE image not found; writing NaN for this pair."
                CORR="NaN"
                RMSE="NaN"
                MAPD="NaN"
                echo "$CORR" > "$TEMP_CORR"
                echo "$RMSE" > "$TEMP_RMSE"
                echo "$MAPD" > "$TEMP_MAPD"
            fi

            ROW_CORR="$ROW_CORR $CORR"
            ROW_RMSE="$ROW_RMSE $RMSE"
            ROW_MAPD="$ROW_MAPD $MAPD"
        done
        echo "$ROW_CORR" >> "$CORR_MATRIX_FILE"
        echo "$ROW_RMSE" >> "$RMSE_MATRIX_FILE"
        echo "$ROW_MAPD" >> "$MAPD_MATRIX_FILE"
    done
done
echo "Linear matrices completed: Correlation, RMSE, and mean absolute percent difference."
echo "Generating plots..."
env -u PYTHONPATH -u PYTHONHOME MPLBACKEND=Agg "$PLOT_PYTHON" "$PLOT_SCRIPT" "$OUT_ID"

#!/bin/bash
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
PLOT_PYTHON="/home/users/sasbo/miniconda3/envs/THS_env/bin/python3"
ORIGINAL_ARGS=("$@")

print_usage() {
    echo "Usage: ./aggregate_syn_matrix.sh -r <reg_id> [-R reg_suffix] [-c corr_id] [-C corr_suffix] [-m] [--cleanup-temp]"
    echo "Legacy: ./aggregate_syn_matrix.sh <identifier> [suffix]"
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

MASK=false
CLEANUP_TEMP=false
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
        --cleanup-temp)
            CLEANUP_TEMP=true
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
printf -v RUN_COMMAND '%q ' "$0" "${ORIGINAL_ARGS[@]}"
RUN_COMMAND=${RUN_COMMAND% }
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ "$REG_DATASET_ID" = "$CORR_DATASET_ID" ]; then
    OUT_ID="$CORR_DATASET_ID"
else
    OUT_ID="reg-${REG_DATASET_ID}__corr-${CORR_DATASET_ID}"
fi
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"

DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${OUT_ID}"
CORR_MATRIX_FILE="${OUT_DIR}/correlation_matrix_SyN_${OUT_ID}.txt"
RMSE_MATRIX_FILE="${OUT_DIR}/rmse_matrix_SyN_${OUT_ID}.txt"
MAPD_MATRIX_FILE="${OUT_DIR}/mapd_matrix_SyN_${OUT_ID}.txt"

if [ ! -d "$OUT_DIR" ]; then
    echo "Error: Directory $OUT_DIR not found."
    exit 1
fi

> "$CORR_MATRIX_FILE"
> "$RMSE_MATRIX_FILE"
> "$MAPD_MATRIX_FILE"
NUM_SES=7
SESSION_DIRS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260602_THS_ses04"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)

write_syn_matrix_provenance() {
    local matrix_file=$1
    local provenance_file="${matrix_file%.txt}_provenance.tsv"
    local row pair_file mov_ses fix_ses

    printf "script\tgenerated_at\tcommand\ttransform\tmasked\tregistration_id\tregistration_suffix\tcorrelation_id\tcorrelation_suffix\toutput_id\tjob_id\ttask_id\tmoving_session\tfixed_session\tstatus\tmoving_registration_file\tfixed_registration_file\tmoving_correlation_file\tfixed_correlation_file\n" > "$provenance_file"
    for (( i=0; i<NUM_SES; i++ )); do
        for (( j=0; j<NUM_SES; j++ )); do
            pair_file="${OUT_DIR}/provenance_SyN_${i}_${j}.tsv"
            if [ -s "$pair_file" ]; then
                sed -n '2p' "$pair_file" >> "$provenance_file"
            else
                mov_ses="${SESSION_DIRS[$i]}"
                fix_ses="${SESSION_DIRS[$j]}"
                row=("$0" "$GENERATED_AT" "$RUN_COMMAND" "SyN" "$MASK" "$REG_ID" "${REG_SUFFIX:-}" "$CORR_ID" "${CORR_SUFFIX:-}" "$OUT_ID" "" "${i}_${j}" "$mov_ses" "$fix_ses" "provenance_unavailable" "" "" "" "")
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${row[@]}" >> "$provenance_file"
            fi
        done
    done
}

echo "Aggregating SyN matrices for $OUT_ID..."

for (( i=0; i<$NUM_SES; i++ )); do
    ROW_CORR=""
    ROW_RMSE=""
    ROW_MAPD=""
    for (( j=0; j<$NUM_SES; j++ )); do
        CORR_TEMP_FILE="${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
        RMSE_TEMP_FILE="${OUT_DIR}/tmp_rmse_SyN_${i}_${j}.txt"
        MAPD_TEMP_FILE="${OUT_DIR}/tmp_mapd_SyN_${i}_${j}.txt"

        if [ -f "$CORR_TEMP_FILE" ]; then
            CORR=$(cat "$CORR_TEMP_FILE")
        else
            CORR="NaN"
        fi

        if [ -f "$RMSE_TEMP_FILE" ]; then
            RMSE=$(cat "$RMSE_TEMP_FILE")
        else
            RMSE="NaN"
        fi

        if [ -f "$MAPD_TEMP_FILE" ]; then
            MAPD=$(cat "$MAPD_TEMP_FILE")
        else
            MAPD="NaN"
        fi

        ROW_CORR="$ROW_CORR $CORR"
        ROW_RMSE="$ROW_RMSE $RMSE"
        ROW_MAPD="$ROW_MAPD $MAPD"
    done
    echo "$ROW_CORR" >> "$CORR_MATRIX_FILE"
    echo "$ROW_RMSE" >> "$RMSE_MATRIX_FILE"
    echo "$ROW_MAPD" >> "$MAPD_MATRIX_FILE"
done

echo "Correlation matrix built at: $CORR_MATRIX_FILE"
echo "RMSE matrix built at: $RMSE_MATRIX_FILE"
echo "MAPD matrix built at: $MAPD_MATRIX_FILE"
write_syn_matrix_provenance "$CORR_MATRIX_FILE"
write_syn_matrix_provenance "$RMSE_MATRIX_FILE"
write_syn_matrix_provenance "$MAPD_MATRIX_FILE"
if [ "$CLEANUP_TEMP" = true ]; then
    rm -f "${OUT_DIR}"/tmp_corr_SyN_*.txt 2>/dev/null
    rm -f "${OUT_DIR}"/tmp_rmse_SyN_*.txt 2>/dev/null
    rm -f "${OUT_DIR}"/tmp_mapd_SyN_*.txt 2>/dev/null
else
    echo "Pair temp files kept for resume support."
fi

if [ -f "$PLOT_SCRIPT" ] && [ -x "$PLOT_PYTHON" ]; then
    echo "Generating plots..."
    env -u PYTHONPATH -u PYTHONHOME MPLBACKEND=Agg "$PLOT_PYTHON" "$PLOT_SCRIPT" "$OUT_ID"
else
    echo "Warning: Plotting script or Python executable not found; skipping plots." >&2
fi

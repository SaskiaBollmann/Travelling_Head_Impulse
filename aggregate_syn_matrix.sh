#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
    exec /bin/bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLOT_SCRIPT="${SCRIPT_DIR}/plot_image_correlation.py"
PLOT_PYTHON="/home/users/sasbo/miniconda3/envs/THS_env/bin/python3"

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

[ -n "$CORR_SUFFIX" ] && CORR_SUFFIX=$(strip_leading_underscores "$CORR_SUFFIX")

OUT_ID="${CORR_ID}"
[ -n "$CORR_SUFFIX" ] && OUT_ID="${OUT_ID}_${CORR_SUFFIX}"
[ "$MASK" = true ] && OUT_ID="${OUT_ID}_masked"

DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${OUT_ID}"
CORR_MATRIX_FILE="${OUT_DIR}/correlation_matrix_SyN_${OUT_ID}.txt"
RMSE_MATRIX_FILE="${OUT_DIR}/rmse_matrix_SyN_${OUT_ID}.txt"

if [ ! -d "$OUT_DIR" ]; then
    echo "Error: Directory $OUT_DIR not found."
    exit 1
fi

> "$CORR_MATRIX_FILE"
> "$RMSE_MATRIX_FILE"
NUM_SES=7

echo "Aggregating SyN matrices for $OUT_ID..."

for (( i=0; i<$NUM_SES; i++ )); do
    ROW_CORR=""
    ROW_RMSE=""
    for (( j=0; j<$NUM_SES; j++ )); do
        CORR_TEMP_FILE="${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
        RMSE_TEMP_FILE="${OUT_DIR}/tmp_rmse_SyN_${i}_${j}.txt"

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

        ROW_CORR="$ROW_CORR $CORR"
        ROW_RMSE="$ROW_RMSE $RMSE"
    done
    echo "$ROW_CORR" >> "$CORR_MATRIX_FILE"
    echo "$ROW_RMSE" >> "$RMSE_MATRIX_FILE"
done

echo "Correlation matrix built at: $CORR_MATRIX_FILE"
echo "RMSE matrix built at: $RMSE_MATRIX_FILE"
if [ "$CLEANUP_TEMP" = true ]; then
    rm -f "${OUT_DIR}"/tmp_corr_SyN_*.txt 2>/dev/null
    rm -f "${OUT_DIR}"/tmp_rmse_SyN_*.txt 2>/dev/null
else
    echo "Pair temp files kept for resume support."
fi

if [ -f "$PLOT_SCRIPT" ] && [ -x "$PLOT_PYTHON" ]; then
    echo "Generating plots..."
    env -u PYTHONPATH -u PYTHONHOME MPLBACKEND=Agg "$PLOT_PYTHON" "$PLOT_SCRIPT" "$OUT_ID"
else
    echo "Warning: Plotting script or Python executable not found; skipping plots." >&2
fi

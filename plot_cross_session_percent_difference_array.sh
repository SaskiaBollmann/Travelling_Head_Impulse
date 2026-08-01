#!/bin/bash
#SBATCH --job-name=cross_session_pdiff
#SBATCH --time=00:15:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=2
#SBATCH --mem=16GB
#SBATCH --array=0-125
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/cross_session_pdiff_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/cross_session_pdiff_%A_%a.error

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
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
           [ -f "${candidate}/plot_cross_session_percent_difference.py" ]; then
            printf '%s\n' "${candidate}/plot_cross_session_percent_difference.py"
            return 0
        fi
    done

    return 1
}

PLOT_SCRIPT=$(resolve_plot_script) || {
    echo "Error: Could not locate plot_cross_session_percent_difference.py." >&2
    exit 1
}
PYTHON="/home/users/sasbo/miniconda3/bin/python3"

SESSIONS=(
    260529_THS_ses01
    260601_THS_ses02
    260602_THS_ses03
    260602_THS_ses04
    260611_THS_ses05
    260618_THS_ses06
    260618_THS_ses07
)
TRANSFORMS=(Rigid Affine SyN)

# One task per ordered (moving, fixed) pair with moving != fixed, for each
# transform. Self-pairs are skipped: a session registered to itself is not a
# cross-session comparison.
COMBOS=()
for transform in "${TRANSFORMS[@]}"; do
    for moving in "${SESSIONS[@]}"; do
        for fixed in "${SESSIONS[@]}"; do
            if [ "$moving" != "$fixed" ]; then
                COMBOS+=("${transform} ${moving} ${fixed}")
            fi
        done
    done
done

TASK_ID=${SLURM_ARRAY_TASK_ID:-0}
if (( TASK_ID < 0 || TASK_ID >= ${#COMBOS[@]} )); then
    echo "Error: Task ID $TASK_ID is outside the combination list (0-$((${#COMBOS[@]} - 1)))." >&2
    exit 1
fi

read -r TRANSFORM MOVING FIXED <<< "${COMBOS[$TASK_ID]}"
echo "Transform=${TRANSFORM} moving=${MOVING} fixed=${FIXED}"

"$PYTHON" "$PLOT_SCRIPT" \
    --moving-session "$MOVING" \
    --fixed-session "$FIXED" \
    --transform "$TRANSFORM"

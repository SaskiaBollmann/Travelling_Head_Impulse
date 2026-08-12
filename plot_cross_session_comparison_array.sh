#!/bin/bash
#SBATCH --job-name=cross_session_compare
#SBATCH --time=00:15:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=2
#SBATCH --mem=16GB
#SBATCH --array=0-8
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/cross_session_compare_%A_%a.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/logs/cross_session_compare_%A_%a.error

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
           [ -f "${candidate}/plot_cross_session_comparison.py" ]; then
            printf '%s\n' "${candidate}/plot_cross_session_comparison.py"
            return 0
        fi
    done

    return 1
}

PLOT_SCRIPT=$(resolve_plot_script) || {
    echo "Error: Could not locate plot_cross_session_comparison.py." >&2
    exit 1
}
PYTHON="/home/users/sasbo/miniconda3/envs/THS_env/bin/python3"

MOVING=260601_THS_ses02
FIXED_SESSIONS=(
    260602_THS_ses03
    260602_THS_ses04
    260618_THS_ses06
)
TRANSFORMS=(Rigid Affine SyN)

# Nine tasks: ses02 registered to ses03, ses04, and ses06 for each transform.
# Each task renders both whole-brain and WM panels, producing 18 figures total.
COMBOS=()
for transform in "${TRANSFORMS[@]}"; do
    for fixed in "${FIXED_SESSIONS[@]}"; do
        COMBOS+=("${transform} ${MOVING} ${fixed}")
    done
done

TASK_ID=${SLURM_ARRAY_TASK_ID:-0}
if (( TASK_ID < 0 || TASK_ID >= ${#COMBOS[@]} )); then
    echo "Error: Task ID $TASK_ID is outside the combination list (0-$((${#COMBOS[@]} - 1)))." >&2
    exit 1
fi

read -r TRANSFORM MOVING FIXED <<< "${COMBOS[$TASK_ID]}"
echo "Transform=${TRANSFORM} moving=${MOVING} fixed=${FIXED}"

env -u PYTHONPATH -u PYTHONHOME -u PYTHONPYCACHEPREFIX \
    PYTHONNOUSERSITE=1 MPLBACKEND=Agg "$PYTHON" "$PLOT_SCRIPT" \
    --modality mp2rage \
    --region both \
    --moving-session "$MOVING" \
    --fixed-session "$FIXED" \
    --transform "$TRANSFORM"

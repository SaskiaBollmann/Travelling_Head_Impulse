#!/bin/bash
#SBATCH --job-name=realign_epi_afni
#SBATCH --time=08:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=32GB
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs/realign_epi_afni_%j.out
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs/realign_epi_afni_%j.err

set -euo pipefail

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
OUT_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/realignment_afni"
IMAGE_TYPE="both"
FORCE=false
DRY_RUN=false
SESSIONS=()
ALL_SESSIONS=(
    "260529_THS_ses01" "260601_THS_ses02" "260602_THS_ses03"
    "260602_THS_ses04" "260611_THS_ses05" "260618_THS_ses06"
    "260618_THS_ses07"
)

usage() {
    cat <<'EOF'
Usage: preprocess_epi_afni.sh [options]

Realign every 4D dzne_ep3d and ep2d_bold magnitude run with AFNI 3dvolreg,
then calculate its temporal mean and tSNR from the realigned time series.

Options:
  -s, --session NAME       Process one session (repeatable). Default: all.
  -t, --type TYPE          ep3d, ep2d, or both (default: both).
  -i, --input-root DIR     Root containing the session directories.
  -o, --output-root DIR    Derivative output root.
  -F, --force              Recompute and overwrite outputs.
  -n, --dry-run            Print selected runs and commands without processing.
  -h, --help               Show this help.

Each run is aligned independently to its middle time point. Single-volume
images and *_ph phase images are skipped. AFNI's 3dTstat -tsnr computes
abs(mean)/temporal-standard-deviation without detrending.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -s|--session)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            SESSIONS+=("$2"); shift 2 ;;
        -t|--type)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            IMAGE_TYPE="${2,,}"; shift 2 ;;
        -i|--input-root)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            BASE_DIR="$2"; shift 2 ;;
        -o|--output-root)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            OUT_ROOT="$2"; shift 2 ;;
        -F|--force) FORCE=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$IMAGE_TYPE" in
    ep3d|ep2d|both) ;;
    *) echo "Error: --type must be ep3d, ep2d, or both." >&2; exit 2 ;;
esac
[ "${#SESSIONS[@]}" -gt 0 ] || SESSIONS=("${ALL_SESSIONS[@]}")

command -v ml >/dev/null 2>&1 || {
    echo "Error: The 'ml' module command is unavailable." >&2; exit 1;
}
ml afni/26.0.07
for program in 3dinfo 3dvolreg 3dTstat; do
    command -v "$program" >/dev/null 2>&1 || {
        echo "Error: ${program} was not found after loading AFNI." >&2; exit 1;
    }
done

strip_nii_extension() {
    local name=${1##*/}
    name=${name%.gz}
    printf '%s\n' "${name%.nii}"
}

classify_image() {
    local name=${1##*/}
    case "$name" in
        *_ph.nii|*_ph.nii.gz) return 1 ;;
        dzne_ep3d*.nii|dzne_ep3d*.nii.gz) echo ep3d ;;
        ep2d_bold*.nii|ep2d_bold*.nii.gz) echo ep2d ;;
        *) return 1 ;;
    esac
}

run_command() {
    if [ "$DRY_RUN" = true ]; then
        printf '  command:'; printf ' %q' "$@"; printf '\n'
    else
        # Invocation happens only for a missing/incomplete output or --force.
        # Overwrite permits clean recovery from a partially completed command.
        AFNI_DECONFLICT=OVERWRITE "$@"
    fi
}

process_run() {
    local session=$1 input=$2 kind=$3
    local nvol base_index stem out_dir realigned mean tsnr motion matrix output

    nvol=$(3dinfo -nt "$input")
    [[ "$nvol" =~ ^[0-9]+$ ]] || {
        echo "Error: Could not read time-point count: ${input}" >&2; return 1;
    }
    if [ "$nvol" -le 1 ]; then
        echo "[Static] ${session}: ${input##*/}; skipping."
        return
    fi

    base_index=$((nvol / 2))
    stem=$(strip_nii_extension "$input")
    out_dir="${OUT_ROOT}/${session}/${stem}_afni"
    realigned="${out_dir}/${stem}_realigned.nii.gz"
    mean="${out_dir}/${stem}_mean.nii.gz"
    tsnr="${out_dir}/${stem}_tsnr.nii.gz"
    motion="${out_dir}/${stem}_motion.1D"
    matrix="${out_dir}/${stem}_aff12.1D"

    echo "[Ready] ${session} (${kind}): ${stem}"
    echo "  time points: ${nvol}; reference index: ${base_index}"
    echo "  output dir:  ${out_dir}"
    if [ "$DRY_RUN" = true ]; then
        run_command 3dvolreg -twopass -zpad 4 -base "$base_index" \
            -1Dfile "$motion" -1Dmatrix_save "$matrix" \
            -prefix "$realigned" "$input"
        run_command 3dTstat -mean -prefix "$mean" "$realigned"
        run_command 3dTstat -tsnr -prefix "$tsnr" "$realigned"
        return
    fi

    mkdir -p "$out_dir"
    if [ "$FORCE" = true ] || [ ! -f "$realigned" ] ||
       [ ! -f "$motion" ] || [ ! -f "$matrix" ]; then
        run_command 3dvolreg -twopass -zpad 4 -base "$base_index" \
            -1Dfile "$motion" -1Dmatrix_save "$matrix" \
            -prefix "$realigned" "$input"
    else
        echo "  [Exists] Realigned series and motion files; reusing."
    fi
    if [ "$FORCE" = true ] || [ ! -f "$mean" ]; then
        run_command 3dTstat -mean -prefix "$mean" "$realigned"
    else
        echo "  [Exists] Mean image; reusing."
    fi
    if [ "$FORCE" = true ] || [ ! -f "$tsnr" ]; then
        run_command 3dTstat -tsnr -prefix "$tsnr" "$realigned"
    else
        echo "  [Exists] tSNR image; reusing."
    fi

    for output in "$realigned" "$mean" "$tsnr" "$motion" "$matrix"; do
        [ -f "$output" ] || {
            echo "Error: Expected output was not created: ${output}" >&2; return 1;
        }
    done
    echo "[Done] ${stem}"
}

failures=0
selected=0
for session in "${SESSIONS[@]}"; do
    session_dir="${BASE_DIR}/${session}"
    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: ${session_dir}" >&2
        failures=$((failures + 1)); continue
    fi
    while IFS= read -r input; do
        [ -n "$input" ] || continue
        kind=$(classify_image "$input") || continue
        if [ "$IMAGE_TYPE" != both ] && [ "$IMAGE_TYPE" != "$kind" ]; then
            continue
        fi
        selected=$((selected + 1))
        process_run "$session" "$input" "$kind" || failures=$((failures + 1))
    done < <(find "$session_dir" -maxdepth 1 -type f | sort)
done

[ "$selected" -gt 0 ] || {
    echo "Error: No matching dzne_ep3d or ep2d_bold images were found." >&2; exit 1;
}
if [ "$failures" -gt 0 ]; then
    echo "Completed with ${failures} failed run(s)." >&2; exit 1
fi
echo "AFNI realignment, mean, and tSNR preprocessing complete."

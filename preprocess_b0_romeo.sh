#!/bin/bash
#SBATCH --job-name=unwrap_b0_romeo
#SBATCH --time=01:00:00
#SBATCH --partition=owners
#SBATCH --cpus-per-task=4
#SBATCH --mem=16GB
#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs/unwrap_b0_romeo_%j.out
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs/unwrap_b0_romeo_%j.err

set -euo pipefail

BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
OUT_ROOT="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/b0_romeo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HZ_CONVERTER="${SCRIPT_DIR}/convert_b0_phase_to_hz.py"
PYTHON="/home/users/sasbo/miniconda3/bin/python3"
FAMILY="both"
FORCE=false
DRY_RUN=false
SESSIONS=()

ALL_SESSIONS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260602_THS_ses04"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)

usage() {
    cat <<'EOF'
Usage: preprocess_b0_romeo.sh [options]

Unwrap GRE B0 phase images (*_e2_ph.nii[.gz]) with ROMEO, using the
corresponding first-echo magnitude image (*_e1.nii[.gz]) as a guide.

Options:
  -s, --session NAME       Process one session (repeatable). Default: all.
  -f, --family NAME        standard, nd, or both (default: both).
  -i, --input-root DIR     Root containing the session directories.
  -o, --output-root DIR    Derivative output root.
  -F, --force              Overwrite existing unwrapped and Hz images.
  -n, --dry-run            Print inputs and commands without running ROMEO.
  -h, --help               Show this help.

Examples:
  sbatch preprocess_b0_romeo.sh
  sbatch preprocess_b0_romeo.sh --session 260529_THS_ses01 --family standard
  ./preprocess_b0_romeo.sh --family nd --dry-run

Output:
  <output-root>/<session>/<phase-basename>_romeo/unwrapped.nii
  <output-root>/<session>/<phase-basename>_romeo/fieldmap_hz.nii.gz

Note: *_e1 is magnitude and is not itself unwrapped. The wrapped phase is
*_e2_ph. ROMEO rescales the stored Siemens phase values to [-pi, pi].
The unwrapped phase difference is divided by 2*pi*DeltaTE to obtain Hz;
DeltaTE is read separately for every acquisition from its JSON sidecars.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -s|--session)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            SESSIONS+=("$2"); shift 2 ;;
        -f|--family)
            [ "$#" -ge 2 ] || { echo "Error: $1 requires a value." >&2; exit 2; }
            FAMILY="${2,,}"; shift 2 ;;
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

case "$FAMILY" in
    standard|nd|both) ;;
    *) echo "Error: --family must be standard, nd, or both." >&2; exit 2 ;;
esac

if [ "${#SESSIONS[@]}" -eq 0 ]; then
    SESSIONS=("${ALL_SESSIONS[@]}")
fi

if [ "$DRY_RUN" = false ]; then
    command -v ml >/dev/null 2>&1 || {
        echo "Error: The 'ml' module command is unavailable." >&2
        exit 1
    }
    ml romeo/3.2.8
    command -v romeo >/dev/null 2>&1 || {
        echo "Error: ROMEO was not found after loading romeo/3.2.8." >&2
        exit 1
    }
    [ -x "$PYTHON" ] || { echo "Error: Python not found: ${PYTHON}" >&2; exit 1; }
    [ -f "$HZ_CONVERTER" ] || { echo "Error: Hz converter not found: ${HZ_CONVERTER}" >&2; exit 1; }
fi

find_one() {
    local directory=$1 regex=$2
    local matches=()
    while IFS= read -r match; do
        [ -n "$match" ] && matches+=("$match")
    done < <(find "$directory" -maxdepth 1 -type f 2>/dev/null |
        sort | grep -E "/${regex}$" || true)

    if [ "${#matches[@]}" -gt 1 ]; then
        echo "Error: More than one file matched in ${directory}:" >&2
        printf '  %s\n' "${matches[@]}" >&2
        return 2
    fi
    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s\n' "${matches[0]}"
    fi
    return 0
}

strip_nii_extension() {
    local name=${1##*/}
    name=${name%.gz}
    printf '%s\n' "${name%.nii}"
}

sidecar_path() {
    local path=$1
    path=${path%.gz}
    printf '%s.json\n' "${path%.nii}"
}

process_family() {
    local session=$1 family=$2
    local session_dir="${BASE_DIR}/${session}"
    local phase_regex magnitude_regex phase magnitude phase_json magnitude_json
    local session_out_dir romeo_out_dir output hz_output hz_json sidecar

    if [ "$family" = "nd" ]; then
        phase_regex='gre_b0map_4iso_sag_ND_[0-9]+_e2_ph\.nii(\.gz)?'
        magnitude_regex='gre_b0map_4iso_sag_ND_[0-9]+_e1\.nii(\.gz)?'
    else
        phase_regex='gre_b0map_4iso_sag_[0-9]+_e2_ph\.nii(\.gz)?'
        magnitude_regex='gre_b0map_4iso_sag_[0-9]+_e1\.nii(\.gz)?'
    fi

    phase=$(find_one "$session_dir" "$phase_regex") || return
    magnitude=$(find_one "$session_dir" "$magnitude_regex") || return

    if [ -z "$phase" ] && [ -z "$magnitude" ]; then
        echo "[Missing] ${session} (${family}): no acquisition found; skipping."
        return
    fi
    if [ -z "$phase" ] || [ -z "$magnitude" ]; then
        echo "Error: ${session} (${family}) has an incomplete pair." >&2
        echo "  phase:     ${phase:-missing}" >&2
        echo "  magnitude: ${magnitude:-missing}" >&2
        return 1
    fi

    session_out_dir="${OUT_ROOT}/${session}"
    romeo_out_dir="${session_out_dir}/$(strip_nii_extension "$phase")_romeo"
    output="${romeo_out_dir}/unwrapped.nii"
    hz_output="${romeo_out_dir}/fieldmap_hz.nii.gz"
    hz_json="${romeo_out_dir}/fieldmap_hz.json"
    phase_json=$(sidecar_path "$phase")
    magnitude_json=$(sidecar_path "$magnitude")

    for sidecar in "$phase_json" "$magnitude_json"; do
        [ -f "$sidecar" ] || {
            echo "Error: Missing JSON sidecar: ${sidecar}" >&2
            return 1
        }
    done


    echo "[Ready] ${session} (${family})"
    echo "  phase:     ${phase}"
    echo "  magnitude: ${magnitude}"
    echo "  output:    ${output}"
    echo "  Hz output: ${hz_output}"

    if [ "$DRY_RUN" = true ]; then
        if [ ! -f "$output" ] || [ "$FORCE" = true ]; then
            printf '  command:   romeo -p %q -m %q -k robustmask -u -o %q\n' \
                "$phase" "$magnitude" "$romeo_out_dir"
        fi
        printf '  command:   %q %q --unwrapped %q --echo1-json %q --echo2-json %q --output %q --output-json %q\n' \
            "$PYTHON" "$HZ_CONVERTER" "$output" "$magnitude_json" \
            "$phase_json" "$hz_output" "$hz_json"
        return
    fi

    mkdir -p "$session_out_dir"
    if [ ! -f "$output" ] || [ "$FORCE" = true ]; then
        romeo -p "$phase" -m "$magnitude" -k robustmask -u -o "$romeo_out_dir"
    else
        echo "[Exists] ${output}; reusing unwrapped phase."
    fi
    [ -f "$output" ] || {
        echo "Error: ROMEO completed without creating ${output}." >&2
        return 1
    }
    if [ ! -f "$hz_output" ] || [ "$FORCE" = true ]; then
        "$PYTHON" "$HZ_CONVERTER" \
            --unwrapped "$output" \
            --echo1-json "$magnitude_json" \
            --echo2-json "$phase_json" \
            --output "$hz_output" \
            --output-json "$hz_json"
    else
        echo "[Exists] ${hz_output}; skipping (use --force to overwrite)."
    fi
    echo "[Done] ${output} and ${hz_output}"
}

case "$FAMILY" in
    standard) families=("standard") ;;
    nd) families=("nd") ;;
    both) families=("standard" "nd") ;;
esac

failures=0
for session in "${SESSIONS[@]}"; do
    session_dir="${BASE_DIR}/${session}"
    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: ${session_dir}" >&2
        failures=$((failures + 1))
        continue
    fi
    for family in "${families[@]}"; do
        process_family "$session" "$family" || failures=$((failures + 1))
    done
done

if [ "$failures" -gt 0 ]; then
    echo "Completed with ${failures} failed item(s)." >&2
    exit 1
fi
echo "ROMEO B0 unwrapping complete."

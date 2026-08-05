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

When a session has more than one 4D ep3d run from the same protocol (e.g.
dzne_ep3d_vasoNIH acquired as two back-to-back runs), the runs are
concatenated in series-number order with 3dTcat into a single combined time
series first, and realignment/mean/tSNR run once on that combined series
instead of once per run. This only applies to ep3d runs that share one grid;
mismatched or single-run families are processed as before.

Options:
  -s, --session NAME       Process one session (repeatable). Default: all.
  -t, --type TYPE          ep3d, ep2d, or both (default: both).
  -i, --input-root DIR     Root containing the session directories.
  -o, --output-root DIR    Derivative output root.
  -F, --force              Recompute and overwrite outputs.
  -n, --dry-run            Print selected runs and commands without processing.
  -h, --help               Show this help.

Each (possibly combined) series is aligned to its own middle time point.
Single-volume images and *_ph phase images are skipped. AFNI's 3dTstat -tsnr
computes abs(mean)/temporal-standard-deviation without detrending.
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
for program in 3dinfo 3dvolreg 3dTstat 3dTcat; do
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

family_key() {
    # Strip a trailing series number (e.g. "..._65" -> "...") so repeated
    # runs of the same protocol group together; series-numberless stems
    # (e.g. multi-echo "..._e1") are left as their own singleton family.
    local stem=$1
    if [[ "$stem" =~ ^(.*)_([0-9]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "$stem"
    fi
}

series_number() {
    local stem=$1
    if [[ "$stem" =~ _([0-9]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '0\n'
    fi
}

grids_match() {
    local result
    result=$(3dinfo -same_grid "$1" "$2" 2>/dev/null) || return 1
    [ "$(printf '%s\n' "$result" | sort -u)" = "1" ]
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
    local session=$1 input=$2 kind=$3 known_nvol=${4:-} known_base_index=${5:-}
    local nvol base_index stem out_dir realigned mean tsnr motion matrix output

    if [ -n "$known_nvol" ]; then
        # Set by the caller for a not-yet-materialized combined series (its
        # volume count is just the sum of its already-on-disk source runs),
        # so this does not depend on $input existing yet.
        nvol=$known_nvol
    else
        nvol=$(3dinfo -nt "$input")
    fi
    [[ "$nvol" =~ ^[0-9]+$ ]] || {
        echo "Error: Could not read time-point count: ${input}" >&2; return 1;
    }
    if [ "$nvol" -le 1 ]; then
        echo "[Static] ${session}: ${input##*/}; skipping."
        return
    fi

    if [ -n "$known_base_index" ]; then
        # Set by the caller for a combined series, so the reference volume
        # falls in the middle of the first source run instead of landing
        # near the seam between runs.
        base_index=$known_base_index
    else
        base_index=$((nvol / 2))
    fi
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

concatenate_runs() {
    # Only the final combined path goes to stdout (the caller captures it via
    # command substitution); every diagnostic line must go to stderr instead.
    local session=$1 combined_stem=$2
    shift 2
    local inputs=("$@")
    local out_dir="${OUT_ROOT}/${session}/${combined_stem}_afni"
    local combined="${out_dir}/${combined_stem}.nii.gz"

    echo "[Combine] ${session}: ${combined_stem} <- ${#inputs[@]} runs" >&2
    local input
    for input in "${inputs[@]}"; do
        echo "    ${input##*/}" >&2
    done

    if [ "$DRY_RUN" = true ]; then
        run_command 3dTcat -prefix "$combined" "${inputs[@]}" >&2
        printf '%s\n' "$combined"
        return
    fi

    mkdir -p "$out_dir"
    if [ "$FORCE" = true ] || [ ! -f "$combined" ]; then
        run_command 3dTcat -prefix "$combined" "${inputs[@]}" >&2
    else
        echo "  [Exists] Combined series; reusing." >&2
    fi
    [ -f "$combined" ] || {
        echo "Error: Expected combined output was not created: ${combined}" >&2
        return 1
    }
    printf '%s\n' "$combined"
}

failures=0
selected=0
for session in "${SESSIONS[@]}"; do
    session_dir="${BASE_DIR}/${session}"
    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: ${session_dir}" >&2
        failures=$((failures + 1)); continue
    fi

    unset family_members
    declare -A family_members=()
    while IFS= read -r input; do
        [ -n "$input" ] || continue
        kind=$(classify_image "$input") || continue
        if [ "$IMAGE_TYPE" != both ] && [ "$IMAGE_TYPE" != "$kind" ]; then
            continue
        fi
        family=$(family_key "$(strip_nii_extension "$input")")
        family_members["${kind}:${family}"]+="${input}"$'\n'
    done < <(find "$session_dir" -maxdepth 1 -type f | sort)

    for key in "${!family_members[@]}"; do
        kind=${key%%:*}
        mapfile -t members < <(printf '%s' "${family_members[$key]}" | sed '/^$/d')

        # Only ep3d runs are candidates for auto-combining, and only the
        # multi-volume (dynamic) ones among them -- a lone static image
        # sharing the family name (e.g. an SBRef) is processed on its own.
        dynamic=()
        static=()
        if [ "$kind" = ep3d ] && [ "${#members[@]}" -gt 1 ]; then
            for input in "${members[@]}"; do
                nvol=$(3dinfo -nt "$input")
                if [[ "$nvol" =~ ^[0-9]+$ ]] && [ "$nvol" -gt 1 ]; then
                    dynamic+=("$input")
                else
                    static+=("$input")
                fi
            done
        else
            static=("${members[@]}")
        fi

        if [ "${#static[@]}" -gt 0 ]; then
            for input in "${static[@]}"; do
                selected=$((selected + 1))
                process_run "$session" "$input" "$kind" || failures=$((failures + 1))
            done
        fi

        if [ "${#dynamic[@]}" -le 1 ]; then
            if [ "${#dynamic[@]}" -eq 1 ]; then
                selected=$((selected + 1))
                process_run "$session" "${dynamic[0]}" "$kind" || failures=$((failures + 1))
            fi
            continue
        fi

        # Multiple dynamic runs of the same protocol: order by series number
        # and require a shared grid before combining.
        ordered=()
        while IFS=$'\t' read -r _ input; do
            ordered+=("$input")
        done < <(
            for input in "${dynamic[@]}"; do
                printf '%s\t%s\n' "$(series_number "$(strip_nii_extension "$input")")" "$input"
            done | sort -n -k1,1
        )

        grid_ok=true
        for input in "${ordered[@]:1}"; do
            grids_match "${ordered[0]}" "$input" || { grid_ok=false; break; }
        done

        if [ "$grid_ok" != true ]; then
            echo "Warning: ${session} ${key#*:}: runs do not share one grid; processing separately." >&2
            for input in "${ordered[@]}"; do
                selected=$((selected + 1))
                process_run "$session" "$input" "$kind" || failures=$((failures + 1))
            done
            continue
        fi

        series_numbers=()
        combined_nvol=0
        first_run_nvol=""
        for input in "${ordered[@]}"; do
            series_numbers+=("$(series_number "$(strip_nii_extension "$input")")")
            input_nvol=$(3dinfo -nt "$input")
            [[ "$input_nvol" =~ ^[0-9]+$ ]] || {
                echo "Error: Could not read time-point count: ${input}" >&2
                failures=$((failures + 1)); continue 2
            }
            [ -n "$first_run_nvol" ] || first_run_nvol=$input_nvol
            combined_nvol=$((combined_nvol + input_nvol))
        done
        combined_stem="${key#*:}_run$(IFS=-; echo "${series_numbers[*]}")"

        # Reference the middle volume of the first run rather than the
        # middle of the combined series, which would otherwise land right
        # on the seam between the first and second run.
        combined_base_index=$((first_run_nvol / 2))

        combined=$(concatenate_runs "$session" "$combined_stem" "${ordered[@]}") || {
            failures=$((failures + 1)); continue
        }
        selected=$((selected + 1))
        process_run "$session" "$combined" "$kind" "$combined_nvol" "$combined_base_index" ||
            failures=$((failures + 1))
    done
done

[ "$selected" -gt 0 ] || {
    echo "Error: No matching dzne_ep3d or ep2d_bold images were found." >&2; exit 1;
}
if [ "$failures" -gt 0 ]; then
    echo "Completed with ${failures} failed run(s)." >&2; exit 1
fi
echo "AFNI realignment, mean, and tSNR preprocessing complete."

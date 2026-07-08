#!/usr/bin/env python3

import sys
import os
import glob
import subprocess


def import_plotting_stack():
    global np
    global plt

    import_error = None
    missing_module = "numpy/matplotlib"

    try:
        import numpy as np
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return
    except ModuleNotFoundError as error:
        import_error = error
        missing_module = error.name
    except ImportError as error:
        import_error = error

    if os.environ.get("PLOT_IMAGE_CORRELATION_REEXECED") != "1":
        clean_env = os.environ.copy()
        clean_env.pop("PYTHONHOME", None)
        clean_env.pop("PYTHONPATH", None)
        clean_env["MPLBACKEND"] = "Agg"
        clean_env["PLOT_IMAGE_CORRELATION_REEXECED"] = "1"

        candidate_pythons = [
            sys.executable,
            "/home/users/sasbo/miniconda3/envs/THS_env/bin/python3",
            "/home/users/sasbo/miniconda3/bin/python3",
        ]
        import_check = "import numpy; import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot"

        seen = set()
        for python in candidate_pythons:
            if not python or python in seen or not os.path.exists(python):
                continue
            seen.add(python)

            check = subprocess.run(
                [python, "-c", import_check],
                env=clean_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if check.returncode == 0:
                script_path = os.path.abspath(__file__)
                os.execve(python, [python, script_path, *sys.argv[1:]], clean_env)

    print(f"Error: Python cannot import required plotting module {missing_module!r}.", file=sys.stderr)
    if import_error is not None:
        print(f"Original import error: {import_error}", file=sys.stderr)
    print("Try this in a fresh shell before plotting:", file=sys.stderr)
    print("  unset PYTHONPATH PYTHONHOME", file=sys.stderr)
    print("  conda activate THS_env", file=sys.stderr)
    print("  python3 -c 'import numpy; import matplotlib'", file=sys.stderr)
    print("", file=sys.stderr)
    print("If that still fails, repair the environment with:", file=sys.stderr)
    print("  conda install -n THS_env -c conda-forge numpy matplotlib", file=sys.stderr)
    sys.exit(1)


import_plotting_stack()


def session_site_and_number(num_sessions):
    if num_sessions == 6:
        session_numbers = [1, 2, 3, 5, 6, 7]
    else:
        session_numbers = list(range(1, num_sessions + 1))

    session_info = []
    for ses_num in session_numbers:
        if ses_num <= 3:
            site = "Stanford"
        elif ses_num == 4:
            site = "Berkeley"
        else:
            site = "Magdeburg"
        session_info.append((site, ses_num))

    return session_info


def session_labels(num_sessions):
    return [
        f"{site}\nSes {ses_num:02d}"
        for site, ses_num in session_site_and_number(num_sessions)
    ]


def group_dividers(num_sessions):
    session_info = session_site_and_number(num_sessions)
    return [
        idx + 0.5
        for idx in range(num_sessions - 1)
        if session_info[idx][0] != session_info[idx + 1][0]
    ]


def load_matrix(file_path):
    # Convert "NaN" strings back to np.nan so matplotlib can mask them cleanly.
    matrix = np.genfromtxt(file_path, missing_values="NaN", filling_values=np.nan)
    return np.atleast_2d(matrix)


def metric_from_filename(filename, folder_name):
    suffix = f"_{folder_name}.txt"

    if filename.startswith("correlation_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("correlation_matrix_", "").replace(suffix, "")
        return {
            "name": "CC",
            "title": "Cross-Session Correlation",
            "transform": transform_name,
            "fmt": ".3f",
            "cmap": "viridis",
            "vmin": None,
            "vmax": 1.0,
        }

    if filename.startswith("rmse_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("rmse_matrix_", "").replace(suffix, "")
        return {
            "name": "RMSE",
            "title": "Cross-Session RMSE",
            "transform": transform_name,
            "fmt": ".4f",
            "cmap": "magma",
            "vmin": 0.0,
            "vmax": None,
        }

    return None


def color_limits(matrix, metric):
    valid_vals = matrix[~np.isnan(matrix)]

    if valid_vals.size == 0:
        return metric["vmin"], metric["vmax"]

    if metric["name"] == "CC":
        # Ignore perfect self-correlations when choosing the lower color bound.
        off_diag_vals = valid_vals[valid_vals < 0.999]
        vmin = np.nanmin(off_diag_vals) if off_diag_vals.size > 0 else 0.95
        return vmin, metric["vmax"]

    return metric["vmin"], np.nanmax(valid_vals)


def safe_color_limits(vmin, vmax):
    if vmin is None or vmax is None or vmin != vmax:
        return vmin, vmax

    if vmin == 0:
        return 0.0, 1.0

    pad = abs(vmin) * 0.05
    return vmin - pad, vmax + pad


def text_color(value, vmin, vmax):
    if np.isnan(value) or vmin is None or vmax is None or vmin == vmax:
        return "black"

    scaled = (value - vmin) / (vmax - vmin)
    return "white" if scaled < 0.45 else "black"


def plot_matrix(file_path, folder_name):
    filename = os.path.basename(file_path)
    metric = metric_from_filename(filename, folder_name)

    if metric is None:
        print(f"  [Skipping] Unrecognized matrix filename: {filename}")
        return False

    try:
        matrix = load_matrix(file_path)
    except Exception as e:
        print(f"  [Skipping] Failed to load {filename}: {e}")
        return False

    num_sessions = matrix.shape[0]
    labels = session_labels(num_sessions)
    vmin, vmax = safe_color_limits(*color_limits(matrix, metric))

    cmap = plt.get_cmap(metric["cmap"]).copy()
    cmap.set_bad(color="lightgray")
    masked_matrix = np.ma.masked_invalid(matrix)

    fig, ax = plt.subplots(figsize=(9, 7))
    image = ax.imshow(masked_matrix, cmap=cmap, vmin=vmin, vmax=vmax)

    colorbar = fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)
    colorbar.set_label(metric["name"])

    ax.set_xticks(np.arange(num_sessions))
    ax.set_yticks(np.arange(num_sessions))
    ax.set_xticklabels(labels, rotation=45, ha="right")
    ax.set_yticklabels(labels)

    ax.set_xticks(np.arange(-0.5, num_sessions, 1), minor=True)
    ax.set_yticks(np.arange(-0.5, num_sessions, 1), minor=True)
    ax.grid(which="minor", color="black", linestyle="-", linewidth=0.5)
    ax.tick_params(which="minor", bottom=False, left=False)

    for divider in group_dividers(num_sessions):
        ax.axhline(divider, color="white", linewidth=3)
        ax.axvline(divider, color="white", linewidth=3)

    for row in range(matrix.shape[0]):
        for col in range(matrix.shape[1]):
            value = matrix[row, col]
            label = "NaN" if np.isnan(value) else format(value, metric["fmt"])
            ax.text(col, row, label, ha="center", va="center",
                    color=text_color(value, vmin, vmax), fontsize=8)

    title = metric["title"]
    transform = metric["transform"]
    ax.set_title(f"{title}: {transform}\n({folder_name})", pad=15)
    fig.tight_layout()

    output_filename = file_path.replace(".txt", ".png")
    fig.savefig(output_filename, dpi=300)
    plt.close(fig)

    print(f"  -> Saved {os.path.basename(output_filename)}")
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 plot_image_correlation.py <folder_name>")
        sys.exit(1)

    folder_name = sys.argv[1]

    base_deriv_dir = "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
    target_dir = os.path.join(base_deriv_dir, folder_name)

    if not os.path.isdir(target_dir):
        print(f"Error: Directory {target_dir!r} does not exist.")
        sys.exit(1)

    matrix_files = []
    for prefix in ("correlation_matrix_", "rmse_matrix_"):
        search_pattern = os.path.join(target_dir, f"{prefix}*.txt")
        matrix_files.extend(glob.glob(search_pattern))

    if not matrix_files:
        print(f"No correlation or RMSE text matrices found in {target_dir!r}.")
        sys.exit(1)

    print(f"Found {len(matrix_files)} matrix file(s) for {folder_name!r}. Generating plots...")

    num_plotted = 0
    for file_path in sorted(matrix_files):
        if plot_matrix(file_path, folder_name):
            num_plotted += 1

    print(f"Generated {num_plotted} plot(s).")


if __name__ == "__main__":
    main()

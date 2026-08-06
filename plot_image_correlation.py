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


def session_site_and_number(num_sessions, includes_berkeley):
    if includes_berkeley:
        if num_sessions != 7:
            raise ValueError(
                "Plots with Berkeley require a 7-session matrix "
                "(3 Stanford, 1 Berkeley, 3 Magdeburg)."
            )
        sites = ["Stanford"] * 3 + ["Berkeley"] + ["Magdeburg"] * 3
    else:
        if num_sessions != 6:
            raise ValueError(
                "Plots without Berkeley require a 6-session matrix "
                "(3 Stanford, 3 Magdeburg)."
            )
        sites = ["Stanford"] * 3 + ["Magdeburg"] * 3

    return list(zip(sites, range(1, num_sessions + 1)))


def session_labels(num_sessions, includes_berkeley):
    return [
        f"{site}\nSes {ses_num:02d}"
        for site, ses_num in session_site_and_number(
            num_sessions, includes_berkeley
        )
    ]


def group_dividers(num_sessions, includes_berkeley):
    session_info = session_site_and_number(num_sessions, includes_berkeley)
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
            "fmt": ".2f",
            "cmap": "viridis",
            "vmin": 0.75,
            "vmax": 1.0,
        }

    if filename.startswith("rmse_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("rmse_matrix_", "").replace(suffix, "")
        return {
            "name": "RMSE",
            "title": "Cross-Session RMSE",
            "transform": transform_name,
            "fmt": ".3f",
            "cmap": "magma",
            "vmin": 0.0,
            "vmax": None,
        }

    if filename.startswith("rmse_hz_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("rmse_hz_matrix_", "").replace(suffix, "")
        return {
            "name": "RMSE (Hz)",
            "title": "Cross-Session RMSE in Hz",
            "transform": transform_name,
            "fmt": ".1f",
            "cmap": "magma",
            "vmin": 0.0,
            "vmax": None,
        }

    if filename.startswith("mapd_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("mapd_matrix_", "").replace(suffix, "")
        return {
            "name": "MAPD (%)",
            "title": "Cross-Session Mean Absolute Percent Difference",
            "transform": transform_name,
            "fmt": ".1f",
            "cmap": "magma",
            "vmin": 0.0,
            "vmax": None,
        }

    if filename.startswith("wm_mapd_matrix_") and filename.endswith(suffix):
        transform_name = filename.replace("wm_mapd_matrix_", "").replace(suffix, "")
        return {
            "name": "WM MAPD (%)",
            "title": "Cross-Session White-Matter Mean Absolute Percent Difference",
            "transform": transform_name,
            "fmt": ".1f",
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
        return metric["vmin"], metric["vmax"]

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


def save_matrix_plot(
    matrix,
    metric,
    folder_name,
    output_filename,
    includes_berkeley,
    vmin,
    vmax,
):
    num_sessions = matrix.shape[0]
    labels = session_labels(num_sessions, includes_berkeley)

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

    for divider in group_dividers(num_sessions, includes_berkeley):
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
    berkeley_label = "with Berkeley" if includes_berkeley else "without Berkeley"
    ax.set_title(
        f"{title}: {transform}\n({folder_name}; {berkeley_label})",
        pad=15,
    )
    fig.tight_layout()

    fig.savefig(output_filename, dpi=300)
    plt.close(fig)

    print(f"  -> Saved {os.path.basename(output_filename)}")


def plot_matrix(file_path, folder_name):
    filename = os.path.basename(file_path)
    metric = metric_from_filename(filename, folder_name)

    if metric is None:
        print(f"  [Skipping] Unrecognized matrix filename: {filename}")
        return 0

    try:
        matrix = load_matrix(file_path)
    except Exception as e:
        print(f"  [Skipping] Failed to load {filename}: {e}")
        return 0

    if matrix.shape[0] != matrix.shape[1]:
        print(f"  [Skipping] Matrix is not square: {filename} ({matrix.shape})")
        return 0

    if matrix.shape[0] not in (6, 7):
        print(
            f"  [Skipping] Expected 6 or 7 sessions, found "
            f"{matrix.shape[0]}: {filename}"
        )
        return 0

    # Use identical color limits for both variants so their colors can be
    # compared directly.
    vmin, vmax = safe_color_limits(*color_limits(matrix, metric))
    output_stem, _ = os.path.splitext(file_path)

    if matrix.shape[0] == 7:
        save_matrix_plot(
            matrix, metric, folder_name,
            f"{output_stem}_with_Berkeley.png",
            includes_berkeley=True, vmin=vmin, vmax=vmax,
        )

        # Berkeley is session 04, at zero-based row/column index 3.
        without_berkeley = np.delete(np.delete(matrix, 3, axis=0), 3, axis=1)
        save_matrix_plot(
            without_berkeley, metric, folder_name,
            f"{output_stem}_without_Berkeley.png",
            includes_berkeley=False, vmin=vmin, vmax=vmax,
        )
        return 2

    print(
        f"  [Info] {filename} already has 6 sessions; "
        "only the without-Berkeley plot can be generated."
    )
    save_matrix_plot(
        matrix, metric, folder_name,
        f"{output_stem}_without_Berkeley.png",
        includes_berkeley=False, vmin=vmin, vmax=vmax,
    )
    return 1


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
    for prefix in (
        "correlation_matrix_",
        "rmse_matrix_",
        "rmse_hz_matrix_",
        "mapd_matrix_",
        "wm_mapd_matrix_",
    ):
        search_pattern = os.path.join(target_dir, f"{prefix}*.txt")
        matrix_files.extend(glob.glob(search_pattern))

    if not matrix_files:
        print(
            "No correlation, RMSE, or mean absolute percent-difference "
            f"text matrices found in {target_dir!r}."
        )
        sys.exit(1)

    print(f"Found {len(matrix_files)} matrix file(s) for {folder_name!r}. Generating plots...")

    num_plotted = 0
    for file_path in sorted(matrix_files):
        num_plotted += plot_matrix(file_path, folder_name)

    print(f"Generated {num_plotted} plot(s).")


if __name__ == "__main__":
    main()

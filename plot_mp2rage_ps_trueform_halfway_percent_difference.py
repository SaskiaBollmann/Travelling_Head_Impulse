#!/usr/bin/env python3

"""Plot percent difference relative to percentile-scaled TrueForm."""

import argparse
import os
from pathlib import Path
import subprocess
import sys


def import_plotting_stack():
    global nib, np, plt

    try:
        import nibabel as nib
        import numpy as np
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return
    except (ImportError, ModuleNotFoundError) as error:
        if os.environ.get("PLOT_MP2RAGE_PERCENT_REEXECED") == "1":
            raise SystemExit(f"Could not import plotting dependencies: {error}")

    clean_env = os.environ.copy()
    clean_env.pop("PYTHONHOME", None)
    clean_env.pop("PYTHONPATH", None)
    clean_env["MPLBACKEND"] = "Agg"
    clean_env["PLOT_MP2RAGE_PERCENT_REEXECED"] = "1"

    candidates = (
        sys.executable,
        "/home/users/sasbo/miniconda3/bin/python3",
        "/home/users/sasbo/miniconda3/envs/THS_env/bin/python3",
    )
    for python in dict.fromkeys(candidates):
        if not python or not Path(python).exists():
            continue
        check = subprocess.run(
            [python, "-c", "import nibabel, numpy, matplotlib"],
            env=clean_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if check.returncode == 0:
            os.execve(
                python,
                [python, str(Path(__file__).resolve()), *sys.argv[1:]],
                clean_env,
            )

    raise SystemExit(
        "Could not find a Python environment with nibabel, numpy, and matplotlib."
    )


import_plotting_stack()


DERIV_DIR = Path(
    "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/"
    "coregistration/mp2rage_0p7iso_patientSpecific_vs_TrueForm_UNI-DEN_ND_masked"
)
SESSIONS = {
    "ses02": "260601_THS_ses02",
    "ses03": "260602_THS_ses03",
}


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Percentile-scale both halfway-space images, then plot percent "
            "difference relative to TrueForm."
        )
    )
    parser.add_argument(
        "--session",
        choices=SESSIONS,
        default="ses03",
        help="Example session to plot (default: ses03).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output PNG (default: the comparison derivatives/figures directory).",
    )
    return parser.parse_args()


def load_canonical(path):
    image = nib.as_closest_canonical(nib.load(str(path)))
    return image, image.get_fdata(dtype=np.float32)


def robust_normalize(data, mask):
    values = data[mask & np.isfinite(data)]
    low, high = np.percentile(values, (1, 99))
    if high <= low:
        raise SystemExit("Cannot normalize image: robust intensity range is empty.")
    return np.clip((data - low) / (high - low), 0, 1)


def best_slices(mask):
    return (
        int(np.argmax(mask.sum(axis=(1, 2)))),
        int(np.argmax(mask.sum(axis=(0, 2)))),
        int(np.argmax(mask.sum(axis=(0, 1)))),
    )


def oriented_slice(volume, axis, index):
    return np.rot90(np.take(volume, index, axis=axis))


def main():
    args = parse_args()
    session = SESSIONS[args.session]
    prefix = DERIV_DIR / "halfway" / f"rigid_halfway_{session}"
    trueform_path = Path(f"{prefix}_TrueForm.nii.gz")
    patient_specific_path = Path(f"{prefix}_patientSpecific.nii.gz")
    mask_path = Path(f"{prefix}_brain_mask.nii.gz")

    for path in (trueform_path, patient_specific_path, mask_path):
        if not path.is_file():
            raise SystemExit(
                f"Required halfway-space file does not exist: {path}\n"
                f"Run: bash register_mp2rage_ps_trueform_halfway.sh {args.session}"
            )

    trueform_image, trueform = load_canonical(trueform_path)
    patient_specific_image, patient_specific = load_canonical(patient_specific_path)
    mask_image, mask_data = load_canonical(mask_path)

    if not (
        trueform.shape == patient_specific.shape == mask_data.shape
        and np.allclose(trueform_image.affine, patient_specific_image.affine)
        and np.allclose(trueform_image.affine, mask_image.affine)
    ):
        raise SystemExit("The halfway images and brain mask do not share one grid.")

    mask = (mask_data > 0) & np.isfinite(trueform) & np.isfinite(patient_specific)
    mask &= (trueform != 0) & (patient_specific != 0)
    if not np.any(mask):
        raise SystemExit("The common halfway-space brain mask is empty.")

    trueform_norm = robust_normalize(trueform, mask)
    patient_specific_norm = robust_normalize(patient_specific, mask)

    # A percentile-scaled TrueForm value near zero makes relative differences
    # unstable. Exclude the lowest 5% of the normalized intensity range.
    percent_mask = mask & (trueform_norm >= 0.05)
    percent_difference = np.full_like(trueform_norm, np.nan)
    percent_difference[percent_mask] = (
        100
        * (patient_specific_norm[percent_mask] - trueform_norm[percent_mask])
        / trueform_norm[percent_mask]
    )

    display_limit = float(
        np.percentile(np.abs(percent_difference[percent_mask]), 99)
    )
    display_limit = max(display_limit, np.finfo(float).eps)
    correlation = float(
        np.corrcoef(trueform_norm[mask], patient_specific_norm[mask])[0, 1]
    )
    mean_absolute_percent = float(
        np.mean(np.abs(percent_difference[percent_mask]))
    )

    row_labels = ("Sagittal", "Coronal", "Axial")
    slice_indices = best_slices(mask)
    column_titles = (
        "TrueForm\n(percentile scaled)",
        "Patient-specific\n(percentile scaled)",
        "Percent difference relative to TrueForm\n"
        "100 × (patient-specific − TrueForm) / TrueForm",
    )

    fig, axes = plt.subplots(3, 3, figsize=(11, 11), constrained_layout=True)
    difference_artist = None
    for axis, (row_label, index) in enumerate(zip(row_labels, slice_indices)):
        panels = (trueform_norm, patient_specific_norm, percent_difference)
        for column, panel in enumerate(panels):
            image = oriented_slice(panel, axis, index)
            if column < 2:
                axes[axis, column].imshow(image, cmap="gray", vmin=0, vmax=1)
            else:
                difference_artist = axes[axis, column].imshow(
                    image,
                    cmap="RdBu_r",
                    vmin=-display_limit,
                    vmax=display_limit,
                )
            axes[axis, column].set_axis_off()
            if axis == 0:
                axes[axis, column].set_title(column_titles[column], fontsize=11)

        axes[axis, 0].text(
            -0.04,
            0.5,
            f"{row_label}\n(slice {index})",
            transform=axes[axis, 0].transAxes,
            ha="right",
            va="center",
            rotation=90,
            fontsize=11,
        )

    colorbar = fig.colorbar(
        difference_artist,
        ax=axes[:, 2],
        location="right",
        shrink=0.75,
        pad=0.02,
    )
    colorbar.set_label("Percent difference relative to TrueForm (%)")
    fig.suptitle(
        f"TrueForm vs patient-specific MP2RAGE — {args.session}\n"
        "inverse-consistent rigid halfway space; "
        f"voxelwise r = {correlation:.3f}; "
        f"mean |percent difference| = {mean_absolute_percent:.1f}%",
        fontsize=15,
    )

    output = args.output
    if output is None:
        output = (
            DERIV_DIR
            / "figures"
            / f"mp2rage_ps_trueform_percent_difference_{args.session}_rigid_halfway.png"
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=300, bbox_inches="tight")
    plt.close(fig)

    print(f"Voxelwise correlation: {correlation:.4f}")
    print(f"Mean absolute percent difference: {mean_absolute_percent:.2f}%")
    print(f"Percent-difference display limit: +/-{display_limit:.2f}%")
    print(f"Saved: {output.resolve()}")


if __name__ == "__main__":
    main()

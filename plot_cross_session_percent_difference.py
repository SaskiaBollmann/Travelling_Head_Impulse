#!/usr/bin/env python3

"""Plot whole-brain and strict-WM cross-session percent differences."""

import argparse
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np


BASE_DIR = Path("/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig")
COREG_DIR = Path(
    "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/"
    "coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked"
)
WM_ROOT = Path(
    "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/"
    "segmentation/fast"
)
SESSIONS = (
    "260529_THS_ses01",
    "260601_THS_ses02",
    "260602_THS_ses03",
    "260602_THS_ses04",
    "260611_THS_ses05",
    "260618_THS_ses06",
    "260618_THS_ses07",
)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--moving-session", choices=SESSIONS, default=SESSIONS[5])
    parser.add_argument("--fixed-session", choices=SESSIONS, default=SESSIONS[2])
    parser.add_argument("--transform", choices=("Rigid", "Affine", "SyN"), default="SyN")
    parser.add_argument("--output-dir", type=Path, default=COREG_DIR / "figures")
    return parser.parse_args()


def patient_specific_regex(session):
    if session.endswith("_ses01"):
        return re.compile(r"mp2rage_0p7iso_UNI[-_]DEN_ND_[0-9]+\.nii(?:\.gz)?$")
    if session.endswith("_ses04"):
        return re.compile(
            r"(?:mp2rage_0p7iso|t1_mp2rage_sag_p3_0p7mm)_"
            r"(?:patientSpecific|PS)_UNI[-_]DEN_[0-9]+\.nii(?:\.gz)?$"
        )
    return re.compile(
        r"mp2rage_0p7iso_(?:patientSpecific|PS)_UNI[-_]DEN_ND_"
        r"[0-9]+\.nii(?:\.gz)?$"
    )


def fixed_image_path(session):
    regex = patient_specific_regex(session)
    matches = sorted(
        path for path in (BASE_DIR / session).iterdir() if regex.fullmatch(path.name)
    )
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one patient-specific fixed image for {session}; "
            f"found {len(matches)}."
        )
    return matches[0]


def load_canonical(path):
    image = nib.as_closest_canonical(nib.load(str(path)))
    return image, image.get_fdata(dtype=np.float32)


def robust_normalize(data, mask):
    values = data[mask & np.isfinite(data)]
    low, high = np.percentile(values, (1, 99))
    if high <= low:
        raise SystemExit("Cannot normalize an image with an empty robust range.")
    return np.clip((data - low) / (high - low), 0, 1)


SAGITTAL_OFFSET_FROM_MIDLINE = 20
MAX_DISPLAY_LIMIT = 20.0


def best_slices(mask):
    midline = int(np.argmax(mask.sum(axis=(1, 2))))
    return (
        min(midline + SAGITTAL_OFFSET_FROM_MIDLINE, mask.shape[0] - 1),
        int(np.argmax(mask.sum(axis=(0, 2)))),
        int(np.argmax(mask.sum(axis=(0, 1)))),
    )


def oriented_slice(volume, axis, index):
    return np.rot90(np.take(volume, index, axis=axis))


def plot_comparison(
    fixed_norm,
    moving_norm,
    difference,
    brain_mask,
    wm_mask,
    slice_indices,
    display_limit,
    title,
    output,
):
    gray = plt.get_cmap("gray").copy()
    gray.set_bad("black")
    diverging = plt.get_cmap("RdBu_r").copy()
    diverging.set_bad("black")
    row_labels = ("Sagittal", "Coronal", "Axial")
    panels = (
        np.where(brain_mask, fixed_norm, np.nan),
        np.where(brain_mask, moving_norm, np.nan),
        difference,
    )
    column_titles = (
        "Fixed session\n(percentile scaled)",
        "Moving session, registered to fixed\n(percentile scaled)",
        "Percent difference relative to fixed\n100 × (moving − fixed) / fixed",
    )

    fig, axes = plt.subplots(3, 3, figsize=(11, 11), constrained_layout=True)
    difference_artist = None
    for axis, (row_label, index) in enumerate(zip(row_labels, slice_indices)):
        for column, panel in enumerate(panels):
            image = oriented_slice(panel, axis, index)
            if column < 2:
                axes[axis, column].imshow(image, cmap=gray, vmin=0, vmax=1)
                if wm_mask is not None:
                    contour = oriented_slice(wm_mask, axis, index)
                    axes[axis, column].contour(
                        contour.astype(float),
                        levels=[0.5],
                        colors=["#00ffff"],
                        linewidths=0.45,
                    )
            else:
                difference_artist = axes[axis, column].imshow(
                    image,
                    cmap=diverging,
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
    colorbar.set_label("Percent difference relative to fixed session (%)")
    fig.suptitle(title, fontsize=14)
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {output}")


def main():
    args = parse_args()
    moving = args.moving_session
    fixed = args.fixed_session
    prefix = COREG_DIR / f"reg_{args.transform}_mov_{moving}_to_fix_{fixed}_"
    fixed_path = fixed_image_path(fixed)
    warped_path = Path(f"{prefix}CORR_Warped.nii.gz")
    difference_path = Path(f"{prefix}PERCENT_DIFF.nii.gz")
    brain_mask_path = COREG_DIR / f"mask_{fixed}.nii.gz"
    wm_mask_path = WM_ROOT / fixed / "wm_mask_fast_pve95.nii.gz"
    for path in (fixed_path, warped_path, difference_path, brain_mask_path, wm_mask_path):
        if not path.is_file():
            raise SystemExit(f"Required input does not exist: {path}")

    fixed_image, fixed_data = load_canonical(fixed_path)
    warped_image, moving_data = load_canonical(warped_path)
    difference_image, difference_data = load_canonical(difference_path)
    brain_image, brain_data = load_canonical(brain_mask_path)
    wm_image, wm_data = load_canonical(wm_mask_path)
    images = (warped_image, difference_image, brain_image, wm_image)
    if any(
        fixed_data.shape != image.shape
        or not np.allclose(fixed_image.affine, image.affine)
        for image in images
    ):
        raise SystemExit("The fixed, registered, difference, and mask images do not share one grid.")

    brain_mask = (brain_data > 0) & np.isfinite(fixed_data) & np.isfinite(moving_data)
    brain_mask &= (fixed_data != 0) & (moving_data != 0)
    wm_mask = brain_mask & (wm_data > 0)
    valid_whole = brain_mask & np.isfinite(difference_data)
    valid_wm = wm_mask & np.isfinite(difference_data)
    if not np.any(valid_whole) or not np.any(valid_wm):
        raise SystemExit("The whole-brain or white-matter comparison mask is empty.")

    fixed_norm = robust_normalize(fixed_data, brain_mask)
    moving_norm = robust_normalize(moving_data, brain_mask)
    whole_difference = np.where(valid_whole, difference_data, np.nan)
    wm_difference = np.where(valid_wm, difference_data, np.nan)
    display_limit = max(
        float(np.percentile(np.abs(difference_data[valid_whole]), 99)),
        np.finfo(float).eps,
    )
    display_limit = min(display_limit, MAX_DISPLAY_LIMIT)
    whole_mapd = float(np.mean(np.abs(difference_data[valid_whole])))
    wm_mapd = float(np.mean(np.abs(difference_data[valid_wm])))
    correlation = float(
        np.corrcoef(fixed_norm[brain_mask], moving_norm[brain_mask])[0, 1]
    )
    slices = best_slices(brain_mask)
    stem = f"{args.transform}_mov-{moving}_to_fix-{fixed}"

    plot_comparison(
        fixed_norm,
        moving_norm,
        whole_difference,
        brain_mask,
        None,
        slices,
        display_limit,
        f"Cross-session patient-specific MP2RAGE — {args.transform}\n"
        f"{moving} → {fixed}; voxelwise r = {correlation:.3f}; "
        f"whole-brain MAPD = {whole_mapd:.1f}%",
        args.output_dir / f"cross_session_percent_difference_{stem}_whole_brain.png",
    )
    plot_comparison(
        fixed_norm,
        moving_norm,
        wm_difference,
        brain_mask,
        wm_mask,
        slices,
        display_limit,
        f"Cross-session patient-specific MP2RAGE — {args.transform}\n"
        f"{moving} → {fixed}; FAST P(WM) ≥ 0.95; WM MAPD = {wm_mapd:.1f}%\n"
        "cyan contour marks the fixed-session WM mask",
        args.output_dir / f"cross_session_percent_difference_{stem}_wm_pve95.png",
    )
    print(f"Whole-brain MAPD: {whole_mapd:.4f}%")
    print(f"White-matter MAPD: {wm_mapd:.4f}%")
    print(f"Shared display limit: +/-{display_limit:.2f}%")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

"""Consistent representative cross-session plots for MP2RAGE, B1, B0, and tSNR."""

import argparse
import csv
import os
from pathlib import Path
import re
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
        if os.environ.get("PLOT_CROSS_SESSION_REEXECED") == "1":
            raise SystemExit(f"Could not import plotting dependencies: {error}")

    clean_env = os.environ.copy()
    clean_env.pop("PYTHONHOME", None)
    clean_env.pop("PYTHONPATH", None)
    clean_env["MPLBACKEND"] = "Agg"
    clean_env["PLOT_CROSS_SESSION_REEXECED"] = "1"
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


DATA_ROOT = Path("/oak/stanford/groups/polimeni/saskia/data/THS_2026")
ORIG_ROOT = DATA_ROOT / "orig"
COREG_ROOT = DATA_ROOT / "derivatives" / "coregistration"
WM_ROOT = DATA_ROOT / "derivatives" / "segmentation" / "fast"
B0_ROOT = DATA_ROOT / "derivatives" / "preprocessing" / "b0_romeo"

MP2RAGE_DIR = COREG_ROOT / "mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked"
B1_ID = "reg-dzne_b1map_5iso_sag__corr-dzne_b1map_5iso_sag_B1Comb_masked"
B1_DIR = COREG_ROOT / B1_ID
B0_ID = (
    "reg-gre_b0map_4iso_sag_ND_e1__corr-"
    "gre_b0map_4iso_sag_ND_romeo_hz_masked"
)
B0_DIR = COREG_ROOT / B0_ID
TSNR_ID = "reg-ep2d_bold_mean__corr-ep2d_bold_tsnr_masked"
TSNR_DIR = COREG_ROOT / TSNR_ID

SESSIONS = (
    "260529_THS_ses01",
    "260601_THS_ses02",
    "260602_THS_ses03",
    "260602_THS_ses04",
    "260611_THS_ses05",
    "260618_THS_ses06",
    "260618_THS_ses07",
)
SAGITTAL_OFFSET_MM = 14.0
DEFAULT_DIFFERENCE_LIMITS = {"mp2rage": 20.0, "b1": 50.0, "b0": 100.0, "tsnr": 50.0}
DEFAULT_B0_IMAGE_LIMIT_HZ = 600.0


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Plot fixed, registered-moving, and difference images in one "
            "consistent layout for MP2RAGE, B1, B0, or tSNR."
        )
    )
    parser.add_argument(
        "--modality",
        choices=("mp2rage", "b1", "b0", "tsnr"),
        default="mp2rage",
    )
    parser.add_argument("--moving-session", choices=SESSIONS, default=SESSIONS[1])
    parser.add_argument("--fixed-session", choices=SESSIONS, default=SESSIONS[2])
    parser.add_argument(
        "--transform", choices=("Rigid", "Affine", "SyN"), default="Rigid"
    )
    parser.add_argument(
        "--region",
        choices=("whole-brain", "wm", "both"),
        default="whole-brain",
        help="MP2RAGE only; B0, B1, and tSNR use whole-brain.",
    )
    parser.add_argument(
        "--difference-limit",
        type=float,
        help="Symmetric difference-map display limit in the modality's units.",
    )
    parser.add_argument(
        "--image-limit",
        type=float,
        help="Symmetric B0 display limit in Hz (default: 600).",
    )
    parser.add_argument("--output-dir", type=Path)
    return parser.parse_args()


def load_canonical(path):
    image = nib.as_closest_canonical(nib.load(str(path)))
    return image, image.get_fdata(dtype=np.float32)


def require_files(paths):
    for path in paths:
        if not path.is_file():
            raise SystemExit(f"Required input does not exist: {path}")


def check_grids(reference_image, reference_data, other_images):
    for image in other_images:
        if reference_data.shape != image.shape or not np.allclose(
            reference_image.affine, image.affine
        ):
            raise SystemExit("The fixed, registered, difference, and mask grids differ.")


def robust_normalize(data, mask):
    values = data[mask & np.isfinite(data)]
    low, high = np.percentile(values, (1, 99))
    if high <= low:
        raise SystemExit("Cannot normalize an image with an empty robust range.")
    return np.clip((data - low) / (high - low), 0, 1)


def best_slices(mask, voxel_sizes):
    midline = int(np.argmax(mask.sum(axis=(1, 2))))
    sagittal_offset = max(1, int(round(SAGITTAL_OFFSET_MM / voxel_sizes[0])))
    sagittal_target = min(midline + sagittal_offset, mask.shape[0] - 1)
    valid_sagittal = np.flatnonzero(mask.sum(axis=(1, 2)) > 0)
    sagittal = int(
        valid_sagittal[np.argmin(np.abs(valid_sagittal - sagittal_target))]
    )
    return (
        sagittal,
        int(np.argmax(mask.sum(axis=(0, 2)))),
        int(np.argmax(mask.sum(axis=(0, 1)))),
    )


def oriented_slice(volume, axis, index):
    return np.rot90(np.take(volume, index, axis=axis))


def patient_specific_path(session):
    if session.endswith("_ses01"):
        regex = re.compile(r"mp2rage_0p7iso_UNI[-_]DEN_ND_[0-9]+\.nii(?:\.gz)?$")
    elif session.endswith("_ses04"):
        regex = re.compile(
            r"(?:mp2rage_0p7iso|t1_mp2rage_sag_p3_0p7mm)_"
            r"(?:patientSpecific|PS)_UNI[-_]DEN_[0-9]+\.nii(?:\.gz)?$"
        )
    else:
        regex = re.compile(
            r"mp2rage_0p7iso_(?:patientSpecific|PS)_UNI[-_]DEN_ND_"
            r"[0-9]+\.nii(?:\.gz)?$"
        )
    matches = sorted(
        path for path in (ORIG_ROOT / session).iterdir() if regex.fullmatch(path.name)
    )
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one patient-specific MP2RAGE image for {session}; "
            f"found {len(matches)}."
        )
    return matches[0]


def correlation_provenance_source(directory, dataset_id, transform, session, label):
    provenance = directory / f"correlation_matrix_{transform}_{dataset_id}_provenance.tsv"
    with provenance.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    matches = [row["correlation_file"] for row in rows if row["session"] == session]
    if len(matches) != 1 or not matches[0]:
        raise SystemExit(
            f"Expected one {label} correlation source for {session}; found {len(matches)}."
        )
    return Path(matches[0])


def b1_source(transform, session):
    return correlation_provenance_source(B1_DIR, B1_ID, transform, session, "B1")


def tsnr_source(transform, session):
    return correlation_provenance_source(TSNR_DIR, TSNR_ID, transform, session, "tSNR")


def b0_source(session):
    session_dir = B0_ROOT / session
    if session.endswith("ses04"):
        pattern = "gre_b0map_4iso_sag_[0-9]*_e2_ph_romeo/fieldmap_hz.nii.gz"
    else:
        pattern = "gre_b0map_4iso_sag_ND_*_e2_ph_romeo/fieldmap_hz.nii.gz"
    matches = sorted(session_dir.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(f"Expected one B0 Hz map for {session}; found {len(matches)}.")
    return matches[0]


def load_comparison(args):
    moving_session = args.moving_session
    fixed_session = args.fixed_session
    transform = args.transform

    if args.modality in ("b0", "b1") and transform == "SyN":
        raise SystemExit(f"{args.modality.upper()} currently has rigid and affine results only.")
    if args.modality != "mp2rage" and args.region != "whole-brain":
        raise SystemExit("--region wm/both is currently available only for MP2RAGE.")

    if args.modality == "mp2rage":
        result_dir = MP2RAGE_DIR
        prefix = result_dir / f"reg_{transform}_mov_{moving_session}_to_fix_{fixed_session}_"
        fixed_path = patient_specific_path(fixed_session)
        moving_path = Path(f"{prefix}CORR_Warped.nii.gz")
        difference_path = Path(f"{prefix}PERCENT_DIFF.nii.gz")
        mask_path = result_dir / f"mask_{fixed_session}.nii.gz"
        wm_path = WM_ROOT / fixed_session / "wm_mask_fast_pve95.nii.gz"
        require_files((fixed_path, moving_path, difference_path, mask_path, wm_path))
    elif args.modality in ("b1", "tsnr"):
        result_dir = B1_DIR if args.modality == "b1" else TSNR_DIR
        source_fn = b1_source if args.modality == "b1" else tsnr_source
        prefix = result_dir / f"reg_{transform}_mov_{moving_session}_to_fix_{fixed_session}_"
        fixed_path = source_fn(transform, fixed_session)
        moving_path = Path(f"{prefix}CORR_Warped.nii.gz")
        difference_path = Path(f"{prefix}PERCENT_DIFF.nii.gz")
        mask_path = result_dir / f"mask_{fixed_session}.nii.gz"
        wm_path = None
        require_files((fixed_path, moving_path, difference_path, mask_path))
    else:
        result_dir = B0_DIR
        prefix = result_dir / f"reg_{transform}_mov_{moving_session}_to_fix_{fixed_session}"
        fixed_path = b0_source(fixed_session)
        moving_path = Path(f"{prefix}_HZ_Warped.nii.gz")
        difference_path = Path(f"{prefix}_DIFF_HZ.nii.gz")
        mask_path = result_dir / f"mask_{fixed_session}.nii.gz"
        wm_path = None
        require_files((fixed_path, moving_path, difference_path, mask_path))

    fixed_image, fixed = load_canonical(fixed_path)
    moving_image, moving = load_canonical(moving_path)
    difference_image, difference = load_canonical(difference_path)
    mask_image, mask_data = load_canonical(mask_path)
    images = [moving_image, difference_image, mask_image]

    wm_data = None
    if wm_path is not None:
        wm_image, wm_data = load_canonical(wm_path)
        images.append(wm_image)
    check_grids(fixed_image, fixed, images)

    brain_mask = (mask_data > 0) & np.isfinite(fixed) & np.isfinite(moving)
    if args.modality != "b0":
        brain_mask &= (fixed != 0) & (moving != 0)
    valid = brain_mask & np.isfinite(difference)
    if np.count_nonzero(valid) < 100:
        raise SystemExit("The common comparison mask is empty.")

    output_dir = args.output_dir or result_dir / "figures"
    return {
        "result_dir": result_dir,
        "output_dir": output_dir,
        "fixed": fixed,
        "moving": moving,
        "difference": difference,
        "brain_mask": brain_mask,
        "valid": valid,
        "wm_data": wm_data,
        "voxel_sizes": nib.affines.voxel_sizes(fixed_image.affine),
    }


def prepare_panel(args, loaded, region):
    fixed = loaded["fixed"]
    moving = loaded["moving"]
    difference = loaded["difference"]
    brain_mask = loaded["brain_mask"]
    valid = loaded["valid"]
    contour = None

    if args.modality == "mp2rage":
        fixed_panel = robust_normalize(fixed, brain_mask)
        moving_panel = robust_normalize(moving, brain_mask)
        image_min, image_max = 0.0, 1.0
        comparison_mask = valid
        region_label = "whole-brain"
        if region == "wm":
            contour = brain_mask & (loaded["wm_data"] > 0)
            comparison_mask = valid & contour
            region_label = "WM P(WM) ≥ 0.95"
        correlation = float(
            np.corrcoef(fixed_panel[brain_mask], moving_panel[brain_mask])[0, 1]
        )
        metric_value = float(np.mean(np.abs(difference[comparison_mask])))
        metric_text = f"MAPD = {metric_value:.1f}%"
        modality_title = "Patient-specific MP2RAGE"
        column_titles = (
            "Fixed MP2RAGE\n(percentile scaled)",
            "Moving MP2RAGE, registered to fixed\n(percentile scaled)",
            "Percent difference\nrelative to fixed (%)",
        )
        colorbar_label = "Percent difference relative to fixed (%)"
        filename_metric = "percent_difference"
    elif args.modality in ("b1", "tsnr"):
        if args.modality == "b1":
            fixed_panel = fixed / 10.0
            moving_panel = moving / 10.0
            modality_title = "B1+ transmit field"
            column_titles = (
                "Fixed B1+ map\n(% nominal; common display scale)",
                "Moving B1+ map, registered to fixed\n(% nominal; common display scale)",
                "Percent difference\nrelative to fixed (%)",
            )
        else:
            fixed_panel = fixed
            moving_panel = moving
            modality_title = "EPI tSNR"
            column_titles = (
                "Fixed tSNR map\n(common display scale)",
                "Moving tSNR map, registered to fixed\n(common display scale)",
                "Percent difference\nrelative to fixed (%)",
            )
        display_values = np.concatenate(
            (fixed_panel[brain_mask], moving_panel[brain_mask])
        )
        image_min, image_max = np.percentile(display_values, (1, 99))
        comparison_mask = valid
        correlation = float(np.corrcoef(fixed[brain_mask], moving[brain_mask])[0, 1])
        metric_value = float(np.mean(np.abs(difference[comparison_mask])))
        metric_text = f"MAPD = {metric_value:.1f}%"
        region_label = "whole-brain"
        colorbar_label = "Percent difference relative to fixed (%)"
        filename_metric = "percent_difference"
    else:
        image_limit = args.image_limit or DEFAULT_B0_IMAGE_LIMIT_HZ
        if image_limit <= 0:
            raise SystemExit("--image-limit must be positive.")
        fixed_panel = fixed
        moving_panel = moving
        image_min, image_max = -image_limit, image_limit
        comparison_mask = valid
        correlation = float(np.corrcoef(fixed[brain_mask], moving[brain_mask])[0, 1])
        metric_value = float(np.sqrt(np.mean(difference[comparison_mask] ** 2)))
        metric_text = f"RMSE = {metric_value:.1f} Hz"
        region_label = "whole-brain"
        modality_title = "B0 frequency field"
        column_titles = (
            "Fixed B0 map\n(Hz; common display scale)",
            "Moving B0 map, registered to fixed\n(Hz; common display scale)",
            "Frequency difference\nmoving − fixed (Hz)",
        )
        colorbar_label = "Frequency difference: moving − fixed (Hz)"
        filename_metric = "difference_hz"

    difference_limit = (
        args.difference_limit
        if args.difference_limit is not None
        else DEFAULT_DIFFERENCE_LIMITS[args.modality]
    )
    if difference_limit <= 0:
        raise SystemExit("--difference-limit must be positive.")

    return {
        "fixed_panel": np.where(brain_mask, fixed_panel, np.nan),
        "moving_panel": np.where(brain_mask, moving_panel, np.nan),
        "difference_panel": np.where(comparison_mask, difference, np.nan),
        "mask": brain_mask,
        "contour": contour,
        "image_min": float(image_min),
        "image_max": float(image_max),
        "difference_limit": float(difference_limit),
        "correlation": correlation,
        "metric_text": metric_text,
        "region_label": region_label,
        "modality_title": modality_title,
        "column_titles": column_titles,
        "colorbar_label": colorbar_label,
        "filename_metric": filename_metric,
    }


def render(args, loaded, panel, region):
    slices = best_slices(panel["mask"], loaded["voxel_sizes"])
    gray = plt.get_cmap("gray").copy()
    gray.set_bad("black")
    diverging = plt.get_cmap("RdBu_r").copy()
    diverging.set_bad("black")
    panels = (
        panel["fixed_panel"],
        panel["moving_panel"],
        panel["difference_panel"],
    )
    row_labels = ("Sagittal", "Coronal", "Axial")

    fig, axes = plt.subplots(3, 3, figsize=(11, 11), constrained_layout=True)
    difference_artist = None
    for axis, (row_label, index) in enumerate(zip(row_labels, slices)):
        for column, data in enumerate(panels):
            image = oriented_slice(data, axis, index)
            if column < 2:
                axes[axis, column].imshow(
                    image,
                    cmap=gray,
                    vmin=panel["image_min"],
                    vmax=panel["image_max"],
                )
                if panel["contour"] is not None:
                    contour = oriented_slice(panel["contour"], axis, index)
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
                    vmin=-panel["difference_limit"],
                    vmax=panel["difference_limit"],
                )
            axes[axis, column].set_axis_off()
            if axis == 0:
                axes[axis, column].set_title(
                    panel["column_titles"][column], fontsize=11
                )
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
        difference_artist, ax=axes[:, 2], location="right", shrink=0.75, pad=0.02
    )
    colorbar.set_label(panel["colorbar_label"])
    fig.suptitle(
        f"Cross-session {panel['modality_title']} — {args.transform}\n"
        f"{args.moving_session} → {args.fixed_session}; "
        f"voxelwise r = {panel['correlation']:.3f}; {panel['metric_text']}\n"
        f"{panel['region_label']}; difference display clipped to "
        f"±{panel['difference_limit']:g}",
        fontsize=14,
    )

    stem = (
        f"{args.transform}_mov-{args.moving_session}_to_fix-{args.fixed_session}"
    )
    region_suffix = "wm_pve95" if region == "wm" else "whole_brain"
    output = loaded["output_dir"] / (
        f"cross_session_{args.modality}_{panel['filename_metric']}_"
        f"{stem}_{region_suffix}.png"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {output.resolve()}")
    print(f"Voxelwise correlation: {panel['correlation']:.6f}")
    print(panel["metric_text"])


def main():
    args = parse_args()
    loaded = load_comparison(args)
    if args.modality == "mp2rage" and args.region == "both":
        regions = ("whole-brain", "wm")
    else:
        regions = (args.region,)
    for region in regions:
        panel = prepare_panel(args, loaded, region)
        render(args, loaded, panel, region)


if __name__ == "__main__":
    main()

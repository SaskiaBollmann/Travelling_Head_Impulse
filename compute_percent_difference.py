#!/usr/bin/env python3

"""Compute a percent-difference image for one registered pair."""

import argparse
import csv
from datetime import datetime, timezone
from pathlib import Path

import nibabel as nib
import numpy as np


TSNR_DATASET_ID = "reg-ep2d_bold_mean__corr-ep2d_bold_tsnr_masked"
TSNR_DIRECTORY = Path(
    "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/"
    f"coregistration/{TSNR_DATASET_ID}"
)
TSNR_SESSIONS = (
    "260529_THS_ses01",
    "260601_THS_ses02",
    "260602_THS_ses03",
    "260602_THS_ses04",
    "260611_THS_ses05",
    "260618_THS_ses06",
    "260618_THS_ses07",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Percentile-scale the fixed and warped-moving images, then compute "
            "100 * (moving - fixed) / fixed."
        )
    )
    parser.add_argument("--fixed", type=Path)
    parser.add_argument("--moving", type=Path)
    parser.add_argument("--mask", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--metric-output", type=Path)
    parser.add_argument(
        "--tsnr-batch",
        choices=("rigid-halfway", "syn-physical"),
        help="Rebuild a full tSNR matrix from existing registered outputs.",
    )
    parser.add_argument("--derivatives-dir", type=Path, default=TSNR_DIRECTORY)
    parser.add_argument(
        "--physical-values",
        action="store_true",
        help="Use input values directly instead of percentile normalization.",
    )
    parser.add_argument(
        "--mean-scale-mask",
        type=Path,
        help=(
            "Scale fixed and moving independently so that each has mean 1 "
            "inside this mask, then compute percent difference. This is "
            "mutually exclusive with --physical-values."
        ),
    )
    return parser.parse_args()


def load_image(path):
    image = nib.load(str(path))
    return image, image.get_fdata(dtype=np.float32)


def robust_normalize(data, mask):
    values = data[mask & np.isfinite(data)]
    low, high = np.percentile(values, (1, 99))
    if high <= low:
        raise SystemExit(f"Cannot normalize image with empty robust range: {low}..{high}")
    return np.clip((data - low) / (high - low), 0, 1)


def scale_to_mask_mean(data, scale_mask, label):
    mean = float(np.mean(data[scale_mask]))
    if not np.isfinite(mean) or np.isclose(mean, 0.0):
        raise SystemExit(f"Cannot mean-scale {label}; mask mean is {mean}.")
    return data / mean, mean


def atomic_savetxt(path, matrix):
    temporary = path.with_name(f".{path.name}.tmp")
    np.savetxt(temporary, matrix, fmt="%.4f")
    temporary.replace(path)


def tsnr_sources(directory):
    path = directory / f"source_images_Rigid_{TSNR_DATASET_ID}.tsv"
    with path.open(newline="", encoding="utf-8") as stream:
        return {
            row["session"]: Path(row["correlation_file"])
            for row in csv.DictReader(stream, delimiter="\t")
        }


def syn_pair_fixed_source(directory, moving_index, fixed_index):
    provenance = directory / f"provenance_SyN_{moving_index}_{fixed_index}.tsv"
    if not provenance.is_file():
        raise SystemExit(f"Required SyN provenance does not exist: {provenance}")
    with provenance.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    if len(rows) != 1 or rows[0].get("status") != "ready":
        raise SystemExit(f"SyN provenance is not ready for one pair: {provenance}")
    return Path(rows[0]["fixed_correlation_file"])


def tsnr_metrics(fixed_path, moving_path, mask_path):
    fixed_image, fixed = load_image(fixed_path)
    moving_image, moving = load_image(moving_path)
    mask_image, mask_data = load_image(mask_path)
    if not (
        fixed.shape == moving.shape == mask_data.shape
        and np.allclose(fixed_image.affine, moving_image.affine)
        and np.allclose(fixed_image.affine, mask_image.affine)
    ):
        raise SystemExit(f"Grid mismatch for {moving_path}")
    valid = (mask_data > 0) & np.isfinite(fixed) & np.isfinite(moving)
    valid &= (fixed != 0) & (moving != 0)
    if np.count_nonzero(valid) < 100:
        raise SystemExit(f"Empty comparison mask for {moving_path}")
    fixed_values = fixed[valid].astype(np.float64)
    moving_values = moving[valid].astype(np.float64)
    difference = np.full(fixed.shape, np.nan, dtype=np.float32)
    difference[valid] = 100 * (moving[valid] - fixed[valid]) / np.abs(fixed[valid])
    return (
        fixed_image,
        difference,
        float(np.corrcoef(fixed_values, moving_values)[0, 1]),
        float(np.sqrt(np.mean((moving_values - fixed_values) ** 2))),
        float(np.mean(np.abs(difference[valid]))),
        int(np.count_nonzero(valid)),
    )


def compute_tsnr_batch(kind, directory):
    size = len(TSNR_SESSIONS)
    correlation = np.eye(size)
    rmse = np.zeros((size, size))
    mapd = np.zeros((size, size))
    rows = []
    sources = tsnr_sources(directory) if kind == "rigid-halfway" else None
    for i, moving_session in enumerate(TSNR_SESSIONS):
        for j, fixed_session in enumerate(TSNR_SESSIONS):
            if kind == "rigid-halfway" and i == j:
                rows.append((moving_session, fixed_session, "identity", "", "", "", ""))
                continue
            if kind == "rigid-halfway":
                prefix = directory / "halfway" / (
                    f"rigid_halfway_from_existing_mov_{moving_session}_to_fix_{fixed_session}"
                )
                fixed_path = Path(f"{prefix}_tsnr_fixed.nii.gz")
                moving_path = Path(f"{prefix}_tsnr_moving.nii.gz")
                mask_path = Path(f"{prefix}_brain_mask.nii.gz")
                transform = Path(f"{prefix}_source_0GenericAffine.mat")
                output_path = None
            else:
                prefix = directory / f"reg_SyN_mov_{moving_session}_to_fix_{fixed_session}_"
                fixed_path = syn_pair_fixed_source(directory, i, j)
                moving_path = Path(f"{prefix}CORR_Warped.nii.gz")
                mask_path = directory / f"mask_{fixed_session}.nii.gz"
                transform = Path(f"{prefix}1Warp.nii.gz")
                output_path = Path(f"{prefix}PERCENT_DIFF.nii.gz")
            for path in (fixed_path, moving_path, mask_path, transform):
                if not path.is_file():
                    raise SystemExit(f"Required input does not exist: {path}")
            image, difference, corr, error, percent, count = tsnr_metrics(
                fixed_path, moving_path, mask_path
            )
            correlation[i, j], rmse[i, j], mapd[i, j] = corr, error, percent
            if output_path:
                header = image.header.copy()
                header.set_data_dtype(np.float32)
                temporary = output_path.with_name(f".{output_path.name}.tmp.nii.gz")
                nib.save(nib.Nifti1Image(difference, image.affine, header), temporary)
                temporary.replace(output_path)
                (directory / f"tmp_mapd_SyN_{i}_{j}.txt").write_text(
                    f"{percent:.4f}\n", encoding="utf-8"
                )
            rows.append((moving_session, fixed_session, "computed_directional",
                         count, fixed_path, moving_path, mask_path))

    transform_name = "Rigid" if kind == "rigid-halfway" else "SyN"
    metrics = {"correlation": correlation, "rmse": rmse, "mapd": mapd}
    selected = metrics if kind == "rigid-halfway" else {"mapd": mapd}
    for name, matrix in selected.items():
        atomic_savetxt(directory / f"{name}_matrix_{transform_name}_{TSNR_DATASET_ID}.txt", matrix)
    provenance = directory / (
        f"halfway_matrix_Rigid_{TSNR_DATASET_ID}_provenance.tsv"
        if kind == "rigid-halfway"
        else f"mapd_matrix_SyN_{TSNR_DATASET_ID}_provenance.tsv"
    )
    method = (
        "directional_rigid_halfway_fixed_denominator"
        if kind == "rigid-halfway"
        else "directional_SyN_physical_tSNR_fixed_denominator"
    )
    with provenance.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(("generated_at", "method", "moving_session", "fixed_session",
                         "status", "valid_voxels", "fixed_tsnr", "moving_tsnr", "mask"))
        generated = datetime.now(timezone.utc).isoformat()
        for row in rows:
            writer.writerow((generated, method, *row))
    print(f"Saved {kind} tSNR matrices and provenance in {directory}")


def compute_pair(args):
    for name in ("fixed", "moving", "output", "metric_output"):
        if getattr(args, name) is None:
            raise SystemExit(f"--{name.replace('_', '-')} is required for pair mode.")
    if args.physical_values and args.mean_scale_mask:
        raise SystemExit(
            "--physical-values and --mean-scale-mask are mutually exclusive."
        )
    fixed_image, fixed = load_image(args.fixed)
    moving_image, moving = load_image(args.moving)

    if (
        fixed.shape != moving.shape
        or not np.allclose(fixed_image.affine, moving_image.affine)
    ):
        raise SystemExit("The fixed and warped-moving images do not share one grid.")

    mask = np.isfinite(fixed) & np.isfinite(moving)
    mask &= (fixed != 0) & (moving != 0)
    if args.mask:
        mask_image, mask_data = load_image(args.mask)
        if (
            fixed.shape != mask_data.shape
            or not np.allclose(fixed_image.affine, mask_image.affine)
        ):
            raise SystemExit("The mask and registered images do not share one grid.")
        mask &= mask_data > 0

    if not np.any(mask):
        raise SystemExit("The common comparison mask is empty.")

    if args.mean_scale_mask:
        scale_mask_image, scale_mask_data = load_image(args.mean_scale_mask)
        if (
            fixed.shape != scale_mask_data.shape
            or not np.allclose(fixed_image.affine, scale_mask_image.affine)
        ):
            raise SystemExit("The mean-scale mask and registered images differ in grid.")
        scale_mask = mask & (scale_mask_data > 0)
        if not np.any(scale_mask):
            raise SystemExit("The common mean-scale mask is empty.")
        fixed_compare, fixed_mean = scale_to_mask_mean(fixed, scale_mask, "fixed")
        moving_compare, moving_mean = scale_to_mask_mean(moving, scale_mask, "moving")
        print(
            f"Mean scaling: fixed={fixed_mean:.8g}, moving={moving_mean:.8g}, "
            f"voxels={np.count_nonzero(scale_mask)}; scaled means=1.0"
        )
        percent_mask = mask & (fixed_compare != 0)
    elif args.physical_values:
        fixed_compare = fixed
        moving_compare = moving
        percent_mask = mask & (fixed != 0)
    else:
        fixed_compare = robust_normalize(fixed, mask)
        moving_compare = robust_normalize(moving, mask)
        # Values close to zero in the normalized reference make relative
        # differences unstable.
        percent_mask = mask & (fixed_compare >= 0.05)
    if not np.any(percent_mask):
        raise SystemExit("No voxels remain after the normalized-reference threshold.")

    percent_difference = np.full(fixed.shape, np.nan, dtype=np.float32)
    percent_difference[percent_mask] = (
        100.0
        * (moving_compare[percent_mask] - fixed_compare[percent_mask])
        / fixed_compare[percent_mask]
    )
    mean_absolute_percent_difference = float(
        np.mean(np.abs(percent_difference[percent_mask]))
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    header = fixed_image.header.copy()
    header.set_data_dtype(np.float32)
    nib.save(
        nib.Nifti1Image(percent_difference, fixed_image.affine, header=header),
        str(args.output),
    )
    args.metric_output.write_text(
        f"{mean_absolute_percent_difference:.4f}\n",
        encoding="utf-8",
    )


def main():
    args = parse_args()
    if args.tsnr_batch:
        compute_tsnr_batch(args.tsnr_batch, args.derivatives_dir)
    else:
        compute_pair(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

"""Compute a robustly scaled percent-difference image for one registered pair."""

import argparse
from pathlib import Path

import nibabel as nib
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Percentile-scale the fixed and warped-moving images, then compute "
            "100 * (moving - fixed) / fixed."
        )
    )
    parser.add_argument("--fixed", type=Path, required=True)
    parser.add_argument("--moving", type=Path, required=True)
    parser.add_argument("--mask", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metric-output", type=Path, required=True)
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


def main():
    args = parse_args()
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

    fixed_norm = robust_normalize(fixed, mask)
    moving_norm = robust_normalize(moving, mask)

    # Match the TrueForm/patient-specific comparison: values close to zero in
    # the normalized reference make relative differences unstable.
    percent_mask = mask & (fixed_norm >= 0.05)
    if not np.any(percent_mask):
        raise SystemExit("No voxels remain after the normalized-reference threshold.")

    percent_difference = np.full(fixed.shape, np.nan, dtype=np.float32)
    percent_difference[percent_mask] = (
        100.0
        * (moving_norm[percent_mask] - fixed_norm[percent_mask])
        / fixed_norm[percent_mask]
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


if __name__ == "__main__":
    main()

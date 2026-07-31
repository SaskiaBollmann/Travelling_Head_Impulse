#!/usr/bin/env python3

"""Compute fixed-session white-matter MAPD matrices from difference images."""

import argparse
from pathlib import Path

import nibabel as nib
import numpy as np


SESSIONS = (
    "260529_THS_ses01",
    "260601_THS_ses02",
    "260602_THS_ses03",
    "260602_THS_ses04",
    "260611_THS_ses05",
    "260618_THS_ses06",
    "260618_THS_ses07",
)
TRANSFORMS = ("Rigid", "Affine", "SyN")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--difference-dir", type=Path, required=True)
    parser.add_argument("--wm-root", type=Path, required=True)
    parser.add_argument("--threshold", type=float, default=0.95)
    return parser.parse_args()


def one_wm_mask(wm_root, session, threshold):
    token = int(round(100 * threshold))
    path = wm_root / session / f"wm_mask_fast_pve{token:02d}.nii.gz"
    if not path.is_file():
        raise SystemExit(
            f"P(WM) >= {threshold:.2f} mask does not exist for {session}: {path}"
        )
    return path


def load_data(path):
    image = nib.load(str(path))
    return image, image.get_fdata(dtype=np.float32)


def main():
    args = parse_args()
    folder = args.difference_dir.name
    wm_images = {}
    for session in SESSIONS:
        path = one_wm_mask(args.wm_root, session, args.threshold)
        image, data = load_data(path)
        wm_images[session] = (path, image, data >= 0.5)

    for transform in TRANSFORMS:
        matrix = np.full((len(SESSIONS), len(SESSIONS)), np.nan)
        counts = np.zeros(matrix.shape, dtype=int)
        for i, moving in enumerate(SESSIONS):
            for j, fixed in enumerate(SESSIONS):
                difference_path = args.difference_dir / (
                    f"reg_{transform}_mov_{moving}_to_fix_{fixed}_"
                    "PERCENT_DIFF.nii.gz"
                )
                if not difference_path.is_file():
                    continue

                difference_image, difference = load_data(difference_path)
                mask_path, mask_image, wm_mask = wm_images[fixed]
                if (
                    difference.shape != wm_mask.shape
                    or not np.allclose(difference_image.affine, mask_image.affine)
                ):
                    raise SystemExit(
                        f"Grid mismatch between {difference_path} and {mask_path}."
                    )

                valid = wm_mask & np.isfinite(difference)
                counts[i, j] = int(np.count_nonzero(valid))
                if counts[i, j]:
                    matrix[i, j] = float(np.mean(np.abs(difference[valid])))

        matrix_path = args.difference_dir / (
            f"wm_mapd_matrix_{transform}_{folder}.txt"
        )
        count_path = args.difference_dir / (
            f"wm_mapd_voxel_count_{transform}_{folder}.txt"
        )
        np.savetxt(matrix_path, matrix, fmt="%.4f")
        np.savetxt(count_path, counts, fmt="%d")
        print(f"Saved: {matrix_path}")
        print(f"Saved: {count_path}")


if __name__ == "__main__":
    main()

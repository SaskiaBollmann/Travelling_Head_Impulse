#!/usr/bin/env python3
"""Prepare rigid halfway-space tSNR images from existing ANTs transforms."""

import argparse
import csv
import filecmp
from pathlib import Path
import shutil
import subprocess

import numpy as np
from scipy.io import loadmat, savemat
from scipy.linalg import sqrtm

DATASET_ID = "reg-ep2d_bold_mean__corr-ep2d_bold_tsnr_masked"
DEFAULT_DIR = Path("/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration") / DATASET_ID
SESSIONS = (
    "260529_THS_ses01", "260601_THS_ses02", "260602_THS_ses03",
    "260602_THS_ses04", "260611_THS_ses05", "260618_THS_ses06",
    "260618_THS_ses07",
)


def parse_args():
    parser = argparse.ArgumentParser(description=(
        "Split existing directional rigid transforms and resample both original "
        "tSNR maps once into halfway space. No registration is run."
    ))
    parser.add_argument("--moving-session", choices=SESSIONS)
    parser.add_argument("--fixed-session", choices=SESSIONS)
    parser.add_argument("--all-pairs", action="store_true")
    parser.add_argument("-F", "--force", action="store_true")
    parser.add_argument("--derivatives-dir", type=Path, default=DEFAULT_DIR)
    args = parser.parse_args()
    if args.all_pairs and (args.moving_session or args.fixed_session):
        parser.error("--all-pairs cannot be combined with individual sessions")
    if not args.all_pairs and not (args.moving_session and args.fixed_session):
        parser.error("provide both session options, or use --all-pairs")
    if not args.all_pairs and args.moving_session == args.fixed_session:
        parser.error("moving and fixed sessions must differ")
    return args


def read_sources(directory):
    path = directory / f"source_images_Rigid_{DATASET_ID}.tsv"
    if not path.is_file():
        raise SystemExit(f"Required rigid provenance does not exist: {path}")
    with path.open(newline="", encoding="utf-8") as stream:
        sources = {
            row["session"]: (Path(row["registration_file"]), Path(row["correlation_file"]))
            for row in csv.DictReader(stream, delimiter="\t")
            if row.get("status") == "ready"
        }
    missing = set(SESSIONS) - set(sources)
    if missing:
        raise SystemExit(f"Rigid provenance lacks ready sessions: {', '.join(sorted(missing))}")
    return sources


def split_affine(source, moving_path, fixed_path):
    key = "AffineTransform_double_3_3"
    transform = loadmat(source)
    if key not in transform or "fixed" not in transform:
        raise SystemExit(f"Not a 3D ANTs affine transform: {source}")
    parameters = np.asarray(transform[key], dtype=np.float64).reshape(-1)
    center = np.asarray(transform["fixed"], dtype=np.float64).reshape(-1)
    matrix = parameters[:9].reshape(3, 3)
    full = np.eye(4)
    full[:3, :3] = matrix
    full[:3, 3] = parameters[9:] + center - matrix @ center
    moving_half = sqrtm(full)
    if np.max(np.abs(np.imag(moving_half))) > 1e-8:
        raise SystemExit(f"Affine has no numerically real square root: {source}")
    moving_half = np.real(moving_half)
    moving_half[3] = (0, 0, 0, 1)
    if not np.allclose(moving_half @ moving_half, full, atol=1e-8):
        raise SystemExit(f"Half-transform validation failed: {source}")

    def save(path, half):
        half_matrix = half[:3, :3]
        translation = half[:3, 3] - center + half_matrix @ center
        savemat(path, {key: np.r_[half_matrix.ravel(), translation][:, None],
                       "fixed": center[:, None]}, format="4")

    save(moving_path, moving_half)
    save(fixed_path, np.linalg.inv(moving_half))


def ants_executable():
    executable = shutil.which("antsApplyTransforms")
    if executable:
        return executable
    probe = subprocess.run(
        ["bash", "-lc", "ml ants >/dev/null 2>&1 && command -v antsApplyTransforms"],
        check=False, capture_output=True, text=True,
    )
    if probe.returncode == 0 and probe.stdout.strip():
        return probe.stdout.strip().splitlines()[-1]
    raise SystemExit("antsApplyTransforms is unavailable; load the ANTs module first.")


def resample(executable, source, reference, interpolation, transform, output):
    subprocess.run([
        executable, "-d", "3", "-i", str(source), "-r", str(reference),
        "-n", interpolation, "-t", str(transform), "-o", str(output),
    ], check=True)


def prepare_pair(directory, sources, moving, fixed, force):
    output_dir = directory / "halfway"
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = output_dir / f"rigid_halfway_from_existing_mov_{moving}_to_fix_{fixed}"
    original = directory / f"reg_Rigid_mov_{moving}_to_fix_{fixed}_0GenericAffine.mat"
    paths = {
        "moving_transform": Path(f"{prefix}_moving_to_half.mat"),
        "fixed_transform": Path(f"{prefix}_fixed_to_half.mat"),
        "transform_copy": Path(f"{prefix}_source_0GenericAffine.mat"),
        "moving_mean": Path(f"{prefix}_mean_moving.nii.gz"),
        "fixed_mean": Path(f"{prefix}_mean_fixed.nii.gz"),
        "mask": Path(f"{prefix}_brain_mask.nii.gz"),
        "moving_tsnr": Path(f"{prefix}_tsnr_moving.nii.gz"),
        "fixed_tsnr": Path(f"{prefix}_tsnr_fixed.nii.gz"),
    }
    moving_mean, moving_tsnr = sources[moving]
    fixed_mean, fixed_tsnr = sources[fixed]
    fixed_mask = directory / f"mask_{fixed}.nii.gz"
    missing = [path for path in (original, moving_mean, moving_tsnr, fixed_mean,
                                  fixed_tsnr, fixed_mask) if not path.is_file()]
    if missing:
        raise SystemExit(f"Required input does not exist: {missing[0]}")
    if force:
        for path in paths.values():
            path.unlink(missing_ok=True)
    copied = paths["transform_copy"]
    if copied.is_file() and not filecmp.cmp(original, copied, shallow=False):
        raise SystemExit(
            f"Source transform changed for {moving} -> {fixed}; use --force to regenerate."
        )
    if not paths["moving_transform"].is_file() or not paths["fixed_transform"].is_file():
        print(f"Splitting rigid transform: {moving} -> {fixed}")
        split_affine(original, paths["moving_transform"], paths["fixed_transform"])
        shutil.copy2(original, copied)

    jobs = (
        (moving_mean, fixed_mean, "Linear", paths["moving_transform"], paths["moving_mean"]),
        (fixed_mean, fixed_mean, "Linear", paths["fixed_transform"], paths["fixed_mean"]),
        (fixed_mask, fixed_mean, "NearestNeighbor", paths["fixed_transform"], paths["mask"]),
        (moving_tsnr, fixed_mean, "Linear", paths["moving_transform"], paths["moving_tsnr"]),
        (fixed_tsnr, fixed_mean, "Linear", paths["fixed_transform"], paths["fixed_tsnr"]),
    )
    pending = [job for job in jobs if not job[-1].is_file()]
    if pending:
        executable = ants_executable()
        for source, reference, interpolation, transform, output in pending:
            print(f"Writing {output}")
            resample(executable, source, reference, interpolation, transform, output)
    print(f"Ready: {moving} -> {fixed}")


def main():
    args = parse_args()
    sources = read_sources(args.derivatives_dir)
    pairs = (
        ((moving, fixed) for moving in SESSIONS for fixed in SESSIONS if moving != fixed)
        if args.all_pairs else ((args.moving_session, args.fixed_session),)
    )
    for moving, fixed in pairs:
        prepare_pair(args.derivatives_dir, sources, moving, fixed, args.force)


if __name__ == "__main__":
    main()

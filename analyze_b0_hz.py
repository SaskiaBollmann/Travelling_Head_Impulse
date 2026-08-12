#!/usr/bin/env python3

"""Resample B0 maps into pairwise spaces and compute correlation and RMSE in Hz."""

import argparse
import csv
import json
import math
import shutil
import subprocess
import tempfile
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
TRANSFORMS = ("Rigid", "Affine")


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Convert previously registered ROMEO phase maps to Hz and calculate "
            "cross-session correlation and RMSE."
        )
    )
    parser.add_argument("--source-registration-dir", type=Path, required=True)
    parser.add_argument("--b0-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def find_one(directory, pattern):
    matches = sorted(directory.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one match for {pattern} in {directory}; found {len(matches)}"
        )
    return matches[0]


def hz_map_for_session(root, session):
    session_dir = root / session
    if session.endswith("ses04"):
        pattern = "gre_b0map_4iso_sag_[0-9]*_e2_ph_romeo/fieldmap_hz.nii.gz"
    else:
        pattern = "gre_b0map_4iso_sag_ND_*_e2_ph_romeo/fieldmap_hz.nii.gz"
    return find_one(session_dir, pattern)


def scale_from_metadata(hz_path):
    metadata_path = hz_path.with_name("fieldmap_hz.json")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    delta_te = float(metadata["EchoTimeDifference"])
    if not math.isfinite(delta_te) or delta_te <= 0:
        raise SystemExit(f"Invalid EchoTimeDifference in {metadata_path}")
    return 1.0 / (2.0 * math.pi * delta_te), metadata_path


def load_data(path):
    image = nib.load(str(path))
    return image, image.get_fdata(dtype=np.float32)


def save_image(data, reference, path, description):
    header = reference.header.copy()
    header.set_data_dtype(np.float32)
    header["descrip"] = description.encode("ascii")
    nib.save(
        nib.Nifti1Image(data.astype(np.float32), reference.affine, header),
        str(path),
    )


def copy_if_different(source, destination):
    if source.resolve() != destination.resolve():
        shutil.copy2(source, destination)


def apply_transform(
    input_path, reference_path, transform_path, output_path, interpolation
):
    subprocess.run(
        [
            "antsApplyTransforms",
            "-d",
            "3",
            "-i",
            str(input_path),
            "-r",
            str(reference_path),
            "-o",
            str(output_path),
            "-n",
            interpolation,
            "-t",
            str(transform_path),
        ],
        check=True,
    )


def main():
    args = parse_args()
    if shutil.which("antsApplyTransforms") is None:
        raise SystemExit(
            "antsApplyTransforms is required. Load the ANTs module before running."
        )
    args.output_dir.mkdir(parents=True, exist_ok=True)

    hz_paths = {
        session: hz_map_for_session(args.b0_root, session) for session in SESSIONS
    }
    hz_images = {}
    hz_data = {}
    romeo_masks = {}
    scales = {}
    metadata_paths = {}
    for session in SESSIONS:
        hz_images[session], hz_data[session] = load_data(hz_paths[session])
        romeo_mask_path = hz_paths[session].with_name("mask.nii")
        if not romeo_mask_path.is_file():
            raise SystemExit(f"Missing ROMEO mask: {romeo_mask_path}")
        romeo_mask_image, romeo_masks[session] = load_data(romeo_mask_path)
        if (
            hz_data[session].shape != romeo_masks[session].shape
            or not np.allclose(hz_images[session].affine, romeo_mask_image.affine)
        ):
            raise SystemExit(f"Grid mismatch for ROMEO mask: {romeo_mask_path}")
        scales[session], metadata_paths[session] = scale_from_metadata(
            hz_paths[session]
        )

    for session in SESSIONS:
        source_mask = args.source_registration_dir / f"mask_{session}.nii.gz"
        if not source_mask.is_file():
            raise SystemExit(f"Missing registration mask: {source_mask}")
        copy_if_different(source_mask, args.output_dir / source_mask.name)

    for transform in TRANSFORMS:
        correlation = np.full((len(SESSIONS), len(SESSIONS)), np.nan)
        rmse = np.full_like(correlation, np.nan)
        provenance_rows = []

        for moving_index, moving_session in enumerate(SESSIONS):
            for fixed_index, fixed_session in enumerate(SESSIONS):
                stem = (
                    f"reg_{transform}_mov_{moving_session}_to_fix_{fixed_session}"
                )
                source_transform = (
                    args.source_registration_dir / f"{stem}_0GenericAffine.mat"
                )
                source_mask = (
                    args.source_registration_dir / f"mask_{fixed_session}.nii.gz"
                )
                for required in (source_transform, source_mask):
                    if not required.is_file():
                        raise SystemExit(f"Missing required registration file: {required}")

                mask_image, mask = load_data(source_mask)
                fixed_image = hz_images[fixed_session]
                fixed_hz = hz_data[fixed_session]
                fixed_romeo_mask = romeo_masks[fixed_session]
                moving_romeo_mask_path = hz_paths[moving_session].with_name(
                    "mask.nii"
                )

                with tempfile.TemporaryDirectory(prefix="analyze_b0_hz_") as temp_dir:
                    temp_dir = Path(temp_dir)
                    warped_hz_path = temp_dir / "moving_hz.nii.gz"
                    warped_mask_path = temp_dir / "moving_romeo_mask.nii.gz"
                    apply_transform(
                        hz_paths[moving_session],
                        hz_paths[fixed_session],
                        source_transform,
                        warped_hz_path,
                        "Linear",
                    )
                    apply_transform(
                        moving_romeo_mask_path,
                        hz_paths[fixed_session],
                        source_transform,
                        warped_mask_path,
                        "NearestNeighbor",
                    )
                    warped_image, moving_hz = load_data(warped_hz_path)
                    _, moving_romeo_mask = load_data(warped_mask_path)

                if (
                    fixed_hz.shape != moving_hz.shape
                    or fixed_hz.shape != mask.shape
                    or fixed_hz.shape != moving_romeo_mask.shape
                    or not np.allclose(fixed_image.affine, warped_image.affine)
                    or not np.allclose(fixed_image.affine, mask_image.affine)
                ):
                    raise SystemExit(f"Grid mismatch for {stem}")

                valid = (
                    (mask > 0)
                    & (fixed_romeo_mask > 0)
                    & (moving_romeo_mask > 0)
                    & np.isfinite(fixed_hz)
                    & np.isfinite(moving_hz)
                )
                voxel_count = int(np.count_nonzero(valid))
                if voxel_count < 100:
                    raise SystemExit(f"Too few common valid voxels for {stem}: {voxel_count}")

                fixed_values = fixed_hz[valid]
                moving_values = moving_hz[valid]
                correlation[moving_index, fixed_index] = np.corrcoef(
                    fixed_values, moving_values
                )[0, 1]
                rmse[moving_index, fixed_index] = np.sqrt(
                    np.mean((moving_values - fixed_values) ** 2)
                )

                registered = np.full(moving_hz.shape, np.nan, dtype=np.float32)
                difference = np.full(moving_hz.shape, np.nan, dtype=np.float32)
                registered[valid] = moving_hz[valid]
                difference[valid] = moving_hz[valid] - fixed_hz[valid]
                save_image(
                    registered,
                    fixed_image,
                    args.output_dir / f"{stem}_HZ_Warped.nii.gz",
                    "Registered B0 frequency offset (Hz)",
                )
                save_image(
                    difference,
                    fixed_image,
                    args.output_dir / f"{stem}_DIFF_HZ.nii.gz",
                    "B0 moving minus fixed (Hz)",
                )
                copy_if_different(
                    source_transform, args.output_dir / source_transform.name
                )
                provenance_rows.append(
                    {
                        "transform": transform,
                        "moving_session": moving_session,
                        "fixed_session": fixed_session,
                        "moving_hz_source": hz_paths[moving_session],
                        "fixed_hz_source": hz_paths[fixed_session],
                        "transform_source": source_transform,
                        "moving_romeo_mask_source": moving_romeo_mask_path,
                        "moving_hz_metadata": metadata_paths[moving_session],
                        "moving_hz_per_radian": f"{scales[moving_session]:.9f}",
                        "mask": source_mask,
                        "voxel_count": voxel_count,
                        "correlation": f"{correlation[moving_index, fixed_index]:.8f}",
                        "rmse_hz": f"{rmse[moving_index, fixed_index]:.8f}",
                    }
                )

        prefix = "reg-gre_b0map_4iso_sag_ND_e1__corr-gre_b0map_4iso_sag_ND_romeo_hz_masked"
        correlation_path = (
            args.output_dir / f"correlation_matrix_{transform}_{prefix}.txt"
        )
        rmse_path = args.output_dir / f"rmse_hz_matrix_{transform}_{prefix}.txt"
        np.savetxt(correlation_path, correlation, fmt="%.6f")
        np.savetxt(rmse_path, rmse, fmt="%.4f")

        provenance_path = args.output_dir / f"metrics_{transform}_{prefix}_provenance.tsv"
        with provenance_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(
                stream, fieldnames=provenance_rows[0].keys(), delimiter="\t"
            )
            writer.writeheader()
            writer.writerows(provenance_rows)

        print(f"{transform}: saved correlation and RMSE-in-Hz results")


if __name__ == "__main__":
    main()

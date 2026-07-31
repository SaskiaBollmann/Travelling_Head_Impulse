#!/usr/bin/env python3

"""Create per-session and cross-session QC plots for strict FAST WM masks."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np


ROOT = Path(
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


def one_file(folder, pattern, description):
    matches = sorted(folder.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one {description} in {folder}; found {len(matches)}."
        )
    return matches[0]


def load_session(session):
    folder = ROOT / session
    image_path = one_file(folder, "*_brain.nii.gz", "brain-extracted MP2RAGE")
    mask_path = folder / "wm_mask_fast_pve95.nii.gz"
    if not mask_path.is_file():
        raise SystemExit(f"WM mask not found: {mask_path}")

    image = nib.as_closest_canonical(nib.load(str(image_path)))
    mask_image = nib.as_closest_canonical(nib.load(str(mask_path)))
    data = image.get_fdata(dtype=np.float32)
    mask = np.asarray(mask_image.dataobj) > 0
    if data.shape != mask.shape or not np.allclose(image.affine, mask_image.affine):
        raise SystemExit(f"Grid mismatch for {session}.")

    values = data[np.isfinite(data) & (data != 0)]
    low, high = np.percentile(values, (1, 99))
    indices = (
        int(np.argmax(mask.sum(axis=(1, 2)))),
        int(np.argmax(mask.sum(axis=(0, 2)))),
        int(np.argmax(mask.sum(axis=(0, 1)))),
    )
    return folder, data, mask, low, high, indices


def draw_overlay(ax, base, mask, low, high, title):
    overlay = np.ma.masked_where(~mask, np.ones(base.shape, dtype=np.float32))
    ax.imshow(base, cmap="gray", vmin=low, vmax=high)
    ax.imshow(overlay, cmap="autumn", alpha=0.32, vmin=0, vmax=1)
    ax.contour(mask.astype(float), levels=[0.5], colors=["#00ffff"], linewidths=0.55)
    ax.set_title(title, fontsize=10)
    ax.set_axis_off()


def main():
    loaded = {}
    plane_names = ("Sagittal", "Coronal", "Axial")
    for session in SESSIONS:
        folder, data, mask, low, high, indices = load_session(session)
        loaded[session] = (data, mask, low, high, indices)

        fig, axes = plt.subplots(1, 3, figsize=(12, 4.2))
        for axis, (ax, name, index) in enumerate(zip(axes, plane_names, indices)):
            base_slice = np.rot90(np.take(data, index, axis=axis))
            mask_slice = np.rot90(np.take(mask, index, axis=axis))
            draw_overlay(
                ax,
                base_slice,
                mask_slice,
                low,
                high,
                f"{name} (slice {index})",
            )
        fig.suptitle(
            f"FAST-only WM mask P(WM) ≥ 0.95 — {session}\n"
            "orange fill; cyan boundary",
            fontsize=13,
        )
        fig.tight_layout()
        output = folder / "wm_mask_fast_pve95_QC.png"
        fig.savefig(output, dpi=200, bbox_inches="tight")
        plt.close(fig)
        print(f"Saved: {output}")

    fig, axes = plt.subplots(2, 4, figsize=(14, 8))
    for ax, session in zip(axes.flat, SESSIONS):
        data, mask, low, high, indices = loaded[session]
        index = indices[0]
        draw_overlay(
            ax,
            np.rot90(data[index, :, :]),
            np.rot90(mask[index, :, :]),
            low,
            high,
            f"{session}\nSagittal slice {index}",
        )
    axes.flat[-1].set_axis_off()
    fig.suptitle(
        "FAST-only WM masks P(WM) ≥ 0.95 — all sessions\n"
        "orange fill; cyan boundary",
        fontsize=15,
    )
    fig.tight_layout()
    combined = ROOT / "wm_mask_fast_pve95_sagittal_all_sessions_QC.png"
    fig.savefig(combined, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {combined}")


if __name__ == "__main__":
    main()

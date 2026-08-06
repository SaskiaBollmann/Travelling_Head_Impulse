# Travelling_Head_Impulse

Pipeline for comparing MP2RAGE, B1, B0, and EPI acquisitions across repeated
scanning sessions (Stanford, Berkeley, Magdeburg) of the same subject, to
characterize reproducibility across sites/table positions/coil setups.
Steps below are roughly in pipeline order: conversion → preprocessing →
per-session QC → cross-session registration and comparison metrics →
plotting.

## Dicom to Nifti conversion
uses dcm2niix dicomtools

dicomtools_1.0.0_20250204/dcm2niix (Chris Rorden's dcm2niiX version v1.0.20241211)

`dcm2niix -f "%d_%s" -o . subfolder/`

## Denoising of MP2RAGE images
based on Jose Marques original code from https://github.com/JosePMarques/MP2RAGE-related-scripts (requires SPM on the path)
SPM version SPM25 (25.01.02)

`Denoise_MP2RAGE`

`Denoise_MP2RAGE.m` loops over the patient-specific and TrueForm MP2RAGE
batches (ND and non-ND) in the current directory, finds each batch's UNI,
INV1, and INV2 images, and overwrites the existing UNI-DEN file with
`RobustCombination` using batch-specific regularization (60 for standard, 5
for ND).

## N4 bias-field analysis
`n4bias_field_analysis.sh` runs ANTs `N4BiasFieldCorrection` (unmasked,
B-spline distance 150) on every `INV2_ND` and `UNI-DEN_ND` image for one
session, skipping any facemasked files. It is a Slurm job, not a
preprocessing dependency of later steps — used to inspect the residual bias
field on the denoised images.

```bash
sbatch n4bias_field_analysis.sh <session_id>
```

Outputs (`*_N4corrected.nii.gz`, `*_biasfield.nii.gz`) are written to
`derivatives/biasfield/<session_id>/`.

## Deface MP2RAGE images
uses mideface from freesurfer and slicer from FSL
freesurfer_8.1.0_20260311
fsl_6.0.7.18_20250928

`do_defacing`

For each `UNI-DEN_ND` reference image, `mideface` generates a facemask, which
is then applied to every other MP2RAGE image in the same batch
(patientSpecific or TrueForm), so all images from one acquisition share one
mask. `slicer` renders a QC PNG for every defaced image.

## Patient-specific vs TrueForm MP2RAGE comparison
Compares the patient-specific (individually shimmed/positioned) and
TrueForm (standard coil position) MP2RAGE acquisitions taken within the same
session.

`register_mp2rage_ps_trueform_halfway.sh` computes an inverse-consistent
rigid registration between the two with FreeSurfer `mri_robust_register`,
resampling both into a shared halfway space, and creates a brain mask from
the halfway TrueForm image with `mri_synthstrip`:

```bash
bash register_mp2rage_ps_trueform_halfway.sh ses02
bash register_mp2rage_ps_trueform_halfway.sh ses03 --force
```

`compare_mp2rage_ps_trueform.sh` instead registers patient-specific to
TrueForm directly (ANTs rigid and/or affine) across all 7 sessions and
reports the FSL `fslcc` correlation coefficient per session/transform:

```bash
bash compare_mp2rage_ps_trueform.sh -t both -m
```

`plot_mp2rage_ps_trueform_halfway_percent_difference.py` percentile-normalizes
the halfway-space images and plots a three-view (sagittal/coronal/axial)
fixed / moving / percent-difference figure with the voxelwise correlation and
mean absolute percent difference:

```bash
python3 plot_mp2rage_ps_trueform_halfway_percent_difference.py --session ses03
```

## Unwrap GRE B0 phase maps

`preprocess_b0_romeo.sh` is a standalone preprocessing step. It unwraps each
`gre_b0map_4iso_sag*_e2_ph.nii[.gz]` phase image with ROMEO, using the matching
`*_e1.nii[.gz]` magnitude image as a guide. It processes both standard and
`_ND` acquisitions by default without changing the source images.

```bash
./preprocess_b0_romeo.sh --dry-run

mkdir -p /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs
sbatch preprocess_b0_romeo.sh

sbatch preprocess_b0_romeo.sh \
    --session 260529_THS_ses01 \
    --family standard
```

Outputs are written under
`derivatives/preprocessing/b0_romeo/<session>/<phase-basename>_romeo/`.
ROMEO's `unwrapped.nii`, mask, and settings file are kept together there.
The same directory also contains `fieldmap_hz.nii.gz` and
`fieldmap_hz.json`. Frequency is calculated (via `convert_b0_phase_to_hz.py`)
as unwrapped phase divided by `2*pi*DeltaTE`, with echo times read from each
acquisition's JSON sidecars (including Berkeley's different DeltaTE).

## Realign EPI runs and calculate mean and tSNR

`preprocess_epi_afni.sh` independently realigns each 4D `dzne_ep3d` and
`ep2d_bold` magnitude run using AFNI `3dvolreg`. It aligns to the middle time
point, saves the six motion parameters and affine matrices, then calculates
the temporal mean and tSNR from the realigned series. Phase images and static
single-volume images are skipped. Repeated same-protocol `ep3d` runs sharing
one grid are concatenated with `3dTcat` first and realigned as one series.

```bash
./preprocess_epi_afni.sh --dry-run

mkdir -p /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/preprocessing/logs
sbatch preprocess_epi_afni.sh

sbatch preprocess_epi_afni.sh \
    --session 260529_THS_ses01 \
    --type ep3d
```

Outputs are grouped by session and run under
`derivatives/preprocessing/realignment_afni/`.

## White-matter segmentation (FAST)

`segment_mp2rage_fast_wm_array.sh` is a 7-element Slurm array job (one task
per session). For each session it brain-extracts the patient-specific MP2RAGE
with the coregistration brain mask, runs FSL `fast`, and thresholds the WM
partial-volume map at P(WM) ≥ 0.95 to produce a strict WM mask
(`wm_mask_fast_pve95.nii.gz`). This mask is the WM restriction used later by
`compute_wm_mapd.py` and by `plot_cross_session_comparison.py --region wm`.

```bash
sbatch segment_mp2rage_fast_wm_array.sh
```

`plot_fast_wm_qc.py` renders per-session three-view overlays of each WM mask
on its brain-extracted MP2RAGE, plus one combined sagittal QC figure across
all sessions, saved next to each session's FAST outputs.

## Cross-session registration and similarity metrics

A generic pairwise-registration engine computes correlation, RMSE, and mean
absolute percent difference (MAPD) between every pair of the 7 sessions, for
a chosen image type ("registration id" for alignment, "correlation id" for
the metric image, which may differ, e.g. registering on MP2RAGE but scoring
B1). Percent difference is computed by `compute_percent_difference.py`
(percentile-normalizes fixed/moving to [0,1], excludes near-zero reference
voxels, and can operate on physical values instead with
`--physical-values`); results feed `plot_image_correlation.py`.

`image_correlation_fast.sh` (single Slurm job) runs rigid and/or affine ANTs
registration (`antsRegistrationSyNQuick.sh`) for all 49 session pairs and
writes 7×7 correlation/RMSE/MAPD matrices, or, with `--afni-epi`, compares
AFNI-realigned EPI mean/tSNR images instead of raw acquisitions:

```bash
sbatch image_correlation_fast.sh -r mp2rage_0p7iso_patientSpecific_UNI-DEN -R ND -m -t both
sbatch image_correlation_fast.sh --afni-epi ep2d --afni-corr tsnr
```

`image_correlation_syn_array.sh` is the SyN (nonlinear) counterpart, split
into a 49-task Slurm array (one task per session pair) because SyN
registration is much slower; `aggregate_syn_matrix.sh` then collects the
per-pair temp files that array produced into the same 7×7 matrix files and
triggers `plot_image_correlation.py`:

```bash
sbatch image_correlation_syn_array.sh -r mp2rage_0p7iso_patientSpecific_UNI-DEN -R ND -m
bash aggregate_syn_matrix.sh -r mp2rage_0p7iso_patientSpecific_UNI-DEN -R ND -m
```

`plot_image_correlation.py` turns any of the resulting
`correlation_matrix_*`, `rmse_matrix_*`, `rmse_hz_matrix_*`, `mapd_matrix_*`,
or `wm_mapd_matrix_*` text files into annotated heatmaps, grouped by site
(Stanford/Berkeley/Magdeburg), each rendered with and without the single
Berkeley session:

```bash
python3 plot_image_correlation.py mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked
```

## White-matter-restricted MAPD

`compute_wm_mapd.py` re-summarizes the `*_PERCENT_DIFF.nii.gz` images already
produced by the registration scripts above, restricting the mean absolute
percent difference to each fixed session's strict FAST WM mask, for the
Rigid, Affine, and SyN transforms:

```bash
python3 compute_wm_mapd.py \
    --difference-dir /oak/.../derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked \
    --wm-root /oak/.../derivatives/segmentation/fast
```

## Cross-session B0 comparison in Hz

`analyze_b0_hz.py` takes the Rigid/Affine registrations already computed by
`image_correlation_fast.sh` on the ROMEO-unwrapped phase (registered in
radians) and rescales each moving image back to Hz using its own
`EchoTimeDifference`, since B0 offset scales differ by session/site. It then
recomputes correlation and RMSE directly in Hz (rather than on the arbitrary
registered phase units) and writes registered/difference Hz images alongside
the standard matrix and provenance files.

```bash
python3 analyze_b0_hz.py \
    --source-registration-dir /oak/.../coregistration/reg-gre_b0map_4iso_sag_ND_e1__corr-gre_b0map_4iso_sag_ND_romeo_unwrapped_masked \
    --b0-root /oak/.../derivatives/preprocessing/b0_romeo \
    --output-dir /oak/.../coregistration/reg-gre_b0map_4iso_sag_ND_e1__corr-gre_b0map_4iso_sag_ND_romeo_hz_masked
```

## Consistent cross-session comparison plots

`plot_cross_session_comparison.py` is the single entry point for representative
MP2RAGE, B1, and B0 comparisons. All modes use the same fixed / registered
moving / difference layout and sagittal / coronal / axial views.

```bash
python3 plot_cross_session_comparison.py --modality mp2rage \
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \
    --transform Rigid --region whole-brain

python3 plot_cross_session_comparison.py --modality b1 \
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \
    --transform Rigid

python3 plot_cross_session_comparison.py --modality b0 \
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \
    --transform Rigid
```

MP2RAGE and B1 show percent difference and MAPD. B1 uses physical B1+ values
for the source panels. B0 shows signed frequency difference and RMSE in Hz;
percent difference is intentionally unavailable. The optional
`plot_cross_session_comparison_array.sh` launcher is a 126-task Slurm array
that generates every ordered (moving, fixed) MP2RAGE pair for all three
transforms.

## Voxel time-series and FFT spectrograms

`plot_voxel_spectrograms.py` is a QC tool for 4D phantom/EPI data: it
Otsu-thresholds the temporal mean to isolate the phantom, picks a handful of
representative (near-median, spatially separated) voxels, then plots each
voxel's percent-signal-change time course alongside its FFT amplitude
spectrum (useful for spotting mechanical/vibration or MR artifact
frequencies).

```bash
python3 plot_voxel_spectrograms.py <4d.nii.gz> --tr 2.0 --n-voxels 4
```

Saves a combined figure, a CSV of voxel coordinates/stats, and an `.npz` with
the raw signals and spectra to a `figures/` folder next to the input.

## Tar Dicoms

`for dir in *; do tar -c -v -f $dir.tar.gz $dir/*; done`

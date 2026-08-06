# Travelling_Head_Impulse

## Dicom to Nifti conversion
uses dcm2niix dicomtools

dicomtools_1.0.0_20250204/dcm2niix (Chris Rorden's dcm2niiX version v1.0.20241211)

`dcm2niix -f "%d_%s" -o . subfolder/`

## Denoising of MP2RAGE images
based on Jose Marques original code from https://github.com/JosePMarques/MP2RAGE-related-scripts (requires SPM on the path)
SPM version SPM25 (25.01.02)

`Denoise_MP2RAGE`

## Deface MP2RAGE images
uses mideface from freesurfer and slicer from FSL
freesurfer_8.1.0_20260311
fsl_6.0.7.18_20250928

`do_defacing`

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
`fieldmap_hz.json`. Frequency is calculated as unwrapped phase divided by
`2*pi*DeltaTE`, with echo times read from each acquisition's JSON sidecars
(including Berkeley's different DeltaTE).


## Consistent cross-session comparison plots

`plot_cross_session_comparison.py` is the single entry point for representative
MP2RAGE, B1, and B0 comparisons. All modes use the same fixed / registered
moving / difference layout and sagittal / coronal / axial views.

```bash
python3 plot_cross_session_comparison.py --modality mp2rage \\
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \\
    --transform Rigid --region whole-brain

python3 plot_cross_session_comparison.py --modality b1 \\
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \\
    --transform Rigid

python3 plot_cross_session_comparison.py --modality b0 \\
    --moving-session 260601_THS_ses02 --fixed-session 260602_THS_ses03 \\
    --transform Rigid
```

MP2RAGE and B1 show percent difference and MAPD. B1 uses physical B1+ values
for the source panels. B0 shows signed frequency difference and RMSE in Hz;
percent difference is intentionally unavailable. The optional
`plot_cross_session_comparison_array.sh` launcher generates all MP2RAGE pairs.


## Realign EPI runs and calculate mean and tSNR

`preprocess_epi_afni.sh` independently realigns each 4D `dzne_ep3d` and
`ep2d_bold` magnitude run using AFNI `3dvolreg`. It aligns to the middle time
point, saves the six motion parameters and affine matrices, then calculates
the temporal mean and tSNR from the realigned series. Phase images and static
single-volume images are skipped.

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

## Tar Dicoms

`for dir in *; do tar -c -v -f $dir.tar.gz $dir/*; done`


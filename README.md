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

## Tar Dicoms

`for dir in *; do tar -c -v -f $dir.tar.gz $dir/*; done`



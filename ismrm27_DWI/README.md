# ISMRM27
## Assessing Cross-Site Reproducibility of 7T Diffusion MRI acquired with High-Performance ‘Impulse’ Head Gradients

Analysis author: Daniel Uher  
Contact: daniel.uher@ovgu.de  

Thank you for your intererst in our work!  
Please contact me or the repo owners for data access.  
The analysis script is setup as a plug-and-play once you have access to my folder structure.  
The script outputs the images in "saved_figs" folder.

What was used for the analysis:  
- OS: Debian GNU/Linux 13 (trixie)
- CPU: Intel Ultra 9 285 24C/24T
- Python: 3.13.9

Dependencies:
- nibabel
- dipy
- numpy
- scipy
- matplotlib
- pandas
- seaborn
- statsmodels
- scipy

## Logic
Preprocessing -> Metrics -> Coreg -> Analysis

## Preprocessing
The preprocessing folder contains the preprocessing pipeline. 
The pipeline is set up in steps. The steps are set up in the `pipeline.config`.
`pipeline.functions` wraps apptainer calls for local .sif containers (MRtrix3, ANTs and Freesurfer)

For your local execution, it is necessary to adjust this and define calls for your own
paths (paths to containers in `pipeline.config`) and setup (whether you run containers or native installs)

> !WARNING
> Work in progress - please feel free to contact to navigate this folder if you are interested.

## Metrics
After preprocessing, metrics need to be calculated via the `metrics.py` and the `tracts.sh`,
which will generate amongst others the FW-corrected FA, NDI, ODI, and TDI.

## Coreg
Afterwards, `coreg.sh` and `coreg_b1map.sh` coregisters all relevant images to MNI and DWI spaces



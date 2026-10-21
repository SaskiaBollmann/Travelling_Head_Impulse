# 7T Diffusion MRI Preprocessing Pipeline (Terra.X Impulse)  
------------------------------------------------------------------------

**Make sure to adjust pipeline.config before running!!**

A modular Bash pipeline for preprocessing diffusion-weighted MRI (DWI) data
acquired on a Siemens 7T Terra.X Impulse Edition (7Tx). Designed for multi-shell acquisitions.

> **WARNING**: This pipeline is NOT plug-and-play and will likely error out without the established folder structure and configurations. Please contact me in case of interest!

## Usage

```bash
# 1. Edit pipeline.config
# 2. Run from the pipeline directory:
bash run_pipeline.sh <sess> <start_step>
```

To resume from a specific step (e.g., after fixing an EDDY parameter),
set `START_STEP` in `pipeline.config` accordingly. All prior step outputs
must already exist in `WORKDIR`.

Logs are automatically written to `LOGDIR/pipeline_<timestamp>.log`.

## Pipeline Overview

Each step script takes two positional arguments — `PREVIOUS_STEPNAME` and
`STEPCOUNT` - supplied automatically by `run_pipeline.sh`. All shared
settings live in `pipeline.config`, which every step sources.

## Requirements

- Bash ≥ 4 (uses associative-style array indexing)
- MRtrix3 (denoise, degibbs, mrconvert, mrcat, dwibiascorrect)
- FSL ≥ 6.0 (`topup`, `eddy_cuda11.0`, `convertwarp`, `applywarp`)
- FreeSurfer ≥ 7.4.2 (`mri_synthstrip`)
- ANTs (`antsApplyTransforms`)
- `gradient_unwarp.py` (cusom Z02 implementaiton - [[gradunwarp-z02|/../blob/main/diffusion_mri/gnc/gradunwarp-z02]])
- MATLAB with NORDIC toolbox on the path
- Docker/Singularity/Apptainer if running containerized MRtrix/FreeSurfer/ANTs (paths defined in config and invoked via wrapper functions in pipeline.functions)

## Output directory Structure

├── steps/  
│ ├── init/ # copied raw inputs  
│ ├── denoise/  
│ ├── degibbs/  
│ ├── prefsl/  
│ ├── topup_eddy/  
│ ├── gnc/  
│ └── bias/ # final corrected outputs written to OUTDIR  
└── logs/ # timestamped run logs  


## Configuration (`pipeline.config`)

Majority of paths, subject IDs, acquisition parameters, and processing options are
centralized here.

## Authors

Pipeline scripts originally written by Daniel Uher (daniel.uher@ovgu.de).

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

Logs are automatically written to `LOGDIR/pipeline_<timestamp>.log`.

## Pipeline Overview

Each step script takes two positional arguments — `PREVIOUS_STEPNAME` and
`STEPCOUNT` - supplied automatically by `run_pipeline.sh`. All shared
settings live in `pipeline.config`, which every step sources.

## Requirements
TODO

## Output directory Structure
TODO

## Configuration (`pipeline.config`)

Majority of paths, subject IDs, acquisition parameters, and processing options are
centralized here.

## Authors

Pipeline scripts originally written by Daniel Uher (daniel.uher@ovgu.de).

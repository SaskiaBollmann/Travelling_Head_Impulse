#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Sep  4 15:40:05 2026

@author: duher
"""

from z02.dwi.gtab import VoxelwiseGradientTable
from z02.dwi.engine import fit_voxelwise
from z02.dwi.io import save_metrics
from dipy.core.gradients import gradient_table
import nibabel as nib
import numpy as np
import os
import amico

def combine_aparc_aseg(input_path: str, output_path: str = None) -> tuple[np.ndarray, np.ndarray]:
    """
    Combines FreeSurfer's aparc+aseg volumetric segmentation into 3 main tissue classes.
    
    Output Label Mapping:
      0 = Background / Other (CSF, Cerebellum GM, Brainstem)
      1 = Cortical Gray Matter
      2 = White Matter
      3 = Deep (Subcortical) Gray Matter
    """
    # Load image volume
    img = nib.load(input_path)
    data = img.get_fdata().astype(int)
    
    combined_mask = np.zeros_like(data, dtype=np.uint8)

    # 1. Cortical Gray Matter (LH: 1000-1035, RH: 2000-2035)
    cortical_gm_ids = list(range(1000, 1036)) + list(range(2000, 2036))
    
    # 2. White Matter (Cerebral WM, Cerebellar WM, Corpus Callosum, WM Hypointensities)
    wm_ids = [
        2, 41,                     # Left & Right Cerebral WM
        7, 46,                     # Left & Right Cerebellar WM
        251, 252, 253, 254, 255,   # Corpus Callosum divisions
        77, 78, 79                 # WM Hypointensities
    ]

    # 3. Deep / Subcortical Gray Matter (Basal Ganglia, Thalamus, Limbic)
    deep_gm_ids = [
        10, 49,   # Thalamus
        11, 50,   # Caudate
        12, 51,   # Putamen
        13, 52,   # Pallidum
        17, 53,   # Hippocampus
        18, 54,   # Amygdala
        26, 58,   # Accumbens Area
        28, 60    # Ventral Diencephalon (Ventral DC)
    ]

    # Vectorized label assignment
    combined_mask[np.isin(data, cortical_gm_ids)] = 1
    combined_mask[np.isin(data, wm_ids)] = 2
    combined_mask[np.isin(data, deep_gm_ids)] = 3

    # Save to disk if output path is provided
    if output_path:
        out_img = nib.Nifti1Image(combined_mask, img.affine, img.header)
        nib.save(out_img, output_path)

    return combined_mask, img.affine

def run_noddi(datadir, dataname, outpath, nthreads=8):
    
    #files
    bvalpath = os.path.join(datadir, dataname+'.bval')
    bvecpath = os.path.join(datadir, dataname+'.bvec')
    datapath = os.path.join(datadir, dataname+'.nii')
    maskpath = os.path.join(datadir, dataname+'_brainmask.nii')
    
    amico.setup()
    ae = amico.Evaluation(output_path = outpath)
    
    ae.set_config('nthreads', nthreads)
    ae.set_config('BLAS_nthreads', nthreads)
    ae.set_config('doComputeRMSE', True)
    ae.set_config('doComputeNRMSE', True)
    
    amico.util.fsl2scheme(bvalpath, bvecpath)
    schemepath = os.path.join(datadir, dataname+'.scheme')
    
    ae.load_data(datapath, schemepath, mask_filename=maskpath, b0_thr=0)
    
    ae.set_model('NODDI')
    ae.generate_kernels(regenerate=True)
    
    ae.load_kernels()
    
    ae.fit()
    
    ae.save_results()

# %%

sub = 'sub-01'
sessions = ['sess-MGDB01',
            'sess-MGDB02',
            'sess-MGDB03',
            'sess-STAN01',
            'sess-STAN02',
            'sess-STAN03']

# sessions = ['sess-BERK01']



# sessions = ['sess-STAN03']

bvals = [0, 1000, 2500]

acq = 'ep2d'
pe = 'PA'
part = 'mag'

DATADIR = '/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/01_data/'

# %% DTI and FW-DTI

seg_masks = {}
seg_masks_pooled = {}

for sess in sessions:
    
    print('>  loading data')
    fpath = os.path.join(DATADIR, sub, sess, 'proc', 
                         f'{sub}_acq-{acq}_preprocessed_DWI')
    
    seg_masks[sess] =  nib.load(f"{fpath}_seg.nii")
    seg_masks_pooled[sess], _ = combine_aparc_aseg(input_path=f"{fpath}_seg.nii") # 1 cGM, 2 WM, 3 dGM
    tissues = {'cGM': 1,
               'WM': 2,
               'dGM': 3}
    
    b0avg = []
    
    dwi = nib.load(f'{fpath}.nii')
    gtab = gradient_table(bvals=f'{fpath}.bval',
                          bvecs=f'{fpath}.bvec')
    
    print ('>  Voxelwise DTI')
    mask = nib.load(f'{fpath}_brainmask.nii')
    bvals_vox = nib.load(f'{fpath}_voxelwise-bval.nii')
    bvecs_vox = nib.load(f'{fpath}_voxelwise-bvec.nii')
    
    # Pass dataobj directly (Zero memory allocated here)
    gtab_vox = VoxelwiseGradientTable(bvals_vox.dataobj, bvecs_vox.dataobj)
    
    # Slice-by-slice voxelwise fitting
    # model = 'DTI'
    # metrics_vox = fit_voxelwise(dwi.dataobj, mask.dataobj, gtab_vox, model=model, slices=slices, n_jobs=-1)
    
    # fit DTI
    model_dti = 'DTI'
    metrics_vox = fit_voxelwise(dwi.dataobj, mask.dataobj, gtab_vox, model=model_dti, n_jobs=8)
    
    # fit FW-DTI
    model_fwdti = 'FW-DTI'
    metrics_vox = fit_voxelwise(dwi.dataobj, mask.dataobj, gtab_vox, model=model_fwdti, n_jobs=8)
    
    # fit standard DTI via dipy
    # metrics_std =     (dwi, mask, fbval, fbvec)
    
    # save metrics
    DTIDIR = os.path.join(DATADIR, sub, sess, 'proc', 'dti')
    FWDTIDIR = os.path.join(DATADIR, sub, sess, 'proc', 'fwdti')
    os.makedirs(DTIDIR, exist_ok=True)
    os.makedirs(FWDTIDIR, exist_ok=True)
    
    save_metrics(metrics_vox, output_dir=DTIDIR, reference_img=mask, prefix=f"{model_dti}_vox_")
    save_metrics(metrics_vox, output_dir=FWDTIDIR, reference_img=mask, prefix=f"{model_fwdti}_vox_")
    # save_metrics(metrics_std, output_dir=os.getcwd(), reference_img=mask, prefix=f"test_{model}_std_")


# %% NODDI - using standard .bval and .bvec

for sess in sessions:
    
    fdir = os.path.join(DATADIR, sub, sess, 'proc')
    fname = f'{sub}_acq-{acq}_preprocessed_DWI'
    outpath = os.path.join(fdir, 'noddi')
    
    run_noddi(fdir, fname, outpath)
    

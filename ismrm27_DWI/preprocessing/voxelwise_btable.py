#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jun 30 16:23:43 2026

This code was build upon the available code from mpaquette and 
tetsuyacht available here:
https://gist.github.com/mpaquette/5dda379e9e3e37e6a12b8776876c1e96
https://gist.github.com/tetsuyacht/6a4b59d9daccb4f62efa77f29be3c1f0/revisions
https://gist.github.com/tetsuyacht/6a4b59d9daccb4f62efa77f29be3c1f0

@author: Daniel Uher
"""

import numpy as np
import nibabel as nib
from dipy.core.gradients import gradient_table
from tqdm import tqdm
import argparse
import os

DESCRIPTION = """
Compute bvecs and bvals at each voxel according to gradient percent deviation map.
"""

def buildArgsParser():
    
    # setup arguments according to the muster established by the
    # references
    p = argparse.ArgumentParser(description=DESCRIPTION)

    p.add_argument('devX', action='store', type=str,
                            help='Path of X gradient deviation file')

    p.add_argument('devY', action='store', type=str,
                            help='Path of Y gradient deviation file')

    p.add_argument('devZ', action='store', type=str,
                            help='Path of Z gradient deviation file')
    
    p.add_argument('--bvecs', dest='bvecs', action='store', type=str,
                            help='/path/to/file.bvec')

    p.add_argument('--bvals', dest='bvals', action='store', type=str,
                            help='/path/to/file.bval')

    p.add_argument('--out', dest='out', action='store', type=str,
                            help='/path/to/output_dir/outname without extensions')
    
    p.add_argument('--saveqc', dest='saveqc', action='store_true',
                            help='/path/to/output/ directory')

    p.add_argument('--mask', dest='mask', action='store', type=str,
                            help='Path of the mask file. If none given, computes on the full volume.')

    return p

def save_nifti_file(img, affine, out_path, dtype=np.float32):
    img = np.asarray(img, dtype=dtype)
    nii_im = nib.Nifti1Image(img, affine)
    nii_im.header.set_data_dtype(dtype)
    nib.save(nii_im, out_path)

def main():
    
    # parse inpout
    parser = buildArgsParser()
    args = parser.parse_args()
    
    # load mask and keep its affine
    # otherwise take the affine of one of the dev files
    if os.path.isfile(args.mask):
        maskhdr = nib.load(args.mask)
        mask = maskhdr.get_fdata()>0
        affine = maskhdr.affine
    else:
        affine = nib.load(args.devX).affine
    
    # load the percentual deviations and make them not percentages
    devX = nib.load(args.devX).get_fdata()*0.01
    devY = nib.load(args.devY).get_fdata()*0.01
    devZ = nib.load(args.devZ).get_fdata()*0.01
    
    # load gradient info
    gtab = gradient_table(bvecs=args.bvecs,                       
                          bvals=args.bvals)

    # get the shapes
    nx, ny, nz = mask.shape
    nv = len(gtab.bvals)
    
    # deviation tensors mapped to all positions
    L = np.concatenate((devX[...,None], devY[...,None], devZ[...,None]), axis=4)
    
    # calculate the q-vectors as q = sqrt(b) * g
    q = (gtab.bvecs * np.sqrt(gtab.bvals)[:,None] )
    
    q_eff = np.zeros((nx,ny,nz,nv,3))
    # for each spatial position
    for idx in tqdm(np.ndindex((nx,ny,nz))):
        # distort bvec according to the L tensor at that position
        # note we are calculating q^T = q^T @ L
        q_eff[*idx,:,:] = q.dot(L[*idx,:,:])
        # TODO this might be sped up by einstein sum np.einsum('vi,xyzij->xyzvj', q, L)
        # but needs to be tested first
        
    # caclulate the norm of the q-vectors
    q_mag = np.linalg.norm(q_eff, axis=4)
    
    # normalize the corrected q-vectors (ignore div by 0 warnings)
    with np.errstate(divide='ignore', invalid='ignore'):
        voxelwise_g = q_eff / q_mag[...,None]
    
    # nan removal (from the b division at b0)
    voxelwise_g[...,gtab.bvals==0,:] = 0
    
    # corrected b-values are the ||q_eff||^2
    # this is equivalent to np.trace(B) where B = b * g_eff @ g_eff.T
    voxelwise_b = q_mag ** 2
    
    # save
    save_nifti_file(voxelwise_b, affine, args.out+'_voxelwise-bval.nii')
    print(f"Voxelwise corrected b-values map saved as: {args.out+'_voxelwise-bval.nii'}")
    
    save_nifti_file(voxelwise_g, affine, args.out+'_voxelwise-bvec.nii')
    print(f"Voxelwise corrected b-vectors map saved as: {args.out+'_voxelwise-bval.nii'}")

    if args.saveqc:
        print('QC: calcuating the b-value deviations (percent) ... ')
        # == b-value percent deviation map =============================
        b_nom = gtab.bvals[None, None, None, :] # (1,1,1,nv)
        
        # get the percentages and suppress division by zero warnings
        with np.errstate(divide='ignore', invalid='ignore'):
            db_perc = 100 * (voxelwise_b - b_nom) / b_nom
            
        # null np.nans
        db_perc[..., gtab.bvals == 0] = 0 
        
        # save
        save_nifti_file(db_perc, affine, args.out + '_qc-perc-dev-bval.nii')

        print('QC: calcuating the b-vector deviations (degrees) ... ')
        # == b-vector angular deviation map (in degrees) ===============
        g_nom = gtab.bvecs[None, None, None, :, :]  # (1,1,1,nv,3)
        
        # calculate the dot product between the og and corrected
        dotprod = np.sum(voxelwise_g * g_nom, axis=-1)
        dotprod = np.clip(np.abs(dotprod), -1.0, 1.0)  # abs due to antipodal symmetry, so that 
        
        # get the angle
        angle_dev = np.degrees(np.arccos(dotprod))
        
        # null bval=0 voxels
        angle_dev[..., gtab.bvals == 0] = 0
        
        # save
        save_nifti_file(angle_dev, affine, args.out + '_qc-angle-dev-bvec.nii')
        print('QC saved as: ')
        print(f"QC-bvals: {args.out + '_qc-perc-dev-bval.nii'}")
        print(f"QC-bvecs: {args.out + '_qc-angle-dev-bvec.nii'}")

if __name__ == '__main__':
    main()









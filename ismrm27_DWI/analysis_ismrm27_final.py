#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Created on Oct 08 2026 12:33

Author: Daniel Uher
E-mail: daniel dot uher at ovgu dot de
"""

from itertools import combinations, product
import os
from dipy.core.gradients import gradient_table
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
import pandas as pd
import seaborn as snb
import statsmodels.formula.api as smf
from scipy.stats import pearsonr


# =============================================================================
# Helper functions
# =============================================================================

def combine_aparc_aseg(input_path: str, output_path: str = None,
                       combine_hemispheres: bool = False,) -> tuple[np.ndarray, np.ndarray]:
    
    """Combine freesurfer's aparc+aseg segmentation into 3 tissue classes.

    Output Label Mapping:
      0 = Other
      1 = Gray Matter
      2 = White Matter
    """
    
    # setup FS labels
    wm_ids = {
        'Left': [2, 7],  # Cerebral WM, Cerebellar WM
        'Right': [41, 46],
    }
    
    gm_ids = {
        'Left': [10, 11, 12, 13, 17, 18, 26, 28] + list(range(1000, 1036)),
        'Right': [49, 50, 51, 52, 53, 54, 58, 60] + list(range(2000, 2036)),
    }
    
    # load the file
    img = nib.load(input_path)
    data = img.get_fdata().astype(int)
    
    # combine left and right or leave separate
    if combine_hemispheres:
        combined_mask = np.zeros_like(data, dtype=np.uint8)
        combined_mask[np.isin(data, gm_ids['Left'] + gm_ids['Right'])] = 1
        combined_mask[np.isin(data, wm_ids['Left'] + wm_ids['Right'])] = 2
    
        # optionally save to .nii
        if output_path:
          out_img = nib.Nifti1Image(combined_mask, img.affine, img.header)
          nib.save(out_img, output_path + '.nii')
    
    else:
        combined_mask = {
            'Left': np.zeros_like(data, dtype=np.uint8),
            'Right': np.zeros_like(data, dtype=np.uint8),
        }
    
        # separate per hemisphere
        for hemi in ['Left', 'Right']:
            combined_mask[hemi][np.isin(data, gm_ids[hemi])] = 1
            combined_mask[hemi][np.isin(data, wm_ids[hemi])] = 2
            
            # optionally save to .nii and mark with hemi
            if output_path:
              out_img = nib.Nifti1Image(combined_mask, img.affine, img.header)
              nib.save(out_img, output_path + f'_{hemi}.nii')
    
    return combined_mask, img.affine


def calculate_dwi_snr(dwi_data: np.ndarray, mask: np.ndarray,
                      bvals: np.ndarray, eval_bval: int = 1000,
                      b0_bval: int = 0, bval_tol: int = 10,) -> tuple[float, float]:
    
    """Calculates SNR for a target powder-averaged shell 
    using noise derived from repeated b=0 images.
    
    Return
    SNR (float) ...   SNR value for the specified shell
    sigma (float) ... Noise estimate
    """
    
    # load bvals and mask
    bvals = np.asarray(bvals)
    mask = mask.astype(bool)
    
    # find positions of the b=0 images
    b0_indices = np.where(np.abs(bvals - b0_bval) <= bval_tol)[0]
    
    # check if there is enough of them
    if len(b0_indices) < 2:
      raise ValueError(f" At least two b={b0_bval} volumes are required to estimate noise variance." )
    
    # separate b=0 volumes
    b0_vols = dwi_data[..., b0_indices]
    
    # calculate variances based on all combinations of available b=0 images
    variances = [
        np.var(b0_vols[..., i][mask] - b0_vols[..., j][mask], ddof=1)
        for i, j in combinations(range(len(b0_indices)), 2)
    ]
    
    # get the noise while accounting for the difference between N images by sqrt(N)
    sigma_noise = np.sqrt(np.mean(variances)) / np.sqrt(2)
    
    # find the target b-value volumes
    target_indices = np.where(np.abs(bvals - eval_bval) <= bval_tol)[0]
    
    # check if they exist
    if len(target_indices) == 0:
        raise ValueError(f"No volumes found matching b={eval_bval}")
    
    # get mean signal and calculate SNR
    target_signal = np.mean(dwi_data[..., target_indices][mask])
    snr = target_signal / sigma_noise
    
    return float(snr), float(sigma_noise)


def calc_pair_cv(v1: float, v2: float) -> float:
    """
    Calculates the coefficient of variation given two arrays in %
    """
    
    # get mean
    mean_val = (v1 + v2) / 2.0
    
    # prevent devision by 0
    if mean_val == 0:
        return 0.0
    
    # standard deviation
    std_val = np.std([v1, v2], ddof=1)
    
    # return CV
    return (std_val / mean_val) * 100.0



# %%

# =============================================================================
# Key Variables Setup
# =============================================================================

# subject ID remains static (N=1 study)
sub = 'sub-01'

# list of available sessions
sessions = [
    'sess-MGDB01',
    'sess-MGDB02',
    'sess-MGDB03',
    'sess-STAN01',
    'sess-STAN02',
    'sess-STAN03',
]


bvals = [0, 1000, 2500] # list of acquired b-values
acq = 'ep2d' # acquisition type
pe = 'PA' # phase encoding direction
part = 'mag' # which part of the image are we working with

# key directories
# TODO: make them into argparse inputs
RESDIR = '/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/02_scripts/analysis/final_test'
DATADIR = '/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/01_data/'
ANALYSISDIR = '/home/duher/Nextcloud/SFB1436/SFB_1436_Serviceprojekt_Z02/duher/08_projects/18_TravellingHead2026/02_scripts/analysis'

# which metric are to be included
metric_names = [
    'fwdti/FW-DTI_vox_fa',
    'noddi/fit_NDI',
    'noddi/fit_ODI',
    'tracts/sub-01_acq-ep2d_preprocessed_tracks-1M_TDI',
]

# metric labels for clean figure titles
metric_labels = ['FW-corrected FA',  
                 'NDI', 
                 'ODI', 
                 'TDI']

# analyzed tissue types
tissues = {'GM': 1, 'WM': 2}

bval_list = [0, 1000, 2500]

# Dictionary to store SNR: snr_data[hemi][tissue_type][bval][sess]
snr_data = {
    'Left': {t: {b: {} for b in bval_list} for t in tissues},
    'Right': {t: {b: {} for b in bval_list} for t in tissues},
}

# hemisphere names
hemis = ['Left', 'Right']

# whether to save figures or not and with what dpi
save_figs = True
dpi = 300


# %%
print('# ====================================================================')
print('# SECTION 1: Data Loading + SNR & Asymmetry Calculation')
print('# ====================================================================')
print('')

metrics_DWIspace = {}
metrics_MNIspace = {}
seg_masks = {}
seg_masks_pooled = {}
powder_averages = {}

# for each sessions
for sess in sessions:
    print(f'> Session: {sess}')
    
    procpath = os.path.join(DATADIR, sub, sess, 'proc')
    fpath = os.path.join(
        DATADIR, sub, sess, 'proc', f'{sub}_acq-{acq}_preprocessed_DWI'
    )
    
    # load segmentation
    seg_masks[sess] = nib.load(f'{fpath}_seg.nii')
    seg_masks_pooled[sess], _ = combine_aparc_aseg(
        input_path=f'{fpath}_seg.nii', combine_hemispheres=False
    )
    
    
    dwi = nib.load(f'{fpath}.nii')
    gtab = gradient_table(bvals=f'{fpath}.bval', bvecs=f'{fpath}.bvec')
    dwi_data = dwi.get_fdata()
    
    # Store powder averages
    powder_averages[sess] = np.stack(
        [np.mean(dwi_data[..., gtab.bvals == b], axis=-1) for b in bvals], axis=-1
    )
    
    # Load metrics of interest in DWI space
    metrics_DWIspace[sess] = [
        nib.load(os.path.join(procpath, m + '.nii.gz')) for m in metric_names
    ]
    
    # Load coregistered metrics of interest in MNI space
    metrics_MNIspace[sess] = [
        nib.load(
            os.path.join(
                procpath,
                'coreg',
                m.split('/')[-1] + '_space-mni.nii.gz',
            )
        )
        for m in metric_names
    ]
    
    for hemi in hemis:
        for tissue_type, label_val in tissues.items():
            mask = 1 * (seg_masks_pooled[sess][hemi] == label_val)
            
              
            # Calculate SNR per shell
            snr_data[hemi][tissue_type][0][sess], _ = calculate_dwi_snr(
                dwi_data, mask, gtab.bvals, eval_bval=0
            )
            snr_data[hemi][tissue_type][1000][sess], _ = calculate_dwi_snr(
                dwi_data, mask, gtab.bvals, eval_bval=1000
            )
            snr_data[hemi][tissue_type][2500][sess], _ = calculate_dwi_snr(
                dwi_data, mask, gtab.bvals, eval_bval=2500
            )


# --- plot SNR and asymmetry Heatmaps ---
f, ax = plt.subplots(nrows=len(tissues.keys()), ncols=3, figsize=(17, 8))

for i, tissue_type in enumerate(tissues.keys()):
    df_left = pd.DataFrame(
        {f'b={b}': snr_data['Left'][tissue_type][b] for b in bval_list}
    )
    df_right = pd.DataFrame(
        {f'b={b}': snr_data['Right'][tissue_type][b] for b in bval_list}
    )
    
    # Calculate Asymmetry Index (%)
    df_asym = 100 * (df_left - df_right) / (df_left + df_right)
    
    # Left SNR
    snb.heatmap(
        df_left,
        annot=True,
        fmt='.2f',
        cmap='viridis',
        vmin=0.0,
        vmax=42.0,
        linewidths=0.5,
        cbar_kws={'label': 'SNR'},
        ax=ax[i, 0],
    )
    ax[i, 0].set_title(f'SNR - {tissue_type} - Left')
    
    # Right SNR
    snb.heatmap(
        df_right,
        annot=True,
        fmt='.2f',
        cmap='viridis',
        vmin=0.0,
        vmax=42.0,
        linewidths=0.5,
        cbar_kws={'label': 'SNR'},
        ax=ax[i, 1],
    )
    ax[i, 1].set_title(f'SNR - {tissue_type} - Right')
    
    # Left-Right Asymmetry
    snb.heatmap(
        df_asym,
        annot=True,
        fmt='.2f',
        cmap='coolwarm',
        vmin=-10.0,
        vmax=10.0,
        linewidths=0.5,
        cbar_kws={'label': 'Asymmetry Index (L-R)/(L+R) [%]'},
        ax=ax[i, 2],
    )
    ax[i, 2].set_title(f'L-R Asymmetry - {tissue_type}')

plt.tight_layout()
plt.show()

if save_figs:
    f.savefig(os.path.join(RESDIR, 'SNR_preprocessed_data.png'), dpi=dpi)

# %%
print('# ====================================================================')
print('# SECTION 2: Raw Data SNR & Asymmetry Calculation')
print('# ====================================================================')
print('')

snr_data_raw = {
    'Left': {t: {b: {} for b in bval_list} for t in tissues},
    'Right': {t: {b: {} for b in bval_list} for t in tissues},
}

for sess in sessions:
    print(f'> Session (Raw PA): {sess}')
    acq_sess = 'cmrr-mbep2d' if sess == 'sess-BERK01' else 'ep2d'
    dwidir = os.path.join(DATADIR, sub, sess, 'dwi')
    
    raw_dwi_vols = []
    raw_bvals_list = []
    
    # Load raw PA files (combining b1k and b2p5k acquisitions)
    for desc in ['desc-b1k', 'desc-b2p5k']:
        base_fname = f'{sub}_{sess}_acq-{acq_sess}_dir-PA_part-mag_{desc}'
        nii_path = os.path.join(dwidir, f'{base_fname}.nii')
        bval_path = os.path.join(dwidir, f'{base_fname}.bval')
      
        if os.path.exists(nii_path) and os.path.exists(bval_path):
          raw_dwi_vols.append(nib.load(nii_path).get_fdata())
          raw_bvals_list.append(np.loadtxt(bval_path))
    
    if not raw_dwi_vols:
        print(f'  [Warning] No raw PA files found for {sess} in {dwidir}')
        continue
    
    # Concatenate raw DWI volumes and b-values along the 4th dimension
    dwi_data_raw = np.concatenate(raw_dwi_vols, axis=-1)
    bvals_raw = np.concatenate(raw_bvals_list, axis=0)
    
    for hemi in hemis:
        for tissue_type, label_val in tissues.items():
            mask = 1 * (seg_masks_pooled[sess][hemi] == label_val)
        
            # Calculate SNR per shell on raw data
            snr_data_raw[hemi][tissue_type][0][sess], _ = calculate_dwi_snr(
                dwi_data_raw, mask, bvals_raw, eval_bval=0
            )
            snr_data_raw[hemi][tissue_type][1000][sess], _ = calculate_dwi_snr(
                dwi_data_raw, mask, bvals_raw, eval_bval=1000
            )
            snr_data_raw[hemi][tissue_type][2500][sess], _ = calculate_dwi_snr(
                dwi_data_raw, mask, bvals_raw, eval_bval=2500
            )

# --- Plot Raw Data SNR & Asymmetry Heatmaps ---
f_raw, ax_raw = plt.subplots(nrows=len(tissues.keys()), ncols=3, figsize=(17, 6))

for i, tissue_type in enumerate(tissues.keys()):
  df_left_raw = pd.DataFrame(
      {f'b={b}': snr_data_raw['Left'][tissue_type][b] for b in bval_list}
  )
  df_right_raw = pd.DataFrame(
      {f'b={b}': snr_data_raw['Right'][tissue_type][b] for b in bval_list}
  )

  # Calculate Asymmetry Index (%)
  df_asym_raw = (
      100 * (df_left_raw - df_right_raw) / (df_left_raw + df_right_raw)
  )

  # Raw Left SNR
  snb.heatmap(
      df_left_raw,
      annot=True,
      fmt='.2f',
      cmap='viridis',
      vmin=0.0,
      vmax=42.0,
      linewidths=0.5,
      cbar_kws={'label': 'SNR'},
      ax=ax_raw[i, 0],
  )
  ax_raw[i, 0].set_title(f'Raw SNR - {tissue_type} - Left (dir-PA)')

  # Raw Right SNR
  snb.heatmap(
      df_right_raw,
      annot=True,
      fmt='.2f',
      cmap='viridis',
      vmin=0.0,
      vmax=42.0,
      linewidths=0.5,
      cbar_kws={'label': 'SNR'},
      ax=ax_raw[i, 1],
  )
  ax_raw[i, 1].set_title(f'Raw SNR - {tissue_type} - Right (dir-PA)')

  # Raw Left-Right Asymmetry
  snb.heatmap(
      df_asym_raw,
      annot=True,
      fmt='.2f',
      cmap='coolwarm',
      vmin=-10.0,
      vmax=10.0,
      linewidths=0.5,
      cbar_kws={'label': 'Asymmetry Index (L-R)/(L+R) [%]'},
      ax=ax_raw[i, 2],
  )
  ax_raw[i, 2].set_title(f'Raw L-R Asymmetry - {tissue_type} (dir-PA)')

plt.tight_layout()
plt.show()

if save_figs:
    f_raw.savefig(os.path.join(RESDIR, 'SNR_acquired_data.png'), dpi=dpi)

# %%
print('# ====================================================================')
print('# SECTION 3A: Powder Average Overview - Preprocessed data')
print('# ====================================================================')

f_pa, ax_pa = plt.subplots(
    nrows=3, ncols=6, layout='compressed', facecolor='black', figsize=(18, 10)
)

slc = 50

for col_id, sess in enumerate(sessions):
    for bval_ind, vmax in enumerate([1300, 500, 200]):
        ax_curr = ax_pa[bval_ind, col_id]
        
        im = ax_curr.imshow(
            powder_averages[sess][..., slc, bval_ind].T,
            cmap='grey',
            origin='lower',
            vmin=0,
            vmax=vmax,
        )
        
        ax_curr.axis('off')
        
        if bval_ind == 0:
            ax_curr.set_title(f'{sess}', color='lightgrey', fontsize=18)
        
        if col_id == 5:
            cbar = f_pa.colorbar(
                im, ax=ax_curr, location='right', shrink=0.85, pad=0.01
            )
            cbar.ax.yaxis.set_tick_params(color='lightgrey')
            plt.setp(cbar.ax.get_yticklabels(), color='lightgrey', fontsize=12)
            cbar.outline.set_edgecolor('black')

plt.show()
if save_figs:
    f_pa.savefig(os.path.join(RESDIR, 'overview_preprocessed_data.png'), dpi=dpi)

# %%

print('# ====================================================================')
print('# SECTION 3B: Powder Average Overview - Raw Data')
print('# ====================================================================')
print('')

powder_averages_raw = {}

# Compute raw powder averages per b-value shell (0, 1000, 2500)
for sess in sessions:
    dwidir = os.path.join(DATADIR, sub, sess, 'dwi')
    
    raw_dwi_vols = []
    raw_bvals_list = []
    
    # Load raw dir-PA series
    for desc in ['desc-b1k', 'desc-b2p5k']:
        base_fname = f'{sub}_{sess}_acq-{acq}_dir-PA_part-mag_{desc}'
        nii_path = os.path.join(dwidir, f'{base_fname}.nii')
        bval_path = os.path.join(dwidir, f'{base_fname}.bval')
      
        if os.path.exists(nii_path) and os.path.exists(bval_path):
            raw_dwi_vols.append(nib.load(nii_path).get_fdata())
            raw_bvals_list.append(np.loadtxt(bval_path))
    
    if not raw_dwi_vols:
        print(f'  [Warning] No raw PA files found for {sess}')
        continue
    
    dwi_data_raw = np.concatenate(raw_dwi_vols, axis=-1)
    bvals_raw = np.concatenate(raw_bvals_list, axis=0)
    
    # Average across target shell volumes
    powder_averages_raw[sess] = np.stack(
        [
            np.mean(dwi_data_raw[..., np.abs(bvals_raw - b) <= 10], axis=-1)
            for b in bvals
        ],
        axis=-1,
    )

# --- Render Raw Powder Average Grid ---
f_pa_raw, ax_pa_raw = plt.subplots(
    nrows=3, ncols=6, layout='compressed', facecolor='black', figsize=(18, 10)
)

slc = 50  # Slice index to display

for col_id, sess in enumerate(sessions):
    if sess not in powder_averages_raw:
      continue
    
    for bval_ind, vmax in enumerate([1300, 500, 200]):
        ax_curr = ax_pa_raw[bval_ind, col_id]
    
        im = ax_curr.imshow(
            powder_averages_raw[sess][..., slc, bval_ind].T,
            cmap='grey',
            origin='lower',
            vmin=0,
            vmax=vmax)
    
        ax_curr.axis('off')
    
        if bval_ind == 0:
            ax_curr.set_title(f"{sess.split('-')[-1]}", color='lightgrey', fontsize=18)
      
        # Style row colorbars on the rightmost column
        if col_id == 5:
            cbar = f_pa_raw.colorbar(im, ax=ax_curr, location='right', shrink=0.85, pad=0.01)
            cbar.ax.yaxis.set_tick_params(color='lightgrey')
            plt.setp(cbar.ax.get_yticklabels(), color='lightgrey', fontsize=12)
            cbar.outline.set_edgecolor('black')

plt.show()
if save_figs:
    f_pa_raw.savefig(os.path.join(RESDIR, 'overview_acquired_data.png'), dpi=dpi)

# %%

print('# ====================================================================')
print('# SECTION 4: Coefficient of Variation Analysis - DWI space')
print('# ====================================================================')

all_metric_records = []
tissue_selected = 'WM'

for m_idx, metric_label in enumerate(metric_labels):
    for sess in sessions:
        site = 'MGDB' if 'MGDB' in sess else 'STAN'
        metric_data = metrics_DWIspace[sess][m_idx].get_fdata()
    
        for hemi in hemis:
            wm_mask = seg_masks_pooled[sess][hemi] == tissues[tissue_selected]
            mean_val = np.mean(metric_data[wm_mask])
        
            all_metric_records.append({
                'metric': metric_label,
                'session': sess,
                'site': site,
                'hemisphere': hemi,
                'mean_val': mean_val,
            })

df_all_metrics = pd.DataFrame(all_metric_records)
cv_plot_records = []

for metric_label in metric_labels:
    for hemi in hemis:
        df_sub = df_all_metrics[
            (df_all_metrics['metric'] == metric_label)
            & (df_all_metrics['hemisphere'] == hemi)
        ]
      
        mgdb_vals = df_sub[df_sub['site'] == 'MGDB']['mean_val'].values
        stan_vals = df_sub[df_sub['site'] == 'STAN']['mean_val'].values
      
        # Intra-site MGDB: Pairwise permutations over 3 sessions (3 pairs: C(3,2))
        for v1, v2 in combinations(mgdb_vals, 2):
            mgdb_cv = calc_pair_cv(v1, v2)
            cv_plot_records.append({
                'metric': metric_label,
                'hemisphere': hemi,
                'Comparison': 'MGDB (Intra-site)',
                'CV_percent': mgdb_cv,
                'is_distribution': True,
            })
      
        # Intra-site STAN: Pairwise permutations over 3 sessions (3 pairs: C(3,2))
        for v1, v2 in combinations(stan_vals, 2):
            stan_cv = calc_pair_cv(v1, v2)
            cv_plot_records.append({
                'metric': metric_label,
                'hemisphere': hemi,
                'Comparison': 'STAN (Intra-site)',
                'CV_percent': stan_cv,
                'is_distribution': True,
            })
      
        # Inter-site: All 3 x 3 = 9 pairwise session combinations
        for v_mgdb, v_stan in product(mgdb_vals, stan_vals):
            inter_cv = calc_pair_cv(v_mgdb, v_stan)
            cv_plot_records.append({
                'metric': metric_label,
                'hemisphere': hemi,
                'Comparison': 'Inter-site (Pairwise Permutations)',
                'CV_percent': inter_cv,
                'is_distribution': True,
            })

df_cv_summary = pd.DataFrame(cv_plot_records)

# Visualization
fig_cv, axes_cv = plt.subplots(
    1, len(metric_labels), figsize=(18, 6), sharey=False
)

if len(metric_labels) == 1:
    axes_cv = [axes_cv]

for m_idx, metric_label in enumerate(metric_labels):
    ax_curr = axes_cv[m_idx]
    df_plot = df_cv_summary[df_cv_summary['metric'] == metric_label]
    
    # Bar plot showing Intra-site CVs (single values) and Inter-site Mean CV (with SD errorbar across 9 pairs)
    barplot = snb.barplot(
        data=df_plot,
        x='hemisphere',
        y='CV_percent',
        hue='Comparison',
        palette='Set2',
        errorbar='sd',
        capsize=0.08,
        alpha=0.75,
        ax=ax_curr,)

    ax_curr.set_title(f'{metric_label}', fontsize=11, fontweight='bold')
    ax_curr.spines[['top', 'right']].set_visible(False)
    ax_curr.grid(axis='y', linestyle='dashed', color='lightgrey')
    ax_curr.set_axisbelow(True)
    ax_curr.set_ylim([0.0,6.0])
    
    # Annotate bar top values
    for p in barplot.patches:
      h = p.get_height()
      if not np.isnan(h) and h > 0:
        ax_curr.annotate(
            f'{h:.2f}%',
            (p.get_x() + p.get_width() / 2.0, h),
            ha='center',
            va='bottom',
            fontsize=8,
            xytext=(0, 2),
            textcoords='offset points')
    
    if m_idx == 0:
        ax_curr.set_ylabel('White matter CV (%)', fontsize=10)
    else:
        ax_curr.set_ylabel('')
        ax_curr.spines[['left']].set_visible(False)
        ax_curr.set_yticklabels([])
    
    if m_idx != len(metric_labels) - 1:
        ax_curr.get_legend().remove()
    else:
        ax_curr.legend(
            title='Comparison', bbox_to_anchor=(1.05, 1), loc='upper left'
        )
      
    ax_curr.set_xlabel('Hemisphere')

plt.tight_layout()
plt.show()

if save_figs:
    fig_cv.savefig(os.path.join(RESDIR, f'CV_analysis_{tissue_selected}.png'), dpi=dpi)

# %%

print('# ====================================================================')
print('# SECTION 5: Cross-Correlation Analysis across All Metrics - MNI Space (WM Mask)')
print('# ====================================================================')

# Load MNI segmentation map
mni_seg = nib.load(os.path.join(ANALYSISDIR, 'MNI152_T1_1mm_brain_seg.nii')).get_fdata()

# TODO: tie this to the established dictionary
wm_ids = [2, 7, 41, 46]
wm_mask_mni = np.isin(mni_seg, wm_ids)

# setup colorbar limits
vmin = 0.8
vmax = 1.0
cmap = 'cividis'

# fig_corr, axes_corr = plt.subplots(
#     1, len(metric_labels), figsize=(6 * len(metric_labels), 6)
# )

figsize_horizontal = 35
nrows = 1
ncols = 5
ratio = nrows / ncols
fig_corr, axes = plt.subplots(nrows=1,
                         ncols=5,
                         figsize=(figsize_horizontal, figsize_horizontal * ratio),
                         gridspec_kw={"width_ratios": [1, 1, 1, 1, 0.05], "wspace": 0.08},
                         )

axes_corr = axes[:4]  # first 4 axes for the heatmaps
cbar_ax = axes[4]  # last axis for the shared colorbar

for m_idx, metric_label in enumerate(metric_labels):
    ax_curr = axes_corr[m_idx]
    
    # Stack 3D MNI volumes for all 6 sessions: shape (X, Y, Z, 6)
    mni_stack = np.stack(
        [metrics_MNIspace[s][m_idx].get_fdata() for s in sessions], axis=-1
    )
    
    # Include all voxels within the MNI White Matter mask (excluding NaNs/Infs if present)
    valid_wm_voxels = wm_mask_mni & np.all(np.isfinite(mni_stack), axis=-1)
    
    # Reshape voxel data to 2D matrix: shape (N_wm_voxels, 6)
    voxel_matrix = mni_stack[valid_wm_voxels]
    
    # setup session names for visualization
    session_names = [x.split('-')[-1] for x in sessions]
    
    # Compute 6x6 Pearson Correlation Matrix across all sessions
    corr_matrix = np.corrcoef(voxel_matrix, rowvar=False)
    df_corr = pd.DataFrame(corr_matrix, index=session_names, columns=session_names)
    
    # Label visual adjustments
    show_yticks = m_idx not in [1, 2, 3]
    
    ax_curr = snb.heatmap(
        df_corr,
        annot=True,
        annot_kws={"fontsize": 15},
        fmt=".3f",
        cmap=cmap,
        square=True,
        ax=ax_curr,
        cbar=False,
        cbar_kws={"label": "Pearson Correlation ($r$)"},
        yticklabels=show_yticks,
        vmin=vmin,
        vmax=vmax,
    )
    
    ax_curr.set_title(f'{metric_label}', fontsize=17, fontweight='bold')
    ax_curr.tick_params(axis='x', rotation=90, labelsize=15)
    ax_curr.tick_params(axis='y', rotation=0, labelsize=15)
    
    if m_idx == len(metric_labels) - 1:
        last_heatmap = ax_curr.collections[0]
    
cbar = fig_corr.colorbar(last_heatmap, cax=cbar_ax)
cbar.set_label("Pearson Correlation ($r$)", fontsize=15)
cbar.ax.tick_params(labelsize=15)

plt.subplots_adjust(wspace=0.08, right=0.92)
plt.tight_layout()
plt.show()

if save_figs:
    fig_corr.savefig(os.path.join(RESDIR, 'CrossCorr_analysis_WM_300dpi.png'), dpi=300, bbox_inches="tight")
    fig_corr.savefig(os.path.join(RESDIR, 'CrossCorr_analysis_WM_100dpi.png'), dpi=100, bbox_inches="tight")

# %%

print('# ====================================================================')
print('# SECTION 6: B1+ analysis')
print('# ====================================================================')



tissue_selected = 'WM'

# Dictionary to store extracted B1+ values per session
b1_data = {}

for sess in sessions:
    procpath = os.path.join(DATADIR, sub, sess, 'proc')
    b1_path = os.path.join(procpath, 'coreg', 'B1Comb_space-dwi.nii')
    
    if os.path.exists(b1_path):
        b1_data[sess] = nib.load(b1_path).get_fdata()
    else:
        print(f'  [Warning] B1 map not found at: {b1_path}')

# Compile metric means and corresponding B1+ values in White Matter for both hemispheres
b1_analysis_records = []

for m_idx, metric_label in enumerate(metric_labels):
    for sess in sessions:
        if sess not in b1_data:
          continue
        
        site = 'MGDB' if 'MGDB' in sess else 'STAN'
        metric_img = metrics_DWIspace[sess][m_idx].get_fdata()
        b1_img = b1_data[sess]
      
        for hemi in hemis:
            wm_mask = (seg_masks_pooled[sess][hemi] == tissues[tissue_selected]) & np.isfinite(b1_img)
            if not np.any(wm_mask):
                continue
            
            mean_metric = np.mean(metric_img[wm_mask])
            mean_b1 = np.mean(b1_img[wm_mask])
        
            b1_analysis_records.append({
                'metric': metric_label,
                'session': sess,
                'site': site,
                'hemisphere': hemi,
                'metric_val': mean_metric,
                'b1_val': mean_b1,
            })

# dictionary of metric values along with the corresponding B1+ values
df_b1_analysis = pd.DataFrame(b1_analysis_records)

# Check if B1+ is hemisphere dependent
df_b1only_analysis = df_b1_analysis[df_b1_analysis['metric']=='NDI']
model_b1 = smf.ols('b1_val ~ C(hemisphere) + C(site)', data=df_b1only_analysis).fit()
print('')
print('------ B1+ ~ Hemisphere + Site -----------------------')
print(f'Hemisphere: p={model_b1.pvalues["C(hemisphere)[T.Right]"]:.3f}')
print(f'Site:       p={model_b1.pvalues["C(site)[T.STAN]"]:.3f}')
print('')

# for each metric
# for metric_label in metric_labels:
#     df_metric = df_b1_analysis[df_b1_analysis['metric'] == metric_label]
    
#     if df_metric.empty:
#         continue
    
#     model_b1_site = smf.ols('metric_val ~ b1_val + C(site)', data=df_metric).fit()
    
#     print(f'\n--- {metric_label} ~ B1 + Site ---')
#     print(model_b1_site.pvalues)


# quick calculation of B1+ asymmetry
b1_asym_records = []

for sess in sessions:
    if sess not in b1_data:
        continue
    
    site = 'MGDB' if 'MGDB' in sess else 'STAN'
    b1_img = b1_data[sess]
    
    # Extract mean B1+ for Left and Right White Matter
    wm_mask_left = (seg_masks_pooled[sess]['Left'] == tissues['WM']) & np.isfinite(b1_img)
    wm_mask_right = (seg_masks_pooled[sess]['Right'] == tissues['WM']) & np.isfinite(b1_img)
    
    if np.any(wm_mask_left) and np.any(wm_mask_right):
        b1_left = np.mean(b1_img[wm_mask_left])
        b1_right = np.mean(b1_img[wm_mask_right])
        
        # Calculate Asymmetry Index (%) using the standard formula: 100 * (L - R) / (L + R)
        asym_idx = 100.0 * (b1_left - b1_right) / (b1_left + b1_right)
        
        b1_asym_records.append({
            'session': sess,
            'site': site,
            'b1_left': b1_left,
            'b1_right': b1_right,
            'b1_asym_percent': asym_idx
        })

df_b1_asym = pd.DataFrame(b1_asym_records)
print(df_b1_asym.to_string(index=False))

print('')
print('Mean B1+ Asymmetry Index (%) per site:')
print(df_b1_asym.groupby('site')['b1_asym_percent'].mean())


# --- Visualization: 1x4 Grid (Combining Left and Right per Metric, N=12) ---
fig_b1, axes_b1 = plt.subplots(
    1, len(metric_labels), 
    figsize=(4.5 * len(metric_labels), 4.2), 
    sharey=False
)

if len(metric_labels) == 1:
    axes_b1 = [axes_b1]

for m_idx, metric_label in enumerate(metric_labels):
    ax_curr = axes_b1[m_idx]
    df_plot = df_b1_analysis[df_b1_analysis['metric'] == metric_label]
    
    if df_plot.empty:
        continue
    
    # Scatter plot: color by site, style (marker) by hemisphere to keep track of both
    snb.scatterplot(
        data=df_plot,
        x='b1_val',
        y='metric_val',
        hue='site',
        style='hemisphere',
        palette='Set2',
        s=75,
        alpha=0.85,
        ax=ax_curr
    )
    
    
    for site in ['MGDB', 'STAN']:
        df_plot_hemi = df_plot[df_plot['site'] == site]

        x_vals = df_plot_hemi['b1_val'].values
        y_vals = df_plot_hemi['metric_val'].values
        
        if len(x_vals) > 1 and np.all(np.isfinite(x_vals)) and np.all(np.isfinite(y_vals)):
            slope, intercept = np.polyfit(x_vals, y_vals, 1)
            x_line = np.linspace(x_vals.min(), x_vals.max(), 100)
            y_line = slope * x_line + intercept
            
            r_val, p_val = pearsonr(x_vals, y_vals)
            
            # print out only significant correlations
            if p_val < 0.05:
                print('')
                print('Significant correlations found between metrics and B1+ per site')
                print('---------------------------------------------------------------')
                print(f'  {site} - {metric_label} - r = {r_val:.2f}   p = {p_val:.3f}')
                print('')
             
                
    ax_curr.set_title(f'{metric_label} ($B_1^+$ Impact)', fontsize=11, fontweight='bold')
    ax_curr.set_xlabel(f'Mean {tissue_selected} $B_1^+$ Value', fontsize=10)
    ax_curr.set_ylabel(f'{metric_label} (WM Mean)', fontsize=10)
    
    ax_curr.spines[['top', 'right']].set_visible(False)
    ax_curr.grid(axis='y', linestyle='dashed', color='lightgrey')
    ax_curr.set_axisbelow(True)
    
    # Clean up legend placement on the final subplot
    if m_idx == len(metric_labels) - 1:
        ax_curr.legend(title='Site / Hemi', bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=8)
    else:
        if ax_curr.get_legend():
            ax_curr.get_legend().remove()

plt.tight_layout()
plt.show()

if save_figs:
    fig_b1.savefig(os.path.join(RESDIR, 'B1plus_impact.png'), dpi=300)



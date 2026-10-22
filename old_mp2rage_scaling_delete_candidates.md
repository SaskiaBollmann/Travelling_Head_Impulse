# Old MP2RAGE scaling deletion candidates

Inventory date: 2026-08-12

## Status checked 2026-10-21

This is a historical inventory, not a current deletion list. A read-only
filesystem metadata check found no retired-name
`figures/cross_session_percent_difference_*.png` plots, and the separate
`mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked_wmmean_scaled` directory
was absent. No analysis outputs were deleted during this check.

The established results directory contains three whole-brain MAPD matrices
and three WM MAPD matrices, modified on August 12. These timestamps alone do
not establish which code version produced them or validate the numeric results.

The separate defaced output directory contains the expected 98 registered
images and 14 per-task provenance TSVs, modified on October 15. This confirms
file presence, not image quality or upload completion.

## Original inventory

Root directory:

`/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked`

These are the products whose contents depended on the former independent
1st–99th percentile scaling. Nothing in the established results directory has
been deleted. The corrected refresh overwrites scaling-dependent products in
place while reusing registrations.

| Filename pattern | Files | Contents | Corrected action |
| --- | ---: | --- | --- |
| `*PERCENT_DIFF.nii.gz` | 147 | Pairwise percent-difference volumes | Overwritten in place |
| `tmp_mapd_*.txt` | 147 | Pairwise MAPD values | Overwritten in place |
| `mapd_matrix_*` | 12 | Whole-brain MAPD matrices, provenance, and heatmaps | Overwritten in place |
| `wm_mapd_matrix_*` | 9 | WM MAPD matrices and heatmaps | Overwritten in place |
| `wm_mapd_voxel_count_*` | 3 | Voxel-count sidecars generated from difference maps | Overwritten in place |
| `figures/cross_session_percent_difference_*.png` | 252 | Figures using the retired filename without the modality | Delete after refreshed plots succeed |
| `figures/cross_session_mp2rage_percent_difference_*.png` | 6 existing | Figures using the current filename | Overwritten; the plot refresh fills all pairs |

The actual post-refresh deletion candidates are therefore the 252 retired-name
plots, totaling 539,197,494 bytes (about 514 MiB). The other audited files are
replaced rather than deleted.

A separate partial directory was created by the cancelled mistaken rerun:

`/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked_wmmean_scaled`

It contains 97 duplicate files totaling 6,092,515,784 bytes. It is not used by
the corrected workflow, but permanent removal requires explicit approval.

The inventory intentionally excludes reusable and scaling-independent files:

- ANTs transforms and warped MP2RAGE images
- brain and white-matter masks
- correlation matrices, pair values, and figures
- RMSE matrices, pair values, and figures
- registration provenance not specific to MAPD

To preview the 252 files that remain deletion candidates after refresh:

```bash
find /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration/mp2rage_0p7iso_patientSpecific_UNI-DEN_ND_masked/figures \
  -maxdepth 1 -type f -name 'cross_session_percent_difference_*.png' -print | sort
```

Delete these only after the WM-mean-scaled run has completed and its outputs
have been checked.

# ISMRM 2027 figures

Open `ismrm_2027_figures.ipynb` from this folder or the repository root. Run the three shared backend cells, then any of the four figure cells. Each figure cell contains its own input selection, plotting and saving. There are no nested configuration dictionaries or figure runners.

The shared cells contain imports and plain paths, generic image/site-plot helpers, and one PNG/JPG saving function. `data_helpers.py` contains the scientific input checks only. Change `DATA_ROOT` and `DERIVATIVES` in the first cell if the local MRI data move.

## Inputs and outputs

Figure display labels use **Stanford 1** (session 02), **Stanford 2** (03), **Berkeley** (04), **Magdeburg 1** (06) and **Magdeburg 2** (07), including axes, panel headings and registration references in both notebooks. Original session IDs remain in data paths and numerical tables. Figure titles omit figure numbers. The final EPI map column is labelled “after recalibration / run 2”; the lower plot shows run 1, run 2 and run 3 with “after recalibration” centred below the group. Dates and preheating details remain in the caption and data records.

The three source CSVs live beside the notebook:

- `ismrm_2027_b0_b1_mp2rage_correlations.csv`
- `ismrm_2027_b0_shim_and_brain_orientation.csv`
- `ismrm_2027_ep2d_summary.csv`

Figures are saved directly in this folder as 300-dpi PNG and high-quality JPG, with captions and provenance JSON. Each figure's filename starts with its number. Saving records source checksums, notebook/helper checksums, plotting choices and software versions. CSV summaries are also saved here. No PDF is produced and no raw MRI file is modified.

## Figure cells

1. **Correlations:** measured directional B0/B1 and MP2RAGE matrices. The reader checks all four complete 7x7 matrices before selecting sessions 02, 03, 04, 06 and 07. Reciprocal values are not averaged.
2. **Animated field maps and static backup:** this single cell always creates `figure_2_b0_b1_shims.gif` and 300-dpi `figure_2_b0_b1_maps.png` / `.jpg`. The GIF alternates absolute maps and signed differences every 2 seconds, cycling reference sessions 02, 03, 04, 06 and 07. It retains acquisition shim plots. The static backup contains only absolute B0/B1 map panels in session 02 space, with no differences, Reference labels, or shim plots. Only the five selected sessions are shown. Transversal world-RAS planes are ±20 mm from each reference brain centroid, with matching saved moving-to-fixed rigid registrations and reference brain masks. Shared absolute scales are ±250 Hz and 0–120% nominal; B1 stored values ×0.1 give percent nominal. Berkeley uses the supplied reconstructed export with consistent numerical/visual scale; its reconstruction sidecar is absent. Inputs are under `derivatives/rigid_b0_b1_maps_2026-10-14/`. The cell checks reference grids and exports captions, provenance, QC CSVs and an animation contact sheet. Shim values remain native acquisition settings: first-order DAC counts and author-confirmed A20/A21/B21/A22/B22 currents in mA; session 03 uses series 15–18 after the PTAB restart.
3. **MP2RAGE and pose:** the main cell always exports `figure_3_mp2rage_pose.gif`, alternating Rigid and SyN registration every 2 seconds (4-second infinite loop), plus static Rigid `figure_3_mp2rage_pose_preview.png` / `.jpg` at 300 dpi. Sessions 02, 03, 04, 06 and 07 share session 02 space and identical transversal/coronal/sagittal planes through its brain-mask centroid. For each session, brain 1st/99th percentile display limits from its Rigid image are reused for SyN, preventing brightness rescaling during alternation; this is distinct from WM metric normalization. Input grids are checked against the reference mask. A registration QC CSV, two-frame contact sheet and caption/provenance are exported. Lower plots retain original native brain-centroid shifts from image-volume centres and PCA fixed-axis xyz rotations, with the existing RAS/LPS choice. They remain unchanged between frames and are not registration transforms.
4. **EPI:** original sessions plus all three Magdeburg runs from 12 October 2026, after Frequalizer recalibration with unchanged protocol settings. Run 1 was unintentional preheating. Maps show representative run 2; numerical points include runs 1–3. Across-run summaries separate the first run from subsequent runs 2–3. The cell reads the relative summary CSV and existing THS export manifest. Mean EPI is independently display-scaled; raw and motion-corrected/detrended tSNR rows share a scale. Map quartiles/counts, source identity, native masks, drop-10 and population-SD contracts must match the CSV. Existing motion correction is reused. Points/whiskers are run medians and within-run voxel quartiles. Across-run summaries are separate, with no across-run IQR for n=1. Processing gains include interpolation, and recalibration/preheating effects cannot be separated. Repeated scans are not independent participants.

Site plots retain shading and connect points within sites only. Pilots 01 and 05 remain excluded. The Add-on stays last and is shown as a separate condition. Figure cells can be rerun independently after the shared cells.

## Figure 2 exports

The main Figure 2 cell includes the animation; there is no separate optional pilot cell. Run the three shared backend cells and then Figure 2 to recreate all outputs. The maps-only backup is saved before GIF encoding and is generated on every run. Ten GIF frames form a 20-second infinite loop: absolute, difference for reference 02, then the same pair for references 03, 04, 06 and 07. B0 differences are moving minus reference in Hz; B1 differences are relative percent, `100*(moving-reference)/reference`, excluding reference values below 10% nominal. Shared difference scales are ±100 Hz and ±50% relative. The physical reference space changes with the selected reference; paired absolute/difference frames share identical planes and overlap masks. The Word builder uses the maps-only PNG backup and its generated caption. Earlier pilot and static exports are retained as history.

## Teaser notebook

`ismrm_2027_teaser.ipynb` always exports `teaser_7t_impulse_traveling_head.gif` and static MP2RAGE-only `.png` / `.jpg` backups. The GIF cycles MP2RAGE → B0 → B1 → mean EPI → raw tSNR in 3-second steps (15-second infinite loop). The header uses the full abstract title, “Reproducibility of High-Performance 7T Neuroimaging Using the Impulse Head-Gradient Coil: A Traveling Head Study”, with no separate subheading. Each frame has one large image per site and a modality-specific bottom colour bar. MP2RAGE uses Rigid session 02 registrations, a common sagittal plane and the existing tighter crop (AP −85 to +96 mm, SI −89 to +73 mm). B0/B1 use Rigid session 02 registrations and transversal planes at +20 mm from its brain centroid, with shared scales ±250 Hz and 0–120% nominal. EPI/tSNR retain native transversal planes and existing validated maps; tSNR uses a shared 0–60 scale and the explicitly labelled Magdeburg October Add-on. Other Magdeburg frames use original session 06. Static backups show only the MP2RAGE frame, preserving the 3:2 aspect ratio and JPG below 1 MB. Animation captions/provenance and a five-frame contact sheet are also exported. Figure 3 titles state that all images are co-registered to Stanford 1 and identify Rigid/SyN registration.

## Validation and history

Run the notebook cells from top to bottom to regenerate the figures. Input checks remain in `data_helpers.py`, including directional matrix validation, LPS/RAS conversion, repeated pose rows, and EPI map/CSV and temporal-contract agreement. The figure notebook has been executed from a clean kernel, and all four PNG figures were visually inspected. The separate teaser notebook also reproduces its PNG/JPG exports. Temporary scripts and the standalone test folder have been removed.

`archive/previous_notebook.ipynb`, `archive/legacy_code/` and `archive/previous_outputs/` preserve the previous implementation and older artifacts, including the abstract drafts. They are not used by the active notebook. The former top-level `notebooks` and `outputs` folders no longer exist.

## Revised abstract and numerical evidence

`2027_ISMRM_THImpulse_revised.docx` updates the latest supplied draft. `revision_status.csv` tracks each completed or pending item. The source draft is unchanged. The existing Word draft predates the completed Figure 2. On regeneration, the document builder uses the new Figure 2 export and its current caption. Full absolute-field analyses, Berkeley reconstruction-side unit metadata, original metric matrices and Thomas Brosnan's email remain separate pending items.

Run `export_abstract_metrics.py` with the scientific notebook Python environment to validate eight included EPI maps and export acquisition inventory, per-run/group tSNR, absolute and percentage changes, partial B1 metrics, correlation summaries and shim/pose data. Sessions 08–10 and pilots are excluded. `abstract_reported_numbers.csv` links reported values to source tables; `metrics_validation.json` records checks and processing contracts. Correlations retain two-decimal plot-transcription precision until original matrices are available.

The primary follow-up comparison is the median of run-level medians for October runs 2–3 against sessions 06–07: raw +37.2%, corrected/detrended +23.0%. Separate comparisons against 06 and 07 and each individual October run are also exported. Processing gain denominators are explicit; gains are ratios of medians, not voxelwise ratios.

`revise_abstract_document.py` rebuilds the Word draft from the supplied source author table and finalized figure outputs, using the bundled document Python runtime. Regeneration must be followed by a new Word/PDF page render and visual review. `document_validation.json` records lengths against the official 2027 limits: https://www.ismrm.org/27m/call/standard/.

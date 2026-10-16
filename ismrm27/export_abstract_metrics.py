"""Validate available native maps and export the abstract's numerical evidence.

Run with the scientific Python environment used for the figure notebook.
No raw MRI inputs or external processing products are modified.
"""
from pathlib import Path
import json
import numpy as np
import pandas as pd
import nibabel as nib
from nibabel.processing import resample_from_to
from data_helpers import read_epi, read_pose, read_json, source_record, METHODS

ROOT = Path(__file__).resolve().parent
DATA = Path(r'C:\Users\hmattern\Documents\Data\TH_Impulse_local')
DERIV = DATA / 'derivatives' / 'ths_impulse_code'
SESSIONS = ['02', '03', '04', '06', '07']
RUNS = SESSIONS + ['new1', 'new2', 'new3']


def export_epi(table):
    table = table.copy()
    table['condition'] = ['original' if s in SESSIONS else 'first_run_unintentional_preheating' if s == 'new1' else 'subsequent_run' for s in table.session]
    table['run_order_october'] = [int(s[-1]) if s.startswith('new') else np.nan for s in table.session]
    for name, numerator, denominator in [
        ('detrending_gain_percent', METHODS[1], METHODS[0]),
        ('motion_correction_gain_percent', METHODS[2], METHODS[1]),
        ('total_processing_gain_percent', METHODS[2], METHODS[0])]:
        table[name] = 100 * (table[numerator + '_median'] / table[denominator + '_median'] - 1)
    table.to_csv(ROOT / 'epi_run_summary.csv', index=False)
    indexed = table.set_index('session')
    changes = []
    for baseline in ['06', '07', 'median_06_07', 'new2']:
        for run in ['new1', 'new2', 'new3', 'median_new2_new3']:
            for metric in METHODS:
                column = metric + '_median'
                b = float(indexed.loc[['06','07'], column].median()) if baseline.startswith('median') else float(indexed.loc[baseline, column])
                f = float(indexed.loc[['new2','new3'], column].median()) if run.startswith('median') else float(indexed.loc[run, column])
                changes.append(dict(metric=metric, baseline=baseline, Add_on_source=run,
                                    baseline_value=b, followup_value=f, absolute_change=f-b,
                                    gain_percent=100*(f/b-1), statistic='ratio of native brain run medians; grouped values are medians of run medians'))
    pd.DataFrame(changes).to_csv(ROOT / 'epi_addon_changes.csv', index=False)
    groups = []
    for site, condition, ids in [('stanford','original',['02','03']),('berkeley','original',['04']),
                                 ('magdeburg','original',['06','07']),
                                 ('magdeburg','first_run_unintentional_preheating',['new1']),
                                 ('magdeburg','subsequent_runs',['new2','new3'])]:
        for metric in METHODS:
            values = indexed.loc[ids, metric+'_median'].to_numpy()
            q1, median, q3 = np.percentile(values, [25,50,75])
            groups.append(dict(site=site, cohort=condition, metric=metric, n_runs=len(ids), median=median,
                               minimum=values.min(), maximum=values.max(),
                               q1=q1 if len(ids)>1 else np.nan, q3=q3 if len(ids)>1 else np.nan,
                               scope='across run medians; not voxel quartiles or confidence intervals'))
    pd.DataFrame(groups).to_csv(ROOT / 'epi_across_run_summary.csv', index=False)
    return table


def main():
    manifest_path = DERIV/'epi_qc'/'abstract_export'/'export_manifest.json'
    table, maps, sources = read_epi(ROOT/'ismrm_2027_ep2d_summary.csv',manifest_path,RUNS,DATA,DERIV)
    table = export_epi(table)
    inventory = []
    manifest = read_json(manifest_path)
    processing = []
    for _, row in table.iterrows():
        sidecar = Path(row.source).with_suffix('.json')
        meta = read_json(sidecar)
        image = nib.load(row.source)
        entry = next(e for e in manifest['runs'] if e['run']==row.run)
        preproc = read_json(entry['preprocessing_manifest'])
        processing.append(dict(run=row.session, preprocessing_manifest=entry['preprocessing_manifest'],
                               ants_version=preproc['ants_version'], contract=preproc['contract']))
        assert preproc['contract']['registration_reference_volume']==0
        assert preproc['contract']['type_of_transform']=='BOLDRigid'
        assert np.isclose(meta['RepetitionTime'],row.tr_seconds)
        assert np.isclose(meta['EchoTime']*1000,row.te_ms)
        inventory.append(dict(acquisition_id=row.session,site=row.site,condition=row.condition,
                              run_order_october=row.run_order_october,source=row.source,sidecar=str(sidecar),
                              software=meta.get('SoftwareVersions'),protocol=meta.get('ProtocolName'),
                              voxel_x_mm=image.header.get_zooms()[0],voxel_y_mm=image.header.get_zooms()[1],voxel_z_mm=image.header.get_zooms()[2],
                              tr_seconds=row.tr_seconds,te_ms=row.te_ms,volumes_acquired=row.volumes_acquired,volumes_used=row.volumes_used,
                              pixel_bandwidth=meta.get('PixelBandwidth'),phase_encoding=meta.get('PhaseEncodingDirection'),
                              multiband_factor=meta.get('MultibandAccelerationFactor'),inplane_acceleration=meta.get('ParallelReductionFactorInPlane')))
    pd.DataFrame(inventory).to_csv(ROOT/'acquisition_inventory.csv',index=False)
    pose = read_pose(ROOT/'ismrm_2027_b0_shim_and_brain_orientation.csv',SESSIONS)
    pose = pose[((pose.session!='03')&(pose.setting==1))|((pose.session=='03')&(pose.setting==2))].copy()
    qc = pd.read_csv(DERIV/'brain_pose.csv', dtype={'session':str})
    qc.session=qc.session.str.zfill(2)
    pose = pose.merge(qc[['session','mask_path','qc_status','qc_messages','qc_image','mask_touches_boundary']],on='session',validate='one_to_one')
    for s in SESSIONS:
        r=pose[pose.session==s].iloc[0]
        assert r.qc_status=='ok' and not r.mask_touches_boundary
        mask=nib.load(r.mask_path)
        valid=np.asanyarray(mask.dataobj)>0
        centroid=nib.affines.apply_affine(mask.affine,np.argwhere(valid).mean(axis=0))
        centre=nib.affines.apply_affine(mask.affine,(np.array(mask.shape)-1)/2)
        assert np.allclose(centroid-centre,[r[f'translation_ras_{a}_mm'] for a in 'xyz'],atol=1e-4)
    pose['second_order_channel_labels']='A20;A21;B21;A22;B22'
    pose['channel_label_basis']='user confirmed'
    pose['shift_definition']='brain centroid minus native mask volume centre'
    pose['rotation_definition']='brain-mask PCA ellipsoid; fixed-axis xyz; RAS'
    pose.to_csv(ROOT/'shim_pose_metrics.csv',index=False)
    # Correlations are already rounded source readings; preserve precision and direction.
    corr=pd.read_csv(ROOT/'ismrm_2027_b0_b1_mp2rage_correlations.csv',dtype={'row_session':str,'col_session':str})
    for column in ['row_session','col_session']:
        corr[column]=corr[column].str.removeprefix('ses').str.zfill(2)
    corr=corr[corr.row_session.isin(SESSIONS)&corr.col_session.isin(SESSIONS)].copy()
    sites=table.set_index('session').site.to_dict()
    corr['comparison']=['identity' if a==b else 'within_site' if sites[a]==sites[b] else 'between_site' for a,b in zip(corr.row_session,corr.col_session)]
    corr['source_precision']='two decimal plot transcription; original matrices pending'
    corr.to_csv(ROOT/'pairwise_metrics.csv',index=False)
    corr[corr.comparison!='identity'].groupby(['matrix','comparison']).correlation.agg(['count','min','max','median']).reset_index().to_csv(ROOT/'correlation_summary.csv',index=False)
    # Four B1 combined maps have an explicit 0.1% scale in their acquisition sidecars.
    files={'02':'dzne_b1map_5iso_sag_B1Comb_11','03':'dzne_b1map_5iso_sag_B1Comb_20','06':'dzne_b1map_5iso_sag_B1Comb_11','07':'dzne_b1map_5iso_sag_B1Comb_11'}
    fields=[]
    for s in SESSIONS:
        if s not in files:
            fields.append(dict(session=s,modality='B1',status='pending reconstructed DREAM map',units='percent nominal'))
            continue
        path=DATA/'scan_data'/f'THS_ses{s}_{sites[s]}'/'nii'/(files[s]+'.nii')
        meta=read_json(path.with_suffix('.json'))
        if 'rel. B1 [0.1 %]' not in meta.get('ImageComments',''):
            raise ValueError(f'{s}: B1 unit conversion is unconfirmed')
        image=nib.load(path)
        brain=nib.load(pose.set_index('session').loc[s,'mask_path'])
        mask=resample_from_to(brain,image,order=0).get_fdata()>0
        data=image.get_fdata()*0.1
        values=data[mask&np.isfinite(data)&(data>0)]
        q1,median,q3=np.percentile(values,[25,50,75])
        fields.append(dict(session=s,modality='B1',status='available native map',units='percent nominal',
                           source=str(path),mask_source=pose.set_index('session').loc[s,'mask_path'],
                           n_valid_voxels=len(values),median=median,q1=q1,q3=q3,mean=values.mean(),sd=values.std(ddof=0),
                           cv_percent=100*values.std(ddof=0)/values.mean(),mean_abs_deviation_from_nominal=np.abs(values-100).mean(),
                           mask_definition='native MP2RAGE brain mask resampled nearest-neighbour; finite positive B1'))
    fields += [dict(session=s,modality='B0',status='pending ROMEO Hz map and validity mask',units='Hz') for s in SESSIONS]
    pd.DataFrame(fields).to_csv(ROOT/'field_metrics.csv',index=False)
    report=[]
    for _,r in table.iterrows():
        for metric in METHODS:
            report.append(dict(section='EPI',acquisition=r.session,metric=metric,value=r[metric+'_median'],rounded=f'{r[metric+"_median"]:.2f}',source_csv='epi_run_summary.csv',statistic='native brain voxel median'))
    for _,r in pd.read_csv(ROOT/'epi_addon_changes.csv').iterrows():
        report.append(dict(section='EPI change',acquisition=r.Add_on_source,baseline=r.baseline,metric=r.metric,value=r.gain_percent,rounded=f'{r.gain_percent:.1f}%',source_csv='epi_addon_changes.csv',statistic=r.statistic))
    for _,r in pd.read_csv(ROOT/'epi_across_run_summary.csv').iterrows():
        report.append(dict(section='EPI group',acquisition=r.site+' '+r.cohort,metric=r.metric,value=r['median'],rounded=f'{r["median"]:.2f}',source_csv='epi_across_run_summary.csv',statistic='median of run-level brain medians'))
    for _,r in pd.read_csv(ROOT/'correlation_summary.csv').iterrows():
        for stat in ['min','max']:
            report.append(dict(section='Correlation',acquisition=r.comparison,metric=r.matrix+' '+stat,value=r[stat],rounded=f'{r[stat]:.2f}',source_csv='correlation_summary.csv',statistic='directed nonidentity plot readings; two-decimal source precision'))
    for column,unit in [('shim_current_0_ma','mA'),('rotation_ras_x_deg','degrees')]:
        for stat in ['min','max']:
            value=float(getattr(pose[column],stat)())
            report.append(dict(section='Shim and pose',acquisition='five original analyzed sessions',metric=column+' '+stat,value=value,rounded=f'{value:.1f}',source_csv='shim_pose_metrics.csv',statistic=unit))
    pd.DataFrame(report).to_csv(ROOT/'abstract_reported_numbers.csv',index=False)
    (ROOT/'metrics_validation.json').write_text(json.dumps(dict(validated_runs=RUNS,map_checks=sources,processing=processing,
        sources=[source_record(ROOT/'ismrm_2027_ep2d_summary.csv'),source_record(manifest_path)],
        pending=['ROMEO B0 Hz maps and validity masks','Berkeley reconstructed DREAM B1 map','original correlation RMSE MAPD matrices'],
        pose_centroids_verified=True,pose_qc='all five selected sessions ok'),indent=2),encoding='utf-8')
    print('Validated 8 EPI runs; exported acquisition, EPI, field, correlation and shim/pose metrics.')


if __name__=='__main__':
    main()

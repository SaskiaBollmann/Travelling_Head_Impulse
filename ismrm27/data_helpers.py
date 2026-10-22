"""Scientific input checks for the notebook; no plotting configuration or output handling."""
from pathlib import Path
import json
import hashlib
import numpy as np
import pandas as pd
import nibabel as nib
from scipy.spatial.transform import Rotation

METHODS = ('raw_tsnr', 'detrended_tsnr', 'motion_corrected_detrended_tsnr')


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def source_record(path, **notes):
    path = Path(path)
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), **notes}


def read_image(path):
    image = nib.load(str(path))
    if len(image.shape) != 3 or not np.isfinite(image.affine).all() or abs(np.linalg.det(image.affine[:3,:3])) < 1e-10:
        raise ValueError(f'Expected a 3D image with valid geometry: {path}')
    return image, image.get_fdata(dtype=np.float32)


def read_correlations(path, sessions):
    table = pd.read_csv(path, dtype={'row_session':str, 'col_session':str})
    expected = ['matrix','row_session','col_session','correlation']
    if list(table.columns) != expected:
        raise ValueError(f'Correlation CSV requires {expected}')
    for col in ('row_session','col_session'):
        table[col] = table[col].str.removeprefix('ses').str.zfill(2)
    names = ['B0_rigid','B1_rigid','MP2RAGE_rigid','MP2RAGE_SyN']
    order = [f'{i:02d}' for i in range(1,8)]
    result = {}
    if set(table.matrix) != set(names):
        raise ValueError('Unexpected or missing correlation matrices')
    for name in names:
        rows = table[table.matrix==name]
        if len(rows)!=49 or rows.duplicated(['row_session','col_session']).any():
            raise ValueError(f'{name}: require 49 unique directional cells')
        if set(rows.row_session)!=set(order) or set(rows.col_session)!=set(order):
            raise ValueError(f'{name}: expected sessions 01–07')
        if not np.isfinite(rows.correlation).all() or (rows.correlation.abs()>1).any():
            raise ValueError(f'{name}: invalid correlation values')
        matrix = rows.pivot(index='row_session',columns='col_session',values='correlation')
        result[name] = matrix.loc[sessions,sessions].to_numpy()
    return result


def read_mapd(path, sessions):
    """Read all directional screenshot-transcribed MAPD values before subsetting."""
    table = pd.read_csv(path, dtype={'row_session': str, 'col_session': str})
    expected = ['matrix', 'row_session', 'col_session', 'mapd_percent']
    if list(table.columns) != expected:
        raise ValueError(f'MAPD CSV requires {expected}')
    for column in ('row_session', 'col_session'):
        table[column] = table[column].str.removeprefix('ses').str.zfill(2)
    names = ['B0_rigid', 'B1_rigid']
    order = [f'{i:02d}' for i in range(1, 8)]
    if set(table.matrix) != set(names):
        raise ValueError('Unexpected or missing MAPD matrices')
    result = {}
    for name in names:
        rows = table[table.matrix == name]
        if len(rows) != 49 or rows.duplicated(['row_session', 'col_session']).any():
            raise ValueError(f'{name}: require 49 unique directional cells')
        if set(rows.row_session) != set(order) or set(rows.col_session) != set(order):
            raise ValueError(f'{name}: expected sessions 01–07')
        if not np.isfinite(rows.mapd_percent).all() or (rows.mapd_percent < 0).any():
            raise ValueError(f'{name}: invalid MAPD values')
        matrix = rows.pivot(index='row_session', columns='col_session', values='mapd_percent')
        result[name] = matrix.loc[sessions, sessions].to_numpy()
    return result


def read_pose(path, sessions):
    table = pd.read_csv(path, dtype={'session':str})
    table.session = table.session.str.zfill(2)
    table = table[table.session.isin(sessions)].copy()
    table['setting'] = table.groupby('session').cumcount()+1
    C = np.diag([-1.,-1.,1.])
    for session in sessions:
        rows = table[table.session==session]
        if rows.empty:
            raise ValueError(f'Missing pose for {session}')
        first = None
        for index,row in rows.iterrows():
            matrix = np.array([[row[f'orientation_lps_r{i}{j}'] for j in range(3)] for i in range(3)],dtype=float)
            angles = np.array([row[f'rotation_lps_{a}_deg'] for a in 'xyz'],dtype=float)
            shift = np.array([row[f'translation_lps_{a}_mm'] for a in 'xyz'],dtype=float)
            if not np.isfinite(matrix).all() or not np.isfinite(angles).all() or not np.isfinite(shift).all():
                raise ValueError(f'{session}: non-finite pose')
            if not np.allclose(matrix.T@matrix,np.eye(3),atol=3e-6,rtol=0) or not np.isclose(np.linalg.det(matrix),1,atol=3e-6):
                raise ValueError(f'{session}: invalid orientation matrix')
            decomposed = Rotation.from_matrix(matrix).as_euler('xyz',degrees=True)
            if np.max(np.abs((decomposed-angles+180)%360-180))>1e-4:
                raise ValueError(f'{session}: LPS Euler angles disagree with matrix')
            signature = np.r_[matrix.ravel(),angles,shift]
            if first is not None and not np.allclose(first,signature,atol=1e-8,rtol=0):
                raise ValueError(f'{session}: repeated pose rows disagree')
            first = signature
            ras_angles = Rotation.from_matrix(C@matrix@C).as_euler('xyz',degrees=True)
            for a,value in zip('xyz',ras_angles):
                table.loc[index,f'rotation_ras_{a}_deg']=value
            for a,value in zip('xyz',C@shift):
                table.loc[index,f'translation_ras_{a}_mm']=value
    return table


def existing_path(value, data_root, derivatives):
    path = Path(value)
    if path.is_file():
        return path
    text = str(value).replace('\\','/')
    for marker,root in (('/derivatives/ths_impulse_code/',derivatives),('/scan_data/',Path(data_root)/'scan_data')):
        if marker in text:
            candidate = Path(root)/text.split(marker,1)[1]
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(f'Missing EPI input: {value}')


def read_epi(path, manifest_path, runs, data_root, derivatives):
    """Reuse existing maps, checking each against the supplied run-level CSV."""
    table = pd.read_csv(path,dtype={'session':str})
    if any((table.session==s).sum()!=1 for s in runs):
        raise ValueError('Each selected EPI run must occur once in the CSV')
    table = table.set_index('session').loc[runs].reset_index()
    manifest = read_json(manifest_path)
    loaded, sources = {}, []
    for _,row in table.iterrows():
        s = row.session
        if row.drop_initial!=10 or row.volumes_used!=row.volumes_acquired-10 or row.tr_seconds<=0:
            raise ValueError(f'{s}: inconsistent temporal scope')
        matches = [r for r in manifest['runs'] if r['run']==row.run]
        if len(matches)!=1:
            raise ValueError(f'{s}: require one matching manifest entry')
        entry = matches[0]
        cache_path = existing_path(entry['raw_metric_cache'],data_root,derivatives)
        corrected_path = existing_path(entry['corrected_metric_summary'],data_root,derivatives)
        cache,corrected = read_json(cache_path),read_json(corrected_path)
        if cache['contract']['drop_initial']!=10 or cache['contract']['ddof']!=0 or corrected['drop_initial']!=10 or corrected['standard_deviation_ddof']!=0 or corrected['retained_timepoints']!=row.volumes_used:
            raise ValueError(f'{s}: temporal map contract differs from CSV')
        original = existing_path(row.source,data_root,derivatives)
        if original.resolve()!=existing_path(cache['contract']['input']['path'],data_root,derivatives).resolve():
            raise ValueError(f'{s}: source differs from cache')
        header = nib.load(original)
        if len(header.shape)!=4 or header.shape[3]!=row.volumes_acquired:
            raise ValueError(f'{s}: source volume count differs')
        paths = {'mean':cache['outputs']['mean_path'], 'raw_tsnr':cache['outputs']['tsnr_path'],
                 'detrended_tsnr':cache['outputs']['detrended_tsnr_path'],
                 'motion_corrected_detrended_tsnr':corrected_path.parent/'motion_corrected_detrended_tsnr.nii.gz',
                 'mask':entry['mask']}
        paths = {k:existing_path(v,data_root,derivatives) for k,v in paths.items()}
        mask_image,mask_data = read_image(paths['mask'])
        mask = np.isfinite(mask_data)&(mask_data>0)
        if int(mask.sum())!=row.brain_voxels:
            raise ValueError(f'{s}: mask voxel count differs')
        images = {}
        for kind in ('mean',*METHODS):
            image,data = read_image(paths[kind])
            if image.shape!=mask_image.shape or not np.allclose(image.affine,mask_image.affine,atol=1e-4,rtol=0):
                raise ValueError(f'{s}: image/mask grids differ')
            valid = mask&np.isfinite(data)
            if kind in METHODS:
                q = np.percentile(data[valid],[25,50,75])
                expected = [row[f'{kind}_{stat}'] for stat in ('q1','median','q3')]
                if int(valid.sum())!=row[f'{kind}_valid_voxels'] or not np.allclose(q,expected,atol=1e-3,rtol=1e-5):
                    raise ValueError(f'{s}: {kind} map quartiles/count disagree with CSV')
            images[kind]=(image,np.where(valid,data,np.nan))
        centre = nib.affines.apply_affine(mask_image.affine,np.argwhere(mask).mean(axis=0))
        loaded[s]={'images':images,'centre':centre,'paths':paths}
        sources.append({'run':s,'source':str(original),'maps':{k:str(v) for k,v in paths.items()},
                        'raw_cache':str(cache_path),'corrected_summary':str(corrected_path),'CSV_values_verified':True})
    table['retained_seconds']=table.volumes_used*table.tr_seconds
    return table,loaded,sources

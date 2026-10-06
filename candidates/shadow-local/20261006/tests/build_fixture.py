#!/usr/bin/env python3
"""Select immutable public source triangles and canopy rows, never rebuild terrain."""
from pathlib import Path
import gzip, hashlib, json, shutil
import numpy as np
ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parents[1]
pins = {}
def read(path, expected=None):
    b = (ROOT/path).read_bytes()
    h = hashlib.sha256(b).hexdigest()
    if expected is not None: assert h == expected, path
    pins[str(path)] = {'sha256':h, 'bytes':len(b)}
    return b
def js(path): return json.loads(read(path))
def write(name, value): (OUT/'fixture'/name).write_text(json.dumps(value,separators=(',',':'))+'\n')
bounds = [2.5,17.6,8.7,23.2]
def selected(t):
    x,z=t[:,:,0],t[:,:,2]
    return (x.max(1)>=bounds[0])&(x.min(1)<=bounds[2])&(z.max(1)>=bounds[1])&(z.min(1)<=bounds[3])
r=Path('artifacts/natural_shorelines_v03_20261002/cache')
m=js(r/'manifest.json')
ground=[];ground_provenance=[]
for row in m['chunks']:
    lo,hi=row['bounds_min'],row['bounds_max']
    if row['kind']!='ground' or lo[0]>bounds[2] or hi[0]<bounds[0] or lo[2]>bounds[3] or hi[2]<bounds[1]:continue
    t=np.frombuffer(gzip.decompress(read(r/row['vertices'],m['files'][row['vertices']]['sha256'])),'<f4').reshape(-1,3,14)
    ids=np.where(selected(t))[0]
    ground.extend(t[ids].reshape(-1,14).tolist())
    ground_provenance.extend([{'chunk':row['key'],'triangle':int(i)} for i in ids])
assert len(ground)==568*3
mount_root=Path('artifacts/faceted_mountains_20261002/shore_v03')
mount=js(mount_root/'manifest.json')
raw=np.frombuffer(gzip.decompress(read(mount_root/mount['binary'],mount['binary_sha256'])),'<f4').reshape(-1,8)
mountains=[];mount_provenance=[]
for group_id in [9,10]:
    g=mount['groups'][group_id]
    t=raw[g['first_vertex']:g['first_vertex']+g['vertices']].reshape(-1,3,8)
    ids=np.where(selected(t))[0]
    mountains.extend(t[ids].reshape(-1,8).tolist())
    mount_provenance.extend([{'group':group_id,'triangle':int(i)} for i in ids])
assert len(mountains)==520*3
can_root=Path('artifacts/integrated_ecology_world_20261002/performance_variant/world_canopies_v2')
can=js(can_root/'manifest.json');rr=can['runtime']
rows=np.frombuffer(gzip.decompress(read(can_root/rr['file'],rr['sha256'])),'<f4').reshape(-1,10)
supports=json.loads(gzip.decompress(read(r/'canopy_support_v03.json.gz',m['files']['canopy_support_v03.json.gz']['sha256'])))['updates']
trees=[]
for i,row in enumerate(rows):
    x,y,z=row[:3];change=supports[i]
    if bounds[0]<=x<=bounds[2] and bounds[1]<=z<=bounds[3] and not change['hide']:
        values=row.tolist();values[1]=change['height']
        trees.append({'source_row':i,'kind':rr['kinds'][int(row[7])],'values':values})
write('ridge.json',{'bounds':bounds,'ground':ground,'mountains':mountains,'trees':trees,'ground_provenance':ground_provenance,'mountain_provenance':mount_provenance})
for src in ['view/ecology_preview/vegetation_meshes.gd','view/integrated_ecology_world/tabs_style/ground.gdshader','view/integrated_ecology_world/tabs_style/vegetation.gdshader','view/integrated_ecology_world/faceted_mountains/mountains.gdshader']:
    (OUT/'fixture'/Path(src).name).write_bytes(read(Path(src)))
(OUT/'fixture'/'visual_weights_v03.png').write_bytes(read(r/'visual_weights_v03.png',m['files']['visual_weights_v03.png']['sha256']))
contact_root=Path('artifacts/integrated_ecology_world_20261002/lighting_profile')
contact=js(contact_root/'manifest.json')
for name in ['manifest.json',contact['file']]:
    (OUT/'fixture'/('contact_'+name)).write_bytes(read(contact_root/name, contact['sha256'] if name==contact['file'] else None))
write('SOURCE_PINS.json',{'public_checkout':'5eef3816f30cc2651d2ac47c95d3fcd9f03e3eda','restore_entry':'tools/restore_repository.py','public_source_mesh_sha256':m['source_mesh_sha256'],'native_v28_identity_claimed':False,'library_bytes_recovered':False,'ground_triangles':568,'mountain_triangles':520,'canopy_instances':len(trees),'pins':pins})
print(json.dumps({'ground':568,'mountains':520,'trees':len(trees),'source_files':len(pins)}))

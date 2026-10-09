#!/usr/bin/env python3
"""Read-only checks for pinned city meshes and flat-varying material contract."""
import hashlib,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
KIT=ROOT/'assets/city_districts'
checks=[]
def check(ok,label):
    checks.append({'passed':bool(ok),'name':label})
def glb(path):
    data=path.read_bytes();length,_=struct.unpack_from('<II',data,12)
    doc=json.loads(data[20:20+length]);binary=data[28+length:]
    def attr(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        count={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
        size=struct.calcsize('<'+fmt)*count;start=v.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from('<'+fmt*count,binary,start+i*v.get('byteStride',size)) for i in range(a['count'])]
    p=doc['meshes'][0]['primitives'][0];positions=attr(p['attributes']['POSITION']);colors=attr(p['attributes']['COLOR_0']);indices=[x[0] for x in attr(p['indices'])]
    return doc,positions,colors,indices
rows=json.loads((KIT/'manifest.json').read_text())['assets']
for row in rows:
    variants=[]
    for kind,key,hash_key in [('full','glb','sha256'),('low','lod1_glb','lod1_sha256')]:
        path=KIT/row[key];check(hashlib.sha256(path.read_bytes()).hexdigest()==row[hash_key],f'{row["id"]}/{kind}: exact original hash')
        doc,pos,col,idx=glb(path)
        check(len(doc['nodes'])==len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,f'{row["id"]}/{kind}: single-node single-surface kit')
        check(all(all(c==col[idx[i]] for c in [col[idx[i+1]],col[idx[i+2]]]) for i in range(0,len(idx),3)),f'{row["id"]}/{kind}: uniform triangle colors for flat varying')
        bounds=([min(v[k] for v in pos) for k in range(3)],[max(v[k] for v in pos) for k in range(3)])
        check(abs(bounds[0][1])<1e-6,f'{row["id"]}/{kind}: unchanged ground pivot')
        variants.append(bounds)
    full,low=variants
    check(all(low[0][k]>=full[0][k]-1e-6 and low[1][k]<=full[1][k]+1e-6 for k in range(3)),f'{row["id"]}: LOD never grows original clearance bounds')
    if row['id']!='garden_court':check(abs(low[1][1]-full[1][1])<1e-6,f'{row["id"]}: main roof/chimney height preserved')
report={'checks':len(checks),'passed':all(r['passed'] for r in checks),'failures':[r for r in checks if not r['passed']],'details':checks}
print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)

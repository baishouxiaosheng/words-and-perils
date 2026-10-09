"""Independent GLB contract check. Run with ordinary Python, not Godot."""
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
TYPE={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
FMT={5121:'B',5123:'H',5125:'I',5126:'f'}

def read_glb(path):
    data=path.read_bytes()
    magic,version,length=struct.unpack_from('<III',data)
    assert magic==0x46546C67 and version==2 and length==len(data)
    p=12;doc=None;binary=None
    while p<len(data):
        n,t=struct.unpack_from('<II',data,p);part=data[p+8:p+8+n];p+=n+8
        if t==0x4E4F534A:doc=json.loads(part)
        if t==0x004E4942:binary=part
    assert doc is not None and binary is not None
    return doc,binary,data

def accessor(doc,binary,idx):
    a=doc['accessors'][idx];v=doc['bufferViews'][a['bufferView']]
    fmt='<'+FMT[a['componentType']]*TYPE[a['type']]
    size=struct.calcsize(fmt);stride=v.get('byteStride',size)
    start=v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]

def main():
    manifest=json.loads((ROOT/'manifest.json').read_text());checks=[]
    assert len(manifest['assets'])==13
    for asset in manifest['assets']:
        for lod,file_key,hash_key in [('lod0','glb','sha256'),('lod1','lod1_glb','lod1_sha256')]:
            doc,bin,data=read_glb(ROOT/asset[file_key])
            assert hashlib.sha256(data).hexdigest()==asset[hash_key]
            assert not doc.get('textures') and not doc.get('images') and not doc.get('animations')
            assert len(doc['meshes'])==len(doc['materials'])==len(doc['nodes'])==1
            assert not any(k in doc['nodes'][0] for k in ['matrix','scale','rotation','translation'])
            assert len(doc['meshes'][0]['primitives'])==1
            p=doc['meshes'][0]['primitives'][0]
            assert {'POSITION','NORMAL','COLOR_0'}<=set(p['attributes'])
            verts=accessor(doc,bin,p['attributes']['POSITION'])
            normals=accessor(doc,bin,p['attributes']['NORMAL'])
            colors=accessor(doc,bin,p['attributes']['COLOR_0'])
            indices=[row[0] for row in accessor(doc,bin,p['indices'])]
            assert len(indices)//3==asset[lod]['triangles']
            assert min(indices)>=0 and max(indices)<len(verts)
            assert len(verts)==len(normals)==len(colors)
            assert all(math.isfinite(v) for row in verts+normals+colors for v in row)
            assert all(abs(sum(x*x for x in n)-1)<.0001 for n in normals)
            lo=[min(v[i] for v in verts) for i in range(3)];hi=[max(v[i] for v in verts) for i in range(3)]
            assert abs(lo[1])<.00001,'origin is not grounded'
            assert hi[0]-lo[0]<=.55001 and hi[2]-lo[2]<=.55001
            assert hi[1]<=1.50001
            if lod=='lod0':
                assert all(abs(lo[i]-asset['aabb_min_xyz'][i])<.00001 for i in range(3))
                assert all(abs(hi[i]-asset['aabb_max_xyz'][i])<.00001 for i in range(3))
            degenerates=0
            for i in range(0,len(indices),3):
                a,b,c=[verts[j] for j in indices[i:i+3]]
                u=[b[k]-a[k] for k in range(3)];v=[c[k]-a[k] for k in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                if sum(x*x for x in cross)<1e-20:degenerates+=1
            assert degenerates==0,(asset['id'],lod,degenerates)
            checks.append({'asset':asset['id'],'lod':lod,'triangles':len(indices)//3,
              'exported_vertices':len(verts),'surfaces':1,'vertex_colors':True,
              'degenerate_triangles':degenerates,'aabb_min':lo,'aabb_max':hi,'bytes':len(data)})
        assert asset['lod1']['triangles']<=asset['lod0']['triangles']
    assert (ROOT/'source/city_district_kit.blend').is_file()
    result={'ok':True,'checks':len(checks),'blender_source_present':True,
      'checks_passed':['GLB2 structure','manifest hashes','one mesh / one surface / one material',
      'no external texture dependency','flat unit normals / vertex colors','finite indexed triangles',
      'zero degenerate triangles','ground pivot / identity transforms','compact footprint <=0.55',
      'declared heights <=1.50','LOD1 bounded by LOD0'],
      'not_claimed':['Godot integration or in-game placement','native runtime screenshot',
      'GTX 1660 Ti frame rate'], 'assets':checks}
    (ROOT/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'ok':True,'checks':len(checks),'triangles':manifest['totals'],
      'glb_bytes':sum(c['bytes'] for c in checks)},indent=2))

if __name__=='__main__':main()

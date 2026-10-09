"""Strict, manifest-driven runtime closure. Never includes provenance-only sources.
Only declared runtime resource locations below res://artifacts are accepted.
"""
from pathlib import Path,PurePosixPath
import json,hashlib

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def resolve_resource(root,path):
 if not isinstance(path,str) or not path.startswith('res://artifacts/') or '\\' in path:raise ValueError('Invalid runtime root: '+str(path))
 parts=PurePosixPath(path[6:]).parts
 if any(p in ('..','.') for p in path[6:].split('/')):raise ValueError('Path escape: '+path)
 value=root.joinpath(*parts).resolve()
 if not value.is_relative_to((root/'artifacts').resolve()):raise ValueError('Runtime path outside artifact root: '+path)
 if not value.is_file():raise FileNotFoundError(value)
 return value

def manifest_members(root,manifest_path):
 """Known cache contracts; unrecognized metadata is not guessed as file input."""
 data=json.loads(manifest_path.read_text());result={}
 def add(name,expected,base=None):
  if not isinstance(name,str) or not name or '/' in name or '\\' in name or name in ('.','..'):raise ValueError('Invalid local member: '+str(name))
  p=(base or manifest_path.parent)/name
  resource='res://'+str(p.relative_to(root));p=resolve_resource(root,resource)
  if not isinstance(expected,str) or len(expected)!=64 or sha(p)!=expected:raise ValueError('Runtime member hash mismatch: '+str(p))
  result[resource]={'path':resource,'sha256':expected,'runtime_required':True}
 for name,row in data.get('files',{}).items():
  if row.get('runtime_required',True) is False:continue
  base=None
  if row.get('storage')=='baseline_cache':
   path=data.get('performance_variant',{}).get('baseline_root')
   if not isinstance(path,str) or not path.startswith('res://artifacts/') or '..' in path:raise ValueError('Invalid baseline storage root')
   base=root/path[6:]
  elif row.get('storage') not in (None,'performance_variant_cache'):raise ValueError('Unknown cache storage')
  add(name,row['sha256'],base)
 for mesh in data.get('meshes',[]):
  for name,expected in mesh.get('file_sha256',{}).items():add(name,expected)
 if isinstance(data.get('runtime'),dict) and 'file' in data['runtime']:add(data['runtime']['file'],data['runtime']['sha256'])
 if 'file' in data and 'sha256' in data:add(data['file'],data['sha256'])
 if 'binary' in data:add(data['binary'],data['binary_sha256'])
 if 'overlay_contract_file' in data:add(data['overlay_contract_file'],data['overlay_contract_sha256'])
 return result

def create_closure(root,entries):
 output={}
 for label,entry in sorted(entries.items()):
  if entry.get('runtime_required',True) is False:continue
  p=resolve_resource(root,entry['path'])
  if sha(p)!=entry['sha256']:raise ValueError('Runtime root SHA mismatch: '+label)
  output[entry['path']]=dict(entry)
  if p.name.endswith('manifest.json') or p.name=='render_cache_manifest_PENDING.json':output.update(manifest_members(root,p))
 return {'schema':'fogbank-runtime-dependency-closure/v1','files':[output[k] for k in sorted(output)],'policy':'DECLARED_RUNTIME_ONLY_NO_SCIENTIFIC_SOURCE_INHERITANCE'}

def runtime_dependency_closure(root,bundle_path=None):
 root=Path(root).resolve();bundle_path=bundle_path or root/'artifacts/world_bundle_20261002/manifest.json'
 manifest=json.loads(bundle_path.read_text())
 if manifest.get('schema')!='fogbank-active-world-bundle/v1':raise ValueError('Unknown bundle schema')
 entry=manifest['runtime']['dependency_closure'];path=resolve_resource(root,entry['path'])
 if sha(path)!=entry['sha256']:raise ValueError('Runtime closure SHA mismatch')
 closure=json.loads(path.read_text())
 if closure.get('schema')!='fogbank-runtime-dependency-closure/v1':raise ValueError('Unknown closure schema')
 files={bundle_path,path}
 for row in closure['files']:
  if row.get('runtime_required',True) is False:continue
  p=resolve_resource(root,row['path'])
  if sha(p)!=row['sha256']:raise ValueError('Runtime dependency SHA mismatch: '+row['path'])
  files.add(p)
 for row in manifest['runtime'].values():
  if row.get('runtime_required',True) is False:continue
  p=resolve_resource(root,row['path'])
  if sha(p)!=row['sha256']:raise ValueError('Bundle runtime member SHA mismatch: '+row['path'])
  files.add(p)
 return files

if __name__=='__main__':
 root=Path(__file__).resolve().parents[2];files=runtime_dependency_closure(root)
 print(json.dumps({'runtime_files':len(files),'bytes':sum(p.stat().st_size for p in files),'bundle':'artifacts/world_bundle_20261002/manifest.json'}))

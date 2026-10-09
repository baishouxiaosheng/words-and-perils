import sys,ast,json,re,hashlib,subprocess,importlib.util,os
from pathlib import Path
R=Path(__file__).parent;G=R/'git';HOST=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\public-v30')
sys.path.insert(0,r'E:\WordsAndPerils-Tasks\local-queue-bootstrap-20261008\run-01a1b40-02');import queue_io as old
def git(*a):return subprocess.run(['git','-C',str(G),*a],check=True,capture_output=True).stdout
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def put(n,x):old.put(R/n,x)
h=git('rev-parse','FETCH_HEAD').decode().strip();tid='WP-RAW-READBACK-VERIFY-20261009-003';raw=git('show',h+':coordination/local-work/inbox/'+tid+'.json');task=old.strict(raw)
assert hashlib.sha256(raw).hexdigest()=='ab7b82befd9ffd776e0fd62ace229f6dd3f1f839691a70391d50881ab8ada078'
assert task['task_id']==tid and task['allowed_production_changes']==[] and task['allowed_test_changes']==['tests/t03_raw_readback_runtime/parse_entry.gd','tests/t03_raw_readback_runtime/run_entry.gd']
(R/'TASK.json').write_bytes(raw)
for n,pin in [('PROTOCOL.json',old.PROTOCOL_SHA),('TASK_SCHEMA.json',old.SCHEMA_SHA)]:
 b=git('show',h+':coordination/local-work/'+n);assert hashlib.sha256(b).hexdigest()==pin;(R/n).write_bytes(b)
vpath=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\evidence\WP-NATURAL-SAVE-BOOL-20261008-001\run-20261008-a1b40-01\validate_start.py')
mod=ast.parse(vpath.read_text('utf-8-sig'));ns={'re':re};exec(compile(ast.Module(body=[n for n in mod.body if isinstance(n,ast.FunctionDef) and n.name=='validate'],type_ignores=[]),'trusted_validator','exec'),ns);ns['validate'](task,old.load(R/'TASK_SCHEMA.json'),old.load(R/'TASK_SCHEMA.json'))
git('merge-base','--is-ancestor',task['base_commit'],h)
rows=[]
for x in task['inputs']:
 old.safe(x['repository_path']);b=git('show',task['base_commit']+':'+x['repository_path']);assert len(b)==x['bytes'] and hashlib.sha256(b).hexdigest()==x['sha256'] and hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==x['git_blob_sha']
 provenance=task['verification']['candidate_input_commit'] if x['repository_path'].startswith('candidates/') else task['verification']['host_release_commit']
 assert git('show',provenance+':'+x['repository_path'])==b
 p=R/'inputs'/x['repository_path'];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b);rows.append({**x,'verified':True,'provenance_commit':provenance})
assert len(rows)==10
helper=HOST/'tools/restore_v30.py';authoritative=git('show',task['verification']['host_release_commit']+':tools/restore_v30.py');assert helper.read_bytes()==authoritative
spec=importlib.util.spec_from_file_location('v30_readonly_authority',helper);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.ROOT=HOST
r=module.legacy_helper();model=module.load_release(r);source_report=r.check_sources(model);resource_count=module.check_runtime_resources(r,model)
# No restore_sources/main/write methods invoked: validate the existing host against its layered v30 model.
assert sha(HOST/'project.godot')==task['baseline_project_pins']['project.godot']
assert sha(HOST/'core/ai_gm_rebuilt/engine.gd')=='3d41f2fc4e52459d5df01732fbacc9e849f0e4a9260094220426001ef236002d'
for p,pin in task['baseline_project_pins'].items():
 if p.startswith('tests/t03_raw_readback/') or p=='core/ai_gm_rebuilt/engine.gd':continue
 assert sha(HOST/p)==pin,p
maps={p:{'path':p,'bytes':x['size'],'sha256':x['sha256']} for p,x in model['final'].items()}
for p,x in model['runtime_resource_pins'].items():maps[p]={'path':p,'bytes':x['bytes'],'sha256':x['sha256']}
for p in ['distribution_manifest.json',module.RUNTIME_RESOURCE_MAP['path']]:maps[p]={'path':p,'bytes':(HOST/p).stat().st_size,'sha256':sha(HOST/p)}
for p,x in maps.items():
 old.safe(p) if p.lower() not in ('readme.md',) else None
 f=(HOST/p).resolve();assert f.is_relative_to(HOST.resolve()) and not (os.lstat(f).st_file_attributes&0x400) and sha(f)==x['sha256'] and f.stat().st_size==x['bytes'],p
put('HOST_SOURCE_RESOURCE_MAP.json',list(maps.values()))
put('INPUT_VERIFICATION.json',{'intake_commit':h,'task_sha256':hashlib.sha256(raw).hexdigest(),'schema_valid':True,'inputs':rows,'all_10_inputs_verified':True,'host_release_commit':task['verification']['host_release_commit'],'readonly_host_source_report':source_report,'runtime_resource_pins_verified':resource_count,'host_map_files':len(maps),'restoration_invoked':False,'BASELINE_VARIANT_PUBLIC_V30':{'host_project_sha256':task['baseline_project_pins']['project.godot'],'historical_original_Raw_project_pin':'0b35574f45a5b50307636bb3eee790a9c99be785ce3dc30c2b44e1c666dc0038','original_manifest_fully_matched':False,'original_static_grades_transferred':False},'original_engine_before_overlay_sha256':sha(HOST/'core/ai_gm_rebuilt/engine.gd')})
print(json.dumps({'inputs_verified':10,'host_files':len(maps),'runtime_resource_pins':resource_count,'production_edits':0,'engine_runs':0}))

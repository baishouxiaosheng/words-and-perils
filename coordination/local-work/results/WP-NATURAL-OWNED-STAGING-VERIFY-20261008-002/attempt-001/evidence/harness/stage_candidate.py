import shutil
from queue_io import *
assert load(R/'runs/task002-mkdir-01/VERIFIED_RESULT.json')['strict_pass']
gate('stage_candidate')
original=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\public-candidates\natural-save-identity\project')
inventory=load(Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\evidence\local-dev-20261008-sol-a1b40\DIRECTORY_INDEX_AND_HASHES.json'))
prefix='public-candidates/natural-save-identity/project/'
rows=[x for x in inventory if x['path'].startswith(prefix)];assert len(rows)==2564
for x in rows:
 p=original/x['path'][len(prefix):];assert not (os.lstat(p).st_file_attributes & 0x400) and sha(p.read_bytes())==x['sha256'],'Unknown original source change: preserved, no candidate'
project=R/'candidate-project';assert not project.exists();shutil.copytree(original,project)
task=load(R/'inbox'/ (TASK+'.json'))
for x in task['inputs']:
 if 'project_path' in x:
  safe(x['project_path']);p=project/x['project_path'];p.parent.mkdir(parents=True,exist_ok=True);b=(R/'inputs'/x['repository_path']).read_bytes();assert sha(b)==x['sha256'];p.write_bytes(b)
for p,h in task['baseline_project_pins'].items():assert sha((project/p).read_bytes())==h,p
sources=[{'path':p.relative_to(project).as_posix(),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size} for p in sorted(project.rglob('*')) if p.is_file()]
assert len(sources)==2570
put(R/'CANDIDATE_SOURCE_MAP.json',sources)
put(R/'CANDIDATE_BINDING.json',{'source_commit':task['base_commit'],'production_adapter_sha256':task['baseline_project_pins']['view/generated_natural_coast_basic/adapter.gd'],'original_source_files_verified':2564,'candidate_source_files':len(sources),'input_overlays_copied_byte_exact':True,'production_source_edits':0,'candidate_adopted':False,'original_project_godot_unchanged':True,'old_task_rerun':False})
print(json.dumps({'candidate_source_files':len(sources),'production_edits':0}))

import shutil,sys
from queue_io import *
kind=sys.argv[1];recipe=sys.argv[2] if len(sys.argv)>2 else ''
name='task002-'+kind+(('-'+recipe) if recipe else '')+'-01';out=R/'runs'/name;assert not out.exists();gate('prepare_'+name)
out.mkdir(parents=True);proj=out/'project'
if kind=='mkdir':
 proj.mkdir();(proj/'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="WordsAndPerils Owned Mkdir Probe Task002"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n','utf-8')
 src=R/'inputs/candidates/t03-natural-owned-staging/20261008-cloud-v1/overlay/tests/t03_natural_owned_staging/test_mkdir_semantics_probe.gd'
 dest=proj/'tests/t03_natural_owned_staging/test_mkdir_semantics_probe.gd';dest.parent.mkdir(parents=True);shutil.copyfile(src,dest)
 entry='tests/t03_natural_owned_staging/test_mkdir_semantics_probe.gd'
else:
 assert load(R/'runs/task002-mkdir-01/VERIFIED_RESULT.json')['strict_pass'],'mkdir prerequisite not strictly passed'
 shutil.copytree(R/'candidate-project',proj)
 entry={'focused':'tests/t03_natural_owned_staging/test_focused_write_result.gd','owned':'tests/t03_natural_owned_staging/test_owned_staging.gd','diagnostic':'tests/t03_natural_owned_staging/test_cleanup_diagnostic.gd','compile':'tests/natural_coast_basic/test_compile.gd','adapter':'tests/natural_coast_basic/test_adapter.gd','parse':''}[kind]
assert '[autoload]' not in (proj/'project.godot').read_text('utf-8-sig')
wrapper='''extends "res://ENTRY"
func _initialize() -> void:
\tvar root := OS.get_cmdline_user_args()[0].replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar os_dir := OS.get_user_data_dir().replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar global_dir := ProjectSettings.globalize_path("user://").replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar autoloads: Array = []
\tfor p in ProjectSettings.get_property_list():
\t\tif str(p.name).begins_with("autoload/"): autoloads.append(p.name)
\tvar isolated := os_dir.to_lower().begins_with((root+"/appdata/Godot/app_userdata/").to_lower()) and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
\tprint("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads,"run_id":"RUN"}))
\tif not isolated:
\t\tquit(3)
\t\treturn
\tOS.set_environment("FOGBANK_STAGING_TEST_USER_DIR",os_dir)
\tOS.set_environment("COAST_PLAY_RECIPE","RECIPE")
\tOS.set_environment("COAST_PLAY_RUN_ID","RUN")
\tOS.set_environment("COAST_PLAY_OUTPUT","OUTPUT")
\tsuper._initialize()
'''
if kind=='parse':
 wrapper=wrapper.replace('extends "res://ENTRY"','extends SceneTree').replace('\tsuper._initialize()','\tvar candidate: Script = load("res://view/generated_natural_coast_basic/adapter.gd")\n\tvar valid := candidate != null and candidate.can_instantiate()\n\tprint("CANDIDATE_PARSE ",JSON.stringify({"ok":valid,"pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"adapter_sha256":FileAccess.get_sha256("res://view/generated_natural_coast_basic/adapter.gd")}))\n\tquit(0 if valid else 1)')
wrapper=wrapper.replace('ENTRY',entry).replace('RECIPE',recipe).replace('RUN',name).replace('OUTPUT',(out/'output').as_posix())
if kind=='adapter':
 wrapper+='\nfunc check(ok: bool, label_: String) -> bool:\n\tvar result := super.check(ok,label_)\n\tif label_.begins_with("T03 "):\n\t\tprint("T03_EXECUTED ",JSON.stringify({"label":label_,"passed":ok}))\n\treturn result\n'
wp=proj/'tests/t03_natural_owned_staging_runtime/_local_entry.gd';wp.parent.mkdir(parents=True,exist_ok=True);wp.write_text(wrapper,'utf-8')
for p in ['data/appdata','data/localappdata','data/temp','output']:(out/p).mkdir(parents=True,exist_ok=True)
rows=[]
for p in sorted(proj.rglob('*')):
 if p.is_file():assert not p.is_symlink() and not (os.lstat(p).st_file_attributes & 0x400);rows.append({'path':p.relative_to(proj).as_posix(),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size})
put(out/'SOURCE_MAP.json',rows)
put(out/'PREPARATION.json',{'run_id':name,'kind':kind,'recipe':recipe,'project':str(proj),'suite':entry,'suite_sha256':sha((proj/entry).read_bytes()) if entry else None,'entry_sha256':sha(wp.read_bytes()),'source_files':len(rows),'minimal_no_candidate_probe':kind=='mkdir','source_commit':'e8941c2235069a168d9b6d92a0e9e1a62acce296','production_edits':False})
put(out/'SPEC.json',{'executable':r'E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe','arguments':['--headless','--path',str(proj),'--script','res://'+wp.relative_to(proj).as_posix(),'--',str(out/'data')],'working_directory':str(proj),'isolated_data_root':str(out/'data'),'profile':'small','timeout_seconds':120,'log_path':str(out/'GUARD_RESULT.json')})
print(json.dumps({'prepared':name,'source_files':len(rows),'kind':kind}))

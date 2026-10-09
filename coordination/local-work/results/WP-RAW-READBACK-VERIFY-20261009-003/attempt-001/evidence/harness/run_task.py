import sys,shutil,copy,ast
sys.dont_write_bytecode=True
from task_io import *
HOST=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\public-v30')
task=load(R/'TASK.json');verification=load(R/'INPUT_VERIFICATION.json');assert verification['all_10_inputs_verified']
ledger=load(STATE/'LEDGER.json');assert TASK not in ledger['tasks'],'Existing task: reconcile only, no restart'
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
handle=k.CreateFileW(str(STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None);assert handle!=ctypes.c_void_p(-1).value,'Active writer: skip'
creation=ctypes.c_ulonglong();ex=ctypes.c_ulonglong();kt=ctypes.c_ulonglong();ut=ctypes.c_ulonglong();k.GetCurrentProcess.restype=ctypes.c_void_p
assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(creation),ctypes.byref(ex),ctypes.byref(kt),ctypes.byref(ut))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=creation.value//10)
put(R/'LOCK_OWNER.json',{'owner_run_id':'raw003-run-01','pid':os.getpid(),'process_created_utc':start.isoformat(),'mechanism':'foreground task process exclusive kernel share0 handle'})
completed=[];claim_commit=None;ack_commit=None;outcome='blocked'
def checkpoint(stage):put(R/'CHECKPOINT_LOCAL.json',{'task_id':TASK,'task_sha256':TASK_SHA,'stage':stage,'claim_commit':claim_commit,'ack_commit':ack_commit,'actual_engine_invocations':len(completed),'completed_runs':completed,'owner_run_id':'raw003-run-01','automation_enabled':True,'context_percent':None,'compact':'unavailable','utc':now(),'do_not_repeat_any_invocation':True})
def isolation_code():return '''func verify_isolation() -> bool:
\tvar root := OS.get_cmdline_user_args()[0].replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar os_dir := OS.get_user_data_dir().replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar global_dir := ProjectSettings.globalize_path("user://").replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar autoloads: Array = []
\tfor p in ProjectSettings.get_property_list():
\t\tif str(p.name).begins_with("autoload/"): autoloads.append(p.name)
\tvar isolated := os_dir.to_lower().begins_with((root+"/appdata/Godot/app_userdata/").to_lower()) and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
\tprint("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads}))
\treturn isolated
'''
def run_one(kind):
 gate('prepare_'+kind);d=R/'runs'/kind;assert not d.exists();project=d/'project';project.mkdir(parents=True)
 source_rows=load(R/'HOST_SOURCE_RESOURCE_MAP.json')
 for row in source_rows:
  p=HOST/row['path'];assert sha(p.read_bytes())==row['sha256'];dest=project/row['path'];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
 for x in task['inputs']:
  if 'project_path' in x:
   b=(R/'inputs'/x['repository_path']).read_bytes();assert sha(b)==x['sha256'];dest=project/x['project_path'];dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
 for p,h in task['baseline_project_pins'].items():assert sha((project/p).read_bytes())==h,p
 if kind=='parse':
  paths=['core/ai_gm_rebuilt/engine.gd','core/ai_gm_rebuilt/canonical.gd','tests/experimental/ai_gm_rebuilt/story_fixture.gd','tests/t03_raw_readback/io_probe.gd','tests/t03_raw_readback/test_save_file.gd']
  text='extends SceneTree\n'+isolation_code()+'''func _initialize() -> void:
\tif not verify_isolation():
\t\tquit(3)
\t\treturn
\tvar loaded: Array = []
\tvar valid := true
'''
  for path in paths:text+='\tvar resource_%d: Script = load("res://%s")\n\tvalid = valid and resource_%d != null and resource_%d.can_instantiate()\n\tloaded.append({"path":"%s","sha256":FileAccess.get_sha256("res://%s")})\n' % (len(loaded:=[]),path,0,0,path,path) if False else ''
  # Each resource uses a unique local name; load parses prototypes and never instantiates test bodies.
  for i,path in enumerate(paths):text+=f'\tvar resource_{i}: Script = load("res://{path}")\n\tvalid = valid and resource_{i} != null and resource_{i}.can_instantiate()\n\tloaded.append({{"path":"{path}","sha256":FileAccess.get_sha256("res://{path}")}})\n'
  text+='\tprint("RAW_PARSE_RESULT ",JSON.stringify({"ok":valid,"loaded":loaded,"pid":OS.get_process_id(),"entry_sha256":FileAccess.get_sha256(get_script().resource_path),"test_bodies_started":false}))\n\tquit(0 if valid else 1)\n'
  entry=task['verification']['parse_entry']
 else:
  text='extends "res://tests/t03_raw_readback/test_save_file.gd"\n'+isolation_code()+'''func _init() -> void:
\tif not verify_isolation():
\t\tquit(3)
\t\treturn
\tsuper._init()
''';entry=task['verification']['isolation_entry']
 ep=project/entry;ep.parent.mkdir(parents=True,exist_ok=True);ep.write_text(text,'utf-8')
 for part in ['data/appdata','data/localappdata','data/temp']: (d/part).mkdir(parents=True,exist_ok=True)
 before=[{'path':p.relative_to(project).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in sorted(project.rglob('*')) if p.is_file()];put(d/'SOURCE_MAP_BEFORE.json',before)
 put(d/'SPEC.json',{'executable':r'E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe','arguments':['--headless','--path',str(project),'--script','res://'+entry,'--',str(d/'data')],'working_directory':str(project),'isolated_data_root':str(d/'data'),'profile':'small','timeout_seconds':120,'log_path':str(d/'GUARD_RESULT.json')})
 gate('engine_'+kind);checkpoint('Launching '+kind+' once; do not repeat if interrupted')
 command=['pwsh','-NoProfile','-NonInteractive','-File',str(R/'Run-Test.ps1'),'-RunName','runs/'+kind,'-Attempt','actual']
 with (d/'actual_host.stdout.log').open('wb') as stdout,(d/'actual_host.stderr.log').open('wb') as stderr:
  host=subprocess.Popen(command,stdout=stdout,stderr=stderr)
  put(d/'OUTER_HOST_IDENTITY.json',{'pid':host.pid,'owned_by_task_process':os.getpid(),'recorded_utc':now()});code=host.wait()
 put(d/'HOST_EXIT.json',{'exit_code':code,'owned_host_pid':host.pid,'process_exited':host.poll() is not None,'completed_utc':now()})
 g=load(d/'GUARD_RESULT.json');(d/'stdout.log').write_text(g['Stdout'],'utf-8');(d/'stderr.log').write_text(g['Stderr'],'utf-8')
 after=[{'path':x['path'],'before_sha256':x['sha256'],'after_sha256':sha((project/x['path']).read_bytes()),'matches':sha((project/x['path']).read_bytes())==x['sha256']} for x in before];put(d/'SOURCE_MAP_AFTER.json',after)
 diagnostics=[line for line in (g['Stdout']+'\n'+g['Stderr']).splitlines() if re.search(r'(?i)(\bERROR:|\bWARNING:|\bSCRIPT ERROR|^\s*FAIL[: ])',line)]
 lines=g['Stdout'].splitlines();iso=[strict(x[len('LOCAL_SUITE_ISOLATION '):].encode()) for x in lines if x.startswith('LOCAL_SUITE_ISOLATION ')]
 strict_pass=g['Status']=='completed' and code==0 and g['GuardExitCode']==0 and g['RootExitCode']==0 and g['JobEmptyAfterRun'] and g['OutputReadersFinished'] and g['AllRecordedHandlesExited'] and not g['SyntheticFault'] and not g['OutputLimitExceeded'] and len(iso)==1 and iso[0]['isolated'] and not diagnostics and all(x['matches'] for x in after)
 if kind=='parse':
  receipts=[strict(x[len('RAW_PARSE_RESULT '):].encode()) for x in lines if x.startswith('RAW_PARSE_RESULT ')];suite=receipts[0] if len(receipts)==1 else {};strict_pass=strict_pass and suite.get('ok') and suite.get('pid')==g['RootPid'] and suite.get('entry_sha256')==sha(ep.read_bytes()) and suite.get('test_bodies_started') is False and len(suite.get('loaded',[]))==5
 else:
  receipts=[strict(x.encode()) for x in lines if x.startswith('{') and 'fault_scope' in x];suite=receipts[0] if len(receipts)==1 else {};cases=suite.get('cases',[]);names=[x['case'] for x in cases]
  strict_pass=strict_pass and suite.get('status')=='passed' and not suite.get('failures') and len(cases)==21 and len(set(names))==21 and names==task['verification']['expected_case_names'] and all(x['passed'] for x in cases) and suite.get('engine_sha256')==task['verification']['engine_sha256'] and suite.get('method_sha256')==task['verification']['save_method_sha256']
 put(d/'SUITE_RESULT.json',suite)
 result={'kind':kind,'strict_pass':bool(strict_pass),'host_exit_code':code,'host_exited':host.poll() is not None,'guard_exit_code':g['GuardExitCode'],'engine_exit_code':g['RootExitCode'],'actual_engine_pid':g['RootPid'],'entry_sha256':sha(ep.read_bytes()),'diagnostics':diagnostics,'source_mismatches':[x for x in after if not x['matches']],'source_files':len(before),'job_empty':g['JobEmptyAfterRun'],'readers_finished':g['OutputReadersFinished'],'recorded_owned_handles_exited':g['AllRecordedHandlesExited'],'isolation':iso,'job_peak_commit_bytes':g['PeakJobCommitBytes'],'physical_rss_measured':False,'admission':g['Admission'],'output_bytes':g['OutputObservedBytes'],'elapsed_seconds':g['ElapsedSeconds'],'suite':suite,'before_map_sha256':sha((d/'SOURCE_MAP_BEFORE.json').read_bytes()),'after_map_sha256':sha((d/'SOURCE_MAP_AFTER.json').read_bytes()),'guard_result_sha256':sha((d/'GUARD_RESULT.json').read_bytes())}
 put(d/'VERIFIED_RESULT.json',result);completed.append(result);checkpoint(kind+' completed');print(json.dumps({'kind':kind,'strict_pass':bool(strict_pass),'pid':g['RootPid'],'cases':len(suite.get('cases',[])),'assertions':suite.get('assertions'),'diagnostics':diagnostics}),flush=True)
 return bool(strict_pass)
try:
 h=gate('preclaim',claim=False)
 claim={'protocol':'words-and-perils-local-work/v1','kind':'claim','task_id':TASK,'task_sha256':TASK_SHA,'attempt_id':'attempt-001','owner_run_id':'raw003-run-01','owner_account_id':128279531,'intake_commit':h,'base_commit':task['base_commit'],'claimed_utc':now()};put(R/'CLAIM.json',claim)
 claim_commit=publish('CLAIM',[('coordination/local-work/results/'+TASK+'/CLAIM.json',R/'CLAIM.json')],h,'Claim exact frozen Raw readback verification task',readback_concurrency=1)
 ledger['tasks'][TASK]={'task_sha256':TASK_SHA,'owner_run_id':'raw003-run-01','attempt_id':'attempt-001','intake_commit':h,'base_commit':task['base_commit'],'claim_commit':claim_commit,'status':'claimed','terminal_for_deduplication':False,'checkpoint':str(R/'CHECKPOINT_LOCAL.json')};put(STATE/'LEDGER.json',ledger);checkpoint('Claim actual remote bytes verified')
 ack={'protocol':'words-and-perils-local-work/v1','kind':'ack','task_id':TASK,'task_sha256':TASK_SHA,'attempt_id':'attempt-001','intake_commit':h,'status':'acknowledged','automation_enabled':True,'summary':'All10 frozen inputs and formal layered public-v30 host/resources verified; unique claim readback verified. Separate Raw test-only task, no original production edits or predecessor rerun.','source_hashes':task['baseline_project_pins'],'checks':[{'input_rows':10,'host_files':verification['host_map_files'],'runtime_resource_pins':876,'baseline_variant':'BASELINE_VARIANT_PUBLIC_V30','claim_commit':claim_commit}],'blockers':[],'context':{'used_percent':None,'compact':'unavailable'},'candidate_adopted':False};put(R/'ACK.json',ack)
 h=gate('ack');ack_commit=publish('ACK',[('coordination/local-work/results/'+TASK+'/attempt-001/ACK.json',R/'ACK.json')],h,'Acknowledge frozen Raw source and accepted public-v30 baseline variant')
 ledger['tasks'][TASK].update(status='running',ack_commit=ack_commit);put(STATE/'LEDGER.json',ledger);checkpoint('ACK readback complete; parse next')
 outcome='reviewable' if run_one('parse') and run_one('suite') else 'failed'
except Exception as error:
 put(R/'EXECUTION_EXCEPTION.json',{'error':str(error),'utc':now(),'engine_runs_completed':len(completed),'no_retry_or_suite_edits':True});outcome='blocked'
finally:
 put(R/'EXECUTION_OUTCOME.json',{'task_id':TASK,'status':outcome,'completed_runs':completed,'claim_commit':claim_commit,'ack_commit':ack_commit,'maximum_engine_invocations':2,'followup_requires_new_task_id_if_runtime_failed':True,'automation_enabled':True});checkpoint('Execution '+outcome+'; publish preserved evidence next')
 if claim_commit:
  ledger=load(STATE/'LEDGER.json');ledger['tasks'][TASK].update(status='execution_'+outcome,execution_outcome=str(R/'EXECUTION_OUTCOME.json'));put(STATE/'LEDGER.json',ledger)
 put(R/'EXECUTION_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(ctypes.c_void_p(handle))),'released_utc':now(),'unknown_processes_killed':False})
print(json.dumps({'execution_outcome':outcome,'actual_engine_runs':len(completed),'claim_commit':claim_commit,'ack_commit':ack_commit}),flush=True)

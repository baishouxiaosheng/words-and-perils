import sys, os, json, ctypes, datetime, subprocess, re, hashlib, shutil
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(sys.argv[1]).resolve()
P=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a');HOST=P/'public-v30'
assert R.is_relative_to(P/'evidence') and R.name in ['run-01','run-02']
sys.path.insert(0,str(R));import task_io as q
assert q.R.resolve()==R and q.TASK in ['WP-STATUS-CLOCK-FOCUSED-20261009-004','WP-FOCUS-LOCATION-FOCUSED-20261009-005']
task=q.load(R/'TASK.json');v=task['verification'];verified=q.load(R/'INPUT_VERIFICATION.json')
assert verified['all_16_inputs_verified'] and q.sha((R/'TASK.json').read_bytes())==q.TASK_SHA
ledger=q.load(q.STATE/'LEDGER.json');assert q.TASK not in ledger['tasks'],'Known task: reconcile only'
assert not (R/'EXECUTION_OUTCOME.json').exists()
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p];k.GetCurrentProcess.restype=ctypes.c_void_p
handle=k.CreateFileW(str(q.STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None)
assert handle!=ctypes.c_void_p(-1).value,'Shared lock busy: no claim'
creation=ctypes.c_ulonglong();exit_time=ctypes.c_ulonglong();kernel=ctypes.c_ulonglong();user=ctypes.c_ulonglong()
assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(creation),ctypes.byref(exit_time),ctypes.byref(kernel),ctypes.byref(user))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=creation.value//10)
owner='focused-'+q.TASK[-3:]+'-'+R.name
q.put(R/'LOCK_OWNER.json',{'owner_run_id':owner,'pid':os.getpid(),'process_created_utc':start.isoformat(),'mechanism':'foreground execution process exclusive kernel handle'})
completed=[];static=[];claim_commit=None;ack_commit=None;outcome='blocked'
def checkpoint(stage):
 q.put(R/'CHECKPOINT_LOCAL.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'owner_run_id':owner,'stage':stage,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_engine_runs':completed,'static_checks':static,'automation_enabled':True,'context':{'used_percent':None,'compact':'unavailable'},'utc':q.now(),'do_not_repeat_recorded_launch':True})
def readonly_path(p,root):
 assert p.resolve().is_relative_to(root.resolve())
 for parent in [p,*p.parents]:
  if parent==root.parent:break
  assert not parent.is_symlink() and not (os.lstat(parent).st_file_attributes&0x400),'Reparse path'
def run_python(label,args):
 q.gate('python_'+label);d=R/'python-runs'/label;d.mkdir(parents=True,exist_ok=False)
 temp=d/'temp';temp.mkdir();readonly_path(temp,R)
 env=os.environ.copy();env['PYTHONUTF8']='1';env['TEMP']=str(temp);env['TMP']=str(temp)
 checkpoint('Python '+label+' launching once')
 with (d/'stdout.log').open('wb') as out,(d/'stderr.log').open('wb') as err:
  proc=subprocess.Popen([sys.executable,'-X','utf8',*map(str,args)],stdout=out,stderr=err,env=env)
  q.put(d/'PID.json',{'pid':proc.pid,'parent_pid':os.getpid(),'utc':q.now(),'temp_root_canonical_inside_owned_run':True});code=proc.wait()
 stdout=(d/'stdout.log').read_bytes();stderr=(d/'stderr.log').read_bytes()
 result={'label':label,'exit_code':code,'pid':proc.pid,'owned_process_exited':proc.poll() is not None,'stdout_bytes':len(stdout),'stderr_bytes':len(stderr),'script_sha256':q.sha(Path(args[0]).read_bytes()),'engine_runs':0,'runtime_counts_not_inherited':True}
 if code==0:
  packet=q.strict(stdout);q.put(d/'PARSED_RESULT.json',packet);result['static_count']=packet.get('count');result['preparation_status']=packet.get('status')
 q.put(d/'RESULT.json',result);static.append(result);checkpoint('Python '+label+' completed');print(json.dumps(result),flush=True)
 if code!=0:raise RuntimeError('Python '+label+' failed exit '+str(code)+'; preserve actual logs and stop later stages')
 return d
def isolation_code():
 return '''func verify_isolation() -> bool:
\tvar args := OS.get_cmdline_user_args()
\tif args.size() != 1:
\t\tprint("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":false,"reason":"missing trusted data-root argument"}))
\t\treturn false
\tvar root := args[0].replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar os_dir := OS.get_user_data_dir().replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar global_dir := ProjectSettings.globalize_path("user://").replace("\\\\", "/").simplify_path().trim_suffix("/")
\tvar leaf := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
\tvar expected := root+"/appdata/"+leaf
\tvar autoloads: Array = []
\tfor p in ProjectSettings.get_property_list():
\t\tif str(p.name).begins_with("autoload/"): autoloads.append(p.name)
\tvar isolated := not leaf.is_empty() and not leaf.contains("/") and not leaf.contains("\\\\") and os_dir.to_lower()==expected.to_lower() and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
\tprint("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"expected":expected,"autoloads":autoloads}))
\treturn isolated
'''
def source_map(project):
 rows=[]
 for p in sorted(project.rglob('*')):
  if p.is_file():readonly_path(p,project);rows.append({'path':p.relative_to(project).as_posix(),'bytes':p.stat().st_size,'sha256':q.sha(p.read_bytes())})
 return rows
def run_one(kind):
 q.gate('prepare_'+kind);d=R/'runs'/kind;d.mkdir(parents=True,exist_ok=False)
 package=R/'inputs'/v['test_prefix'];candidate=R/'inputs'/v['candidate_prefix']
 run_python('prepare_'+kind,[package/'prepare.py','--source-root',HOST,'--candidate-root',candidate,'--work-root',d,'--name','project'])
 project=d/'project';assert not (project/'main.gd').exists()
 original_driver=project/v['suite_entry'];assert q.sha(original_driver.read_bytes())==v['original_driver_sha256']
 assert q.sha((project/'view/playable_build/player_details.gd').read_bytes())==v['candidate_overlay_sha256']
 for part in ['appdata','localappdata','temp']:(d/'data'/part).mkdir(parents=True,exist_ok=False)
 run_entry=project/v['isolation_entry'];run_entry.write_text('extends "res://'+v['suite_entry']+'"\n'+isolation_code()+'''func _initialize() -> void:
\tif not verify_isolation():
\t\tquit(3)
\t\treturn
\tsuper._initialize()
''','utf-8')
 parse_entry=project/v['parse_entry']
 paths=['view/playable_build/player_details.gd','tests/focused/baseline_player_details.gd',v['suite_entry'],v['isolation_entry']]
 text='extends SceneTree\n'
 for i,path in enumerate(paths):text+=f'const Prototype{i} = preload("res://{path}")\n'
 text+=isolation_code()+'''func _initialize() -> void:
\tif not verify_isolation():
\t\tquit(3)
\t\treturn
\tvar loaded: Array = []
\tvar valid := true
'''
 for i,path in enumerate(paths):text+=f'\tvalid = valid and Prototype{i}.can_instantiate()\n\tloaded.append({{"path":"{path}","sha256":FileAccess.get_sha256("res://{path}")}})\n'
 text+='\tprint("FOCUSED_PARSE_RESULT ",JSON.stringify({"ok":valid,"pid":OS.get_process_id(),"loaded":loaded,"entry_sha256":FileAccess.get_sha256(get_script().resource_path),"test_bodies_started":false}))\n\tquit(0 if valid else 1)\n'
 parse_entry.write_text(text,'utf-8')
 binding=q.load(project/'tests/focused/source_binding.json')
 for entry in [v['parse_entry'],v['isolation_entry']]:
  b=(project/entry).read_bytes();binding['files'].append({'path':entry,'bytes':len(b),'sha256':q.sha(b)})
 q.put(project/'tests/focused/source_binding.json',binding)
 before=source_map(project);q.put(d/'SOURCE_MAP_BEFORE.json',before)
 entry=v['parse_entry' if kind=='parse' else 'isolation_entry']
 q.put(d/'SPEC.json',{'executable':r'E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe','arguments':['--headless','--path',str(project),'--script','res://'+entry,'--',str(d/'data')],'working_directory':str(project),'isolated_data_root':str(d/'data'),'profile':'small','timeout_seconds':120,'log_path':str(d/'GUARD_RESULT.json')})
 q.gate('engine_'+kind);checkpoint('ENGINE '+kind+' launching exactly once: do not repeat if interrupted')
 with (d/'actual_host.stdout.log').open('wb') as out,(d/'actual_host.stderr.log').open('wb') as err:
  proc=subprocess.Popen(['pwsh','-NoProfile','-NonInteractive','-File',str(R/'Run-Test.ps1'),'-RunName','runs/'+kind,'-Attempt','actual'],stdout=out,stderr=err)
  q.put(d/'OUTER_HOST_IDENTITY.json',{'pid':proc.pid,'parent_pid':os.getpid(),'utc':q.now()});code=proc.wait()
 q.put(d/'HOST_EXIT.json',{'exit_code':code,'pid':proc.pid,'process_exited':proc.poll() is not None,'utc':q.now()})
 g=q.load(d/'GUARD_RESULT.json');(d/'stdout.log').write_text(g['Stdout'],'utf-8');(d/'stderr.log').write_text(g['Stderr'],'utf-8')
 after=source_map(project);q.put(d/'SOURCE_MAP_AFTER.json',after)
 unchanged=all((project/x['path']).stat().st_size==x['bytes'] and q.sha((project/x['path']).read_bytes())==x['sha256'] for x in before)
 diagnostic=[x for x in (g['Stdout']+'\n'+g['Stderr']).splitlines() if re.search(r'(?i)(\bSCRIPT ERROR|\bERROR:|\bWARNING:|^\s*FAIL[: ])',x)]
 iso=[q.strict(x[len('LOCAL_SUITE_ISOLATION '):].encode()) for x in g['Stdout'].splitlines() if x.startswith('LOCAL_SUITE_ISOLATION ')]
 strict=g['Status']=='completed' and code==0 and g['GuardExitCode']==0 and g['RootExitCode']==0 and g['JobEmptyAfterRun'] and g['OutputReadersFinished'] and g['AllRecordedHandlesExited'] and not g['SyntheticFault'] and not g['OutputLimitExceeded'] and len(iso)==1 and iso[0]['isolated'] and not diagnostic and unchanged
 if kind=='parse':
  packets=[q.strict(x[len('FOCUSED_PARSE_RESULT '):].encode()) for x in g['Stdout'].splitlines() if x.startswith('FOCUSED_PARSE_RESULT ')];suite=packets[0] if len(packets)==1 else {}
  strict=strict and suite.get('ok') and suite.get('pid')==g['RootPid'] and suite.get('entry_sha256')==q.sha((project/entry).read_bytes()) and suite.get('test_bodies_started') is False and len(suite.get('loaded',[]))==4
 else:
  packets=[q.strict(x.encode()) for x in g['Stdout'].splitlines() if x.startswith('{') and '"suite"' in x];suite=packets[0] if len(packets)==1 else {}
  strict=strict and suite.get('suite')==v['expected_suite_name'] and suite.get('status')==v['expected_summary_status'] and suite.get('failures')==[] and type(suite.get('checks')) is int and suite['checks']>0 and suite.get('main_ui_visibility_verified') is False
 q.put(d/'SUITE_RESULT.json',suite)
 result={'kind':kind,'strict_pass':bool(strict),'actual_engine_pid':g['RootPid'],'host_pid':proc.pid,'host_exit_code':code,'host_exited':proc.poll() is not None,'guard_exit_code':g['GuardExitCode'],'engine_exit_code':g['RootExitCode'],'job_empty':g['JobEmptyAfterRun'],'readers_finished':g['OutputReadersFinished'],'recorded_handles_exited':g['AllRecordedHandlesExited'],'diagnostics':diagnostic,'isolation':iso,'source_before_after_unchanged':unchanged,'original_driver_sha256':q.sha(original_driver.read_bytes()),'candidate_overlay_sha256':q.sha((project/'view/playable_build/player_details.gd').read_bytes()),'entry_sha256':q.sha((project/entry).read_bytes()),'binding_sha256':q.sha((project/'tests/focused/source_binding.json').read_bytes()),'before_map_sha256':q.sha((d/'SOURCE_MAP_BEFORE.json').read_bytes()),'after_map_sha256':q.sha((d/'SOURCE_MAP_AFTER.json').read_bytes()),'job_peak_commit_bytes':g['PeakJobCommitBytes'],'physical_rss_measured':False,'admission':g['Admission'],'elapsed_seconds':g['ElapsedSeconds'],'output_bytes':g['OutputObservedBytes'],'suite':suite}
 q.put(d/'VERIFIED_RESULT.json',result);completed.append(result);checkpoint(kind+' completed');print(json.dumps({'kind':kind,'strict_pass':bool(strict),'pid':g['RootPid'],'actual_suite_checks':suite.get('checks'),'diagnostics':diagnostic}),flush=True)
 return bool(strict)
try:
 h=q.gate('preclaim',claim=False)
 if v.get('predecessor_terminal_task_id'):
  pred=q.load(q.STATE/'LEDGER.json')['tasks'][v['predecessor_terminal_task_id']];assert pred['terminal_for_deduplication'] and pred['safe_cleanup']['shared_lock_free_verified'] and pred['safe_cleanup']['publication_exited']
  remote=q.strict(q.blob(h,'coordination/local-work/results/'+v['predecessor_terminal_task_id']+'/attempt-001/RESULT.json'));assert remote['task_sha256']==pred['task_sha256'] and remote['status'] in ['reviewable','failed','blocked','stopped']
 q.put(R/'CLAIM.json',{'protocol':'words-and-perils-local-work/v1','kind':'claim','task_id':q.TASK,'task_sha256':q.TASK_SHA,'attempt_id':'attempt-001','owner_run_id':owner,'owner_account_id':128279531,'intake_commit':h,'base_commit':task['base_commit'],'claimed_utc':q.now()})
 claim_commit=q.publish('CLAIM',[('coordination/local-work/results/'+q.TASK+'/CLAIM.json',R/'CLAIM.json')],h,'Claim independent focused formatter task '+q.TASK[-3:])
 ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK]={'task_sha256':q.TASK_SHA,'owner_run_id':owner,'status':'claimed','terminal_for_deduplication':False,'claim_commit':claim_commit,'intake_commit':h,'base_commit':task['base_commit'],'checkpoint':str(R/'CHECKPOINT_LOCAL.json')};q.put(q.STATE/'LEDGER.json',ledger);checkpoint('unique CLAIM actual readback complete')
 q.put(R/'ACK.json',{'protocol':'words-and-perils-local-work/v1','kind':'ack','task_id':q.TASK,'task_sha256':q.TASK_SHA,'attempt_id':'attempt-001','intake_commit':h,'status':'acknowledged','automation_enabled':True,'summary':'Accepted local scope/new root pins,16 immutable inputs,actual acceptance receipts and formal layered source map verified. Only independent formatter host; no Main/UI visibility/adoption or production edits.','source_hashes':task['baseline_project_pins'],'checks':[{'claim_commit':claim_commit,'all_16_inputs_verified':True,'source_map_sha256':verified['source_map_sha256']}],'blockers':[],'context':{'used_percent':None,'compact':'unavailable'},'candidate_adopted':False})
 h=q.gate('ack');ack_commit=q.publish('ACK',[('coordination/local-work/results/'+q.TASK+'/attempt-001/ACK.json',R/'ACK.json')],h,'ACK exact focused inputs and scope acceptance')
 ledger['tasks'][q.TASK].update(status='running',ack_commit=ack_commit);q.put(q.STATE/'LEDGER.json',ledger);checkpoint('ACK readback complete')
 package=R/'inputs'/v['test_prefix'];candidate=R/'inputs'/v['candidate_prefix']
 run_python('candidate_static',[candidate/'check_static.py','--restored-root',HOST])
 run_python('package_static',[package/'check_static.py','--source-root',HOST,'--candidate-root',candidate])
 outcome='reviewable' if run_one('parse') and run_one('suite') else 'failed'
except Exception as e:
 q.put(R/'EXECUTION_EXCEPTION.json',{'error':str(e),'completed_engine_runs':len(completed),'no_stage_retry':True,'utc':q.now()});outcome='blocked' if not completed else 'failed'
finally:
 result={'task_id':q.TASK,'task_sha256':q.TASK_SHA,'status':outcome,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_runs':completed,'static_runs':static,'maximum_engine_invocations':2,'same_task_rerun_forbidden':True,'automation_enabled':True}
 q.put(R/'EXECUTION_OUTCOME.json',result);checkpoint('Execution '+outcome+'; publication next')
 if claim_commit:
  ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK].update(status='execution_'+outcome,execution_outcome=str(R/'EXECUTION_OUTCOME.json'));q.put(q.STATE/'LEDGER.json',ledger)
 q.put(R/'EXECUTION_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(handle)),'released_utc':q.now(),'unknown_processes_killed':False})
print(json.dumps({'execution_outcome':outcome,'actual_engine_runs':len(completed),'claim_commit':claim_commit,'ack_commit':ack_commit}),flush=True)

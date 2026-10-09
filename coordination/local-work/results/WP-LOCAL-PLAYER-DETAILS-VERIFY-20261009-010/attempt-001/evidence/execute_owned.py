import sys,os,json,ctypes,datetime,subprocess,re,hashlib,shutil,ast,difflib
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R));import task_io as q
P=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a');HOST=P/'public-v30'
task=q.load(R/'TASK.json');assert q.sha((R/'TASK.json').read_bytes())==q.TASK_SHA
assert q.TASK not in q.load(q.STATE/'LEDGER.json')['tasks']
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.GetCurrentProcess.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p]
handle=k.CreateFileW(str(q.STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None)
assert handle!=ctypes.c_void_p(-1).value,'Other active writer: stop'
created=ctypes.c_ulonglong();ex=ctypes.c_ulonglong();kr=ctypes.c_ulonglong();us=ctypes.c_ulonglong()
assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(created),ctypes.byref(ex),ctypes.byref(kr),ctypes.byref(us))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=created.value//10)
owner='direct-owner-local-010'
q.put(R/'LOCK_OWNER.json',{'pid':os.getpid(),'process_created_utc':start.isoformat(),'owner_run_id':owner})
completed=[];static=[];claim_commit=None;ack_commit=None;outcome='blocked';v={}
def checkpoint(stage):
 q.put(R/'CHECKPOINT_LOCAL.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'stage':stage,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_engine_runs':completed,'static_checks':static,'utc':q.now(),'context':{'used_percent':None,'compact':'unavailable'},'do_not_repeat_recorded_launch':True})

# Reuse reviewed run/isolation/source verification functions, not old task execution.
old_path=q.STATE/'focused_queue_run_20261009_v3_tasks008009.py'
original=old_path.read_text('utf-8');module=ast.parse(original)
function_names=['readonly_path','run_python','isolation_code','source_map','run_one']
for node in module.body:
 if isinstance(node,ast.FunctionDef) and node.name in function_names:
  source=ast.get_source_segment(original,node)
  if node.name=='run_python':
   source=source.replace('code=proc.wait()','code=proc.wait(timeout=120)')
  if node.name=='run_one':
   source=source.replace("d=R/'runs'/kind","d=R/'runs'/v['label']/kind")
   source=source.replace("package=R/'inputs'/v['test_prefix']","package=R/'portable-packages'/v['label']")
   source=source.replace("run_python('prepare_'+kind", "run_python('prepare_'+v['label']+'_'+kind")
   source=source.replace("'-RunName','runs/'+kind", "'-RunName','runs/'+v['label']+'/'+kind")
   source=source.replace("'prepare_'+kind", "'prepare_'+v['label']+'_'+kind")
   source=source.replace("'engine_'+kind", "'engine_'+v['label']+'_'+kind")
   source=source.replace("'kind':kind,'strict_pass'", "'kind':v['label']+'_'+kind,'strict_pass'")
  exec(compile(source,str(R/'REUSED_VERIFICATION_FUNCTIONS.py'),'exec'),globals())

def repair_package(suite):
 label=suite['label'];source=R/'inputs'/suite['package'];dest=R/'portable-packages'/label
 shutil.copytree(source,dest)
 prepare=dest/'prepare.py';before=prepare.read_text('utf8')
 changed=before.replace('import re\n','import re\nimport os\n')
 changed=changed.replace('any(p.is_symlink() for p in (path, *path.parents))','any(p.is_symlink() or (p.exists() and (os.lstat(p).st_file_attributes & 0x400)) for p in (path, *path.parents))')
 prepare.write_text(changed,'utf8',newline='\n')
 manifest=q.load(dest/'TEST_MANIFEST.json')
 for pin in manifest['package_files']:
  if pin['path']=='prepare.py':pin.update(bytes=prepare.stat().st_size,sha256=q.sha(prepare.read_bytes()))
 manifest['local_test_revision']={'task_id':q.TASK,'change':'Refuse all Windows reparse components; no privilege changes; explicit unavailable symlink fixtures only','original_prepare_sha256':q.sha(before.encode())}
 q.put(dest/'TEST_MANIFEST.json',manifest)
 checker=dest/'check_static.py'
 if checker.exists():
  before_check=checker.read_text('utf8')
  changed_check=before_check.replace('    args = parser.parse_args()','    parser.add_argument("--symlink-fixture-mode", choices=["required", "unavailable"], default="required")\n    args = parser.parse_args()')
  changed_check=changed_check.replace('    checks = []','    checks = []\n    not_run = []')
  changed_check=changed_check.replace('{"argparse", "hashlib", "json", "re"}','{"argparse", "hashlib", "json", "re", "os"}')
  blocks=[('        link = work / "linked-output"\n','        bad_source = work / "tampered-source"\n','symlink output refused'),('        target.unlink()\n','        bad_candidate = work / "tampered-candidate"\n','symlink source refused before output creation')]
  for begin,end,label_ in blocks:
   a=changed_check.index(begin);b=changed_check.index(end,a);old_block=changed_check[a:b]
   replacement='        if args.symlink_fixture_mode == "unavailable":\n            not_run.append({"name": '+repr(label_)+', "status": "NOT_RUN", "reason": "Previously observed WinError1314; owner forbids repeating privileged fixture creation"})\n        else:\n'+''.join('    '+line if line.strip() else line for line in old_block.splitlines(keepends=True))
   changed_check=changed_check[:a]+replacement+changed_check[b:]
  changed_check=changed_check.replace('"status": "PASSED_STATIC_AND_PYTHON_PREPARATION_ONLY",','"status": "PASSED_AVAILABLE_STATIC_AND_PREPARATION_WITH_NOT_RUN_NEGATIVES" if not_run else "PASSED_STATIC_AND_PYTHON_PREPARATION_ONLY", "not_run": not_run, "all_negative_cases_executed": not not_run,')
  checker.write_text(changed_check,'utf8',newline='\n')
  (R/'diffs').mkdir(exist_ok=True)
  (R/'diffs'/(suite['label']+'_checker.patch')).write_text(''.join(difflib.unified_diff(before_check.splitlines(True),changed_check.splitlines(True),fromfile='original/check_static.py',tofile='portable/check_static.py')),'utf8')
  assert 'link.symlink_to' in changed_check and 'target.symlink_to' in changed_check,'Original negative assertions retained on supported hosts'
 (R/'diffs').mkdir(exist_ok=True)
 (R/'diffs'/(suite['label']+'_prepare.patch')).write_text(''.join(difflib.unified_diff(before.splitlines(True),changed.splitlines(True),fromfile='original/prepare.py',tofile='portable/prepare.py')),'utf8')
 for py in dest.glob('*.py'):ast.parse(py.read_text('utf8'))
 return dest

try:
 # Direct human's continuing policy supersedes technical-network latch only.
 q.lock_check();q.git('fetch','--no-tags','origin','refs/heads/main');h=q.git('rev-parse','FETCH_HEAD').decode().strip();t=q.tree(h)
 assert not (q.STATE/'STOP').exists() and 'coordination/local-work/STOP' not in t
 cfg=q.load(q.STATE/'QUEUE_CONFIG.v2.json');ctrl=q.strict(q.blob(h,'coordination/local-work/CONTROL.json'))
 assert set(ctrl)=={'protocol','kind','queue_enabled','stop','resume_generation','reason'} and ctrl['queue_enabled'] is True and ctrl['stop'] is False and type(ctrl['resume_generation']) is int and ctrl['resume_generation']>=0
 for name,pin in [('PROTOCOL.json',q.PROTOCOL_SHA),('TASK_SCHEMA.json',q.SCHEMA_SHA)]:assert q.sha(q.blob(h,'coordination/local-work/'+name))==pin
 acceptance=Path(cfg['scope_extension']['acceptance_receipt_local']);assert q.sha(acceptance.read_bytes())=='cc89e53a90eb85e0f21831883d7a2d836a3b03c0912405b4742280d486f5083f'
 latch=q.STATE/'STOP-LATCH.json';assert q.sha(latch.read_bytes())=='212e353c8a056e236f0ee9dd511221f507ac86f67342b0710b4a9a7ebc2b5db2'
 receipt=q.load(latch);assert 'SSL_ERROR_SYSCALL' in receipt['error'] and receipt['boundary']=='final_completion'
 (R/'policy').mkdir();(R/'policy/ORIGINAL_NETWORK_LATCH.json').write_bytes(latch.read_bytes());(R/'policy/CONFIG_BEFORE.json').write_bytes((q.STATE/'QUEUE_CONFIG.v2.json').read_bytes());(R/'policy/LEDGER_BEFORE.json').write_bytes((q.STATE/'LEDGER.json').read_bytes())
 policy={'direct_owner_authorized':True,'accepted_utc':q.now(),'network_failure':'Pause affected task, do not launch new tasks this round; bounded read-only recovery; on later network restoration verify ALL admissions before resuming','protected_stops':['user STOP','cancel','real approval or operation rejection','source/identity failure'],'network_return_never_clears_protected_stop':True,'unchanged_old_terminal_results':True,'cleared_exact_network_latch_sha256':q.sha(latch.read_bytes()),'fresh_head':h,'control':ctrl}
 q.put(R/'policy/OWNER_POLICY_ACCEPTANCE.json',policy)
 cfg['network_recovery_policy']=policy;cfg['direct_owner_current_work_authority']='Cross-platform test-fixture repair and fixed clock/location combined candidate verification with guarded focused GUI capture; no formal adoption'
 cfg['queue_runtime_state']='active_after_verified_direct_owner_continuing_network_policy';q.put(q.STATE/'QUEUE_CONFIG.v2.json',cfg);assert q.load(q.STATE/'QUEUE_CONFIG.v2.json')==cfg
 q.put(q.STATE/'OWNER_NETWORK_POLICY_20261009.json',policy)
 latch.unlink()
 with (q.STATE/'QUEUE_HANDOFF.txt').open('a',encoding='utf8') as f:f.write('\nDirect owner continuing authorization supersedes technical-network-only latch handling. Read OWNER_NETWORK_POLICY_20261009.json before future gates. Network faults pause affected task/no new task this round; later fresh full admission may resume, unlike user STOP/cancel/real rejection/source-identity failure which remain protected. Current direct task010 repairs NEW fixture packages and verifies fixed clock/location/combined plus guarded focused GUI. Automatic inbox scope/pins remain unchanged; task files never update rules.\n')
 h=q.gate('preclaim',claim=False)
 q.put(R/'CLAIM.json',{'protocol':'words-and-perils-local-work/v1','kind':'claim','task_id':q.TASK,'task_sha256':q.TASK_SHA,'attempt_id':'attempt-001','owner_run_id':owner,'owner_account_id':128279531,'intake_commit':h,'base_commit':task['base_commit'],'claimed_utc':q.now(),'authority':'direct current human instruction; this is not an inbox policy expansion'})
 prefix='coordination/local-work/results/'+q.TASK+'/'
 claim_commit=q.publish('CLAIM',[(prefix+'TASK.json',R/'TASK.json'),(prefix+'CLAIM.json',R/'CLAIM.json')],h,'Claim direct owner-authorized portable fixture and player-details verification')
 ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK]={'task_sha256':q.TASK_SHA,'status':'claimed','terminal_for_deduplication':False,'owner_run_id':owner,'claim_commit':claim_commit,'base_commit':task['base_commit'],'checkpoint':str(R/'CHECKPOINT_LOCAL.json')};q.put(q.STATE/'LEDGER.json',ledger);checkpoint('Claim real bytes verified')
 q.put(R/'ACK.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'claim_commit':claim_commit,'intake_commit':h,'status':'acknowledged','all_inputs_verified':True,'old_tasks_not_rerun':True,'source_binding':q.load(R/'INPUT_VERIFICATION.json')})
 h=q.gate('ack');ack_commit=q.publish('ACK',[(prefix+'attempt-001/ACK.json',R/'ACK.json')],h,'ACK exact source pins and non-privileged fixture revision')
 ledger['tasks'][q.TASK].update(status='running',ack_commit=ack_commit);q.put(q.STATE/'LEDGER.json',ledger)
 for suite in task['suites']:
  package=repair_package(suite);candidate=R/'inputs'/suite['candidate'];inputs=suite['inputs'];driver=package/inputs['test_entry']
  match=re.search(r'"suite": "([^"]+)"',driver.read_text('utf8'));assert match
  v={'label':suite['label'],'test_prefix':suite['package'],'candidate_prefix':suite['candidate'],'suite_entry':inputs['prepared_test_path'],'isolation_entry':'tests/focused/local_isolated.gd','parse_entry':'tests/focused/local_parse.gd','original_driver_sha256':q.sha(driver.read_bytes()),'candidate_overlay_sha256':q.sha((candidate/inputs['overlay_path']).read_bytes()),'expected_suite_name':match.group(1),'expected_summary_status':'UNIT_PASSED'}
  if suite['label']=='combined':run_python('combined_candidate_static',[candidate/'check_static.py','--restored-root',HOST])
  else:
   replay=R/'replay-evidence'/suite['label'];replay.mkdir(parents=True)
   run_python(suite['label']+'_candidate_static',[candidate/'check_static.py','--restored-root',HOST,'--replay-evidence-root',replay])
   run_python(suite['label']+'_package_static',[package/'check_static.py','--source-root',HOST,'--candidate-root',candidate,'--symlink-fixture-mode','unavailable'])
  if not run_one('parse'):raise RuntimeError(suite['label']+' parse failed; no suite or dependent stage')
  if not run_one('suite'):raise RuntimeError(suite['label']+' suite failed; stop dependent combination/GUI')
 outcome='reviewable'
 checkpoint('All three independent source-bound parse/suite pairs complete; guarded focused GUI next')
except Exception as e:
 q.put(R/'EXECUTION_EXCEPTION.json',{'error':str(e),'completed_engine_runs':len(completed),'utc':q.now(),'no_unchanged_stage_retry':True});print('EXECUTION_EXCEPTION',str(e),flush=True)
 outcome='failed' if completed or any(x.get('exit_code')!=0 for x in static) else 'blocked'
finally:
 q.put(R/'EXECUTION_OUTCOME.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'status':outcome,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_runs':completed,'static_runs':static,'gui':'NOT_RUN_YET','symlink_negative_cases':'NOT_RUN; no privileged operation retried','formal_adoption':False})
 checkpoint('Engine phase '+outcome)
 if claim_commit:
  ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK].update(status='execution_'+outcome,execution_outcome=str(R/'EXECUTION_OUTCOME.json'));q.put(q.STATE/'LEDGER.json',ledger)
 q.put(R/'EXECUTION_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(handle)),'utc':q.now(),'unknown_processes_killed':False})
print(json.dumps({'status':outcome,'actual_engine_runs':len(completed),'claim_commit':claim_commit,'ack_commit':ack_commit}),flush=True)

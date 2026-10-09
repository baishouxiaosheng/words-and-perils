import sys,os,json,ctypes,datetime,subprocess,re,hashlib,shutil,ast,difflib
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R));import task_io as q
P=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a');HOST=P/'public-v30'
task=q.load(R/'TASK.json');prior=q.load(R/'EXECUTION_OUTCOME.json')
assert prior['completed_runs']==[] and len(prior['static_runs'])==2 and prior['static_runs'][0]['exit_code']==0 and prior['static_runs'][1]['exit_code']==1
assert 'exact test package check_static.py' in (R/'python-runs/clock_package_static/stderr.log').read_text('utf8')
archive=R/'retained-revision1';archive.mkdir()
for name in ['EXECUTION_OUTCOME.json','EXECUTION_EXCEPTION.json','CHECKPOINT_LOCAL.json','EXECUTION_LOCK_RELEASED.json']:(archive/name).write_bytes((R/name).read_bytes())
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.GetCurrentProcess.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p]
handle=k.CreateFileW(str(q.STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None);assert handle!=ctypes.c_void_p(-1).value
created=ctypes.c_ulonglong();ex=ctypes.c_ulonglong();kr=ctypes.c_ulonglong();us=ctypes.c_ulonglong()
assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(created),ctypes.byref(ex),ctypes.byref(kr),ctypes.byref(us))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=created.value//10)
q.put(R/'LOCK_OWNER.json',{'pid':os.getpid(),'process_created_utc':start.isoformat(),'owner_run_id':'direct-owner-local-010-revision2'})
completed=[];static=prior['static_runs'][:];claim_commit=prior['claim_commit'];ack_commit=prior['ack_commit'];v={};outcome='blocked'
original=(R/'execute_owned.py').read_text('utf8')
node=next(n for n in ast.parse(original).body if isinstance(n,ast.FunctionDef) and n.name=='checkpoint');exec(compile(ast.get_source_segment(original,node),__file__,'exec'),globals())
old=(q.STATE/'focused_queue_run_20261009_v3_tasks008009.py').read_text('utf8')
sources=[]
for n in ast.parse(old).body:
 if isinstance(n,ast.FunctionDef) and n.name in ['readonly_path','run_python','isolation_code','source_map','run_one']:
  source=ast.get_source_segment(old,n)
  if n.name=='run_one':
   source=source.replace("d=R/'runs'/kind","d=R/'runs'/v['label']/kind").replace("package=R/'inputs'/v['test_prefix']","package=R/'portable-packages-v2'/v['label']")
   source=source.replace("run_python('prepare_'+kind", "run_python('prepare_'+v['label']+'_'+kind").replace("'-RunName','runs/'+kind","'-RunName','runs/'+v['label']+'/'+kind")
   source=source.replace("'prepare_'+kind","'prepare_'+v['label']+'_'+kind").replace("'engine_'+kind","'engine_'+v['label']+'_'+kind").replace("'kind':kind,'strict_pass'","'kind':v['label']+'_'+kind,'strict_pass'")
  sources.append(source)
  exec(compile(source,__file__,'exec'),globals())
(R/'REUSED_VERIFICATION_FUNCTIONS.py').write_text('\n\n'.join(sources),'utf8')
node=next(n for n in ast.parse(original).body if isinstance(n,ast.FunctionDef) and n.name=='repair_package')
source=ast.get_source_segment(original,node).replace("dest=R/'portable-packages'/label","dest=R/'portable-packages-v2'/label")
source=source.replace('(os.lstat(p).st_file_attributes & 0x400)','(getattr(os.lstat(p), "st_file_attributes", 0) & 0x400)')
source=source.replace("'original_prepare_sha256':q.sha(before.encode())","'original_prepare_sha256':q.sha((R/'inputs'/suite['package']/'prepare.py').read_bytes())")
# Bind every actually changed package file AFTER modifications, never weakening pins.
source=source.replace(" for py in dest.glob('*.py'):ast.parse(py.read_text('utf8'))", " for pin in manifest['package_files']:\n  bound=(dest/pin['path']).read_bytes();pin.update(bytes=len(bound),sha256=q.sha(bound))\n q.put(dest/'TEST_MANIFEST.json',manifest)\n for py in dest.glob('*.py'):ast.parse(py.read_text('utf8'))")
exec(compile(source,__file__,'exec'),globals())
try:
 q.gate('revision2_resume');assert q.load(q.STATE/'LEDGER.json')['tasks'][q.TASK]['claim_commit']==claim_commit
 q.put(R/'TEST_REVISION2_CORRECTION.json',{'prior_failure':'Revised checker pin was not refreshed in new test manifest','fix':'Refresh exact bytes/SHA for changed checker after all source edits; Windows reparse inspection uses portable getattr','assertions_weakened':False,'original_manifest_changed':False,'old_logs_retained':True,'production_source_changes':0,'godot_runs_before_fix':0})
 for suite in task['suites']:
  package=repair_package(suite);candidate=R/'inputs'/suite['candidate'];inputs=suite['inputs'];driver=package/inputs['test_entry']
  match=re.search(r'"suite": "([^"]+)"',driver.read_text('utf8'));assert match
  v={'label':suite['label'],'test_prefix':suite['package'],'candidate_prefix':suite['candidate'],'suite_entry':inputs['prepared_test_path'],'isolation_entry':'tests/focused/local_isolated.gd','parse_entry':'tests/focused/local_parse.gd','original_driver_sha256':q.sha(driver.read_bytes()),'candidate_overlay_sha256':q.sha((candidate/inputs['overlay_path']).read_bytes()),'expected_suite_name':match.group(1),'expected_summary_status':'UNIT_PASSED'}
  if suite['label']=='combined':run_python('combined_candidate_static',[candidate/'check_static.py','--restored-root',HOST])
  else:
   if suite['label']!='clock':
    replay=R/'replay-evidence'/suite['label'];replay.mkdir(parents=True)
    run_python(suite['label']+'_candidate_static',[candidate/'check_static.py','--restored-root',HOST,'--replay-evidence-root',replay])
   run_python(suite['label']+'_package_static_revision2',[package/'check_static.py','--source-root',HOST,'--candidate-root',candidate,'--symlink-fixture-mode','unavailable'])
  if not run_one('parse'):raise RuntimeError(suite['label']+' parse failed')
  if not run_one('suite'):raise RuntimeError(suite['label']+' suite failed')
 outcome='reviewable';checkpoint('Source-bound headless complete; GUI next')
except Exception as e:
 q.put(R/'REVISION2_EXCEPTION.json',{'error':str(e),'engine_runs':len(completed),'utc':q.now()});print('REVISION2_EXCEPTION',str(e),flush=True);outcome='failed'
finally:
 q.put(R/'EXECUTION_OUTCOME.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'status':outcome,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_runs':completed,'static_runs':static,'test_revision':2,'gui':'NOT_RUN_YET','symlink_negatives':'NOT_RUN explicit; no privileged attempts','candidate_adopted':False})
 checkpoint('Revision2 '+outcome)
 ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK].update(status='execution_'+outcome,execution_outcome=str(R/'EXECUTION_OUTCOME.json'));q.put(q.STATE/'LEDGER.json',ledger)
 q.put(R/'REVISION2_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(handle)),'utc':q.now()})
print(json.dumps({'outcome':outcome,'new_engine_runs':len(completed)}),flush=True)

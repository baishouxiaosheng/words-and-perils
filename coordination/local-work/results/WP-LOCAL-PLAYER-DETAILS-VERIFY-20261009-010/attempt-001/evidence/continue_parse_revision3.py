import sys,os,json,ctypes,datetime,subprocess,re,hashlib,shutil,ast,difflib
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R));import task_io as q
P=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a');HOST=P/'public-v30'
task=q.load(R/'TASK.json');prior=q.load(R/'EXECUTION_OUTCOME.json')
assert len(prior['completed_runs'])==1 and not prior['completed_runs'][0]['strict_pass']
assert 'Cannot call non-static function' in '\n'.join(prior['completed_runs'][0]['diagnostics'])
archive=R/'retained-revision2';archive.mkdir()
for name in ['EXECUTION_OUTCOME.json','CHECKPOINT_LOCAL.json']:(archive/name).write_bytes((R/name).read_bytes())
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.GetCurrentProcess.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p]
handle=k.CreateFileW(str(q.STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None);assert handle!=ctypes.c_void_p(-1).value
created=ctypes.c_ulonglong();ex=ctypes.c_ulonglong();kr=ctypes.c_ulonglong();us=ctypes.c_ulonglong()
assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(created),ctypes.byref(ex),ctypes.byref(kr),ctypes.byref(us))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=created.value//10)
q.put(R/'LOCK_OWNER.json',{'pid':os.getpid(),'process_created_utc':start.isoformat(),'owner_run_id':'direct-owner-local-010-revision3'})
completed=prior['completed_runs'][:];static=prior['static_runs'][:];claim_commit=prior['claim_commit'];ack_commit=prior['ack_commit'];v={};outcome='blocked'
src=(R/'execute_owned.py').read_text('utf8')
node=next(n for n in ast.parse(src).body if isinstance(n,ast.FunctionDef) and n.name=='checkpoint');exec(compile(ast.get_source_segment(src,node),__file__,'exec'),globals())
functions=(R/'REUSED_VERIFICATION_FUNCTIONS.py').read_text('utf8')
functions=functions.replace("package=R/'portable-packages-v2'/v['label']","package=R/'portable-packages-v2'/v['package_label']")
old="text+=f'\\tvalid = valid and Prototype{i}.can_instantiate()\\n\\tloaded.append({{\"path\":\"{path}\",\"sha256\":FileAccess.get_sha256(\"res://{path}\")}})\\n'"
new="text+=f'\\tvar loaded_script{i}: Script = load(\"res://{path}\")\\n\\tvalid = valid and loaded_script{i} != null and loaded_script{i}.can_instantiate()\\n\\tloaded.append({{\"path\":\"{path}\",\"sha256\":FileAccess.get_sha256(\"res://{path}\")}})\\n'"
assert old in functions
functions=functions.replace(old,new)
(R/'REUSED_VERIFICATION_FUNCTIONS_REVISION3.py').write_text(functions,'utf8')
exec(compile(functions,__file__,'exec'),globals())
src=(R/'continue_verified_revision2.py').read_text('utf8')
node=next(n for n in ast.parse(src).body if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Name) and n.value.func.id=='exec') if False else None
# Only the reviewed repair function is needed for packages not yet prepared.
repair_src=(R/'execute_owned.py').read_text('utf8');node=next(n for n in ast.parse(repair_src).body if isinstance(n,ast.FunctionDef) and n.name=='repair_package')
repair=ast.get_source_segment(repair_src,node).replace("dest=R/'portable-packages'/label","dest=R/'portable-packages-v2'/label")
repair=repair.replace('(os.lstat(p).st_file_attributes & 0x400)','(getattr(os.lstat(p), "st_file_attributes", 0) & 0x400)')
repair=repair.replace("'original_prepare_sha256':q.sha(before.encode())","'original_prepare_sha256':q.sha((R/'inputs'/suite['package']/'prepare.py').read_bytes())")
repair=repair.replace(" for py in dest.glob('*.py'):ast.parse(py.read_text('utf8'))", " for pin in manifest['package_files']:\n  bound=(dest/pin['path']).read_bytes();pin.update(bytes=len(bound),sha256=q.sha(bound))\n q.put(dest/'TEST_MANIFEST.json',manifest)\n for py in dest.glob('*.py'):ast.parse(py.read_text('utf8'))")
exec(compile(repair,__file__,'exec'),globals())
try:
 q.gate('revision3_resume')
 q.put(R/'PARSE_WRAPPER_REVISION3.json',{'failure':'Preloaded GDScript class cannot call non-static Script.can_instantiate directly','fix':'After double-API isolation, load each existing script as typed Script object and call can_instantiate without creating test instances','new_disposable_parse_copy':True,'original_failed_logs_retained':True,'assertions_weakened':False,'production_or_driver_changes':False})
 for suite in task['suites']:
  label=suite['label'];package=R/'portable-packages-v2'/label
  if label!='clock':package=repair_package(suite)
  candidate=R/'inputs'/suite['candidate'];inputs=suite['inputs'];driver=package/inputs['test_entry'];match=re.search(r'"suite": "([^"]+)"',driver.read_text('utf8'));assert match
  v={'label':label+'-revision3','package_label':label,'candidate_prefix':suite['candidate'],'suite_entry':inputs['prepared_test_path'],'isolation_entry':'tests/focused/local_isolated.gd','parse_entry':'tests/focused/local_parse.gd','original_driver_sha256':q.sha(driver.read_bytes()),'candidate_overlay_sha256':q.sha((candidate/inputs['overlay_path']).read_bytes()),'expected_suite_name':match.group(1),'expected_summary_status':'UNIT_PASSED'}
  if label=='combined':run_python('combined_candidate_static',[candidate/'check_static.py','--restored-root',HOST])
  elif label!='clock':
   replay=R/'replay-evidence'/label;replay.mkdir(parents=True)
   run_python(label+'_candidate_static',[candidate/'check_static.py','--restored-root',HOST,'--replay-evidence-root',replay])
   run_python(label+'_package_static_revision2',[package/'check_static.py','--source-root',HOST,'--candidate-root',candidate,'--symlink-fixture-mode','unavailable'])
  if not run_one('parse'):raise RuntimeError(label+' revised parse failed')
  if not run_one('suite'):raise RuntimeError(label+' suite failed')
 outcome='reviewable';checkpoint('All corrected parse/suite pairs passed; focused GUI next')
except Exception as e:
 q.put(R/'REVISION3_EXCEPTION.json',{'error':str(e),'engine_runs':len(completed),'utc':q.now()});print('REVISION3_EXCEPTION',str(e),flush=True);outcome='failed'
finally:
 q.put(R/'EXECUTION_OUTCOME.json',{'task_id':q.TASK,'task_sha256':q.TASK_SHA,'status':outcome,'claim_commit':claim_commit,'ack_commit':ack_commit,'completed_runs':completed,'static_runs':static,'test_revision':3,'gui':'NOT_RUN_YET','symlink_negatives':'NOT_RUN explicit; no privileged attempts','candidate_adopted':False})
 checkpoint('Revision3 '+outcome)
 ledger=q.load(q.STATE/'LEDGER.json');ledger['tasks'][q.TASK].update(status='execution_'+outcome);q.put(q.STATE/'LEDGER.json',ledger)
 q.put(R/'REVISION3_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(handle)),'utc':q.now()})
print(json.dumps({'outcome':outcome,'all_actual_engine_runs':len(completed)}),flush=True)

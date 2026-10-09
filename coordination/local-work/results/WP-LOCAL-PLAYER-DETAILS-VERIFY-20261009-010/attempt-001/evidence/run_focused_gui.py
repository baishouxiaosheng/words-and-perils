import sys,os,json,ctypes,datetime,subprocess,re,hashlib,shutil,ast
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R));import task_io as q
P=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a');HOST=P/'public-v30'
prior=q.load(R/'EXECUTION_OUTCOME.json');assert prior['status']=='reviewable' and len(prior['completed_runs'])==7 and all(x['strict_pass'] for x in prior['completed_runs'][1:])
k=ctypes.WinDLL('kernel32',use_last_error=True);k.CreateFileW.restype=ctypes.c_void_p;k.GetCurrentProcess.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p]
handle=k.CreateFileW(str(q.STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None);assert handle!=ctypes.c_void_p(-1).value
created=ctypes.c_ulonglong();ex=ctypes.c_ulonglong();kr=ctypes.c_ulonglong();us=ctypes.c_ulonglong();assert k.GetProcessTimes(ctypes.c_void_p(k.GetCurrentProcess()),ctypes.byref(created),ctypes.byref(ex),ctypes.byref(kr),ctypes.byref(us))
start=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=created.value//10)
q.put(R/'LOCK_OWNER.json',{'pid':os.getpid(),'process_created_utc':start.isoformat(),'owner_run_id':'direct-owner-local-010-focused-gui'})
namespace={'R':R,'q':q,'Path':Path,'os':os};function_src=(R/'REUSED_VERIFICATION_FUNCTIONS_REVISION3.py').read_text('utf8')
for node in ast.parse(function_src).body:
 if isinstance(node,ast.FunctionDef) and node.name in ['readonly_path','source_map','isolation_code']:exec(compile(ast.get_source_segment(function_src,node),__file__,'exec'),namespace)
source_map=namespace['source_map'];isolation_code=namespace['isolation_code'];runs=[]
def launch(label,project,data,entry,headless):
 d=R/'runs'/label;d.mkdir(parents=True)
 for part in ['appdata','localappdata','temp']:(data/part).mkdir(parents=True,exist_ok=False)
 before=source_map(project);q.put(d/'SOURCE_MAP_BEFORE.json',before)
 args=(['--headless'] if headless else [])+['--path',str(project),'--script','res://'+entry]
 if not headless:args+=['--fixed-fps','15']
 args+=['--',str(data)]
 q.put(d/'SPEC.json',{'executable':r'E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe','arguments':args,'working_directory':str(project),'isolated_data_root':str(data),'profile':'small','timeout_seconds':120,'log_path':str(d/'GUARD_RESULT.json')})
 q.gate('engine_'+label)
 with (d/'host.stdout.log').open('wb') as out,(d/'host.stderr.log').open('wb') as err:
  process=subprocess.Popen(['pwsh','-NoProfile','-NonInteractive','-File',str(R/'Run-Test.ps1'),'-RunName','runs/'+label],stdout=out,stderr=err)
  q.put(d/'HOST_PID.json',{'pid':process.pid,'parent_pid':os.getpid(),'utc':q.now()});code=process.wait(timeout=150)
 g=q.load(d/'GUARD_RESULT.json');(d/'stdout.log').write_text(g['Stdout'],'utf8');(d/'stderr.log').write_text(g['Stderr'],'utf8')
 after=source_map(project);q.put(d/'SOURCE_MAP_AFTER.json',after)
 unchanged=all((project/x['path']).stat().st_size==x['bytes'] and q.sha((project/x['path']).read_bytes())==x['sha256'] for x in before)
 diagnostic=[line for line in (g['Stdout']+'\n'+g['Stderr']).splitlines() if re.search(r'(?i)(\bSCRIPT ERROR|\bERROR:|\bWARNING:|^\s*FAIL[: ])',line)]
 iso=[q.strict(line[len('LOCAL_SUITE_ISOLATION '):].encode()) for line in g['Stdout'].splitlines() if line.startswith('LOCAL_SUITE_ISOLATION ')]
 strict=code==0 and g['Status']=='completed' and g['GuardExitCode']==0 and g['RootExitCode']==0 and g['JobEmptyAfterRun'] and g['OutputReadersFinished'] and g['AllRecordedHandlesExited'] and not g['SyntheticFault'] and not g['OutputLimitExceeded'] and unchanged and not diagnostic and len(iso)==1 and iso[0]['isolated']
 result={'label':label,'strict_pass':bool(strict),'engine_pid':g['RootPid'],'engine_exit':g['RootExitCode'],'guard_exit':g['GuardExitCode'],'host_pid':process.pid,'host_exit':code,'host_exited':process.poll() is not None,'source_unchanged':unchanged,'diagnostics':diagnostic,'isolation':iso,'job_empty':g['JobEmptyAfterRun'],'readers_finished':g['OutputReadersFinished'],'handles_exited':g['AllRecordedHandlesExited'],'peak_job_commit_bytes':g['PeakJobCommitBytes'],'admission':g['Admission'],'headless':headless,'production_sha256':q.sha((project/'view/playable_build/player_details.gd').read_bytes()),'gui_entry_sha256':q.sha((project/'tests/focused/local_gui.gd').read_bytes())}
 if not headless:
  packets=[q.strict(line[len('FOCUSED_GUI_RESULT '):].encode()) for line in g['Stdout'].splitlines() if line.startswith('FOCUSED_GUI_RESULT ')]
  result['gui']=packets[0] if len(packets)==1 else {};strict=strict and result['gui'].get('status')=='GUI_PASSED' and result['gui'].get('pressed_events')==4 and result['gui'].get('frames')==225
  result['strict_pass']=bool(strict)
 q.put(d/'VERIFIED_RESULT.json',result);runs.append(result);print(json.dumps({'label':label,'strict_pass':bool(strict),'pid':g['RootPid'],'diagnostics':diagnostic}),flush=True)
 if not strict:raise RuntimeError('Guarded '+label+' failed; preserve raw result and stop')
 return result
try:
 q.gate('gui_prepare')
 d=R/'gui-work';d.mkdir()
 package=R/'portable-packages-v2/combined';candidate=R/'inputs/candidates/player-details-clock-location/20261009-cloud-v1'
 p=subprocess.run([sys.executable,'-X','utf8',str(package/'prepare.py'),'--source-root',str(HOST),'--candidate-root',str(candidate),'--work-root',str(d),'--name','project'],capture_output=True,timeout=120,env={**os.environ,'PYTHONUTF8':'1'})
 (d/'prepare.stdout.log').write_bytes(p.stdout);(d/'prepare.stderr.log').write_bytes(p.stderr);assert p.returncode==0
 project=d/'project';assert not (project/'main.gd').exists()
 (project/'tests/focused/local_gui.gd').write_bytes((R/'focused_gui.gd').read_bytes())
 parse='extends SceneTree\nconst GuiEntry = preload("res://tests/focused/local_gui.gd")\n'+isolation_code()+'func _initialize() -> void:\n\tif not verify_isolation():\n\t\tquit(3)\n\t\treturn\n\tvar loaded: Script = load("res://tests/focused/local_gui.gd")\n\tprint("FOCUSED_GUI_PARSE ",JSON.stringify({"loaded":loaded != null and loaded.can_instantiate(),"test_bodies_started":false}))\n\tquit(0 if loaded != null and loaded.can_instantiate() else 1)\n'
 (project/'tests/focused/local_gui_parse.gd').write_text(parse,'utf8')
 binding=q.load(project/'tests/focused/source_binding.json')
 for name in ['tests/focused/local_gui.gd','tests/focused/local_gui_parse.gd']:binding['files'].append({'path':name,'bytes':(project/name).stat().st_size,'sha256':q.sha((project/name).read_bytes())})
 q.put(project/'tests/focused/source_binding.json',binding)
 launch('gui-parse',project,R/'runs/gui-parse/data','tests/focused/local_gui_parse.gd',True)
 result=launch('gui-capture',project,R/'runs/gui-capture/data','tests/focused/local_gui.gd',False)
 receipt=q.load(project/'PREPARATION_RECEIPT.json');user=R/'runs/gui-capture/data/appdata'/receipt['isolated_user_dir_leaf']
 assert q.load(user/'GUI_RESULT.json')==result['gui']
 media=R/'media';media.mkdir()
 for frame in [35,80,125,170,215]:shutil.copyfile(user/('focused-gui-%03d.png'%frame),media/('focused-gui-%03d.png'%frame))
 q.put(R/'GUI_SOURCE_BINDING.json',{'same_production_as_combined_unit':result['production_sha256']==prior['completed_runs'][-1]['candidate_overlay_sha256'],'production_sha256':result['production_sha256'],'gui_driver_sha256':result['gui_entry_sha256'],'unit_driver_unchanged':True,'isolated_user_dir':str(user),'actual_rendered_frames':len(list(user.glob('focused-gui-*.png'))),'physical_mouse_or_Main_claim':False})
 q.put(R/'GUI_OUTCOME.json',{'status':'reviewable','runs':runs,'user_dir':str(user),'result':result['gui'],'video_encoding':'PENDING; actual PNG frames captured after isolation'})
except Exception as e:
 q.put(R/'GUI_OUTCOME.json',{'status':'blocked' if 'SSL_' in str(e) else 'failed','runs':runs,'error':str(e),'utc':q.now()});print('GUI_EXCEPTION',str(e),flush=True)
finally:
 q.put(R/'GUI_LOCK_RELEASED.json',{'pid':os.getpid(),'handle_disposed':bool(k.CloseHandle(handle)),'utc':q.now()})

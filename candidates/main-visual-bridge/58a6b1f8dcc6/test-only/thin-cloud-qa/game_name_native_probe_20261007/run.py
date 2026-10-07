from pathlib import Path
import hashlib,json,os,subprocess,sys,time
HERE=Path(__file__).resolve().parent
GUARD=HERE.parent/'recover_private_bridge_v1_20261007/guard_effective8g.py'
ORIGINAL=Path('/workspace/recover30/project.godot')
CANDIDATE=HERE.parent/'game_name_candidate_20261007/candidate/payload/project.godot'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if sha(GUARD)!='22605fa19cf73893a3812836c78d509e20be449b6eca6d3ec12eacfc43cefb52':raise SystemExit('Original guard differs')
if sha(ORIGINAL)!='34343acc9519c5479f0c0e86028fa7ed47bf207147d43a804c71ab504358c1fd' or sha(CANDIDATE)!='0b35574f45a5b50307636bb3eee790a9c99be785ce3dc30c2b44e1c666dc0038':raise SystemExit('Original/naming source pair differs')
OUT=HERE/'evidence'/('paths_'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()));OUT.mkdir(parents=True)
env=os.environ.copy()
for key in ['DATA','CACHE','CONFIG']:
 p=OUT/key.lower();p.mkdir();env['XDG_'+key+'_HOME']=str(p)
results=[]
for label_,source in [('original',ORIGINAL),('candidate',CANDIDATE)]:
 project=OUT/label_;project.mkdir();(project/'project.godot').write_bytes(source.read_bytes());(project/'probe.gd').write_bytes((HERE/'probe.gd').read_bytes());env['NAME_PROBE_REPORT']=str(OUT/(label_+'.json'))
 cmd=[sys.executable,'-B',str(GUARD),'--log',str(OUT/(label_+'_guard.jsonl')),'--timeout','180','--reserve-mib','512','--admission-extra-mib','1741','--','godot','--headless','--path',str(project),'--audio-driver','Dummy','--script','res://probe.gd']
 print('NAME_PATH_PROBE_START',label_,str(OUT),flush=True)
 with (OUT/(label_+'.log')).open('w') as f:code=subprocess.call(cmd,cwd=project,env=env,stdout=f,stderr=subprocess.STDOUT)
 diagnostics=[x for x in (OUT/(label_+'.log')).read_text().splitlines() if 'ERROR:' in x or 'WARNING:' in x]
 if code or diagnostics:raise SystemExit('Isolated '+label_+' path probe failed; preserve original logs')
 results.append(json.loads((OUT/(label_+'.json')).read_bytes()))
a,b=results
same=a['user_data_dir']==b['user_data_dir'] and a['globalized_user_path']==b['globalized_user_path']
summary={'ok':same,'platform':a['platform'],'original':a,'candidate':b,'physical_user_data_path_equal':same,'actual_windows_test':'not_run','actual_existing_save_reload':'not_run','stable_project_unchanged':sha(ORIGINAL)=='34343acc9519c5479f0c0e86028fa7ed47bf207147d43a804c71ab504358c1fd','scope':'Two tiny isolated configs and one fresh XDG root; no production edits or real saves read'}
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print('NAME_PATH_PROBE_RESULT',json.dumps(summary,ensure_ascii=False),flush=True)
raise SystemExit(0 if same else 1)

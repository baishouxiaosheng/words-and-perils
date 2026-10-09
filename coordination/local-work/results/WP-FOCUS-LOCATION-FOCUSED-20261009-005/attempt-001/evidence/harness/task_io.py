import json,hashlib,re,subprocess,os,ctypes,datetime,urllib.request
from pathlib import Path
R=Path(__file__).parent;G=R/'git';STATE=Path(r'E:\WordsAndPerils-Tasks\.local-work-state\repo-1403552519')
TASK='WP-FOCUS-LOCATION-FOCUSED-20261009-005';TASK_SHA='e5ee48b068825115242d431cc955ad061d0356bdbae829b4b8b8590b35daea68'
PROTOCOL_SHA='ac97c2523a6400bbde3c1f9b83f0398a704887891a8bfc94f5247476245400bc';SCHEMA_SHA='14a68f72c3cea797799237051e154a5d1e9c5d1184d7cbebdf2d3db0086144ab'
def sha(b):return hashlib.sha256(b).hexdigest()
def strict(b):
 def pairs(xs):
  d={}
  for k,v in xs:
   if k in d:raise ValueError('Duplicate key')
   d[k]=v
  return d
 return json.loads(b.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=lambda x:(_ for _ in ()).throw(ValueError(x)))
def load(p):return strict(p.read_bytes())
def put(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n','utf-8')
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(*a,input=None,env=None):
 p=subprocess.run(['git','-C',str(G),*a],input=input,capture_output=True,env=env)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
 return p.stdout
def tree(h):
 d={}
 for line in git('ls-tree','-rz',h).split(b'\0'):
  if line:
   meta,p=line.split(b'\t',1);mode,kind,blob=meta.decode().split();d[p.decode()]={'mode':mode,'kind':kind,'blob':blob}
 return d
def blob(h,p):
 meta=tree(h)[p];assert meta['mode']=='100644' and meta['kind']=='blob';return git('cat-file','blob',meta['blob'])
def lock_check():
 owner=load(R/'LOCK_OWNER.json')
 k=ctypes.WinDLL('kernel32',use_last_error=True);k.OpenProcess.restype=ctypes.c_void_p;k.CreateFileW.restype=ctypes.c_void_p
 h=k.OpenProcess(0x1000,False,owner['pid']);assert h,'Lock owner exited'
 creation=ctypes.c_ulonglong();exit_time=ctypes.c_ulonglong();kernel=ctypes.c_ulonglong();user=ctypes.c_ulonglong()
 try:
  assert k.GetProcessTimes(ctypes.c_void_p(h),ctypes.byref(creation),ctypes.byref(exit_time),ctypes.byref(kernel),ctypes.byref(user))
  expected=datetime.datetime.fromisoformat(owner['process_created_utc'].replace('Z','+00:00'))
  actual=datetime.datetime(1601,1,1,tzinfo=datetime.timezone.utc)+datetime.timedelta(microseconds=creation.value//10)
  assert abs((actual-expected).total_seconds())<0.000002,'Lock owner identity changed'
 finally:k.CloseHandle(ctypes.c_void_p(h))
 handle=k.CreateFileW(str(STATE/'REPO-WIDE-WRITER.lock'),0xC0000000,0,None,3,0,None)
 if handle!=ctypes.c_void_p(-1).value:
  k.CloseHandle(ctypes.c_void_p(handle));raise ValueError('Repository lock not held')
 assert ctypes.get_last_error()==32,'Cannot establish sharing lock'
def gate(boundary,claim=True):
 receipt={'boundary':boundary,'started_utc':now(),'passed':False,'local_stop':str(STATE/'STOP')}
 try:
  assert not (STATE/'STOP').exists() and not (STATE/'STOP-LATCH.json').exists(),'STOP latched'
  config=load(STATE/'QUEUE_CONFIG.v2.json');assert config['protocol_sha256']==PROTOCOL_SHA and config['schema_sha256']==SCHEMA_SHA
  accept=load(Path(config['scope_extension']['acceptance_receipt_local']));assert accept['local_acceptance_status']=='accepted' and accept['trusted_config_readback_match'] and config['scope_extension']['acceptance_remote_readback_verified']
  assert sha(Path(config['scope_extension']['acceptance_receipt_local']).read_bytes())=='cc89e53a90eb85e0f21831883d7a2d836a3b03c0912405b4742280d486f5083f'
  lock_check();receipt['local_lock_held']=True
  git('fetch','--no-tags','origin','refs/heads/main');h=git('rev-parse','FETCH_HEAD').decode().strip();t=tree(h)
  assert 'coordination/local-work/STOP' not in t,'Remote STOP present'
  for p,pin in [('PROTOCOL.json',PROTOCOL_SHA),('TASK_SCHEMA.json',SCHEMA_SHA),('inbox/'+TASK+'.json',TASK_SHA)]:
   path='coordination/local-work/'+p;assert t[path]['mode']=='100644' and sha(blob(h,path))==pin,'Pinned queue file changed'
  ctrl=strict(blob(h,'coordination/local-work/CONTROL.json'))
  assert set(ctrl)=={'protocol','kind','queue_enabled','stop','resume_generation','reason'}
  assert ctrl['protocol']=='words-and-perils-local-work/v1' and ctrl['kind']=='control' and type(ctrl['stop']) is bool and not ctrl['stop'] and type(ctrl['queue_enabled']) is bool and ctrl['queue_enabled'] and type(ctrl['resume_generation']) is int and ctrl['resume_generation']>=0 and type(ctrl['reason']) is str
  cp='coordination/local-work/results/'+TASK+'/CLAIM.json'
  if claim:assert blob(h,cp)==(R/'CLAIM.json').read_bytes(),'Claim changed'
  else:assert not any(p.startswith('coordination/local-work/results/'+TASK+'/') for p in t),'Existing task state: reconcile, do not claim'
  assert not (STATE/'STOP').exists(),'Local STOP appeared'
  receipt.update(passed=True,head=h,remote_stop_absent=True,control=ctrl,claim_verified=claim,ended_utc=now());put(R/'gates'/('GATE-'+boundary+'.json'),receipt);return h
 except Exception as e:
  receipt.update(error=str(e),ended_utc=now());put(R/'gates'/('GATE-'+boundary+'-FAILED.json'),receipt)
  if not (STATE/'STOP-LATCH.json').exists():put(STATE/'STOP-LATCH.json',receipt)
  raise
def safe(p):
 assert isinstance(p,str) and p and not re.search(r'[\x00-\x1f\x7f\\:]',p) and not p.startswith('/')
 assert all(x and x.lower() not in ('.','..','.git','.github','readme','readme.md') for x in p.split('/'))
def publish(label,files,head,message,readback_concurrency=1):
 assert git('rev-parse','FETCH_HEAD').decode().strip()==head
 old=tree(head);git('read-tree',head);rows=[]
 prefixes=['coordination/local-work/results/'+TASK+'/','coordination/local-work/results/LOCAL-QUEUE-BOOTSTRAP-20261008/','candidates/focus-location-focused-verification/20261009-local-005/']
 for dest,source in files:
  safe(dest);assert any(dest.startswith(p) for p in prefixes) and dest not in old,'Publication outside exact new prefixes or overwrites'
  p=Path(source).resolve();assert p.is_relative_to(R.resolve()) and p.is_file()
  for part in [p,*list(p.parents)[:len(p.relative_to(R).parts)]]:assert not (os.lstat(part).st_file_attributes & 0x400),'Reparse path'
  b=p.read_bytes();oid=git('hash-object','-w','--no-filters','--stdin',input=b).decode().strip();git('update-index','--add','--cacheinfo','100644',oid,dest)
  rows.append({'path':dest,'bytes':len(b),'sha256':sha(b),'git_blob_sha':oid})
 tr=git('write-tree').decode().strip();env=os.environ.copy();env.update(GIT_AUTHOR_NAME='baishouxiaosheng',GIT_COMMITTER_NAME='baishouxiaosheng',GIT_AUTHOR_EMAIL='128279531+baishouxiaosheng@users.noreply.github.com',GIT_COMMITTER_EMAIL='128279531+baishouxiaosheng@users.noreply.github.com')
 c=git('commit-tree',tr,'-p',head,input=(message+'\n').encode(),env=env).decode().strip()
 delta=git('diff-tree','--no-commit-id','--name-status','-r',head,c).decode().splitlines();assert len(delta)==len(rows) and all(x.startswith('A\t') for x in delta)
 hooks=R/'git-hooks';hooks.mkdir(exist_ok=True);(hooks/'EXPECTED_HEAD').write_text(head+'\n','ascii')
 (hooks/'pre-push').write_text('#!/bin/sh\nexpected=$(cat "$(dirname "$0")/EXPECTED_HEAD") || exit 71\nwhile read lr lo rr ro; do\n [ "$rr" = "refs/heads/main" ] && [ "$ro" = "$expected" ] || exit 73\ndone\n','utf-8',newline='\n')
 rec={'label':label,'parent':head,'commit':c,'tree':tr,'files':rows,'force':False,'single_parent':True,'CAS':'expected advertised old main SHA enforced by owned pre-push hook; normal fast-forward receive-pack old/new CAS'};put(R/(label+'_PREPARED.json'),rec)
 p=subprocess.run(['git','-C',str(G),'-c','core.hooksPath='+str(hooks),'push','origin',c+':refs/heads/main'],capture_output=True)
 (R/(label+'_PUSH.stdout.log')).write_bytes(p.stdout);(R/(label+'_PUSH.stderr.log')).write_bytes(p.stderr);put(R/(label+'_PUSH.json'),{'exit_code':p.returncode,'commit':c,'ended_utc':now()});assert p.returncode==0,'Push failed; stop and read-only reconcile'
 def read_one(row):
  url='https://raw.githubusercontent.com/baishouxiaosheng/words-and-perils/'+c+'/'+row['path']
  with urllib.request.urlopen(urllib.request.Request(url,headers={'Cache-Control':'no-cache','User-Agent':'WordsAndPerils-verified-readback'}),timeout=35) as resp:b=resp.read()
  assert len(b)==row['bytes'] and sha(b)==row['sha256'] and hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==row['git_blob_sha'],'Remote readback mismatch'
  out=R/'remote-readback'/label/row['path'];out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(b);return {**row,'actual_http_bytes_match':True}
 from concurrent.futures import ThreadPoolExecutor
 assert 1<=readback_concurrency<=6
 with ThreadPoolExecutor(max_workers=readback_concurrency) as pool:got=list(pool.map(read_one,rows))
 put(R/(label+'_READBACK.json'),{'commit':c,'all_match':True,'files':got,'verified_utc':now()});return c

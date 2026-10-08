import ast,json,hashlib,re,subprocess,os,datetime
from pathlib import Path
R=Path(__file__).parent;G=R/'git'
def load(p):
 def pairs(xs):
  d={}
  for k,v in xs:
   if k in d:raise ValueError('Duplicate key')
   d[k]=v
  return d
 return json.loads(p.read_text('utf-8-sig'),object_pairs_hook=pairs,parse_constant=lambda x:(_ for _ in ()).throw(ValueError(x)))
def sha(b):return hashlib.sha256(b).hexdigest()
def dump(n,v):(R/n).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n','utf-8')
def git(*args):return subprocess.run(['git','-C',str(G),*args],capture_output=True,check=True).stdout
def safe(s):return bool(s) and not re.search(r'[\x00-\x1f\x7f\\:]',s) and not s.startswith('/') and all(p not in ('','.','..','.git','.github') for p in s.split('/'))
assert sha((R/'PROTOCOL.json').read_bytes())=='209cc25f649f2ce6635012d6d6f0bdcf09526ac68d1a7dcbf907e7398a73c05a'
assert sha((R/'TASK_SCHEMA.json').read_bytes())=='ad3a3cd71adae6c38817042e06322d0aaa0092080be3c15579ccffe1b1c8e85c'
task=load(R/'inbox/WP-NATURAL-OWNED-STAGING-VERIFY-20261008-002.json')
assert sha((R/'inbox/WP-NATURAL-OWNED-STAGING-VERIFY-20261008-002.json').read_bytes())=='49032c299667885b29120af6f7e37685272f8098302be457aaba91e314e9425a'
assert task['base_commit']=='e8941c2235069a168d9b6d92a0e9e1a62acce296' and task['allowed_production_changes']==[] and task['allowed_test_changes']==['tests/t03_natural_owned_staging_runtime/']
old=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\evidence\WP-NATURAL-SAVE-BOOL-20261008-001\run-20261008-a1b40-01')
module=ast.parse((old/'validate_start.py').read_text('utf-8-sig'))
ns={'re':re};exec(compile(ast.Module(body=[n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='validate'],type_ignores=[]),'pinned_schema_validator','exec'),ns)
ns['validate'](task,load(R/'TASK_SCHEMA.json'),load(R/'TASK_SCHEMA.json'))
intake=load(R/'BOOT_READS.base64.json')['head'];assert git('rev-parse','FETCH_HEAD').decode().strip()==intake
assert git('merge-base','--is-ancestor',task['base_commit'],intake)==b''
root=R/'inputs';assert not root.exists();root.mkdir()
rows=[]
for x in task['inputs']:
 assert safe(x['repository_path'])
 b=git('show',task['base_commit']+':'+x['repository_path']);blob=hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
 assert len(b)==x['bytes'] and sha(b)==x['sha256'] and blob==x['git_blob_sha'],x['repository_path']
 p=root/x['repository_path'];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
 rows.append({**x,'verified':True})
assert len(rows)==17
guard=Path(r'E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a\windows-guard-v3')
guard_rows=[]
for row in load(guard/'source-hashes.json'):
 b=(guard/row['name']).read_bytes();assert sha(b)==row['sha256'];guard_rows.append({'name':row['name'],'sha256':sha(b),'verified':True})
assert sha((guard/'WindowsGuard.cs').read_bytes())==task['verification']['guard_provenance']['guard_source_sha256']
assert sha((guard/'Invoke-WindowsGuard.ps1').read_bytes())==task['verification']['guard_provenance']['guard_wrapper_sha256']
assert sha((R/'reviews/CHANNEL_TRUST_REVIEW_20261008.json').read_bytes())==task['verification']['channel_review']['sha256']
dump('INPUT_VERIFICATION.json',{'intake_commit':intake,'base_commit':task['base_commit'],'task_sha256':sha((R/'inbox/WP-NATURAL-OWNED-STAGING-VERIFY-20261008-002.json').read_bytes()),'schema_valid':True,'all_17_verified':True,'inputs':rows,'guard':guard_rows,'review_sha256':task['verification']['channel_review']['sha256'],'production_change_permission':[]})
dump('AUTHORITY.json',{'repository_id':1403552519,'owner_id':128279531,'current_authenticated_account_id':128279531,'permission':'admin','channel':'main:coordination/local-work/inbox/','authority':'Direct user instruction in current local chat, 2026-10-08; fixed designated bounded repository channel.','signature_or_all_collaborator_roster_required':False,'author_text_used_as_authentication':False,'source_channel_gate_passed':True,'canary':load(R/'CANARY_RESULT.json'),'automation_enabled':False,'native_persistence_verified':False,'protocol_sha256':'209cc25f649f2ce6635012d6d6f0bdcf09526ac68d1a7dcbf907e7398a73c05a','schema_sha256':'ad3a3cd71adae6c38817042e06322d0aaa0092080be3c15579ccffe1b1c8e85c'})
print(json.dumps({'inputs_verified':17,'guard_files_verified':len(guard_rows),'task_schema_valid':True,'source_channel_gate':True,'canary_actual_pass':True}))

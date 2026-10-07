#!/usr/bin/env python3
"""Stage approved source-only actor/v29 candidate in its own local QA copy."""
from pathlib import Path
import base64,hashlib,io,json,os,shutil,stat,subprocess,sys,time,zipfile
REPO=Path(__file__).resolve().parents[3]
DEST=Path('/workspace/actor05eb')
PREFIX='candidates/actor-public-v29-compat/05ebbe56e88d'
def digest(b):return hashlib.sha256(b).hexdigest()
def regular(p):
    if p.is_symlink() or not p.is_file():raise ValueError('Expected regular source file')
    return p.read_bytes()
def stage():
    if DEST.exists():raise ValueError('Fresh isolated candidate copy required')
    if digest(regular(REPO/'main.gd'))!='6e2f62e76db2f4a64a9bbdf4d348a32588d1cb991e6d869bff4c730e12e61e5c':raise ValueError('Existing restored v29 Main differs')
    original=json.loads(regular(REPO/'candidates/actor-status/a6de3fff486d/manifest.json'))
    a=original['archive'];encoded=regular(REPO/'candidates/actor-status/a6de3fff486d'/a['file'])
    if len(encoded)!=a['encoded_bytes'] or digest(encoded)!=a['encoded_sha256']:raise ValueError('Original public packet mismatch')
    b=base64.b64decode(encoded,validate=True)
    if len(b)!=a['zip_bytes'] or digest(b)!=a['zip_sha256']:raise ValueError('Original public archive mismatch')
    z=zipfile.ZipFile(io.BytesIO(b))
    if len(z.namelist())!=len(set(z.namelist())) or set(z.namelist())!=set(a['members']):raise ValueError('Original member allowlist differs')
    for info in z.infolist():
        row=a['members'][info.filename];data=z.read(info.filename)
        if info.is_dir() or stat.S_IFMT(info.external_attr>>16)!=stat.S_IFREG or len(data)!=row['bytes'] or digest(data)!=row['sha256']:raise ValueError('Original pinned member mismatch')
    newmain=subprocess.check_output(['git','show','3f312035b684e51b062c59472395f22f5d672d6c:'+PREFIX+'/production/main.gd'],cwd=REPO)
    if hashlib.sha1(b'blob '+str(len(newmain)).encode()+b'\0'+newmain).hexdigest()!='2c522dfa6942bf51c4004d2d8a69c8a667c4ca56':raise ValueError('Approved source blob differs')
    shutil.copytree(REPO,DEST,ignore=shutil.ignore_patterns('.git','.runtime'))
    for row in original['production_files']:
        if row['path']=='main.gd':continue
        target=DEST/row['path']
        if target.is_symlink():raise ValueError('Source target symlink')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read('production/'+row['path']))
    (DEST/'main.gd').write_bytes(newmain)
    for name in z.namelist():
        if name.startswith('test-only/tests/'):
            target=DEST/name[len('test-only/'):];target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(name))
    e=DEST/'artifacts/actor05eb_qa';e.mkdir()
    pins={row['path']:digest(regular(DEST/row['path'])) for row in original['production_files']}
    for row in json.loads(regular(REPO/'updates/v29/manifest.json'))['files']:
        n=row['path']
        if n not in pins:pins[n]=digest(regular(DEST/n))
    (e/'source-pins.json').write_text(json.dumps(pins,sort_keys=True,indent=2)+'\n')
    tests=DEST/'tests/actor_v29_compat';tests.mkdir()
    (tests/'parse_combo.gd').write_text('extends SceneTree\nconst Main=preload("res://main.gd")\nconst ExistingTests=preload("res://tests/actor_status_entry/parse_public_tests.gd")\nfunc _initialize()->void:\n\tprint("ACTOR_V29_COMBO_PARSE_OK")\n\tquit(0)\n')
    print('ACTOR_COMBO_STAGE_OK',len(original['production_files']),'original sources',digest(newmain),flush=True)
def run_parse():
    e=DEST/'artifacts/actor05eb_qa';pins=json.loads(regular(e/'source-pins.json'))
    for n,h in pins.items():
        if digest(regular(DEST/n))!=h:raise ValueError('Staged source differs')
    work=e/'parse'
    if work.exists():raise ValueError('Fresh parse output required')
    work.mkdir();env=os.environ.copy()
    for key in ('DATA','CACHE','CONFIG'):
        p=work/key.lower();p.mkdir();env['XDG_'+key+'_HOME']=str(p)
    guard=REPO/'artifacts/dot_native_qa_20261007/guard_effective8g.py'
    if digest(regular(guard))!='22605fa19cf73893a3812836c78d509e20be449b6eca6d3ec12eacfc43cefb52':raise ValueError('Approved guard differs')
    cmd=[sys.executable,'-B',str(guard),'--log',str(work/'guard.jsonl'),'--timeout','120','--reserve-mib','512','--admission-extra-mib','1024','--','godot','--headless','--path',str(DEST),'--audio-driver','Dummy','--script','res://tests/actor_v29_compat/parse_combo.gd']
    with (work/'runtime.log').open('w') as log:code=subprocess.call(cmd,cwd=DEST,env=env,stdout=log,stderr=subprocess.STDOUT)
    lines=(work/'runtime.log').read_text(errors='replace').splitlines();errors=[s for s in lines if 'ERROR:' in s or 'WARNING:' in s]
    for n,h in pins.items():
        if digest(regular(DEST/n))!=h:raise ValueError('Parse modified pinned sources')
    result={'code':code,'strict_errors':errors,'source_pins':pins,'scope':'New source combination parse/load only; no scenario acceptance'}
    (work/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print('ACTOR_COMBO_PARSE_RESULT',code,'strict',len(errors),flush=True)
    if code or errors:raise SystemExit(1)
if __name__=='__main__':
    if sys.argv[1]=='stage':stage()
    elif sys.argv[1]=='parse':run_parse()
    else:raise SystemExit('Use stage or parse')

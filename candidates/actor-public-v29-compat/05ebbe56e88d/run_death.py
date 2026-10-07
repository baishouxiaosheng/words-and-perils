#!/usr/bin/env python3
"""Run only the two existing logic-only death gates with immutable old input."""
from pathlib import Path
import base64,hashlib,io,json,os,stat,subprocess,sys,time,zipfile
REPO=Path(__file__).resolve().parents[3]
DEST=Path('/workspace/actor05eb')
def digest(b):return hashlib.sha256(b).hexdigest()
def regular(p):
    if p.is_symlink() or not p.is_file():raise ValueError('Expected own regular QA file')
    return p.read_bytes()
def run(case):
    if case not in ['death-enemy','death-player']:raise ValueError('Only the two approved death cases')
    # A private consumer-local fixture path is allowed; bytes remain exactly pinned.
    input_path=Path(sys.argv[2]) if len(sys.argv)>2 else Path(__file__).with_name('death_fixture_inputs.zip.b64')
    encoded=regular(input_path)
    if len(encoded)!=105240 or digest(encoded)!='6695f8b9366c567f065a67dae28c194df197d6dc6af2416433dbb015d8de615d':raise ValueError('Fixed death attachment differs')
    zb=base64.b64decode(encoded,validate=True)
    if len(zb)!=78930 or digest(zb)!='2f8aba302e2e282f8aa046e532bd756e4c5086c2ba36c429feeffd06e25dcb8b':raise ValueError('Fixed death ZIP differs')
    z=zipfile.ZipFile(io.BytesIO(zb));manifest=json.loads(z.read('INPUT_MANIFEST.json'));members=manifest['source_members']
    if len(z.namelist())!=len(set(z.namelist())) or set(z.namelist())!=set(members)|{'INPUT_MANIFEST.json'}:raise ValueError('Fixed member set differs')
    for n,row in members.items():
        info=z.getinfo(n);b=z.read(n)
        if info.is_dir() or stat.S_IFMT(info.external_attr>>16)!=stat.S_IFREG or len(b)!=row['bytes'] or digest(b)!=row['sha256']:raise ValueError('Pinned input member differs')
        if n.startswith('tests/'):
            p=DEST/n
            if p.is_symlink():raise ValueError('Test target symlink')
            p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
    e=DEST/'artifacts/actor05eb_qa';work=e/(case+'-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()));work.mkdir()
    env=os.environ.copy()
    for key in ['DATA','CACHE','CONFIG']:
        p=work/key.lower();p.mkdir();env['XDG_'+key+'_HOME']=str(p)
    env['FOGBANK_ACTOR_FULL_TEST_ROOT']=str(work)
    user=work/'data/godot/app_userdata/雾岸纪事 · AI 沙盘'
    for n in members:
        if n.startswith('producer_checkpoints/'):
            p=user/'actor_full_main'/n[len('producer_'):];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(n))
    pins=json.loads(regular(e/'source-pins.json'))
    consumer=json.loads(z.read('tests/actor_full_main/public_source_pins.json'))['files']
    runtime_path=REPO/'candidates/public-v29-enhanced/2b82fa8b37d5/runtime_876_pins.json';runtimebytes=regular(runtime_path)
    if digest(runtimebytes)!='4f61e1ce088cc0817ef2044f142f6c80edd5a6a7c3ec47688fa559ed16c1860e':raise ValueError('Original876 map differs')
    runtime=json.loads(runtimebytes)
    def verify():
        for n,h in {**pins,**consumer}.items():
            if digest(regular(DEST/n))!=h:raise ValueError('Original49/current65 source identity differs: '+n)
        for n,row in runtime.items():
            b=regular(DEST/n)
            if len(b)!=row['bytes'] or digest(b)!=row['sha256']:raise ValueError('Original876 runtime input differs: '+n)
    def snapshot():
        paths=[p for p in DEST.iterdir() if p.is_file() and p.suffix in ['.gd','.tscn','.tres','.gdshader']]
        for directory in ['core','view','assets','tests']:
            paths.extend(p for p in (DEST/directory).rglob('*') if p.is_file() and p.suffix in ['.gd','.tscn','.tres','.gdshader'])
        paths.append(DEST/'project.godot')
        return {str(p.relative_to(DEST)):digest(regular(p)) for p in sorted(paths)}
    verify();before=snapshot();(work/'whole-code-before.json').write_text(json.dumps(before,sort_keys=True,indent=2)+'\n')
    guard=REPO/'artifacts/dot_native_qa_20261007/guard_effective8g.py'
    if digest(regular(guard))!='22605fa19cf73893a3812836c78d509e20be449b6eca6d3ec12eacfc43cefb52':raise ValueError('Original owned guard differs')
    cmd=[sys.executable,'-B',str(guard),'--log',str(work/'guard.jsonl'),'--timeout','180','--reserve-mib','512','--admission-extra-mib','1741','--','godot','--headless','--path',str(DEST),'--audio-driver','Dummy','--script','res://tests/test_full_main_bridge_logic.gd','--','--gate=display','--case='+case]
    with (work/'runtime.log').open('w') as log:code=subprocess.call(cmd,cwd=DEST,env=env,stdout=log,stderr=subprocess.STDOUT)
    verify();after=snapshot()
    if before!=after:raise ValueError('Gate mutated literal code/scene/shader inputs')
    (work/'whole-code-after.json').write_text(json.dumps(after,sort_keys=True,indent=2)+'\n')
    text=(work/'runtime.log').read_text(errors='replace');errors=[x for x in text.splitlines() if 'ERROR:' in x or 'WARNING:' in x]
    reportpath=user/('actor_full_main/report_logic_display_'+case+'.json')
    report=json.loads(regular(reportpath)) if reportpath.exists() else {}
    if reportpath.exists():(work/'report.json').write_bytes(regular(reportpath))
    guardrows=[json.loads(x) for x in regular(work/'guard.jsonl').decode().splitlines()]
    summary={'code':code,'strict_errors':errors,'source_pins_before_after':consumer,'original49_sources_verified_before_after':len(pins),'original_runtime876_verified_before_after':len(runtime),'runtime876_map_sha256':digest(runtimebytes),'whole_code_input_count':len(before),'whole_code_before_after_sha256':digest(regular(work/'whole-code-before.json')),'original_checkpoint_members':{n:r for n,r in members.items() if n.startswith('producer_')},'producer_identity':json.loads(z.read('producer_checkpoints/engagement/manifest.json')),'consumer_logic_sha256':manifest['consumer_logic_driver_sha256'],'consumer_pinmap_sha256':manifest['consumer_source_pin_sha256'],'guard_terminal_events':[r for r in guardrows if r['event']!='sample'],'max_sampled_owned_VmHWM_kib':max((r.get('VmHWM_kib',0) for r in guardrows),default=0),'native_log_files':{n:{'bytes':len(regular(work/n)),'sha256':digest(regular(work/n))} for n in ['runtime.log','guard.jsonl']},'result':report,'scope':'Original two death modes only; old immutable engagement producer and new source-bound consumer are distinct; no original historical scores reused; literal code snapshot plus49/65/876 pre/post; no native visual acceptance'}
    (work/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print('ACTOR_COMBO_DEATH_RESULT',case,code,'strict',len(errors),'checks',report.get('checks'),'pid',report.get('pid'),'ok',report.get('ok'),flush=True)
    if code or errors or not report.get('ok'):raise SystemExit(1)
if __name__=='__main__':run(sys.argv[1])

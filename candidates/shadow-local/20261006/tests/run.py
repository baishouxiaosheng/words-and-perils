#!/usr/bin/env python3
"""Fresh evidence directory, immutable inputs before/after, one owned engine."""
from pathlib import Path
import datetime,hashlib,json,os,re,subprocess,sys,time
root=Path(__file__).resolve().parents[1]
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
run=root/'evidence'/stamp
run.mkdir(parents=True,exist_ok=False)
def hashes():
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and not any(x in p.relative_to(root).parts for x in ['.godot','evidence']) and not p.name.endswith(('.uid','.import'))}
before=hashes();(run/'before.json').write_text(json.dumps(before,indent=2)+'\n')
env=os.environ.copy()
for name in ['DATA','CONFIG','CACHE']:
    path=run/('xdg_'+name.lower());path.mkdir();env['XDG_'+name+'_HOME']=str(path)
env['DISPLAY']=':91';env['LIBGL_ALWAYS_SOFTWARE']='1';env['LP_NUM_THREADS']='2'
args=['godot','--path',str(root),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--display-driver','x11','--script','tests/capture.gd','--',str(run)]
if '--validate-only' in sys.argv:
    args.remove('--display-driver');args.remove('x11');args.insert(1,'--headless');args.append('--validate-only')
display=None
def identity(child):
    proc=Path('/proc')/str(child.pid)
    tail=(proc/'stat').read_text().rsplit(') ',1)[1].split()
    return (os.readlink(proc/'exe'),int(tail[1]),int(tail[19]))
try:
    if '--validate-only' not in sys.argv:
        # Xorg and Godot must share this invocation's IPC namespace for MIT-SHM.
        # A server orphaned by a previous sandbox invocation causes BadShmSeg.
        with (run/'display.log').open('wb') as log:
            display=subprocess.Popen(['/usr/lib/xorg/Xorg',':91','-config','/etc/X11/xorg.conf','-logfile',str(run/'Xorg.91.log'),'-noreset','-nolisten','tcp'],stdout=log,stderr=subprocess.STDOUT,env=env)
        display_id=identity(display)
        for _ in range(60):
            if display.poll() is not None:raise RuntimeError('Owned display failed')
            if Path('/tmp/.X11-unix/X91').exists():break
            time.sleep(.05)
        else:raise RuntimeError('Display startup timed out')
    with (run/'engine.log').open('wb') as log:
        result=subprocess.run([sys.executable,str(root/'tests/run_owned_guard.py'),'--log',str(run/'guard.jsonl'),'--timeout','120','--reserve-mib','512','--',*args],env=env,stdout=log,stderr=subprocess.STDOUT)
finally:
    if display is not None and display.poll() is None and identity(display)==display_id:
        display.terminate()
        try:display.wait(timeout=5)
        except subprocess.TimeoutExpired:
            if identity(display)==display_id:display.kill();display.wait(timeout=2)
after=hashes();(run/'after.json').write_text(json.dumps(after,indent=2)+'\n')
text=(run/'engine.log').read_text()
# Keep every log line; known GLX swap-interval warning is not a script/render error.
errors=re.findall(r'^.*(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FATAL).*$',text,re.M)
status={'process_exit':result.returncode,'inputs_unchanged':before==after,'engine_errors':errors,'pass_marker':'SHADOW_LOCAL_PASS' in text,'scope':'cpu' if '--validate-only' in sys.argv else 'render'}
(run/'validation.json').write_text(json.dumps(status,indent=2)+'\n')
print(run);print(json.dumps(status));print(text[-11000:])
sys.exit(0 if result.returncode==0 and before==after and not errors and status['pass_marker'] else 1)

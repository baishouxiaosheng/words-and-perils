from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,time
HERE=Path(__file__).resolve().parent
ROOT=Path('/workspace/recover30')
GUARD=HERE.parent/'recover_private_bridge_v1_20261007/guard_effective8g.py'
SOURCE=HERE.parent/'recover_private_bridge_v1_20261007/verified_v1/dynamic_current/source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if sha(GUARD)!='22605fa19cf73893a3812836c78d509e20be449b6eca6d3ec12eacfc43cefb52':raise SystemExit('Original guard changed')
pins={p.name:sha(p) for p in SOURCE.iterdir() if p.is_file()}
for n,s in pins.items():
 if sha(ROOT/n if n=='main.gd' else ROOT/'private_main_visual'/n)!=s:raise SystemExit('Actual source differs:'+n)
if sha(ROOT/'project.godot')!='34343acc9519c5479f0c0e86028fa7ed47bf207147d43a804c71ab504358c1fd':raise SystemExit('Unadopted naming change must not enter current recording')
if shutil.which('ffmpeg')!='/usr/bin/ffmpeg' or shutil.which('ffprobe')!='/usr/bin/ffprobe':raise SystemExit('Current preinstalled video tools missing')
available=shutil.disk_usage(HERE).free
if available<512*1024*1024:raise SystemExit('Need512MiB bounded movie+conversion workspace headroom')
OUT=HERE/'evidence'/('movie_'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()));OUT.mkdir(parents=True)
movie=OUT/'offline_move_candidate.ogv';mp4=OUT/'WordsAndPerils_OfflineMove_Candidate.mp4'
(ROOT/'tests/offline_feature_movie.gd').write_bytes((HERE/'movie.gd').read_bytes())
env=os.environ.copy()
for key in ['DATA','CACHE','CONFIG']:
 p=OUT/key.lower();p.mkdir();env['XDG_'+key+'_HOME']=str(p)
env['OFFLINE_MOVIE_REPORT']=str(OUT/'report.json')
common=[sys.executable,'-B',str(GUARD),'--timeout','180','--reserve-mib','512','--admission-extra-mib','1741']
def gate(name,args):
 print('MOVIE_STAGE',name,str(OUT),flush=True)
 with (OUT/(name+'.log')).open('w') as f:
  code=subprocess.call(common+['--log',str(OUT/(name+'_guard.jsonl')),'--','godot','--path',str(ROOT),'--audio-driver','Dummy']+args,env=env,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 diagnostics=[x for x in (OUT/(name+'.log')).read_text().splitlines() if 'ERROR:' in x or 'WARNING:' in x]
 print('MOVIE_TERMINAL',name,code,json.dumps(diagnostics),flush=True)
 if code:raise SystemExit('Movie '+name+' failed; original evidence retained')
 return diagnostics
d=gate('parse',['--headless','--check-only','--script','res://tests/offline_feature_movie.gd'])
if d:raise SystemExit('Movie fixture parse diagnostics')
d=gate('movie',['--rendering-method','gl_compatibility','--resolution','1180x812','--write-movie',str(movie),'--fixed-fps','30','--script','res://tests/offline_feature_movie.gd'])
known='WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.'
if any(x!=known for x in d):raise SystemExit('Movie diagnostics require original-text review')
r=json.loads((OUT/'report.json').read_bytes())
if not r.get('ok') or not movie.is_file() or movie.stat().st_size<=0:raise SystemExit('Actual move/movie result not complete')
with (OUT/'ffmpeg.log').open('w') as f:
 code=subprocess.call(['/usr/bin/ffmpeg','-nostdin','-v','error','-i',str(movie),'-c:v','libx264','-threads','2','-preset','fast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(mp4)],stdout=f,stderr=subprocess.STDOUT)
if code:raise SystemExit('Movie conversion failed; original OGV retained')
probe=json.loads(subprocess.check_output(['/usr/bin/ffprobe','-v','error','-show_streams','-show_format','-of','json',str(mp4)]))
(OUT/'ffprobe.json').write_text(json.dumps(probe,indent=2)+'\n')
video=next(x for x in probe['streams'] if x['codec_type']=='video')
after={n:sha(ROOT/n if n=='main.gd' else ROOT/'private_main_visual'/n) for n in pins}
summary={'ok':after==pins,'checks':r['checks'],'pid':r['pid'],'diagnostics':d,'source_pins':pins,'source_unchanged':after==pins,'mp4':{'bytes':mp4.stat().st_size,'sha256':sha(mp4),'width':video['width'],'height':video['height'],'fps':video['avg_frame_rate'],'duration_s':float(probe['format']['duration'])},'original_ogv':{'bytes':movie.stat().st_size,'sha256':sha(movie)},'report_sha256':sha(OUT/'report.json'),'scope':r['scope']}
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('OFFLINE_MOVIE_RESULT',json.dumps({k:v for k,v in summary.items() if k!='source_pins'},ensure_ascii=False),flush=True)
raise SystemExit(0 if summary['ok'] else 1)

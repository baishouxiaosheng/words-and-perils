from pathlib import Path
import hashlib,json,subprocess
HERE=Path(__file__).resolve().parent
OUT=HERE/'evidence/movie_20261007T144236Z'
original=OUT/'offline_move_candidate.ogv'
if hashlib.sha256(original.read_bytes()).hexdigest()!='d1cca6e6561aea038399a0ac37073739583d5c5f9134bd1b5ea50e76fecb7a75':raise SystemExit('Original recorded bytes differ')
movie=OUT/'WordsAndPerils_OfflineMove_Candidate_30fps.mp4'
with (OUT/'cfr_transcode.log').open('w') as f:
 subprocess.run(['/usr/bin/ffmpeg','-nostdin','-v','error','-i',str(original),'-c:v','libx264','-threads','2','-preset','fast','-crf','20','-pix_fmt','yuv420p','-r','30','-fps_mode','cfr','-c:a','aac','-movflags','+faststart',str(movie)],stdout=f,stderr=subprocess.STDOUT,check=True,timeout=45)
for at in [1.0,4.0,6.5]:
 subprocess.run(['/usr/bin/ffmpeg','-nostdin','-v','error','-ss',str(at),'-i',str(movie),'-frames:v','1',str(OUT/('review_'+str(at)+'.png'))],check=True,timeout=15)
probe=json.loads(subprocess.check_output(['/usr/bin/ffprobe','-v','error','-show_streams','-show_format','-of','json',str(movie)],timeout=10))
stream=next(x for x in probe['streams'] if x['codec_type']=='video')
result={'path':str(movie),'bytes':movie.stat().st_size,'sha256':hashlib.sha256(movie.read_bytes()).hexdigest(),'width':stream['width'],'height':stream['height'],'average_frame_rate':stream['avg_frame_rate'],'frames':stream.get('nb_frames'),'duration_s':float(probe['format']['duration']),'scope':'Original OGV preserves timing; CFR MP4 repeats identical held frames, no interpolation or content/authority editing'}
if result['average_frame_rate']!='30/1':raise SystemExit('Expected30fps output differs')
(OUT/'cfr_summary.json').write_text(json.dumps(result,indent=2)+'\n');print('OFFLINE_MOVIE_CFR',json.dumps(result),flush=True)

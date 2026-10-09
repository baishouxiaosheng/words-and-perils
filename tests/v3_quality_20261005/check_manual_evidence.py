#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
from PIL import Image
base=Path(__file__).resolve().parents[1]
out=base/'artifacts/manual_03'
game=base.parent/'v3_playable_candidate_20261005/game'
report=json.loads((out/'manual_report.json').read_text())
rows={r['label']:r for r in report['records']}
checks=[]
def check(name,value):checks.append({'name':name,'ok':bool(value)})
check('manual session completed',report['completed'] and report['observed_v3'])
check('18 logged checkpoints',len(rows)==18)
for name,row in rows.items():
 with Image.open(row['path']) as image:
  image.load();size=list(image.size)
 check(name+' actual native raster',row['png_saved'] and size==row['png_size']==row['native_root']==row['world_raster']==[1280,720])
 check(name+' preserves old coast authority',row.get('coast_preserved',False))
 check(name+' has no board error',not row['board_error'])
check('normal default and returned coast exact full authority',rows['default_coast']['authority_hash']==rows['manual_1']['authority_hash']==rows['manual_16']['authority_hash']==rows['final']['authority_hash']==report['initial_coast_authority'])
check('V3 display, selection, details and sample-fill do not act',len({rows['manual_'+str(i)]['authority_hash'] for i in range(2,7)})==1)
check('radius12 exact source and spawn',rows['manual_2']['source']['board_radius']==12 and rows['manual_2']['source']['content_hash']=='d88a38a306fb0d084a9b9ded823c0b272fdcec1d11deb6886d8e8d2862c668fc' and rows['manual_2']['actor']['hex']==[0,0])
check('whole map overview shown',rows['manual_3']['camera']['overview'])
check('readable source biome details shown',rows['manual_5']['details_visible'] and '生态：丛林' in rows['manual_5']['details'])
check('pending action survives next focus and file reload exactly',len({rows['manual_'+str(i)]['authority_hash'] for i in range(7,11)})==1)
check('later focus distinct from frozen action',rows['manual_8']['selected_focus']['hex']==[1,-1] and rows['manual_8']['frozen_focus']['hex']==[-1,0])
check('save uses independent V3 namespace',rows['manual_9']['last_save']=={'ok':True,'path':'user://generated_v3_adventure_v1.json'})
check('actual menu reload restored exact pending',rows['manual_10']['last_load']=={'ok':True,'exact_pending':True})
check('move commits frozen target with displayed3stamina charge',rows['manual_11']['phase']=='idle' and rows['manual_11']['turn']==1 and rows['manual_11']['actor']['hex']==[-1,0] and rows['manual_11']['actor']['stamina']['current']==5)
check('free text waits with unchanged world',rows['manual_12']['phase']=='awaiting_assessment' and rows['manual_12']['intent']=='look around' and rows['manual_12']['state_hash']==rows['manual_11']['state_hash'])
check('opening free-text panel does not change authority',rows['manual_12']['authority_hash']==rows['manual_13']['authority_hash'])
check('cancel returns idle without a turn or world change',rows['manual_14']['phase']=='idle' and rows['manual_14']['state_hash']==rows['manual_11']['state_hash'])
check('saving completed/canceled state is read only',rows['manual_14']['authority_hash']==rows['manual_15']['authority_hash'])
freeze=json.loads((base/'artifacts/manual_source_freeze_before.json').read_text());pins=[]
for f in freeze['production']:
 current=hashlib.sha256((game/f['path']).read_bytes()).hexdigest()
 pins.append({'path':f['path'],'expected':f['sha256'],'current':current,'ok':current==f['sha256']})
check('all20 frozen production files unchanged during manual QA',len(pins)==20 and all(p['ok'] for p in pins))
log=(out/'engine.log').read_text();guard=[json.loads(line) for line in (out/'guard.jsonl').read_text().splitlines()]
check('clean native engine exit0',guard[-1].get('event')=='exited' and guard[-1].get('child_exit')==0 and (out/'exit.txt').read_text().strip()=='0')
check('no script or engine ERROR in accepted attempt','ERROR:' not in log)
check('original8GiB guard and512MiB reserve retained',guard[0]['cgroup_limit']==8589934592 and guard[0]['reserve_bytes']==536870912)
check('no guard intervention',not any(x.get('event') in ['stop','stopped','timeout','limit_reached','terminated'] for x in guard))
peak=max(x.get('cgroup_current',0) for x in guard);threshold=guard[0]['stop_threshold']
check('all sampled cgroup memory below guard threshold',peak<threshold)
result={'ok':all(c['ok'] for c in checks),'checks':len(checks),'passed':sum(c['ok'] for c in checks),'failures':[c['name'] for c in checks if not c['ok']], 'scope':'Independent real mouse/keyboard on frozen opt-in V3 candidate; functional acceptance at this exact source freeze. Renderer lighting follow-on and final old-mode regression are separate gates.', 'records':len(rows),'checks_detail':checks,'production_pins':pins,'guard':{'owned_pid':guard[-1]['owned_pid'],'exit_code':guard[-1]['child_exit'],'elapsed_seconds':guard[-1]['elapsed_s'],'peak_cgroup_bytes':peak,'headroom_above_reserve_at_peak_bytes':threshold-peak,'peak_process_rss_kib':max(x.get('VmRSS_kib',0) for x in guard),'final_cgroup_bytes':guard[-1]['cgroup_current']},'excluded_attempts':{'manual_01':'Harness parse inference mistake; no game startup; exit1','manual_02':'Harness used missing coast save_data method; closed normally; exit0 with scriptERROR; no acceptance witness'},'rendering':'Native1280x720, Godot4.6.3 GL Compatibility cloud llvmpipe; no hardwareFPS claim'}
(out/'independent_acceptance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ('checks_detail','production_pins')},indent=2))
raise SystemExit(0 if result['ok'] else 1)

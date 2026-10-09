#!/usr/bin/env python3
"""Independent readback of retained actual mock envelopes; never sends or runs Godot."""
from pathlib import Path
import json, hashlib, argparse
p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
checks=[];rows=[]
def check(ok,label): checks.append({'ok':bool(ok),'label':label})
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for label in ('conversation','committed_narration','learned_plant','timeout_retry','replacement_request'):
 h=args.evidence/(label+'_http.json'); e=args.evidence/(label+'_engine.json')
 check(h.is_file() and e.is_file(),label+' retained pair exists')
 if not h.is_file() or not e.is_file():continue
 envelope=json.loads(h.read_bytes()); expected=e.read_bytes(); actual=envelope['messages'][1]['content'].encode('utf8'); request=json.loads(actual)
 check(actual==expected,label+' outgoing public JSON byte-exact to frozen engine request')
 check(envelope.get('stream') is False and envelope.get('store') is False,label+' no streaming or provider storage requested')
 check(envelope['model']=='unchanged-synthetic-test-model',label+' exact explicitly configured model identifier')
 check(envelope.get('response_format')=={'type':'json_object'} and not envelope.get('tools'),label+' JSON-only transport, no tools')
 check(len(actual)<=65536,label+' within fixed profile64KiB public cap')
 check(b'synthetic-runtime-npc-test-only' not in h.read_bytes(),label+' no credential marker in transmitted body')
 check(request['schema_version']=='ai_gm_rebuilt/v1' and 'transport_scope' not in request,label+' unchanged current request schema and no second coast scope')
 check(not any(k in request for k in ('state','rng','source','engine','receipts','pending')),label+' no private authority envelope roots')
 if request['phase']=='assessment':
  facts=request['context']['facts']; identity=facts['generated_source']; focus=request['context']['attention_focus']
  check(identity['profile']=='generated_v3_village_npc/v1' and identity['projection_id']=='generated_v3_village_npc_context/v1',label+' exact current village public profile')
  check(len(facts['hexes'])<=62,label+' source projection cell bound retained')
  check(request['context']['goal'] and request['context']['actor_id']=='actor_player',label+' complete explicit goal and actor')
  if label=='learned_plant':
   check(bool(facts['learned_facts']),label+' acquired facts retained')
   check(focus['catalog_version']=='source-vegetation-focus/v1',label+' selected real plant witness retained')
   key=','.join(str(x) for x in focus['hex']);check(key in facts['hexes'],label+' selected outer support is public')
 else:
  check(request['phase']=='narration' and request['context'].get('provisional_until_commit') is False,label+' committed-only narration')
  check(request['context']['authoritative_result']['action_id']==request['action_id'],label+' exact receipt binding')
 rows.append({'label':label,'phase':request['phase'],'action_id':request['action_id'],'context_hash':request['context_hash'],'public_bytes':len(actual),'http_bytes':h.stat().st_size,'http_sha256':sha(h),'engine_sha256':sha(e)})
events_path=args.evidence/'events.json';check(events_path.is_file(),'event trace retained')
if events_path.is_file():
 events=json.loads(events_path.read_bytes()); by={r['label']:r for r in events}
 for r in events:check(r['live'] is False,r['label']+' explicitly mock provenance')
 if 'before_timeout' in by and 'retry_sent' in by:
  a,b=by['before_timeout'],by['retry_sent']
  check(a['authority_hash']==b['authority_hash'] and a['rng_hash']==b['rng_hash'],'timeout and manual retry preserve exact authority and RNG')
  check(b['sent']==a['sent']+1,'manual retry sends exactly one additional request')
  check(b['operation']['client_request_id']>a['operation']['client_request_id'],'retry uses a newer client token')
 if 'before_send' in by and 'after_talk_and_prose' in by:
  a,b=by['before_send'],by['after_talk_and_prose'];check(b['turn']==a['turn']+1,'one assessment and optional prose produce exactly one game turn')
  check(a['rng_hash']==b['rng_hash'],'registered direct talk does not consume a random draw')
report={'scope':'independent actual mock HTTP/readback only; no live provider executed','checks':len(checks),'failures':[r['label'] for r in checks if not r['ok']],'requests':rows,'assertions':checks}
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='assertions'},ensure_ascii=False,indent=2))
raise SystemExit(1 if report['failures'] else 0)

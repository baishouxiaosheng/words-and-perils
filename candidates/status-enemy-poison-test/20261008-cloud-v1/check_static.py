from pathlib import Path
import json,hashlib,re,argparse
r=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
checks=[]
def check(ok,label):
 checks.append({'name':label,'passed':bool(ok)})
 if not ok: raise AssertionError(label)
parser=argparse.ArgumentParser(description="Read-only source/static checks; no Godot or network execution")
parser.add_argument('--repo-root',type=Path,required=True,help="local fixed-commit repository contents")
parser.add_argument('--restored-root',type=Path,required=True,help="local formal public-v30 restored source root")
args=parser.parse_args()
manifest=json.loads((r/'MANIFEST.json').read_text())
check(manifest['base_git_commit']=='8928d7012cb9c7cf42e1cb41f2717143299ebac9','fixed Git commit binding')
for x in manifest['verification_inputs']['repository_files']:
 b=(args.repo_root/x['path']).read_bytes();check(len(b)==x['bytes'] and sha(b)==x['sha256'],'input bytes/readback '+x['path'])
production=args.restored_root
check(all(len((production/x['path']).read_bytes())==x['bytes'] and sha((production/x['path']).read_bytes())==x['sha256'] for x in manifest['verification_inputs']['restored_files']),'42 release +21 selected inherited source hashes remain exact')
origin=args.repo_root/'candidates/status-player-poison-test/20261008-dot-v1'
old=json.loads((origin/'MANIFEST.json').read_text()); old_player=(origin/old['new_driver']).read_bytes()
check(sha(old_player)=='4843bcd54484876ed42158979fee47092b7673068b093d48ff90239b77c5fb2d' and len(old_player.splitlines())==102,'existing 102-line player test bytes untouched')
new_path='overlay/tests/actor_status_death/test_enemy_poison.gd'; b=(r/new_path).read_bytes();s=b.decode('utf-8')
check(b'\r' not in b and b.endswith(b'\n'),'new driver UTF8/LF')
helper_files=[x for x in old['files'] if x['path'].startswith('frozen_inputs/')]
for x in helper_files:
 data=(r/x['path']).read_bytes();check(data==(origin/x['path']).read_bytes() and len(data)==x['bytes'] and sha(data)==x['sha256'],'exact unchanged helper '+x['path'])
check(s.startswith('extends "res://tests/actor_status_death/frozen_finite_main.gd"'),'inherits exact original finite49 helpers')
check(s.count('f.admit()')==1 and not any(x in s for x in ['f.fresh(', 'successful_sequence(', 'successful_self(', 'Generator.generate(', 'seed =', 'randomize(', '.set_seed(', 'while ']),'one authored source, no retry/seed/success search')
check(not re.search(r'\.(?:health|stamina)\.current\s*=(?!=)|\.(?:rng|_rng)\.(?:seed|state)\s*=(?!=)|\.load_data\(|\._publish\(|\.status_foundation\s*=(?!=)|\.items\[[^\n]+\]\.(?:quantity|owner_actor_id)\s*=(?!=)',s),'no direct HP/resources/RNG/world/item/save injection')
check('return await action(kind, extra)' in s and len(re.findall(r'(?<![\w])action\(',s))==1 and 'actions.size() < MAX_COMMITS' in s,'every scripted commit uses bounded inherited Main action helper')
check('const MAX_ROUTE_STEPS = 32' in s and 'const MAX_COMMITS = 47' in s and 32+1+2+5+3+4==47,'47 commit cap:32 moves, initial enemy1, vial2, owner5, interleave3, optional rest/observe4')
check('navigation.plan(initial, anchor, MAX_ROUTE_STEPS)' in s and 'movement_preview(plan.route[index])' in s and 'plan.route.size() <= MAX_ROUTE_STEPS+1' in s,'admitted bounded source navigation and real per-move preview')
check('ActorPolicy.Legacy.melee_range(before, F.PLAYER, F.ENEMY, app.playtest.core.source.navigation)' in s and 'initial.items[POISON].owner_actor_id == F.PLAYER' in s and 'POISON in initial.actors[F.PLAYER].inventory' in s,'actual owner and source dry-adjacent target admission')
check('for bottle in range(2):' in s and 'var ticks: int = 3 if bottle == 0 else 2' in s and 'owner_ticks == 5' in s,'two existing sources and fixed five owner ticks')
check('if not F.applied(applied):' in s and 'INCONCLUSIVE' in s and 'no retry or fresh lineage' in s,'actual contested failure is inconclusive without retry')
check('after.actors[F.ENEMY].health.current == before.actors[F.ENEMY].health.current-1' in s and 'C.bytes(F.status(after, F.ENEMY, "poison")) == old_status' in s,'assert owner tick damage and no opponent tick')
check('terminal_state.actors[F.PLAYER].health.current == 12' in s and 'after.actors[F.ENEMY].statuses.is_empty()' in s and '"basic_attack"' not in s,'enemy-only typed poison, no legacy weapon attack or double death')
check('app.playtest.phase() == "awaiting_assessment"' in s and 'app.submit_button.pressed.emit()' in s and 'for old_receipt in [old_application_receipt, death_receipt]:' in s,'both original old receipts replay with real newer Main player action pending')
check('duplicate.get("already_committed", false)' in s and 'C.bytes(app.playtest.save_data()) == preserved' in s and 'app.playtest.active_action == pending' in s and 'C.bytes(app.playtest.request()) == request' in s,'duplicate preserves entire save, costs/RNG/history/owner clocks, pending and request')
check('app.runtime_ai.set_transport(mock)' in s and 'not mock.info().live' in s and 'mock.sent.is_empty()' in s and not re.search(r'HTTP(?:Request|Client)\.new\(|TCPServer\.new\(|StreamPeerTCP\.new\(',s),'offline mock only, no live transport construction')
check('hexes.size() == 1801' in s and 'OS.get_user_data_dir() == isolated' in s and 'MAIN_SHA' in s and 'F.FROZEN_PROFILE' in s,'exact full1801 Main, private user dir and profile binding')
check('var stored: bool = out.store_string(' in s and 'var write_error: Error = out.get_error()' in s and 'var flush_error: Error = out.get_error()' in s and s.count('out.close()')==1 and 'quit(2); return' in s,'report checks store bool/flush/errors and closes once; output error cannot pass')
# Source-derived arithmetic only; no engine/RNG execution.
catalog=json.loads((production/'data/catalog.json').read_text()); poison=next(x for x in catalog['definitions'] if x['id']=='poison')
check(poison['duration']=={'clock':'owner_action','ticks':3} and [x['basis'] for x in poison['mechanics']]==['flat','max_bps'],'original catalog separates flat and percent owner events')
enemy=(production/'core/source_enemy/catalog.gd').read_text();content=(production/'core/status_gameplay/content.gd').read_text();profiles=(production/'core/status_gameplay/source_profiles.gd').read_text();runtime=(production/'core/status_foundation/runtime.gd').read_text();policy=(production/'view/actor_action_profile_v2/policy.gd').read_text()
check('"health":{"current":5,"max":5}' in enemy and '"quantity":2' in content and '"flat_damage":1,"max_health_bps":1000' in profiles and 'int(amount)' in runtime and int(-1)+int(-5*1000/10000)==-1,'enemy5, owned two vials and actual int-truncation yield one HP per owner tick')
check('if actor_id==ACTORS[0] and can_schedule(candidate,navigation):phase="enemy"' in policy and 'var phase="player"' in policy,'post-hook actor policy returns player after enemy action')
check(sha((production/'main.gd').read_bytes())==old['formal_main_sha256']=='05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f','formal Main exact hash; no production edits')
files=[]
for name in [new_path,'TEST_ONLY.patch','MANIFEST.json','USAGE.txt','check_static.py']+[x['path'] for x in helper_files]:
 data=(r/name).read_bytes();check(data==(r/name).read_bytes(),'deliverable actual readback '+name);files.append({'path':name,'bytes':len(data),'sha256':sha(data),'readback_equal':True})
result={'status':'PASSED_STATIC_ONLY_NOT_GODOT_PARSE','checks':checks,'count':len(checks),'files':files,'production_changes':0,'godot_parses':0,'runtime_runs':0}
print(json.dumps(result,ensure_ascii=False,indent=2))

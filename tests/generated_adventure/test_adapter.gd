extends SceneTree
const Adapter = preload("res://view/generated_adventure/adapter.gd")
const Generator = preload("res://core/world_generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Session = preload("res://view/generated_adventure/session.gd")
const CoastFixture = preload("res://view/ai_gm_playtest/adapter.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL "+message)
func run() -> void:
	var started:=Time.get_ticks_msec()
	var source:=Generator.generate(726381,4,{"generator_version":Generator.BIOMES_VERSION})
	var adapter:=Adapter.new(source)
	check(adapter.ready().ok,"exact generated source creates current program engine")
	if not adapter.ready().ok:printerr(adapter.ready());finish();return
	check(adapter.engine.rule_id()=="generated_exploration_release/v1","new version does not enable old rule authority")
	var state:=adapter.state_copy()
	check(state.actors.keys()==["actor_player"] and state.items.is_empty() and not state.flags.has("lamp_restored"),"no coast keeper/story/entities copied into arbitrary seed")
	var initial:=C.bytes(adapter.engine.save_data())
	var actor: Dictionary=state.actors.actor_player
	var from_key: String="%d,%d"%actor.hex
	var neighbor_key: String=adapter.source.navigation.allowed[from_key][0]
	var cell: Dictionary=state.hexes[neighbor_key]
	var target: Array=[cell.q,cell.r]
	var focus:=adapter.tile_reference(target)
	var selected:=adapter.attention(focus)
	check(selected.ok and selected.readonly and C.bytes(adapter.engine.save_data())==initial,"select tile is read-only and consumes no RNG")
	check(selected.focus.facts.has("biome") and selected.focus.facts.has("landform") and selected.focus.facts.has("elevation_q4096"),"focus has independent bounded biome/landform/source facts")
	check(not adapter.attention({"world_id":"other_seed","kind":"tile","id":cell.id,"hex":target}).ok,"focus from different seed rejected")
	check(not adapter.attention({"world_id":state.world_id,"kind":"tree","id":"coast_tree","hex":target}).ok,"coast/visual tree cannot become an unsupported actionable target")
	var preview:=adapter.movement_preview(target)
	check(preview.ok and preview.cost==Policy.COSTS[cell.terrain],"source dry edge uses canonical terrain effort")
	check(adapter.begin_intent(adapter.sample_goal("move",focus),focus).ok,"explicit move begins awaiting assessment")
	check(adapter.phase()=="awaiting_assessment" and C.bytes(adapter.state_copy())==C.bytes(state),"intent does not move or deduct resources")
	check(not adapter.roll_once().ok,"unassessed action cannot roll")
	var request:=adapter.request()
	check(request.context.facts.hexes.size()<=62 and C.bytes(request).to_utf8_buffer().size()<=65536,"public request is cell and byte bounded")
	check(not request.has("rng") and not request.context.facts.has("generated_world") and not request.context.facts.has("receipts") and not request.context.facts.has("pending"),"public request excludes raw source/save/RNG/receipts")
	check(request.contract.resolver_ids==["generated_move_v1","generated_observe_v1","generated_rest_v1"],"closed source-specific resolver registry")
	check(not adapter.import_reply({"phase":"resolution","state_patch":{"actors":{}}}).ok,"legacy arbitrary model patch rejected")
	check(adapter.prepare_fixture().ok and adapter.phase()=="ready_roll","exact signed assessment admitted")
	var action:=adapter.action_copy()
	check(action.checks[0].method=="direct_success" and action.branches.size()==2,"safe direct policy is program-owned with complete frozen branches")
	check(adapter.roll_once().ok and adapter.phase()=="rolled","result locks once")
	var locked:=C.bytes(adapter.save_data());var rng:=C.bytes(adapter.engine.save_data().rng)
	check(adapter.roll_once().ok and C.bytes(adapter.save_data())==locked,"repeat roll cannot consume RNG or change result")
	check(not adapter.cancel().ok,"locked result cannot cancel")
	check(adapter.save_file("user://generated_locked.json").ok,"locked save written atomically in isolated namespace")
	var restored:=Adapter.new()
	check(restored.load_file("user://generated_locked.json").ok,"restart admits source then verifies exact pending transaction")
	check(C.bytes(restored.save_data())==locked and C.bytes(restored.engine.save_data().rng)==rng,"locked save/restart preserves facts, plan, focus, RNG, and history exactly")
	check(restored.stage().ok and restored.commit().ok,"restored lock stages and commits through current engine")
	var committed:=restored.state_copy()
	check(committed.actors.actor_player.hex==target and committed.actors.actor_player.stamina.current==8-preview.cost and committed.turn==1 and committed.state_version==1,"persistent movement consequence and one turn")
	var receipt_id: String=restored.last_action
	var saved: Dictionary=restored.engine.save_data();var receipt: Dictionary=saved.receipts[receipt_id]
	check(restored.engine.commit(receipt_id,receipt.stage_hash).already_committed and C.bytes(restored.engine.save_data())==C.bytes(saved),"duplicate commit exactly once")
	var current_focus:=restored.tile_reference(target)
	check(restored.begin_intent(restored.sample_goal("observe",current_focus),current_focus).ok and restored.prepare_fixture().ok and restored.roll_once().ok and restored.stage().ok and restored.commit().ok,"assessed observation completes")
	check(restored.state_copy().flags.observations==1 and restored.state_copy().flags.last_observed_cell==neighbor_key,"observation has persistent program-owned consequence")
	check(restored.begin_intent(restored.sample_goal("rest")).ok and restored.prepare_fixture().ok and restored.roll_once().ok and restored.stage().ok and restored.commit().ok,"assessed rest completes")
	check(restored.state_copy().actors.actor_player.stamina.current==8,"rest recovers bounded stamina")
	var whole:=C.bytes(restored.save_data());check(restored.save_file("user://generated_committed.json").ok,"committed save written")
	var restarted:=Adapter.new();check(restarted.load_file("user://generated_committed.json").ok and C.bytes(restarted.save_data())==whole,"restart preserves committed observations/history exactly")
	var wet_found:=false
	for row in state.hexes.values():
		if row.ground_blocked:
			wet_found=true;check(not restarted.movement_preview([row.q,row.r]).ok,"water target cannot use dry movement");break
	check(wet_found,"fixture contains real unsupported water anchor")
	var tampered:=source.duplicate(true);tampered.hexes[from_key].elevation+=1.0/4096.0
	var bad:=Adapter.new(tampered);check(not bad.ready().ok,"modified mesh descriptor rejects stale hash")
	var unsigned:=tampered.duplicate(true);unsigned.erase("content_hash");tampered.content_hash=C.digest(unsigned)
	bad=Adapter.new(tampered);check(not bad.ready().ok,"resigned altered source rejected by seeded reproduction")
	var corrupt:=restarted.save_data();corrupt.engine.state.hexes[from_key].terrain="road"
	var before:=C.bytes(restarted.save_data());check(not restarted.load_data(corrupt).ok and C.bytes(restarted.save_data())==before,"forged cheaper terrain rejected atomically")
	corrupt=restarted.save_data();corrupt.engine.state.generated_world.runtime_hash="other"
	check(not restarted.load_data(corrupt).ok and C.bytes(restarted.save_data())==before,"runtime contract/source swap rejected atomically")
	corrupt=restarted.save_data();corrupt.engine.rule_id="coast_release/v1"
	check(not restarted.load_data(corrupt).ok and C.bytes(restarted.save_data())==before,"unknown/historical rule never silently upgraded")
	check(not restarted.load_data(restarted.engine.save_data()).ok,"raw engine or old pending save cannot masquerade as generated envelope")
	var coast:=CoastFixture.new(99);var coast_exact:=C.bytes(coast.engine.save_data())
	var session:=Session.new(coast)
	check(session.enter(restarted).ok,"independent session enters admitted generated world")
	var epoch:=session.epoch
	check(session.return_coast().ok and session.active==coast and C.bytes(coast.engine.save_data())==coast_exact,"coast return preserves original engine object and exact state/RNG")
	check(not session.import_at({},epoch,"old_action").ok,"late generated callback rejected after world switch")
	check(session.enter(restarted).ok,"return to existing generated progress")
	check(restarted.begin_intent(restarted.sample_goal("observe",current_focus),current_focus).ok,"create pending generated action")
	var pending:=C.bytes(restarted.save_data())
	check(not session.return_coast().ok and C.bytes(restarted.save_data())==pending,"pending action blocks switching without mutation")
	check(restarted.cancel().ok and session.return_coast().ok,"legal pre-roll cancel permits coast return")
	check(coast.begin_intent("Exact old pending test").ok,"coast fixture begins old pending action")
	var old_pending:=C.bytes(coast.engine.save_data())
	check(not session.enter(restarted).ok and C.bytes(coast.engine.save_data())==old_pending,"old pending exact preserved on generated entry rejection")
	# Weighted route test on an explicitly synthetic graph. No source edits are admitted.
	var graph:=state.duplicate(true);graph.hexes={};graph.actors.actor_player.hex=[0,0]
	for row in [[0,0,"grass"],[1,0,"mountain"],[2,0,"grass"],[0,1,"grass"],[1,1,"grass"]]:
		graph.hexes["%d,%d"%[row[0],row[1]]]={"q":row[0],"r":row[1],"scene_id":actor.scene_id,"terrain":row[2],"ground_blocked":false,"air_blocked":false,"all_blocked":false}
	var route:=Policy.plan(graph,"actor_player",[2,0],8,func(_a,_b):return {"ok":true})
	check(route.ok and route.cost==3 and route.route==[[0,0],[0,1],[1,1],[2,0]],"Dijkstra chooses lower accumulated effort detour, not shortest steps")
	var old_facts:=ModelView.facts(coast.state_copy(),{"npc_secret_allowlist":[],"public_flag_ids":[]})
	check(not old_facts.has("context_scope") and not old_facts.has("generated_source"),"old-world public projection shape is untouched")
	print("GENERATED_ADAPTER_METRICS ",JSON.stringify({"elapsed_ms":Time.get_ticks_msec()-started,"request_bytes":C.bytes(request).to_utf8_buffer().size(),"source_bytes":C.bytes(source).to_utf8_buffer().size(),"navigation":adapter.source.navigation.diagnostics}))
	finish()
func finish() -> void:
	print("GENERATED CURRENT AUTHORITY ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)

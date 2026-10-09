extends SceneTree
const Adapter=preload("res://view/playable_build/adapter.gd")
const Nav=preload("res://view/playable_build/navigation.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Movement=preload("res://view/playable_build/movement_resolver.gd")
const Presentation=preload("res://view/action_presentation.gd")
var assertions:=0
var failed:Array[String]=[]
func check(value:bool,label_:String)->void:
	assertions+=1
	if not value:failed.append(label_);printerr("FAIL: "+label_)
func _initialize()->void:call_deferred("run")
func movement_reply(adapter:RefCounted,disposition:String)->Dictionary:
	var req:Dictionary=adapter.request();var facts:Dictionary=req.context.facts
	return {"schema_version":"ai_gm_assessment/v1","action_id":req.action_id,"state_version":req.state_version,"context_hash":req.context_hash,"narration":"Offline route regression assessment, not live AI.","interpretation":"Explicit route to (3,8).","resolver_id":Movement.ID,"bindings":{"actor_id":"actor_player","target_hex":[3,8]},"components":[{"id":"move","parameters":{"A":3,"D":1,"P":0},"disposition":disposition,"fact_ref_ids":["player","target"]}],"fact_refs":[{"id":"player","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"target","path":"/hexes/3,8","expected":facts.hexes["3,8"]}],"provenance":{"provider":"offline movement regression fixture","live":false,"kind":"fixture"}}
func run()->void:
	var a:=Adapter.new(17);var original:=a.state_copy();var target:Array=[3,8]
	var route:=Nav.plan_route(original,"actor_player",target,8)
	check(route.ok,"real source path exists")
	if not route.ok:quit(1);return
	check(route.cost==7 and route.route.size()==8,"seven-edge real natural-water detour, geometric distance six")
	check(C.bytes(route)==C.bytes(Nav.plan_route(original,"actor_player",target,8)),"deterministic route tie ordering")
	for i in range(1,route.route.size()):check(Nav.step(route.route[i-1],route.route[i]).ok,"each frozen segment physically dry")
	var blocked:=original.duplicate(true);blocked.hexes["-1,13"].ground_blocked=true
	var detour:=Nav.plan_route(blocked,"actor_player",target,8)
	check(detour.ok and not [-1,13] in detour.route and detour.route!=route.route,"routes around dynamic blocker")
	check(not Nav.plan_route(original,"actor_player",target,6).ok,"insufficient total stamina refuses full route")
	check(not Nav.plan_route(original,"actor_player",target,0).ok,"zero budget refuses")
	check(not Nav.plan_route(original,"actor_player",original.actors.actor_player.hex,8).ok,"same target refuses free turn")
	for bad in [null,[],[1],['3',8],[3.2,8],[1001,0]]:check(not Nav.plan_route(original,"actor_player",bad,8).ok,"malformed or out-of-world destination refused")
	blocked.hexes["3,8"].all_blocked=true
	check(not Nav.plan_route(blocked,"actor_player",target,8).ok,"blocked destination refused")
	for offset in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]:
		blocked.hexes["%d,%d"%[-1+offset[0],14+offset[1]]].all_blocked=true
	blocked.hexes["3,8"].all_blocked=false
	check(not Nav.plan_route(blocked,"actor_player",target,8).ok,"enclosed origin unreachable atomically")
	var wrong:=original.duplicate(true);wrong.generated_world.bundle_id="stale"
	check(not Nav.plan_route(wrong,"actor_player",target,8).ok,"stale source/nav bundle refused")
	check(a.begin_intent(a.movement_goal(target)).ok,"one explicit route intent")
	check(a.state_copy()==original,"intent and preview never move")
	check(not a.begin_intent(a.movement_goal([-2,15])).ok,"concurrent context cannot replace intent")
	check(a.prepare_fixture().ok,"honest installed offline assessment accepted")
	check(a.action_copy().assessment.resolver_id==Movement.ID and not a.action_copy().assessment.provenance.live,"new version explicit and fixture not live AI")
	check(a.state_copy()==original,"assessment freezes but does not execute")
	check(a.frozen_movement_preview().route==route.route and a.frozen_movement_preview().cost==7,"preview derives frozen actual patches")
	for phase in ["ready_roll","rolled","staged"]:
		check(a.phase()==phase,"expected phase "+phase)
		var saved_action:=C.bytes(a.action_copy())
		check(a.save_file("user://multistep_"+phase+".json").ok,"save "+phase)
		var loaded:=Adapter.new(9)
		check(loaded.load_file("user://multistep_"+phase+".json").ok,"restore frozen "+phase)
		check(C.bytes(loaded.action_copy())==saved_action,"same path, costs and dice after load "+phase)
		if phase=="ready_roll":check(a.roll_once().ok,"resolve once")
		elif phase=="rolled":
			check(a.roll_once().ok and C.bytes(a.action_copy())==saved_action,"second resolve cannot reroll")
			check(not a.cancel().ok,"cannot cancel locked route")
			check(a.stage().ok and a.state_copy()==original,"stage atomic no partial movement")
		else:
			check(loaded.commit().ok,"loaded route commits")
			var locked:=a.action_copy();var committed:=a.commit()
			check(committed.ok,"original route commits")
			check(C.bytes(a.state_copy())==C.bytes(loaded.state_copy()),"loaded/original exact same final effect")
			var final_state:=a.state_copy()
			check(final_state.actors.actor_player.hex==target and final_state.actors.actor_player.stamina.current==1,"destination and seven stamina charged")
			check(final_state.turn==1 and final_state.state_version==1,"whole route one turn/version")
			check(final_state.actors.actor_scout.patrol.index==(original.actors.actor_scout.patrol.index+1)%original.actors.actor_scout.patrol.route.size(),"patrol advances exactly once")
			var after:=C.bytes(final_state)
			check(a.engine.commit(locked.action_id,locked.stage_hash).already_committed and C.bytes(a.state_copy())==after,"duplicate commit no extra movement/cost/patrol")
	# Manual/offline negative cases use the same versioned assessment envelope.
	var negative:=Adapter.new(23);negative.begin_intent(negative.movement_goal(target))
	var reply:=movement_reply(negative,"possible")
	var stale:=reply.duplicate(true);stale.context_hash="different frozen context"
	check(not negative.engine.prepare_assessment(stale).ok and negative.state_copy()==original,"stale context cannot prepare or mutate")
	stale=reply.duplicate(true);stale.state_version+=1
	check(not negative.engine.prepare_assessment(stale).ok and negative.phase()=="awaiting_assessment","stale version cannot replace current context")
	check(negative.engine.prepare_assessment(reply).ok and negative.roll_once().ok,"possible assessment uses program one-time roll")
	var random_lock:=C.bytes(negative.action_copy());var random_rng:=C.bytes(negative.engine.save_data().rng)
	check(negative.roll_once().ok and C.bytes(negative.action_copy())==random_lock and C.bytes(negative.engine.save_data().rng)==random_rng,"random route re-resolve consumes no new RNG")
	negative.save_file("user://multistep_random.json");var random_loaded:=Adapter.new(999)
	check(random_loaded.load_file("user://multistep_random.json").ok and C.bytes(random_loaded.action_copy())==random_lock,"random route load preserves exact die and branch")
	var tampered:Dictionary=negative.engine.save_data();var action_id:String=negative.active_action
	for branch in tampered.pending[action_id].branches:
		if branch.requires.move:branch.patches[1].hex=[0,13]
	check(not random_loaded.engine.load_data(tampered).ok and C.bytes(random_loaded.action_copy())==random_lock,"tampered saved waypoint rejects without replacing current lock")
	negative.engine._state.hexes["-1,13"].ground_blocked=true
	var changed:=C.bytes(negative.state_copy())
	check(not negative.stage().ok and C.bytes(negative.state_copy())==changed,"concurrent world blocker change prevents stale atomic stage")
	var exhausted:=Adapter.new(17);var exhausted_data:Dictionary=exhausted.engine.save_data();exhausted_data.state.actors.actor_player.stamina.current=6
	check(exhausted.engine.load_data(exhausted_data).ok,"low-resource fixture admitted")
	exhausted.begin_intent(exhausted.movement_goal(target));var low_before:=C.bytes(exhausted.engine.save_data())
	check(not exhausted.prepare_fixture().ok and C.bytes(exhausted.engine.save_data())==low_before,"unaffordable assessed route changes no state, action phase, RNG or resources")
	var denied:=Adapter.new(17);denied.begin_intent(denied.movement_goal(target))
	check(denied.engine.prepare_assessment(movement_reply(denied,"impossible")).ok and denied.roll_once().ok and denied.stage().ok and denied.commit().ok,"assessed failure completes its one approved turn")
	check(denied.state_copy().actors.actor_player.hex==original.actors.actor_player.hex and denied.state_copy().actors.actor_player.stamina==original.actors.actor_player.stamina and denied.state_copy().turn==1,"failure stays put and spends no route stamina")
	# A five-action registry save still validates and replays the v1 frozen move.
	var old:=Adapter.new(17);old.engine=old._make_engine(17,false,false,false)
	var old_goal:=old.sample_goal("move")
	var begun:Dictionary=old.engine.begin_intent(old_goal);old.active_action=begun.request.action_id
	check(old.prepare_fixture().ok and old.roll_once().ok and old.stage().ok,"old v1 action frozen under historical registry")
	var old_locked:=C.bytes(old.action_copy());old.save_file("user://multistep_old_v1.json")
	var upgrade:=Adapter.new(11)
	check(upgrade.load_file("user://multistep_old_v1.json").ok and C.bytes(upgrade.action_copy())==old_locked,"old pending route unmodified on load")
	check(upgrade.commit().ok and upgrade.begin_intent(upgrade.movement_goal(target)).ok,"old save upgrades only after pending commit")
	check(Movement.ID in upgrade.engine.save_data().resolver_ids,"new route registry available after idle migration")
	# Visual queue traverses every segment, interruption snaps to authoritative end.
	var presentation:=Presentation.new();root.add_child(presentation);presentation.set_process(false)
	var token:=Node3D.new();root.add_child(token);presentation.register_actor("p",token,Vector3.ZERO)
	var points:Array=[Vector3(1,0,0),Vector3(1,0,1),Vector3(2,0,1),Vector3(2,0,2)]
	presentation.move_actor_path("p",points,.75)
	for point in points:
		presentation._process(.4);check(token.position.y>0,"per-segment lift arc")
		presentation._process(2);check(token.position.is_equal_approx(point),"lands each ordered waypoint")
	check(not presentation.actors.p.moving and presentation.actors.p.support==points.back(),"final visual equals authority")
	presentation.move_actor_path("p",[Vector3(3,0,2),Vector3(4,0,2)],.75);presentation._process(.2);presentation.cancel_all();presentation._process(4)
	check(token.position==Vector3(4,0,2) and not presentation.actors.p.moving,"load/cancel discards stale queue and snaps final authority")
	presentation.move_actor_path("p",[Vector3(5,0,2),Vector3(6,0,2)],.75);presentation._process(.2)
	presentation.move_actor_path("p",[Vector3(6,0,3),Vector3(6,0,4)],.75)
	check(token.position==Vector3(6,0,2) and presentation.actors.p.from==Vector3(6,0,2),"new committed action cancels old visual route at prior authoritative endpoint")
	presentation.queue_free();token.queue_free();await process_frame
	var report={"assertions":assertions,"failed":failed,"route":route,"offline_fixture":true,"live_ai_tested":false,"native_tested":false}
	var file:=FileAccess.open("res://tests/playable_build/multistep_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MULTISTEP MOVEMENT ",assertions-failed.size(),"/",assertions," route=",route.route)
	quit(0 if failed.is_empty() else 1)

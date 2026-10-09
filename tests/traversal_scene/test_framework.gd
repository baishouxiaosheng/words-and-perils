extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Coast = preload("res://view/playable_build/world.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Nav = preload("res://view/playable_build/navigation.gd")
const Registry = preload("res://view/playable_build/scene_adapters.gd")
const Fixture = preload("res://view/playable_build/scene_framework_fixture.gd")
const Move = preload("res://view/playable_build/weighted_movement_resolver.gd")
const Transition = preload("res://view/playable_build/scene_transition_resolver.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const Rule = preload("res://tests/core_gameplay/test_release_rule.gd")
const Focus = preload("res://core/focus_contract.gd")
const RoomBoard = preload("res://view/playable_build/scene_test_board.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
var checks := 0
var failures: Array = []
func expect(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label);push_error(label)
func engine_for(state: Dictionary) -> RefCounted:
	var move := Move.new();var transition := Transition.new();var registry := {move.ID:move,transition.ID:transition}
	return GMEngine.new(state,Rule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":[]},67)
func assess(engine: RefCounted,goal: String,resolver: String,bindings: Dictionary,component: String,focus: Dictionary = {}) -> Dictionary:
	var begun: Dictionary=engine.begin_intent(goal,focus)
	expect(begun.ok,"begin "+goal)
	if not begun.ok:return {}
	var request: Dictionary=begun.request
	var actor: Dictionary=request.context.facts.actors.actor_player
	var reply := {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"框架测试，未运行模型。","interpretation":goal,"resolver_id":resolver,"bindings":bindings,"components":[{"id":component,"parameters":{"A":3,"D":1,"P":0},"disposition":"certain","fact_ref_ids":["actor"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":actor}],"provenance":{"provider":"manual_framework_test","live":false,"kind":"model_reply"}}
	var prepared: Dictionary=engine.prepare_assessment(reply)
	expect(prepared.ok,"prepare "+goal)
	if not prepared.ok:print(prepared);return {}
	return {"id":request.action_id,"reply":reply}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var state := Coast.world()
	expect(World.validate(state).ok,"legacy world unchanged valid")
	var legacy_bytes := C.bytes(state)
	Fixture.install(state)
	expect(World.validate(state).ok,"optional scene maps and reciprocal entrances valid")
	expect(state.hexes.has("0,0") and state.scene_hexes[Fixture.ROOM].has("0,0"),"outer and interior reuse local coordinate")
	expect(state.hexes["0,0"].id!=state.scene_hexes[Fixture.ROOM]["0,0"].id,"overlapping cell stable identity distinct")
	var bad := state.duplicate(true);bad.scene_transitions.entrance_framework_room.destination_scene_id="absent"
	expect(not World.validate(bad).ok,"absent destination rejected")
	bad=state.duplicate(true);bad.scene_transitions.entrance_framework_return.landing_hex=[999,999]
	expect(not World.validate(bad).ok,"bad return landing rejected")
	bad=state.duplicate(true);bad.actors.actor_player.traversal_profile={"policy_id":Policy.ID,"terrain_discounts":{"forest":9},"max_action_cost":32}
	expect(not World.validate(bad).ok,"out of bound capabilities rejected")
	var transition_assessment:={"bindings":{"actor_id":"actor_player","entrance_id":"entrance_framework_room"},"components":[{"id":"transition"}]}
	bad=state.duplicate(true);bad.generated_world.bundle_id="wrong_bundle"
	expect(not Transition.new().freeze(bad,transition_assessment).ok,"wrong source geography cannot use entrance")
	bad=state.duplicate(true);bad.scene_hexes[Fixture.ROOM]["0,0"].ground_blocked=true
	expect(not Transition.new().freeze(bad,transition_assessment).ok,"blocked landing rejects transition")
	bad=state.duplicate(true);bad.scene_hexes[Fixture.ROOM]["0,0"].terrain="water"
	expect(not Transition.new().freeze(bad,transition_assessment).ok,"water landing rejects even authored dry adapter")
	bad=state.duplicate(true);bad.scenes[Fixture.ROOM].renderer_id="uninstalled"
	expect(not Transition.new().freeze(bad,transition_assessment).ok,"uninstalled destination renderer rejects transition")
	var e := engine_for(state)
	expect(e.ready().ok,"scene engine ready")
	var before := C.bytes(e.state_copy());var begun: Dictionary=e.begin_intent("进入测试室")
	expect(begun.ok and C.bytes(e.state_copy())==before,"intent cannot transition without assessment")
	e.cancel_intent(begun.request.action_id)
	var action := assess(e,"明确使用测试入口",Transition.ID,{"actor_id":"actor_player","entrance_id":"entrance_framework_room"},"transition")
	if action.is_empty():quit(1);return
	for phase in ["ready_roll","rolled","staged"]:
		var saved: Dictionary=e.save_data();var reload:=engine_for(state)
		expect(reload.load_data(saved).ok and C.bytes(reload.save_data())==C.bytes(saved),"scene exact save/load "+phase)
		e=reload
		if phase=="ready_roll":expect(e.roll_once(action.id).ok,"transition roll once")
		elif phase=="rolled":expect(e.stage(action.id).ok,"transition stage")
	expect(e.state_copy().actors.actor_player.scene_id=="scene_coast","staged transition not published")
	var staged: Dictionary=e.action_copy(action.id)
	expect(e.commit(action.id,staged.stage_hash).ok,"transition commit")
	var entered: Dictionary=e.state_copy()
	expect(entered.actors.actor_player.scene_id==Fixture.ROOM and entered.actors.actor_player.hex==[0,0],"actual scene and local landing changed")
	expect(entered.turn==1 and entered.actors.actor_player.stamina.current==7,"scene one turn one stamina")
	expect(entered.actors.actor_scout.patrol.index==1,"transition patrol once")
	var after := C.bytes(entered);e.commit(action.id,staged.stage_hash)
	expect(C.bytes(e.state_copy())==after,"duplicate commit does not transition/cost twice")
	expect(e.authoritative_result(action.id).public_effects.any(func(p):return p.type=="actor_scene_transition"),"scene event published")
	var focus:=Focus.new();var room_ref:={"world_id":state.world_id,"kind":"tile","id":Cells.local_id(Fixture.ROOM,[0,0]),"hex":[0,0],"scene_id":Fixture.ROOM}
	var resolved: Dictionary=focus.resolve(room_ref,entered)
	expect(resolved.ok and Focus.validate_scene_scope(resolved.focus,entered),"room attention scoped")
	if resolved.ok:
		var public_: Dictionary=ModelView.focus_view(resolved.focus,ModelView.facts(entered,{"npc_secret_allowlist":[],"public_flag_ids":[]}))
		expect(public_.facts.id==room_ref.id,"room attention projection correct same-coordinate cell")
		expect(focus.validate_historical(resolved.focus,entered).is_empty(),"local historical focus survives")
	var coast_ref:={"world_id":state.world_id,"kind":"tile","id":state.hexes["0,0"].id,"hex":[0,0]}
	var outside: Dictionary=focus.resolve(coast_ref,entered)
	expect(outside.ok and not Focus.validate_scene_scope(outside.focus,entered),"same-coordinate outside focus rejected in room")
	var p := Nav.plan_weighted_route(entered,"actor_player",[1,0],7)
	expect(p.ok and p.cost==1 and p.scene_id==Fixture.ROOM,"room navigation uses room adapter no coast water")
	var changed:=entered.duplicate(true);changed.scene_hexes[Fixture.ROOM]["1,0"].ground_blocked=true
	expect(not Nav.plan_weighted_route(changed,"actor_player",[1,0],7).ok,"room blocked target rejected")
	changed=entered.duplicate(true);changed.scenes[Fixture.ROOM].renderer_id="missing"
	expect(not Nav.plan_weighted_route(changed,"actor_player",[1,0],7).ok,"missing renderer adapter rejects movement")
	var reloaded:=engine_for(state)
	expect(reloaded.load_data(e.save_data()).ok and reloaded.state_copy().actors.actor_player.scene_id==Fixture.ROOM,"saved active scene restored")
	e=reloaded
	action=assess(e,"明确返回海岸",Transition.ID,{"actor_id":"actor_player","entrance_id":"entrance_framework_return"},"transition")
	if action.is_empty():quit(1);return
	e.roll_once(action.id);e.stage(action.id);expect(e.commit(action.id,e.action_copy(action.id).stage_hash).ok,"saved return transition commits")
	expect(e.state_copy().actors.actor_player.scene_id=="scene_coast" and e.state_copy().actors.actor_player.hex==state.actors.actor_player.hex,"return exact source scene and entrance")
	# Five-cell graph: two costly edges vs three cheap edges. Stable positive costs.
	var tiny:=entered.duplicate(true);tiny.scene_hexes[Fixture.ROOM]={};tiny.scenes[Fixture.ROOM].hex_ids=[]
	for h in [[0,0],[1,0],[2,0],[0,1],[1,1]]:
		var cell:={"id":Cells.local_id(Fixture.ROOM,h),"q":h[0],"r":h[1],"scene_id":Fixture.ROOM,"terrain":"hill" if h==[1,0] else "floor","ground_blocked":false,"air_blocked":false,"all_blocked":false}
		tiny.scene_hexes[Fixture.ROOM][Cells.key(h)]=cell;tiny.scenes[Fixture.ROOM].hex_ids.append(cell.id)
	var weighted:=Nav.plan_weighted_route(tiny,"actor_player",[2,0],7)
	expect(weighted.ok and weighted.cost==3 and weighted.distance==3,"minimum cost chooses longer route over two costly edges")
	var move_engine:=engine_for(tiny)
	expect(move_engine.ready().ok,"weighted engine ready")
	var move_action:=assess(move_engine,"地形加权三步路线",Move.ID,{"actor_id":"actor_player","target_hex":[2,0]},"move",room_ref)
	if move_action.is_empty():quit(1);return
	var move_saved: Dictionary=move_engine.save_data();var move_reload:=engine_for(tiny)
	expect(move_reload.load_data(move_saved).ok and C.bytes(move_reload.save_data())==C.bytes(move_saved),"weighted pending frozen exact reload")
	var tampered: Dictionary=move_saved.duplicate(true)
	tampered.state.scene_hexes[Fixture.ROOM]["1,0"].terrain="floor"
	expect(not engine_for(tiny).load_data(tampered).ok,"changed terrain invalidates pending snapshot")
	move_reload.roll_once(move_action.id);move_reload.stage(move_action.id)
	expect(move_reload.commit(move_action.id,move_reload.action_copy(move_action.id).stage_hash).ok,"weighted route commit")
	expect(move_reload.state_copy().actors.actor_player.stamina.current==4 and move_reload.state_copy().actors.actor_player.hex==[2,0],"weighted frozen cost and arrival exact")
	expect(move_reload.state_copy().turn==2 and move_reload.state_copy().actors.actor_scout.patrol.index==2,"weighted multiple edges consume one patrol/turn")
	expect(engine_for(tiny).load_data(move_reload.save_data()).ok,"historical focused local receipt reload")
	var visual_variant:=tiny.duplicate(true);visual_variant.scene_hexes[Fixture.ROOM]["1,0"].visual_height=1000
	expect(Nav.plan_weighted_route(visual_variant,"actor_player",[2,0],7).cost==weighted.cost,"visual height does not alter authoritative terrain cost")
	var capability:=tiny.duplicate(true);capability.actors.actor_player.traversal_profile={"policy_id":Policy.ID,"terrain_discounts":{"hill":2},"max_action_cost":4}
	var discounted:=Nav.plan_weighted_route(capability,"actor_player",[2,0],7)
	expect(discounted.ok and discounted.cost==2 and discounted.distance==2 and discounted.budget==4,"bounded authored terrain capability changes path and budget")
	capability.actors.actor_player.traversal_profile.max_action_cost=1
	expect(not Nav.plan_weighted_route(capability,"actor_player",[2,0],7).ok,"authored action budget enforced")
	tiny.actors.actor_player.statuses={"status_flight":{"id":"status_flight","kind":"flight","remaining_turns":3,"magnitude":1}}
	tiny.scene_hexes[Fixture.ROOM]["1,0"].ground_blocked=true
	var flying:=Nav.plan_weighted_route(tiny,"actor_player",[2,0],7)
	expect(flying.ok and flying.cost==2 and flying.route[1]==[1,0],"flight bypasses ground-only obstacle with dry cost1")
	tiny.scene_hexes[Fixture.ROOM]["1,0"].air_blocked=true
	expect(Nav.plan_weighted_route(tiny,"actor_player",[2,0],7).distance==3,"flight cannot bypass air wall")
	tiny.scene_hexes[Fixture.ROOM]["1,0"].all_blocked=true
	expect(Nav.plan_weighted_route(tiny,"actor_player",[2,0],7).distance==3,"flight cannot bypass all wall")
	var coast_flight:=Coast.world();coast_flight.actors.actor_player.statuses=tiny.actors.actor_player.statuses.duplicate(true)
	var water_pair: Array=Nav.cache.water_contact_pairs[0]
	var a: PackedStringArray=String(water_pair[0]).split(",");var b: PackedStringArray=String(water_pair[1]).split(",")
	expect(not Nav.step([int(a[0]),int(a[1])],[int(b[0]),int(b[1])]).ok,"flight never changes source water edge policy")
	coast_flight.actors.actor_player.hex=[int(a[0]),int(a[1])]
	expect(not Nav.plan_weighted_route(coast_flight,"actor_player",[int(b[0]),int(b[1])],1).ok,"active flight cannot use one-step physical water shortcut")
	var legacy: Dictionary=JSON.parse_string(legacy_bytes)
	expect(World.validate(legacy).ok and C.bytes(legacy)==legacy_bytes and not legacy.has("scene_hexes"),"legacy no-map bytes unchanged")
	var adapter:=Adapter.new(92,true)
	expect(adapter.start_scene_framework_test(92).ok,"explicit new framework adapter session")
	for kind in ["enter_scene","return_scene"]:
		var goal: String=adapter.sample_goal(kind)
		expect(not goal.is_empty() and adapter.begin_intent(goal).ok and adapter.fixture_available(),"authored transition goal recognized "+kind)
		var prepared: Dictionary=adapter.prepare_fixture()
		expect(prepared.ok,"strict release authored transition accepted "+kind)
		if not prepared.ok:print(prepared);quit(1);return
		adapter.roll_once();adapter.stage();expect(adapter.commit().ok,"authored transition commit "+kind)
		var path:="user://scene_framework_roundtrip.json"
		expect(adapter.save_file(path).ok,"save scene adapter "+kind)
		var reload_adapter:=Adapter.new()
		expect(reload_adapter.load_file(path).ok and C.bytes(reload_adapter.engine.save_data())==C.bytes(adapter.engine.save_data()),"adapter exact scene save/load "+kind)
		adapter=reload_adapter
	print("TRAVERSAL SCENE ",checks-failures.size(),"/",checks," ",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
const SourceProof=preload("res://tests/settlement/source_proof.gd")
const Adapter=preload("res://view/playable_build/adapter.gd")
const Content=preload("res://view/playable_build/settlement_content.gd")
const Catalog=preload("res://view/playable_build/entity_catalog.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Nav=preload("res://view/playable_build/navigation.gd")
const Traversal=preload("res://core/ai_gm_rebuilt/traversal.gd")
const Focus=preload("res://core/focus_contract.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Attack=preload("res://core/ai_gm_rebuilt/basic_actions.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func _initialize()->void:call_deferred("run")
func finish(a:RefCounted,goal:String,focus:Dictionary={})->bool:
	var before:=C.bytes(a.state_copy())
	if not check(a.begin_intent(goal,focus).ok,"intent "+goal):return false
	check(C.bytes(a.state_copy())==before,"intent unchanged")
	var prepared:Dictionary=a.prepare_fixture()
	if not check(prepared.ok,"assessment "+goal+str(prepared.get("message",""))):print(prepared);return false
	check(C.bytes(a.state_copy())==before,"assessment unchanged")
	if not check(a.roll_once().ok,"program adjudication"):return false
	if not check(a.stage().ok,"program stage"):return false
	var id:String=a.active_action;var hash_:String=a.action_copy().stage_hash
	if not check(a.commit().ok,"atomic commit"):return false
	var committed:=C.bytes(a.state_copy());check(a.engine.commit(id,hash_).ok and C.bytes(a.state_copy())==committed,"duplicate commit idempotent")
	return true
func run()->void:
	var source_start:=SourceProof.snapshot()
	var a:=Adapter.new(751,true);var state:=a.state_copy();var data:=Content.manifest()
	if not check(a.engine.ready().ok and Content.active(state),"new release world valid content"):print(a.engine.ready());quit(1);return
	check(data.wall_edges.size()==12 and data.interior_hexes.size()==3,"three-cell city boundary has twelve edges")
	var vertices:Dictionary={};var gates:=0
	for edge in data.wall_edges:
		for point in [edge.a,edge.b]:
			var k:="%.6f,%.6f"%[point[0],point[2]];vertices[k]=int(vertices.get(k,0))+1
		if edge.is_gate:gates+=1
		check(not Content.edge_allowed(state,state.actors.actor_player,edge.inside_hex,edge.outside_hex),"closed wall rejects "+edge.id)
		check(not Content.edge_allowed(state,state.actors.actor_player,edge.inside_hex,edge.outside_hex,true),"binary attack closed "+edge.id)
	check(gates==1,"one gate edge")
	for count in vertices.values():check(count==2,"joined ring vertex degree two")
	check(Nav.ready(),"physical source navigation ready")
	for section in data.road_sections:
		for side in ["left","center","right"]:
			var p:Array=section[side].position;var wet:Dictionary=Nav.water.water_endpoint_context(Vector2(p[0],p[2]))
			check(wet.ok and not wet.is_water,"road ribbon dry source sample")
	for i in range(1,data.road_hexes.size()):check(Nav.step(data.road_hexes[i-1],data.road_hexes[i]).ok,"road actual dry edge")
	check(Content.all_settlements().size()==3,"three explicit1/1/3 source-bound sites")
	for place in Content.all_settlements():
		check(place.interior_hexes.size()==(3 if place.site_kind=="large_city" else 1),"requested footprint scale "+place.site_kind)
		check(a.attention(Catalog.make_reference(place.id,state)).ok,"stable settlement selection "+place.name)
		for district in place.districts:
			var selected:Dictionary=a.attention(Catalog.make_reference(district.id,state))
			check(selected.ok and selected.focus.kind=="district" and selected.focus.facts.entity.public_facts.settlement_id==place.id and not selected.focus.facts.entity.state.ground_blocking,"district independently selectable; does not claim a blocked floor")
		for edge in place.wall_edges:check(Content.edge_allowed(state,state.actors.actor_player,edge.inside_hex,edge.outside_hex)==(not place.walled),"data driven site wall policy")
		for section in place.road_sections:
			for side in ["left","center","right"]:
				var point:Array=section[side].position;var water:Dictionary=Nav.water.water_endpoint_context(Vector2(point[0],point[2]))
				check(water.ok and not water.is_water,"all sites source ribbon dry")
		for i in range(1,place.road_sections.size()):
			for side in ["left","center","right"]:
				var p:Array=place.road_sections[i-1][side].position;var q:Array=place.road_sections[i][side].position
				var contact:Dictionary=Nav.water.segment_intersects_water(Vector2(p[0],p[2]),Vector2(q[0],q[2]))
				check(contact.ok and not contact.intersects,"all road ribbon sides avoid physical water")
	var legacy:=Adapter.new(77);var legacy_state:=legacy.state_copy()
	check(not legacy_state.has("settlement_state") and Catalog.make_reference(data.id,legacy_state).is_empty(),"legacy no invented content")
	check(legacy.begin_intent(legacy.sample_goal("observe")).ok and legacy.prepare_fixture().ok,"historical action prepared")
	var old_saved:Dictionary=legacy.engine.save_data()
	check(legacy.save_file("user://settlement_legacy_pending.json").ok,"historical save written")
	var restored:=Adapter.new();check(restored.load_file("user://settlement_legacy_pending.json").ok and C.bytes(restored.engine.save_data())==C.bytes(old_saved),"historical pending exact registry/state/replay")
	check(not restored.state_copy().has("settlement_state"),"old pending save gets no settlement gifts or teleport")
	var before:=C.bytes(state);var ref:=Catalog.make_reference(data.id,state);var gate_ref:=Catalog.make_reference(data.gate_id,state)
	check(a.attention(ref).ok and a.attention(gate_ref).ok and C.bytes(a.state_copy())==before,"city and gate selection read only")
	check(a.begin_intent("只观察围寨，不开门。",ref).ok,"free text remains exact city context")
	check(a.request().context.facts.settlement.id==data.id and a.request().context.attention_focus.facts.entity.id==data.id,"public stable settlement and frozen selection")
	check(not a.fixture_available(),"free text gets no scripted gate fallback")
	var scoped=preload("res://view/runtime_ai/scoped_engine.gd").new(a.engine,func():return true)
	var sent:Dictionary=scoped.model_request(a.active_action)
	check(not sent.is_empty() and sent.context.facts.settlements.size()==3 and scoped.last_metrics.sent_public_bytes<=65536,"all city/district facts fit public transport budget")
	a.cancel()
	check(a.begin_intent(a.sample_goal("open_gate")).ok,"distant gate intent still requires assessment")
	var distant:Dictionary=a.prepare_fixture()
	check(not distant.ok and distant.get("code")=="GATE_RANGE" and C.bytes(a.state_copy())==before,"distant gate assessed range rejects with no action")
	a.cancel()
	check(not a.movement_preview(data.center_hex).ok,"closed ring prevents exterior entry")
	check(Nav.plan_weighted_route(state,"actor_player",state.actors.actor_keeper.hex,8).ok,"existing keeper approach unchanged")
	check(Nav.plan_weighted_route(state,"actor_player",state.actors.actor_raider.hex,8).ok,"existing raider approach unchanged")
	if not finish(a,a.movement_goal(data.gate_outside_hex)):quit(1);return
	check(a.state_copy().actors.actor_player.hex==data.gate_outside_hex,"actual source gate approach")
	var arrived:Dictionary=a.state_copy();check(not a.movement_preview(data.gate_inside_hex).ok,"closed gate rejects assessed movement")
	check(a.begin_intent(a.sample_goal("open_gate"),Catalog.make_reference(data.gate_id,arrived)).ok,"gate intent")
	var frozen_request:Dictionary=a.request();check(a.prepare_fixture().ok,"gate assessed safe direct")
	for phase in ["ready_roll","rolled","staged"]:
		check(a.save_file("user://settlement_pending.json").ok,"gate pending save "+phase)
		var save_before:Dictionary=a.engine.save_data();var reloaded:=Adapter.new()
		var loaded:Dictionary=reloaded.load_file("user://settlement_pending.json")
		if not check(loaded.ok and C.bytes(reloaded.engine.save_data())==C.bytes(save_before),"gate exact reload "+phase):print(loaded);quit(1);return
		a=reloaded
		if phase=="ready_roll":check(a.roll_once().ok,"gate fixed roll")
		elif phase=="rolled":check(a.stage().ok,"gate staged")
	check(not Content.gate_open(a.state_copy(),data.gate_id),"staged gate not yet published")
	check(a.commit().ok,"gate committed")
	var opened:Dictionary=a.state_copy()
	check(Content.gate_open(opened,data.gate_id) and opened.settlement_state.revision==1,"open state revision persisted")
	check(opened.turn==arrived.turn+1 and opened.actors.actor_player.stamina.current==arrived.actors.actor_player.stamina.current-1,"gate cost one stamina one turn")
	check(opened.actors.actor_scout.patrol.index==(int(arrived.actors.actor_scout.patrol.index)+1)%arrived.actors.actor_scout.patrol.route.size(),"gate ticks existing patrol exactly once")
	check(not a.attention(gate_ref).ok,"old gate selection revision rejected")
	check(Focus.new().validate_historical(frozen_request.context.attention_focus,opened).is_empty(),"historical closed gate focus valid after open")
	for edge in data.wall_edges:check(Content.edge_allowed(opened,opened.actors.actor_player,edge.inside_hex,edge.outside_hex)==edge.is_gate,"only open gate admits ground "+edge.id)
	var flying:=opened.duplicate(true);flying.settlement_state.gate_states[data.gate_id]=false;flying.settlement_state.revision=2;flying.actors.actor_player.statuses.flight_test={"id":"flight_test","kind":"flight","remaining_turns":3,"magnitude":1}
	for edge in data.wall_edges:
		check(Content.edge_allowed(flying,flying.actors.actor_player,edge.inside_hex,edge.outside_hex),"explicit flight clears ground wall")
		check(not Content.edge_allowed(flying,flying.actors.actor_player,edge.inside_hex,edge.outside_hex,true),"flight does not invent projectile arcs")
	if not finish(a,a.movement_goal(data.center_hex)):quit(1);return
	check(data.center_hex==a.state_copy().actors.actor_player.hex,"walk entered city through gate")
	check(a.save_file("user://settlement_entered.json").ok,"entered save written")
	var saved_state:=C.bytes(a.state_copy());a=Adapter.new();check(a.load_file("user://settlement_entered.json").ok and C.bytes(a.state_copy())==saved_state,"restart restores city location and gate")
	if not finish(a,a.sample_goal("rest")):quit(1);return
	if not finish(a,a.movement_goal(data.gate_inside_hex)):quit(1);return
	if not finish(a,a.sample_goal("close_gate")):quit(1);return
	check(not a.movement_preview(data.gate_outside_hex).ok,"closed gate prevents departure")
	if not finish(a,a.sample_goal("rest")):quit(1);return
	if not finish(a,a.sample_goal("open_gate")):quit(1);return
	if not finish(a,a.movement_goal(data.gate_outside_hex)):quit(1);return
	if not finish(a,a.sample_goal("rest")):quit(1);return
	if not finish(a,a.movement_goal([-1,14])):quit(1);return
	check(a.state_copy().actors.actor_player.hex==[-1,14],"assessed return to unchanged original start")
	# Visit the separate one-cell village/city-state through assessed source routes.
	var village:Dictionary=data.additional_settlements[0];var citadel:Dictionary=data.additional_settlements[1]
	for target in village.road_hexes:
		if a.state_copy().actors.actor_player.hex==target:continue
		if a.state_copy().actors.actor_player.stamina.current<1:
			if not finish(a,a.sample_goal("rest")):quit(1);return
		if not finish(a,a.movement_goal(target)):quit(1);return
	check(a.state_copy().actors.actor_player.hex==village.center_hex,"one-cell village reached without invented gate")
	for target in citadel.road_hexes.slice(4,citadel.road_hexes.size()-1):
		if a.state_copy().actors.actor_player.stamina.current<1:
			if not finish(a,a.sample_goal("rest")):quit(1);return
		if not finish(a,a.movement_goal(target)):quit(1);return
	check(a.state_copy().actors.actor_player.hex==citadel.gate_outside_hex,"independent citystate actual gate approach")
	check(not a.movement_preview(citadel.gate_inside_hex).ok,"second closed gate blocks its own boundary")
	if a.state_copy().actors.actor_player.stamina.current<2:
		if not finish(a,a.sample_goal("rest")):quit(1);return
	if not finish(a,a.sample_goal("open_gate")):quit(1);return
	check(Content.gate_open(a.state_copy(),data.gate_id) and Content.gate_open(a.state_copy(),citadel.gate_id),"opening secondary gate preserves primary gate")
	if not finish(a,a.movement_goal(citadel.center_hex)):quit(1);return
	check(a.save_file("user://settlement_two_gates.json").ok,"independent gate map saved")
	var two_gates:=C.bytes(a.state_copy());var pair_reload:=Adapter.new()
	check(pair_reload.load_file("user://settlement_two_gates.json").ok and C.bytes(pair_reload.state_copy())==two_gates,"two gates restore exact identities and state")
	# Isolated rule fixtures prove attack/move patch consumers use the same wall predicate.
	var fixture:Dictionary=Adapter.new(82,true).state_copy()
	fixture.actors.actor_player.hex=data.gate_outside_hex.duplicate();fixture.actors.actor_raider.hex=data.gate_inside_hex.duplicate();fixture.actors.actor_player.equipment.weapon="item_coast_bow"
	var refs:Array=[];var ref_ids:Array=[]
	for path in ["/actors/actor_player","/actors/actor_raider","/items/item_coast_bow","/items/item_coast_arrows"]:
		var id_:String="ref_"+str(refs.size());refs.append({"id":id_,"path":path,"expected":C.pointer(fixture,path).value});ref_ids.append(id_)
	var assessment:={"resolver_id":"coast_basic_attack_v1","bindings":{"actor_id":"actor_player","target_actor_id":"actor_raider","weapon_item_id":"item_coast_bow"},"components":[],"fact_refs":refs}
	for component in ["accuracy","impact"]:assessment.components.append({"id":component,"parameters":{"A":3,"D":1,"P":0},"disposition":"certain","fact_ref_ids":ref_ids})
	check(Attack.new("basic_attack").freeze(fixture,assessment).get("code")=="ATTACK_WALL","actual attack resolver rejects closed gate binary LOS")
	var blocked_copy:=fixture.duplicate(true)
	check(not World.apply(blocked_copy,{"type":"actor_move","actor_id":"actor_player","scene_id":"scene_coast","hex":data.gate_inside_hex}).ok,"committed patch cannot jump through closed gate")
	check(World.apply(fixture,{"type":"settlement_gate_set","gate_id":data.gate_id,"expected_revision":0,"gate_open":true}).ok,"typed gate fixture patch")
	check(Attack.new("basic_attack").freeze(fixture,assessment).ok,"actual attack resolver sees open gate")
	check(World.apply(fixture,{"type":"actor_move","actor_id":"actor_player","scene_id":"scene_coast","hex":data.gate_inside_hex}).ok,"committed adjacent patch sees open gate")
	var invalid:=fixture.duplicate(true);invalid.settlement_state.content_sha256="wrong"
	check(not World.validate(invalid).ok,"incompatible content save rejected without mixing source")
	var source_end:=SourceProof.snapshot()
	check(C.bytes(source_start)==C.bytes(source_end),"source unchanged through authority suite")
	var report:={"source_start":source_start,"source_end":source_end,"checks":checks,"failures":failures,"passed":failures.is_empty(),"live_api":false,"source_bundle":data.bundle_id,"content_sha256":Content.SHA,"final_state":a.state_copy().settlement_state}
	var f:=FileAccess.open("res://artifacts/runtime_ai_capacity_20261004/regressions/settlement_report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("SETTLEMENT_RULES ",checks," checks; failures=",failures);quit(0 if failures.is_empty() else 1)

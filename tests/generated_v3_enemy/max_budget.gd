extends SceneTree
## Large source-backed fixture, actual committed knowledge/history, offline only.
const A=preload("res://view/generated_v3_enemy/adapter.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const E=preload("res://view/generated_v3_enemy/assessments.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const B=preload("res://view/generated_v3_enemy/response_budget.gd")
const Scope=preload("res://view/generated_v3_enemy/runtime_engine.gd")
const Model=preload("res://core/ai_gm_rebuilt/model_view.gd")
var checks=0
var failures:Array=[]
var rows:Array=[]
var enemy_requests:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->bool:
	checks+=1
	if not ok:failures.append(label_);printerr("BUDGET_FAIL ",label_)
	return ok
func complete(a:RefCounted,enemy:bool=false)->bool:
	var exact:Dictionary=a.request();var size_:int=C.bytes(exact).to_utf8_buffer().size()
	if not check(size_<=65536,"actual "+("enemy" if enemy else "player")+" request fits"):return false
	if enemy:
		enemy_requests.append({"turn":a.state_copy().turn,"bytes":size_,"memory_record_bytes":exact.memory_context.used_record_bytes,"learned_facts":exact.context.facts.learned_facts.size(),"preflight_upper_bound":a.source.enemy_capacity_metrics.get("upper_bound_bytes",0)})
		var bound:Dictionary=B.check(a.state_copy(),a.source.enemy_request_contract)
		if not check(bound.ok and size_<=bound.upper_bound_bytes,"actual next enemy request bounded before RNG"):return false
	var made:Dictionary=E.build(exact)
	if not check(made.ok,"explicit mock interpretation"):return false
	var reply:Dictionary=made.assessment
	reply.provenance={"provider":"max-budget-offline-mock","live":false,"kind":"model_reply"}
	if enemy:
		# Deliberately low-skill test opponent, still two real program dice.
		for component in reply.components:component.parameters={"A":0,"D":4,"P":-2}
	if not check(a.import_reply(reply).ok,"mock assessment accepted"):return false
	for step in ["roll_once","stage","commit"]:
		var result:Dictionary=a.call(step)
		if not check(result.ok,step+" "+str(result)):return false
	return true
func execute(a:RefCounted,kind:String,focus:Dictionary={})->bool:
	if not check(a.begin_intent(a.sample_goal(kind,focus),focus).ok,"begin "+kind):return false
	if not complete(a):return false
	if a.enemy_response_available():
		if not check(a.begin_enemy_response().ok,"separate actual enemy request after player commit"):return false
		if not complete(a,true):return false
	return check(a.state_copy().actors.actor_player.health.current>0,"test traveler remains available")
func walk(a:RefCounted,target:Array)->bool:
	var start:String="%d,%d"%a.state_copy().actors.actor_player.hex;var end:String="%d,%d"%target
	var queue:Array=[start];var parents:Dictionary={start:""};var i=0
	while i<queue.size() and not parents.has(end):
		var at:String=queue[i];i+=1
		for next in a.source.navigation.allowed.get(at,[]):
			if not parents.has(next):parents[next]=at;queue.append(next)
	if not parents.has(end):return false
	var route:Array=[];var at:String=end
	while at!=start:route.push_front(at);at=parents[at]
	for key in route:
		var parts:PackedStringArray=key.split(",");var hex:Array=[int(parts[0]),int(parts[1])]
		var tried=0
		while not a.movement_preview(hex).ok and tried<5:
			tried+=1
			if not execute(a,"rest"):return false
		if not execute(a,"move",a.tile_reference(hex)):return false
	return true
func run()->void:
	var raw:Dictionary=G.generate(726381,12,"coastal_range")
	var a=A.new();a.feature_options={"vegetation":true}
	if not check(a.start_source(raw.source).ok,"radius12 full vegetation admitted"):finish();return
	# Normal engine entropy; only the explicit offline assessment scores are fixtures.
	if not check(walk(a,a.state_copy().actors[a.source.npc_id].hex),"legitimate assessed approach to NPC"):finish();return
	for i in range(8):
		if a.state_copy().actors.actor_player.stamina.current<1 and not execute(a,"rest"):finish();return
		if not execute(a,"talk",a.npc_reference()):finish();return
	for i in range(8):
		if not execute(a,"observe",a.tile_reference(a.state_copy().actors.actor_player.hex)):finish();return
	if not check(not a.state_copy().npc_state.learned_facts.actor_player.is_empty(),"real learned fact retained"):finish();return
	var state:Dictionary=a.state_copy()
	var focuses:Array=[{},a.tile_reference(state.actors.actor_player.hex),a.enemy_reference(),a.npc_reference(),a.item_reference(),{"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":state.actors.actor_player.hex,"scene_id":state.actors.actor_player.scene_id}]
	for id in state.generated_world.static_entity_catalog.entries:focuses.append(a.static_reference(id))
	var far="";var best=-1
	for id in state.generated_world.vegetation_entity_catalog.entries:
		var h:Array=state.generated_world.vegetation_entity_catalog.entries[id].hex
		var q:int=h[0]-state.actors.actor_player.hex[0];var r:int=h[1]-state.actors.actor_player.hex[1]
		var distance:int=maxi(absi(q),maxi(absi(r),absi(q+r)))
		if distance>best:best=distance;far=id
	if not far.is_empty():focuses.append(a.vegetation_reference(far))
	for focus in focuses:
		var before:String=C.bytes(a.state_copy());var rng:String=C.bytes(a.engine.save_data().rng)
		var result:Dictionary=a.begin_intent("\\\"".repeat(2048),focus)
		var row:Dictionary={"kind":focus.get("kind","none"),"id":focus.get("id",""),"accepted":result.ok}
		if result.ok:
			var exact:Dictionary=a.request();var bytes_:int=C.bytes(exact).to_utf8_buffer().size();row["bytes"]=bytes_;row["memory_record_bytes"]=exact.memory_context.used_record_bytes
			check(bytes_<=65536 and exact.context.goal.to_utf8_buffer().size()==4096,"max escaped goal retained within64KiB")
			check(not exact.context.facts.learned_facts.is_empty(),"learned facts retained in every focus")
			check(exact.context.facts.hexes.size()<=39,"declared radius3+exact dependencies bound")
			var scope=Scope.new(a.engine,func():return true,98304)
			check(C.bytes(scope.model_request(a.active_action))==C.bytes(exact) and scope.last_metrics.budget_bytes==65536,"configured96KiB cannot enlarge or reproject exact request")
			check(a.cancel().ok,"budget probe cancels")
		else:
			row["code"]=result.get("code","");check(result.get("code")=="V3_REQUEST_BUDGET","oversize explicitly rejected, never truncated")
		check(a.phase()=="idle" and C.bytes(a.state_copy())==before and C.bytes(a.engine.save_data().rng)==rng,"budget probes do not advance state or entropy")
		rows.append(row)
	var detached:Dictionary=a.state_copy();detached.actors.actor_player.hex=a.source.enemy_placement_result.attack_anchor_hex.duplicate();detached.actors.actor_player.health.current=12;detached.actors[a.source.enemy_id].stamina.current=6;detached.combat_turn.phase="enemy"
	var base_bound:Dictionary=B.check(detached,a.source.enemy_request_contract)
	check(base_bound.ok,"worst fixture can expose feasible enemy context")
	var inflated:Dictionary=a.source.enemy_request_contract.duplicate(true);inflated["synthetic_capacity_fixture"]="x".repeat(65536)
	check(not B.check(detached,inflated).ok,"synthetic unsendable enemy branch rejected before RNG")
	var restored=A.new();check(restored.load_data(JSON.parse_string(C.bytes(a.save_data()))).ok,"large learned/history save replays")
	rows.append({"kind":"summary","turn":a.state_copy().turn,"learned_facts":a.state_copy().npc_state.learned_facts.actor_player.size(),"far_plant_distance":best,"enemy_records":enemy_requests.size(),"detached_enemy_upper_bound":base_bound.get("upper_bound_bytes",0)})
	finish()
func finish()->void:
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"requests":rows,"post_commit_enemy_requests":enemy_requests,"source":{"seed":726381,"radius":12,"recipe":"coastal_range","vegetation":true},"max_goal_bytes":4096,"configured_capacity":98304,"effective_capacity":65536,"mock_only":true,"network_calls":0}
	FileAccess.open("res://artifacts/generated_v3_enemy/max_budget_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENEMY_MAX_BUDGET ",checks," ",failures);quit(0 if failures.is_empty() else 1)

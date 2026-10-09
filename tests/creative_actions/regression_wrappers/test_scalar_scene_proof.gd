extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Fixture = preload("res://view/playable_build/scene_framework_fixture.gd")
const Authored = preload("res://view/playable_build/authored_assessments.gd")
const Scalar = preload("res://view/playable_build/scene_transition_resolver_v2.gd")
var checks:=0
var failures: Array=[]
var reply_sizes: Dictionary={}
func expect(v: bool,label: String) -> void:
	checks+=1
	if not v:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var adapter:=Adapter.new(97,true)
	expect(adapter.start_scene_framework_test(97).ok,"new scalar test session")
	var registry: Array=adapter.engine.save_data().resolver_ids
	expect(Scalar.ID_V2 in registry and not "coast_scene_transition_v1" in registry,"new runtime exposes only scalar scene family")
	expect("/scenes/<destination_scene_id>/id" in Scalar.new().action_schema().required_fact_paths,"advertised scalar scene evidence")
	for kind in ["enter_scene","return_scene"]:
		var goal: String=adapter.sample_goal(kind)
		expect(adapter.begin_intent(goal).ok,"begin "+kind)
		var request: Dictionary=adapter.request()
		var built:=Authored.build(request)
		expect(built.ok and built.assessment.resolver_id==Scalar.ID_V2,"authored prefers v2 "+kind)
		var reply: Dictionary=built.assessment
		var id: String=reply.bindings.entrance_id
		var dest: String=request.context.facts.scene_transitions[id].destination_scene_id
		var scalar_path: String="/scenes/"+dest+"/id"
		var matches: Array=reply.fact_refs.filter(func(ref):return ref.path==scalar_path)
		expect(matches.size()==1 and matches[0].expected==dest,"exact scalar identity ref "+kind)
		var size: int=C.bytes(reply).to_utf8_buffer().size();reply_sizes[kind]=size
		expect(size<4096,"complete authored JSON under4KiB "+kind)
		if kind=="return_scene":
			expect(request.context.facts.scenes.scene_coast.hex_ids.size()==1801,"full1801 destination context retained")
			var full_echo: Dictionary=reply.duplicate(true)
			for ref in full_echo.fact_refs:
				if ref.path==scalar_path:ref.path="/scenes/"+dest;ref.expected=request.context.facts.scenes[dest]
			expect(C.bytes(full_echo).to_utf8_buffer().size()>20000,"regression reproduces old catalog echo size")
			expect(not Scalar.new().freeze(adapter.action_copy().snapshot,full_echo).ok,"full scene object cannot replace required scalar proof")
		var missing: Dictionary=reply.duplicate(true)
		missing.fact_refs=missing.fact_refs.filter(func(ref):return ref.path!=scalar_path)
		expect(not Scalar.new().freeze(adapter.action_copy().snapshot,missing).ok,"missing scalar proof rejects "+kind)
		var uncited: Dictionary=reply.duplicate(true)
		uncited.components[0].fact_ref_ids.erase(matches[0].id)
		expect(not Scalar.new().freeze(adapter.action_copy().snapshot,uncited).ok,"uncited scalar proof rejects "+kind)
		var false_id: Dictionary=reply.duplicate(true)
		for ref in false_id.fact_refs:
			if ref.path==scalar_path:ref.expected="wrong_scene"
		expect(not Scalar.new().freeze(adapter.action_copy().snapshot,false_id).ok,"wrong scene scalar rejects "+kind)
		expect(adapter.prepare_fixture().ok,"strict fixture accepts scalar "+kind)
		var phase_path:="user://scalar_scene_pending.json"
		for phase in ["ready_roll","rolled","staged"]:
			expect(adapter.save_file(phase_path).ok,"scalar pending save "+phase)
			var resumed:=Adapter.new()
			expect(resumed.load_file(phase_path).ok and C.bytes(resumed.engine.save_data())==C.bytes(adapter.engine.save_data()),"scalar pending exact "+phase)
			adapter=resumed
			if phase=="ready_roll":adapter.roll_once()
			elif phase=="rolled":adapter.stage()
		expect(adapter.commit().ok,"scalar transition commits "+kind)
	expect(adapter.state_copy().actors.actor_player.scene_id=="scene_coast","scalar return destination exact")
	# Historical v1 pending return uses its old full-scene evidence and exact registry.
	var old:=Adapter.new(99,true)
	old.engine=old._make_engine(99,false,true,true,true,true,true,true,true,false)
	var historical: Dictionary=old.engine.save_data();Fixture.install(historical.state)
	historical.state.actors.actor_player.scene_id=Fixture.ROOM;historical.state.actors.actor_player.hex=[0,0]
	expect(old.engine.load_data(historical).ok,"old v1 fixture state accepted")
	var old_goal: String=old.sample_goal("return_scene")
	var began: Dictionary=old.engine.begin_intent(old_goal);old.active_action=began.request.action_id
	expect(old.prepare_fixture().ok,"historical full scene fixture retained")
	expect(old.action_copy().assessment.resolver_id=="coast_scene_transition_v1" and old.action_copy().assessment.fact_refs.any(func(ref):return ref.path=="/scenes/scene_coast"),"old evidence contract unmodified")
	for phase in ["ready_roll","rolled","staged"]:
		var path:="user://legacy_scene_pending.json"
		expect(old.save_file(path).ok,"old v1 pending save "+phase)
		var reload:=Adapter.new()
		expect(reload.load_file(path).ok and C.bytes(reload.engine.save_data())==C.bytes(old.engine.save_data()),"old v1 pending byte exact "+phase)
		old=reload
		if phase=="ready_roll":old.roll_once()
		elif phase=="rolled":old.stage()
	expect(old.commit().ok and old.state_copy().actors.actor_player.scene_id=="scene_coast","old v1 pending return commits")
	expect(old.begin_intent(old.sample_goal("enter_scene")).ok and Scalar.ID_V2 in old.engine.save_data().resolver_ids and not "coast_scene_transition_v1" in old.engine.save_data().resolver_ids,"idle subsequent intent upgrades to scalar family without rewriting receipt")
	print("SCALAR SCENE PROOF ",checks-failures.size(),"/",checks," sizes=",JSON.stringify(reply_sizes)," failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

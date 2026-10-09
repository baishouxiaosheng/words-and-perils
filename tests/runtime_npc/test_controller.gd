extends "res://tests/generated_v3_npc/test_adapter.gd"
const Runtime=preload("res://view/runtime_ai/controller.gd")
const Session=preload("res://view/runtime_ai/village_session.gd")
const Full=preload("res://view/runtime_ai/bounded_profile_engine.gd")
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
const OUT="res://artifacts/runtime_npc/"
const KEY="synthetic-runtime-npc-test-only"
var ticks=0
var events:Array=[]
func envelope(reply:Dictionary)->String:
	# Encode test controls as valid external JSON escapes, not Godot's raw-C0
	# serializer behavior, so the transport boundary is genuinely exercised.
	var inner=C.bytes(reply)
	for code in range(32):
		if code not in [9,10,13]:inner=inner.replace(String.chr(code),"\\u%04x"%code) if code>0 else inner
	return C.bytes({"choices":[{"finish_reason":"stop","message":{"content":inner}}]})
func outgoing(mock:Node)->Dictionary:return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func answer(request:Dictionary,kind:String="talk")->Dictionary:
	var prototype=request.duplicate(true);prototype.context.goal=Examples.goal(kind)
	var made:Dictionary=Examples.build(prototype)
	if not made.ok:return {}
	made.assessment.provenance={"provider":"mock_test_transport","live":false,"kind":"model_reply"}
	made.assessment.interpretation="明确标注的离线模拟评估；自由文字仍由结构化回复解释，不是关键词自动执行。"
	return made.assessment
func prose(request:Dictionary,text_:String="MOCK_DISPLAY_ONLY：村民已说明入口；实际资料以旅途笔记和回执为准。")->Dictionary:
	return {"schema_version":"ai_gm_narration/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":text_}
func configured(a:RefCounted)->Array:
	var session=Session.new(a);var runtime=Runtime.new();root.add_child(runtime);var mock=Mock.new();runtime.set_transport(mock)
	runtime.bind_adapter(session);runtime.clock=func():return ticks
	check(runtime.configure({"endpoint":"https://example.invalid/v1/chat/completions","model":"unchanged-synthetic-test-model","timeout_seconds":1.0,"public_request_budget_bytes":98304},KEY).ok,"synthetic-only configuration, no connection")
	runtime.connection_enabled=true
	return [runtime,mock,session]
func trace(label:String,runtime:Node,a:RefCounted,mock:Node):
	events.append({"label":label,"epoch":runtime._epoch,"operation_sequence":runtime._operation_sequence,"operation":runtime._operation.duplicate(true),"adapter_instance":a.get_instance_id(),"engine_instance":a.engine.get_instance_id(),"phase":a.phase(),"world_id":a.state_copy().world_id,"turn":a.state_copy().turn,"authority_hash":C.digest(a.save_data()),"rng_hash":C.digest(a.engine.save_data().rng),"sent":mock.sent.size(),"live":false})
func retain(label:String,mock:Node,request:Dictionary):
	check(not mock.sent.back().body.contains(KEY),label+" outgoing body has no credential marker")
	FileAccess.open(OUT+label+"_http.json",FileAccess.WRITE).store_string(mock.sent.back().body)
	FileAccess.open(OUT+label+"_engine.json",FileAccess.WRITE).store_string(C.bytes(request))
func make_ready(a:RefCounted)->bool:
	return a.begin_intent("请告诉我村口的道路。",a.npc_reference()).ok and a.engine.prepare_assessment(answer(a.request())).ok
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
	var a=Adapter.new();a.feature_options={"vegetation":true}
	if not check(a.start_source(generated.source).ok and walk_to_npc(a),"real forest NPC source and legitimate approach"):finish_runtime();return
	var trio=configured(a);var runtime:Node=trio[0];var mock:Node=trio[1];var session:RefCounted=trio[2]
	check(mock.sent.is_empty(),"configuring never sends")
	var accepted=[0];var narrated=[0]
	runtime.assessment_validated.connect(func(_id):
		accepted[0]+=1
		check(a.roll_once().ok and a.stage().ok and a.commit().ok,"validated reply uses original lock stage commit")
		session.committed();runtime.committed())
	runtime.narration_received.connect(func(id,text_):
		narrated[0]+=1;check(session.record_narration(id,text_).ok,"receipt-bound view narration recorded"))
	runtime.automatic_narration=true
	var goal_="请告诉我从这里进村该走哪条路，我想把你的指引记下来。"
	check(a.begin_intent(goal_,a.npc_reference()).ok and not a.fixture_available(),"natural text waits without preset keyword execution")
	var frozen=C.bytes(a.save_data());var exact:Dictionary=a.request();trace("before_send",runtime,a,mock)
	var started:Dictionary=runtime.request_assessment()
	if not check(started.ok,"first request starts "+str(started)):runtime.free();finish_runtime();return
	var request=outgoing(mock)
	check(started.ok and C.bytes(request)==C.bytes(exact),"complete bounded NPC request transported byte exact")
	check(runtime._scope is Full and runtime.last_metrics.budget_bytes==65536 and runtime.client.public_configuration().public_request_budget_bytes==98304,"profile64KiB enforced without changing connection setting")
	check(not request.has("transport_scope") and request.context.goal==goal_,"no second projection or goal rewrite")
	check(not runtime.request_assessment().ok and mock.sent.size()==1 and C.bytes(a.save_data())==frozen,"double request no send or authority change")
	retain("conversation",mock,exact)
	a.attention(a.item_reference());check(C.bytes(a.request())==C.bytes(exact),"selection change preserves frozen outgoing focus")
	mock.respond(started.request_id,envelope(answer(request)))
	if not check(accepted[0]==1 and a.phase()=="idle" and a.state_copy().npc_state.contacts[a.source.npc_id].conversation_count==1,"one interpreted conversation commits "+str(runtime.last_result)):runtime.free();finish_runtime();return
	check(mock.sent.size()==2 and outgoing(mock).phase=="narration" and not outgoing(mock).context.provisional_until_commit,"optional narration only after commit")
	var committed=C.bytes(a.save_data());var nr=outgoing(mock);var ntoken:int=mock.sent.back().request_id
	retain("committed_narration",mock,a.request());mock.respond(started.request_id,envelope(answer(request)))
	check(C.bytes(a.save_data())==committed and accepted[0]==1,"duplicate assessment cannot repeat a turn")
	mock.respond(ntoken,envelope(prose(nr)))
	check(narrated[0]==1 and session.has_recorded_narration(a.last_action) and C.bytes(a.save_data())==committed,"optional prose outside exact authority")
	var sent:int=mock.sent.size();check(not runtime.request_narration().ok and mock.sent.size()==sent,"recorded receipt prevents repeat narration charge")
	check(not C.bytes(a.request()).contains("MOCK_DISPLAY_ONLY"),"display prose does not become model facts")
	trace("after_talk_and_prose",runtime,a,mock)
	# Save/load facade leaves every V19 core byte and schema unchanged.
	var path="user://runtime_npc_sidecar.json";check(a.save_file(path).ok and session.save_sidecar(path).ok,"core and optional sidecar saved independently")
	var b=Adapter.new();check(b.load_file(path).ok,"unchanged V19 core reload")
	var bsession=Session.new(b);var loaded:Dictionary=bsession.load_sidecar(path)
	check(loaded.status=="loaded" and bsession.narration_entries().size()==1 and C.bytes(b.save_data())==committed,"matching receipt sidecar restores once")
	var sidecar=FileAccess.get_file_as_string(path+".narration.json")
	FileAccess.open(path+".narration.json",FileAccess.WRITE).store_string("bad JSON")
	loaded=bsession.load_sidecar(path);check(loaded.status.begins_with("ignored") and bsession.narration_entries().is_empty() and C.bytes(b.save_data())==committed,"corrupt optional prose warns without failing core")
	FileAccess.open(path+".narration.json",FileAccess.WRITE).store_string(sidecar)
	bsession.load_sidecar(path)
	var bad=b.save_data();bad.schema_version="wrong";check(not b.load_data(bad).ok and bsession.has_recorded_narration(b.last_action),"failed core load preserves existing view records")
	var fresh:RefCounted=b.restarted();var fresh_session=Session.new(fresh)
	check(fresh_session.narration_entries().is_empty(),"same-source restart never reuses old logical action records")
	# Current learned facts and distant plant support travel unchanged.
	var far="";var far_distance=-1
	for id in a.source.identity.vegetation_entity_catalog.entries:
		var h:Array=a.source.identity.vegetation_entity_catalog.entries[id].hex;var at:Array=a.state_copy().actors.actor_player.hex
		var q:int=h[0]-at[0];var r:int=h[1]-at[1];var distance=maxi(absi(q),maxi(absi(r),absi(q+r)))
		if distance>far_distance:far=id;far_distance=distance
	check(a.begin_intent("看看那株植物，暂时不要采集。",a.vegetation_reference(far)).ok,"known plant intent frozen")
	exact=a.request();started=runtime.request_assessment();request=outgoing(mock)
	check(C.bytes(request)==C.bytes(exact) and not request.context.facts.learned_facts.is_empty(),"selected plant and learned knowledge retained exactly")
	retain("learned_plant",mock,exact);runtime.cancel();a.cancel()
	# Request failure, timeout and explicit retry never advance or reroll.
	check(a.begin_intent("请再次说明去村口的道路。",a.npc_reference()).ok,"retry test free text")
	frozen=C.bytes(a.save_data());started=runtime.request_assessment();request=outgoing(mock)
	trace("before_timeout",runtime,a,mock);runtime.client._on_timeout()
	check(not runtime.busy() and runtime.last_result.code=="TIMEOUT" and C.bytes(a.save_data())==frozen,"timeout keeps pending authority exact")
	mock.respond(started.request_id,envelope(answer(request)));check(accepted[0]==1 and C.bytes(a.save_data())==frozen,"late timeout result rejected")
	check(not runtime.request_assessment().ok,"manual retry respects cooldown");ticks+=40000
	started=runtime.request_assessment();retain("timeout_retry",mock,a.request());trace("retry_sent",runtime,a,mock)
	runtime.cancel();a.cancel();runtime.free()
	# No completion may clear a replacement operation, even with same world/ID.
	var old=Adapter.new(generated.source);check(walk_to_npc(old) and old.begin_intent("询问村口。",old.npc_reference()).ok,"reentry source")
	trio=configured(old);runtime=trio[0];mock=trio[1];session=trio[2]
	started=runtime.request_assessment();request=outgoing(mock)
	var replacement=Adapter.new();check(replacement.load_data(old.save_data()).ok,"same-ID replacement pending source")
	var next_session=Session.new(replacement);var swapped=[false];var new_token=[-1]
	runtime.client.busy_changed.connect(func(value):
		if not value and not swapped[0]:
			swapped[0]=true;runtime.bind_adapter(next_session)
			var next:Dictionary=runtime.request_assessment();new_token[0]=next.get("request_id",-1))
	var frozen_next=C.bytes(replacement.save_data());mock.respond(started.request_id,"old failure",500)
	check(swapped[0] and new_token[0]>started.request_id and runtime.busy() and runtime._operation.client_request_id==new_token[0],"old busy-false failure cannot clear new request")
	check(runtime.last_result.is_empty() and C.bytes(replacement.save_data())==frozen_next,"old failure cannot overwrite new status or authority")
	trace("replacement_owns_new_request",runtime,replacement,mock);retain("replacement_request",mock,replacement.request())
	mock.respond(started.request_id,envelope(answer(request)));check(C.bytes(replacement.save_data())==frozen_next,"late old adventure response cannot bind same logical action")
	runtime.cancel();runtime.free()
	# Final action-only notification must recheck ownership after changed.
	for kind in ["assessment","narration"]:
		old=Adapter.new(generated.source);check(walk_to_npc(old),"final-signal source approach")
		if kind=="narration":check(execute(old,"talk",old.npc_reference()),"committed narration race source")
		else:check(old.begin_intent("询问村口。",old.npc_reference()).ok,"assessment race intent")
		trio=configured(old);runtime=trio[0];mock=trio[1];session=trio[2]
		var delivered=[0];runtime.assessment_validated.connect(func(_id):delivered[0]+=1);runtime.narration_received.connect(func(_id,_text):delivered[0]+=1)
		started=runtime.request_assessment() if kind=="assessment" else runtime.request_narration();request=outgoing(mock)
		var moved=[false];var replacement_box=[null]
		runtime.changed.connect(func():
			if not moved[0] and runtime._operation.is_empty() and not runtime.client.busy() and old.phase()==("ready_roll" if kind=="assessment" else "idle"):
				moved[0]=true;var restored=Adapter.new();check(restored.load_data(old.save_data()).ok,"same-ID final-signal replacement admitted")
				replacement_box[0]=Session.new(restored);runtime.bind_adapter(replacement_box[0]))
		mock.respond(started.request_id,envelope(answer(request) if kind=="assessment" else prose(request)))
		check(moved[0] and delivered[0]==0,"reentrant "+kind+" changed prevents stale final signal")
		if replacement_box[0]!=null:check(replacement_box[0].narration_entries().is_empty(),"replacement receives no stale narration")
		runtime.free()
	FileAccess.open(OUT+"events.json",FileAccess.WRITE).store_string(JSON.stringify(events,"\t"))
	finish_runtime()
func finish_runtime():
	FileAccess.open(OUT+"controller_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"transport_live":false,"network_calls":0,"scope":"actual V19 source/engine with injected mock HTTP only; final Main and full boundary cases are separate"},"\t"))
	print("RUNTIME_NPC_CONTROLLER ",checks," ",failures);quit(0 if failures.is_empty() else 1)

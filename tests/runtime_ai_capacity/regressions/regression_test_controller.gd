extends SceneTree
const Runtime = preload("res://view/runtime_ai/controller.gd")
const Scoped = preload("res://view/runtime_ai/scoped_engine.gd")
const Coast = preload("res://view/playable_build/adapter.gd")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array[String] = []
var ticks := 0
var accepted := 0
var narrations := 0
var completed: Array = []
const KEY := "synthetic-runtime-test-marker-never-a-live-key"
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL: " + description)
func _initialize() -> void: run.call_deferred()
func envelope(reply: Dictionary) -> String: return JSON.stringify({"choices":[{"finish_reason":"stop", "message":{"content":JSON.stringify(reply)}}]})
func outgoing(mock: Node) -> Dictionary: return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func observation(request: Dictionary) -> Dictionary:
	return {"schema_version":"ai_gm_assessment/v1", "action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,
		"narration":"准备观察旧灯周边，结果尚未产生。","interpretation":"测试transport返回针对实际自由意图的结构化观察评估。","resolver_id":"coast_observe","bindings":{"actor_id":"actor_player"},
		"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["player","coast"]}],
		"fact_refs":[{"id":"player","path":"/actors/actor_player","expected":request.context.facts.actors.actor_player},{"id":"coast","path":"/story_anchors/anchor_coast","expected":request.context.facts.story_anchors.anchor_coast}],
		"provenance":{"provider":"mock_test_transport","live":false,"kind":"model_reply"}}
func narration(request: Dictionary) -> Dictionary:
	return {"schema_version":"ai_gm_narration/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"程序已完成这一回合；实际结果以已提交数值与线索栏为准。"}
func create_runtime() -> Array:
	var adapter := Coast.new()
	var runtime := Runtime.new(); root.add_child(runtime)
	var mock := Mock.new(); runtime.set_transport(mock)
	runtime.clock = func(): return ticks
	runtime.bind_adapter(adapter)
	runtime.request_finished.connect(func(result: Dictionary): completed.append(result))
	return [adapter, runtime, mock]
func configure(runtime: Node) -> void:
	check(runtime.configure({"endpoint":"https://example.invalid/v1/chat/completions","model":"provided-test-id","timeout_seconds":1.0}, KEY).ok,"local-only configuration accepted")
	runtime.connection_enabled = true
func run() -> void:
	var trio := create_runtime(); var adapter: RefCounted = trio[0]; var runtime: Node = trio[1]; var mock: Node = trio[2]
	check(adapter.engine.ready().ok,"real full-map engine ready")
	var outer_cells:Dictionary={};var interior_cells:Dictionary={}
	var mini_public:Dictionary={"hexes":{"0,0":{"id":"outer","scene_id":"coast"}},"scene_hexes":{"room":{"0,0":{"id":"inside","scene_id":"room"},"1,0":{"id":"inside_neighbor","scene_id":"room"}}}}
	Scoped._include_scene_neighborhood(outer_cells,interior_cells,mini_public,"room",[0,0])
	check(outer_cells.is_empty() and interior_cells.room["0,0"].id=="inside","interior projection never substitutes outer coordinate cell")
	check(interior_cells.room.has("1,0"),"selected interior cell keeps its actual-scene neighbors")
	Scoped._include_scene_neighborhood(outer_cells,interior_cells,mini_public,"coast",[0,0])
	check(outer_cells["0,0"].id=="outer","legacy outer scene projection preserved separately")

	check(not runtime.automatic_assessment_enabled() and not runtime.connection_enabled,"default connection and automatic requests off")
	check(adapter.begin_intent("观察南潮海岸与旧灯，记录眼前的线索。").ok,"free intent freezes on actual adapter")
	check(not adapter.fixture_available(),"free intent is never mapped to signed fixture")
	var frozen: Dictionary = adapter.engine.save_data()
	check(not runtime.request_assessment().ok and mock.sent.is_empty(),"unconfigured request never transmits")
	configure(runtime)
	check(mock.sent.is_empty(),"configure has no network/mock send")
	var started: Dictionary = runtime.request_assessment(); var request := outgoing(mock)
	var scope_metrics: Dictionary = runtime.last_metrics.duplicate(true)
	check(started.ok and mock.sent.size()==1,"optional controller sends exactly once")
	check(request.context.goal == "观察南潮海岸与旧灯，记录眼前的线索。","exact free intent preserved")
	check(request.context_hash == adapter.engine.model_request(adapter.active_action).context_hash,"authority full-context hash preserved")
	check(request.context.facts.hexes.size() < 1801 and request.transport_scope.total_hexes==1801,"explicit bounded scope does not send whole map")
	check(C.bytes(request.context.facts.actors)==C.bytes(adapter.engine.model_request(adapter.active_action).context.facts.actors),"all complete public actor refs preserved")
	var budget_probe := Scoped.new(adapter.engine, func(): return true)
	var too_large:Dictionary=request.duplicate(true);too_large.context.goal="x".repeat(70000)
	check(budget_probe._budget(request,too_large,"budget-test").is_empty() and budget_probe.last_error.code=="CONTEXT_BUDGET", "oversize required context fails closed, no truncation")
	check(runtime.last_metrics.sent_public_bytes < 65536 and runtime.last_metrics.sent_public_bytes < runtime.last_metrics.full_public_bytes/2,"request budget measures real full-map reduction")
	for forbidden in ['"rng"','"seed"','"receipts"','"snapshot"','"private_notes"','"secrets"',KEY]: check(not mock.sent.back().body.contains(forbidden),"public request excludes "+forbidden)
	check(not runtime.request_assessment().ok and mock.sent.size()==1,"double click blocked without another request")
	check(C.bytes(adapter.engine.save_data())==C.bytes(frozen),"requests never change state/RNG")
	# Full trusted journey is triggered only after validated assessment.
	runtime.assessment_validated.connect(func(_id: String):
		accepted += 1
		check(adapter.roll_once().ok,"trusted roll")
		check(adapter.stage().ok,"trusted stage")
		check(adapter.commit().ok,"trusted atomic commit")
		runtime.committed())
	runtime.narration_received.connect(func(_id: String, _text: String): narrations += 1)
	runtime.automatic_narration = true
	mock.respond(started.request_id,envelope(observation(request)))
	check(accepted==1 and adapter.state_copy().turn==1,"one validated assessment completes exactly one turn")
	check(mock.sent.size()==2 and outgoing(mock).phase=="narration","optional narration only requested after commit")
	check(not outgoing(mock).context.provisional_until_commit,"narrator receives committed receipt only")
	var committed: Dictionary = adapter.engine.save_data()
	var nr := outgoing(mock); var narration_token: int = mock.sent.back().request_id
	mock.respond(started.request_id,envelope(observation(request)))
	check(accepted==1 and C.bytes(adapter.engine.save_data())==C.bytes(committed),"duplicate/reversed assessment ignored during narration")
	mock.respond(narration_token,envelope(narration(nr)))
	check(narrations==1 and not adapter.narration.is_empty(),"read-only optional narration delivered")
	check(C.bytes(adapter.engine.save_data())==C.bytes(committed),"narration cannot alter save/RNG/receipts")
	var savepath := "user://runtime_ai_controller_test.json"
	check(adapter.save_file(savepath).ok,"committed result saves")
	check(not FileAccess.get_file_as_string(savepath).contains(KEY),"save contains no runtime credential")
	var restored := Coast.new()
	check(restored.load_file(savepath).ok and C.bytes(restored.engine.save_data())==C.bytes(committed),"save restore exact authoritative state")
	DirAccess.remove_absolute(savepath)
	# Narration failures retain committed facts, expose bounded manual cooldown,
	# and never cause automated paid retries or a second judgement.
	for status in [401,429,500,503]:
		ticks += 40000
		started = runtime.request_narration(); check(started.ok,"manual narration request accepted for failure case")
		var sent_count: int = mock.sent.size()
		mock.respond(started.request_id,"untrusted backend diagnostic",status)
		check(not runtime.busy() and not completed.back().ok,"HTTP %d completes honestly"%status)
		check(mock.sent.size()==sent_count and C.bytes(adapter.engine.save_data())==C.bytes(committed),"HTTP failure cannot retry or mutate")
		if status!=401:
			check(runtime.cooldown_remaining()>0.0 and runtime.cooldown_remaining()<=30.0,"transient cooldown bounded")
			check(not runtime.request_narration().ok and mock.sent.size()==sent_count,"cooldown blocks duplicate manual request")
	ticks += 40000; started = runtime.request_narration(); nr=outgoing(mock)
	await create_timer(1.1).timeout
	check(completed.back().code=="TIMEOUT" and not runtime.busy(),"watchdog timeout terminates operation")
	mock.respond(started.request_id,envelope(narration(nr)))
	check(narrations==1 and C.bytes(adapter.engine.save_data())==C.bytes(committed),"late timeout response cannot rewrite result")
	ticks+=40000
	check(adapter.record_narration(adapter.last_action,"不可重复计费的已记录叙事。").ok,"record committed prose for no-network duplicate guard")
	var sent_before_duplicate:int=mock.sent.size()
	var duplicate_narration:Dictionary=runtime.request_narration()
	check(not duplicate_narration.ok and duplicate_narration.code=="ALREADY_RECORDED" and mock.sent.size()==sent_before_duplicate,"already recorded receipt blocks duplicate provider request")
	runtime.free()
	# Isolated failed/cancelled intents with no successful assessment.
	trio=create_runtime(); adapter=trio[0]; runtime=trio[1]; mock=trio[2]; configure(runtime)
	check(adapter.begin_intent("观察旧灯与海岸。").ok,"second independent free intent")
	frozen=adapter.engine.save_data()
	for attack in ["bad_json","unsupported","raw_patch","code","wrong_actor","unknown_resolver","bad_hash","missing_ref","omitted_ref","tool_call","credential_echo"]:
		started=runtime.request_assessment(); request=outgoing(mock)
		var reply:=observation(request); var body: String
		match attack:
			"bad_json": body="not JSON"
			"unsupported": body=envelope({"error":{"code":"UNSUPPORTED_INTENT"}})
			"raw_patch": reply["patches"]=[{"type":"flag_set","flag_id":"coast_observed","value":true}]; body=envelope(reply)
			"code": reply["code"]="OS.execute('evil',[])"; body=envelope(reply)
			"wrong_actor": reply.bindings.actor_id="actor_keeper"; body=envelope(reply)
			"unknown_resolver": reply.resolver_id="invented_unlimited_power"; body=envelope(reply)
			"bad_hash": reply.context_hash="not-the-frozen-hash"; body=envelope(reply)
			"missing_ref": reply.fact_refs=3; body=envelope(reply)
			"omitted_ref":
				var full:Dictionary=adapter.engine.model_request(adapter.active_action)
				for key in full.context.facts.hexes:
					if not request.context.facts.hexes.has(key):
						reply.fact_refs.append({"id":"invented_unseen","path":"/hexes/"+key,"expected":full.context.facts.hexes[key]}); break
				body=envelope(reply)
			"tool_call": body=JSON.stringify({"choices":[{"finish_reason":"stop","message":{"content":JSON.stringify(reply),"tool_calls":[]}}]})
			"credential_echo": body=envelope({"error":{"detail":KEY}})
		mock.respond(started.request_id,body)
		check(not completed.back().ok and adapter.phase()=="awaiting_assessment",attack+" rejected before plan freeze")
		check(C.bytes(adapter.engine.save_data())==C.bytes(frozen),attack+" preserves entire authority")
	started=runtime.request_assessment();request=outgoing(mock);runtime.cancel()
	mock.respond(started.request_id,envelope(observation(request)))
	check(not runtime.busy() and C.bytes(adapter.engine.save_data())==C.bytes(frozen),"cancel followed by late valid reply harmless")
	started=runtime.request_assessment();request=outgoing(mock);runtime.bind_adapter(restored)
	check(runtime.last_result.is_empty(),"binding new scene clears prior same-ID transport status")
	mock.respond(started.request_id,envelope(observation(request)))
	check(C.bytes(adapter.engine.save_data())==C.bytes(frozen) and C.bytes(restored.engine.save_data())==C.bytes(committed),"adapter reset/load invalidates old request")
	runtime.bind_adapter(adapter);started=runtime.request_assessment();request=outgoing(mock)
	# Same adapter but a replacement engine must also invalidate facade mutation.
	adapter.engine=Coast.new().engine
	mock.respond(started.request_id,envelope(observation(request)))
	check(adapter.state_copy().turn==0 and not completed.back().ok,"stale source engine cannot prepare/commit")
	# Destroyed scene/client disconnects externally owned transport callbacks.
	var external:=Mock.new();root.add_child(external);runtime.set_transport(external)
	check(adapter.begin_intent("观察海岸。").ok,"destruction test new frozen intent")
	started=runtime.request_assessment();request=outgoing(external)
	var before_destroy:=C.bytes(adapter.engine.save_data());runtime.free()
	external.respond(started.request_id,envelope(observation(request)))
	check(C.bytes(adapter.engine.save_data())==before_destroy,"destroyed scene ignores retained external mock response")
	external.free()
	var result:Dictionary={"scope":"actual-world runtime controller, injected mock only, no network", "checks":checks,"failures":failures,"live_provider_verified":false,"completed_main_scene_test":"separate test_main_flow.gd","assessment_context_metrics":scope_metrics,"rule_mode":"default production adapter, no injected seed or test rule"}
	var f:=FileAccess.open("res://artifacts/runtime_ai_capacity_20261004/regressions/controller_results.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("RUNTIME AI CONTROLLER ",checks-failures.size(),"/",checks,"; MOCK ONLY; NO NETWORK")
	quit(0 if failures.is_empty() else 1)

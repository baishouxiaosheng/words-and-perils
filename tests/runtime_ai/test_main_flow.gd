extends SceneTree
## This is the real default main scene. Only the injected provider is synthetic.
const Main = preload("res://main.tscn")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL: "+label)
func _initialize() -> void: run.call_deferred()
func envelope(reply: Dictionary) -> String: return JSON.stringify({"choices":[{"finish_reason":"stop","message":{"content":JSON.stringify(reply)}}]})
func outgoing(mock: Node) -> Dictionary: return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func assessment(request: Dictionary) -> Dictionary:
	return {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,
		"narration":"你打算观察旧灯。","interpretation":"根据完整自由意图评估海岸观察。","resolver_id":"coast_observe","bindings":{"actor_id":"actor_player"},
		"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["player","coast"]}],
		"fact_refs":[{"id":"player","path":"/actors/actor_player","expected":request.context.facts.actors.actor_player},{"id":"coast","path":"/story_anchors/anchor_coast","expected":request.context.facts.story_anchors.anchor_coast}],
		"provenance":{"provider":"mock_test_transport","live":false,"kind":"model_reply"}}
func run() -> void:
	var scene:=Main.instantiate();root.add_child(scene)
	await process_frame; await process_frame
	check(scene.coast_mode,"default main starts actual coast")
	check(is_instance_valid(scene.runtime_ai),"runtime exists in actual default main")
	var runtime: Node=scene.runtime_ai
	var panel: Control=scene.runtime_connection_panel
	check(is_instance_valid(panel) and not runtime.automatic_assessment_enabled(),"actual advanced panel starts offline")
	var mock:=Mock.new();runtime.set_transport(mock)
	scene.set_player_intent("我停下来观察南潮海岸和旧灯，记录能看到的线索。")
	scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment" and mock.sent.is_empty(),"offline free input waits honestly without fabricated result")
	scene.cancel_pending()
	check(scene.playtest.phase()=="idle","actual main can cancel offline wait")
	panel.endpoint_input.text="https://example.invalid/v1/chat/completions"
	panel.model_input.text="provided-test-model"
	panel.key_input.text="synthetic-main-flow-marker-not-an-api-key"
	panel.consent_input.button_pressed=true
	panel._apply()
	panel.automatic_assessment_input.button_pressed=true
	panel.automatic_narration_input.button_pressed=true
	check(runtime.automatic_assessment_enabled() and mock.sent.is_empty(),"choosing provider config enables explicit end-turn, no configuration call")
	panel.model_input.text="unapplied-provider-model"
	panel.model_input.text_changed.emit(panel.model_input.text)
	check(not runtime.automatic_assessment_enabled(),"unapplied dirty configuration disables automatic send")
	panel.model_input.text="provided-test-model";panel.key_input.text="synthetic-main-flow-marker-not-an-api-key";panel._apply()
	check(panel.key_input.text.is_empty() and panel.key_input.secret,"local secret field cleared after memory-only apply")
	scene.on_hex_selected(Vector2i(-2,15))
	var text:="我留在原地观察南潮海岸和旧灯，记下眼前的线索，不向关注格移动。"
	scene.set_player_intent(text)
	var before:Dictionary=scene.playtest.engine.save_data()
	scene.end_turn()
	check(mock.sent.size()==1 and scene.playtest.phase()=="awaiting_assessment","actual primary action requests assessment once")
	var req:=outgoing(mock);var token:int=mock.sent.back().request_id
	check(req.context.goal==text and not req.context.attention_focus.is_empty(),"free text and attention transported independently")
	check(req.context.text_priority=="explicit_player_text","explicit intent outranks selected object")
	check(req.contract.action_schemas.size()==req.contract.resolver_ids.size(),"every installed action family publishes actual typed schema")
	scene.end_turn();check(mock.sent.size()==1,"main double end-turn cannot issue duplicate request")
	mock.respond(token,envelope(assessment(req)))
	check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==before.state.turn+1,"real main performs assessment→roll→stage→commit exactly once")
	check(scene.playtest.state_copy().actors.actor_player.hex==before.state.actors.actor_player.hex,"attention target did not replace explicit observation intent")
	check(not scene.readable_turn_feedback().is_empty(),"main provides readable authoritative fallback before prose")
	check(mock.sent.size()==2 and outgoing(mock).phase=="narration","main triggers optional narration only after commit")
	var committed:Dictionary=scene.playtest.engine.save_data()
	var nr:=outgoing(mock);var ntoken:int=mock.sent.back().request_id
	mock.respond(token,envelope(assessment(req)))
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(committed),"late duplicate assessment cannot double turn")
	mock.respond(ntoken,envelope({"schema_version":"ai_gm_narration/v1","action_id":nr.action_id,"state_version":nr.state_version,"context_hash":nr.context_hash,"narration":"观察已经结算，已提交的线索与数值决定后续冒险。"}))
	check(not scene.playtest.narration.is_empty(),"actual main receives optional provider prose")
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(committed),"provider prose never changes authority")
	# Actual main save/load methods use the existing own adventure slot. Preserve
	# any prior player save fixture around this integration test.
	var path: String=scene.playtest.COAST_SAVE
	var existed:=FileAccess.file_exists(path)
	var prior:=FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var prose_path:String=path+".narration.json"
	var prose_existed:=FileAccess.file_exists(prose_path)
	var prior_prose:=FileAccess.get_file_as_bytes(prose_path) if prose_existed else PackedByteArray()
	scene.save_game()
	check(scene.last_save_result.get("ok",false) and FileAccess.file_exists(path),"actual main writes save")
	check(not FileAccess.get_file_as_string(path).contains("synthetic-main-flow-marker"),"actual save has no credential")
	scene.load_game()
	check(scene.last_load_result.get("ok",false),"actual main load reports validated success")
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(committed),"actual main restore keeps committed facts/RNG/receipts")
	check(scene.playtest.narration_entries().size()==1 and not scene.playtest.narration.is_empty(),"provider prose survives actual main save/load as one display record")
	check(scene.journal.get_parsed_text().contains("叙事记录 · 第") and not scene.journal.get_parsed_text().contains("非权威"),"loaded narration uses natural heading without internal jargon")
	check(scene.playtest.journal_entries().any(func(row):return row.get("non_authoritative",false)),"display-only title change preserves nonauthoritative protocol metadata")
	var journal_count:int=scene.journal.get_parsed_text().count("观察已经结算，已提交的线索与数值决定后续冒险。")
	var manual:Dictionary={"schema_version":"ai_gm_narration/v1","action_id":nr.action_id,"state_version":nr.state_version,"context_hash":nr.context_hash,"narration":"duplicate manual text must not retcon history"}
	check(scene.apply_playtest_reply(manual),"manual narration uses same committed history route")
	check(scene.playtest.narration_entries().size()==1 and scene.journal.get_parsed_text().count("观察已经结算，已提交的线索与数值决定后续冒险。") == journal_count,"manual duplicate does not append/rewrite provider history")
	manual.narration="synthetic-main-flow-marker-not-an-api-key"
	check(not scene.apply_playtest_reply(manual) and not FileAccess.get_file_as_string(prose_path).contains(manual.narration),"manual import cannot persist currently configured credential")
	var sent_before_duplicate:int=mock.sent.size()
	var duplicate_narration:Dictionary=runtime.request_narration()
	check(not duplicate_narration.ok and duplicate_narration.code=="ALREADY_RECORDED" and mock.sent.size()==sent_before_duplicate,"logged current narration cannot trigger another potentially paid request")
	check(panel.narration_button.disabled,"advanced narrator button disabled for already logged receipt")
	# Create a genuinely unrecorded second receipt, with automatic prose disabled.
	# Then prove a new intent cancels its optional narrator without blocking play.
	panel.automatic_narration_input.button_pressed=false
	scene.set_player_intent("我再次核对海岸与旧灯的可见线索。")
	scene.end_turn();req=outgoing(mock);token=mock.sent.back().request_id
	mock.respond(token,envelope(assessment(req)))
	check(scene.playtest.phase()=="idle" and not runtime.narration_recorded(),"second committed receipt genuinely has no prose record")
	committed=scene.playtest.engine.save_data()
	check(runtime.request_narration().ok,"unrecorded committed receipt may request optional narration")
	nr=outgoing(mock);ntoken=mock.sent.back().request_id
	scene.set_player_intent("再次观察旧灯附近目前的线索。")
	scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment" and outgoing(mock).phase=="assessment","new intent cancels obsolete narrator and starts next decision")
	mock.respond(ntoken,envelope({"schema_version":"ai_gm_narration/v1","action_id":nr.action_id,"state_version":nr.state_version,"context_hash":nr.context_hash,"narration":"过期叙事不得显示"}))
	check(scene.playtest.narration!="过期叙事不得显示" and C.bytes(scene.playtest.state_copy())==C.bytes(committed.state),"obsolete prose cannot affect newer turn")
	scene.cancel_pending()
	# Failures traverse the real main UI/controller, not a codec-only harness.
	var wall_clock:Dictionary={"ms":1000000}
	runtime.clock=func():return wall_clock.ms
	for code in [401,429,500,503]:
		wall_clock.ms+=40000
		scene.set_player_intent("观察旧灯附近的现状。")
		scene.end_turn()
		var pending_state:=C.bytes(scene.playtest.engine.save_data())
		var count:int=mock.sent.size()
		mock.respond(mock.sent.back().request_id,"discarded provider diagnostic",code)
		check(not runtime.busy() and scene.playtest.phase()=="awaiting_assessment","main HTTP %d exits waiting transport honestly"%code)
		check(mock.sent.size()==count and C.bytes(scene.playtest.engine.save_data())==pending_state,"main HTTP %d neither retries nor changes facts/RNG"%code)
		scene.cancel_pending()
	wall_clock.ms+=40000
	for bad_body in ["malformed",envelope({"error":{"code":"UNSUPPORTED_INTENT"}})]:
		scene.set_player_intent("观察海岸目前的情况。")
		scene.end_turn()
		var pending_state:=C.bytes(scene.playtest.engine.save_data())
		mock.respond(mock.sent.back().request_id,bad_body)
		check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.engine.save_data())==pending_state,"main malformed/unsupported reply cannot fabricate a turn")
		scene.cancel_pending()
	# A validated pending save/load must cancel its in-flight provider request.
	scene.set_player_intent("检查眼前旧灯附近的线索。")
	scene.end_turn();req=outgoing(mock);token=mock.sent.back().request_id
	scene.save_game();check(scene.last_save_result.get("ok",false),"actual main saves awaiting provider state")
	scene.load_game();check(scene.last_load_result.get("ok",false),"actual main restores awaiting state successfully")
	var loaded_pending:=C.bytes(scene.playtest.engine.save_data())
	mock.respond(token,envelope(assessment(req)))
	check(scene.playtest.phase()=="awaiting_assessment" and not runtime.busy() and C.bytes(scene.playtest.engine.save_data())==loaded_pending,"pending load invalidates old response without replaying or retrying")
	check(scene.playtest.narration.is_empty() and scene.playtest.narration_entries().size()==1,"pending load keeps old prose historical instead of assigning it to new intent")
	scene.cancel_pending()
	if existed:
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(prior);file.close()
	else:DirAccess.remove_absolute(path)
	if prose_existed:
		var file:=FileAccess.open(prose_path,FileAccess.WRITE);file.store_buffer(prior_prose);file.close()
	else:DirAccess.remove_absolute(prose_path)
	panel._clear()
	check(not runtime.client.configured() and not runtime.automatic_assessment_enabled(),"clear returns actual main to honest offline")
	var report:Dictionary={"scope":"actual main scene + real 1801-cell source + injected mock provider only","checks":checks,"failures":failures,"live_api_executed":false,"provider_model_semantics_verified":false,"public_context_metrics":runtime.last_metrics}
	var f:=FileAccess.open("res://artifacts/runtime_ai_20261003/main_flow_results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	scene.free(); print("ACTUAL MAIN AI FLOW ",checks-failures.size(),"/",checks,"; MOCK ONLY; NO NETWORK")
	quit(0 if failures.is_empty() else 1)

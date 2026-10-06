extends SceneTree
## Provider successor of the accepted real-Main flow; mock only, not live service.
## Unexecuted cloud test attachment: requires the public restored base and isolated user://.
## No real credentials, external fixtures, authority hash substitution or native acceptance claim.
const Main = preload("res://main.tscn")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const Presets=preload("res://view/dual_api_settings/provider_presets.gd")
const PROVIDERS := {"narration":"deepseek","decision":"openrouter"}
const DECISION_KEY := "synthetic-main-flow-marker-not-an-api-key"
const NARRATION_KEY := "synthetic-main-narration-marker-not-an-api-key"
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
func check_transport(runtime: Node, mock: Node) -> bool:
	var accepted: bool=runtime.set_transport(mock).get("ok",false) and mock.info().get("live",true)==false
	check(accepted,"explicit mock must replace live transport before provider configuration")
	return accepted
func check_wire(mock: Node, token_parameter: String, label_: String) -> void:
	var body: Dictionary=JSON.parse_string(mock.sent.back().body)
	check(body.get(token_parameter)==2048 and not body.has("max_tokens" if token_parameter=="max_completion_tokens" else "max_completion_tokens"),label_+" preserves exact provider token parameter and limit")
	check(not body.has("store") and not body.has("response_format") and not body.has("thinking") and not body.has("reasoning_effort"),label_+" omits unsupported or unselected optional parameters")
func run() -> void:
	var expected_user_dir := OS.get_environment("FOGBANK_API_TEST_USER_DIR").replace("\\", "/").trim_suffix("/")
	var actual_user_dir := OS.get_user_data_dir().replace("\\", "/").trim_suffix("/")
	if expected_user_dir.is_empty() or actual_user_dir != expected_user_dir:
		printerr("FULL_API_TEST_REFUSED: explicit isolated user directory must match actual user://")
		quit(2); return
	if FileAccess.file_exists("user://r24_coast_adventure_save.json") or FileAccess.file_exists("user://r24_coast_adventure_save.json.narration.json"):
		printerr("PROVIDER_MAIN_TEST_REFUSED: use a fresh isolated provider test user directory");quit(2);return
	var scene:=Main.instantiate();root.add_child(scene);current_scene=scene
	await process_frame; await process_frame
	check(scene.coast_mode and scene.playtest_mode and scene.playtest!=null,"default Main selects real Coast adapter")
	if scene.playtest==null:
		scene.free(); quit(1); return
	var boot_state: Dictionary=scene.playtest.state_copy()
	var generated: Dictionary=boot_state.get("generated_world",{})
	var bundle_ok: bool=Bundle.ready()
	check(bundle_ok,"default production Bundle validator accepts every public runtime dependency")
	var bundle_manifest: Dictionary=Bundle.manifest() if bundle_ok else {}
	var catalog: Dictionary=Bundle.document("catalog") if bundle_ok else {}
	var source_identity: Dictionary=bundle_manifest.get("source_identity",{})
	var initial_identity: Dictionary={"world_id":boot_state.get("world_id"),"hex_count":boot_state.get("hexes",{}).size(),"scene_id":boot_state.get("actors",{}).get("actor_player",{}).get("scene_id"),"scene_hex_count":boot_state.get("scenes",{}).get("scene_coast",{}).get("hex_ids",[]).size(),"rule_id":scene.playtest.engine.rule_id(),"bundle_id":generated.get("bundle_id"),"catalog_sha256":generated.get("catalog_sha256"),"source_mesh_sha256":generated.get("source_mesh_sha256"),"source_drainage_sha256":generated.get("source_drainage_sha256")}
	check(initial_identity.world_id=="natural_coast_shore_v03_adventure" and initial_identity.world_id==catalog.get("world_id"),"actual world identity is published natural shore adventure, never fallback")
	check(initial_identity.hex_count==1801 and initial_identity.scene_hex_count==1801 and initial_identity.scene_id=="scene_coast","actual world and active Coast scene each contain 1801 cells")
	check(initial_identity.rule_id=="coast_release/v1" and scene.playtest.get_script().resource_path=="res://view/playable_build/adapter.gd" and not scene.playtest.status_gameplay_mode,"actual Main uses default production release adapter/profile, never seeded/test/actor-status profile")
	check(initial_identity.bundle_id==Bundle.bundle_id() and initial_identity.catalog_sha256==Bundle.catalog_sha256(),"actual generated world binds the current public validated bundle and catalog")
	check(initial_identity.source_mesh_sha256==source_identity.get("mesh_sha256") and initial_identity.source_drainage_sha256==source_identity.get("drainage_sha256"),"actual generated world binds validated public source mesh and drainage identity")
	check(is_instance_valid(scene.board) and scene.board.get_script().resource_path=="res://view/playable_build/board.gd" and scene.board.load_error.is_empty(),"real production Coast board loads without fallback or source error")
	if not failures.is_empty():
		printerr("FULL_API_MAIN_BOOT_FAILED "+str(failures));scene.free();quit(1);return
	check(is_instance_valid(scene.runtime_ai),"runtime exists in actual default main")
	var runtime: Node=scene.runtime_ai
	var panel: Control=scene.runtime_connection_panel
	check(is_instance_valid(panel) and not runtime.automatic_assessment_enabled(),"actual advanced panel starts offline")
	var mock:=Mock.new()
	if not check_transport(runtime,mock):
		scene.free();quit(1);return
	scene.set_player_intent("我停下来观察南潮海岸和旧灯，记录能看到的线索。")
	scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment" and mock.sent.is_empty(),"offline free input waits honestly without fabricated result")
	scene.cancel_pending()
	check(scene.playtest.phase()=="idle","actual main can cancel offline wait")
	scene.show_ai_connection()
	await process_frame; await process_frame
	check(panel.settings_dialog.visible and panel.role_fields.size()==2,"actual Main settings opens two-role modal")
	var unchanged_draft: String=scene.goal.text
	var unchanged_state:=C.bytes(scene.playtest.engine.save_data())
	for role in ["narration","decision"]:
		var field: Dictionary=panel.role_fields[role]
		field.preset.select(Presets.IDS.find(PROVIDERS[role]));field.preset.item_selected.emit(field.preset.selected)
		field.model.text="provided-%s-model"%role
		field.key.text=NARRATION_KEY if role=="narration" else DECISION_KEY
	panel.enable_input.button_pressed=true
	scene.end_turn()
	check(mock.sent.is_empty() and C.bytes(scene.playtest.engine.save_data())==unchanged_state,"open API modal prevents background end-turn")
	panel.close_settings()
	await process_frame; await process_frame
	check(not runtime.client.any_role_configured() and not runtime.connection_enabled and scene.goal.text==unchanged_draft,"Cancel preserves offline configuration and narrative draft")
	scene.show_ai_connection()
	for role in ["narration","decision"]:
		var field: Dictionary=panel.role_fields[role]
		field.preset.select(Presets.IDS.find(PROVIDERS[role]));field.preset.item_selected.emit(field.preset.selected)
		field.model.text="provided-%s-model"%role
		field.key.text=NARRATION_KEY if role=="narration" else DECISION_KEY
	panel.enable_input.button_pressed=true
	panel._save_settings()
	await process_frame; await process_frame
	panel.automatic_assessment_input.button_pressed=true
	panel.automatic_narration_input.button_pressed=true
	check(not panel.settings_dialog.visible and runtime.automatic_assessment_enabled() and mock.sent.is_empty(),"saving two provider roles enables explicit end-turn with no send")
	check(panel.role_fields.narration.key.text.is_empty() and panel.role_fields.decision.key.text.is_empty() and panel.role_fields.narration.key.secret and panel.role_fields.decision.key.secret,"both masked key fields cleared after memory-only save")
	var saved_roles: Dictionary={"narration":runtime.client.role_configuration("narration"),"decision":runtime.client.role_configuration("decision")}
	scene.show_ai_connection()
	panel.role_fields.decision.model.text="unapplied-provider-model"
	panel.close_settings()
	await process_frame; await process_frame
	check(runtime.client.role_configuration("decision")==saved_roles.decision and runtime.client.role_configuration("narration")==saved_roles.narration and runtime.automatic_assessment_enabled(),"Cancel on configured modal preserves both roles and enable state")
	scene.show_ai_connection()
	panel._save_settings()
	await process_frame; await process_frame
	check(runtime.client.contains_current_credential(DECISION_KEY) and runtime.client.contains_current_credential(NARRATION_KEY) and mock.sent.is_empty(),"blank key save retains both session credentials without request")
	scene.show_ai_connection()
	panel.role_fields.decision.endpoint.text=Presets.ENDPOINTS.openrouter+"/other-tenant"
	panel.role_fields.decision.endpoint.text_changed.emit(panel.role_fields.decision.endpoint.text)
	panel._save_settings()
	await process_frame;await process_frame
	check(panel.settings_dialog.visible and panel.dialog_status.visible and runtime.client.role_configuration("decision")==saved_roles.decision and runtime.client.role_configuration("narration")==saved_roles.narration and mock.sent.is_empty(),"real Main blocks changed full endpoint with blank key atomically without send")
	panel.close_settings();await process_frame;await process_frame
	scene.on_hex_selected(Vector2i(-2,15))
	var text:="我留在原地观察南潮海岸和旧灯，记下眼前的线索，不向关注格移动。"
	scene.set_player_intent(text)
	var before:Dictionary=scene.playtest.engine.save_data()
	scene.end_turn()
	check(mock.sent.size()==1 and scene.playtest.phase()=="awaiting_assessment","actual primary action requests assessment once")
	check(mock.sent.back().endpoint==Presets.ENDPOINTS.openrouter and JSON.parse_string(mock.sent.back().body).model=="provided-decision-model" and mock.sent.back().headers.has("Authorization: Bearer "+DECISION_KEY) and not mock.sent.back().headers.has("Authorization: Bearer "+NARRATION_KEY),"actual Main assessment selects decision endpoint model and credential only")
	check_wire(mock,"max_completion_tokens","actual Main OpenRouter decision")
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
	check(mock.sent.back().endpoint==Presets.ENDPOINTS.deepseek and JSON.parse_string(mock.sent.back().body).model=="provided-narration-model" and mock.sent.back().headers.has("Authorization: Bearer "+NARRATION_KEY) and not mock.sent.back().headers.has("Authorization: Bearer "+DECISION_KEY),"actual Main narration selects narration endpoint model and credential only")
	check_wire(mock,"max_tokens","actual Main DeepSeek narration")
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
	check(not runtime.client.contains_current_credential(FileAccess.get_file_as_string(path)) and (not FileAccess.file_exists(prose_path) or not runtime.client.contains_current_credential(FileAccess.get_file_as_string(prose_path))),"actual save and prose sidecar contain neither credential")
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
	var report:Dictionary={"schema":"provider_presets_public_full_main_test/v1","providers":PROVIDERS,"scope":"actual Main + real public 1801-cell source + injected mock only; not OS keyboard or broad gameplay acceptance","network_calls":0,"isolated_user_dir_matched":true,"initial_world_identity":initial_identity,"checks":checks,"failures":failures,"live_api_executed":false,"provider_model_semantics_verified":false,"public_context_metrics":runtime.last_metrics}
	var report_path: String=OS.get_environment("FOGBANK_API_TEST_REPORT")
	if report_path.is_empty(): report_path="user://provider_presets_main_results.json"
	var f:=FileAccess.open(report_path,FileAccess.WRITE)
	if f==null:
		failures.append("test report could not be written")
		printerr("FULL_API_TEST_REPORT_WRITE_FAILED")
	else: f.store_string(JSON.stringify(report,"\t"));f.close()
	scene.free(); print("ACTUAL PROVIDER MAIN FLOW ",checks-failures.size(),"/",checks,"; MOCK ONLY; NO NETWORK")
	quit(0 if failures.is_empty() else 1)

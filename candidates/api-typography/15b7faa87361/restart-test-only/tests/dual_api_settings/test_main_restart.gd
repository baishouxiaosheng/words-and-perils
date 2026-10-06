extends SceneTree
## Two invocations of real Main: write, exit; read in a distinct OS process.
## Test-only, mock transport, exact isolated user directory, no external fixture.
const Main = preload("res://main.tscn")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const DECISION_KEY := "synthetic-restart-decision-not-an-api-key"
const NARRATION_KEY := "synthetic-restart-narration-not-an-api-key"
const PROSE := "这次观察已经结算；已保存的海岸线索将在重新启动后继续保留。"
const PINS := {
	"main.gd":"48d166879987b7285c21ce2bf7388a37654f1710131db851dfc0f70b0d6deb42",
	"view/dual_api_settings/client.gd":"5d84992c2f3a7e28f02795511b0b0c79bc24f2ae0e0cbf0e5a8b4ec8f2db7ffc",
	"view/dual_api_settings/controller.gd":"214ccf927d266317a7fe037c18f5d1d6f6592fe4c49e7059485969735f05063a",
	"view/dual_api_settings/panel.gd":"3c7c0298e79bf334dae4d7dc67d334f11e0d46aee1ed145672ae7bc6a1853c75",
	"view/ui_typography/style.gd":"0ce716c357b80da23063ae8f8d678a2c4c022f58df63c34b14ad802f9b90e565"
}
var app: Control
var mock: Node
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {}
var stage := ""
var nonce := ""
var receipt_path := ""
var report_path := ""
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("RESTART_FAIL: "+label)
	return value
func frames(n: int = 4) -> void:
	for _i in range(n): await process_frame
func digest(value: Variant) -> String: return C.bytes(value).sha256_text()
func clean(text: String) -> bool: return not text.contains(DECISION_KEY) and not text.contains(NARRATION_KEY)
func envelope(reply: Dictionary) -> String: return JSON.stringify({"choices":[{"finish_reason":"stop","message":{"content":JSON.stringify(reply)}}]})
func outgoing() -> Dictionary: return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func assessment(request: Dictionary) -> Dictionary:
	return {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,
		"narration":"你打算观察旧灯。","interpretation":"根据完整自由意图评估海岸观察。","resolver_id":"coast_observe","bindings":{"actor_id":"actor_player"},
		"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["player","coast"]}],
		"fact_refs":[{"id":"player","path":"/actors/actor_player","expected":request.context.facts.actors.actor_player},{"id":"coast","path":"/story_anchors/anchor_coast","expected":request.context.facts.story_anchors.anchor_coast}],
		"provenance":{"provider":"mock_test_transport","live":false,"kind":"model_reply"}}
func snapshot() -> Dictionary:
	var data: Dictionary=app.playtest.engine.save_data()
	var state: Dictionary=app.playtest.state_copy()
	var player: Dictionary=state.actors.actor_player
	return {"engine_sha256":digest(data),"world_sha256":digest(state),"rng_sha256":digest(data.rng),"action_sha256":digest(app.playtest.action_copy()),"history_sha256":digest(app.playtest.journal_entries()),"prose_sha256":digest(app.playtest.narration_entries()),"phase":app.playtest.phase(),"world_id":state.world_id,"turn":state.turn,"state_version":state.state_version,"position":player.hex.duplicate(),"scene_id":player.scene_id,"health":player.health.duplicate(true),"stamina":player.stamina.duplicate(true),"inventory_sha256":digest(state.items),"generated_world_sha256":digest(state.generated_world)}
func bootstrap() -> bool:
	check(app.coast_mode and app.playtest_mode and app.playtest!=null,"real Main enters Coast")
	if app.playtest==null: return false
	var state: Dictionary=app.playtest.state_copy()
	var identity: Dictionary=state.get("generated_world",{})
	var bundle_ok: bool=Bundle.ready()
	check(bundle_ok,"public source Bundle validator accepts complete real closure")
	var catalog: Dictionary=Bundle.document("catalog") if bundle_ok else {}
	var source: Dictionary=Bundle.manifest().get("source_identity",{}) if bundle_ok else {}
	check(state.get("world_id")=="natural_coast_shore_v03_adventure" and state.get("world_id")==catalog.get("world_id"),"actual public Coast world identity")
	check(state.get("hexes",{}).size()==1801 and state.get("scenes",{}).get("scene_coast",{}).get("hex_ids",[]).size()==1801 and state.get("actors",{}).get("actor_player",{}).get("scene_id")=="scene_coast","real world and Coast scene each contain 1801 cells")
	check(app.playtest.engine.rule_id()=="coast_release/v1" and app.playtest.get_script().resource_path=="res://view/playable_build/adapter.gd" and not app.playtest.status_gameplay_mode,"default production profile and adapter without test seed or status override")
	check(identity.get("bundle_id")==Bundle.bundle_id() and identity.get("catalog_sha256")==Bundle.catalog_sha256() and identity.get("source_mesh_sha256")==source.get("mesh_sha256") and identity.get("source_drainage_sha256")==source.get("drainage_sha256"),"world binds actual validated public catalog and source identity")
	check(is_instance_valid(app.board) and app.board.get_script().resource_path=="res://view/playable_build/board.gd" and app.board.load_error.is_empty(),"real source Coast board loaded")
	check(is_instance_valid(app.runtime_ai) and not app.runtime_ai.connection_enabled and not app.runtime_ai.client.any_role_configured() and not app.runtime_ai.automatic_assessment_enabled(),"fresh Main has no configured roles and is offline")
	return failures.is_empty()
func run() -> void:
	stage=OS.get_environment("FOGBANK_API_RESTART_STAGE")
	nonce=OS.get_environment("FOGBANK_API_RESTART_NONCE")
	var expected_dir := OS.get_environment("FOGBANK_API_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	var actual_dir := OS.get_user_data_dir().replace("\\","/").trim_suffix("/")
	var valid_nonce: bool=nonce.length()>=16 and nonce.length()<=80
	for character in nonce: valid_nonce=valid_nonce and (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
	if stage not in ["write","read"] or not valid_nonce or expected_dir.is_empty() or expected_dir!=actual_dir or not OS.get_cmdline_user_args().is_empty():
		printerr("RESTART_REFUSED: explicit isolated directory, unique nonce and write/read stage required");quit(2);return
	receipt_path="user://api_restart_receipt_"+nonce+".json"
	report_path="user://api_restart_"+stage+"_"+nonce+".json"
	if FileAccess.file_exists(report_path) or (stage=="write" and FileAccess.file_exists(receipt_path)):
		printerr("RESTART_REFUSED: existing report/receipt must not be overwritten");quit(2);return
	report={"schema":"dual_api_real_main_restart/v1","stage":stage,"nonce":nonce,"pid":OS.get_process_id(),"test_sha256":FileAccess.get_sha256(get_script().resource_path),"production_pins":PINS,"isolated_user_dir_matched":true,"network_basis":"single mock transport; no live provider; not an OS packet measurement"}
	for path in PINS: check(FileAccess.get_sha256("res://"+path)==PINS[path],"production source pin "+path)
	if not failures.is_empty(): await finish(); return
	app=Main.instantiate();root.add_child(app);current_scene=app
	await frames()
	if not bootstrap(): await finish();return
	mock=Mock.new()
	if not check(app.runtime_ai.set_transport(mock).get("ok",false) and mock.info().get("live",true)==false,"explicit mock transport accepted before requests"):
		await finish();return
	if stage=="write": await write_stage()
	else: await read_stage()
	await finish()
func write_stage() -> void:
	var path: String=app.playtest.COAST_SAVE
	var prose_path: String=path+".narration.json"
	if not check(not FileAccess.file_exists(path) and not FileAccess.file_exists(prose_path),"writer refuses any prior save or sidecar in isolated slot"): return
	var before: Dictionary=snapshot()
	var panel: Control=app.runtime_connection_panel
	app.show_ai_connection()
	for role in ["narration","decision"]:
		var fields: Dictionary=panel.role_fields[role]
		fields.endpoint.text="https://restart-"+role+".invalid/v1/chat/completions"
		fields.model.text="restart-"+role+"-model"
		fields.key.text=NARRATION_KEY if role=="narration" else DECISION_KEY
	panel.enable_input.button_pressed=true;panel._save_settings()
	await frames()
	panel.automatic_assessment_input.button_pressed=true;panel.automatic_narration_input.button_pressed=true
	if not check(app.runtime_ai.automatic_assessment_enabled() and app.runtime_ai.client.contains_current_credential(DECISION_KEY) and app.runtime_ai.client.contains_current_credential(NARRATION_KEY) and mock.sent.is_empty(),"writer configures both session-only dummy roles without send"): return
	app.set_player_intent("我留在原地观察南潮海岸和旧灯，记录眼前的线索。")
	app.end_turn()
	if not check(mock.sent.size()==1 and app.playtest.phase()=="awaiting_assessment","real Main submits one decision request"): return
	check(mock.sent.back().headers.has("Authorization: Bearer "+DECISION_KEY) and not mock.sent.back().headers.has("Authorization: Bearer "+NARRATION_KEY),"writer decision uses its own key")
	var request: Dictionary=outgoing();mock.respond(mock.sent.back().request_id,envelope(assessment(request)))
	if not check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==before.turn+1 and mock.sent.size()==2 and outgoing().phase=="narration","real Main commits one turn and requests optional prose"): return
	check(mock.sent.back().headers.has("Authorization: Bearer "+NARRATION_KEY) and not mock.sent.back().headers.has("Authorization: Bearer "+DECISION_KEY),"writer narration uses its own key")
	request=outgoing();mock.respond(mock.sent.back().request_id,envelope({"schema_version":"ai_gm_narration/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":PROSE}))
	await frames()
	check(app.playtest.narration==PROSE and app.playtest.narration_entries().size()==1 and app.playtest.phase()=="idle" and not app.runtime_ai.busy() and mock.sent.size()==2,"committed optional prose is recorded once and writer transport is idle after exactly two mock sends")
	var expected: Dictionary=snapshot()
	check(expected.engine_sha256!=before.engine_sha256 and expected.rng_sha256!=before.rng_sha256 and not app.playtest.journal_entries().is_empty(),"ordinary unseeded action creates changed state RNG and authoritative history")
	app.save_game()
	if not check(app.last_save_result.get("ok",false) and FileAccess.file_exists(path) and FileAccess.file_exists(prose_path),"real Main writes both save and narration sidecar"):return
	check(snapshot()==expected,"saving does not mutate committed facts RNG resources or history")
	check(clean(FileAccess.get_file_as_string(path)) and clean(FileAccess.get_file_as_string(prose_path)),"neither dummy key enters persisted save or prose")
	if not failures.is_empty(): return
	var receipt: Dictionary={"schema":"dual_api_main_restart_receipt/v1","nonce":nonce,"writer_pid":OS.get_process_id(),"test_sha256":report.test_sha256,"production_pins":PINS,"snapshot":expected,"history":app.playtest.journal_entries(),"prose":app.playtest.narration_entries(),"save_sha256":FileAccess.get_sha256(path),"sidecar_sha256":FileAccess.get_sha256(prose_path)}
	var file:=FileAccess.open(receipt_path,FileAccess.WRITE)
	if not check(file!=null,"writer receipt opened"):return
	file.store_string(C.bytes(receipt));file.flush();file.close()
	check(clean(FileAccess.get_file_as_string(receipt_path)),"writer receipt contains no credentials")
	report["receipt_sha256"]=FileAccess.get_sha256(receipt_path);report["snapshot"]=expected;report["mock_sends"]=mock.sent.size()
func read_stage() -> void:
	var expected_hash := OS.get_environment("FOGBANK_API_RESTART_RECEIPT_SHA256")
	if not check(expected_hash.length()==64 and FileAccess.file_exists(receipt_path) and FileAccess.get_sha256(receipt_path)==expected_hash,"reader requires exact separately recorded writer receipt SHA"):return
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not check(raw is Dictionary and raw.get("schema")=="dual_api_main_restart_receipt/v1" and raw.get("nonce")==nonce,"reader receipt schema and nonce match"):return
	var receipt: Dictionary=raw
	if not check(int(receipt.writer_pid)!=OS.get_process_id() and receipt.test_sha256==report.test_sha256 and receipt.production_pins==PINS,"reader is a distinct process with identical test and production sources"):return
	var path: String=app.playtest.COAST_SAVE;var prose_path: String=path+".narration.json"
	if not check(FileAccess.get_sha256(path)==receipt.save_sha256 and FileAccess.get_sha256(prose_path)==receipt.sidecar_sha256,"reader sees exact disk files produced by writer"):return
	check(clean(FileAccess.get_file_as_string(path)) and clean(FileAccess.get_file_as_string(prose_path)),"persisted files contain neither prior process key")
	check(not app.runtime_ai.client.contains_current_credential(DECISION_KEY) and not app.runtime_ai.client.contains_current_credential(NARRATION_KEY) and not app.runtime_ai.client.any_role_configured() and not app.runtime_ai.connection_enabled,"new process did not recover session-only credentials")
	app.load_game()
	await frames()
	if not check(app.last_load_result.get("ok",false),"new real Main Continue/load accepts actual prior process save"):return
	var actual: Dictionary=snapshot();var expected: Dictionary=receipt.snapshot
	check(actual.engine_sha256==expected.engine_sha256 and actual.world_sha256==expected.world_sha256,"entire authoritative engine and world state exactly restore")
	check(actual.world_id==expected.world_id and actual.generated_world_sha256==expected.generated_world_sha256 and actual.turn==expected.turn and actual.state_version==expected.state_version,"world identity and committed turn/version restore")
	check(actual.position==expected.position and actual.scene_id==expected.scene_id,"actual player position and scene restore")
	check(actual.health==expected.health and actual.stamina==expected.stamina and actual.inventory_sha256==expected.inventory_sha256,"health stamina and all inventory/resource records restore")
	check(actual.rng_sha256==expected.rng_sha256 and actual.action_sha256==expected.action_sha256 and actual.phase==expected.phase,"RNG stream active action and phase restore without reroll")
	check(actual.history_sha256==expected.history_sha256 and actual.prose_sha256==expected.prose_sha256,"authoritative history and bound prose restore exactly")
	check(C.bytes(app.playtest.journal_entries())==C.bytes(receipt.history) and C.bytes(app.playtest.narration_entries())==C.bytes(receipt.prose),"saved historical wording and prose records are identical")
	check(app.journal.get_parsed_text().count(PROSE)==1,"actual Main history shows restored prose once")
	check(not app.runtime_ai.client.any_role_configured() and not app.runtime_ai.connection_enabled and not app.runtime_ai.automatic_assessment_enabled() and mock.sent.is_empty(),"Continue stays offline without provider send or restored credentials")
	check(FileAccess.get_sha256(path)==receipt.save_sha256 and FileAccess.get_sha256(prose_path)==receipt.sidecar_sha256,"Continue does not rewrite prior disk evidence")
	report["receipt_sha256"]=expected_hash;report["writer_pid"]=receipt.writer_pid;report["snapshot"]=actual;report["mock_sends"]=mock.sent.size()
func finish() -> void:
	if is_instance_valid(app):
		app.free();app=null
	await frames()
	for path in PINS: check(FileAccess.get_sha256("res://"+path)==PINS[path],"production source unchanged after stage "+path)
	report["checks"]=checks;report["failures"]=failures;report["ok"]=failures.is_empty()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:printerr("RESTART_REPORT_WRITE_FAILED");quit(1);return
	file.store_string(C.bytes(report));file.flush();file.close()
	print("ACTUAL_MAIN_RESTART ",stage," ",checks-failures.size(),"/",checks," PID=",OS.get_process_id()," REPORT_SHA256=",FileAccess.get_sha256(report_path))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Reader-only correction for exact successful revision-2 writer evidence.
## Preserves whole-state/RNG equality; normalizes only validated JSON integers.
## Test-only, mock transport, exact isolated user directory, no external fixture.
const Main = preload("res://main.tscn")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const DECISION_KEY := "synthetic-restart-decision-not-an-api-key"
const NARRATION_KEY := "synthetic-restart-narration-not-an-api-key"
const ACCEPTED_WRITER_TEST_SHA := "629e6b4e5a540a5a8b10992ea6b31de2218a8dd175867c1b1443888a2cae366d"
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
	if stage!="read" or not valid_nonce or expected_dir.is_empty() or expected_dir!=actual_dir or not OS.get_cmdline_user_args().is_empty():
		printerr("RESTART_REFUSED: explicit isolated directory, unique nonce and reader stage required");quit(2);return
	receipt_path="user://api_restart_receipt_"+nonce+".json"
	report_path="user://api_restart_read_r3_"+nonce+".json"
	if FileAccess.file_exists(report_path) or (stage=="write" and FileAccess.file_exists(receipt_path)):
		printerr("RESTART_REFUSED: existing report/receipt must not be overwritten");quit(2);return
	report={"schema":"dual_api_real_main_restart/v1","stage":stage,"nonce":nonce,"pid":OS.get_process_id(),"test_sha256":FileAccess.get_sha256(get_script().resource_path),"production_pins":PINS,"accepted_writer_test_sha256":ACCEPTED_WRITER_TEST_SHA,"reader_revision":3,"isolated_user_dir_matched":true,"network_basis":"single mock transport; no live provider; not an OS packet measurement"}
	for path in PINS: check(FileAccess.get_sha256("res://"+path)==PINS[path],"production source pin "+path)
	check(valid_position([-1,14]) and valid_position([-1.0,14.0]) and C.bytes([-1,14])==C.bytes([-1.0,14.0]),"integer JSON roundtrip normalization is exact")
	for invalid in [[true,14],[-1.25,14],[INF,0],[NAN,0],[C.LIMIT+1,0],[0]]:
		check(not valid_position(invalid),"position boundary rejects bool fraction nonfinite out-of-range and wrong shape")
	check(not valid_pool({"current":true,"max":12}) and not valid_pool({"current":13,"max":12}) and not valid_pool({"current":0,"max":0}) and not valid_pool({"current":0,"max":INF}),"pool boundary rejects bool invalid range and nonfinite")
	if not failures.is_empty(): await finish(); return
	app=Main.instantiate();root.add_child(app);current_scene=app
	await frames()
	if not bootstrap(): await finish();return
	mock=Mock.new()
	if not check(app.runtime_ai.set_transport(mock).get("ok",false) and mock.info().get("live",true)==false,"explicit mock transport accepted before requests"):
		await finish();return
	await read_stage()
	await finish()
func valid_position(value: Variant) -> bool:
	return value is Array and value.size()==2 and C.integer(value[0]) and C.integer(value[1])
func valid_pool(value: Variant) -> bool:
	return C.exact_fields(value,["current","max"]) and C.integer(value.current) and C.integer(value.max) and value.max>0 and value.current>=0 and value.current<=value.max
func normalized_equal(first: Variant, second: Variant) -> bool:
	var a: Variant=C.normalized(first);var b: Variant=C.normalized(second)
	if not (a is Array or a is Dictionary) or typeof(a)!=typeof(b) or a.is_empty() or b.is_empty():return false
	var a_bytes: String=C.bytes(a);var b_bytes: String=C.bytes(b)
	return not a_bytes.is_empty() and not b_bytes.is_empty() and a_bytes==b_bytes
func boundary_types(value: Dictionary) -> Dictionary:
	var position_elements: Array=[]
	if value.position is Array:
		for part in value.position:position_elements.append(typeof(part))
	return {"position":typeof(value.position),"position_elements":position_elements,"scene_id":typeof(value.scene_id),"health":typeof(value.health),"health_current":typeof(value.health.current),"health_max":typeof(value.health.max),"stamina":typeof(value.stamina),"stamina_current":typeof(value.stamina.current),"stamina_max":typeof(value.stamina.max)}
func read_stage() -> void:
	var expected_hash := OS.get_environment("FOGBANK_API_RESTART_RECEIPT_SHA256")
	if not check(expected_hash.length()==64 and FileAccess.file_exists(receipt_path) and FileAccess.get_sha256(receipt_path)==expected_hash,"reader requires exact separately recorded writer receipt SHA"):return
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not check(raw is Dictionary and raw.get("schema")=="dual_api_main_restart_receipt/v1" and raw.get("nonce")==nonce,"reader receipt schema and nonce match"):return
	var receipt: Dictionary=raw
	if not check(int(receipt.writer_pid)!=OS.get_process_id() and receipt.test_sha256==ACCEPTED_WRITER_TEST_SHA and receipt.production_pins==PINS,"reader is a distinct process linked to the exact accepted revision-2 writer and same production sources"):return
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
	var position_shape: bool=valid_position(actual.position) and valid_position(expected.position)
	var health_shape: bool=valid_pool(actual.health) and valid_pool(expected.health)
	var stamina_shape: bool=valid_pool(actual.stamina) and valid_pool(expected.stamina)
	var position_equal: bool=position_shape and normalized_equal(actual.position,expected.position)
	var health_equal: bool=health_shape and normalized_equal(actual.health,expected.health)
	var stamina_equal: bool=stamina_shape and normalized_equal(actual.stamina,expected.stamina)
	var scene_equal: bool=actual.scene_id is String and expected.scene_id is String and actual.scene_id==expected.scene_id
	var inventory_equal: bool=actual.inventory_sha256==expected.inventory_sha256
	report["boundary_types"]={"actual":boundary_types(actual),"expected":boundary_types(expected)}
	report["boundary_predicates"]={"position_shape":position_shape,"health_shape":health_shape,"stamina_shape":stamina_shape,"position_equal":position_equal,"scene_equal":scene_equal,"health_equal":health_equal,"stamina_equal":stamina_equal,"inventory_equal":inventory_equal,"raw_position_equal":actual.position==expected.position,"raw_health_equal":actual.health==expected.health,"raw_stamina_equal":actual.stamina==expected.stamina}
	check(position_shape,"actual and receipt positions are two finite safe integers, never bool")
	check(health_shape,"actual and receipt health have exact finite integer current/max and valid bounds")
	check(stamina_shape,"actual and receipt stamina have exact finite integer current/max and valid bounds")
	check(position_equal,"actual player position exactly matches after validated JSON integer normalization")
	check(scene_equal,"actual player scene exactly matches")
	check(health_equal,"actual health exactly matches after validated JSON integer normalization")
	check(stamina_equal,"actual stamina exactly matches after validated JSON integer normalization")
	check(inventory_equal,"complete inventory/resource digest exactly matches")
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

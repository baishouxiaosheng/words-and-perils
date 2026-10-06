extends "res://tests/test_view_facade.gd"
## AUTHORED ONLY. Run exclusively in an admitted, disposable FullMain composition.
## This inherits the existing SceneTree and offline reply builders; it never
## constructs another SceneTree, substitutes an Engine, edits world facts or RNG.
## Use the approved isolated FullMain process/resource guard described in README.md.
const OldEnemy = preload("res://view/generated_v3_enemy/adapter.gd")
const OfflineTransport = preload("res://tests/ai_gm_http/mock_transport.gd")
const NativeSupport = preload("res://view/actor_action_entry/moving_support.gd")
const ActorPolicy = preload("res://view/actor_action_profile_v2/policy.gd")
const EXPECTED_MAIN_SHA = "bb15728f636f5d22a0d2f54b026468933246d073dfee59998fa78e2e54f3fa84"
const EXPECTED_AUTHORITY_SHA = "084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e"
const PRIVATE_ROOT_ENV = "FOGBANK_ACTOR_FULL_TEST_ROOT"
const PUBLIC_PIN_PATH = "res://tests/actor_full_main/public_source_pins.json"
const EXPECTED_PUBLIC_PIN_SHA = "9017a2c377b14e66eac54d7a10a56ed38fb6cd69eaf34bc7d2eda548ec1ab282"
const EXPECTED_PRODUCTION_MANIFEST_SHA = "a6de3fff486df95013f47602fd743de5ed21af484b13f63ac3e9c1a9b5d2a546"
const OUT = "user://actor_full_main/"
const PLAYER = "actor_player"
const ENEMY = "actor_village_hostile"
const DRAFT = "PLAYER_DRAFT_ONLY: inspect the coast after the hostile finishes"
const SEED_PROSE = "FULL_MAIN_SIDECAR_SEED: the first observation is recorded"
const PHASES = ["awaiting_assessment", "ready_roll", "rolled", "staged"]
const LEGACY_FILES = ["savegame.json", "generated_adventure_v1.json", "generated_v3_village_enemy_v1.json", "generated_v3_village_equipment_v1.json", "actor_actions_v1.json"]
const BRIDGE_FILES = ["main.gd", "main.tscn", "view/actor_action_entry/view_adapter.gd", "view/actor_action_entry/render_source.gd", "view/actor_action_entry/panel.gd", "view/actor_action_entry/board.gd", "view/actor_action_entry/moving_support.gd", "view/actor_action_entry/item_view.gd", "view/actor_action_entry/runtime/actor_scope.gd", "view/actor_status_entry_v1/runtime/controller.gd", "view/actor_status_entry_v1/runtime/client.gd", "view/actor_status_entry_v1/runtime/status_scope.gd", "view/actor_status_entry_v1/runtime/intention_codec.gd", "view/dual_api_settings/actor_controller.gd", "view/dual_api_settings/actor_client.gd", "view/dual_api_settings/client.gd", "view/dual_api_settings/controller.gd", "view/dual_api_settings/panel.gd", "view/dual_api_settings/provider_presets.gd", "view/ui_typography/style.gd", "view/runtime_ai/controller.gd", "view/runtime_ai/connection_panel.gd", "core/ai_gm_http/client.gd", "core/ai_gm_http/openai_chat_codec.gd", "tests/test_view_facade.gd", "tests/ai_gm_http/mock_transport.gd"]

# Explicit test-only failure at the production renderer's result boundary.
# Normal frames, support fitting, motion and receipt effects use the real board.
# This does NOT establish a naturally unsupported destination or change terrain.
class SupportFaultBoard:
	extends "res://view/actor_action_entry/board.gd"
	var reject_animated_refresh := ""
	var injected_failures := 0
	func set_world(state: Dictionary, animate_changes: bool = false, effects: Array = []) -> void:
		if animate_changes and not reject_animated_refresh.is_empty():
			injected_failures += 1
			load_error = "FULL_MAIN_TEST_INJECTED_" + reject_animated_refresh
			return
		super.set_world(state, animate_changes, effects)

var app
var offline: Node
var gate := ""
var case_name := ""
var started_ms := 0
var rows: Array = []
var captures: Array = []
var samples: Array = []
var checkpoint_names: Array = []
var baseline_legacy: Dictionary = {}
var safety_ready := false
var action_count := 0
var source_content_hash := ""
var boot_readiness: Dictionary = {}
var source_pin_evidence: Dictionary = {}

func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("ACTOR_FULL_MAIN_FAIL ", label)
	return value

func option(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.substr(name.length() + 3)
	return ""

func run() -> void:
	started_ms = Time.get_ticks_msec()
	gate = option("gate")
	case_name = option("case")
	if not admission(): report(); return
	await boot_main()
	if not failures.is_empty(): report(); return
	match gate:
		"flow": await flow_gate()
		"interruptions": await interruption_gate()
		"display": await display_gate()
		"continue": await continue_gate()
	if is_instance_valid(app):
		expect(app.runtime_ai.client.provider_info().get("live", true) == false, "only the explicitly installed offline transport remains attached")
		for filename in LEGACY_FILES:
			expect(file_signature("user://" + filename) == baseline_legacy[filename], "legacy save untouched: " + filename)
		memory_sample("finished")
	report()

func admission() -> bool:
	if not expect(gate in ["flow", "interruptions", "display", "continue"], "one explicit bounded --gate is required"): return false
	if gate == "display" and not expect(case_name in ["movement", "death-enemy", "death-player"], "display runs exactly one explicit --case"): return false
	if gate == "continue" and not expect(valid_checkpoint_case(case_name), "continue names one produced actor/phase checkpoint"): return false
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var xdg: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var supplied_root: String = OS.get_environment(PRIVATE_ROOT_ENV).replace("\\", "/").trim_suffix("/")
	var private_root: String = supplied_root.simplify_path()
	# The original guard must directly own this same Godot process and inherited XDG.
	if not expect(not supplied_root.is_empty() and supplied_root.is_absolute_path() and supplied_root == private_root and private_root != "/" and DirAccess.dir_exists_absolute(private_root), "explicit normalized absolute private QA root already exists"): return false
	if not expect(xdg.is_absolute_path() and user_path.is_absolute_path() and user_path.begins_with(private_root + "/") and xdg.begins_with(private_root + "/") and user_path.begins_with(xdg + "/"), "user:// and inherited XDG_DATA_HOME are inside the exact private QA root"): return false
	if gate == "flow" and not expect(not DirAccess.dir_exists_absolute(OUT), "flow uses a fresh private session and never overwrites earlier checkpoints"): return false
	if not expect(DisplayServer.get_name() != "headless", "FullMain visual gate requires the separately admitted native renderer"): return false
	if not expect(FileAccess.get_sha256("res://main.gd") == EXPECTED_MAIN_SHA, "exact reviewed production Main, never canonical/another revision"): return false
	if not expect(Source.profile_digest() == EXPECTED_AUTHORITY_SHA, "actor-v2 authority matches independently frozen public source identity"): return false
	if not verify_public_source_pins(): return false
	if not expect(DirAccess.make_dir_recursive_absolute(OUT) == OK, "private evidence directory exists"): return false
	safety_ready = true
	for filename in LEGACY_FILES: baseline_legacy[filename] = file_signature("user://" + filename)
	return true

func verify_public_source_pins() -> bool:
	if not expect(file_signature(PUBLIC_PIN_PATH) == EXPECTED_PUBLIC_PIN_SHA, "exact independently frozen public source pinset"): return false
	var pins: Dictionary = read_json(PUBLIC_PIN_PATH)
	if not expect(pins.get("status") == "PUBLIC_EFFECTIVE_SOURCES_VERIFIED" and pins.get("production_manifest_sha256") == EXPECTED_PRODUCTION_MANIFEST_SHA and pins.get("files") is Dictionary, "public production and effective-base source identities are bound"): return false
	for path in pins.files:
		if not expect(file_signature("res://" + path) == pins.files[path], "exact public production/test source: " + path): return false
	source_pin_evidence = {"source_pins_sha256": EXPECTED_PUBLIC_PIN_SHA, "production_manifest_sha256": EXPECTED_PRODUCTION_MANIFEST_SHA, "verified_file_count": pins.files.size(), "effective_base_binding": pins.effective_base_binding}
	return true

func valid_checkpoint_case(value: String) -> bool:
	for actor in ["player", "enemy"]:
		for phase in PHASES:
			if value == actor + "_" + phase: return true
	return false

func boot_main() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://main.tscn")
	if not expect(scene != null, "actual canonical Main scene loads"): return
	var startup_capture_path: String = "res://artifacts/first_board.png"
	var startup_capture_before: int = FileAccess.get_modified_time(startup_capture_path) if FileAccess.file_exists(startup_capture_path) else 0
	app = scene.instantiate()
	app.startup_legacy = true
	root.add_child(app)
	await frames(3)
	if not expect(app.get_script().resource_path == "res://main.gd", "actual Main instance, not a mock/subclass controller"): return
	offline = OfflineTransport.new()
	var installed: Dictionary = app.runtime_ai.set_transport(offline)
	if not expect(installed.get("ok", false) and app.runtime_ai.client._transport == offline and offline.info().get("live", true) == false, "replace unconfigured HTTP transport with explicit no-network fixture"): return
	app.runtime_ai.connection_enabled = false
	app.runtime_ai.automatic_assessment = false
	app.runtime_ai.automatic_narration = false
	expect(not app.runtime_ai.client.configured() and not app.runtime_ai.busy(), "no provider configuration or request inherited at boot")
	await frames(2)
	if not await wait_startup_capture(startup_capture_before): return
	memory_sample("main_ready")

func wait_startup_capture(previous_modified: int) -> bool:
	var startup_capture_path: String = "res://artifacts/first_board.png"
	# Observe Main's existing one-second startup capture to completion. Do not
	# create another timer, flush/free unrelated objects or alter production code.
	var startup_wait_started: int = Time.get_ticks_msec()
	var startup_deadline: int = startup_wait_started + 8000
	var startup_capture_after: int = FileAccess.get_modified_time(startup_capture_path) if FileAccess.file_exists(startup_capture_path) else 0
	while startup_capture_after == previous_modified and Time.get_ticks_msec() < startup_deadline:
		await process_frame
		startup_capture_after = FileAccess.get_modified_time(startup_capture_path) if FileAccess.file_exists(startup_capture_path) else 0
	boot_readiness = {"path": startup_capture_path, "mtime_before_instantiation": previous_modified, "mtime_after_existing_main_capture": startup_capture_after, "waited_ms": Time.get_ticks_msec() - startup_wait_started, "bounded_wait_ms": 8000, "fresh_artifact": startup_capture_after != previous_modified and startup_capture_after > 0}
	return expect(boot_readiness.fresh_artifact, "Main-owned startup capture completed with a fresh artifact before action tests")

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func motion_finished() -> bool:
	var deadline: int = Time.get_ticks_msec() + 8000
	while is_instance_valid(app) and is_instance_valid(app.board.presentation):
		var moving := false
		for actor in app.board.presentation.actors.values():
			if actor.get("moving", false): moving = true
		if not moving: await frames(); return true
		if Time.get_ticks_msec() >= deadline: return expect(false, "real receipt motion completed within its bounded observation window")
		await process_frame
	return expect(false, "actual presentation remains available")

func screenshot(label: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var path: String = OUT + gate + "_" + case_name + "_" + label + ".png"
	var captured: Image = root.get_texture().get_image()
	if expect(captured != null and captured.get_size() == root.size, "native screenshot size: " + label):
		expect(captured.save_png(path) == OK, "write private screenshot: " + label)
		captures.append({"path": path, "label": label, "visual_review": "pending"})

func file_signature(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"

func write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not expect(file != null, "open private evidence " + path): return false
	file.store_string(C.bytes(value)); file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return expect(ok, "write complete private evidence " + path)

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var value: Variant = JSON.parse_string(file.get_as_text()); file.close()
	return value if value is Dictionary else {}

func copy_private_file(from: String, to: String) -> bool:
	# Only isolated user:// fixtures are copied; never assets, real saves or source.
	if not expect(safety_ready and from.begins_with("user://") and to.begins_with("user://"), "copy stays in isolated user://"): return false
	var input: FileAccess = FileAccess.open(from, FileAccess.READ)
	if not expect(input != null and input.get_length() <= 24 * 1024 * 1024, "bounded checkpoint input " + from): return false
	var bytes: PackedByteArray = input.get_buffer(input.get_length()); input.close()
	var output: FileAccess = FileAccess.open(to, FileAccess.WRITE)
	if not expect(output != null, "private checkpoint destination " + to): return false
	output.store_buffer(bytes); output.flush()
	var ok: bool = output.get_error() == OK; output.close()
	return expect(ok and file_signature(from) == file_signature(to), "byte-exact private checkpoint copy")

func save_checkpoint(name: String) -> bool:
	app.save_game()
	if not expect(app.last_save_result.get("ok", false) and app.last_save_result.get("narration_log_saved", false), "Main saves authority and optional sidecar at " + name): return false
	var directory: String = OUT + "checkpoints/" + name + "/"
	if not expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "checkpoint subdirectory " + name): return false
	var destination: String = directory + "actor_actions_v2.json"
	if not copy_private_file(View.SAVE_PATH, destination): return false
	if not copy_private_file(View.SAVE_PATH + ".narration.json", destination + ".narration.json"): return false
	var pending: Dictionary = app.playtest.action_copy()
	var manifest: Dictionary = {"name": name, "phase": app.playtest.phase(), "actor_id": pending.get("actor_id", app.playtest.current_actor_id()), "action_id": app.playtest.active_action, "goal": pending.get("goal", ""), "save_sha256": file_signature(destination), "sidecar_sha256": file_signature(destination + ".narration.json"), "source_content_hash": source_content_hash, "main_sha256": EXPECTED_MAIN_SHA, "authority_profile_digest": EXPECTED_AUTHORITY_SHA, "source_pins_sha256": EXPECTED_PUBLIC_PIN_SHA, "driver_sha256": file_signature("res://tests/test_full_main_bridge.gd"), "rng_digest": C.digest(app.playtest.engine.save_data().rng), "receipt_digest": C.digest(app.playtest.engine.save_data().receipts), "narration_entries": app.playtest.narration_entries(), "producer_pid": OS.get_process_id()}
	if not write_json(directory + "manifest.json", manifest): return false
	checkpoint_names.append(name)
	return true

func install_checkpoint(name: String, fresh_continue: bool) -> Dictionary:
	var directory: String = OUT + "checkpoints/" + name + "/"
	var manifest: Dictionary = read_json(directory + "manifest.json")
	if not expect(not manifest.is_empty() and manifest.get("main_sha256") == EXPECTED_MAIN_SHA and manifest.get("authority_profile_digest") == EXPECTED_AUTHORITY_SHA and manifest.get("source_pins_sha256") == EXPECTED_PUBLIC_PIN_SHA and manifest.get("driver_sha256") == file_signature("res://tests/test_full_main_bridge.gd"), "checkpoint manifest matches exact bridge and authority"): return {}
	var saved: String = directory + "actor_actions_v2.json"
	if not expect(file_signature(saved) == manifest.save_sha256 and file_signature(saved + ".narration.json") == manifest.sidecar_sha256, "checkpoint and sidecar hashes still match producer"): return {}
	if not copy_private_file(saved, View.SAVE_PATH) or not copy_private_file(saved + ".narration.json", View.SAVE_PATH + ".narration.json"): return {}
	source_content_hash = manifest.source_content_hash
	if fresh_continue:
		if not expect(app.actor_action_adventure == null and app.playtest == null, "fresh Main has no retained actor/adventure instance"): return {}
		app.on_tool_selected(app.ACTOR_ENTRY_CONTINUE)
	else:
		app.goal.text = DRAFT
		app.load_game()
	if not expect(app.actor_action_mode and app.playtest != null and app.playtest.ready().get("ok", false), "actual Continue/load publishes admitted actor entry"): return {}
	if not expect(C.bytes(app.playtest.save_data()).sha256_text() == manifest.save_sha256, "Main restored byte-exact pending/receipts/RNG"): return {}
	if fresh_continue and manifest.get("actor_id") == ENEMY:
		# Seed the unrelated draft only after the real enemy host owns this editor.
		# Fresh player pending goals remain exactly as restored by production Main.
		if not expect(app.playtest.current_actor_id() == ENEMY, "fresh enemy checkpoint admits its actual actor before draft setup"): return {}
		var before_draft: String = C.bytes(app.playtest.save_data())
		var phase_before_draft: String = app.playtest.phase()
		var action_before_draft: String = app.playtest.active_action
		var ui_action_before_draft: String = app.active_action
		app.goal.text = DRAFT
		if not expect(C.bytes(app.playtest.save_data()) == before_draft and app.playtest.phase() == phase_before_draft and app.playtest.active_action == action_before_draft and app.active_action == ui_action_before_draft, "fresh enemy-host draft setup leaves authority bytes phase and action unchanged"): return {}
	return manifest

func import_ui(reply: Dictionary) -> bool:
	app.show_import()
	app.import_text.text = C.bytes(reply)
	app.import_decision()
	return expect(app.import_error_label.text.is_empty() and not app.import_dialog.visible, "real manual JSON modal accepts exact typed reply: " + str(reply.get("schema_version")))

func begin_ui(kind: String) -> String:
	var actor: String = app.playtest.current_actor_id()
	if actor == PLAYER:
		app.set_player_intent("Explicit offline FullMain player intention: " + kind)
		app.submit_button.pressed.emit()
	else:
		var draft: String = app.goal.text
		app._begin_required_enemy_turn()
		if not expect(app.playtest.decision_pending() and app.playtest.phase() == "idle", "Main prepares proposal without fabricating a pending assessment"): return ""
		if not import_ui(proposal(app.playtest.request(), "Explicit offline FullMain hostile intention: " + kind)): return ""
		expect(app.goal.text == draft, "accepted hostile proposal preserves exact player draft")
	if not expect(app.playtest.phase() == "awaiting_assessment" and app.playtest.action_copy().actor_id == actor, "Main begins ordinary pending action for exact actor"): return ""
	return app.playtest.active_action

func ui_action(kind: String, extra: Dictionary = {}, capture_prefix: String = "", permit_display_failure: bool = false) -> Dictionary:
	if not expect(Time.get_ticks_msec() - started_ms < 105000, "suite has time left under external 120-second ceiling"): return {}
	var before: Dictionary = app.playtest.state_copy()
	var journal_count: int = app.playtest.core.journal.size()
	var effects_before: int = app.board.committed_effects.accepted_receipts
	var draft: String = app.goal.text
	var id: String = begin_ui(kind)
	if id.is_empty(): return {}
	var actor: String = app.playtest.action_copy().actor_id
	var reply: Dictionary = assessment(app.playtest.request(), kind, extra)
	if capture_prefix.is_empty():
		# Normal production path: accepted assessment calls complete_requested_turn.
		if not import_ui(reply): return {}
	else:
		# TEST OBSERVATION ONLY: pause Main's existing convenience auto-advance.
		# No Engine phase, world fact, die, resolver or scheduler state is modified.
		app.end_turn_requested = false
		if not save_checkpoint(capture_prefix + "_awaiting_assessment"): return {}
		if not import_ui(reply): return {}
		if not expect(app.playtest.phase() == "ready_roll", "manual ordinary assessment leaves debug ready_roll"): return {}
		if not save_checkpoint(capture_prefix + "_ready_roll"): return {}
		for phase in ["rolled", "staged"]:
			app.roll_button.pressed.emit()
			if not expect(app.playtest.phase() == phase and C.bytes(app.playtest.state_copy()) == C.bytes(before), "same Main stage control freezes without authority mutation: " + phase): return {}
			if not save_checkpoint(capture_prefix + "_" + phase): return {}
		var staged_hash: String = app.playtest.action_copy().stage_hash
		app.roll_button.pressed.emit()
		if not expect(app.playtest.committed(id).get("stage_hash") == staged_hash, "Main commit uses exact previously staged hash"): return {}
	if not expect(app.playtest.phase() == "idle" and app.playtest.core.journal.size() == journal_count + 1, "ordinary Main path publishes one real receipt plus one authority journal entry"): return {}
	var receipt: Dictionary = app.playtest.committed(id)
	if not expect(not receipt.is_empty() and receipt.actor_id == actor and app.playtest.state_copy().turn == before.turn + 1, "one committed turn belongs to actual actor"): return {}
	var witness: Dictionary = app.playtest.core.journal.back()
	expect(witness.action_id == id and witness.actor_id == actor and witness.assessment.provenance == {"provider": "manual_offline_assessment", "live": false, "kind": "model_reply"}, "actual frozen assessment witness has exact manual provenance and actor")
	if actor == ENEMY: expect(app.goal.text == draft, "hostile assessment/roll/stage/commit never replaces player draft")
	action_count += 1
	rows.append({"action_id": id, "actor_id": actor, "kind": kind, "turn": receipt.turn, "receipt_hash": receipt.receipt_hash, "stage_hash": receipt.stage_hash, "path": "actual Main manual import and stage driver", "debug_pause": not capture_prefix.is_empty()})
	if not permit_display_failure:
		if not expect(app.actor_render_error.is_empty() and app.board.visible, "real committed authority has an accepted visible board"): return {}
		var accepted_count: int = app.board.committed_effects.accepted_receipts
		var emitted_count: int = app.board.committed_effects.emitted_effects
		expect(accepted_count == effects_before + 1, "actual Main presents the fresh committed receipt exactly once")
		var duplicate: Dictionary = app.board.present_committed_receipt(receipt, before)
		expect(not duplicate.get("presented", true) and app.board.committed_effects.accepted_receipts == accepted_count and app.board.committed_effects.emitted_effects == emitted_count, "duplicate receipt cannot replay its visual effects")
		if not await motion_finished(): return {}
	await frames()
	return receipt

func flow_gate() -> void:
	var generated: Dictionary = Generator.generate(726381, 4, "coastal_range")
	if not expect(generated.get("ok", false), "one canonical source generated for every subsequent gate"): return
	source_data = generated.source
	source_content_hash = str(source_data.content_hash)
	var old: RefCounted = OldEnemy.new(source_data)
	if not expect(old.ready().get("ok", false), "existing village-hostile source admitted"): return
	app._switch_mode_to("generated_v3_enemy", old)
	await frames()
	if not expect(app.playtest == old, "real old-mode Main factory admitted before explicit opt-in"): return
	var old_save: String = C.bytes(old.save_data())
	var goal_control: TextEdit = app.goal
	var roll_control: Button = app.roll_button
	var connection_control: Node = app.runtime_connection_panel
	var entry_index: int = app.advanced_menu.get_item_index(app.ACTOR_ENTRY_NEW)
	if not expect(entry_index >= 0 and app.advanced_menu.get_item_text(entry_index).contains("统一行动测试"), "new mode has explicit advanced-menu test entry"): return
	app.on_tool_selected(app.ACTOR_ENTRY_NEW)
	await frames()
	if not expect(app.actor_action_mode and app.playtest.profile_id() == Source.PROFILE, "actual Main menu opens independent actor v2"): return
	expect(app.goal == goal_control and app.roll_button == roll_control and app.runtime_connection_panel == connection_control, "editor/stage/connection controls are the existing HUD instances")
	expect(C.bytes(old.save_data()) == old_save and C.bytes(app.playtest.source.data) == C.bytes(old.source.data), "opt-in preserves original progress and byte-identical generated source")
	expect(C.bytes(app.playtest.state_copy().generated_world) == C.bytes(old.state_copy().generated_world), "old content/catalog/placement metadata is retained without impersonating old authority")
	expect(not app.actor_action_panel.consent.button_pressed and not app.runtime_ai.intention_consent, "visual and runtime extra-call consent both start false")
	memory_sample("same_source_actor_entry")
	await check_inventory_focus("initial carried bundle and staff")
	await screenshot("explicit_entry")
	if not failures.is_empty(): return
	var first: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex})
	if first.is_empty(): return
	var idle_before: String = C.bytes(app.playtest.save_data())
	app._on_runtime_narration(first.action_id, SEED_PROSE)
	expect(narration_display_snapshot() == {"speaker": "叙事记录 · 第%d回合" % int(first.turn), "text": SEED_PROSE, "tooltip": SEED_PROSE}, "valid latest idle receipt updates all three latest display controls")
	expect(app.playtest.phase() == "idle" and C.bytes(app.playtest.save_data()) == idle_before, "valid latest idle prose leaves authority/phase/RNG/receipts unchanged")
	var historical: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex}, "player")
	if historical.is_empty(): return
	var newer: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex})
	if newer.is_empty(): return
	var next_id: String = begin_ui("observe historical-prose isolation")
	if next_id.is_empty(): return
	app.end_turn_requested = false
	var pending_bytes: String = C.bytes(app.playtest.save_data())
	var pending_display: Dictionary = narration_display_snapshot()
	var invalid_journal: String = app.journal.get_parsed_text()
	var invalid_entries: String = C.bytes(app.playtest.narration_entries())
	var invalid_narration: String = app.playtest.narration
	app._on_runtime_narration(next_id, "UNCOMMITTED_RECEIPT_MUST_NOT_DISPLAY")
	app._on_runtime_narration("invalid_unregistered_receipt", "INVALID_RECEIPT_MUST_NOT_DISPLAY")
	expect(narration_display_snapshot() == pending_display and app.journal.get_parsed_text() == invalid_journal and C.bytes(app.playtest.narration_entries()) == invalid_entries and app.playtest.narration == invalid_narration, "invalid and uncommitted narration callbacks are inert in history and all three latest controls")
	expect(app.playtest.phase() == "awaiting_assessment" and app.playtest.active_action == next_id and C.bytes(app.playtest.save_data()) == pending_bytes, "invalid and uncommitted prose preserve actual pending/authority/RNG/receipts")
	app._on_runtime_narration(newer.action_id, "LATEST_RECEIPT_NOTE")
	expect(narration_display_snapshot() == pending_display and app.journal.get_parsed_text().count("LATEST_RECEIPT_NOTE") == 1 and app.playtest.has_recorded_narration(newer.action_id), "first narration for latest committed receipt stays in history while a newer pending action owns all three latest controls")
	expect(app.playtest.phase() == "awaiting_assessment" and app.playtest.active_action == next_id and C.bytes(app.playtest.save_data()) == pending_bytes, "latest committed prose during newer pending preserves phase/authority/RNG/receipts")
	var latest_field: String = app.playtest.narration
	app._on_runtime_narration(historical.action_id, "HISTORICAL_RECEIPT_ONLY")
	var once: String = app.journal.get_parsed_text()
	app._on_runtime_narration(historical.action_id, "HISTORICAL_RECEIPT_ONLY")
	expect(app.journal.get_parsed_text() == once and once.count("HISTORICAL_RECEIPT_ONLY") == 1 and once.contains("叙事记录 · 第%d回合" % int(historical.turn)), "older prose displays once under immutable receipt turn")
	expect(app.playtest.narration == latest_field and C.bytes(app.playtest.save_data()) == pending_bytes and app.playtest.active_action == next_id, "historical prose cannot replace latest narration or newer pending authority")
	expect(narration_display_snapshot() == pending_display, "older receipt and its duplicate cannot overwrite newer pending speaker/text/tooltip")
	var duplicate: Dictionary = app.playtest.core.commit(historical.action_id, historical.stage_hash)
	app.playtest.refresh_runtime_state(); app.sync_playtest_request()
	expect(duplicate.get("already_committed", false) and C.bytes(app.playtest.save_data()) == pending_bytes and app.playtest.active_action == next_id, "late committed receipt callback preserves newer HUD action")
	app.cancel_button.pressed.emit()
	var following: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex})
	if following.is_empty(): return
	app._on_runtime_narration(following.action_id, "NEWEST_COMMITTED_NOTE")
	latest_field = app.playtest.narration; once = app.journal.get_parsed_text()
	var committed_display: Dictionary = narration_display_snapshot()
	var committed_bytes: String = C.bytes(app.playtest.save_data())
	app._on_runtime_narration(historical.action_id, "HISTORICAL_RECEIPT_ONLY")
	expect(app.playtest.narration == latest_field and app.journal.get_parsed_text() == once, "old receipt prose cannot overwrite a later committed receipt's field")
	expect(narration_display_snapshot() == committed_display, "older receipt cannot overwrite later committed speaker/text/tooltip")
	expect(app.playtest.phase() == "idle" and app.playtest.last_action == following.action_id and C.bytes(app.playtest.save_data()) == committed_bytes, "old receipt callback after later commit preserves authority/phase/RNG/receipts")
	if not await engage_main(): return
	app.goal.text = DRAFT
	if not save_checkpoint("engagement"): return
	await screenshot("enemy_proposal")
	var enemy_receipt: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex}, "enemy")
	if enemy_receipt.is_empty(): return
	var next_player: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex})
	if next_player.is_empty(): return
	app.goal.text = DRAFT
	var next_enemy: Dictionary = await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})
	if next_enemy.is_empty(): return
	var later_idle_display: Dictionary = narration_display_snapshot()
	var later_idle_bytes: String = C.bytes(app.playtest.save_data())
	expect(not app.playtest.has_recorded_narration(enemy_receipt.action_id), "old enemy receipt has no earlier prose before late first-delivery check")
	app._on_runtime_narration(enemy_receipt.action_id, "FIRST_OLD_PROSE_AFTER_LATER_COMMIT")
	expect(narration_display_snapshot() == later_idle_display and app.journal.get_parsed_text().count("FIRST_OLD_PROSE_AFTER_LATER_COMMIT") == 1 and app.playtest.has_recorded_narration(enemy_receipt.action_id), "first old receipt narration after a later commit adds history without overwriting speaker/text/tooltip")
	expect(app.playtest.phase() == "idle" and app.playtest.last_action == next_enemy.action_id and C.bytes(app.playtest.save_data()) == later_idle_bytes, "first old prose after later commit preserves authority/phase/RNG/receipts")
	expect(offline.sent.is_empty(), "entire manual flow has zero transport sends")
	await screenshot("manual_pipeline_complete")

func narration_display_snapshot() -> Dictionary:
	return {"speaker": app.dialogue_speaker.text, "text": app.latest_dialogue.text, "tooltip": app.latest_dialogue.tooltip_text}

func engage_main() -> bool:
	var target: Array = app.playtest.core.source.base.enemy_placement_result.attack_anchor_hex
	var plan: Dictionary = app.playtest.source.navigation.plan(app.playtest.state_copy(), target, 32)
	if not expect(plan.get("ok", false) and plan.route.size() <= 33, "bounded original-source path reaches registered contact"): return false
	for index in range(1, plan.route.size()):
		if app.playtest.current_actor_id() == ENEMY: break
		var preview: Dictionary = app.playtest.movement_preview(plan.route[index])
		if not preview.get("ok", false) and app.playtest.state_copy().actors[PLAYER].stamina.current < app.playtest.state_copy().actors[PLAYER].stamina.max:
			if (await ui_action("rest")).is_empty(): return false
		if (await ui_action("move", {"target_hex": plan.route[index]})).is_empty(): return false
	return expect(app.playtest.current_actor_id() == ENEMY and app._waiting_enemy_phase(), "unchanged contact scheduling exposes actual hostile slot")

func check_inventory_focus(label: String) -> void:
	app.refresh_world(); await frames()
	var state: Dictionary = app.playtest.state_copy()
	var texts: Array = []
	for child in app.inventory_box.get_children():
		if child is Button and not child.is_queued_for_deletion(): texts.append(child.text)
	for id in ["item_coast_staff", "item_raider_blade"]:
		expect(app.playtest.item_reference(id).is_empty() and not texts.has("查看" + str(state.items[id].name)), label + ": unsupported weapon has no focus reference or misleading view button: " + id)
	var reference: Dictionary = app.playtest.item_reference("item_travel_bundle")
	expect(not reference.is_empty() and reference.world_id == state.world_id, label + ": supported bundle keeps exact source/world reference")
	var before: String = C.bytes(app.playtest.save_data())
	app.select_generated_item("item_travel_bundle")
	expect(app.selected_focus.get("id") == "item_travel_bundle" and C.bytes(app.playtest.save_data()) == before, label + ": real supported item focus is read-only")
	app.focus_details_dialog.hide(); app.clear_target()

func configure_offline_runtime() -> bool:
	# Use the current dual-role modal and its real save signal, never the hidden
	# old one-config controls or a direct client configuration shortcut.
	var panel = app.runtime_connection_panel
	var sent_before: int = offline.sent.size()
	var applied_results: Array = []
	if not expect(app.runtime_ai.client._transport == offline and offline.info().get("live", true) == false, "actual modal configuration is guarded by the exact no-network mock"): return false
	panel.automatic_assessment_input.button_pressed = false
	panel.automatic_narration_input.button_pressed = false
	if not expect(not panel.settings_button.disabled and panel.settings_button.pressed.is_connected(panel.open_settings), "actual API settings control is enabled and connected to its production opener"): return false
	panel.settings_button.pressed.emit()
	await frames(2)
	if not expect(panel.settings_dialog.visible and app._api_settings_open(), "real dual-role API modal owns input during editing"): return false
	for role in ["decision", "narration"]:
		var fields: Dictionary = panel.role_fields[role]
		fields.preset.select(0); fields.preset.item_selected.emit(0)
		var custom_index: int = -1
		for index in range(fields.model_choice.item_count):
			if str(fields.model_choice.get_item_metadata(index)).is_empty(): custom_index = index; break
		if not expect(custom_index >= 0, "actual modal has its custom model choice for " + role): return false
		fields.model_choice.select(custom_index); fields.model_choice.item_selected.emit(custom_index)
		if not expect(fields.model.editable, "explicit custom model choice permits input for " + role): return false
		fields.endpoint.text = "https://offline.invalid/v1/chat/completions"
		fields.model.text = "full-main-offline-fixture"
		fields.model.text_changed.emit(fields.model.text)
		fields.reasoning.text = ""
		fields.key.text = "full_main_offline_fixture_only_" + role
		fields.timeout.value = 30.0
		fields.local.button_pressed = false
		fields.budget.text = "65536"
		fields.token_parameter.select(0)
		fields.json_mode.button_pressed = false
	panel.enable_input.button_pressed = true
	if not expect(not panel.settings_dialog.get_ok_button().disabled and panel.settings_dialog.confirmed.is_connected(panel._save_settings), "real modal Save control is enabled and connected to its production handler"): return false
	panel.configuration_applied.connect(func(result: Dictionary): applied_results.append(result.duplicate(true)), CONNECT_ONE_SHOT)
	panel.settings_dialog.confirmed.emit()
	if not expect(applied_results.size() == 1 and applied_results[0].get("ok", false), "existing client configured exclusively against no-network mock"): return false
	await frames(2)
	if not expect(not panel.settings_dialog.visible and not app._api_settings_open(), "actual Save closes the modal and restores Main input before action tests"): return false
	if not expect(panel.consent_input.button_pressed and not panel._dirty and app.runtime_ai.client.configured() and app.runtime_ai.connection_enabled, "actual global consent and Apply establish configured enabled runtime"): return false
	for role in ["decision", "narration"]:
		if not expect(panel.role_fields[role].key.text.is_empty() and offline.sent.size() == sent_before, "actual Apply clears visible fixture credential and sends no request: " + role): return false
		var applied_config: Dictionary = app.runtime_ai.client.role_configuration(role)
		if not expect(applied_config.get("model") == "full-main-offline-fixture" and applied_config.get("public_request_budget_bytes") == 65536 and is_equal_approx(float(applied_config.get("timeout_seconds", 0.0)), 30.0), "actual applied model budget and timeout preserve original offline fixture scope: " + role): return false
		if not expect(applied_config.get("service_preset") == "custom" and applied_config.get("endpoint") == "https://offline.invalid/v1/chat/completions", "both roles retain the explicitly selected custom fixture endpoint: " + role): return false
	if not expect(not panel.automatic_assessment_input.button_pressed and not panel.automatic_narration_input.button_pressed and not app.runtime_ai.automatic_assessment and not app.runtime_ai.automatic_narration, "actual automatic request controls remain off"): return false
	return expect(app.runtime_ai.client._transport == offline and not app.runtime_ai.client.provider_info().live, "actual transport explicitly reports live=false")

func wire_request() -> Dictionary:
	var body: Dictionary = JSON.parse_string(offline.sent.back().body)
	return JSON.parse_string(body.messages[1].content)

func envelope(reply: Dictionary) -> String:
	return C.bytes({"choices": [{"finish_reason": "stop", "message": {"content": C.bytes(reply)}}]})

func assert_consent_reset(label: String) -> void:
	expect(not app.actor_action_panel.consent.button_pressed and not app.runtime_ai.intention_consent, label + ": visible checkbox and runtime consent both false")
	app.actor_action_panel.consent.button_pressed = true
	expect(app.runtime_ai.intention_consent, label + ": one explicit checkbox re-check restores runtime consent")
	app.actor_action_panel.consent.button_pressed = false

func interruption_gate() -> void:
	if install_checkpoint("engagement", true).is_empty(): return
	await frames()
	app._prepare_actor_decision()
	var grant: Dictionary = app.playtest.request()
	if not expect(grant.get("schema_version") == "actor_intent_proposal/v1" and not grant.has("phase") and not grant.has("action_id"), "phase-less proposal stays a proposal in the actual HUD"): return
	app.export_request()
	expect(app.file_dialog.current_file == "actor_actions_v2_intent_request.json", "proposal dialog chooses dedicated namespace without a phase field")
	var exported: String = OUT + "actor_actions_v2_intent_request.json"
	app.on_file_selected(exported); app.file_dialog.hide()
	expect(C.bytes(read_json(exported)) == C.bytes(grant), "actual file dialog callback exports exact public proposal")
	var protected_signature: String = file_signature(View.SAVE_PATH)
	app.export_request(); app.on_file_selected(View.SAVE_PATH); app.file_dialog.hide()
	expect(file_signature(View.SAVE_PATH) == protected_signature, "proposal cannot overwrite authority save namespace")
	var stale_dir: String = OUT + "stale_cancel/"
	expect(DirAccess.make_dir_recursive_absolute(stale_dir) == OK, "stale cancellation output directory")
	var stale_path: String = stale_dir + "actor_actions_v2_intent_request.json"
	var stale_signature: String = file_signature(stale_path)
	app.export_request(); app.cancel_button.pressed.emit(); app.on_file_selected(stale_path); app.file_dialog.hide()
	expect(file_signature(stale_path) == stale_signature, "cancelled grant cannot be exported by its still-open modal")
	app._prepare_actor_decision(); grant = app.playtest.request()
	app.show_import(); app._invalidate_mode_dialogs(); app.import_text.text = C.bytes(proposal(grant, "Stale modal must not act"))
	var before: String = C.bytes(app.playtest.save_data())
	app.import_decision(); app._on_import_file_selected(exported)
	expect(C.bytes(app.playtest.save_data()) == before and app.playtest.phase() == "idle", "stale import and import-file callbacks cannot create action after mode epoch invalidation")
	app.export_request(); app._invalidate_mode_dialogs(); app.on_file_selected(stale_path)
	expect(file_signature(stale_path) == stale_signature, "stale export mode epoch cannot write")
	if not await configure_offline_runtime(): return
	app.actor_action_panel.consent.button_pressed = true
	app.actor_action_panel.decision_button.pressed.emit()
	if not expect(offline.sent.size() == 1 and app.runtime_ai.busy(), "actual consent and request controls start one offline proposal"): return
	var request: Dictionary = wire_request()
	var token: int = offline.sent.back().request_id
	before = C.bytes(app.playtest.save_data())
	app.cancel_button.pressed.emit()
	offline.respond(token, envelope(proposal(request, "Late cancelled hostile candidate")))
	expect(C.bytes(app.playtest.save_data()) == before and app.playtest.phase() == "idle" and not app.runtime_ai.busy() and not app.playtest.decision_pending(), "cancel plus late proposal spends no resources and preserves hostile slot")
	app._prepare_actor_decision(); app.actor_action_panel.decision_button.pressed.emit()
	request = wire_request(); token = offline.sent.back().request_id
	if not import_ui(proposal(request, "Manual hostile observation wins HTTP ownership")): return
	app.end_turn_requested = false
	before = C.bytes(app.playtest.save_data())
	offline.respond(token, envelope(proposal(request, "Late provider candidate loses")))
	expect(C.bytes(app.playtest.save_data()) == before and app.goal.text == DRAFT, "manual proposal retires old transport without overwriting draft")
	if not expect(app.runtime_ai.request_assessment().get("ok", false), "same client starts separate ordinary offline assessment"): return
	request = wire_request(); token = offline.sent.back().request_id
	var reply: Dictionary = assessment(request, "observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})
	app.export_request()
	expect(app.file_dialog.current_file == "actor_actions_v2_request.json", "ordinary assessment uses separate request namespace")
	app.file_dialog.hide()
	if not import_ui(reply): return
	before = C.bytes(app.playtest.save_data())
	reply.provenance.provider = "mock_test_transport"
	offline.respond(token, envelope(reply)); offline.respond(token, envelope(reply))
	expect(app.playtest.phase() == "ready_roll" and C.bytes(app.playtest.save_data()) == before, "late/duplicate assessment cannot consume manual ownership or advance numerical action")
	app.actor_action_panel.consent.button_pressed = true
	app.save_game(); before = C.bytes(app.playtest.save_data()); app.load_game()
	expect(app.last_load_result.get("ok", false) and C.bytes(app.playtest.save_data()) == before and app.goal.text == DRAFT, "Main pending load restores exact hostile action and keeps unrelated player draft")
	assert_consent_reset("load")
	app.cancel_button.pressed.emit()
	app.actor_action_panel.consent.button_pressed = true
	app.reset_playtest(); await frames()
	expect(app.playtest.state_copy().turn == 0 and str(app.playtest.source.data.content_hash) == source_content_hash, "Main reset restores same source start without migration")
	assert_consent_reset("reset")
	app.actor_action_panel.consent.button_pressed = true
	app._switch_mode("legacy"); await frames()
	app.on_tool_selected(app.ACTOR_ENTRY_CONTINUE); await frames()
	expect(app.actor_action_mode, "actual Continue returns to parked same-mode instance")
	assert_consent_reset("mode switch/return")
	await screenshot("cancel_load_reset_consent")

func continue_gate() -> void:
	var manifest: Dictionary = install_checkpoint(case_name, true)
	if manifest.is_empty(): return
	await frames(3)
	expect(manifest.producer_pid != OS.get_process_id(), "Continue is an independent native process, never same-process adapter roundtrip")
	expect(app.playtest.phase() == manifest.phase and app.playtest.active_action == manifest.action_id, "fresh Continue restores selected pending phase and action")
	expect(C.digest(app.playtest.engine.save_data().rng) == manifest.rng_digest and C.digest(app.playtest.engine.save_data().receipts) == manifest.receipt_digest, "fresh Continue neither rerolls nor creates/replays receipt")
	expect(app.end_turn_requested and app.playtest.action_copy().goal == manifest.goal, "Main restores pending goal and completion flag")
	if manifest.actor_id == PLAYER:
		expect(app.submitted_player_intent() == manifest.goal, "actual player's pending goal returns to existing editor")
	else:
		expect(app.goal.text == DRAFT and app.journal.get_parsed_text().contains(manifest.goal), "hostile pending goal is in journal while unrelated player draft remains")
	for entry in manifest.narration_entries:
		expect(app.journal.get_parsed_text().count(str(entry.narration)) == 1 and app.playtest.has_recorded_narration(entry.action_id), "receipt sidecar restored once: " + str(entry.action_id))
	expect(app.journal.get_parsed_text().contains(SEED_PROSE) and app.playtest.narration_log_status == "loaded", "fresh Continue loaded original bound sidecar")
	expect(not app.playtest.decision_pending() and not app.runtime_ai.busy(), "proposal grants and network ownership do not persist")
	expect(not app.actor_action_panel.consent.button_pressed and not app.runtime_ai.intention_consent, "fresh Continue visually clears extra-call consent")
	expect(app.board.committed_effects.accepted_receipts == 0 and app.board.committed_effects.emitted_effects == 0, "saved historical receipts are display baseline, not replayed effects")
	expect(C.bytes(app.playtest.save_data()).sha256_text() == manifest.save_sha256 and offline.sent.is_empty(), "rendering and sidecar restore leave pending authority unchanged with no sends")
	await screenshot("fresh_pending")

func supported_enemy_destination() -> Array:
	var before: Dictionary = app.playtest.state_copy()
	for cell in app.playtest.public_facts().hexes.values():
		var target: Array = [cell.q, cell.r]
		var preview: Dictionary = app.playtest.movement_preview(target)
		if not preview.get("ok", false) or preview.route.size() != 2: continue
		# Detached READ-ONLY geometry probe, never published/saved as authority.
		var projected: Dictionary = before.duplicate(true)
		projected.actors[ENEMY].hex = target.duplicate(); projected.combat_turn.phase = "player"
		var fit: Dictionary = NativeSupport.fit(app.playtest.source, projected)
		var route: Dictionary = NativeSupport.route(app.playtest.source, before, projected, [{"type": "actor_move", "actor_id": ENEMY, "hex": target}])
		if fit.get("ok", false) and route.get("ok", false): return target
	return []

func install_failure_board() -> bool:
	var source: RefCounted = app.playtest.source
	# Free old native board first: no simultaneous duplicate rendered world.
	app.viewport.remove_child(app.board); app.board.free()
	var fault = SupportFaultBoard.new(source)
	app.board = fault; fault.attention_ui_mode = true
	app.viewport.add_child(fault)
	fault.focus_candidates.connect(app.on_focus_candidates)
	fault.hex_hovered.connect(app.on_hex_hovered)
	app.refresh_world(); fault.focus_player()
	return expect(app.actor_render_error.is_empty() and fault.visible, "test-only fault seam starts from real admitted native board")

func display_gate() -> void:
	if install_checkpoint("engagement", true).is_empty(): return
	await frames()
	if case_name.begins_with("death-"):
		await death_case(ENEMY if case_name == "death-enemy" else PLAYER)
		return
	var before: Dictionary = app.playtest.state_copy()
	var saved: String = C.bytes(app.playtest.save_data())
	var target: Array = supported_enemy_destination()
	if not expect(not target.is_empty() and C.bytes(app.playtest.save_data()) == saved, "native support selection is read-only and finds one actual legal destination"): return
	app.goal.text = DRAFT
	var moved: Dictionary = await ui_action("move", {"target_hex": target})
	if moved.is_empty(): return
	var actual: Dictionary = app.playtest.state_copy()
	var fit: Dictionary = NativeSupport.fit(app.playtest.source, actual)
	expect(actual.actors[ENEMY].hex == target and target != before.actors[ENEMY].hex and app.board.world_state.actors[ENEMY].hex == target, "actual committed enemy position reaches real board without reset to spawn")
	expect(fit.get("ok", false) and fit.scale == 1.0 and NativeSupport.route(app.playtest.source, before, actual, moved.patches).get("ok", false), "real committed destination and swept route retain original full-size support")
	expect(app.board.token_nodes[ENEMY].global_position.distance_to(fit.position) < 0.005, "actual native enemy token reaches fitted committed position")
	await screenshot("enemy_moved_full_size")
	# Reuse original source/checkpoint for reproducible independent display faults.
	if install_checkpoint("engagement", false).is_empty(): return
	await frames()
	if not install_failure_board(): return
	for fault_kind in ["SUPPORT", "ROUTE"]:
		if fault_kind == "ROUTE":
			if install_checkpoint("engagement", false).is_empty(): return
		before = app.playtest.state_copy()
		target = supported_enemy_destination()
		if not expect(not target.is_empty(), "legal ordinary move available before injected " + fault_kind): return
		var accepted_before: int = app.board.committed_effects.accepted_receipts
		var sent_before: int = offline.sent.size()
		app.actor_action_panel.consent.button_pressed = true
		app.board.reject_animated_refresh = fault_kind
		var committed: Dictionary = await ui_action("move", {"target_hex": target}, "", true)
		if committed.is_empty(): return
		var committed_bytes: String = C.bytes(app.playtest.save_data())
		expect(app.playtest.state_copy().actors[ENEMY].hex == target and app.playtest.state_copy().turn == before.turn + 1, "injected display rejection preserves real committed movement, no rollback")
		expect(app.actor_render_suspended and not app.actor_render_error.is_empty() and not app.board.visible and not app.board.is_processing_input(), "display rejection latches, hides board and disables board input")
		expect(app.submit_button.disabled and app.roll_button.disabled and app.runtime_ai._adapter == null and not app._waiting_enemy_phase(), "latch blocks numerical controls and follow-on transport")
		expect(app.status_label.text.contains("支撑校验") and not app.status_label.text.contains("这一回合已完成"), "support failure remains visible instead of success banner")
		expect(not app.actor_action_panel.consent.button_pressed and not app.runtime_ai.intention_consent, "display rejection visually revokes extra-call consent")
		app.submit_playtest(); app.advance_playtest(); app._request_actor_decision()
		expect(C.bytes(app.playtest.save_data()) == committed_bytes and offline.sent.size() == sent_before and app.board.committed_effects.accepted_receipts == accepted_before, "latched direct handlers cannot commit again, send or present rejected receipt")
		await screenshot("latched_" + fault_kind.to_lower())
		app.save_game()
		if not expect(app.last_save_result.get("ok", false), "committed authority remains saveable during display rejection"): return
		app.board.reject_animated_refresh = ""
		app.load_game(); await frames()
		expect(app.last_load_result.get("ok", false) and C.bytes(app.playtest.save_data()) == committed_bytes, "same-source real load recovers exact already-committed authority")
		expect(app.actor_render_error.is_empty() and not app.actor_render_suspended and app.board.visible and app.board.is_processing_input() and app.runtime_ai._adapter == app.playtest, "successful original support checks clear latch and explicitly rebind runtime")
		assert_consent_reset("display recovery " + fault_kind)
		expect(app.board.committed_effects.accepted_receipts == accepted_before, "recovery never replays rejected receipt effect")
	# Actual item custody actions, not fabricated renderer states.
	if install_checkpoint("engagement", false).is_empty(): return
	if (await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})).is_empty(): return
	if (await ui_action("drop_item", {"item_id": "item_coast_staff"})).is_empty(): return
	await check_inventory_focus("grounded unsupported staff")
	if (await ui_action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})).is_empty(): return
	if (await ui_action("drop_item", {"item_id": "item_travel_bundle"})).is_empty(): return
	await check_inventory_focus("grounded supported bundle")
	if (await ui_action("pickup_item", {"item_id": "item_travel_bundle"})).is_empty(): return
	expect(app.playtest.state_copy().items.item_travel_bundle.owner_actor_id == ENEMY, "real enemy pickup retains dynamic owner identity")
	await check_inventory_focus("enemy-carried supported bundle")
	await screenshot("dynamic_item_owner")

func death_case(victim: String) -> void:
	var attacker: String = PLAYER if victim == ENEMY else ENEMY
	var first: Dictionary = app.playtest.state_copy()
	var occupied_hex: Array = first.actors[victim].hex.duplicate()
	var enemy_bounds: AABB = app.board.enemy_body_bounds
	var attempts := 0
	while app.playtest.state_copy().actors[victim].health.current > 0 and attempts < 32:
		attempts += 1
		var state: Dictionary = app.playtest.state_copy()
		var actor: String = app.playtest.current_actor_id()
		var kind := "observe"
		var extra: Dictionary = {"target_hex": state.actors[actor].hex}
		if actor == attacker:
			var weapon: String = str(state.actors[actor].equipment.weapon)
			if int(state.actors[actor].stamina.current) < int(state.items[weapon].weapon_profile.stamina_cost):
				kind = "rest"; extra = {}
			else:
				kind = "basic_attack"; extra = {"target_actor_id": victim, "weapon_item_id": weapon}
		# No HP/status injection, forced die, fixed outcome or synthetic receipt.
		if (await ui_action(kind, extra)).is_empty(): return
	var state: Dictionary = app.playtest.state_copy()
	if not expect(state.actors[victim].health.current == 0, "bounded legitimate ordinary encounter reaches actual death: " + victim): return
	expect(state.actors[victim].hex == occupied_hex and ActorPolicy.occupied(state, occupied_hex, attacker), "downed actor preserves authoritative occupied cell")
	expect(not app.playtest.movement_preview(occupied_hex).get("ok", false), "downed occupied cell remains an illegal move destination")
	expect(app.board.token_nodes.has(victim) and is_instance_valid(app.board.token_nodes[victim]), "downed actor stays on real board")
	var token: Node3D = app.board.token_nodes[victim]
	expect(is_equal_approx(token.scale.x, 1.0) and is_equal_approx(token.scale.z, 1.0) and is_equal_approx(token.scale.y, 0.38), "existing downed display keeps full horizontal token footprint")
	var plate: Label3D = token.get_node_or_null("Nameplate") as Label3D
	expect(plate != null and plate.text.contains("已倒下"), "downed actor is labelled in existing native token")
	if victim == ENEMY:
		expect(app.board.enemy_body_bounds == enemy_bounds and app.board.enemy_pose.get("downed_occupied", false), "downed enemy retains original dynamic body exclusion")
		expect(not app.playtest.enemy_response_available(), "downed enemy receives no fabricated next slot")
	else:
		expect(app.submit_button.disabled and not app.goal.editable and app.phase_label.text.contains("倒下"), "dead player's actual HUD disables further deliberate action")
	app.save_game()
	expect(app.last_save_result.get("ok", false), "real combat-death history remains persistable")
	await screenshot("actual_" + victim + "_downed")

func memory_sample(label: String) -> void:
	var row: Dictionary = {"label": label, "pid": OS.get_process_id(), "elapsed_ms": Time.get_ticks_msec() - started_ms, "nodes": get_node_count(), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}
	var file: FileAccess = FileAccess.open("/proc/self/status", FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line: String = file.get_line()
			for field in ["VmRSS", "VmHWM"]:
				if line.begins_with(field + ":"): row[field + "_bytes"] = int(line.trim_prefix(field + ":").strip_edges().split(" ", false)[0]) * 1024
		file.close()
	var current: FileAccess = FileAccess.open("/sys/fs/cgroup/memory.current", FileAccess.READ)
	if current != null: row.cgroup_current_bytes = int(current.get_as_text()); current.close()
	samples.append(row)
	print("ACTOR_FULL_MAIN_MEMORY ", JSON.stringify(row))

func report() -> void:
	if safety_ready: verify_public_source_pins()
	var inputs: Dictionary = {}
	for path in BRIDGE_FILES: inputs[path] = file_signature("res://" + path)
	var result: Dictionary = {"schema_version": "actor_full_main_bridge_test/v1", "ok": failures.is_empty(), "gate": gate, "case": case_name, "checks": checks, "failures": failures, "pid": OS.get_process_id(), "elapsed_ms": Time.get_ticks_msec() - started_ms, "main_sha256": file_signature("res://main.gd"), "driver_sha256": file_signature("res://tests/test_full_main_bridge.gd"), "bridge_inputs": inputs, "authority_profile_digest": EXPECTED_AUTHORITY_SHA, "source_content_hash": source_content_hash, "actual_action_count": action_count, "actions": rows, "produced_checkpoints": checkpoint_names, "screenshots": captures, "memory": samples, "transport": "explicit local mock only", "network_calls": 0, "mock_sends": offline.sent.size() if is_instance_valid(offline) else 0, "visual_review": "pending; screenshot existence is not visual acceptance", "full_bridge_accepted": false}
	result["boot_readiness"] = boot_readiness
	result["public_source_identity"] = source_pin_evidence
	if safety_ready:
		var path: String = OUT + "report_" + gate + "_" + case_name + ".json"
		var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify(result, "\t")); output.flush(); output.close()
		else:
			result.ok = false; result.failures.append("cannot write private final report")
	print("ACTOR_FULL_MAIN_RESULT ", JSON.stringify(result))
	if is_instance_valid(app): app.free()
	quit(0 if result.ok else 1)

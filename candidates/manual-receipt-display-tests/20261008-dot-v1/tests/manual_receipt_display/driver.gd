extends SceneTree
## Test-only, bounded real-Main actor-v2 entry. Authored, not parsed or run.
## One source-bound contact route, one round trip, two pending imports/cancels,
## two further real observe actions, latest idle import. No fabricated receipts.
const Main = preload("res://main.tscn")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const OldEnemy = preload("res://view/generated_v3_enemy/adapter.gd")
const Source = preload("res://view/actor_action_profile_v2/source.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const Helper = preload("res://tests/manual_receipt_display/helper.gd")
const PLAYER = "actor_player"
const ENEMY = "actor_village_hostile"
const BASE_MAIN_SHA = "05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f"
const PATCHED_MAIN_SHA = "fcbe64b533f21bbd6e6b21c9c020f11f934ccee4c064078216e0f69cdcb6376b"
const AUTHORITY_SHA = "084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e"
const HELPER_SHA = "a53846c2072b1cf3a7e646cfc0924302a89c9d975af55a05cd58de03a1b43d5e"
var app
var mock
var checks: Array = []
var failures: Array = []
var actions: Array = []
var helper_results: Array = []
var finished := false
var checkpoint := "initialize"
var source_content_hash := ""
var started_ms := 0
var safety_ready := false

func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	create_timer(150.0).timeout.connect(func():
		if not finished:
			expect(false, "driver deadline at " + checkpoint)
			finish())
	run.call_deferred()

func expect(value: bool, label: String) -> bool:
	checkpoint = label
	checks.append({"label": label, "ok": value})
	if not value: failures.append(label); printerr("MANUAL_RECEIPT_DRIVER_FAIL ", label)
	return value

func frames(count: int = 2) -> void:
	for _i in count: await process_frame

func admission() -> bool:
	var private_root: String = OS.get_environment("WAP_RECEIPT_PRIVATE_ROOT").simplify_path().trim_suffix("/")
	var expected: String = OS.get_environment("WAP_RECEIPT_USER_DIR").simplify_path()
	var report: String = OS.get_environment("WAP_RECEIPT_REPORT").simplify_path()
	if not expect(not private_root.is_empty() and private_root.is_absolute_path() and private_root != "/"
		and expected.begins_with(private_root + "/") and report.begins_with(private_root + "/")
		and OS.get_user_data_dir().simplify_path() == expected, "exact isolated user directory and report destination"): return false
	if not expect(FileAccess.get_sha256("res://main.gd") == OS.get_environment("WAP_RECEIPT_MAIN_SHA")
		and OS.get_environment("WAP_RECEIPT_MAIN_SHA") in [BASE_MAIN_SHA, PATCHED_MAIN_SHA], "exact baseline or candidate Main"): return false
	if not expect(FileAccess.get_sha256("res://tests/manual_receipt_display/helper.gd") == HELPER_SHA
		and Source.profile_digest() == AUTHORITY_SHA, "unchanged published helper and frozen actor authority"): return false
	if not expect(not FileAccess.file_exists(report), "new result file, never overwrite prior evidence"): return false
	safety_ready = true
	return true

func manual(reply: Dictionary) -> bool:
	app.show_import(); app.import_text.text = C.bytes(reply); app.import_decision()
	return expect(not app.import_dialog.visible and app.import_error_label.text.is_empty(), "real Main manual JSON accepted")

func assessment(request: Dictionary, kind: String, extra: Dictionary = {}) -> Dictionary:
	# The existing public test_view_facade builder contract, reduced to the three
	# ordinary action families used here. Every value comes from this real request.
	var actor_id: String = request.context.actor_id
	var bindings: Dictionary = {"actor_id": actor_id}; bindings.merge(extra)
	var paths: Array = ["/actors/" + actor_id]
	if bindings.has("target_hex"): paths.append("/hexes/" + "%d,%d" % bindings.target_hex)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found: Dictionary = C.pointer(request.context.facts, path)
		if not found.ok: return {}
		var id := "fact_" + str(refs.size()); ids.append(id)
		refs.append({"id": id, "path": path, "expected": found.value})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id,
		"state_version": request.state_version, "context_hash": request.context_hash,
		"narration": "Explicit offline receipt-driver assessment data.", "interpretation": "Authored ordinary test intention",
		"resolver_id": "actor_" + kind + "_v2", "bindings": bindings,
		"components": [{"id": kind, "parameters": {"A": 4, "D": 0, "P": 2}, "disposition": "certain", "fact_ref_ids": ids}],
		"fact_refs": refs, "provenance": {"provider": "offline_receipt_driver", "live": false, "kind": "model_reply"}}

func proposal(grant: Dictionary, goal: String) -> Dictionary:
	var reply: Dictionary = {}
	for field in ["schema_version", "proposal_id", "actor_id", "state_version", "context_hash"]: reply[field] = grant[field]
	reply.goal = goal; reply.focus = {}
	return reply

func motion_finished() -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(app) and is_instance_valid(app.board.presentation):
		var moving := false
		for actor in app.board.presentation.actors.values():
			if actor.get("moving", false): moving = true
		if not moving: await frames(); return true
		if Time.get_ticks_msec() >= deadline: return expect(false, "real receipt motion deadline")
		await process_frame
	return expect(false, "real presentation remains available")

func action(kind: String, extra: Dictionary = {}) -> Dictionary:
	if not expect(kind in ["move", "observe", "rest"] and Time.get_ticks_msec() - started_ms < 140000,
		"bounded ordinary action only"): return {}
	var before: Dictionary = app.playtest.state_copy()
	var who: String = app.playtest.current_actor_id()
	var draft: String = app.goal.text
	var journal_count: int = app.playtest.core.journal.size()
	var effects_count: int = app.board.committed_effects.accepted_receipts
	if who == PLAYER:
		app.clear_target(); app.set_player_intent("Receipt-driver player intention: " + kind)
		app.submit_button.pressed.emit()
	else:
		if not expect(who == ENEMY, "only the existing single enemy may own the slot"): return {}
		app._begin_required_enemy_turn()
		if not expect(app.playtest.decision_pending(), "real enemy proposal grant, no scripted fallback"): return {}
		if not manual(proposal(app.playtest.request(), "Receipt-driver enemy intention: " + kind)): return {}
		if not expect(app.goal.text == draft, "enemy proposal preserves player draft"): return {}
	if not expect(app.playtest.phase() == "awaiting_assessment" and app.playtest.action_copy().actor_id == who,
		"real pending action bound to current actor"): return {}
	var id: String = app.playtest.active_action
	var reply: Dictionary = assessment(app.playtest.request(), kind, extra)
	if not expect(not reply.is_empty(), "complete references from actual request"): return {}
	if not manual(reply): return {}
	var receipt: Dictionary = app.playtest.committed(id)
	if not expect(not receipt.is_empty() and receipt.actor_id == who and app.playtest.phase() == "idle"
		and app.playtest.state_copy().turn == before.turn + 1 and app.playtest.core.journal.size() == journal_count + 1,
		"one real Engine transaction and receipt"): return {}
	if not expect(app.actor_render_error.is_empty() and app.board.visible
		and app.board.committed_effects.accepted_receipts == effects_count + 1, "source-bound receipt presentation exactly once"): return {}
	actions.append({"action_id": id, "actor_id": who, "kind": kind, "turn": receipt.turn, "receipt_hash": receipt.receipt_hash})
	if not await motion_finished(): return {}
	if not expect(mock.sent.is_empty(), "authored manual actions make zero model requests"): return {}
	return receipt

func cancel_pending_only() -> bool:
	var state: String = C.bytes(app.playtest.state_copy())
	var rng: String = C.bytes(app.playtest.engine.save_data().rng)
	var receipts: String = C.bytes(app.playtest.engine.save_data().receipts)
	app.cancel_button.pressed.emit(); await frames()
	return expect(app.playtest.phase() == "idle" and app.playtest.current_actor_id() == PLAYER
		and C.bytes(app.playtest.state_copy()) == state and C.bytes(app.playtest.engine.save_data().rng) == rng
		and C.bytes(app.playtest.engine.save_data().receipts) == receipts, "real cancellation preserves facts, RNG and committed receipts")

func add_helper_result(label: String, result: Dictionary) -> void:
	helper_results.append({"case": label, "result": result})
	for failure in result.get("failures", []): failures.append(label + ": " + str(failure))

func run() -> void:
	if not admission(): finish(); return
	root.gui_embed_subwindows = true; root.size = Vector2i(1280, 720)
	app = Main.instantiate(); root.add_child(app); current_scene = app; await frames(6)
	if not expect(app.coast_mode and app.playtest.state_copy().hexes.size() == 1801, "actual public-v30 default Main boot"): finish(); return
	mock = Mock.new()
	if not expect(app.runtime_ai.set_transport(mock).get("ok", false) and not mock.info().live, "original no-network transport installed"): finish(); return
	app.runtime_ai.connection_enabled = false; app.runtime_ai.automatic_assessment = false; app.runtime_ai.automatic_narration = false
	if not expect(not app.runtime_ai.client.configured() and not app.runtime_ai.busy(), "no configuration or credentials used"): finish(); return
	var generated: Dictionary = Generator.generate(726381, 4, "coastal_range")
	if not expect(generated.get("ok", false), "same existing canonical generated source"): finish(); return
	source_content_hash = str(generated.source.content_hash)
	var old = OldEnemy.new(generated.source)
	if not expect(old.ready().get("ok", false), "original generated-enemy source admitted"): finish(); return
	app._switch_mode_to("generated_v3_enemy", old); await frames()
	var old_save: String = C.bytes(old.save_data())
	app.on_tool_selected(app.ACTOR_ENTRY_NEW); await frames()
	if not expect(app.actor_action_mode and not app.actor_status_mode and app.playtest.profile_id() == Source.PROFILE
		and app.playtest.core.source.identity.profile_hash == AUTHORITY_SHA, "real advanced menu enters frozen actor_actions_v2"): finish(); return
	if not expect(C.bytes(old.save_data()) == old_save and C.bytes(app.playtest.source.data) == C.bytes(old.source.data), "old progress retained, byte-identical source"): finish(); return
	var anchor: Array = app.playtest.core.source.base.enemy_placement_result.attack_anchor_hex
	var plan: Dictionary = app.playtest.source.navigation.plan(app.playtest.state_copy(), anchor, 32)
	if not expect(plan.get("ok", false) and plan.route.size() <= 33, "bounded real source navigation to contact"): finish(); return
	var player_receipt: Dictionary = {}
	for index in range(1, plan.route.size()):
		if app.playtest.current_actor_id() == ENEMY: break
		var preview: Dictionary = app.playtest.movement_preview(plan.route[index])
		if not preview.get("ok", false):
			var stamina: Dictionary = app.playtest.state_copy().actors[PLAYER].stamina
			if not expect(stamina.current < stamina.max, "only legal non-full stamina rest is considered"): finish(); return
			if (await action("rest")).is_empty(): finish(); return
			preview = app.playtest.movement_preview(plan.route[index])
			if not expect(preview.get("ok", false), "movement revalidated after actual rest"): finish(); return
		player_receipt = await action("move", {"target_hex": plan.route[index]})
		if player_receipt.is_empty(): finish(); return
	if not expect(not player_receipt.is_empty() and app.playtest.current_actor_id() == ENEMY and app._waiting_enemy_phase(), "real player movement yields the single enemy slot"): finish(); return
	var enemy_receipt: Dictionary = await action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})
	if not expect(not enemy_receipt.is_empty() and app.playtest.current_actor_id() == PLAYER
		and int(enemy_receipt.turn) == int(player_receipt.turn) + 1, "authentic player -> enemy -> player round trip"): finish(); return
	add_helper_result("older-player-with-new-pending", Helper.pending_import(app, player_receipt.action_id, "MANUAL_OLDER_RECEIPT_ONLY"))
	if not await cancel_pending_only(): finish(); return
	add_helper_result("latest-enemy-with-new-pending", Helper.pending_import(app, enemy_receipt.action_id, "MANUAL_LATEST_RECEIPT_WITH_NEW_PENDING"))
	if not await cancel_pending_only(): finish(); return
	# The unchanged helper requires a genuinely un-narrated latest receipt. Two
	# new real ordinary actions supply it; no reset, save forgery or Engine swap.
	if (await action("observe", {"target_hex": app.playtest.state_copy().actors[PLAYER].hex})).is_empty(): finish(); return
	if not expect(app.playtest.current_actor_id() == ENEMY, "same contact scope schedules next ordinary enemy"): finish(); return
	if (await action("observe", {"target_hex": app.playtest.state_copy().actors[ENEMY].hex})).is_empty(): finish(); return
	add_helper_result("latest-idle", Helper.idle_latest_import(app, "MANUAL_LATEST_IDLE_RECEIPT"))
	expect(mock.sent.is_empty() and not app.runtime_ai.intention_consent, "entire finite suite stays offline without intention consent")
	finish()

func finish() -> void:
	if finished: return
	finished = true
	var report: Dictionary = {"schema": "manual-receipt-real-main-driver/v1", "ok": failures.is_empty(),
		"checks": checks, "failures": failures, "helper_results": helper_results, "actions": actions,
		"source_content_hash": source_content_hash, "main_sha256": FileAccess.get_sha256("res://main.gd"),
		"helper_sha256": FileAccess.get_sha256("res://tests/manual_receipt_display/helper.gd"),
		"driver_sha256": FileAccess.get_sha256("res://tests/manual_receipt_display/driver.gd"),
		"authority_sha256": Source.profile_digest(), "pid": OS.get_process_id(),
		"model_requests": mock.sent.size() if is_instance_valid(mock) else 0, "renderer": DisplayServer.get_name(),
		"scope": "one genuine source-bound contact route, two real round trips, manual receipt display only; no visual/GPU acceptance claim"}
	var path: String = OS.get_environment("WAP_RECEIPT_REPORT")
	if not safety_ready: printerr("MANUAL_RECEIPT_ADMISSION_FAILED ", C.bytes(report)); quit(2); return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: printerr("MANUAL_RECEIPT_REPORT_FAILED"); quit(2); return
	file.store_string(C.bytes(report)); file.close()
	if is_instance_valid(app): app.free()
	print("MANUAL_RECEIPT_DRIVER_RESULT ", C.bytes(report))
	quit(0 if failures.is_empty() else 1)

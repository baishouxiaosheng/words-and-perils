extends SceneTree
const Contract = preload("res://core/world_generation_contract.gd")
const Game = preload("res://core/game_state.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
class StartController:
	extends "res://main.gd"
	var preview := true
	var leave_allowed := true
	var switches := 0
	var preparations := 0
	var reject_navigation := false
	var last_status := ""
	func _ready() -> void: set_process(false)
	func is_map_preview() -> bool: return preview
	func _can_leave_current_adventure() -> bool: return leave_allowed
	func set_status(text: String) -> void: last_status = text
	func _switch_mode(mode: String) -> void:
		if mode == "generated": preview = false; generated_mode = true; playtest_mode = true; playtest = generated_adventure; switches += 1
	func prepare_seeded_adventure(envelope: Dictionary) -> RefCounted:
		preparations += 1
		if reject_navigation:
			var denied := SeededAdventure.new()
			denied.admission = {"ok": false, "code": "SEED_NAV_COMPONENT", "errors": ["Injected disconnected starting component rejection"]}
			return denied
		return super.prepare_seeded_adventure(envelope)
var checks := 0
var failures: Array = []
var app: Node
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func run() -> void:
	app = StartController.new(); app.game = Game.new(); root.add_child(app)
	app.goal = TextEdit.new(); app.add_child(app.goal); app.goal.text = "保留原草稿"
	var envelope := Contract.generate("UI-雪岸", "compact_coast", 4)
	app.game.state = app.prepare_world_candidate(envelope.source).candidate
	var original: String = C.bytes(app.game.state)
	app._mode_ui_snapshots.generated = {"protected": true}
	await app.start_generated_from_preview()
	check(app.preparations == 0 and app.generated_adventure == null and C.bytes(app.game.state) == original, "missing provenance rejects old preview without guessed metadata")
	check(app.last_status.contains("重新生成预览") and app.goal.text == "保留原草稿", "missing metadata gives useful Chinese action and preserves draft")
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	app.world_build_busy = true; await app.start_generated_from_preview()
	check(app.preparations == 0, "generation in progress blocks adventure start")
	app.world_build_busy = false; app.leave_allowed = false; await app.start_generated_from_preview()
	check(app.preparations == 0 and app.generated_adventure == null, "pending action custody blocks new source admission")
	app.leave_allowed = true; app.last_world_generation_metadata.request.seed_token = "tampered"
	await app.start_generated_from_preview()
	check(app.preparations == 1 and app.generated_adventure == null and app.preview, "mismatched metadata fails before mode switch")
	check(C.bytes(app.game.state) == original and app.goal.text == "保留原草稿" and app._mode_ui_snapshots.generated == {"protected": true}, "failed admission preserves preview, draft and prior generated UI snapshot")
	check(not app.generated_start_busy and app.last_status.contains("原世界与草稿保留"), "failure releases busy latch with honest status")
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	app.reject_navigation = true
	await app.start_generated_from_preview()
	check(app.preparations == 2 and app.generated_adventure == null and C.bytes(app.game.state) == original, "disconnected-start rejection does not publish candidate or lose original world")
	check(app.goal.text == "保留原草稿" and app.last_status.contains("SEED_NAV_COMPONENT"), "failed exact-navigation entry preserves draft and reports gate code")
	app.reject_navigation = false
	app.start_generated_from_preview()
	app._mode_epoch += 1; app.preview = false
	await process_frame; await process_frame
	check(app.preparations == 2 and not app.generated_start_busy and app.generated_adventure == null, "back/navigation while awaiting frame invalidates old entry")
	app.preview = true
	app.start_generated_from_preview(); app._world_build_epoch += 1
	await process_frame; await process_frame
	check(app.preparations == 2 and app.generated_adventure == null and not app.generated_start_busy, "new preview generation invalidates prior entry even within same mode")
	app.start_generated_from_preview(); app.start_generated_from_preview()
	await process_frame; await process_frame
	check(app.preparations == 3 and app.switches == 1, "duplicate starts build and publish exactly one candidate")
	check(app.generated_mode and app.playtest.ready().ok and not app.generated_start_busy, "actual seed wrapper admitted through main entry")
	check(C.bytes(app.playtest.generation_metadata) == C.bytes(envelope.metadata) and app.playtest.source.identity.content_hash == envelope.source.content_hash, "entry carries exact preview source and detached seed/preset provenance")
	check(C.bytes(app.game.state) == original and app.goal.text == "保留原草稿", "admission leaves preview source and draft untouched before renderer switch")
	check(not app._mode_ui_snapshots.has("generated"), "only successful new start discards prior generated UI snapshot")
	var established: String = C.bytes(app.generated_adventure.save_data())
	await app.start_generated_from_preview()
	check(app.preparations == 3 and C.bytes(app.generated_adventure.save_data()) == established, "generated mode cannot restart through stale preview command")
	var file := FileAccess.open("res://artifacts/seeded_adventure_20261003/controller_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "Actual main start method and real seeded adapter; renderer/mode switch mocked, navigation failure injected; no visual claim."}, "\t")); file.close()
	print("SEEDED ADVENTURE CONTROLLER ", checks - failures.size(), "/", checks)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

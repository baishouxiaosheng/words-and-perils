extends SceneTree
const Contract = preload("res://core/world_generation_contract.gd")
const Game = preload("res://core/game_state.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
class StartController:
	extends "res://main.gd"
	var preview := true
	var leave_allowed := true
	var switches := 0
	var inventory_starts := 0
	var plain_starts := 0
	var last_status := ""
	func _ready() -> void: set_process(false)
	func is_map_preview() -> bool: return preview
	func _can_leave_current_adventure() -> bool: return leave_allowed
	func set_status(text: String) -> void: last_status = text
	func _switch_mode(mode: String) -> void:
		if mode == "generated": preview = false; generated_mode = true; playtest_mode = true; playtest = generated_adventure; switches += 1
	func prepare_inventory_adventure(envelope: Dictionary) -> RefCounted:
		inventory_starts += 1
		return super.prepare_inventory_adventure(envelope)
	func prepare_seeded_adventure(envelope: Dictionary) -> RefCounted:
		plain_starts += 1
		return super.prepare_seeded_adventure(envelope)
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func run() -> void:
	var app := StartController.new(); app.game = Game.new(); root.add_child(app)
	app.goal = TextEdit.new(); app.add_child(app.goal); app.goal.text = "保留原草稿"
	app.generated_inventory_choice = CheckButton.new(); app.add_child(app.generated_inventory_choice)
	var envelope := Contract.generate("UI-行囊", "compact_coast", 4)
	app.game.state = app.prepare_world_candidate(envelope.source).candidate
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	var original := C.bytes(app.game.state)
	app.generated_inventory_choice.button_pressed = true
	app.leave_allowed = false; await app.start_generated_from_preview()
	check(app.inventory_starts == 0 and app.generated_adventure == null, "pending current adventure blocks opted-in start")
	app.leave_allowed = true
	app.last_world_generation_metadata.request.seed_token = "mismatch"
	await app.start_generated_from_preview()
	check(app.inventory_starts == 1 and app.generated_adventure == null and app.preview, "inventory start rejects inconsistent provenance without fallback")
	check(C.bytes(app.game.state) == original and app.goal.text == "保留原草稿", "failed inventory start preserves old preview/draft")
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	app.start_generated_from_preview(); app._mode_epoch += 1; app.preview = false
	await process_frame; await process_frame
	check(app.inventory_starts == 1 and app.generated_adventure == null and not app.generated_start_busy, "navigation during initial frame invalidates opted-in start")
	app.preview = true
	app.start_generated_from_preview(); app.generated_inventory_choice.button_pressed = false; app.start_generated_from_preview()
	await process_frame; await process_frame
	check(app.inventory_starts == 2 and app.plain_starts == 0 and app.switches == 1, "start captures explicit profile once; repeat click/toggle cannot replace it")
	check(app.generated_mode and app.playtest.save_data().schema_version == "generated_inventory_save/v1", "actual main starts exact inventory profile")
	check(app.playtest.state_copy().items.size() == 1 and app.playtest.state_copy().actors.actor_player.inventory == ["item_travel_bundle"], "profile adds only explicit carried bundle")
	check(C.bytes(app.game.state) == original and app.goal.text == "保留原草稿" and C.bytes(app.playtest.generation_metadata) == C.bytes(envelope.metadata), "source/provenance/draft remain exact through opted-in start")
	var initial := C.bytes(app.playtest.save_data())
	app.fill_generated_sample("drop_item")
	check(not app.goal.text.contains("署名") and app.submitted_player_intent().contains("署名物品样例"), "UI displays ordinary wording but retains exact signed assessment goal")
	check(C.bytes(app.playtest.save_data()) == initial, "sample button only fills text, never assesses or drops")
	app.goal.text += "，再拆开"
	check(app.submitted_player_intent() == app.goal.text, "editing sample cannot retain original fixture authorization")
	app.queue_free(); await process_frame
	var file := FileAccess.open("res://artifacts/generated_inventory_20261004/controller_report.json", FileAccess.WRITE); file.store_string(JSON.stringify({"checks": checks, "failures": failures, "scope": "Actual entry callbacks; render/mode switch replaced. Native UI tested separately."}, "\t")); file.close()
	print("INVENTORY CONTROLLER ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)

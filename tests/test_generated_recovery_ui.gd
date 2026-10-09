extends SceneTree
## Corrupt generated saves must never reach renderer dereferences.
const Main = preload("res://main.tscn")
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = Main.instantiate(); root.add_child(scene); await process_frame
	scene.world_build_requested = true; scene.world_build_seed = 726381; scene.world_build_radius = 7
	scene.build_selected_world()
	scene.goal.text = "保留已掷骰的世界"; scene.submit_action()
	var request: Dictionary = scene.current_request.duplicate(true)
	check(scene.apply_decision({"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "计划尚待确认。", "context": "UI integrity fixture", "needs_roll": true, "difficulty": 10}), "Generated planning applies normally")
	scene.roll_dice()
	check(scene.current_request.phase == "resolution", "UI retains a rolled resolution before corrupt load")
	var before: Dictionary = scene.game.state.duplicate(true)
	var action: String = scene.active_action
	var current: Dictionary = scene.current_request.duplicate(true)
	var phase: String = scene.phase_label.text
	var die: String = scene.die_label.text
	for replacement in [{}, null, {"generator_version": "future_macro_v2"}]:
		var corrupt := before.duplicate(true); corrupt.generated_world = replacement
		write_save(corrupt)
		scene.load_game()
		check(scene.game.state == before and scene.active_action == action and scene.current_request == current, "Malformed metadata rejection preserves world, active action and current request")
		check(scene.phase_label.text == phase and scene.die_label.text == die and scene.status_label.text.contains("读取失败"), "Malformed metadata rejection preserves displayed phase/die and reports load failure")
	var corrupt := before.duplicate(true)
	corrupt.generated_world.seed = "bad seed type"; write_save(corrupt); scene.load_game()
	check(scene.game.state == before and scene.active_action == action, "Wrong seed type is rejected before UI/renderer access")
	corrupt = before.duplicate(true)
	corrupt.generated_world.roads[0].path = ["99,99", "0,0"]; write_save(corrupt); scene.load_game()
	check(scene.game.state == before and scene.active_action == action, "Missing road tile is rejected before infrastructure renderer access")
	corrupt = before.duplicate(true)
	corrupt.generated_world.settlements[0].hex = [99,99]; write_save(corrupt); scene.load_game()
	check(scene.game.state == before and scene.active_action == action, "Invalid settlement coordinate is rejected before renderer access")
	write_save(before); scene.restart_game(); scene.load_game()
	check(scene.game.state == before and scene.active_action == action and scene.current_request.phase == "resolution", "Full valid generated rolled save still reloads through application")
	check(scene.current_request.roll.d20 == before.pending_actions[action].roll.value and scene.roll_button.disabled, "Reloaded die remains exact and cannot reroll")
	scene.cancel_pending(); scene.restart_game(); scene.save_game(); scene.load_game()
	check(scene.game.state.hexes.size() == 61 and not scene.game.state.has("generated_world"), "Original metadata-absent61 world still reloads through application")
	scene.queue_free(); await process_frame; await process_frame
	for failure in failures: printerr("FAIL: " + failure)
	print("GENERATED RECOVERY UI: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
func write_save(value: Dictionary) -> void:
	var file := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

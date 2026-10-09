extends SceneTree
## Scenario fixtures test the player-facing state machine, never GM quality.
const Main = preload("res://main.tscn")
var scene
var results: Array = []

func _initialize() -> void:
	call_deferred("run_tests")

func record(id: String, passed: bool, expected: String, observed: String, severity := "P2", owner := "UI") -> void:
	results.append({"id": id, "passed": passed, "expected": expected, "observed": observed, "severity": severity, "owner": owner, "evidence": "tests/test_playability.gd; isolated headless scene fixture"})
	print(("PASS " if passed else "FAIL ") + id + ": " + observed)

func planning(needs_roll: bool) -> Dictionary:
	return {"schema_version": 1, "action_id": scene.active_action, "state_version": scene.game.state.state_version, "phase": "planning", "narration": "测试拟议行动，尚未执行。", "context": "QA protocol fixture, not a live or recorded model response.", "needs_roll": needs_roll, "difficulty": 12}

func resolution(patches: Array = []) -> Dictionary:
	return {"schema_version": 1, "action_id": scene.active_action, "state_version": scene.game.state.state_version, "phase": "resolution", "narration": "测试回合完成。", "outcome": "QA only", "patches": patches, "provenance": {"provider": "qa_protocol_fixture", "live": false}}

func run_tests() -> void:
	scene = Main.instantiate()
	root.add_child(scene)
	await process_frame
	scene.goal.text = "  "
	scene.submit_action()
	record("S01_EMPTY_INTENT", scene.active_action.is_empty(), "Empty intent and no target cannot submit", scene.status_label.text)
	scene.on_hex_selected(Vector2i(4, 0))
	scene.goal.text = ""
	var before_click_submit:Dictionary=scene.game.state.duplicate(true)
	scene.submit_action()
	record("S02_ATTENTION_ONLY", scene.active_action.is_empty() and scene.game.state==before_click_submit, "Selected focus alone never creates an action or changes exact state", scene.status_label.text)
	scene.goal.text="尝试前往远处所关注的地格"
	scene.submit_action()
	var action_id: String = scene.active_action
	record("S02B_EXPLICIT_FAR_INTENT", scene.current_request.get("target_binding")=="unbound" and scene.current_request.attention_focus.id=="hex_4_0", "Explicit far intent carries contextual attention without client-created destination or effects", str(scene.current_request.get("target_hex")))
	scene.submit_action()
	scene.submit_action()
	record("S03_RAPID_SUBMIT", scene.active_action == action_id and scene.game.state.pending_actions.size() == 1, "Repeated submit does not create duplicate actions", "%s pending actions" % scene.game.state.pending_actions.size(), "P1")
	var stale_plan: Dictionary = planning(false)
	scene.cancel_pending()
	record("S04_CANCEL_LATE_REPLY", not scene.apply_decision(stale_plan) and scene.game.state.state_version == 0, "Late reply after cancellation is rejected with no factual mutation", scene.status_label.text, "P1")
	scene.restart_game()
	scene.goal.text = "观察守卫"
	scene.submit_action()
	scene.apply_decision(planning(true))
	scene.roll_dice()
	var first_roll: Dictionary = scene.current_request.context.player_roll.duplicate(true)
	scene.roll_dice()
	record("S05_RAPID_DICE", scene.current_request.context.player_roll == first_roll, "A second roll cannot change the recorded result", str(scene.current_request.context.player_roll), "P1")
	scene.cancel_pending()
	scene.goal.text = "重新观察河岸"
	scene.submit_action()
	record("S06_NEW_ACTION_DIE", scene.die_label.text.contains("—"), "A new pending action shows no die rather than a cancelled action's result", scene.die_label.text)
	var before: Dictionary = scene.game.state.duplicate(true)
	scene.import_text.text = "{not JSON"
	scene.import_decision()
	record("S07_BAD_JSON", scene.game.state == before and scene.import_text.text == "{not JSON", "Malformed response preserves state and editable input", scene.status_label.text, "P1")
	scene.apply_decision(planning(false))
	record("S08_NO_ROLL", scene.current_request.get("phase") == "resolution" and scene.roll_button.disabled and scene.game.state.state_version == 0, "No-roll planning still waits for final adjudication", scene.phase_label.text, "P1")
	scene.apply_decision(resolution([{"op": "set", "path": "/flags/qa_progress", "value": true}]))
	scene.save_game()
	scene.on_hex_selected(Vector2i(4, 0))
	scene.board.hover_hex=Vector2i(4,0)
	scene.goal.text = "这个草稿不属于保存的世界"
	scene.load_game()
	record("S09_LOAD_CLEAR_DRAFT", scene.selected == Vector2i(99, 99) and scene.board.hover_hex==Vector2i(99,99) and scene.goal.text.is_empty(), "Loading without a pending action clears unrelated stale target and draft", "target=%s; draft=%s" % [scene.selected, scene.goal.text])
	var before_demo: Dictionary = scene.game.state.duplicate(true)
	scene.start_demo()
	record("S10_DEMO_PRESERVES_PROGRESS", scene.game.state.world_id == before_demo.world_id and scene.game.state.state_version == before_demo.state_version and scene.game.state.flags.get("qa_progress", false), "Trying recorded demo after progress must not silently replace the world", "before=v%s %s; after=v%s %s" % [before_demo.state_version, before_demo.world_id, scene.game.state.state_version, scene.game.state.world_id], "P1")
	scene.restart_game()
	scene.start_demo()
	record("S11_DEMO_PREVIEW", scene.game.state.state_version == 0 and scene.game.state.actors.actor_player.hex == [-2, 1] and scene.roll_button.text.contains("9"), "Recorded planning remains provisional and labels the fixed test die", scene.roll_button.text, "P1")
	scene.roll_dice()
	record("S12_DEMO_COMMIT", scene.game.state.state_version == 1 and scene.game.state.items.item_mist_draught.quantity == 0 and scene.game.state.actors.actor_player.hex == [1, -1], "Recorded compound turn commits exactly once", "v%s, position=%s, potion=%s" % [scene.game.state.state_version, scene.game.state.actors.actor_player.hex, scene.game.state.items.item_mist_draught.quantity], "P1")
	scene.restart_game()
	scene.goal.text = "等待模型判断"
	scene.submit_action()
	scene.apply_decision(planning(true))
	scene.save_game()
	scene.restart_game()
	scene.load_game()
	record("S13_RESUME_NEXT_STEP", not scene.roll_button.disabled and (scene.phase_label.text.contains("掷骰") or scene.phase_label.text.contains("D20")), "Restoring a pending roll visibly states the next required step", scene.phase_label.text)
	var report := {"kind": "player_flow_protocol_fixtures", "live_model_calls": 0, "results": results}
	var file := FileAccess.open("res://tests/playability_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var failures: int = results.filter(func(row): return not row.passed).size()
	print("PLAYABILITY SCENARIOS: %s/%s passed" % [results.size()-failures, results.size()])
	quit(1 if failures else 0)

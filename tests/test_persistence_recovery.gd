extends SceneTree
## Integrity-only save recovery tests; no gameplay decisions are fabricated.
const Game = preload("res://core/game_state.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	var game = Game.new()
	var request: Dictionary = game.request("观察河岸", Vector2i(-1, 1)).request
	game.apply_planning({"schema_version": 1, "action_id": request.action_id, "state_version": 0, "phase": "planning", "narration": "尚未执行的测试规划。", "context": "QA integrity fixture only.", "needs_roll": true, "difficulty": 12})
	game.roll_action(request.action_id, 9)
	var valid: Dictionary = game.state.duplicate(true)
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt.pending_actions[request.action_id].roll.erase("source")
	reject(corrupt, "P01_MISSING_ROLL_SOURCE", "Saved roll without provenance must be rejected before resume_request accesses source")
	corrupt = valid.duplicate(true)
	corrupt.pending_actions[request.action_id].status = "awaiting_roll"
	reject(corrupt, "P02_REROLLABLE_STORED_DIE", "Saved action cannot be awaiting_roll when it already owns a recorded die")
	corrupt = valid.duplicate(true)
	corrupt.pending_actions[request.action_id].roll = null
	reject(corrupt, "P03_MISSING_REQUIRED_DIE", "Resolution requiring a roll must contain its committed D20")
	corrupt = valid.duplicate(true)
	corrupt.pending_actions[request.action_id].planning = {}
	reject(corrupt, "P04_MISSING_REQUIRED_PLAN", "Resolution must retain the GM planning it depends on")
	corrupt = valid.duplicate(true)
	corrupt.pending_actions[request.action_id].snapshot = {}
	reject(corrupt, "P05_EMPTY_SNAPSHOT", "Pending request must retain complete world snapshot")
	corrupt = valid.duplicate(true)
	corrupt.pending_actions = {}
	corrupt.actors.erase("actor_player")
	reject(corrupt, "P06_MISSING_PLAYER", "Application save must retain the player actor consumed by UI")
	var path := "user://qa_integrity_valid.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(valid)); file.close()
	var restored = Game.new()
	check(restored.load_from_file(path).ok and restored.state == valid, "P07_VALID_ROUNDTRIP", "Well-formed rolled save still roundtrips exactly")
	_run_extended_tests()
	print("PERSISTENCE RECOVERY: %s/%s passed" % [checks-failures.size(), checks])
	quit(1 if not failures.is_empty() else 0)

func reject(corrupt: Dictionary, id: String, explanation: String) -> void:
	var path := "user://qa_integrity_" + id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt)); file.close()
	var target = Game.new()
	var before: Dictionary = target.state.duplicate(true)
	var loaded: Dictionary = target.load_from_file(path)
	check(not loaded.ok and target.state == before, id, explanation + "; accepted=" + str(loaded.ok))

func check(passed: bool, id: String, message: String) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + id + ": " + message)
	if not passed: failures.append(id)

func plan(request: Dictionary, needs_roll: bool = true) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "仅描述尚待确认的意图。", "context": "Integrity fixture, not gameplay adjudication.", "needs_roll": needs_roll, "difficulty": 7.5, "new_model_field": {"possible_effects": ["GM-defined"]}}

func resolution(request: Dictionary) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "resolution", "narration": "完整性测试已结束。", "outcome": "arbitrary GM-defined outcome", "patches": [{"op": "set", "path": "/flags/model_defined_condition", "value": {"origin": "GM", "weight": 0.125}}], "new_model_field": "permitted"}

func roundtrip(source, id: String):
	var path := "user://qa_roundtrip_" + id + ".json"
	var expected: Dictionary = source.state.duplicate(true)
	var restored = Game.new()
	var saved: Dictionary = source.save_to_file(path)
	var loaded: Dictionary = restored.load_from_file(path)
	check(saved.ok and loaded.ok and restored.state == expected, id, "Supported save phase roundtrips without losing facts or optional GM fields")
	return restored

func mutate_and_reject(valid: Dictionary, path: Array, value: Variant, id: String) -> void:
	var corrupt: Dictionary = valid.duplicate(true)
	var node: Variant = corrupt
	for index in range(path.size() - 1):
		node = node[path[index]]
	node[path[-1]] = value
	reject(corrupt, id, "Malformed persisted protocol/world/ledger field must be rejected atomically")

func _run_extended_tests() -> void:
	var game = Game.new()
	var asked: Dictionary = game.request("观察雾岸", Vector2i.ZERO).request
	var action_id: String = asked.action_id
	var planning_state: Dictionary = game.state.duplicate(true)
	var restored = roundtrip(game, "P08_AWAITING_PLANNING")
	check(restored.resume_request(action_id).request.phase == "planning", "P09_RESUME_PLANNING", "Restored unplanned intent exports the original planning phase")
	game.apply_planning(plan(asked))
	var roll_state: Dictionary = game.state.duplicate(true)
	restored = roundtrip(game, "P10_AWAITING_ROLL")
	var resumed: Dictionary = restored.resume_request(action_id)
	resumed.action.planning.needs_roll = false
	check(restored.state.pending_actions[action_id].planning.needs_roll, "P11_DETACHED_RESUME", "Resume metadata cannot modify stored planning")
	check(restored.roll_action(action_id, 6).ok and not restored.roll_action(action_id, 18).ok, "P12_RESUMED_ROLL_ONCE", "Restored awaiting-roll action accepts exactly one die")
	var rolled: Dictionary = game.roll_action(action_id, 9)
	rolled.request.context.player_roll.value = 20
	rolled.request.context.player_roll.source = "tampered"
	rolled.request.context.planning.needs_roll = false
	check(game.state.pending_actions[action_id].roll.value == 9 and game.state.pending_actions[action_id].roll.source == "test_override" and game.state.pending_actions[action_id].planning.needs_roll, "P13_DETACHED_EXPORTED_DIE", "Exported resolution context cannot alter immutable recorded die or GM planning")
	var valid: Dictionary = game.state.duplicate(true)
	restored = roundtrip(game, "P14_ROLLED_RESOLUTION")
	var resume: Dictionary = restored.resume_request(action_id)
	check(resume.request.roll.d20 == 9 and resume.request.context.player_roll.source == "test_override" and not restored.roll_action(action_id, 17).ok, "P15_RESUME_LOCKED_DIE", "Restored resolution keeps the exact original D20 and rejects reroll")
	var final := resolution(resume.request)
	check(restored.commit_decision(final).ok, "P16_COMMIT_RESTORED", "Restored resolution commits model-defined fields without local gameplay rules")
	var committed_state: Dictionary = restored.state.duplicate(true)
	var reloaded = roundtrip(restored, "P17_COMMITTED")
	var before: Dictionary = reloaded.state.duplicate(true)
	check(reloaded.commit_decision(final).get("already_committed", false) and reloaded.state == before, "P18_DURABLE_IDEMPOTENCY", "Repeated identical resolution after reload leaves every fact unchanged")
	var conflicting := final.duplicate(true)
	conflicting.outcome = "different GM outcome"
	check(not reloaded.commit_decision(conflicting).ok and reloaded.state == before, "P19_DURABLE_CONFLICT", "Different decision under committed ID is rejected after reload")
	check(not reloaded.cancel_action(action_id).ok and reloaded.state == before, "P20_COMMITTED_CANCEL", "Cancellation cannot remove an already committed event")
	game = Game.new()
	asked = game.request("不用骰子的意图", Vector2i.ZERO).request
	var no_roll_plan := plan(asked, false)
	no_roll_plan.difficulty = null
	var no_roll_request: Dictionary = game.apply_planning(no_roll_plan).request
	var no_roll_state: Dictionary = game.state.duplicate(true)
	restored = roundtrip(game, "P21_NO_ROLL_RESOLUTION")
	resume = restored.resume_request(asked.action_id)
	check(resume.request.phase == "resolution" and resume.request.roll == null and resume.request.context.player_roll == null and not restored.roll_action(asked.action_id).ok, "P22_NO_FABRICATED_DIE", "No-roll save resumes directly at resolution with no manufactured die")
	check(restored.commit_decision(resolution(resume.request)).ok, "P23_NO_ROLL_COMMIT", "No-roll final adjudication still commits normally")
	game = Game.new()
	asked = game.request("取消测试", Vector2i.ZERO).request
	game.apply_planning(plan(asked))
	game.roll_action(asked.action_id, 5)
	check(game.cancel_action(asked.action_id).ok, "P24_CANCEL_ROLLED", "Cancelling a rolled pending action preserves world facts")
	restored = roundtrip(game, "P25_CANCELLED")
	before = restored.state.duplicate(true)
	check(not restored.resume_request(asked.action_id).ok and not restored.apply_planning(plan(asked)).ok and not restored.commit_decision(resolution(asked)).ok and restored.state == before, "P26_CANCEL_LATE_REPLIES", "Cancelled action cannot be resumed or resurrected by late planning/resolution")
	game = Game.new()
	var older: Dictionary = game.request("并发旧意图", Vector2i.ZERO).request
	var newer: Dictionary = game.request("并发完成意图", Vector2i(1, 0)).request
	game.apply_planning(plan(older))
	game.apply_planning(plan(newer, false))
	game.commit_decision(resolution(newer))
	restored = roundtrip(game, "P27_VALID_STALE_PENDING")
	before = restored.state.duplicate(true)
	check(not restored.roll_action(older.action_id).ok and not restored.commit_decision(resolution(older)).ok and restored.state == before, "P28_STALE_REMAINS_INERT", "Legitimate concurrent stale saves load while old actions cannot change the new world")
	var bad_plan := plan(older)
	bad_plan.provenance = "incorrect object type"
	var fresh = Game.new()
	var fresh_request: Dictionary = fresh.request("协议类型测试", Vector2i.ZERO).request
	bad_plan = plan(fresh_request)
	bad_plan.provenance = "incorrect object type"
	before = fresh.state.duplicate(true)
	check(not fresh.apply_planning(bad_plan).ok and fresh.state == before, "P29_BAD_PROVENANCE_PROTOCOL", "Protocol rejects unsafe provenance before creating an unsaveable action")
	for case in [
		[["schema_version"], "1", "P30_SCHEMA_TYPE"],
		[["board_radius"], "4", "P31_RADIUS_TYPE"],
		[["hexes", "0,0", "q"], 4294967296, "P32_COORDINATE_WRAP"],
		[["recent_dialogue", 0], "bad entry", "P33_DIALOGUE_TYPE"],
		[["recent_dialogue", 0, "state_version"], -1, "P34_DIALOGUE_VERSION"],
		[["pending_actions", action_id, "state_version"], -1, "P35_NEGATIVE_ACTION_VERSION"],
		[["pending_actions", action_id, "state_version"], 1, "P36_FUTURE_ACTION_VERSION"],
		[["pending_actions", action_id, "goal"], " ", "P37_EMPTY_GOAL"],
		[["pending_actions", action_id, "roll", "source"], 42, "P38_ROLL_SOURCE_TYPE"],
		[["pending_actions", action_id, "roll", "source"], "", "P39_EMPTY_ROLL_SOURCE"],
		[["pending_actions", action_id, "roll", "value"], 0, "P40_INVALID_DIE"],
		[["pending_actions", action_id, "roll", "value"], 9.5, "P41_FRACTIONAL_DIE"],
		[["pending_actions", action_id, "planning", "action_id"], "other_action", "P42_PLAN_ID"],
		[["pending_actions", action_id, "planning", "state_version"], 1, "P43_PLAN_VERSION"],
		[["pending_actions", action_id, "planning", "phase"], "resolution", "P44_PLAN_PHASE"],
		[["pending_actions", action_id, "planning", "needs_roll"], "true", "P45_PLAN_ROLL_TYPE"],
		[["pending_actions", action_id, "planning", "difficulty"], -1, "P46_INVALID_GM_DIFFICULTY"],
		[["pending_actions", action_id, "planning", "patches"], [{"op": "set", "path": "/flags/x", "value": true}], "P47_PLANNING_MUTATION"],
		[["pending_actions", action_id, "planning", "provenance"], [], "P48_PLAN_PROVENANCE_TYPE"],
		[["pending_actions", action_id, "snapshot", "world_id"], "other_world", "P49_SNAPSHOT_WORLD"],
		[["pending_actions", action_id, "snapshot", "state_version"], 1, "P50_SNAPSHOT_VERSION"],
		[["pending_actions", action_id, "snapshot", "actors", "actor_player", "hex"], [99, 99], "P51_SNAPSHOT_ACTOR_HEX"],
		[["pending_actions", action_id, "preview"], {}, "P52_PREVIEW_MISSING"],
		[["pending_actions", action_id, "preview", "from"], [1, 0], "P53_PREVIEW_FROM"],
		[["pending_actions", action_id, "preview", "to"], [1, 0], "P54_PREVIEW_TO"],
		[["pending_actions", action_id, "preview", "hex_distance"], 99, "P55_PREVIEW_DISTANCE"],
		[["pending_actions", action_id, "preview", "advisory_only"], false, "P56_PREVIEW_AUTHORITY"],
		[["pending_actions", action_id, "preview", "target_terrain"], "unknown", "P57_PREVIEW_TERRAIN"]
	]:
		mutate_and_reject(valid, case[0], case[1], case[2])
	mutate_and_reject(planning_state, ["pending_actions", action_id, "planning"], plan({"action_id": action_id, "state_version": 0}), "P58_UNPLANNED_WITH_PLAN")
	mutate_and_reject(planning_state, ["pending_actions", action_id, "roll"], {"die": "d20", "value": 2, "source": "test_override"}, "P59_UNPLANNED_WITH_DIE")
	mutate_and_reject(roll_state, ["pending_actions", action_id, "planning", "needs_roll"], false, "P60_AWAITING_UNNEEDED_ROLL")
	mutate_and_reject(no_roll_state, ["pending_actions", no_roll_request.action_id, "roll"], {"die": "d20", "value": 2, "source": "test_override"}, "P61_NO_ROLL_WITH_DIE")
	for case in [
		[["events", 0], "bad event", "P62_EVENT_TYPE"],
		[["events", 0, "roll", "source"], "", "P63_EVENT_DIE_SOURCE"],
		[["events", 0, "after_version"], 7, "P64_EVENT_VERSION_SEQUENCE"],
		[["committed_actions", action_id, "decision_hash"], "broken", "P65_IDEMPOTENCY_HASH"],
		[["committed_actions", action_id, "event", "outcome"], "tampered", "P66_LEDGER_EVENT_MISMATCH"],
		[["committed_actions"], {}, "P67_MISSING_IDEMPOTENCY_LEDGER"],
		[["events"], [], "P68_MISSING_EVENT_HISTORY"],
		[["pending_actions", action_id], valid.pending_actions[action_id], "P69_PENDING_COMMITTED_COLLISION"]
	]:
		mutate_and_reject(committed_state, case[0], case[1], case[2])
	var invalid_state: Dictionary = valid.duplicate(true)
	invalid_state.actors.actor_player.health.current = -1
	var writer = Game.new()
	var protected_path := "user://qa_protected_atomic_save.json"
	writer.save_to_file(protected_path)
	var existing_bytes := FileAccess.get_file_as_string(protected_path)
	writer.state = invalid_state
	check(not writer.save_to_file(protected_path).ok and FileAccess.get_file_as_string(protected_path) == existing_bytes, "P70_SAVE_FAILURE_PRESERVES_FILE", "Invalid live state cannot replace an existing good save")

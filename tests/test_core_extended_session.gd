extends SceneTree
## Positive compatibility fixture: new GM-defined data and durable long history.
const Game = preload("res://core/game_state.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	var game = Game.new()
	var request: Dictionary = game.request("GM 描述新的同行者与物品", Vector2i.ZERO).request
	var planned: Dictionary = game.apply_planning(plan(request, false))
	check(planned.ok, "Initial no-roll planning")
	var final := resolution(planned.request)
	final.patches = [
		{"op": "set", "path": "/actors/actor_companion", "value": {"id": "actor_companion", "name": "GM 命名的同行者", "hex": [1, 0], "health": {"current": 4.75, "max": 8.5}, "stamina": {"current": 0.125, "max": 2.5}, "inventory": ["item_custom"], "model_defined_condition": {"description": "完全由 GM 解释", "tags": ["custom"]}}},
		{"op": "set", "path": "/items/item_custom", "value": {"id": "item_custom", "name": "GM 命名的物品", "description": "没有对应任何客户端效果表。", "quantity": 3, "model_defined_property": ["descriptive", 0.375]}},
		{"op": "set", "path": "/hexes/1,0/terrain", "value": "GM 命名的地形"},
		{"op": "set", "path": "/flags/new_model_field", "value": {"custom": [true, null, 0.375]}}
	]
	check(game.commit_decision(final).ok, "GM may create new valid entities/terrain/fields and fractional numeric pools")
	for index in range(48):
		request = game.request("长历史测试 %d" % index, Vector2i(1, 0), "actor_companion").request
		planned = game.apply_planning(plan(request, index % 2 == 0))
		check(planned.ok, "Planning accepts complete accumulated snapshot %d" % index)
		var exact_request: Dictionary
		if index % 2 == 0:
			var rolled: Dictionary = game.roll_action(request.action_id, index % 20 + 1)
			check(rolled.ok, "Exactly one stored D20 for action %d" % index)
			exact_request = rolled.request
		else:
			exact_request = planned.request
		final = resolution(exact_request)
		final.patches = [{"op": "set", "path": "/world_time", "value": index + 1}, {"op": "set", "path": "/flags/gm_history_note", "value": "arbitrary %d" % index}]
		check(game.commit_decision(final).ok, "One atomic final event %d" % index)
	check(game.state.events.size() == 49 and game.state.committed_actions.size() == 49 and game.state.state_version == 49 and game.state.recent_dialogue.size() == 40, "Long session keeps full durable ledger and bounds only recent dialogue")
	request = game.request("继续长历史中已掷骰的同行者行动", Vector2i.ZERO, "actor_companion").request
	game.apply_planning(plan(request, true))
	var rolled: Dictionary = game.roll_action(request.action_id, 13)
	var path := "user://qa_extended_session.json"
	var expected: Dictionary = game.state.duplicate(true)
	var restored = Game.new()
	check(game.save_to_file(path).ok and restored.load_from_file(path).ok and restored.state == expected, "49-event save with rolled pending action roundtrips all custom fields exactly")
	var resumed: Dictionary = restored.resume_request(request.action_id)
	check(resumed.request.context.player_roll.value == 13 and resumed.request.snapshot.events.size() == 49 and resumed.request.actor_id == "actor_companion", "Restored GM receives exact custom actor, die and complete historical snapshot")
	final = resolution(resumed.request)
	check(restored.commit_decision(final).ok and restored.state.events.size() == 50, "Long-history resumed action commits once")
	expected = restored.state.duplicate(true)
	check(restored.commit_decision(final).get("already_committed", false) and restored.state == expected, "Long-history identical final remains idempotent")
	request = restored.request("取消同行者的下一意图", Vector2i.ZERO, "actor_companion").request
	check(restored.cancel_action(request.action_id).ok and restored.state.events.size() == 50, "Custom actor cancellation preserves all durable history")
	for failure in failures: printerr("FAIL: " + failure)
	print("CORE EXTENDED SESSION: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func plan(request: Dictionary, needs_roll: bool) -> Dictionary:
	var decision := {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "仅为待确认的 GM 意图。", "context": "Positive compatibility fixture.", "needs_roll": needs_roll, "model_extension": {"unrestricted_description": "Future GM fields survive."}}
	if needs_roll: decision.difficulty = 3.125
	return decision

func resolution(request: Dictionary) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "resolution", "narration": "GM 完整性测试最终裁定。", "outcome": "unlisted free-text GM result", "patches": [], "model_extension": {"unrestricted_description": "No client-side result enum."}}

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed: failures.append(message)

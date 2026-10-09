extends SceneTree
const Game = preload("res://core/game_state.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void:
	var game = Game.new()
	var request: Dictionary = game.request("类型契约测试", Vector2i.ZERO).request
	var types: Dictionary = request.gm_contract.field_types
	check(types.common.narration.contains("nonempty string"), "GM narration explicitly typed as nonempty string")
	check(types.common.schema_version.contains("integer") and types.common.state_version.contains("integer"), "Protocol versions explicitly typed as integers")
	check(types.common.action_id.contains("string"), "Action identity explicitly typed as string")
	check(types.planning.context.contains("string") and types.planning.context.contains("never an object or array"), "Planning context explicitly typed as string rather than structured object")
	check(types.planning.needs_roll.contains("boolean"), "Roll requirement explicitly typed as boolean")
	check(types.planning.difficulty.contains("finite nonnegative number") and types.planning.difficulty.contains("required only"), "GM difficulty explicitly typed as finite conditional numeric field")
	check(types.planning.patches.contains("omit") and types.planning.patches.contains("never changes state"), "Planning patch restriction is explicit")
	check(types.resolution.outcome.contains("nonempty string") and types.resolution.outcome.contains("free-text"), "Outcome stays a nonempty free-text GM string")
	check(types.resolution.patches.contains("required array") and types.resolution.patches.contains("[] is allowed"), "Resolution patches explicitly typed as array")
	var planning := {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "计划尚未落实。", "needs_roll": false, "context": {"approach": "invalid object output"}}
	var before: Dictionary = game.state.duplicate(true)
	check(not game.apply_planning(planning).ok and game.state == before, "Object-valued model context is rejected without coercion or mutation")
	planning.context = "Corrected model context string"
	var planned: Dictionary = game.apply_planning(planning)
	check(planned.ok and planned.request.gm_contract.field_types == types, "Corrected string context is accepted and typed contract continues into resolution")
	var final := {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "resolution", "narration": "最终裁定。", "outcome": {"invalid": "object"}, "patches": []}
	before = game.state.duplicate(true)
	check(not game.commit_decision(final).ok and game.state == before, "Object-valued outcome is rejected without coercion or mutation")
	final.outcome = "GM-defined free text"
	final.patches = {"invalid": "object"}
	check(not game.commit_decision(final).ok and game.state == before, "Object-valued patches are rejected without coercion or mutation")
	final.patches = []
	check(game.commit_decision(final).ok, "Well-typed empty-patch final commits normally")
	for failure in failures: printerr("FAIL: " + failure)
	print("GM CONTRACT TYPES: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

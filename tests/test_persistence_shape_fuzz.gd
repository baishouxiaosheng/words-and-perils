extends SceneTree
## Deterministic malformed-type probes for every persisted required field.
## Optional model-defined metadata and patch values remain unrestricted JSON.
const Game = preload("res://core/game_state.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	var game = Game.new()
	var request: Dictionary = game.request("数据形状测试", Vector2i.ZERO).request
	var planning := {"schema_version": 1, "action_id": request.action_id, "state_version": 0, "phase": "planning", "narration": "尚待确认的意图。", "context": "QA fixture", "needs_roll": true, "difficulty": 12}
	game.apply_planning(planning)
	game.roll_action(request.action_id, 9)
	var pending: Dictionary = game.state.duplicate(true)
	probe(pending)
	game.commit_decision({"schema_version": 1, "action_id": request.action_id, "state_version": 0, "phase": "resolution", "narration": "QA fixture completed", "outcome": "GM-defined", "patches": [{"op": "set", "path": "/flags/fixture", "value": {"arbitrary": "model metadata"}}]})
	probe(game.state)
	for key in ["schema_version", "action_id", "state_version", "phase", "narration", "needs_roll", "difficulty", "context"]:
		for replacement in bad_types(planning[key]):
			var decision := planning.duplicate(true)
			decision[key] = replacement
			var fresh = Game.new()
			var fresh_request: Dictionary = fresh.request("协议测试", Vector2i.ZERO).request
			if key != "action_id": decision.action_id = fresh_request.action_id
			var before: Dictionary = fresh.state.duplicate(true)
			checks += 1
			if fresh.apply_planning(decision).ok or fresh.state != before:
				failures.append("decision." + key + " accepts " + type_string(typeof(replacement)))
	for failure in failures: printerr("FAIL: " + failure)
	print("PERSISTENCE SHAPE FUZZ: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func probe(valid: Dictionary) -> void:
	var fields: Array = []
	collect(valid, [], fields)
	var target = Game.new()
	var before: Dictionary = target.state.duplicate(true)
	var path := "user://qa_shape_fuzz.json"
	for field in fields:
		for replacement in bad_types(field.value):
			var corrupt := valid.duplicate(true)
			var node: Variant = corrupt
			for index in range(field.path.size() - 1): node = node[field.path[index]]
			node[field.path[-1]] = replacement
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify(corrupt)); file.close()
			checks += 1
			var result: Dictionary = target.load_from_file(path)
			if result.ok or target.state != before:
				failures.append(str(field.path) + " accepts " + type_string(typeof(replacement)))
				# Preserve isolation so one failure cannot mask subsequent failures.
				target.state = before.duplicate(true)

func collect(value: Variant, path: Array, fields: Array) -> void:
	if not path.is_empty():
		if path[-1] is String and path[-1] == "value" and path.has("patches"): return
		fields.append({"path": path.duplicate(), "value": value})
		# These are required containers, but their child fields are model-owned.
		if path[-1] in ["flags", "provenance"]: return
	if value is Dictionary:
		for key in value:
			var child := path.duplicate(); child.append(key)
			collect(value[key], child, fields)
	elif value is Array:
		for index in range(value.size()):
			var child := path.duplicate(); child.append(index)
			collect(value[index], child, fields)

func bad_types(value: Variant) -> Array:
	if value is Dictionary: return [null, true, "invalid", 1, []]
	if value is Array: return [null, true, "invalid", 1, {}]
	if value is String: return [null, true, 1, [], {}]
	if value is bool: return [null, "true", 1, [], {}]
	if value is int or value is float: return [null, true, "invalid", [], {}]
	return []

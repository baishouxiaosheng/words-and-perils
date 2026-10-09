extends SceneTree
## Render-consumer recovery checks only; no terrain scoring or gameplay rules.
const Game = preload("res://core/game_state.gd")
const Generator = preload("res://core/world_generator.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	var game = generated_game(726381)
	var request: Dictionary = game.request("保留完整生成快照", Vector2i.ZERO).request
	game.apply_planning(plan(request))
	game.roll_action(request.action_id, 9)
	var valid: Dictionary = game.state.duplicate(true)
	check(roundtrip(valid), "Valid generated rolled save roundtrips exactly")
	for field in ["generator_version", "seed", "board_radius", "hexes", "river_edges", "roads", "settlements"]:
		var corrupt := valid.duplicate(true)
		corrupt.generated_world.erase(field)
		reject(corrupt, "Missing mandatory generated field " + field)
	for field in ["elevation", "raw_elevation", "fill_depth"]:
		var corrupt := valid.duplicate(true)
		corrupt.generated_world.hexes["0,0"].erase(field)
		reject(corrupt, "Missing numeric cache field " + field)
	for case in [
		[["generated_world"], {}, "Empty generated object"],
		[["generated_world", "generator_version"], "future_macro_v2", "Unsupported future generator version", "supported version: macro_hex_v1"],
		[["generated_world", "seed"], 3.5, "Fractional seed"],
		[["generated_world", "board_radius"], 10, "Radius differs from canonical board"],
		[["generated_world", "hexes"], {}, "Incomplete generated board cache"],
		[["generated_world", "hexes", "0,0", "q"], 4294967296, "Wrapped cache coordinate"],
		[["generated_world", "hexes", "0,0", "id"], "other_id", "Changed cache stable ID"],
		[["generated_world", "river_edges", 0, "from_hex"], [0], "Short river coordinate array"],
		[["generated_world", "river_edges", 0, "to_hex"], [99, 99], "Off-board river endpoint"],
		[["generated_world", "river_edges", 0, "width"], 0, "Zero-width river geometry"],
		[["generated_world", "river_edges", 0, "width"], -1, "Negative-width river geometry"],
		[["generated_world", "river_edges", 0, "from"], "99,99", "Mismatched river key"],
		[["generated_world", "roads", 0, "path"], ["0,0"], "Road lacks two segment endpoints"],
		[["generated_world", "roads", 0, "path"], ["0,0", "3,0"], "Disconnected road segment"],
		[["generated_world", "roads", 0, "path"], ["0,0", "99,99"], "Road references missing tile"],
		[["generated_world", "roads", 0, "path"], ["0,0", 1], "Road references numeric key"],
		[["generated_world", "roads", 0, "from_settlement"], "unknown_site", "Unknown road site reference"],
		[["generated_world", "settlements", 0, "id"], "unsafe/site", "Slash in settlement node ID"],
		[["generated_world", "settlements", 0, "id"], "unsafe:site", "Colon in settlement node ID"],
		[["generated_world", "settlements", 0, "id"], "unsafe\\site", "Backslash in settlement node ID"],
		[["generated_world", "settlements", 0, "hex_key"], "99,99", "Mismatched settlement key"],
		[["generated_world", "settlements", 0, "hex"], [99, 99], "Off-board settlement"],
		[["hexes", "0,0", "road_neighbors"], ["99,99"], "Invalid canonical road neighbor"],
		[["pending_actions", request.action_id, "snapshot", "generated_world"], {}, "Malformed internal generation snapshot"]
	]:
		var corrupt := valid.duplicate(true)
		mutate(corrupt, case[0], case[1])
		reject(corrupt, case[2], case[3] if case.size() > 3 else "")
	for collection in ["settlements", "roads", "river_edges"]:
		var corrupt := valid.duplicate(true)
		corrupt.generated_world[collection][1].id = corrupt.generated_world[collection][0].id
		reject(corrupt, "Duplicate " + collection + " stable ID")
	# Wrong types across every mandatory consumer field. Five safe JSON shapes
	# exercise type guards, so rejection itself must not throw script errors.
	for path in [
		["generated_world"], ["generated_world", "generator_version"], ["generated_world", "seed"], ["generated_world", "board_radius"],
		["generated_world", "hexes"], ["generated_world", "river_edges"], ["generated_world", "roads"], ["generated_world", "settlements"],
		["generated_world", "hexes", "0,0"], ["generated_world", "hexes", "0,0", "id"], ["generated_world", "hexes", "0,0", "q"], ["generated_world", "hexes", "0,0", "r"], ["generated_world", "hexes", "0,0", "terrain"],
		["generated_world", "hexes", "0,0", "elevation"], ["generated_world", "hexes", "0,0", "raw_elevation"], ["generated_world", "hexes", "0,0", "fill_depth"],
		["generated_world", "hexes", "0,0", "bridge"], ["generated_world", "hexes", "0,0", "road_neighbors"], ["generated_world", "hexes", "0,0", "settlement_id"],
		["generated_world", "river_edges", 0], ["generated_world", "river_edges", 0, "from_hex"], ["generated_world", "river_edges", 0, "to_hex"], ["generated_world", "river_edges", 0, "from_elevation"], ["generated_world", "river_edges", 0, "to_elevation"], ["generated_world", "river_edges", 0, "width"], ["generated_world", "river_edges", 0, "from"], ["generated_world", "river_edges", 0, "to"], ["generated_world", "river_edges", 0, "id"],
		["generated_world", "roads", 0], ["generated_world", "roads", 0, "path"], ["generated_world", "roads", 0, "from"], ["generated_world", "roads", 0, "to"], ["generated_world", "roads", 0, "id"], ["generated_world", "roads", 0, "from_settlement"],
		["generated_world", "settlements", 0], ["generated_world", "settlements", 0, "id"], ["generated_world", "settlements", 0, "name"], ["generated_world", "settlements", 0, "kind"], ["generated_world", "settlements", 0, "hex"], ["generated_world", "settlements", 0, "hex_key"],
		["hexes", "0,0", "bridge"], ["hexes", "0,0", "road_neighbors"], ["hexes", "0,0", "settlement_id"], ["hexes", "0,0", "elevation"]
	]:
		var original: Variant = valid
		for key in path: original = original[key]
		for replacement in bad_types(original):
			var corrupt := valid.duplicate(true)
			mutate(corrupt, path, replacement)
			reject(corrupt, str(path) + " with " + type_string(typeof(replacement)))
	game = generated_game(-91)
	game.state.generated_world["unknown_campaign"] = {"details": ["preserved", true, null, 0.375]}
	game.state.generated_world.hexes["0,0"]["unknown_cave"] = {"description": "GM-defined"}
	game.state.generated_world.hexes["0,0"].terrain = "GM-defined cached terrain"
	game.state.generated_world.hexes["0,0"].elevation = 0.375
	game.state.hexes["0,0"].terrain = "different canonical GM terrain"
	game.state.hexes["0,0"].elevation = 0.625
	game.state.generated_world.settlements[0].kind = "GM-defined settlement kind"
	check(roundtrip(game.state), "Negative seed, unknown extensions, free-text terrain/kind and different finite cached/canonical geometry remain valid")
	for key in game.state.generated_world.hexes:
		for field in ["bridge", "road_neighbors", "settlement_id"]: game.state.generated_world.hexes[key].erase(field)
	for key in game.state.hexes:
		for field in ["bridge", "road_neighbors", "settlement_id"]: game.state.hexes[key].erase(field)
	check(roundtrip(game.state), "Optional render fields may be absent and keep renderer defaults")
	game = generated_game(726381)
	game.state.generated_world.river_edges = []
	game.state.generated_world.roads = []
	game.state.generated_world.settlements = []
	check(roundtrip(game.state), "Empty infrastructure arrays are valid; no geography or sites are fabricated")
	check(roundtrip(Game.new().state), "Original 61-cell state without generated metadata remains valid")
	var live = Game.new()
	var protected_path := "user://qa_metadata_protected_save.json"
	live.save_to_file(protected_path)
	var bytes := FileAccess.get_file_as_string(protected_path)
	live.state = valid.duplicate(true); live.state.generated_world = {}
	check(not live.save_to_file(protected_path).ok and FileAccess.get_file_as_string(protected_path) == bytes, "Malformed generated state cannot replace an existing good save")
	for failure in failures: printerr("FAIL: " + failure)
	print("GENERATED METADATA RECOVERY: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func generated_game(seed: int):
	var generated := Generator.generate(seed, 7)
	var game = Game.new()
	game.state.board_radius = generated.board_radius
	game.state.hexes = generated.hexes.duplicate(true)
	game.state.generated_world = generated.duplicate(true)
	for id in generated.actor_spawn_hexes: game.state.actors[id].hex = generated.actor_spawn_hexes[id].duplicate()
	return game

func plan(request: Dictionary) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "待确认的计划。", "context": "Integrity fixture", "needs_roll": true, "difficulty": 9}

func reject(corrupt: Dictionary, label: String, required_reason: String = "") -> void:
	var path := "user://qa_generated_metadata_invalid.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt)); file.close()
	var target = Game.new()
	var request: Dictionary = target.request("存档拒绝时仍需保留的行动", Vector2i.ZERO).request
	target.apply_planning(plan(request)); target.roll_action(request.action_id, 12)
	var before: Dictionary = target.state.duplicate(true)
	var loaded: Dictionary = target.load_from_file(path)
	check(not loaded.ok and target.state == before and (required_reason.is_empty() or str(loaded.get("errors", [])).contains(required_reason)), label)

func roundtrip(value: Dictionary) -> bool:
	var source = Game.new(); source.state = value.duplicate(true)
	var target = Game.new()
	var path := "user://qa_generated_metadata_valid.json"
	return source.save_to_file(path).ok and target.load_from_file(path).ok and source.state == target.state

func mutate(value: Dictionary, path: Array, replacement: Variant) -> void:
	var node: Variant = value
	for index in range(path.size() - 1): node = node[path[index]]
	node[path[-1]] = replacement

func bad_types(value: Variant) -> Array:
	if value is Dictionary: return [null, true, "invalid", 1, []]
	if value is Array: return [null, true, "invalid", 1, {}]
	if value is String: return [null, true, 1, [], {}]
	if value is bool: return [null, "true", 1, [], {}]
	if value is int or value is float: return [null, true, "invalid", [], {}]
	return []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

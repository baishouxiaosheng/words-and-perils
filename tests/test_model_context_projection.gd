extends SceneTree
## Export-only duplicate removal. Complete exact saves are deliberately retained.
const Game = preload("res://core/game_state.gd")
const Generator = preload("res://core/world_generator.gd")
const Relay = preload("res://core/json_relay_provider.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	for radius in [7, 10]: test_generated(radius)
	test_extensions_and_versions()
	test_original_fixture()
	for failure in failures: printerr("FAIL: " + failure)
	print("MODEL CONTEXT PROJECTION: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func generated_game(radius: int):
	var generated := Generator.generate(726381, radius)
	var game = Game.new()
	game.state.hexes = generated.hexes.duplicate(true)
	game.state.board_radius = generated.board_radius
	game.state.generated_world = generated.duplicate(true)
	for id in generated.actor_spawn_hexes: game.state.actors[id].hex = generated.actor_spawn_hexes[id].duplicate()
	return game

func test_generated(radius: int) -> void:
	var game = generated_game(radius)
	var request: Dictionary = game.request("观察聚落附近的道路与河流", Vector2i.ZERO).request
	var action_id: String = request.action_id
	var internal: Dictionary = game.state.pending_actions[action_id].snapshot.duplicate(true)
	var expected_state: Dictionary = game.state.duplicate(true)
	var generated: Dictionary = internal.generated_world
	check(internal.generated_world.hexes == internal.hexes, "r%d internal snapshot retains the complete rendering cache" % radius)
	check(request.snapshot.hexes == internal.hexes and request.snapshot.hexes.size() == 1 + 3 * radius * (radius + 1), "r%d all exact canonical cells and every per-hex field reach GM" % radius)
	for key in internal:
		if key != "generated_world": check(request.snapshot[key] == internal[key], "r%d snapshot field %s unchanged" % [radius, key])
	check(not request.snapshot.generated_world.has("hexes"), "r%d identical known duplicate cell cache omitted" % radius)
	check(not request.snapshot.generated_world.hydrology.has("river_edges"), "r%d identical known hydrology edge duplicate omitted" % radius)
	for key in generated:
		if key not in ["hexes", "hydrology"]: check(request.snapshot.generated_world[key] == generated[key], "r%d generated %s semantics unchanged" % [radius, key])
	for key in generated.hydrology:
		if key != "river_edges": check(request.snapshot.generated_world.hydrology[key] == generated.hydrology[key], "r%d hydrology %s retained" % [radius, key])
	check(request.gm_contract.get("snapshot_projection", "").contains("complete current board"), "r%d GM receives explicit cache deduplication note" % radius)
	check(game.state == expected_state, "r%d exporting cannot mutate live state or the full internal snapshot" % radius)
	request.snapshot.hexes["0,0"].terrain = "mutated exported value"
	request.snapshot.generated_world.settlements[0].name = "mutated exported site"
	check(game.state == expected_state, "r%d projected request remains fully detached" % radius)
	var path := "user://qa_projection_%d.json" % radius
	var restored = Game.new()
	check(game.save_to_file(path).ok and restored.load_from_file(path).ok and restored.state == game.state, "r%d full generated save and internal snapshot roundtrip exactly" % radius)
	var resumed: Dictionary = restored.resume_request(action_id).request
	check(resumed.snapshot == game._model_snapshot(internal), "r%d reload produces the same projected planning context" % radius)
	check(restored.apply_planning(plan(resumed, true)).ok, "r%d GM planning remains compatible with structural validation" % radius)
	var rolled: Dictionary = restored.roll_action(action_id, 9)
	check(rolled.ok and rolled.request.snapshot == resumed.snapshot and rolled.request.context.player_roll.value == 9, "r%d resolution receives identical world snapshot plus exact retained die" % radius)
	expected_state = restored.state.duplicate(true)
	check(restored.save_to_file(path).ok, "r%d rolled save remains valid despite export projection" % radius)
	var rolled_restore = Game.new()
	check(rolled_restore.load_from_file(path).ok and rolled_restore.state == expected_state, "r%d rolled save restores the full unprojected snapshot" % radius)
	var resolution_request: Dictionary = rolled_restore.resume_request(action_id).request
	check(resolution_request.snapshot == resumed.snapshot and resolution_request.roll.d20 == 9, "r%d resumed resolution retains projected geography and exact die" % radius)
	var final := {"schema_version": 1, "action_id": action_id, "state_version": 0, "phase": "resolution", "narration": "仅为完整性夹具。", "outcome": "GM-defined", "patches": [{"op": "set", "path": "/hexes/0,0/terrain", "value": "GM 定义的新地形"}]}
	check(rolled_restore.commit_decision(final).ok, "r%d final GM terrain patch still validates against full internal facts" % radius)
	var next: Dictionary = rolled_restore.request("检查改变后的地点", Vector2i.ZERO).request
	check(next.snapshot.hexes["0,0"].terrain == "GM 定义的新地形" and next.snapshot.generated_world.hexes["0,0"].terrain == generated.hexes["0,0"].terrain, "r%d differing initial-generation metadata is preserved alongside authoritative changed terrain" % radius)
	check(next.snapshot.events == rolled_restore.state.events, "r%d full untruncated event history reaches subsequent requests" % radius)
	check(rolled_restore.apply_planning(plan(next, false)).request.snapshot == next.snapshot, "r%d no-roll resolution uses the same projection" % radius)

func test_extensions_and_versions() -> void:
	var game = generated_game(7)
	game.state["campaign_custom"] = {"description": "unknown top-level exact field", "details": [true, null, 0.375]}
	game.state.hexes["0,0"]["gm_passage"] = {"description": "unknown per-hex rule evidence"}
	game.state.generated_world["gm_campaign"] = {"instructions": "unknown generation extension"}
	game.state.generated_world.hexes["0,0"]["gm_cache_only"] = ["unknown", 0.125]
	game.state.generated_world.hexes["0,0"]["gm_passage"] = game.state.hexes["0,0"].gm_passage.duplicate(true)
	game.state.hexes["0,0"].moisture = "GM-defined qualitative moisture"
	game.state.generated_world.hydrology["gm_river_extension"] = {"description": "preserve unknown nested data"}
	var request: Dictionary = game.request("自定义上下文", Vector2i.ZERO).request
	var projected: Dictionary = request.snapshot
	check(projected.campaign_custom == game.state.campaign_custom, "Unknown top-level GM fields preserved")
	check(projected.hexes == game.state.hexes, "Canonical known and unknown per-hex fields preserved without truncation")
	check(projected.generated_world.gm_campaign == game.state.generated_world.gm_campaign, "Unknown generation extension preserved")
	check(projected.generated_world.hexes["0,0"].gm_cache_only == ["unknown", 0.125], "Unknown cache-only fields preserved at original path")
	check(projected.generated_world.hexes["0,0"].gm_passage == game.state.hexes["0,0"].gm_passage, "Even identical unknown cache extensions are preserved")
	check(projected.generated_world.hexes["0,0"].id == "hex_0_0" and projected.generated_world.hexes["0,0"].q == 0 and projected.generated_world.hexes["0,0"].r == 0, "Residual cache data retains stable coordinate identity")
	check(projected.generated_world.hexes["0,0"].moisture == game.state.generated_world.hexes["0,0"].moisture and projected.hexes["0,0"].moisture is String, "Different known-field types retained without unsafe mixed-type comparison")
	check(projected.generated_world.hydrology.gm_river_extension == game.state.generated_world.hydrology.gm_river_extension, "Unknown hydrology extensions preserved")
	var path := "user://qa_projection_extensions.json"
	var restored = Game.new()
	check(game.save_to_file(path).ok and restored.load_from_file(path).ok and restored.state == game.state, "Custom fields and differing cache values roundtrip unchanged")
	game = generated_game(7)
	var edges: Array = game.state.generated_world.river_edges
	check(not edges.is_empty(), "Fixture contains directed rivers")
	game.state.generated_world.hydrology.river_edges[0]["gm_edge_extension"] = "preserve at original location"
	game.state.generated_world.river_edges[0]["gm_edge_extension"] = "preserve at original location"
	projected = game.request("自定义河流", Vector2i.ZERO).request.snapshot
	check(projected.generated_world.hydrology.river_edges == game.state.generated_world.hydrology.river_edges, "Unknown edge fields prevent omission even when full duplicate arrays agree")
	check(projected.generated_world.river_edges == game.state.generated_world.river_edges, "Primary directed river semantics remain complete")
	game = generated_game(7)
	game.state.generated_world.hydrology.river_edges[0].width = 999
	projected = game.request("不同的河流缓存", Vector2i.ZERO).request.snapshot
	check(projected.generated_world.hydrology.river_edges[0].width == 999, "Differing hydrology cache values are never silently discarded")
	for version in ["future_macro_v2", "", 7, null]:
		game = generated_game(7)
		game.state.generated_world.generator_version = version
		request = game.request("未知生成版本", Vector2i.ZERO).request
		check(request.snapshot == game.state.pending_actions[request.action_id].snapshot and not request.gm_contract.has("snapshot_projection"), "Unrecognized generator version remains entirely unchanged: " + str(version))
	game = generated_game(7)
	game.state.flags["generated_world"] = game.state.generated_world.duplicate(true)
	request = game.request("未知标记内容", Vector2i.ZERO).request
	check(request.snapshot.flags == game.state.flags, "Unknown GM-controlled flags are never projected or summarized")

func test_original_fixture() -> void:
	var game = Game.new()
	var request: Dictionary = game.request("喝下雾行药剂，穿过浅水走到那里，再试着说服守卫放下武器。", Vector2i(1, -1)).request
	check(request.snapshot == game.state.pending_actions[request.action_id].snapshot and request.snapshot.hexes.size() == 61 and not request.gm_contract.has("snapshot_projection"), "Original 61-cell recorded context is unchanged")
	var relay = Relay.new()
	var replay: Dictionary = relay.recorded_example_for(request, "res://tests/recorded_compound_planning.json")
	check(replay.ok and game.apply_planning(replay.decision).ok, "Recorded planning still matches the original exact snapshot")
	var rolled: Dictionary = game.roll_action(request.action_id, 9)
	var final: Dictionary = relay.recorded_example_for(rolled.request, "res://tests/recorded_compound_resolution_d20_9.json")
	check(final.ok and game.commit_decision(final.decision).ok, "Recorded resolution still matches original context and commits once")

func plan(request: Dictionary, needs_roll: bool) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "尚待确认的意图。", "context": "Integrity fixture only.", "needs_roll": needs_roll, "difficulty": 8.125}

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed: failures.append(message)

extends SceneTree

const Generator = preload("res://core/world_generator.gd")
const GameState = preload("res://core/game_state.gd")
var checks := 0
var failures: Array = []
var timings: Array = []

func _initialize() -> void:
	_run()
	_check(checks > 10000, "full invariant suite reached completion, not aborted by runtime error")
	var evidence := {"godot_version": Engine.get_version_info().string, "assertions": checks, "failures": failures, "measurements": timings, "scope": "generator plus model-state roundtrip, no graphics or live model API measurement"}
	var file := FileAccess.open("res://tests/world_generation_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t", true, true))
		file.close()
	if failures.is_empty():
		print("WORLD GENERATOR TESTS PASSED: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + str(failure))
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _hex(cell: Dictionary) -> Vector2i:
	return Vector2i(cell.q, cell.r)

func _run() -> void:
	var original := GameState.new()
	_check(original.state.board_radius == 4 and original.state.hexes.size() == 61, "recorded demonstration fixture remains radius4/61hex")
	_check(original.state.actors.actor_player.hex == [-2, 1] and original.state.hexes["0,0"].terrain == "bridge", "recorded starting position and bridge unchanged")
	var first: Dictionary = Generator.generate(726381, 10)
	var repeated: Dictionary = Generator.generate(726381, 10)
	_check(JSON.stringify(first, "", true, true) == JSON.stringify(repeated, "", true, true), "same seed/radius/config produces byte-identical serialized content")
	_check(first.content_hash != Generator.generate(726382, 10).content_hash, "different seed changes content hash")
	_check(first.hexes["0,0"].raw_elevation != Generator.generate(726382, 10).hexes["0,0"].raw_elevation, "different seed changes geography, not only seed metadata")
	repeated.hexes["0,0"].elevation = -999
	_check(first.hexes["0,0"].elevation != -999, "generated values are detached")
	_check(Generator.generate(1, -20).board_radius == Generator.MIN_RADIUS, "negative radius is bounded")
	_check(Generator.generate(1, 999).board_radius == Generator.MAX_RADIUS, "huge radius is bounded")
	for radius in [4, 8, 10, 16, 24]:
		for seed_value in [0, 1, -91, 726381, 2147483659]:
			var started := Time.get_ticks_usec()
			var world: Dictionary = Generator.generate(seed_value, radius)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			timings.append({"seed": seed_value, "radius": radius, "milliseconds": elapsed, "statistics": world.statistics, "hash": world.content_hash})
			_validate_world(world)
			print("seed=%d radius=%d cells=%d rivers=%d cities=%d roads=%d generation_ms=%.2f" % [seed_value, radius, world.hexes.size(), world.river_edges.size(), world.settlements.size(), world.roads.size(), elapsed])
	_validate_model_roundtrip(first)
	_validate_sampler(first)
	var configured: Dictionary = Generator.generate(91, 7, {"settlement_count": 8, "river_threshold": 3.0})
	_validate_world(configured)
	_check(configured.settlements.size() == 8, "explicit settlement count honored where suitable sites exist")
	var invalid_options: Dictionary = Generator.generate(1, 7, {"settlement_count": "wrong", "river_threshold": NAN, "settlement_max_slope": INF, "road_max_slope": []})
	_check(invalid_options.config.settlement_count == 4 and invalid_options.config.river_threshold == snappedf(5.6, Generator.SERIAL_QUANTUM), "invalid config types/nonfinite values use bounded defaults")
	_validate_world(invalid_options)

func _validate_world(world: Dictionary) -> void:
	var label := "seed=%d/r=%d " % [world.seed, world.board_radius]
	var cells: Dictionary = world.hexes
	_check(cells.size() == 1 + 3 * world.board_radius * (world.board_radius + 1), label + "exact radius cell count")
	_check(world.settlements.size() >= 2, label + "at least two safe settlement sites")
	_check(world.roads.size() == maxi(0, world.settlements.size() - 1), label + "settlement road tree has n-1 connections")
	_check(not world.river_edges.is_empty(), label + "river network is nonempty")
	_check(not world.mountain_regions.is_empty(), label + "macro mountain range is nonempty")
	var mountain_cells := 0
	for region in world.mountain_regions:
		mountain_cells += region.hex_keys.size()
	_check(mountain_cells >= world.board_radius, label + "mountains form a meaningful highland region")
	for key in cells:
		var cell: Dictionary = cells[key]
		_check(cell.id == "hex_%d_%d" % [cell.q, cell.r] and key == Generator.hex_key(_hex(cell)), label + "canonical hex identity " + key)
		_check(Generator.hex_distance(Vector2i.ZERO, _hex(cell)) <= world.board_radius, label + "in-radius hex " + key)
		_check(is_finite(float(cell.elevation)) and is_finite(float(cell.slope)) and is_finite(float(cell.flow_accumulation)), label + "finite geography " + key)
		if not String(cell.flow_to).is_empty():
			_check(cells.has(cell.flow_to), label + "flow target exists " + key)
			var next: Dictionary = cells[cell.flow_to]
			_check(Generator.hex_distance(_hex(cell), _hex(next)) == 1, label + "flow is neighboring " + key)
			_check(float(cell.drainage_elevation) > float(next.drainage_elevation), label + "directed drainage strictly downhill " + key)
			_check(float(cell.elevation) > (0.0 if next.ocean else float(next.elevation)), label + "displayed land elevation also downhill " + key)
			_check(next.flow_from.has(key), label + "flow reciprocal upstream list " + key)
			_check(float(next.flow_accumulation) >= float(cell.flow_accumulation), label + "rainfall never decreases downstream " + key)
		# Independent cycle/outlet check, not just assuming the height invariant.
		var seen: Dictionary = {}
		var cursor: String = key
		while not cursor.is_empty() and not seen.has(cursor):
			seen[cursor] = true
			cursor = cells[cursor].flow_to
		_check(cursor.is_empty(), label + "no drainage cycle " + key)
		for next_key in cell.road_neighbors:
			_check(cells.has(next_key) and cells[next_key].road_neighbors.has(key), label + "road reciprocal neighboring list " + key)
	for edge in world.river_edges:
		_check(cells.has(edge.from) and cells.has(edge.to), label + "river edge endpoints exist")
		_check(Generator.hex_distance(_hex(cells[edge.from]), _hex(cells[edge.to])) == 1, label + "river edge has no gaps")
		_check(float(edge.from_elevation) > float(edge.to_elevation), label + "river surface descends")
		_check(cells[edge.from].river_to == edge.to and cells[edge.to].river_from.has(edge.from), label + "river direction agrees with cell metadata")
		_check(cells[edge.to].ocean or cells[edge.to].river, label + "river continues to another river or sea")
		_check(cells[edge.from].flow_to == edge.to, label + "river follows drainage, no arbitrary adjacency")
		var terminal: String = edge.to
		var steps := 0
		while cells[terminal].river and not String(cells[terminal].river_to).is_empty() and steps < cells.size():
			terminal = cells[terminal].river_to
			steps += 1
		_check(cells[terminal].ocean or world.hydrology.outlets.has(terminal), label + "river terminates only at sea/boundary")
	var settlements_by_id: Dictionary = {}
	for settlement in world.settlements:
		settlements_by_id[settlement.id] = settlement
		var cell: Dictionary = cells[settlement.hex_key]
		_check(not cell.ocean and not cell.river and cell.terrain not in ["mountain", "swamp"], label + "settlement is dry and suitable")
		_check(float(cell.slope) <= float(world.config.settlement_max_slope), label + "settlement slope allowed")
		_check(cell.settlement_id == settlement.id and settlement.hex == [cell.q, cell.r], label + "settlement refers to canonical model hex")
		_check(not settlement.road_ids.is_empty(), label + "every settlement connected by road")
	var road_adjacency: Dictionary = {}
	for road in world.roads:
		_check(settlements_by_id.has(road.from_settlement) and settlements_by_id.has(road.to_settlement), label + "road settlement IDs valid")
		_check(road.path[0] == road.from and road.path[-1] == road.to, label + "road reaches exact endpoint hexes")
		if not road_adjacency.has(road.from_settlement): road_adjacency[road.from_settlement] = []
		if not road_adjacency.has(road.to_settlement): road_adjacency[road.to_settlement] = []
		road_adjacency[road.from_settlement].append(road.to_settlement)
		road_adjacency[road.to_settlement].append(road.from_settlement)
		for index in range(road.path.size()):
			var cell: Dictionary = cells[road.path[index]]
			_check(not cell.ocean and cell.road and float(cell.slope) <= float(world.config.road_max_slope), label + "road avoids water and impassable grade")
			if index > 0:
				_check(Generator.hex_distance(_hex(cell), _hex(cells[road.path[index - 1]])) == 1, label + "road path continuous")
			if cell.river:
				_check(cell.bridge and cell.terrain == "bridge" and road.bridge_hexes.has(road.path[index]), label + "river road crossings have explicit bridge metadata")
	var visited: Dictionary = {}
	var queue: Array = [world.settlements[0].id] if not world.settlements.is_empty() else []
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if visited.has(current): continue
		visited[current] = true
		queue.append_array(road_adjacency.get(current, []))
	_check(visited.size() == world.settlements.size(), label + "all settlements are mutually connected")
	for actor_id in world.actor_spawn_hexes:
		var coordinates: Array = world.actor_spawn_hexes[actor_id]
		var key := Generator.hex_key(Vector2i(coordinates[0], coordinates[1]))
		_check(cells.has(key) and not cells[key].ocean and not cells[key].river and cells[key].terrain != "mountain", label + "stable actor spawn dry/valid " + actor_id)
	_check(world.actor_spawn_hexes.actor_player != world.actor_spawn_hexes.actor_sentinel, label + "actors have distinct spawn sites")

func _validate_model_roundtrip(world: Dictionary) -> void:
	var game := GameState.new()
	game.state.board_radius = world.board_radius
	game.state.hexes = world.hexes.duplicate(true)
	game.state.flags.generated_world = {
		"seed": world.seed, "generator_version": world.generator_version,
		"content_hash": world.content_hash, "macro_landscape": world.macro_landscape,
		"hydrology": world.hydrology, "settlements": world.settlements,
		"roads": world.roads, "mountain_regions": world.mountain_regions
	}
	for actor_id in world.actor_spawn_hexes:
		game.state.actors[actor_id].hex = world.actor_spawn_hexes[actor_id].duplicate()
	var path := "user://generator_model_roundtrip.json"
	var saved: Dictionary = game.save_to_file(path)
	_check(saved.ok, "full generator data satisfies exact model validator and saves")
	var loaded := GameState.new()
	var restored: Dictionary = loaded.load_from_file(path)
	_check(restored.ok, "generated model-state save reloads")
	_check(JSON.stringify(game.state, "", true, true) == JSON.stringify(loaded.state, "", true, true), "generated geography, roads, river directions and spawns roundtrip exactly")
	var asked: Dictionary = loaded.request("沿河观察，尝试用绳索搭建临时跨越点", Vector2i(0, 0))
	_check(asked.ok and asked.request.preview.advisory_only, "generated geography keeps all gameplay adjudication with external GM")
	_check(asked.request.snapshot.flags.generated_world.hydrology.river_edges.size() == world.river_edges.size(), "GM snapshot includes directed river context")

func _validate_sampler(world: Dictionary) -> void:
	var field = Generator.create_height_field(world.seed, world.board_radius)
	for key in world.hexes:
		var cell: Dictionary = world.hexes[key]
		var point := Generator.hex_center(_hex(cell))
		_check(absf(field.sample_visual_height(point) - float(cell.raw_elevation)) <= Generator.SERIAL_QUANTUM, "sampler matches original upstream macro field at " + key)
	field.configure_visual_world(world)
	for key in world.hexes:
		var cell: Dictionary = world.hexes[key]
		var point := Generator.hex_center(_hex(cell))
		_check(absf(field.sample_visual_height(point) - float(cell.elevation)) <= Generator.SERIAL_QUANTUM * 2.0, "conditioned visual sampler matches saved hex elevation at " + key)
		_check(field.sample_visual_height(point) == field.sample_visual_height(Vector3(point.x, 0.0, point.y)), "Vector2 and Vector3 use identical world-space field at " + key)
	# Arbitrary shared edge samples match across callers, including tiny
	# perturbations near interpolation triangle boundaries.
	var before: float = field.sample_visual_height(Vector2(0.2, 0.3))
	_check(before == field.sample_visual_height(Vector2(0.2, 0.3)), "repeated shared vertex sample is deterministic")
	_check(absf(field.sample_visual_height(Vector2(0.2, 0.3) + Vector2(0.00001, 0.0)) - before) < 0.001, "continuous macro height across nearby world-space samples")
	var started := Time.get_ticks_usec()
	var sum := 0.0
	for index in range(10000):
		sum += field.sample_visual_height(Vector2(float(index % 100) * 0.2 - 10.0, float(index / 100) * 0.2 - 10.0))
	_check(is_finite(sum), "10000 efficient macro vertex samples remain finite")
	timings.append({"kind": "10000_continuous_vertex_samples", "milliseconds": (Time.get_ticks_usec() - started) / 1000.0, "radius": world.board_radius})

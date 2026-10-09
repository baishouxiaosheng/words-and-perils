extends RefCounted
## Independent, bounded quality gates for the existing reproducible macro recipe.
## Structural clearance is NOT renderer clearance; gameplay admission remains separate.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator = preload("res://core/world_generator.gd")
const ID := "macro_preset_validation/v1"
const SOURCE_FIELDS := ["actor_spawn_hexes", "board_radius", "config", "content_hash", "generator_version", "hexes", "hydrology", "macro_landscape", "mountain_regions", "river_edges", "roads", "seed", "settlements", "statistics"]
const MAX_BYTES := 4 * 1024 * 1024
const SEED_LIMIT := 2147483647
const BIOMES := ["ocean", "grassland", "desert", "temperate_forest", "jungle", "alpine", "wetland"]

static func validate_source(value: Variant) -> Dictionary:
	if not C.exact_fields(value, SOURCE_FIELDS) or not C.safe(value):
		return C.fail("SEED_SOURCE_SCHEMA", "Expected a JSON-safe, exact macro source envelope.")
	if value.generator_version != Generator.BIOMES_VERSION or not C.integer(value.seed) or absf(float(value.seed)) > SEED_LIMIT:
		return C.fail("SEED_SOURCE_VERSION", "The supported recipe requires macro_hex_biomes_v2 and an adapter-safe signed32 seed.")
	if not C.integer(value.board_radius) or value.board_radius < 4 or value.board_radius > 24:
		return C.fail("SEED_SOURCE_RADIUS", "Radius must be an integer from 4 through 24.")
	var radius := int(value.board_radius)
	if not value.hexes is Dictionary or value.hexes.size() != 1 + 3 * radius * (radius + 1):
		return C.fail("SEED_SOURCE_CELLS", "The complete, bounded axial hex domain is required.")
	var serialized := C.bytes(value)
	if serialized.to_utf8_buffer().size() > MAX_BYTES:
		return C.fail("SEED_SOURCE_BUDGET", "Source exceeds the 4 MiB admission budget.")
	var unsigned: Dictionary = value.duplicate(true)
	unsigned.erase("content_hash")
	if not value.content_hash is String or value.content_hash != C.digest(unsigned):
		return C.fail("SEED_SOURCE_HASH", "Source hash does not match canonical content.")
	# Reproduction also protects all nested types before independent invariants
	# inspect them. A re-signed arbitrary map cannot masquerade as this recipe.
	var reproduced := Generator.generate(int(value.seed), radius, {"generator_version": Generator.BIOMES_VERSION})
	if serialized != C.bytes(reproduced):
		return C.fail("SEED_SOURCE_REPRODUCE", "Source does not reproduce under the pinned default macro recipe.")
	return _inspect_reproduced(reproduced)

static func _inspect_reproduced(world: Dictionary) -> Dictionary:
	var errors: Array = []
	var radius := int(world.board_radius)
	var cells: Dictionary = world.hexes
	var dry: Dictionary = {}
	var land_count := 0
	var ocean_count := 0
	var bridges := 0
	for key in cells:
		var cell: Dictionary = cells[key]
		var hex := Vector2i(cell.q, cell.r)
		_check(key == Generator.hex_key(hex) and cell.id == "hex_%d_%d" % [cell.q, cell.r] and Generator.hex_distance(Vector2i.ZERO, hex) <= radius, errors, "Cell identity/domain mismatch: " + key)
		_check(cell.biome in BIOMES, errors, "Unsupported biome: " + key)
		for metric in ["raw_elevation", "elevation", "slope", "moisture", "temperature", "fill_depth", "drainage_elevation", "flow_accumulation", "plateau_weight", "plateau_height"]:
			var number := float(cell[metric])
			_check(is_finite(number) and number * 4096 == roundf(number * 4096), errors, "Nonfinite/nonquantized " + metric + ": " + key)
		if cell.ocean: ocean_count += 1
		else: land_count += 1
		if not cell.ocean and not cell.river and cell.terrain != "mountain" and float(cell.slope) <= float(world.config.road_max_slope): dry[key] = true
		if cell.bridge:
			bridges += 1
			_check(cell.river and cell.road and cell.terrain == "bridge", errors, "Bridge lacks explicit river and road: " + key)
		if not String(cell.flow_to).is_empty():
			_check(_adjacent(cells, key, cell.flow_to), errors, "Drainage leaves world or skips a cell: " + key)
			if cells.has(cell.flow_to):
				_check(float(cell.drainage_elevation) > float(cells[cell.flow_to].drainage_elevation), errors, "Drainage does not strictly descend: " + key)
		for neighbor in cell.road_neighbors:
			_check(_adjacent(cells, key, neighbor) and cells.get(neighbor, {}).get("road_neighbors", []).has(key), errors, "Road edge is not reciprocal/in-world: " + key)
	_check(land_count >= radius * 3 and ocean_count >= 3, errors, "Coastal preset lacks a usable land/sea domain.")
	_check(not world.river_edges.is_empty(), errors, "Coastal preset lacks a river network.")
	for edge in world.river_edges:
		_check(_adjacent(cells, edge.from, edge.to), errors, "River leaves world or skips a cell.")
		if cells.has(edge.from) and cells.has(edge.to):
			_check(cells[edge.from].flow_to == edge.to and cells[edge.from].river_to == edge.to and cells[edge.to].river_from.has(edge.from), errors, "River and drainage topology disagree.")
			_check(float(edge.from_elevation) > float(edge.to_elevation), errors, "River surface is not downhill.")
			_check(cells[edge.to].ocean or cells[edge.to].river, errors, "River terminates without a sea/outlet continuation.")
	# Strict downhill edges prove no directed cycles. Check each empty-flow
	# terminal explicitly rather than accepting an unexplained inland sink.
	for key in cells:
		var cell: Dictionary = cells[key]
		if String(cell.flow_to).is_empty():
			_check(cell.ocean or Generator.hex_distance(Vector2i.ZERO, Vector2i(cell.q, cell.r)) == radius, errors, "Unexplained inland drainage sink: " + key)
	var settlements := {}
	var settlement_edges := {}
	for settlement in world.settlements:
		var key: String = settlement.hex_key
		_check(not settlements.has(settlement.id) and cells.has(key), errors, "Invalid or duplicate settlement identity.")
		settlements[settlement.id] = settlement
		settlement_edges[settlement.id] = []
		if cells.has(key):
			var cell: Dictionary = cells[key]
			_check(not cell.ocean and not cell.river and cell.terrain not in ["mountain", "swamp"] and float(cell.slope) <= float(world.config.settlement_max_slope), errors, "Settlement lacks stable dry placement: " + key)
	_check(settlements.size() >= 2 and world.roads.size() == settlements.size() - 1, errors, "Preset requires at least two connected settlements and a road tree.")
	for road in world.roads:
		_check(settlements.has(road.from_settlement) and settlements.has(road.to_settlement) and road.path.size() >= 2, errors, "Road has invalid settlement endpoints.")
		if settlement_edges.has(road.from_settlement) and settlement_edges.has(road.to_settlement):
			settlement_edges[road.from_settlement].append(road.to_settlement)
			settlement_edges[road.to_settlement].append(road.from_settlement)
		for index in range(road.path.size()):
			var key: String = road.path[index]
			_check(cells.has(key), errors, "Road leaves world.")
			if not cells.has(key): continue
			var cell: Dictionary = cells[key]
			_check(not cell.ocean and cell.road and float(cell.slope) <= float(world.config.road_max_slope), errors, "Road crosses unsupported terrain: " + key)
			if index > 0: _check(_adjacent(cells, road.path[index - 1], key), errors, "Road path skips a cell.")
			if cell.river: _check(cell.bridge and road.bridge_hexes.has(key), errors, "River crossing lacks explicit bridge metadata: " + key)
	if not settlements.is_empty():
		_check(_graph_component(settlement_edges, settlements.keys()[0]).size() == settlements.size(), errors, "Settlement road graph is disconnected.")
	var spawn_keys: Array = []
	for actor_id in world.actor_spawn_hexes:
		var coordinates: Array = world.actor_spawn_hexes[actor_id]
		var key := "%d,%d" % coordinates
		_check(dry.has(key) and not spawn_keys.has(key), errors, "Starting actor lacks distinct conservative dry support: " + actor_id)
		spawn_keys.append(key)
	var dry_components := _components(cells, dry)
	var largest_dry: int = dry_components[0].size() if not dry_components.is_empty() else 0
	_check(largest_dry >= maxi(3, radius), errors, "No sufficiently connected conservative dry area.")
	var biome_regions := {}
	var coherent_terrestrial := 0
	for biome in BIOMES:
		var members := {}
		for key in cells:
			if cells[key].biome == biome: members[key] = true
		var components := _components(cells, members)
		var sizes: Array = []
		for component in components: sizes.append(component.size())
		biome_regions[biome] = sizes
		if biome != "ocean" and not sizes.is_empty() and sizes[0] >= maxi(2, radius / 2): coherent_terrestrial += 1
		if biome == "ocean":
			for component in components:
				var reaches_boundary := false
				for key in component:
					var cell: Dictionary = cells[key]
					if Generator.hex_distance(Vector2i.ZERO, Vector2i(cell.q, cell.r)) == radius: reaches_boundary = true
				_check(reaches_boundary, errors, "Coastal ocean label forms an isolated inland component.")
	_check(coherent_terrestrial >= 2, errors, "Preset needs two coherent terrestrial biome regions; not every biome is required.")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "SEED_QUALITY_REJECTED", "errors": errors, "diagnostics": {"validator_version": ID, "cell_count": cells.size(), "land_cells": land_count, "ocean_cells": ocean_count, "largest_conservative_dry_component": largest_dry, "biome_component_sizes": biome_regions, "coherent_terrestrial_biomes": coherent_terrestrial, "bridge_cells": bridges, "source_geometry_checked": true, "renderer_navigation_checked": false, "visual_quality_checked": false}}

static func validate_navigation(source: Dictionary, allowed: Variant, supported: Variant, start: Variant) -> Dictionary:
	# This validates a graph produced by the exact renderer-based adapter. It
	# cannot certify that a caller-supplied graph represents mesh clearance.
	if not allowed is Dictionary or not supported is Dictionary or not start is Array or start.size() != 2 or not C.integer(start[0]) or not C.integer(start[1]):
		return C.fail("SEED_NAV_SCHEMA", "Expected an exact-navigation graph and integer starting anchor.")
	var cells: Dictionary = source.get("hexes", {})
	if allowed.size() != cells.size() or supported.size() != cells.size(): return C.fail("SEED_NAV_DOMAIN", "Navigation domain does not match the source.")
	for key in cells:
		if not allowed.get(key) is Array or not supported.get(key) is bool: return C.fail("SEED_NAV_DOMAIN", "Navigation omits a source cell.")
		if allowed[key].size() > 6: return C.fail("SEED_NAV_DEGREE", "Hex navigation cannot have more than six neighbors.")
		var seen := {}
		for target in allowed[key]:
			if not target is String or seen.has(target) or not _adjacent(cells, key, target) or not supported[key] or not supported.get(target, false) or not allowed.get(target) is Array or not allowed[target].has(key):
				return C.fail("SEED_NAV_EDGE", "Navigation has duplicate, wet, asymmetric, or out-of-world edges.")
			seen[target] = true
	var start_key := "%d,%d" % start
	if not supported.get(start_key, false): return C.fail("SEED_NAV_START", "Starting anchor lacks exact dry support.")
	var reachable := _graph_component(allowed, start_key)
	if reachable.size() < maxi(3, int(source.board_radius)):
		return C.fail("SEED_NAV_COMPONENT", "Starting anchor has too little verified reachable ground.")
	return {"ok": true, "reachable_start_cells": reachable.size(), "graph_checked": true, "clearance_authority": "caller must use generated_adventure/source.gd"}

static func _check(condition: bool, errors: Array, message: String) -> void:
	if not condition and errors.size() < 32: errors.append(message)

static func _adjacent(cells: Dictionary, a: String, b: String) -> bool:
	return cells.has(a) and cells.has(b) and Generator.hex_distance(Vector2i(cells[a].q, cells[a].r), Vector2i(cells[b].q, cells[b].r)) == 1

static func _components(cells: Dictionary, members: Dictionary) -> Array:
	var seen := {}; var components: Array = []
	var keys: Array = members.keys(); keys.sort()
	for key in keys:
		if seen.has(key): continue
		var queue: Array = [key]; seen[key] = true; var index := 0
		while index < queue.size():
			var cell: Dictionary = cells[queue[index]]; index += 1
			for direction in Generator.DIRS:
				var next := Generator.hex_key(Vector2i(cell.q, cell.r) + direction)
				if members.has(next) and not seen.has(next): seen[next] = true; queue.append(next)
		components.append(queue)
	components.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size() or (a.size() == b.size() and String(a[0]) < String(b[0])))
	return components

static func _graph_component(edges: Dictionary, start: String) -> Array:
	var queue: Array = [start]; var seen := {start: true}; var index := 0
	while index < queue.size():
		var key: String = queue[index]; index += 1
		for next in edges.get(key, []):
			if not seen.has(next): seen[next] = true; queue.append(next)
	return queue

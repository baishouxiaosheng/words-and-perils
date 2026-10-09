extends RefCounted
## Bounded, seeded, upstream world generation. This authors geography only:
## no movement legality, item effects, action difficulty, or GM adjudication.
## Stages: continuous macro field -> hex samples -> drainage -> rivers ->
## settlements -> least-cost roads -> serializable renderer/model metadata.
## See docs/world_generation.md for sources, guarantees and honest limitations.

const VERSION := "macro_hex_v1"
const BIOMES_VERSION := "macro_hex_biomes_v2"
const SUPPORTED_VERSIONS := [VERSION, BIOMES_VERSION]
const BIOMES_CELL_FIELDS := ["temperature", "landform", "plateau_region", "plateau_height", "plateau_weight"]
const MIN_RADIUS := 4
const MAX_RADIUS := 24
const DEFAULT_RADIUS := 10
const DEFAULT_SEED := 726381
const SEA_LEVEL := 0.0
const FLOW_EPSILON := 1.0 / 1024.0
const SERIAL_QUANTUM := 1.0 / 4096.0
const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const NAMES := ["松湾", "白石", "河门", "青岬", "北岭", "暮溪", "榆港", "石桥"]

var _seed: int
var _radius: int
var _version := VERSION
var _config: Dictionary
var _rng := RandomNumberGenerator.new()
var _continental: FastNoiseLite
var _ridges: FastNoiseLite
var _moisture: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _coast_axis: Vector2
var _ranges: Array = []
var _climate: Dictionary = {}
var _plateaus: Array = []
var _cells: Dictionary = {}
var _keys: Array = []
var _neighbors: Dictionary = {}
var _water_distances: Dictionary = {}
var _visual_fill: Dictionary = {}

## Return a detached, JSON-safe dictionary. Radius/config inputs are bounded.
## No global RNG, wall clock, or existing state is consulted.
static func generate(world_seed: int = DEFAULT_SEED, board_radius: int = DEFAULT_RADIUS, options: Dictionary = {}) -> Dictionary:
	var generator := new()
	return generator._generate(world_seed, board_radius, options)

## Construct once per rendered world, then sample every shared mesh vertex.
## x/z use the same world-space basis as hex_center; Vector2 uses x/y as x/z.
## This prepares continuous noise/spines only, never regenerates a world.
static func create_height_field(world_seed: int = DEFAULT_SEED, board_radius: int = DEFAULT_RADIUS) -> RefCounted:
	var field := new()
	field._seed = world_seed
	field._radius = clampi(board_radius, MIN_RADIUS, MAX_RADIUS)
	field._rng.seed = world_seed
	field._configure_field()
	return field

## Optional: apply saved drainage fill as a continuous correction to the
## original macro height. Triangular interpolation is exact at hex centers.
## This does not derive mountains from cell labels or generate isolated cones.
func configure_visual_world(world: Dictionary) -> bool:
	# v1 retains its original seeded sampling path. v2 samples its stored macro
	# parameters, never a guessed/default climate or a label-derived plateau.
	var version = world.get("generator_version", VERSION)
	if not version is String or version not in SUPPORTED_VERSIONS:
		return false
	var cells = world.get("hexes")
	if not cells is Dictionary:
		return false
	for key in cells:
		var cell = cells[key]
		if not key is String or not cell is Dictionary:
			return false
		var fill = cell.get("fill_depth", 0.0)
		if not (fill is int or fill is float) or not is_finite(float(fill)):
			return false
	if version == BIOMES_VERSION:
		if not validate_biomes_macro(world.get("macro_landscape")).is_empty():
			return false
		if not _exact_integer(world.get("seed")) or not _exact_integer(world.get("board_radius")) or world.board_radius < MIN_RADIUS or world.board_radius > MAX_RADIUS:
			return false
		_seed = int(world.seed)
		_radius = int(world.board_radius)
		_version = BIOMES_VERSION
		_rng.seed = _seed
		_configure_field()
		_load_biomes_macro(world.macro_landscape)
	elif _version != VERSION or (world.has("seed") and world.has("board_radius") and (world.seed != _seed or world.board_radius != _radius)):
		if not _exact_integer(world.get("seed")) or not _exact_integer(world.get("board_radius")) or world.board_radius < MIN_RADIUS or world.board_radius > MAX_RADIUS:
			return false
		_seed = int(world.seed)
		_radius = int(world.board_radius)
		_version = VERSION
		_rng.seed = _seed
		_configure_field()
	_visual_fill.clear()
	for key in world.get("hexes", {}):
		var cell: Dictionary = world.hexes[key]
		_visual_fill[String(key)] = float(cell.get("fill_depth", 0.0))
	return true

func sample_visual_height(world_pos: Variant) -> float:
	var point := _world_point(world_pos)
	var macro := _sample_macro(point / (float(_radius) * sqrt(3.0)))
	return float(macro.elevation) + _sample_fill_correction(point)

func sample_visual_landscape(world_pos: Variant) -> Dictionary:
	var point := _world_point(world_pos)
	var sample := _sample_macro(point / (float(_radius) * sqrt(3.0)))
	sample["fill_depth"] = _sample_fill_correction(point)
	sample["raw_elevation"] = sample.elevation
	sample.elevation = float(sample.elevation) + float(sample.fill_depth)
	if _version == BIOMES_VERSION:
		sample["biome"] = _biome_v2(float(sample.elevation), float(sample.moisture), float(sample.temperature))
	return sample

func _world_point(world_pos: Variant) -> Vector2:
	if world_pos is Vector3:
		return Vector2(world_pos.x, world_pos.z)
	if world_pos is Vector2:
		return world_pos
	return Vector2.ZERO

func _sample_fill_correction(point: Vector2) -> float:
	if _visual_fill.is_empty(): return 0.0
	var qf := point.x / sqrt(3.0) - point.y / 3.0
	var rf := point.y * 2.0 / 3.0
	var q := floori(qf)
	var r := floori(rf)
	var u := qf - q
	var v := rf - r
	var vertices: Array
	var weights: Array
	if u + v <= 1.0:
		vertices = [Vector2i(q, r), Vector2i(q + 1, r), Vector2i(q, r + 1)]
		weights = [1.0 - u - v, u, v]
	else:
		vertices = [Vector2i(q + 1, r + 1), Vector2i(q, r + 1), Vector2i(q + 1, r)]
		weights = [u + v - 1.0, 1.0 - u, 1.0 - v]
	var correction := 0.0
	var total := 0.0
	for i in range(3):
		var key := hex_key(vertices[i])
		if _visual_fill.has(key):
			correction += float(_visual_fill[key]) * float(weights[i])
			total += float(weights[i])
	return correction / total if total > 0.00001 else 0.0

static func hex_key(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]

static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))

static func hex_center(hex: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * (hex.x + hex.y * 0.5), 1.5 * hex.y)

func _generate(world_seed: int, board_radius: int, options: Dictionary) -> Dictionary:
	var requested_version = options.get("generator_version", VERSION)
	if not requested_version is String or requested_version not in SUPPORTED_VERSIONS:
		return {}
	_version = requested_version
	_seed = world_seed
	_radius = clampi(board_radius, MIN_RADIUS, MAX_RADIUS)
	_config = {
		"settlement_count": int(_bounded_number(options.get("settlement_count", 4), 4.0, 2.0, 8.0)),
		"river_threshold": _bounded_number(options.get("river_threshold"), maxf(4.5, float(_radius) * 0.8), 3.0, 80.0),
		"settlement_max_slope": _bounded_number(options.get("settlement_max_slope"), 0.46, 0.18, 0.65),
		"road_max_slope": _bounded_number(options.get("road_max_slope"), 1.15, 0.65, 1.6),
		"mountain_threshold": 1.70 if _version == BIOMES_VERSION else 1.1,
		"height_units": "world_space",
		"minimum_flow_drop": FLOW_EPSILON,
		"sea_level": SEA_LEVEL
	}
	_rng.seed = world_seed
	_configure_field()
	if _version == BIOMES_VERSION:
		# Store and use exactly the same binary-quantized parameters before the
		# first cell is sampled. Reload does not subtly move a cap/coast/climate.
		_load_biomes_macro(_canonicalize(_macro_metadata()))
	_sample_hexes()
	var drainage := _condition_drainage()
	_measure_slopes_and_biomes()
	var river_edges := _build_rivers()
	_measure_water_access()
	var regions := _label_mountain_regions()
	var settlements := _place_settlements()
	var roads := _connect_settlements(settlements)
	var spawns := _choose_actor_spawns(settlements)
	var counts: Dictionary = {}
	for key in _keys:
		var terrain: String = _cells[key].terrain
		counts[terrain] = int(counts.get(terrain, 0)) + 1
	var world := {
		"generator_version": _version, "seed": _seed, "board_radius": _radius,
		"config": _config, "hexes": _cells,
		"macro_landscape": {"coast_axis": [_coast_axis.x, _coast_axis.y], "mountain_ranges": _ranges},
		"hydrology": {"method": "six_neighbor_priority_flood", "outlets": drainage.outlets, "conditioned_cell_count": drainage.conditioned_cell_count, "river_threshold": _config.river_threshold, "river_edges": river_edges},
		"river_edges": river_edges, "mountain_regions": regions,
		"settlements": settlements, "roads": roads,
		"actor_spawn_hexes": spawns,
		"statistics": {"hex_count": _cells.size(), "terrain_counts": counts, "river_edge_count": river_edges.size(), "settlement_count": settlements.size(), "road_count": roads.size()}
	}
	if _version == BIOMES_VERSION:
		world.macro_landscape = _macro_metadata()
		var biome_counts: Dictionary = {}
		var landform_counts: Dictionary = {}
		for key in _keys:
			var cell: Dictionary = _cells[key]
			biome_counts[cell.biome] = int(biome_counts.get(cell.biome, 0)) + 1
			landform_counts[cell.landform] = int(landform_counts.get(cell.landform, 0)) + 1
		world.statistics["biome_counts"] = biome_counts
		world.statistics["landform_counts"] = landform_counts
	# A deterministic content signature excludes run-time measurement.
	world = _canonicalize(world)
	world["content_hash"] = JSON.stringify(world, "", true, true).sha256_text()
	return world.duplicate(true)

func _bounded_number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)

func _noise(seed_offset: int, frequency: float, octaves: int, ridged: bool = false) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	# FastNoiseLite's seed is signed32; mix offsets within that range explicitly.
	noise.seed = int(posmod(_seed + seed_offset, 2147483647))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.48
	return noise

func _configure_field() -> void:
	_ranges.clear()
	_climate.clear()
	_plateaus.clear()
	_continental = _noise(117, 1.25, 3)
	_continental.domain_warp_enabled = true
	_continental.domain_warp_amplitude = 0.20
	_continental.domain_warp_frequency = 1.05
	_continental.domain_warp_fractal_octaves = 2
	_ridges = _noise(941, 5.4, 3, true)
	_moisture = _noise(2701, 1.9, 3)
	_detail = _noise(5309, 5.7, 2)
	var angle := _rng.randf_range(-PI, PI)
	_coast_axis = Vector2(cos(angle), sin(angle))
	var along := Vector2(-_coast_axis.y, _coast_axis.x)
	# The ranges are landscape-scale curved spines, not one peak per tile.
	# Their control points exist before any hex is constructed.
	for index in range(2):
		var points: Array = []
		var center_offset := 0.20 + index * 0.35 + _rng.randf_range(-0.08, 0.08)
		var half_length := 0.68 if index == 0 else 0.43
		for j in range(5):
			var t := -1.0 + float(j) * 0.5
			var bend := sin(t * PI + _rng.randf_range(-0.18, 0.18)) * 0.11
			var p := _coast_axis * (center_offset + bend) + along * (t * half_length + (0.05 if index == 0 else -0.18))
			points.append([p.x, p.y])
		_ranges.append({"id": "range_%d" % index, "control_points_normalized": points, "width_normalized": 0.16 if index == 0 else 0.12, "uplift": 2.45 if index == 0 else 1.5})
	if _version == BIOMES_VERSION:
		_temperature = _noise(7193, 1.35, 3)
		# A broad wet/dry domain across the coast tangent is intentional, not
		# a random biome per cell. The rotated fields retain seed variability.
		_climate = {
			"temperature_axis": [_coast_axis.x, _coast_axis.y],
			"moisture_axis": [along.x, along.y],
			"temperature_base": 0.76, "temperature_gradient": 0.12,
			"temperature_noise": 0.12, "moisture_base": 0.50,
			"moisture_gradient": 0.67, "moisture_noise": 0.20,
			"elevation_lapse": 0.12
		}
		var center := _coast_axis * 0.48 - along * 0.28
		_plateaus = [{"id": "plateau_0", "center_normalized": [center.x, center.y],
			"axis_normalized": [along.x, along.y], "radius_normalized": [0.29, 0.24],
			"core_ratio": 0.60, "height": 1.32}]

func _macro_metadata() -> Dictionary:
	return {"coast_axis": [_coast_axis.x, _coast_axis.y], "mountain_ranges": _ranges,
		"climate": _climate, "plateaus": _plateaus}

func _load_biomes_macro(macro: Dictionary) -> void:
	_coast_axis = Vector2(macro.coast_axis[0], macro.coast_axis[1])
	_ranges = macro.mountain_ranges.duplicate(true)
	_climate = macro.climate.duplicate(true)
	_plateaus = macro.plateaus.duplicate(true)

static func _quantized_number(value: Variant, minimum: float, maximum: float) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):
		return false
	return float(value) >= minimum and float(value) <= maximum and snappedf(float(value), SERIAL_QUANTUM) == float(value)

static func _exact_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 and float(value) == floor(float(value))

static func _macro_pair(value: Variant, axis: bool = false, positive: bool = false) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for number in value:
		if not _quantized_number(number, SERIAL_QUANTUM if positive else -4.0, 4.0):
			return false
	return not axis or absf(Vector2(value[0], value[1]).length() - 1.0) < 0.001

## Shared read-only consumer validation. Unknown GM extensions are retained.
static func validate_biomes_macro(value: Variant) -> Array:
	var errors: Array = []
	if not value is Dictionary:
		return ["v2 macro_landscape must be an object."]
	if not _macro_pair(value.get("coast_axis"), true):
		errors.append("v2 coast_axis must be a quantized unit axis.")
	var ranges = value.get("mountain_ranges")
	if not ranges is Array or ranges.is_empty():
		errors.append("v2 mountain_ranges must be a nonempty array.")
	else:
		var ids := {}
		for mountain_range in ranges:
			if not mountain_range is Dictionary or not mountain_range.get("id") is String or mountain_range.get("id", "").is_empty():
				errors.append("v2 range requires a string id.")
				continue
			if ids.has(mountain_range.id): errors.append("v2 range ids must be unique.")
			ids[mountain_range.id] = true
			if not _quantized_number(mountain_range.get("width_normalized"), SERIAL_QUANTUM, 4.0) or not _quantized_number(mountain_range.get("uplift"), 0.0, 8.0):
				errors.append("v2 range width/uplift must be bounded quantized numbers.")
			var points = mountain_range.get("control_points_normalized")
			if not points is Array or points.size() < 2:
				errors.append("v2 range requires at least two control points.")
			else:
				for point in points:
					if not _macro_pair(point): errors.append("v2 range point must be a quantized coordinate pair.")
	var climate = value.get("climate")
	if not climate is Dictionary:
		errors.append("v2 climate must be an object.")
	else:
		for field in ["temperature_axis", "moisture_axis"]:
			if not _macro_pair(climate.get(field), true): errors.append("v2 climate " + field + " must be a quantized unit axis.")
		for field in ["temperature_base", "temperature_gradient", "temperature_noise", "moisture_base", "moisture_gradient", "moisture_noise", "elevation_lapse"]:
			if not _quantized_number(climate.get(field), -4.0, 4.0): errors.append("v2 climate " + field + " must be a bounded quantized number.")
	var plateaus = value.get("plateaus")
	if not plateaus is Array or plateaus.is_empty():
		errors.append("v2 plateaus must be a nonempty array.")
	else:
		var ids := {}
		for plateau in plateaus:
			if not plateau is Dictionary or not plateau.get("id") is String or plateau.get("id", "").is_empty():
				errors.append("v2 plateau requires a string id.")
				continue
			if ids.has(plateau.id): errors.append("v2 plateau ids must be unique.")
			ids[plateau.id] = true
			if not _macro_pair(plateau.get("center_normalized")) or not _macro_pair(plateau.get("axis_normalized"), true) or not _macro_pair(plateau.get("radius_normalized"), false, true):
				errors.append("v2 plateau requires quantized center, unit axis and positive radii.")
			if not _quantized_number(plateau.get("core_ratio"), SERIAL_QUANTUM, 1.0 - SERIAL_QUANTUM) or not _quantized_number(plateau.get("height"), SERIAL_QUANTUM, 8.0):
				errors.append("v2 plateau core_ratio/height must be bounded quantized numbers.")
	return errors

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var t := clampf((p - a).dot(delta) / maxf(delta.length_squared(), 0.00001), 0.0, 1.0)
	return p.distance_to(a + delta * t)

func _sample_macro(p: Vector2) -> Dictionary:
	var continentalness := 0.30 + p.dot(_coast_axis) * 0.53 + _continental.get_noise_2d(p.x, p.y) * 0.22
	if _version == BIOMES_VERSION:
		# Shoreline perturbation depends on along-coast position only. Near sea
		# this gives one continuous seaward half-domain rather than little
		# below-sea noise pits mislabeled as disconnected inland ocean cells.
		var tangent := Vector2(-_coast_axis.y, _coast_axis.x)
		var coastal_point := tangent * p.dot(tangent)
		continentalness = 0.30 + p.dot(_coast_axis) * 0.53 + _continental.get_noise_2d(coastal_point.x, coastal_point.y) * 0.22
	var ridge_modulation := 0.68 + 0.32 * clampf(0.5 + _ridges.get_noise_2d(p.x, p.y) * 0.5, 0.0, 1.0)
	var uplift := 0.0
	var strongest := ""
	for mountain_range in _ranges:
		var distance := INF
		var points: Array = mountain_range.control_points_normalized
		for j in range(points.size() - 1):
			distance = minf(distance, _distance_to_segment(p, Vector2(points[j][0], points[j][1]), Vector2(points[j + 1][0], points[j + 1][1])))
		var width: float = mountain_range.width_normalized
		var contribution: float = exp(-pow(distance / width, 2.0)) * float(mountain_range.uplift) * ridge_modulation
		if contribution > uplift:
			uplift = contribution
			strongest = mountain_range.id
	var height := continentalness + uplift + _detail.get_noise_2d(p.x, p.y) * 0.055
	if _version == BIOMES_VERSION:
		# Retain inland relief; taper tiny detail out at the continuous coast.
		height = continentalness + uplift + _detail.get_noise_2d(p.x, p.y) * 0.055 * smoothstep(0.04, 0.18, continentalness)
	var humidity := clampf(0.53 + _moisture.get_noise_2d(p.x, p.y) * 0.42 - maxf(0.0, p.dot(_coast_axis)) * 0.08, 0.12, 0.94)
	var sample := {"elevation": height, "continentalness": continentalness, "uplift": uplift, "range_id": strongest if uplift > 0.08 else "", "moisture": humidity}
	if _version == BIOMES_VERSION:
		var plateau_weight := 0.0
		var plateau_region := ""
		var plateau_height := 0.0
		for plateau in _plateaus:
			var axis := Vector2(plateau.axis_normalized[0], plateau.axis_normalized[1])
			var cross_axis := Vector2(-axis.y, axis.x)
			var offset := p - Vector2(plateau.center_normalized[0], plateau.center_normalized[1])
			var elliptical := Vector2(offset.dot(axis) / float(plateau.radius_normalized[0]), offset.dot(cross_axis) / float(plateau.radius_normalized[1])).length()
			var weight := 1.0 - smoothstep(float(plateau.core_ratio), 1.0, elliptical)
			if weight > plateau_weight:
				plateau_weight = weight
				plateau_region = plateau.id
				plateau_height = plateau.height
		# A true flat macro cap replaces the noisy/ridged base at weight1.
		# Its C1 smooth apron blends into the original adjoining relief.
		height = lerpf(height, plateau_height, plateau_weight)
		var temperature_axis := Vector2(_climate.temperature_axis[0], _climate.temperature_axis[1])
		var moisture_axis := Vector2(_climate.moisture_axis[0], _climate.moisture_axis[1])
		humidity = clampf(float(_climate.moisture_base) + p.dot(moisture_axis) * float(_climate.moisture_gradient) + _moisture.get_noise_2d(p.x, p.y) * float(_climate.moisture_noise), 0.0, 1.0)
		var temperature := clampf(float(_climate.temperature_base) + p.dot(temperature_axis) * float(_climate.temperature_gradient) + _temperature.get_noise_2d(p.x, p.y) * float(_climate.temperature_noise) - maxf(height, 0.0) * float(_climate.elevation_lapse), 0.0, 1.0)
		sample.elevation = height
		sample.moisture = humidity
		sample["temperature"] = temperature
		sample["plateau_weight"] = plateau_weight
		sample["plateau_region"] = plateau_region
		sample["plateau_height"] = plateau_height
		sample["landform"] = "plateau" if plateau_weight >= 0.99999 else ("slope" if plateau_weight > 0.0 else ("ridge" if uplift >= 0.35 or height >= 0.75 else "lowland"))
		sample["biome"] = _biome_v2(height, humidity, temperature)
	return sample

func _biome_v2(elevation: float, moisture: float, temperature: float) -> String:
	if elevation <= SEA_LEVEL: return "ocean"
	if elevation > 1.90 or temperature < 0.30: return "alpine"
	if moisture < 0.31 and temperature >= 0.48: return "desert"
	if moisture > 0.76 and elevation < 0.24: return "wetland"
	if moisture > 0.67 and temperature >= 0.56: return "jungle"
	if moisture > 0.58: return "temperate_forest"
	return "grassland"

func _sample_hexes() -> void:
	for q in range(-_radius, _radius + 1):
		for r in range(-_radius, _radius + 1):
			var hex := Vector2i(q, r)
			if hex_distance(Vector2i.ZERO, hex) > _radius:
				continue
			var key := hex_key(hex)
			var point := hex_center(hex) / (float(_radius) * sqrt(3.0))
			var sample := _sample_macro(point)
			var ocean: bool = sample.elevation <= SEA_LEVEL
			_cells[key] = {
				"id": "hex_%d_%d" % [q, r], "q": q, "r": r,
				"terrain": "ocean" if ocean else "plain", "biome": "ocean" if ocean else "grassland",
				"raw_elevation": sample.elevation, "elevation": sample.elevation,
				"continentalness": sample.continentalness, "uplift": sample.uplift,
				"range_id": sample.range_id, "mountain_region": "", "moisture": sample.moisture,
				"slope": 0.0, "ocean": ocean, "water_surface": SEA_LEVEL if ocean else null,
				"flow_to": "", "flow_from": [], "flow_accumulation": 0.0,
				"drainage_elevation": maxf(SEA_LEVEL, sample.elevation), "fill_depth": 0.0,
				"river": false, "river_to": "", "river_from": [], "river_width": 0.0,
				"road": false, "road_neighbors": [], "bridge": false, "settlement_id": ""
			}
			if _version == BIOMES_VERSION:
				for field in BIOMES_CELL_FIELDS:
					_cells[key][field] = sample[field]
			_keys.append(key)
	for key in _keys:
		var cell: Dictionary = _cells[key]
		var neighboring: Array = []
		for dir in DIRS:
			var target := hex_key(Vector2i(cell.q, cell.r) + dir)
			if _cells.has(target):
				neighboring.append(target)
		_neighbors[key] = neighboring

# Deterministic binary min-heap for drainage and Dijkstra. Secondary key is a
# stable string; insertion order and Dictionary order do not choose outcomes.
func _heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and String(a[1]) < String(b[1]))

func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) >> 1
		if not _heap_less(heap[index], heap[parent]):
			break
		var swap: Array = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent

func _heap_pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and _heap_less(heap[child + 1], heap[child]):
			child += 1
		if not _heap_less(heap[child], heap[index]):
			break
		var swap: Array = heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return first

func _condition_drainage() -> Dictionary:
	var queue: Array = []
	var visited: Dictionary = {}
	var outlets: Array = []
	var order: Array = []
	var conditioned := 0
	# Every ocean cell and board-boundary land cell is an outlet. Ocean has no
	# downstream link; the bounded map may drain beyond its cropped boundary.
	for key in _keys:
		var cell: Dictionary = _cells[key]
		if cell.ocean or _neighbors[key].size() < 6:
			visited[key] = true
			outlets.append(key)
			_heap_push(queue, [float(cell.drainage_elevation), key])
	while not queue.is_empty():
		var entry := _heap_pop(queue)
		var key: String = entry[1]
		var current: Dictionary = _cells[key]
		order.append(key)
		for neighbor in _neighbors[key]:
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			var next: Dictionary = _cells[neighbor]
			var filled := maxf(float(next.raw_elevation), float(current.drainage_elevation) + FLOW_EPSILON)
			next.drainage_elevation = filled
			next.elevation = filled
			next.fill_depth = filled - float(next.raw_elevation)
			if next.fill_depth > FLOW_EPSILON:
				conditioned += 1
			next.flow_to = key
			current.flow_from.append(neighbor)
			_heap_push(queue, [filled, neighbor])
	# A parent's flood priority is strictly lower than its child's. Reverse
	# processing therefore accumulates upstream rainfall without recursion.
	for key in _keys:
		_cells[key].flow_accumulation = 0.0 if _cells[key].ocean else 0.55 + float(_cells[key].moisture)
	order.reverse()
	for key in order:
		var cell: Dictionary = _cells[key]
		if not String(cell.flow_to).is_empty():
			_cells[cell.flow_to].flow_accumulation += float(cell.flow_accumulation)
	return {"outlets": outlets, "conditioned_cell_count": conditioned}

func _measure_slopes_and_biomes() -> void:
	for key in _keys:
		var cell: Dictionary = _cells[key]
		var slope := 0.0
		for neighbor in _neighbors[key]:
			slope = maxf(slope, absf(float(cell.elevation) - float(_cells[neighbor].elevation)) / sqrt(3.0))
		cell.slope = slope
		if cell.ocean:
			continue
		if _version == BIOMES_VERSION:
			cell.biome = _biome_v2(float(cell.elevation), float(cell.moisture), float(cell.temperature))
			if float(cell.elevation) > float(_config.mountain_threshold) and cell.landform != "plateau":
				cell.terrain = "mountain"
			elif cell.biome == "wetland":
				cell.terrain = "swamp"
			elif cell.biome in ["jungle", "temperate_forest"]:
				cell.terrain = "forest"
			elif float(cell.elevation) > 0.75:
				cell.terrain = "hill"
			else:
				cell.terrain = "plain"
		elif float(cell.elevation) >= float(_config.mountain_threshold):
			cell.terrain = "mountain"
			cell.biome = "alpine" if float(cell.elevation) > 1.8 else "rocky_highland"
		elif float(cell.elevation) > 0.75:
			cell.terrain = "hill"
			cell.biome = "highland"
		elif float(cell.moisture) > 0.69 and float(cell.elevation) < 0.30:
			cell.terrain = "swamp"
			cell.biome = "wetland"
		elif float(cell.moisture) > 0.58:
			cell.terrain = "forest"
			cell.biome = "temperate_forest"
		else:
			cell.terrain = "plain"
			cell.biome = "grassland"
		for neighbor in _neighbors[key]:
			if _cells[neighbor].ocean:
				cell["coastal"] = true
				break

func _build_rivers() -> Array:
	var edges: Array = []
	var threshold: float = _config.river_threshold
	# Accumulation never decreases downstream, so thresholded nodes include
	# their entire downstream path. Rivers stop at sea or a board outlet.
	for key in _keys:
		var cell: Dictionary = _cells[key]
		if cell.ocean or float(cell.flow_accumulation) < threshold:
			continue
		cell.river = true
		cell.river_width = clampf(0.12 + sqrt(float(cell.flow_accumulation)) * 0.018, 0.14, 0.42)
		cell["river_surface"] = float(cell.drainage_elevation) + 0.015
		if cell.terrain != "mountain":
			cell.terrain = "river"
		var target: String = cell.flow_to
		if target.is_empty():
			cell["river_outlet"] = "board_boundary"
			continue
		cell.river_to = target
		_cells[target].river_from.append(key)
		edges.append({
			"id": "river_" + key + "_" + target, "from": key, "to": target,
			"from_hex": [cell.q, cell.r], "to_hex": [_cells[target].q, _cells[target].r],
			"from_elevation": cell.river_surface,
			"to_elevation": SEA_LEVEL + 0.015 if _cells[target].ocean else float(_cells[target].drainage_elevation) + 0.015,
			"width": cell.river_width, "flow": cell.flow_accumulation,
			"mouth": bool(_cells[target].ocean)
		})
	return edges

func _label_mountain_regions() -> Array:
	var regions: Array = []
	var seen: Dictionary = {}
	for key in _keys:
		if seen.has(key) or _cells[key].terrain != "mountain":
			continue
		var region_id := "mountain_region_%d" % regions.size()
		var queue: Array = [key]
		var members: Array = []
		var highest: String = key
		seen[key] = true
		var index := 0
		while index < queue.size():
			var current: String = queue[index]
			index += 1
			members.append(current)
			_cells[current].mountain_region = region_id
			if float(_cells[current].elevation) > float(_cells[highest].elevation):
				highest = current
			for neighbor in _neighbors[current]:
				if not seen.has(neighbor) and _cells[neighbor].terrain == "mountain":
					seen[neighbor] = true
					queue.append(neighbor)
		regions.append({"id": region_id, "hex_keys": members, "peak_hex": highest, "peak_elevation": _cells[highest].elevation, "range_id": _cells[highest].range_id})
	return regions

func _road_allowed(key: String) -> bool:
	var cell: Dictionary = _cells[key]
	return not cell.ocean and float(cell.slope) <= float(_config.road_max_slope)

func _land_components() -> Array:
	var components: Array = []
	var seen: Dictionary = {}
	for key in _keys:
		if seen.has(key) or not _road_allowed(key):
			continue
		var members: Array = [key]
		seen[key] = true
		var index := 0
		while index < members.size():
			var current: String = members[index]
			index += 1
			for neighbor in _neighbors[current]:
				if not seen.has(neighbor) and _road_allowed(neighbor):
					seen[neighbor] = true
					members.append(neighbor)
		components.append(members)
	components.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size() or (a.size() == b.size() and String(a[0]) < String(b[0])))
	return components

func _measure_water_access() -> void:
	# Multi-source BFS gives minimum hex-distance to river/sea in O(V+E),
	# avoiding an all-pairs water scan for every candidate settlement.
	var queue: Array = []
	for key in _keys:
		if _cells[key].ocean or _cells[key].river:
			_water_distances[key] = 0
			queue.append(key)
	var index := 0
	while index < queue.size():
		var key: String = queue[index]
		index += 1
		for neighbor in _neighbors[key]:
			if not _water_distances.has(neighbor):
				_water_distances[neighbor] = int(_water_distances[key]) + 1
				queue.append(neighbor)

func _water_distance(key: String) -> int:
	return int(_water_distances.get(key, _radius * 2 + 1))

func _place_settlements() -> Array:
	var components := _land_components()
	if components.is_empty():
		return []
	var candidates: Array = []
	for key in components[0]:
		var cell: Dictionary = _cells[key]
		if cell.river or cell.terrain in ["mountain", "swamp"] or float(cell.slope) > float(_config.settlement_max_slope):
			continue
		var distance := _water_distance(key)
		var interior := _radius - hex_distance(Vector2i.ZERO, Vector2i(cell.q, cell.r))
		var access := 1.0 / (1.0 + distance)
		var score := access * 3.0 + (1.0 - float(cell.slope)) * 1.3 + float(cell.moisture) * 0.5 + minf(float(interior), 3.0) * 0.12 - absf(float(cell.elevation) - 0.25) * 0.25
		candidates.append({"hex_key": key, "score": score, "water_distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score or (a.score == b.score and String(a.hex_key) < String(b.hex_key)))
	var selected: Array = []
	var minimum_spacing := maxi(2, roundi(float(_radius) * 0.43))
	# Relax spacing only if necessary, never the dry/stable-slope constraint.
	for spacing in range(minimum_spacing, 0, -1):
		for candidate in candidates:
			if selected.size() >= int(_config.settlement_count):
				break
			var cell: Dictionary = _cells[candidate.hex_key]
			var hex := Vector2i(cell.q, cell.r)
			var valid := true
			for previous in selected:
				if hex_distance(hex, Vector2i(previous.hex[0], previous.hex[1])) < spacing:
					valid = false
					break
			if not valid:
				continue
			var id := "settlement_%d" % selected.size()
			cell.settlement_id = id
			selected.append({"id": id, "name": NAMES[selected.size()], "kind": "city" if selected.is_empty() else "town", "hex_key": candidate.hex_key, "hex": [cell.q, cell.r], "elevation": cell.elevation, "slope": cell.slope, "water_distance": candidate.water_distance, "water_access": candidate.water_distance <= 2, "site_score": candidate.score, "road_ids": []})
	return selected

func _road_step(a: String, b: String) -> float:
	var next: Dictionary = _cells[b]
	var slope := absf(float(_cells[a].elevation) - float(next.elevation)) / sqrt(3.0)
	var cost := 1.0 + slope * 5.0 + float(next.slope) * 1.8
	if next.terrain == "mountain": cost += 5.0
	if next.biome == "temperate_forest": cost += 0.45
	if next.biome == "wetland": cost += 2.5
	if next.river: cost += 3.0 # bridge construction preference, no gameplay law
	if next.road: cost *= 0.65
	return cost

func _least_cost_path(start: String, goal: String) -> Dictionary:
	var open: Array = []
	var distance: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	_heap_push(open, [0.0, start])
	while not open.is_empty():
		var entry := _heap_pop(open)
		var key: String = entry[1]
		if float(entry[0]) > float(distance[key]): continue
		if key == goal: break
		for neighbor in _neighbors[key]:
			if not _road_allowed(neighbor): continue
			var next_cost := float(entry[0]) + _road_step(key, neighbor)
			if next_cost < float(distance.get(neighbor, INF)):
				distance[neighbor] = next_cost
				previous[neighbor] = key
				_heap_push(open, [next_cost, neighbor])
	if not distance.has(goal):
		return {"path": [], "cost": INF}
	var path: Array = [goal]
	while path[-1] != start:
		path.append(previous[path[-1]])
	path.reverse()
	return {"path": path, "cost": distance[goal]}

func _connect_settlements(settlements: Array) -> Array:
	var roads: Array = []
	if settlements.size() < 2: return roads
	# Prim-style network selection using actual least-cost paths, not straight
	# lines through water/cliffs. All sites share a traversable land component.
	var connected: Dictionary = {0: true}
	while connected.size() < settlements.size():
		var best: Dictionary = {"cost": INF}
		for i in range(settlements.size()):
			if not connected.has(i): continue
			for j in range(settlements.size()):
				if connected.has(j): continue
				var candidate := _least_cost_path(settlements[i].hex_key, settlements[j].hex_key)
				if candidate.cost < best.cost:
					best = {"from_index": i, "to_index": j, "path": candidate.path, "cost": candidate.cost}
		if not best.has("path") or best.path.is_empty(): break
		var from: Dictionary = settlements[best.from_index]
		var to: Dictionary = settlements[best.to_index]
		var road_id := "road_%d" % roads.size()
		var bridge_hexes: Array = []
		var segments: Array = []
		for index in range(best.path.size()):
			var key: String = best.path[index]
			var cell: Dictionary = _cells[key]
			cell.road = true
			if cell.river:
				cell.bridge = true
				cell.terrain = "bridge"
				bridge_hexes.append(key)
			if index == best.path.size() - 1: continue
			var next: String = best.path[index + 1]
			if not cell.road_neighbors.has(next): cell.road_neighbors.append(next)
			if not _cells[next].road_neighbors.has(key): _cells[next].road_neighbors.append(key)
			segments.append({"from": key, "to": next})
		var road := {"id": road_id, "from_settlement": from.id, "to_settlement": to.id, "from": from.hex_key, "to": to.hex_key, "path": best.path, "segments": segments, "bridge_hexes": bridge_hexes, "construction_cost": best.cost}
		roads.append(road)
		from.road_ids.append(road_id)
		to.road_ids.append(road_id)
		connected[best.to_index] = true
	return roads

func _choose_actor_spawns(settlements: Array) -> Dictionary:
	if settlements.size() >= 2:
		return {"actor_player": settlements[0].hex.duplicate(), "actor_sentinel": settlements[1].hex.duplicate()}
	var choices: Array = []
	for key in _keys:
		if _road_allowed(key) and not _cells[key].river and _cells[key].terrain != "mountain": choices.append(key)
	if choices.is_empty(): choices = _keys.duplicate()
	var first: Dictionary = _cells[choices[0]]
	var second: Dictionary = _cells[choices[-1]]
	return {"actor_player": [first.q, first.r], "actor_sentinel": [second.q, second.r]}

# Quantize display/geography metrics to binary-exact fractions before they
# enter exact model-state snapshots. Integral floats become canonical ints.
# This prevents Godot decimal parsing from changing a final-bit double or a
# content hash after save/reload. The quantum is 1/4096 world units, much
# smaller than the explicit downhill flow drop (1/1024 units).
func _canonicalize(value: Variant) -> Variant:
	if value is float:
		var number := snappedf(float(value), SERIAL_QUANTUM)
		return int(number) if number == floor(number) else number
	if value is Dictionary:
		var output: Dictionary = {}
		for key in value:
			output[String(key)] = _canonicalize(value[key])
		return output
	if value is Array:
		var output: Array = []
		for entry in value:
			output.append(_canonicalize(entry))
		return output
	return value

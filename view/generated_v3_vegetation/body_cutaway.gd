extends RefCounted
## Bounded, presentation-only crown suppression. Original assets stay immutable.
const POLICY := "visual_canopy_cutaway/v1"
const SOURCE_PINS := {
	"res://view/ecology_preview/vegetation_meshes.gd": "90f29e8c844d9f0094186c5a61060a831de50ef37ca35da36881c24a4c0c56bb",
	"res://view/ecology_preview/vegetation_surface.gdshader": "e7bc8bdf45017df68daf059c818778f1638a21f3d1f5859a2536d8ffacd8fafb",
	"res://view/ecology_preview/LICENSE.txt": "8f2f09db1ebceff3581d6016eb2c4154c60d15b01709a9add27d83d88b716251"}
const PICK_THRESHOLD := 0.5
const ENTER_MARGIN := 0.015
const EXIT_MARGIN := 0.08
const BIN_SIZE := 2.0
const MAX_PLANTS := 1024
const MAX_BODY_BOUNDS := 8
const MAX_QUERY_BINS := 64
const MAX_NEARBY_CANDIDATES := 128
const MAX_EXAMINED := 256
const BARK_TRIANGLES := {"temperate": 14, "tropical": 28, "sapling": 14}
const FULL_TRIANGLES := {"temperate": 77, "tropical": 91, "sapling": 77}
const META_POLICY := "v3_cutaway_policy"
const META_BARK := "v3_cutaway_bark_triangles"
var _entries: Dictionary = {}
var _bins: Dictionary = {}
var _hidden: Dictionary = {}
var _last_boxes: Array = []
var _last_enabled: bool = false
var _have_query: bool = false
var _revision: int = 0
var _calls: int = 0
var _last: Dictionary = {}
var _checked_ids: Array = []

static func _bark_mesh(source: ArrayMesh, bark_triangles: int) -> ArrayMesh:
	var original: Array = source.surface_get_arrays(0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var end: int = bark_triangles * 3
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		if original[attribute] != null:
			arrays[attribute] = original[attribute].slice(0, end)
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _valid_original(mesh: ArrayMesh, triangles: int) -> bool:
	if mesh == null or mesh.get_surface_count() != 1 or mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or arrays[Mesh.ARRAY_VERTEX].size() != triangles * 3:
		return false
	return not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or arrays[Mesh.ARRAY_INDEX].is_empty()

static func derive_visual_assets(full: Dictionary, far: Dictionary) -> Dictionary:
	for path in SOURCE_PINS:
		if FileAccess.get_sha256(path) != SOURCE_PINS[path]:
			return {"ok": false, "error": "cutaway_original_source_pin_changed:" + str(path)}
	var full_visual: Dictionary = full.duplicate()
	var far_visual: Dictionary = far.duplicate()
	var bark: Dictionary = {}
	var records: Dictionary = {}
	for kind in BARK_TRIANGLES:
		if not full.has(kind):
			continue
		var full_mesh: ArrayMesh = full.get(kind) as ArrayMesh
		var far_mesh: ArrayMesh = far.get(kind) as ArrayMesh
		if not _valid_original(full_mesh, int(FULL_TRIANGLES[kind])) or not _valid_original(far_mesh, 7):
			return {"ok": false, "error": "cutaway_requires_original_triangle_layout:" + str(kind)}
		var bark_count: int = int(BARK_TRIANGLES[kind])
		# Keep the exact original render resources. VERTEX_ID plus immutable
		# native per-instance bark-prefix data classifies crown membership.
		full_visual[kind] = full_mesh
		far_visual[kind] = far_mesh
		bark[kind] = _bark_mesh(full_mesh, bark_count)
		if full_visual[kind] != full_mesh or far_visual[kind] != far_mesh:
			return {"ok": false, "error": "cutaway_original_mesh_identity_changed"}
		for pair in [[full_mesh, full_visual[kind]], [far_mesh, far_visual[kind]]]:
			var source_arrays: Array = pair[0].surface_get_arrays(0)
			var visual_arrays: Array = pair[1].surface_get_arrays(0)
			for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
				if source_arrays[attribute] != visual_arrays[attribute]:
					return {"ok": false, "error": "cutaway_changed_original_buffer:" + str(kind) + ":attribute_" + str(attribute)}
		records[kind] = {"full_bark_triangles": [0, bark_count - 1],
			"full_crown_triangles": [bark_count, int(FULL_TRIANGLES[kind]) - 1],
			"far_bark_triangles": [], "far_crown_triangles": [0, 6]}
	return {"ok": true, "full_meshes": full_visual, "far_meshes": far_visual,
		"bark_meshes": bark, "triangle_sets": records, "source_pins": SOURCE_PINS.duplicate(),
		"original_position_index_normal_color_arrays_preserved": true}

func clear() -> void:
	_entries.clear()
	_bins.clear()
	_hidden.clear()
	_last_boxes.clear()
	_last_enabled = false
	_have_query = false
	_revision = 0
	_calls = 0
	_last = {}
	_checked_ids.clear()

func configure(plants: Array, full_meshes: Dictionary, far_meshes: Dictionary) -> Dictionary:
	clear()
	if plants.size() > MAX_PLANTS:
		return {"ok": false, "error": "cutaway_plant_budget"}
	var crowns: Dictionary = {}
	for kind in BARK_TRIANGLES:
		if not full_meshes.has(kind):
			continue
		var mesh: ArrayMesh = full_meshes.get(kind) as ArrayMesh
		if not _valid_original(mesh, int(FULL_TRIANGLES[kind])):
			return {"ok": false, "error": "cutaway_requires_original_full_mesh:" + str(kind)}
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var crown_vertices: PackedVector3Array = vertices.slice(int(BARK_TRIANGLES[kind]) * 3)
		var far_mesh: ArrayMesh = far_meshes.get(kind) as ArrayMesh
		if not _valid_original(far_mesh, 7):
			return {"ok": false, "error": "cutaway_requires_original_far_mesh:" + str(kind)}
		crown_vertices.append_array(far_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		crowns[kind] = crown_vertices
	for row in plants:
		var kind: String = str(row.asset_id)
		if not BARK_TRIANGLES.has(kind):
			continue
		var id: String = str(row.id)
		if id.is_empty() or _entries.has(id) or not crowns.has(kind):
			return {"ok": false, "error": "cutaway_row_identity"}
		var p: Array = row.position
		var transform_: Transform3D = Transform3D(Basis(Vector3.UP, float(row.yaw)).scaled(
			Vector3(float(row.radius), float(row.height), float(row.radius))), Vector3(float(p[0]), float(p[1]), float(p[2])))
		var vertices: PackedVector3Array = crowns[kind]
		var bounds: AABB = AABB(transform_ * vertices[0], Vector3.ZERO)
		for vertex in vertices:
			bounds = bounds.expand(transform_ * vertex)
		var width: int = floori(bounds.end.x / BIN_SIZE) - floori(bounds.position.x / BIN_SIZE) + 1
		var depth: int = floori(bounds.end.z / BIN_SIZE) - floori(bounds.position.z / BIN_SIZE) + 1
		if not _valid_box(bounds) or width * depth > 16:
			return {"ok": false, "error": "cutaway_entry_bounds_budget"}
		_entries[id] = {"bounds": bounds, "asset_id": kind}
		for key in _keys(bounds):
			if not _bins.has(key):
				_bins[key] = []
			_bins[key].append(id)
	return {"ok": true, "report": report()}

static func _valid_box(box: AABB) -> bool:
	return box.position.is_finite() and box.size.is_finite() and box.size.x >= 0.0 and box.size.y >= 0.0 and box.size.z >= 0.0

static func _keys(box: AABB) -> Array:
	var result: Array = []
	for x in range(floori(box.position.x / BIN_SIZE), floori(box.end.x / BIN_SIZE) + 1):
		for z in range(floori(box.position.z / BIN_SIZE), floori(box.end.z / BIN_SIZE) + 1):
			result.append("%d,%d" % [x, z])
	return result

func update_bounds(boxes: Array, enabled: bool = true) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	_calls += 1
	_last = {"candidate_count": 0, "bucket_count": 0, "examined_count": 0,
		"changed_count": 0, "elapsed_us": 0, "cached_idle": false, "error": ""}
	if boxes.size() > MAX_BODY_BOUNDS:
		return _failure("too_many_body_bounds", started)
	for value in boxes:
		if not value is AABB or not _valid_box(value):
			return _failure("invalid_body_bounds", started)
	if _have_query and enabled == _last_enabled and boxes == _last_boxes:
		_last.cached_idle = true
		return _finish([], [], started)
	var nearby: Dictionary = {}
	var queried_bins: Dictionary = {}
	if enabled:
		for value in boxes:
			var box: AABB = value.grow(ENTER_MARGIN)
			var width: int = floori(box.end.x / BIN_SIZE) - floori(box.position.x / BIN_SIZE) + 1
			var depth: int = floori(box.end.z / BIN_SIZE) - floori(box.position.z / BIN_SIZE) + 1
			if width * depth > MAX_QUERY_BINS:
				return _failure("body_bounds_bucket_budget", started)
			for key in _keys(box):
				queried_bins[key] = true
				if queried_bins.size() > MAX_QUERY_BINS:
					return _failure("body_bounds_bucket_budget", started)
				for id in _bins.get(key, []):
					nearby[id] = true
					if nearby.size() > MAX_NEARBY_CANDIDATES:
						return _failure("nearby_candidate_budget", started)
	_last.bucket_count = queried_bins.size()
	_last.candidate_count = nearby.size()
	var examined: Dictionary = nearby.duplicate()
	for id in _hidden:
		examined[id] = true
	if examined.size() > MAX_EXAMINED:
		return _failure("active_set_budget", started)
	_last.examined_count = examined.size()
	_checked_ids = examined.keys()
	var next_hidden: Dictionary = {}
	for id in examined:
		if not enabled:
			continue
		var crown: AABB = _entries[id].bounds
		var margin: float = EXIT_MARGIN if _hidden.has(id) else ENTER_MARGIN
		for value in boxes:
			if crown.intersects(value.grow(margin)):
				next_hidden[id] = true
				break
	if next_hidden.size() > MAX_NEARBY_CANDIDATES:
		return _failure("suppressed_set_budget", started)
	var hide_ids: Array = []
	var show_ids: Array = []
	for id in next_hidden:
		if not _hidden.has(id):
			hide_ids.append(id)
	for id in _hidden:
		if not next_hidden.has(id):
			show_ids.append(id)
	hide_ids.sort()
	show_ids.sort()
	_hidden = next_hidden
	_last_boxes = boxes.duplicate()
	_last_enabled = enabled
	_have_query = true
	return _finish(hide_ids, show_ids, started)

func _finish(hide_ids: Array, show_ids: Array, started: int) -> Dictionary:
	_last.changed_count = hide_ids.size() + show_ids.size()
	_last.elapsed_us = Time.get_ticks_usec() - started
	if int(_last.changed_count) > 0:
		_revision += 1
	return {"ok": true, "hide_ids": hide_ids, "show_ids": show_ids, "checked_ids": _checked_ids.duplicate(), "report": report()}

func _failure(error: String, started: int) -> Dictionary:
	_last.error = error
	_last.elapsed_us = Time.get_ticks_usec() - started
	return {"ok": false, "error": error, "hide_ids": [], "show_ids": [], "report": report()}

func is_hidden(id: String) -> bool:
	return _hidden.has(id)

func report() -> Dictionary:
	var ids: Array = _hidden.keys()
	ids.sort()
	var result: Dictionary = {"policy": POLICY, "suppressed_ids": ids, "suppressed_count": ids.size(),
		"mask_revision": _revision, "update_calls": _calls, "indexed_trees": _entries.size(),
		"index_buckets": _bins.size(), "enter_margin": ENTER_MARGIN, "exit_margin": EXIT_MARGIN,
		"mask_threshold": PICK_THRESHOLD, "transition": "immediate_opaque_cutoff_with_exit_hysteresis",
		"max_body_bounds": MAX_BODY_BOUNDS, "max_query_buckets": MAX_QUERY_BINS,
		"max_nearby_candidates": MAX_NEARBY_CANDIDATES, "max_examined": MAX_EXAMINED,
		"physical_clearance_claim": false, "body_source_contract": "actual player and visible packs; NPCs excluded by caller"}
	result.merge(_last, true)
	return result

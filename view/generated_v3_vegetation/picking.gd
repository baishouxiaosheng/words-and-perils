extends RefCounted
## Read-only raw ArrayMesh picking for bounded, source-row-bound MultiMeshes.
## The caller supplies the nearest actual terrain/other occluder distance.
## Identity is captured once per instance slot. Mesh, transform and visibility
## are read live; replacing a MultiMesh requires an explicit recapture.

const BodyCutaway = preload("res://view/generated_v3_vegetation/body_cutaway.gd")
const MAX_PLANTS := 1024
const MAX_BATCHES := 64
const MAX_TRIANGLES := 80000
const MAX_CACHED_MESHES := 10
const MAX_MESH_TRIANGLES := 4096
const MAX_MESH_VERTICES := 12288
const MAX_MESH_SURFACES := 8
const BROADPHASE_MARGIN := 0.000001

var _batches: Array[Dictionary] = []
var _entities: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _cache_builds: int = 0
var _cache_evictions: int = 0
var _cache_clock: int = 0
var last_query: Dictionary = {}

func capture(batches: Array) -> Dictionary:
	clear()
	if batches.size() > MAX_BATCHES:
		return _capture_failure("batch_budget_exceeded")
	var captured_nodes: Dictionary = {}
	for value in batches:
		if not value is Dictionary:
			return _capture_failure("invalid_batch")
		var node: MultiMeshInstance3D = value.get("node") as MultiMeshInstance3D
		var rows: Variant = value.get("rows")
		if not is_instance_valid(node) or node.is_queued_for_deletion() or node.multimesh == null:
			return _capture_failure("invalid_batch_node")
		if captured_nodes.has(node.get_instance_id()):
			return _capture_failure("duplicate_batch_node")
		captured_nodes[node.get_instance_id()] = true
		if not rows is Array or rows.size() != node.multimesh.instance_count:
			return _capture_failure("instance_identity_count_mismatch")
		var identities: Array[Dictionary] = []
		for row in rows:
			if not row is Dictionary:
				return _capture_failure("invalid_instance_identity")
			var id: String = str(row.get("id", ""))
			var hex: Variant = row.get("hex")
			if id.is_empty() or _entities.has(id) or not _valid_hex(hex):
				return _capture_failure("invalid_or_duplicate_instance_identity")
			var identity: Dictionary = {"id": id, "hex": hex.duplicate()}
			identities.append(identity)
			_entities[id] = true
			if _entities.size() > MAX_PLANTS:
				return _capture_failure("plant_budget_exceeded")
		_batches.append({"node": weakref(node), "multimesh": weakref(node.multimesh), "rows": identities})
		var mesh: ArrayMesh = node.multimesh.mesh as ArrayMesh
		if mesh == null or not bool(_mesh_data(mesh).ok):
			return _capture_failure("invalid_raw_array_mesh")
	var result: Dictionary = report()
	result["ok"] = true
	return result

func clear() -> void:
	for key in _mesh_cache.keys():
		_drop_mesh(int(key))
	_batches.clear()
	_entities.clear()
	_cache_builds = 0
	_cache_evictions = 0
	_cache_clock = 0
	last_query = {}

func _capture_failure(error: String) -> Dictionary:
	clear()
	return {"ok": false, "error": error}

func query(origin: Vector3, direction: Vector3, max_distance: float) -> Array[Dictionary]:
	var started: int = Time.get_ticks_usec()
	var hits: Array[Dictionary] = []
	last_query = {"batch_tests": 0, "instance_tests": 0, "broadphase_instances": 0,
		"triangle_tests": 0, "hidden_crown_triangles_skipped": 0, "hits": 0, "active_triangles": 0, "complete": false, "error": ""}
	if not origin.is_finite() or not direction.is_finite() or direction == Vector3.ZERO or is_nan(max_distance) or max_distance < 0.0:
		return _finish_query(hits, started, "invalid_ray")
	var largest: float = maxf(absf(direction.x), maxf(absf(direction.y), absf(direction.z)))
	var ray: Vector3 = (direction / largest).normalized()
	var live_meshes: Dictionary = {}
	var live_entities: Dictionary = {}
	var retained: Array[Dictionary] = []
	var prepared: Array[Dictionary] = []
	var active_triangles: int = 0
	# Complete preflight before returning any hits. Never truncate a query when
	# a changed mesh exceeds a budget, which could expose an occluded object.
	for batch in _batches:
		var node: MultiMeshInstance3D = batch.node.get_ref() as MultiMeshInstance3D
		if not _attached_alive(node):
			continue
		retained.append(batch)
		for identity in batch.rows:
			live_entities[str(identity.id)] = true
		if not node.is_visible_in_tree():
			continue
		var multimesh: MultiMesh = batch.multimesh.get_ref() as MultiMesh
		if multimesh == null or node.multimesh != multimesh or multimesh.instance_count != batch.rows.size():
			# A still-visible replacement can occlude another plant. Skipping it
			# would make the remaining hits falsely appear complete. Keep the
			# binding even while hidden so visibility changes cannot bypass this.
			return _finish_query(hits, started, "visible_instance_ownership_changed")
		var count: int = multimesh.instance_count
		if multimesh.visible_instance_count >= 0:
			count = mini(count, multimesh.visible_instance_count)
		if count <= 0:
			continue
		var mesh: ArrayMesh = multimesh.mesh as ArrayMesh
		if mesh == null:
			return _finish_query(hits, started, "current_mesh_is_not_array_mesh")
		live_meshes[mesh.get_instance_id()] = true
		var data: Dictionary = _mesh_data(mesh)
		if not bool(data.ok):
			return _finish_query(hits, started, "invalid_current_raw_mesh")
		active_triangles += count * int(data.triangles)
		if active_triangles > MAX_TRIANGLES:
			return _finish_query(hits, started, "current_triangle_budget_exceeded")
		prepared.append({"node": node, "multimesh": multimesh, "rows": batch.rows,
			"data": data, "count": count})
	_batches = retained
	_entities = live_entities
	# No accumulating old LOD resources or stale detached instance identities.
	for key in _mesh_cache.keys():
		if not live_meshes.has(key):
			_drop_mesh(int(key))
	last_query.active_triangles = active_triangles
	for batch in prepared:
		var node: MultiMeshInstance3D = batch.node
		var multimesh: MultiMesh = batch.multimesh
		var data: Dictionary = batch.data
		last_query.batch_tests += 1
		for slot in range(int(batch.count)):
			var mask: Color = multimesh.get_instance_custom_data(slot) if multimesh.use_custom_data else Color(1.0, 0.0, 0.0, 0.0)
			var crown_hidden: bool = str(node.get_meta(BodyCutaway.META_POLICY, "")) == BodyCutaway.POLICY and mask.b > 0.5 and mask.r < BodyCutaway.PICK_THRESHOLD
			var bark_triangles: int = int(roundf(mask.g / 3.0))
			var current: Transform3D = node.global_transform * multimesh.get_instance_transform(slot)
			if not current.is_finite() or current.basis.determinant() == 0.0:
				continue
			var inverse: Transform3D = current.affine_inverse()
			var local_origin: Vector3 = inverse * origin
			# Leave this unnormalized: t remains world distance under all affine
			# parents, including nonuniform scale, reflection and shear.
			var local_direction: Vector3 = inverse.basis * ray
			if not local_origin.is_finite() or not local_direction.is_finite():
				continue
			last_query.instance_tests += 1
			if not ray_box(data.bounds.grow(BROADPHASE_MARGIN), local_origin, local_direction, max_distance):
				continue
			last_query.broadphase_instances += 1
			var best: float = INF
			for surface in data.surfaces:
				var vertices: PackedVector3Array = surface.vertices
				var indices: PackedInt32Array = surface.indices
				var count: int = vertices.size() if indices.is_empty() else indices.size()
				if crown_hidden:
					var visible_count: int = mini(count, bark_triangles * 3)
					last_query.hidden_crown_triangles_skipped += int((count - visible_count) / 3)
					count = visible_count
				# Discarded crown triangles cannot select or occlude; continue
				# testing all remaining raw bark and every farther live instance.
				for index in range(0, count, 3):
					var a: Vector3 = vertices[index if indices.is_empty() else indices[index]]
					var b: Vector3 = vertices[index + 1 if indices.is_empty() else indices[index + 1]]
					var c: Vector3 = vertices[index + 2 if indices.is_empty() else indices[index + 2]]
					last_query.triangle_tests += 1
					var distance: float = ray_triangle(local_origin, local_direction, a, b, c)
					if distance >= 0.0 and distance <= max_distance and distance < best:
						best = distance
			if is_finite(best):
				var identity: Dictionary = batch.rows[slot]
				hits.append({"id": identity.id, "hex": identity.hex.duplicate(),
					"distance": best, "point": origin + ray * best})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.distance) < float(b.distance) if a.distance != b.distance else str(a.id) < str(b.id))
	return _finish_query(hits, started, "")

func _finish_query(hits: Array[Dictionary], started: int, error: String) -> Array[Dictionary]:
	last_query["elapsed_us"] = Time.get_ticks_usec() - started
	last_query["cache_entries"] = _mesh_cache.size()
	last_query["hits"] = hits.size()
	last_query["complete"] = error.is_empty()
	last_query["error"] = error
	return hits

static func _attached_alive(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	var ancestor: Node = node
	while ancestor != null:
		if ancestor.is_queued_for_deletion():
			return false
		ancestor = ancestor.get_parent()
	return true

static func _valid_hex(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)) or float(component) != floor(float(component)):
			return false
	return true

func _mesh_data(mesh: ArrayMesh) -> Dictionary:
	_cache_clock += 1
	var key: int = mesh.get_instance_id()
	if _mesh_cache.has(key) and _mesh_cache[key].resource.get_ref() == mesh:
		_mesh_cache[key].used = _cache_clock
		return _mesh_cache[key]
	if _mesh_cache.has(key):
		_drop_mesh(key)
	if _mesh_cache.size() >= MAX_CACHED_MESHES:
		var oldest_key: int = int(_mesh_cache.keys()[0])
		for candidate in _mesh_cache:
			if int(_mesh_cache[candidate].used) < int(_mesh_cache[oldest_key].used):
				oldest_key = int(candidate)
		_drop_mesh(oldest_key)
		_cache_evictions += 1
	var data: Dictionary = read_mesh(mesh)
	data["resource"] = weakref(mesh)
	data["used"] = _cache_clock
	var changed_callback: Callable = Callable(self, "_on_mesh_changed").bind(key)
	data["changed_callback"] = changed_callback
	mesh.changed.connect(changed_callback)
	_mesh_cache[key] = data
	_cache_builds += 1
	return data

func _on_mesh_changed(key: int) -> void:
	# In-place resource edits are not expected for admitted assets, but must
	# never keep stale triangles if they occur in a fixture or future renderer.
	_drop_mesh(key)

func _drop_mesh(key: int) -> void:
	if not _mesh_cache.has(key):
		return
	var entry: Dictionary = _mesh_cache[key]
	var resource: ArrayMesh = entry.resource.get_ref() as ArrayMesh
	var callback: Callable = entry.changed_callback
	if resource != null and resource.changed.is_connected(callback):
		resource.changed.disconnect(callback)
	_mesh_cache.erase(key)

static func read_mesh(mesh: ArrayMesh) -> Dictionary:
	var data: Dictionary = {"ok": false, "surfaces": [], "bounds": AABB(),
		"triangles": 0, "raw_pick_bytes": 0, "known_array_bytes": 0}
	if mesh == null or mesh.get_surface_count() <= 0 or mesh.get_surface_count() > MAX_MESH_SURFACES:
		return data
	var found: bool = false
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return data
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			return data
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		if vertices.size() > MAX_MESH_VERTICES or count % 3 != 0 or count > MAX_MESH_TRIANGLES * 3:
			return data
		for index in indices:
			if index < 0 or index >= vertices.size():
				return data
		for vertex in vertices:
			if not vertex.is_finite():
				return data
			data.bounds = data.bounds.expand(vertex) if found else AABB(vertex, Vector3.ZERO)
			found = true
		data.surfaces.append({"vertices": vertices, "indices": indices})
		data.triangles += int(count / 3)
		if int(data.triangles) > MAX_MESH_TRIANGLES:
			return data
		data.raw_pick_bytes += vertices.size() * 12 + indices.size() * 4
		data.known_array_bytes += vertices.size() * 12 + indices.size() * 4
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			data.known_array_bytes += arrays[Mesh.ARRAY_NORMAL].size() * 12
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			data.known_array_bytes += arrays[Mesh.ARRAY_COLOR].size() * 16
		if arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
			data.known_array_bytes += arrays[Mesh.ARRAY_TEX_UV2].size() * 8
	data.ok = found and int(data.triangles) > 0
	return data

static func ray_box(box: AABB, origin: Vector3, direction: Vector3, maximum: float) -> bool:
	var low: float = 0.0
	var high: float = maximum
	for axis in range(3):
		if direction[axis] == 0.0:
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]:
				return false
			continue
		var first: float = (box.position[axis] - origin[axis]) / direction[axis]
		var second: float = (box.end[axis] - origin[axis]) / direction[axis]
		low = maxf(low, minf(first, second))
		high = minf(high, maxf(first, second))
		if low > high:
			return false
	return true

static func ray_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	# Two-sided Moller-Trumbore on the actual raw vertices, without a proxy.
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var perpendicular: Vector3 = direction.cross(ac)
	var determinant: float = ab.dot(perpendicular)
	if determinant == 0.0:
		return -1.0
	var offset: Vector3 = origin - a
	var u: float = offset.dot(perpendicular) / determinant
	if u < 0.0 or u > 1.0:
		return -1.0
	var crossed: Vector3 = offset.cross(ab)
	var v: float = direction.dot(crossed) / determinant
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var distance: float = ac.dot(crossed) / determinant
	return distance if is_finite(distance) else -1.0

func report() -> Dictionary:
	var triangles: int = 0
	var native_bytes: int = 0
	for entry in _mesh_cache.values():
		triangles += int(entry.triangles)
		native_bytes += int(entry.raw_pick_bytes)
	return {"entity_count": _entities.size(), "batch_count": _batches.size(),
		"mesh_cache_entries": _mesh_cache.size(), "mesh_cache_limit": MAX_CACHED_MESHES,
		"cached_triangles": triangles, "cached_raw_pick_bytes": native_bytes,
		"cache_builds": _cache_builds, "cache_evictions": _cache_evictions,
		"vertex_source": "surface_get_arrays", "get_faces_proxy_used": false,
		"occlusion": "caller_supplied_world_distance_limit", "last_query": last_query.duplicate(true)}

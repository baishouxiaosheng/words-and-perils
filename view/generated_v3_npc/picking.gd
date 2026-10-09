extends RefCounted
## Read-only CPU picking of an admitted renderer's selection_nodes() snapshot.
## NPC-only presentation reuse of the accepted raw-array picker.
## Each physical mesh is tested once, then contributes to every captured owner.
## Mesh resources are immutable; mesh-only LOD swaps and current transforms are
## read on every query. Only raw surface arrays are used, never TriangleMesh.

const GLOW_NAME := "SelectedEdgeGlow"
const BROADPHASE_MARGIN := 0.000001
var _entities: Dictionary = {}
var _parts: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _cache_builds: int = 0
var last_query: Dictionary = {}

func capture(rows: Array) -> Dictionary:
	clear()
	for value in rows:
		if not value is Dictionary:
			return _capture_failure("invalid_selection_row")
		var row: Dictionary = value
		var id: String = str(row.get("id", ""))
		var kind: String = str(row.get("kind", ""))
		var hex: Variant = row.get("hex")
		var root: Variant = row.get("node")
		if id.is_empty() or kind not in ["actor"] or not hex is Array or hex.size() != 2:
			return _capture_failure("invalid_selection_identity")
		if not is_instance_valid(root) or not root is Node3D or root.is_queued_for_deletion():
			continue
		if _entities.has(id):
			if _entities[id].kind != kind or _entities[id].hex != hex:
				return _capture_failure("conflicting_selection_identity")
		else:
			_entities[id] = {"id": id, "kind": kind, "hex": hex.duplicate(true), "order": _entities.size()}
		_capture_node(root, root, id)
	# Warm only the current geometry. No resource or node is retained strongly.
	for part in _parts.values():
		var node: MeshInstance3D = part.node.get_ref() as MeshInstance3D
		if is_instance_valid(node) and node.mesh != null:
			_mesh_data(node.mesh)
	var result: Dictionary = report()
	result["ok"] = true
	return result

func clear() -> void:
	_entities.clear()
	_parts.clear()
	_mesh_cache.clear()
	_cache_builds = 0
	last_query = {}

func _capture_failure(error: String) -> Dictionary:
	clear()
	return {"ok": false, "error": error}

func _capture_node(node: Node, root: Node3D, id: String) -> void:
	# Also exclude an already-existing shell if capture is repeated after focus.
	if node.is_queued_for_deletion() or str(node.name) == GLOW_NAME:
		return
	if node is MeshInstance3D:
		var instance_id: int = node.get_instance_id()
		if not _parts.has(instance_id):
			_parts[instance_id] = {"node": weakref(node), "owners": {}}
		var owners: Dictionary = _parts[instance_id].owners
		if not owners.has(id):
			owners[id] = []
		var roots: Array = owners[id]
		var seen: bool = false
		for existing in roots:
			if existing.get_ref() == root:
				seen = true
		if not seen:
			roots.append(weakref(root))
	for child in node.get_children():
		_capture_node(child, root, id)

func query(origin: Vector3, direction: Vector3, max_distance: float) -> Array[Dictionary]:
	var started: int = Time.get_ticks_usec()
	var result: Array[Dictionary] = []
	last_query = {"mesh_tests": 0, "broadphase_meshes": 0, "triangle_tests": 0, "hits": 0}
	# Reject invalid inputs rather than producing NaN hits. Positive infinity is
	# a valid unbounded limit; zero allows a point on a forward-facing surface.
	if not origin.is_finite() or not direction.is_finite() or direction == Vector3.ZERO or is_nan(max_distance) or max_distance < 0.0:
		return result
	# Scale before normalization so finite tiny/huge directions cannot
	# underflow/overflow the Vector3 length calculation.
	var largest: float = maxf(absf(direction.x), maxf(absf(direction.y), absf(direction.z)))
	var ray: Vector3 = (direction / largest).normalized()
	var nearest: Dictionary = {}
	var live_meshes: Dictionary = {}
	var live_entities: Dictionary = {}
	for instance_id in _parts.keys():
		var part: Dictionary = _parts[instance_id]
		var node: MeshInstance3D = part.node.get_ref() as MeshInstance3D
		if not _attached_alive(node):
			_parts.erase(instance_id)
			continue
		var owners: Array[String] = _live_owners(part, node)
		if owners.is_empty():
			_parts.erase(instance_id)
			continue
		for id in owners:
			live_entities[id] = true
		if node.mesh == null or not node.is_visible_in_tree():
			continue
		var mesh: Mesh = node.mesh
		live_meshes[mesh.get_instance_id()] = true
		var data: Dictionary = _mesh_data(mesh)
		if not data.ok:
			continue
		var current: Transform3D = node.global_transform
		if not current.is_finite() or current.basis.determinant() == 0.0:
			continue
		var inverse: Transform3D = current.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		# Do NOT normalize this direction: its parameter remains world distance
		# even with rotation, reflection, nonuniform scale or a sheared parent.
		var local_direction: Vector3 = inverse.basis * ray
		if not local_origin.is_finite() or not local_direction.is_finite():
			continue
		last_query.mesh_tests += 1
		if not _ray_box(data.bounds.grow(BROADPHASE_MARGIN), local_origin, local_direction, max_distance):
			continue
		last_query.broadphase_meshes += 1
		var best: float = INF
		for surface in data.surfaces:
			var vertices: PackedVector3Array = surface.vertices
			var indices: PackedInt32Array = surface.indices
			var count: int = vertices.size() if indices.is_empty() else indices.size()
			for index in range(0, count, 3):
				var a: Vector3 = vertices[index if indices.is_empty() else indices[index]]
				var b: Vector3 = vertices[index + 1 if indices.is_empty() else indices[index + 1]]
				var c: Vector3 = vertices[index + 2 if indices.is_empty() else indices[index + 2]]
				last_query.triangle_tests += 1
				var distance: float = _ray_triangle(local_origin, local_direction, a, b, c)
				if distance >= 0.0 and distance <= max_distance and distance < best:
					best = distance
		if not is_finite(best):
			continue
		for id in owners:
			if not nearest.has(id) or best < float(nearest[id].distance):
				var entity: Dictionary = _entities[id]
				nearest[id] = {"id": id, "kind": entity.kind, "hex": entity.hex.duplicate(true),
					"distance": best, "point": origin + ray * best}
	# No accumulating old LOD resources, detached nodes, or stale entity IDs.
	for mesh_id in _mesh_cache.keys():
		if not live_meshes.has(mesh_id):
			_mesh_cache.erase(mesh_id)
	for id in _entities.keys():
		if not live_entities.has(id):
			_entities.erase(id)
	for hit in nearest.values():
		result.append(hit)
	# Renderer row order puts a building/road before its aggregate at equal depth.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance if a.distance != b.distance else _entities[a.id].order < _entities[b.id].order)
	last_query.hits = result.size()
	last_query["elapsed_us"] = Time.get_ticks_usec() - started
	last_query["cache_entries"] = _mesh_cache.size()
	return result

func _attached_alive(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	var ancestor: Node = node
	while ancestor != null:
		if ancestor.is_queued_for_deletion():
			return false
		ancestor = ancestor.get_parent()
	return true

func _live_owners(part: Dictionary, node: MeshInstance3D) -> Array[String]:
	var result: Array[String] = []
	var owners: Dictionary = part.owners
	for id in owners.keys():
		var roots: Array = []
		for reference in owners[id]:
			var root: Node3D = reference.get_ref() as Node3D
			if _attached_alive(root) and (root == node or root.is_ancestor_of(node)):
				roots.append(reference)
		if roots.is_empty():
			owners.erase(id)
		else:
			owners[id] = roots
			result.append(str(id))
	return result

func _mesh_data(mesh: Mesh) -> Dictionary:
	var key: int = mesh.get_instance_id()
	if _mesh_cache.has(key) and _mesh_cache[key].resource.get_ref() == mesh:
		return _mesh_cache[key]
	var data: Dictionary = {"ok": false, "resource": weakref(mesh), "surfaces": [],
		"bounds": AABB(), "triangles": 0, "native_bytes": 0}
	_mesh_cache[key] = data
	_cache_builds += 1
	var found: bool = false
	for surface_index in range(mesh.get_surface_count()):
		if mesh is ArrayMesh:
			if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:return data
		elif not mesh is PrimitiveMesh:return data
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			return data
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		if count % 3 != 0:
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
		data.native_bytes += vertices.size() * 12 + indices.size() * 4
	data.ok = found and data.triangles > 0
	return data

static func _ray_box(box: AABB, origin: Vector3, direction: Vector3, maximum: float) -> bool:
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

static func _ray_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	# Two-sided Moller-Trumbore on the original floats. A zero determinant
	# rejects degeneracy/parallel rays without a coordinate-size snap threshold.
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
		native_bytes += int(entry.native_bytes)
	return {"entity_count": _entities.size(), "mesh_instances": _parts.size(),
		"mesh_cache_entries": _mesh_cache.size(), "cached_triangles": triangles,
		"cached_native_bytes": native_bytes, "cache_builds": _cache_builds,
		"vertex_source": "surface_get_arrays", "get_faces_proxy_used": false}

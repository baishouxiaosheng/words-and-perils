extends SceneTree
## Bounded synthetic tests. Run through the parent's owned Godot QA queue:
## godot --headless --path . --script res://tests/generated_v3_placement/test_static_picking.gd
## No source generation, imported assets, physics, or authority state is needed.
const Picker = preload("res://view/generated_v3_settlement/picking.gd")
var checks: int = 0
var failures: Array[String] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func run() -> void:
	_raw_coordinate_case()
	_transformed_oracle_case()
	_shared_aggregate_case()
	_distance_limit_case()
	_lod_cache_case()
	_visibility_lifetime_case()
	_capture_reset_case()
	print("V3_STATIC_PICKING_REPORT ", JSON.stringify({"checks": checks,
		"passed": checks - failures.size(), "failures": failures, "evidence": evidence}))
	print("V3 STATIC PICKING ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)

func _root() -> Node3D:
	var node: Node3D = Node3D.new()
	get_root().add_child(node)
	return node

func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array = PackedInt32Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _plane(height: float = 0.0, right: float = 1.0) -> ArrayMesh:
	return _mesh(PackedVector3Array([Vector3(-1, height, -1), Vector3(right, height, -1),
		Vector3(right, height, 1), Vector3(-1, height, 1)]), PackedInt32Array([0, 2, 1, 0, 3, 2]))

func _part(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	return node

func _row(id: String, node: Node3D, kind: String = "building", hex: Array = [2, -1]) -> Dictionary:
	return {"id": id, "kind": kind, "hex": hex, "node": node}

func _raw_coordinate_case() -> void:
	var root: Node3D = _root()
	var raw_x: float = 0.251514077
	var mesh: ArrayMesh = _plane(0.0, raw_x)
	var original_vertices: PackedByteArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()
	var original_indices: PackedByteArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].to_byte_array()
	var node: MeshInstance3D = _part(root, mesh)
	var picker = Picker.new()
	check(picker.capture([_row("raw", node)]).ok, "raw arrays capture")
	var origin: Vector3 = Vector3(0.251507, 2.0, 0.0)
	var hits: Array[Dictionary] = picker.query(origin, Vector3.DOWN, 10.0)
	check(hits.size() == 1, "raw boundary sliver is hittable before .0001 proxy snapping")
	if not hits.is_empty():
		check(absf(hits[0].distance - 2.0) < 0.000001 and hits[0].point.distance_to(Vector3(origin.x, 0, 0)) < 0.000001, "raw boundary exact point and distance")
	# Reproduce only the known coordinate quantization, without using get_faces.
	node.mesh = _plane(0.0, snappedf(raw_x, 0.0001))
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "manually snapped proxy loses the raw boundary sliver")
	node.mesh = _mesh(PackedVector3Array([Vector3(raw_x, -1, -1), Vector3(raw_x, 1, -1), Vector3(raw_x, 0, 1)]))
	var native_x: float = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].x
	hits = picker.query(Vector3(2, 0, 0), Vector3.LEFT, 10.0)
	check(hits.size() == 1, "nonindexed surface is hit")
	if not hits.is_empty():
		check(absf(hits[0].distance - (2.0 - native_x)) < 0.000001, "native coordinate distance is not snapped")
		check(absf(hits[0].distance - (2.0 - snappedf(native_x, 0.0001))) > 0.00001, "native distance distinguishes .0001 proxy")
		evidence["raw_distance"] = {"native_x": native_x, "distance": hits[0].distance,
			"snapped_distance": 2.0 - snappedf(native_x, 0.0001)}
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array() == original_vertices and mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].to_byte_array() == original_indices, "picking preserves original vertex and index bytes")
	check(picker.report().vertex_source == "surface_get_arrays" and not picker.report().get_faces_proxy_used, "raw native array provenance")
	root.free()

func _transformed_oracle_case() -> void:
	var root: Node3D = _root()
	var nested: Node3D = Node3D.new()
	root.add_child(nested)
	root.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.5, -0.2)), Vector3(3, 2, -5))
	nested.transform = Transform3D(Basis.from_euler(Vector3(-0.3, 0.2, 0.4)).scaled(Vector3(1.7, 0.6, 0.8)), Vector3(-1, 0.7, 2))
	var mesh: ArrayMesh = _mesh(PackedVector3Array([Vector3(-1, 0.137514, -1), Vector3(1, 0.137514, -1), Vector3(0, 0.137514, 1)]))
	# Add a second indexed surface, lower in local Y, to check every surface.
	var arrays: Array = _plane(-0.4).surface_get_arrays(0)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node: MeshInstance3D = _part(nested, mesh)
	node.transform = Transform3D(Basis(Vector3(-1.2, 0, 0), Vector3(0.15, 0.8, 0), Vector3(0, 0, 1.4)), Vector3(0.2, 0, -0.3))
	var picker = Picker.new()
	picker.capture([_row("transformed", root)])
	var local_target: Vector3 = Vector3(0, 0.137514, -0.1)
	var world_target: Vector3 = node.global_transform * local_target
	var normal: Vector3 = (node.global_transform.basis.inverse().transposed() * Vector3.UP).normalized()
	var origin: Vector3 = world_target + normal * 4.5
	var hits: Array[Dictionary] = picker.query(origin, -normal * 7.0, 20.0)
	var oracle: Dictionary = _brute_world(mesh, node.global_transform, origin, -normal, 20.0)
	check(hits.size() == 1 and not oracle.is_empty(), "nested reflected nonuniform and sheared mesh is hit")
	if not hits.is_empty() and not oracle.is_empty():
		check(absf(hits[0].distance - oracle.distance) < 0.00001, "local-space hit matches independent world-space brute oracle")
		check(hits[0].point.distance_to(oracle.point) < 0.00002, "transformed world hit point matches brute oracle")
		check(absf(hits[0].distance - 4.5) < 0.00002, "unnormalized caller direction returns world distance")
	check(picker.last_query.triangle_tests == 3, "all indexed and nonindexed surfaces are tested")
	var builds: int = picker.report().cache_builds
	node.position.y += 0.25
	oracle = _brute_world(mesh, node.global_transform, origin, -normal, 20.0)
	hits = picker.query(origin, -normal, 20.0)
	check(not hits.is_empty() and not oracle.is_empty(), "changed transform still picks current mesh")
	if not hits.is_empty() and not oracle.is_empty():
		check(absf(hits[0].distance - oracle.distance) < 0.00001, "live transform changes match world oracle without recapture")
	check(picker.report().cache_builds == builds, "transform-only changes reuse native mesh cache")
	node.scale = Vector3.ZERO
	check(picker.query(origin, -normal, 20.0).is_empty(), "singular transform is excluded safely")
	root.free()

func _shared_aggregate_case() -> void:
	var root: Node3D = _root()
	var building: Node3D = Node3D.new()
	root.add_child(building)
	var shared: ArrayMesh = _plane()
	var first: MeshInstance3D = _part(building, shared)
	var second: MeshInstance3D = _part(building, shared)
	second.position.y = -1.0
	var road: MeshInstance3D = _part(root, shared)
	road.position = Vector3(4, 0, 0)
	var rows: Array = [_row("building", building), _row("road", road, "road"), _row("village", root, "settlement")]
	var picker = Picker.new()
	var captured: Dictionary = picker.capture(rows)
	check(captured.ok and captured.mesh_instances == 3 and captured.entity_count == 3, "aggregate and child reuse each physical mesh once")
	check(captured.mesh_cache_entries == 1 and captured.cached_triangles == 2, "separate instances share one immutable resource cache")
	var hits: Array[Dictionary] = picker.query(Vector3(0, 3, 0), Vector3.DOWN, 10.0)
	check(hits.size() == 2, "nearest hit emitted once for building and once for aggregate")
	if hits.size() == 2:
		check(hits[0].id == "building" and hits[1].id == "village", "equal-distance tie follows renderer specific-before-aggregate order")
		check(hits[0].distance == 3.0 and hits[1].distance == 3.0, "nearest semantic hit ignores deeper geometry for same ID")
		check(hits[0].keys().size() == 5 and hits[0].has_all(["id", "kind", "hex", "distance", "point"]), "only raw source identity and geometry are returned")
		hits[0].hex[0] = 99
		check(rows[0].hex == [2, -1], "returned hex cannot mutate renderer rows")
	check(picker.last_query.mesh_tests == 3 and picker.last_query.broadphase_meshes == 2 and picker.last_query.triangle_tests == 4, "physical triangles are tested once across all semantic owners with AABB culling")
	rows[0].hex[0] = 42
	hits = picker.query(Vector3(0, 3, 0), Vector3.DOWN, 10.0)
	check(not hits.is_empty() and hits[0].hex == [2, -1], "capture owns an isolated identity snapshot")
	var glow: MeshInstance3D = _part(first, _plane(2.0))
	glow.name = "SelectedEdgeGlow"
	var extra: MeshInstance3D = _part(glow, _plane(2.5))
	extra.name = "GlowNestedGeometry"
	hits = picker.query(Vector3(0, 3, 0), Vector3.DOWN, 10.0)
	check(not hits.is_empty() and hits[0].distance == 3.0 and picker.report().mesh_instances == 3, "later attention glow and its children are never captured")
	rows[0].hex[0] = 2
	picker.capture(rows)
	hits = picker.query(Vector3(0, 3, 0), Vector3.DOWN, 10.0)
	check(not hits.is_empty() and hits[0].distance == 3.0 and picker.report().mesh_instances == 3, "recapture also excludes existing attention glow subtree")
	root.free()

func _distance_limit_case() -> void:
	var root: Node3D = _root()
	var near: MeshInstance3D = _part(root, _plane(1.0))
	var far: MeshInstance3D = _part(root, _plane(-1.0))
	var behind: MeshInstance3D = _part(root, _plane(5.0))
	var picker = Picker.new()
	picker.capture([_row("far", far), _row("behind", behind), _row("near", near)])
	var origin: Vector3 = Vector3(0.2, 3, 0.1)
	var hits: Array[Dictionary] = picker.query(origin, Vector3.DOWN, 10.0)
	check(hits.size() == 2 and hits[0].id == "near" and hits[1].id == "far", "all forward semantic hits returned sorted without actor/item occlusion decisions")
	hits = picker.query(origin, Vector3.DOWN, 2.0)
	check(hits.size() == 1 and hits[0].id == "near" and hits[0].distance == 2.0, "opaque-board distance bound is inclusive")
	check(picker.query(origin, Vector3.DOWN, 1.999).is_empty(), "distance limit excludes geometry beyond opaque occluder")
	check(picker.query(Vector3(0.2, 1, 0.1), Vector3.DOWN, 0.0).size() == 1, "zero-distance surface hit remains forward")
	check(picker.query(origin, Vector3.ZERO, 10.0).is_empty(), "zero ray rejected")
	check(picker.query(origin, Vector3.DOWN, -1.0).is_empty(), "negative distance rejected")
	check(picker.query(origin, Vector3.DOWN, NAN).is_empty(), "NaN distance rejected")
	check(picker.query(Vector3(INF, 0, 0), Vector3.DOWN, 10.0).is_empty(), "nonfinite origin rejected")
	check(picker.query(origin, Vector3(0, NAN, 0), 10.0).is_empty(), "nonfinite direction rejected")
	check(picker.query(origin, Vector3.DOWN, INF).size() == 2, "unbounded positive limit remains supported")
	check(picker.query(origin, Vector3(0, -1.0e30, 0), 10.0).size() == 2, "huge finite direction normalizes without overflow")
	check(picker.query(origin, Vector3(0, -1.0e-30, 0), 10.0).size() == 2, "tiny finite nonzero direction normalizes without underflow")
	root.free()

func _lod_cache_case() -> void:
	var root: Node3D = _root()
	var full: ArrayMesh = _plane(0.0)
	var low: ArrayMesh = _plane(0.5)
	var node: MeshInstance3D = _part(root, full)
	var picker = Picker.new()
	picker.capture([_row("lod", root)])
	var origin: Vector3 = Vector3(0.2, 3, 0.1)
	var transform_before: Transform3D = node.transform
	var memory_bound: int = picker.report().cached_native_bytes
	for index in range(40):
		node.mesh = low if index % 2 == 0 else full
		var hits: Array[Dictionary] = picker.query(origin, Vector3.DOWN, 10.0)
		var expected: float = 2.5 if index % 2 == 0 else 3.0
		check(hits.size() == 1 and absf(hits[0].distance - expected) < 0.000001, "LOD swap %d uses current mesh without recapture" % index)
		check(picker.report().mesh_cache_entries == 1 and picker.report().cached_native_bytes == memory_bound, "LOD swap %d cache bounded by current mesh" % index)
	check(node.transform == transform_before, "LOD picking never refits or recenters renderer")
	var builds: int = picker.report().cache_builds
	for _index in range(32):
		picker.query(origin, Vector3.DOWN, 10.0)
	check(picker.report().cache_builds == builds, "repeated queries do not rebuild or accumulate mesh arrays")
	# Distinct transient resources must not remain retained by the picker.
	var previous_resource: WeakRef = null
	var released: bool = true
	for index in range(24):
		node.mesh = _plane(float(index) * 0.01)
		picker.query(origin, Vector3.DOWN, 10.0)
		if previous_resource != null and previous_resource.get_ref() != null:
			released = false
		previous_resource = weakref(node.mesh)
		check(picker.report().mesh_cache_entries == 1 and picker.report().cached_native_bytes == memory_bound, "transient LOD %d does not grow cache" % index)
	check(released, "cached raw arrays do not strongly retain prior mesh resources")
	evidence["bounded_cache"] = picker.report()
	root.free()
	picker.query(origin, Vector3.DOWN, 10.0)
	check(picker.report().mesh_instances == 0 and picker.report().mesh_cache_entries == 0 and picker.report().cached_native_bytes == 0, "dead mesh nodes and cached array storage are reclaimed on next query")

func _visibility_lifetime_case() -> void:
	var root: Node3D = _root()
	var node: MeshInstance3D = _part(root, _plane())
	var picker = Picker.new()
	picker.capture([_row("visible", root)])
	var origin: Vector3 = Vector3(0.2, 3, 0.1)
	node.hide()
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "hidden mesh excluded")
	node.show()
	check(picker.query(origin, Vector3.DOWN, 10.0).size() == 1, "reshown captured mesh remains eligible")
	root.hide()
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "hidden ancestor excluded")
	root.show()
	check(picker.query(origin, Vector3.DOWN, 10.0).size() == 1, "reshown ancestor restores captured geometry")
	var outside: Node3D = _root()
	node.reparent(outside)
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty() and picker.report().mesh_instances == 0, "mesh moved outside captured owner is excluded and pruned")
	node.reparent(root)
	picker.capture([_row("visible", root)])
	root.remove_child(node)
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "detached node excluded before free")
	check(picker.report().mesh_cache_entries == 0 and picker.report().entity_count == 0, "removed node releases cache and stale identity")
	root.add_child(node)
	picker.capture([_row("visible", root)])
	node.queue_free()
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "queued mesh deletion excluded before end of frame")
	var live: MeshInstance3D = _part(root, _plane())
	picker.capture([_row("queued_parent", live)])
	root.queue_free()
	check(picker.query(origin, Vector3.DOWN, 10.0).is_empty(), "queued ancestor deletion excluded even when row names its child")
	root.free()
	outside.free()

func _capture_reset_case() -> void:
	var root: Node3D = _root()
	var node: MeshInstance3D = _part(root, _plane())
	var picker = Picker.new()
	for _index in range(20):
		picker.capture([_row("repeat", root), _row("repeat", root)])
	check(picker.report().entity_count == 1 and picker.report().mesh_instances == 1 and picker.report().cached_triangles == 2, "duplicate rows and repeated captures do not accumulate geometry")
	check(picker.query(Vector3(0, 2, 0), Vector3.DOWN, 10.0).size() == 1, "duplicate semantic identity emits a single nearest hit")
	var conflicting: Dictionary = _row("repeat", node, "road")
	check(not picker.capture([_row("repeat", root), conflicting]).ok, "conflicting identity capture fails closed")
	check(picker.query(Vector3(0, 2, 0), Vector3.DOWN, 10.0).is_empty(), "failed recapture cannot retain old semantic picks")
	check(picker.capture([]).ok and picker.report().cached_native_bytes == 0, "empty capture fully resets state")
	root.free()

func _brute_world(mesh: Mesh, transform_: Transform3D, origin: Vector3, direction: Vector3, maximum: float) -> Dictionary:
	# Independent oracle: transformed world vertices, plane intersection, and
	# barycentric dot products. It shares neither picker narrowphase nor AABB.
	var ray: Vector3 = direction.normalized()
	var nearest: float = INF
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		for index in range(0, count, 3):
			var a: Vector3 = transform_ * vertices[index if indices.is_empty() else indices[index]]
			var b: Vector3 = transform_ * vertices[index + 1 if indices.is_empty() else indices[index + 1]]
			var c: Vector3 = transform_ * vertices[index + 2 if indices.is_empty() else indices[index + 2]]
			var ab: Vector3 = b - a
			var ac: Vector3 = c - a
			var normal: Vector3 = ab.cross(ac)
			var denominator: float = normal.dot(ray)
			if denominator == 0.0:
				continue
			var distance: float = normal.dot(a - origin) / denominator
			if distance < 0.0 or distance > maximum or distance >= nearest:
				continue
			var offset: Vector3 = origin + ray * distance - a
			var aa: float = ab.dot(ab)
			var bb: float = ac.dot(ac)
			var cross_: float = ab.dot(ac)
			var determinant: float = aa * bb - cross_ * cross_
			if determinant == 0.0:
				continue
			var u: float = (bb * offset.dot(ab) - cross_ * offset.dot(ac)) / determinant
			var v: float = (aa * offset.dot(ac) - cross_ * offset.dot(ab)) / determinant
			if u >= 0.0 and v >= 0.0 and u + v <= 1.0:
				nearest = distance
	return {"distance": nearest, "point": origin + ray * nearest} if is_finite(nearest) else {}

extends SceneTree
## Standalone synthetic fixture. No terrain/planner/catalog/factory is loaded.
## Run only in the owner's allocated engine slot:
## godot --rendering-method gl_compatibility --path <candidate> --script res://tests/test_generated_v3_vegetation_picking.gd
## Requires a real display renderer (an owned Xvfb display is sufficient).
## --headless uses dummy MultiMesh setters/getters and cannot prove live transforms.

const Picker = preload("res://view/generated_v3_vegetation/picking.gd")
var _checks: int = 0
var _failures: Array[String] = []
var _world: Node3D
var _picker: RefCounted = Picker.new()

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)

func _mesh(y: float = 0.0, indexed: bool = false, width: float = 1.0) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-width, y, -width), Vector3(width, y, -width), Vector3(0, y, width)])
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _node(mesh: ArrayMesh, transforms: Array) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = multimesh
	_world.add_child(node)
	return node

func _capture(node: MultiMeshInstance3D, ids: Array) -> Dictionary:
	var rows: Array = []
	for id in ids:
		rows.append({"id": id, "hex": [2, -1]})
	return _picker.capture([{"node": node, "rows": rows}])

func _down(limit: float = INF, x: float = 0.0, z: float = 0.0) -> Array[Dictionary]:
	return _picker.query(Vector3(x, 10, z), Vector3.DOWN, limit)

func _near(actual: float, expected: float, tolerance: float = 0.00002) -> bool:
	return absf(actual - expected) <= tolerance

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var near_mesh: ArrayMesh = _mesh()
	var node: MultiMeshInstance3D = _node(near_mesh, [Transform3D.IDENTITY])
	_check(bool(_capture(node, ["v3:plant:a"]).ok), "capture plain triangle")
	var hits: Array[Dictionary] = _down()
	_check(hits.size() == 1 and hits[0].id == "v3:plant:a", "source row identity retained")
	_check(hits.size() == 1 and _near(float(hits[0].distance), 10.0), "world distance for unindexed triangle")
	_check(hits.size() == 1 and hits[0].point.is_equal_approx(Vector3.ZERO), "reported actual point")
	_check(hits.size() == 1 and hits[0].hex == [2, -1], "owning hex retained")
	_check(_down(9.99).is_empty(), "occluded by smaller caller limit")
	_check(_down(10.0).size() == 1, "exact occluder boundary is inclusive")
	_check(_down(INF, 0.95, 0.95).is_empty(), "AABB overlap alone cannot create triangle hit")
	_check(_picker.query(Vector3.ZERO, Vector3.UP, 0.0).size() == 1, "zero-distance surface hit")
	_check(_picker.query(Vector3(0, -10, 0), Vector3.UP, INF).size() == 1, "two-sided raw triangle")
	_check(_picker.query(Vector3(0, 10, 0), Vector3(0, -1e-30, 0), INF).size() == 1, "tiny finite direction normalization")
	_check(_picker.query(Vector3(0, 10, 0), Vector3(0, -1e30, 0), INF).size() == 1, "huge finite direction normalization")
	for invalid in [Vector3.ZERO, Vector3(NAN, 0, 0), Vector3(INF, 0, 0)]:
		_check(_picker.query(Vector3.ZERO, invalid, INF).is_empty(), "invalid direction rejected")
	_check(_picker.query(Vector3(NAN, 0, 0), Vector3.DOWN, INF).is_empty(), "invalid origin rejected")
	_check(_down(-1.0).is_empty() and _down(NAN).is_empty(), "invalid limit rejected")
	var indexed: ArrayMesh = _mesh(2.0, true)
	node.multimesh.mesh = indexed
	hits = _down()
	_check(hits.size() == 1 and _near(float(hits[0].distance), 8.0), "live indexed LOD mesh swap")
	_check(int(_picker.report().mesh_cache_entries) == 1, "old inactive LOD raw cache evicted")
	node.multimesh.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(2, 3, 0.5)), Vector3(1, 1, 0)))
	hits = _down(INF, 1.0)
	_check(hits.size() == 1 and _near(float(hits[0].distance), 3.0), "current nonuniform instance transform")
	# Test a reflected/sheared parent and rotated instance against a ray aimed
	# at an actual known local point, with a known 7-unit world distance.
	node.transform = Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.4, 1.2, 0.1), Vector3(0.2, 0.0, 1.1)), Vector3(4, 0.5, -2))
	node.multimesh.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.3, 0.8, 0.6)), Vector3(1, 0.2, 0.3)))
	var current: Transform3D = node.global_transform * node.multimesh.get_instance_transform(0)
	var target: Vector3 = current * Vector3(0, 2, 0)
	var ray: Vector3 = Vector3(0.1, -1.0, 0.2).normalized()
	hits = _picker.query(target - ray * 7.0, ray, 7.001)
	_check(hits.size() == 1 and _near(float(hits[0].distance), 7.0), "rotation reflection shear maintain world ray parameter")
	node.transform = Transform3D.IDENTITY
	node.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	node.visible = false
	_check(_down().is_empty(), "hidden batch not pickable")
	node.visible = true
	_world.visible = false
	_check(_down().is_empty(), "hidden ancestor not pickable")
	_world.visible = true
	node.multimesh.visible_instance_count = 0
	_check(_down().is_empty(), "visible instance count zero not pickable")
	node.multimesh.visible_instance_count = -1
	node.multimesh.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_check(_down().is_empty(), "zero-basis disabled instance not pickable")
	node.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	# A shell nearer to the camera must never enter the explicitly captured set.
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "SelectedVegetationGlow"
	shell.mesh = _mesh(9.0)
	node.add_child(shell)
	hits = _down()
	_check(hits.size() == 1 and _near(float(hits[0].distance), 8.0), "highlight excluded from hit/occlusion data")
	# Resource change invalidates immutable raw snapshots, not row ownership.
	indexed.clear_surfaces()
	var replacement_arrays: Array = []
	replacement_arrays.resize(Mesh.ARRAY_MAX)
	replacement_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 3, -1), Vector3(1, 3, -1), Vector3(0, 3, 1)])
	indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, replacement_arrays)
	indexed.emit_changed()
	hits = _down()
	_check(hits.size() == 1 and _near(float(hits[0].distance), 7.0), "changed raw resource invalidates cached triangles")
	# Many mesh swaps must not retain historical resource IDs or raw buffers.
	for index in range(24):
		node.multimesh.mesh = _mesh(float(index % 5))
		_down()
	_check(int(_picker.report().mesh_cache_entries) == 1, "repeated LOD swaps leave one active mesh cache entry")
	var original_multimesh: MultiMesh = node.multimesh
	var replacement: MultiMesh = MultiMesh.new()
	replacement.transform_format = MultiMesh.TRANSFORM_3D
	replacement.mesh = near_mesh
	replacement.instance_count = 1
	replacement.set_instance_transform(0, Transform3D.IDENTITY)
	node.multimesh = replacement
	_check(_down().is_empty(), "replacing instance buffer cannot inherit old source IDs")
	node.multimesh = original_multimesh
	_check(_down().size() == 1, "restoring the exact captured buffer restores valid ownership")
	_check(bool(_capture(node, ["v3:plant:new"]).ok), "explicit recapture restores only new identity")
	hits = _down()
	_check(hits.size() == 1 and hits[0].id == "v3:plant:new", "no old identity after recapture")
	_world.remove_child(node)
	_check(_down().is_empty() and int(_picker.report().entity_count) == 0, "detached node and identities pruned")
	node.free()
	# Equal-depth ties use source IDs, not engine instance ID or capture order.
	node = _node(near_mesh, [Transform3D.IDENTITY, Transform3D.IDENTITY])
	_check(bool(_capture(node, ["v3:plant:z", "v3:plant:a"]).ok), "capture independent source slots")
	hits = _down()
	_check(hits.size() == 2 and hits[0].id == "v3:plant:a", "stable ID tie break")
	node.multimesh.visible_instance_count = 1
	hits = _down()
	_check(hits.size() == 1 and hits[0].id == "v3:plant:z", "visible prefix preserves source slot identity")
	node.multimesh.visible_instance_count = -1
	node.multimesh.instance_count = 1
	_check(_down().is_empty(), "changed slot count invalidates captured ownership")
	_check(not bool(_capture(node, ["a", "b"]).ok), "count mismatch capture fails closed")
	node.multimesh.instance_count = 2
	_check(not bool(_capture(node, ["same", "same"]).ok), "duplicate source IDs rejected")
	_check(int(_picker.report().entity_count) == 0, "failed capture leaves no partial identity")
	node.queue_free()
	_picker.clear()
	# An invalid visible foreground batch must fail the complete query, never
	# expose a valid farther row; hidden invalid batches cannot occlude.
	var foreground: MultiMeshInstance3D = _node(_mesh(7.0), [Transform3D.IDENTITY])
	var background: MultiMeshInstance3D = _node(_mesh(0.0), [Transform3D.IDENTITY])
	var captured_mm: MultiMesh = foreground.multimesh
	_check(bool(_picker.capture([
		{"node": foreground, "rows": [{"id": "front", "hex": [0, 0]}]},
		{"node": background, "rows": [{"id": "back", "hex": [0, 0]}]}]).ok), "capture foreground and background")
	foreground.multimesh = replacement
	_check(_down().is_empty() and not bool(_picker.last_query.complete), "visible replaced occluder fails whole query")
	foreground.visible = false
	hits = _down()
	_check(hits.size() == 1 and hits[0].id == "back" and bool(_picker.last_query.complete), "hidden replaced batch safely omitted")
	foreground.visible = true
	_check(_down().is_empty() and not bool(_picker.last_query.complete), "hidden replacement cannot become untracked visible occluder")
	foreground.multimesh = captured_mm
	hits = _down()
	_check(hits.size() == 2 and hits[0].id == "front" and bool(_picker.last_query.complete), "exact original instance binding restored")
	foreground.multimesh.instance_count = 2
	_check(_down().is_empty() and not bool(_picker.last_query.complete), "visible changed slot count fails whole query")
	foreground.visible = false
	hits = _down()
	_check(hits.size() == 1 and hits[0].id == "back" and bool(_picker.last_query.complete), "hidden changed slot count does not block valid hit")
	_picker.clear()
	print(JSON.stringify({"fixture": "generated_v3_vegetation_raw_multimesh_picker", "ok": _failures.is_empty(),
		"checks": _checks, "failures": _failures, "uses_real_terrain": false, "uses_get_faces": false}))
	quit(0 if _failures.is_empty() else 1)

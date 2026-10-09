extends SceneTree
## Synthetic renderer-contract fixture; not planner/source admission evidence.
## Run with real gl_compatibility/display, not --headless dummy mesh storage.
const View = preload("res://view/generated_v3_vegetation/vegetation_view.gd")
const IDS := ["temperate", "tropical", "sapling", "shrub", "tuft", "reed"]
var _checks: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)

func _mesh(y: float, triangles: int = 1) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	for index in range(triangles):
		vertices.append(Vector3(-1, y, -1))
		vertices.append(Vector3(1, y, -1))
		vertices.append(Vector3(0, y, 1))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _assets(triangles: int = 1) -> Dictionary:
	var full: Dictionary = {}
	var far: Dictionary = {}
	for id in IDS:
		full[id] = _mesh(0.0, triangles)
		far[id] = full[id] if id in ["tuft", "reed"] else _mesh(0.8)
	return {"full_meshes": full, "far_meshes": far, "catalog": {"fixture_only": true}}

func _row(index: int, asset_id: String, position_: Array) -> Dictionary:
	return {"id": "fixture:plant:%04d" % index, "hex": [0, 0], "asset_id": asset_id,
		"biome": "fixture", "position": position_, "radius": 0.15, "height": 1.2,
		"yaw": 0.7, "tint": 0.95, "root_footprint": [], "solid_footprint": [],
		"canopy_footprint": [], "support": {}, "row_hash": "fixture_only"}

func _result(rows: Array, assets: Dictionary) -> Dictionary:
	return {"ok": true, "manifest": {"schema_version": "generated_v3_vegetation/v1",
		"profile_id": "sparse_biomes/v1", "plants": rows}, "assets": assets,
		"surface": null, "diagnostics": {"fixture_only": true}}

func _run() -> void:
	var view: Node3D = View.new()
	root.add_child(view)
	var rows: Array = []
	for asset_index in range(IDS.size()):
		for x in [-23.0, -7.0, 9.0]:
			for z in [-23.0, -7.0, 9.0]:
				for duplicate in range(2):
					rows.append(_row(rows.size(), IDS[asset_index], [x + float(asset_index) * 1.5, 0.0, z + float(duplicate)]))
	var assets: Dictionary = _assets()
	var supplied: Dictionary = _result(rows, assets)
	var source_json: String = JSON.stringify(supplied.manifest)
	_check(bool(view.configure(supplied).ok), "configure valid synthetic admitted shape")
	var report: Dictionary = view.report()
	_check(int(report.plants) == 108, "108 source rows retained")
	_check(int(report.batch_nodes) == 54 and int(report.active_batches) == 54, "six assets across fixed nine chunks give 54 active batches")
	_check(int(report.per_plant_nodes) == 0 and int(report.physics_nodes) == 0, "no plant scene or physics nodes")
	_check(int(report.shared_mesh_resources) == 10 and int(report.shared_material_resources) == 1, "shared full/far resources with tuft/reed no-far paths")
	_check(int(report.instance_buffer_bytes) == 108 * 20 * 4, "native MultiMesh transform+color+cutaway-mask buffer accounting")
	_check(JSON.stringify(supplied.manifest) == source_json, "renderer does not mutate supplied authoritative manifest")
	var groups: Array = view.get("_groups")
	var materials: Dictionary = {}
	for group in groups:
		var node: MultiMeshInstance3D = group.node
		materials[node.material_override.get_instance_id()] = true
		_check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "batch shadows disabled")
	_check(materials.size() == 1, "one shared original vegetation shader material")
	var slots: Dictionary = view.get("_slots")
	var first: Dictionary = slots["fixture:plant:0000"]
	var first_node: MultiMeshInstance3D = first.node.get_ref() as MultiMeshInstance3D
	var expected: Transform3D = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(0.15, 1.2, 0.15)), Vector3(-23, 0, -23))
	_check(first_node.multimesh.get_instance_transform(int(first.slot)).is_equal_approx(expected), "exact positive-yaw row transform without refit/recenter")
	var color: Color = first_node.multimesh.get_instance_color(int(first.slot))
	_check(absf(color.r - 0.95) < 0.001 and color.r == color.g and color.g == color.b, "scalar tint preserved")
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.size = 22.0
	view.update_lod(camera)
	report = view.report()
	_check(report.lod == "far_same_footprint" and int(report.mesh_swaps) == 36, "far threshold swaps woody groups only")
	for group in groups:
		_check(group.node.multimesh.mesh == group.far, "current live mesh matches far catalog resource")
	camera.size = 21.0
	view.update_lod(camera)
	_check(view.report().lod == "far_same_footprint", "hysteresis retains far at size21")
	camera.size = 20.0
	view.update_lod(camera)
	_check(view.report().lod == "full" and int(view.report().lod_switches) == 2, "size20 restores full")
	camera.size = 21.0
	view.update_lod(camera)
	_check(view.report().lod == "full", "hysteresis retains full at size21")
	_check(bool(view.select("fixture:plant:0000")), "select known row")
	var hit: Array = view.pick(Vector3(-23, 10, -23), Vector3.DOWN, INF)
	_check(hit.size() == 1 and hit[0].id == "fixture:plant:0000" and absf(float(hit[0].distance) - 10.0) < 0.0001, "selection shell excluded from full LOD pick")
	_check(int(view.report().selection_draw_calls) == 1 and int(view.report().picker.entity_count) == 108, "one shell with unchanged source pick set")
	camera.size = 22.0
	view.update_lod(camera)
	hit = view.pick(Vector3(-23, 10, -23), Vector3.DOWN, INF)
	_check(hit.size() == 1 and absf(float(hit[0].distance) - 9.04) < 0.0001, "picker and shell follow current far raw triangles")
	var shell: MeshInstance3D = view.get("_highlight") as MeshInstance3D
	_check(shell.mesh == first_node.multimesh.mesh, "shell shares active LOD mesh")
	first_node.visible = false
	view.update_lod(camera)
	_check(view.pick(Vector3(-23, 10, -23), Vector3.DOWN, INF).is_empty() and not shell.visible, "hidden batch cannot leave picked/highlighted geometry")
	first_node.visible = true
	_check(not bool(view.select("not:a:source:row")), "unknown selection clears highlight")
	_check(not shell.visible, "unknown selection hides shell")
	# Reconfiguration is replacement, never append: old IDs and buffers vanish.
	var replacement: Dictionary = _result([_row(999, "tuft", [1.0, 0.0, 1.0])], assets)
	_check(bool(view.configure(replacement).ok), "reconfigure replacement source")
	_check(int(view.report().plants) == 1 and int(view.report().batch_nodes) == 1, "reconfigure clears old batches")
	_check(not bool(view.select("fixture:plant:0000")), "old source ID not selectable after replacement")
	var bad_tint: Dictionary = _result([_row(0, "tuft", [0.0, 0.0, 0.0])], assets)
	bad_tint.manifest.plants[0].tint = [1, 1, 1, 1]
	_check(not bool(view.configure(bad_tint).ok), "non-scalar tint rejected")
	var bad_tuft: Dictionary = _assets()
	bad_tuft.far_meshes.tuft = _mesh(0.8)
	_check(not bool(view.configure(_result([_row(0, "tuft", [0.0, 0.0, 0.0])], bad_tuft)).ok), "tuft must retain exact full mesh resource")
	_check(not bool(view.configure(_result([_row(1, "shrub", [0.0, 0.0, 0.0]), _row(0, "shrub", [1.0, 0.0, 0.0])], assets)).ok), "unsorted stable rows rejected")
	var too_many: Array = []
	for index in range(1025):
		too_many.append(_row(index, "shrub", [0.0, 0.0, 0.0]))
	_check(not bool(view.configure(_result(too_many, assets)).ok), "hard plant budget enforced")
	too_many.resize(1024)
	_check(not bool(view.configure(_result(too_many, _assets(79))).ok), "hard full triangle budget enforced")
	var too_many_batches: Array = []
	for index in range(65):
		too_many_batches.append(_row(index, "shrub", [float(index) * 16.0, 0.0, 0.0]))
	_check(not bool(view.configure(_result(too_many_batches, assets)).ok), "hard batch budget enforced")
	_check(not bool(view.report().configured) and int(view.report().plants) == 0, "failed admission leaves renderer empty")
	view.free()
	camera.free()
	print(JSON.stringify({"fixture": "generated_v3_vegetation_renderer_contract", "ok": _failures.is_empty(),
		"checks": _checks, "failures": _failures, "actual_source_admission_proven": false}))
	quit(0 if _failures.is_empty() else 1)

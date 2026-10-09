extends SceneTree
## Real Compatibility fixture: exact crown classification, visible bark and bounds.
const View = preload("res://view/generated_v3_vegetation/vegetation_view.gd")
const Picker = preload("res://view/generated_v3_vegetation/picking.gd")
const Cutaway = preload("res://view/generated_v3_vegetation/body_cutaway.gd")
const Trees = preload("res://view/ecology_preview/vegetation_meshes.gd")
const FarTrees = preload("res://view/integrated_ecology_world/performance_variant/whole_canopies.gd")
var checks: int = 0
var failures: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func row(id: String, kind: String, x: float) -> Dictionary:
	return {"id": id, "hex": [0, 0], "asset_id": kind, "biome": "fixture", "position": [x, 0.0, 0.0],
		"radius": 1.0, "height": 1.0, "yaw": 0.0, "tint": 1.0}

func rays(view: Node3D, x: float = 0.0, y: float = 0.5) -> Array:
	return view.pick(Vector3(x, y, 3.0), Vector3.FORWARD, 10.0)

func run() -> void:
	check(DisplayServer.get_name() != "headless", "real MultiMesh transform backend required")
	if not failures.is_empty():
		quit(2)
		return
	var full: Dictionary = {}
	var far: Dictionary = {}
	var original_bytes: Dictionary = {}
	var original_arrays: Dictionary = {}
	var far_factory: Node3D = FarTrees.new()
	for kind in ["temperate", "tropical", "sapling", "shrub", "tuft", "reed"]:
		full[kind] = Trees.make(kind)
		far[kind] = far_factory._low_crown(kind) if kind in ["temperate", "tropical", "sapling", "shrub"] else full[kind]
		original_bytes[kind] = full[kind].surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()
		original_arrays[kind] = [full[kind].surface_get_arrays(0), far[kind].surface_get_arrays(0)]
	far_factory.free()
	var rows: Array = [row("a", "temperate", 0.0), row("b", "temperate", 20.0), row("c", "shrub", 5.0),
		row("d", "tuft", 10.0), row("e", "reed", 15.0), row("f", "tropical", -10.0)]
	var result: Dictionary = {"ok": true, "manifest": {"schema_version": "generated_v3_vegetation/v1",
		"profile_id": "sparse_biomes/v1", "plants": rows}, "assets": {"full_meshes": full, "far_meshes": far}}
	var view: Node3D = View.new()
	root.add_child(view)
	check(bool(view.configure(result).ok), "configure original source rows")
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	root.add_child(camera)
	view.update_lod(camera)
	var before: Array = rays(view)
	check(before.size() == 1 and before[0].id == "a", "original full crown ray hit")
	var crown_distance: float = float(before[0].distance) if not before.is_empty() else 0.0
	var body: AABB = AABB(Vector3(-0.2, 0.45, -0.2), Vector3(0.4, 0.5, 0.4))
	var installed: Dictionary = view.set_body_cutaway_bounds([body], true)
	check(bool(installed.ok), "actual body box masks local crown")
	if not bool(installed.ok):
		var setup_failure: Dictionary = {"ok": false, "checks": checks, "failures": failures,
			"failed_set_body_result": installed, "renderer_report": view.report()}
		print("CUTAWAY_SETUP_FAILURE ", JSON.stringify(setup_failure))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/generated_v3_vegetation"))
		var setup_file: FileAccess = FileAccess.open("res://artifacts/generated_v3_vegetation/cutaway_focused_report.json", FileAccess.WRITE)
		setup_file.store_string(JSON.stringify(setup_failure, "\t"))
		setup_file.close()
		view.free()
		camera.free()
		quit(1)
		return
	check(view.is_canopy_cut_away("a") and not view.is_canopy_cut_away("b"), "only intersecting crown is suppressed")
	var after: Array = rays(view)
	check(after.size() == 1 and after[0].id == "a" and float(after[0].distance) > crown_distance + 0.1, "visible bark behind former nearer crown remains selectable")
	check(rays(view, 0.0, 0.8).is_empty(), "hidden crown cannot select above bark")
	view.select("a")
	var shell: MeshInstance3D = view.get("_highlight") as MeshInstance3D
	check(shell != null and int(Picker.read_mesh(shell.mesh).triangles) == 14, "selection shell contains bark only")
	var slots: Dictionary = view.get("_slots")
	var node: MultiMeshInstance3D = slots.a.node.get_ref() as MultiMeshInstance3D
	check(node.multimesh.mesh == full.temperate, "original ArrayMesh resource is retained without geometry repack")
	var mask_data: Color = node.multimesh.get_instance_custom_data(0)
	check(mask_data.g == 42.0 and mask_data.b == 1.0, "exact full bark vertex prefix and woody membership")
	var arrays: Array = node.multimesh.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].to_byte_array() == original_bytes.temperate, "all original raw vertices remain unchanged")
	# A hidden crown must not occlude an unrelated visible target behind it.
	var plane_arrays: Array = []
	plane_arrays.resize(Mesh.ARRAY_MAX)
	plane_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, -2), Vector3(1, 0, -2), Vector3(0, 2, -2)])
	var plane: ArrayMesh = ArrayMesh.new()
	plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	var background: MultiMeshInstance3D = MultiMeshInstance3D.new()
	background.multimesh = MultiMesh.new()
	background.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	background.multimesh.mesh = plane
	background.multimesh.instance_count = 1
	background.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	root.add_child(background)
	var picker: RefCounted = Picker.new()
	check(bool(picker.capture([{"node": node, "rows": [{"id": "a", "hex": [0, 0]}]},
		{"node": background, "rows": [{"id": "unrelated", "hex": [0, 0]}]}]).ok), "capture hidden crown and unrelated target")
	var hits: Array = picker.query(Vector3(0, 0.8, 3), Vector3.FORWARD, 10.0)
	check(hits.size() == 1 and hits[0].id == "unrelated", "hidden crown does not occlude unrelated target")
	# Same explicit threshold in opaque shader and current raw CPU picking.
	mask_data.r = 0.49
	node.multimesh.set_instance_custom_data(0, mask_data)
	check(rays(view, 0.0, 0.8).is_empty(), "mask below0.5 suppresses crown picking")
	mask_data.r = 0.5
	node.multimesh.set_instance_custom_data(0, mask_data)
	check(rays(view, 0.0, 0.8).size() == 1, "mask at0.5 preserves crown picking")
	view.set_body_cutaway_bounds([], false)
	view.set_body_cutaway_bounds([body], true)
	var revision: int = int(view.report().cutaway.mask_revision)
	view.set_body_cutaway_bounds([body], true)
	check(int(view.report().cutaway.mask_revision) == revision and view.report().cutaway.cached_idle, "idle avoids candidate rescans and mask writes")
	# Moving pawn and visible dropped/carried pack are the same actual-box API.
	var pack: AABB = AABB(Vector3(19.8, 0.45, -0.2), Vector3(0.4, 0.5, 0.4))
	view.set_body_cutaway_bounds([body, pack], true)
	check(view.is_canopy_cut_away("a") and view.is_canopy_cut_away("b"), "pawn and pack boxes can suppress independently")
	view.set_body_cutaway_bounds([pack], true)
	check(not view.is_canopy_cut_away("a") and view.is_canopy_cut_away("b"), "moving pawn restores its old crown while stationary pack retains mask")
	view.set_body_cutaway_bounds([body], true)
	check(view.is_canopy_cut_away("a") and not view.is_canopy_cut_away("b"), "pack removal/drop-away restores its old crown")
	camera.size = 22.0
	view.update_lod(camera)
	var report: Dictionary = view.report()
	check(int(report.cutaway.forced_full_cutaway_groups) == 1 and int(report.active_batches) <= 64, "far LOD keeps bark in one forced-full existing batch")
	check(int(Picker.read_mesh(node.multimesh.mesh).triangles) == 77 and rays(view).size() == 1, "far cutaway retains actual full bark geometry")
	var distant: MultiMeshInstance3D = slots.b.node.get_ref() as MultiMeshInstance3D
	check(int(Picker.read_mesh(distant.multimesh.mesh).triangles) == 7, "distant unaffected group retains original far crown")
	view.set_body_cutaway_bounds([], false)
	check(not view.is_canopy_cut_away("a") and int(Picker.read_mesh(node.multimesh.mesh).triangles) == 7, "toggle off restores far crown and its raw picking")
	camera.size = 12.0
	view.update_lod(camera)
	for pair in [["c", 5.0], ["d", 10.0], ["e", 15.0]]:
		var initial: Array = rays(view, float(pair[1]), 0.45)
		var low_body: AABB = AABB(Vector3(float(pair[1]) - 0.5, 0.1, -0.5), Vector3(1, 1, 1))
		view.set_body_cutaway_bounds([low_body], true)
		var current: Array = rays(view, float(pair[1]), 0.45)
		check(not view.is_canopy_cut_away(str(pair[0])) and not current.is_empty() and not initial.is_empty() and absf(float(current[0].distance) - float(initial[0].distance)) < 0.00001, "low solid control never suppressed:" + str(pair[0]))
	view.set_body_cutaway_bounds([body], true)
	var prior_revision: int = int(view.report().cutaway.mask_revision)
	check(not bool(view.set_body_cutaway_bounds([AABB(Vector3(NAN, 0, 0), Vector3.ONE)], true).ok), "invalid body bounds explicitly fail")
	check(view.is_canopy_cut_away("a") and int(view.report().cutaway.mask_revision) == prior_revision, "invalid input cannot silently restore stale crowns")
	check(rays(view).is_empty() and not bool(view.report().picker.last_query.complete) and int(view.report().active_batches) == 0, "latched invalid input hides presentation and makes queries incomplete")
	check(not bool(view.set_body_cutaway_bounds([body], true).ok), "retry cannot recover partially applied mask ownership")
	check(not str(view.report().cutaway.error).is_empty(), "invalid-input error remains visible in diagnostics")
	check(bool(view.configure(result).ok), "reconfigure clears latched input failure")
	view.set_body_cutaway_bounds([body], true)
	check(not bool(view.set_body_cutaway_bounds([AABB(Vector3(-100, 0, -100), Vector3(200, 2, 200))], true).ok), "large body query cannot scan whole map")
	check(view.is_canopy_cut_away("a"), "over-budget input does not silently restore foliage")
	check(bool(view.configure(result).ok), "restart/reconfigure resets visual-only policy")
	check(not view.is_canopy_cut_away("a") and int(view.report().cutaway.mask_revision) == 0, "restart clears stale masks")
	check(bool(view.set_body_cutaway_bounds([body], true).ok) and view.is_canopy_cut_away("a"), "fresh policy works after restart")
	# Renderer/global movement transforms current body bounds back to source space.
	view.position = Vector3(3, 0, 0)
	check(bool(view.set_body_cutaway_bounds([AABB(body.position + Vector3(3, 0, 0), body.size)], true).ok) and view.is_canopy_cut_away("a"), "global renderer transform preserves correct source-frame cutaway")
	check(rays(view, 3.0, 0.8).is_empty(), "globally moved hidden crown remains unpickable")
	view.position = Vector3.ZERO
	view.configure(result)
	view.set_body_cutaway_bounds([body], true)
	var fresh_slots: Dictionary = view.get("_slots")
	var fresh_node: MultiMeshInstance3D = fresh_slots.a.node.get_ref() as MultiMeshInstance3D
	var moved: Transform3D = fresh_node.multimesh.get_instance_transform(0)
	moved.origin.x += 0.02
	fresh_node.multimesh.set_instance_transform(0, moved)
	check(not bool(view.set_body_cutaway_bounds([body], true).ok), "nearby immutable instance-transform mutation latches failure even for idle body")
	check(rays(view).is_empty() and not bool(view.report().picker.last_query.complete) and int(view.report().active_batches) == 0, "transform integrity failure hides stale presentation and blocks queries")
	check(bool(view.configure(result).ok) and bool(view.set_body_cutaway_bounds([body], true).ok), "reconfigure repairs transform ownership and masks")
	for kind in original_bytes:
		check(full[kind].surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array() == original_bytes[kind], "unchanged source asset:" + str(kind))
		for lod in range(2):
			var source_mesh: ArrayMesh = full[kind] if lod == 0 else far[kind]
			var current_arrays: Array = source_mesh.surface_get_arrays(0)
			for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
				check(current_arrays[attribute] == original_arrays[kind][lod][attribute], "strict original full/far array equality:" + str(kind) + ":" + str(lod) + ":" + str(attribute))
	var hashes: Dictionary = {}
	for path in ["res://view/generated_v3_vegetation/vegetation_view.gd", "res://view/generated_v3_vegetation/picking.gd",
		"res://view/generated_v3_vegetation/body_cutaway.gd", "res://view/generated_v3_vegetation/body_cutaway.gdshader",
		"res://core/generated_v3_vegetation/planner.gd", "res://core/generated_v3_vegetation/assets.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	var output: Dictionary = {"fixture": "visual_canopy_cutaway/v1", "checks": checks, "failures": failures,
		"ok": failures.is_empty(), "renderer_report": view.report(), "source_hashes": hashes,
		"physical_clearance_claim": false, "opaque_mask_threshold": Cutaway.PICK_THRESHOLD}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/generated_v3_vegetation"))
	var file: FileAccess = FileAccess.open("res://artifacts/generated_v3_vegetation/cutaway_focused_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print(JSON.stringify(output))
	picker.clear()
	background.free()
	view.free()
	camera.free()
	quit(0 if failures.is_empty() else 1)

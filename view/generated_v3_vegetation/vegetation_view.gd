extends Node3D
## Presentation only of an already-admitted sparse_biomes/v1 result.
## One MultiMesh per (asset, fixed chunk); one optional selection shell total.
## No terrain, navigation, source catalog, actor or gameplay state is written.

const Picker = preload("res://view/generated_v3_vegetation/picking.gd")
const BodyCutaway = preload("res://view/generated_v3_vegetation/body_cutaway.gd")
const CUTAWAY_SHADER = preload("res://view/generated_v3_vegetation/body_cutaway.gdshader")
const SURFACE_SHADER = preload("res://view/ecology_preview/vegetation_surface.gdshader")
const SCHEMA := "generated_v3_vegetation/v1"
const PROFILE := "sparse_biomes/v1"
const ASSET_IDS := ["temperate", "tropical", "sapling", "shrub", "tuft", "reed"]
const CHUNK_SIZE := 16.0
const CHUNK_OFFSET := 24.0
const LOD_FAR_ENTER := 22.0
const LOD_FULL_RETURN := 20.0
const MAX_PLANTS := 1024
const MAX_FULL_TRIANGLES := 80000
const MAX_BATCHES := 64
const EXPECTED_R12_MAX_BATCHES := 54

var manifest: Dictionary = {}
var diagnostics: Dictionary = {}
var _configured: bool = false
var _content: Node3D
var _material: ShaderMaterial
var _highlight_material: StandardMaterial3D
var _highlight: MeshInstance3D
var _picker: RefCounted = Picker.new()
var _groups: Array[Dictionary] = []
var _slots: Dictionary = {}
var _mesh_stats: Dictionary = {}
var _selected_id: String = ""
var _far: bool = false
var _lod_switches: int = 0
var _mesh_swaps: int = 0
var _full_triangles: int = 0
var _far_triangles: int = 0
var _instance_buffer_bytes: int = 0
var _known_mesh_array_bytes: int = 0
var _cutaway: RefCounted = BodyCutaway.new()
var _cutaway_ready: bool = false
var _cutaway_error: String = ""
var _cutaway_update_us: int = 0
var _cutaway_ownership_checks: int = 0
var _cutaway_source_meshes: Dictionary = {}
var _cutaway_visual_assets: Dictionary = {}

func configure(result: Dictionary) -> Dictionary:
	_clear()
	var started: int = Time.get_ticks_usec()
	diagnostics = {"configured": false, "errors": [], "terrain_mutated": false,
		"gameplay_mutated": false, "physics_nodes": 0, "per_plant_nodes": 0,
		"raw_triangle_picking": true, "highlight_in_pick_set": false,
		"full_far_footprint_validated_by": "admitted_asset_catalog",
		"shadow_casting": "off", "source_authority": "planner_admission_required"}
	if not bool(result.get("ok", false)):
		return _fail("vegetation_not_admitted")
	var supplied: Variant = result.get("manifest")
	var assets: Variant = result.get("assets")
	if not supplied is Dictionary or not assets is Dictionary:
		return _fail("missing_manifest_or_assets")
	if supplied.get("schema_version") != SCHEMA or supplied.get("profile_id") != PROFILE:
		return _fail("unsupported_manifest_profile")
	var plants: Variant = supplied.get("plants")
	var full_meshes: Variant = assets.get("full_meshes")
	var far_meshes: Variant = assets.get("far_meshes")
	if not plants is Array or not full_meshes is Dictionary or not far_meshes is Dictionary:
		return _fail("missing_plants_or_shared_meshes")
	if plants.size() > MAX_PLANTS:
		return _fail("plant_budget_exceeded")
	manifest = supplied.duplicate(true)
	_cutaway_source_meshes = {"full_meshes": full_meshes.duplicate(), "far_meshes": far_meshes.duplicate()}
	var buckets: Dictionary = {}
	var prior_id: String = ""
	for value in plants:
		if not value is Dictionary:
			return _fail("invalid_plant_row")
		var row: Dictionary = value
		var id: String = str(row.get("id", ""))
		var asset_id: String = str(row.get("asset_id", ""))
		if id.is_empty() or (not prior_id.is_empty() and id <= prior_id) or asset_id not in ASSET_IDS:
			return _fail("unsorted_duplicate_or_invalid_plant_identity")
		prior_id = id
		if not Picker._valid_hex(row.get("hex")) or not _numeric_array(row.get("position"), 3):
			return _fail("invalid_plant_coordinates")
		for key in ["radius", "height", "yaw", "tint"]:
			if not _finite_number(row.get(key)):
				return _fail("invalid_plant_transform:" + key)
		if float(row.radius) <= 0.0 or float(row.height) <= 0.0 or float(row.tint) < 0.0:
			return _fail("invalid_plant_scale_or_tint")
		var full: ArrayMesh = full_meshes.get(asset_id) as ArrayMesh
		var far: ArrayMesh = far_meshes.get(asset_id) as ArrayMesh
		if full == null or far == null or full.get_surface_count() != 1 or far.get_surface_count() != 1:
			return _fail("expected_single_surface_shared_array_mesh:" + asset_id)
		if asset_id in ["tuft", "reed"] and far != full:
			return _fail("ground_cover_requires_same_full_mesh_at_both_lods:" + asset_id)
		for mesh in [full, far]:
			var mesh_id: int = mesh.get_instance_id()
			if not _mesh_stats.has(mesh_id):
				var measured: Dictionary = Picker.read_mesh(mesh)
				if not bool(measured.ok):
					return _fail("invalid_raw_asset_mesh:" + asset_id)
				_mesh_stats[mesh_id] = {"triangles": int(measured.triangles),
					"known_array_bytes": int(measured.known_array_bytes)}
				_known_mesh_array_bytes += int(measured.known_array_bytes)
		_full_triangles += int(_mesh_stats[full.get_instance_id()].triangles)
		_far_triangles += int(_mesh_stats[far.get_instance_id()].triangles)
		if _full_triangles > MAX_FULL_TRIANGLES or _far_triangles > MAX_FULL_TRIANGLES:
			return _fail("triangle_budget_exceeded")
		var p: Array = row.position
		var position_: Vector3 = Vector3(float(p[0]), float(p[1]), float(p[2]))
		var transform_: Transform3D = Transform3D(Basis(Vector3.UP, float(row.yaw)).scaled(
			Vector3(float(row.radius), float(row.height), float(row.radius))), position_)
		if not transform_.is_finite() or transform_.basis.determinant() == 0.0:
			return _fail("unrepresentable_plant_transform")
		var chunk: Vector2i = Vector2i(floori((position_.x + CHUNK_OFFSET) / CHUNK_SIZE),
			floori((position_.z + CHUNK_OFFSET) / CHUNK_SIZE))
		var key: String = "%s_%d_%d" % [asset_id, chunk.x, chunk.y]
		if not buckets.has(key):
			buckets[key] = {"asset_id": asset_id, "chunk": chunk, "full": full, "far": far, "rows": []}
		buckets[key].rows.append({"id": id, "hex": row.hex.duplicate(),
			"transform": transform_, "tint": float(row.tint)})
	if buckets.size() > MAX_BATCHES:
		return _fail("batch_budget_exceeded")
	_material = ShaderMaterial.new()
	_material.shader = SURFACE_SHADER
	_content = Node3D.new()
	_content.name = "AdmittedGeneratedVegetation"
	add_child(_content)
	var keys: Array = buckets.keys()
	keys.sort()
	var captures: Array = []
	for key in keys:
		var bucket: Dictionary = buckets[key]
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = bucket.full
		multimesh.instance_count = bucket.rows.size()
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = str(key)
		node.multimesh = multimesh
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_content.add_child(node)
		var identities: Array = []
		for slot in range(bucket.rows.size()):
			var row: Dictionary = bucket.rows[slot]
			multimesh.set_instance_transform(slot, row.transform)
			var tint: float = float(row.tint)
			multimesh.set_instance_color(slot, Color(tint, tint, tint, 1.0))
			multimesh.set_instance_custom_data(slot, Color(1.0, 0.0, 0.0, 0.0))
			if multimesh.get_instance_transform(slot) != row.transform:
				return _fail("native_instance_transform_readback_mismatch")
			identities.append({"id": row.id, "hex": row.hex.duplicate()})
			_slots[str(row.id)] = {"node": weakref(node), "multimesh": weakref(multimesh), "slot": slot, "count": bucket.rows.size(), "group_index": _groups.size(), "asset_id": bucket.asset_id, "transform": row.transform}
		_instance_buffer_bytes += multimesh.buffer.size() * 4
		_groups.append({"node": node, "full": bucket.full, "far": bucket.far,
			"asset_id": bucket.asset_id, "chunk": bucket.chunk, "count": identities.size(), "suppressed_count": 0})
		captures.append({"node": node, "rows": identities})
	var captured: Dictionary = _picker.capture(captures)
	if not bool(captured.ok):
		return _fail("picker_capture:" + str(captured.get("error", "unknown")))
	_configured = true
	visible = true
	set_process(true)
	diagnostics.configured = true
	diagnostics["configure_us"] = Time.get_ticks_usec() - started
	return {"ok": true, "report": report()}

func _clear() -> void:
	set_process(false)
	_configured = false
	visible = false
	_picker.clear()
	if is_instance_valid(_content):
		remove_child(_content)
		_content.free()
	_content = null
	_highlight = null
	_material = null
	_highlight_material = null
	_groups.clear()
	_slots.clear()
	_mesh_stats.clear()
	manifest.clear()
	_selected_id = ""
	_far = false
	_lod_switches = 0
	_mesh_swaps = 0
	_full_triangles = 0
	_far_triangles = 0
	_instance_buffer_bytes = 0
	_known_mesh_array_bytes = 0
	_cutaway.clear()
	_cutaway_ready = false
	_cutaway_error = ""
	_cutaway_update_us = 0
	_cutaway_ownership_checks = 0
	_cutaway_source_meshes.clear()
	_cutaway_visual_assets.clear()

func _fail(error: String) -> Dictionary:
	_clear()
	diagnostics["configured"] = false
	diagnostics["errors"] = [error]
	return {"ok": false, "error": error, "report": diagnostics.duplicate(true)}

func update_lod(camera: Camera3D) -> void:
	if not _configured:
		return
	var desired_far: bool = _far
	if is_instance_valid(camera) and is_finite(camera.size):
		if camera.size >= LOD_FAR_ENTER:
			desired_far = true
		elif camera.size <= LOD_FULL_RETURN:
			desired_far = false
	if desired_far != _far:
		_far = desired_far
		_lod_switches += 1
		for group in _groups:
			_refresh_cutaway_group(group)
	_sync_selection()

func _ensure_body_cutaway() -> Dictionary:
	if _cutaway_ready:
		return {"ok": true}
	var derived: Dictionary = BodyCutaway.derive_visual_assets(_cutaway_source_meshes.full_meshes, _cutaway_source_meshes.far_meshes)
	if not bool(derived.ok):
		return derived
	var indexed: Dictionary = _cutaway.configure(manifest.plants, _cutaway_source_meshes.full_meshes, _cutaway_source_meshes.far_meshes)
	if not bool(indexed.ok):
		return indexed
	_cutaway_visual_assets = derived
	_cutaway_ready = true
	_material.shader = CUTAWAY_SHADER
	_mesh_stats.clear()
	_known_mesh_array_bytes = 0
	for group in _groups:
		group.full = derived.full_meshes[group.asset_id]
		group.far = derived.far_meshes[group.asset_id]
		for mesh in [group.full, group.far]:
			_remember_mesh_stats(mesh)
		_refresh_cutaway_group(group)
	for mesh in derived.bark_meshes.values():
		_remember_mesh_stats(mesh)
	return {"ok": true}

func _remember_mesh_stats(mesh: ArrayMesh) -> void:
	var mesh_id: int = mesh.get_instance_id()
	if _mesh_stats.has(mesh_id):
		return
	var measured: Dictionary = Picker.read_mesh(mesh)
	_mesh_stats[mesh_id] = {"triangles": int(measured.triangles), "known_array_bytes": int(measured.known_array_bytes)}
	_known_mesh_array_bytes += int(measured.known_array_bytes)

func _refresh_cutaway_group(group: Dictionary) -> void:
	var node: MultiMeshInstance3D = group.node
	if not is_instance_valid(node) or node.multimesh == null:
		return
	var mesh: ArrayMesh = group.far if _far and int(group.suppressed_count) == 0 else group.full
	if node.multimesh.mesh != mesh:
		node.multimesh.mesh = mesh
		_mesh_swaps += 1
	if not _cutaway_ready:
		return
	var woody: bool = BodyCutaway.BARK_TRIANGLES.has(str(group.asset_id))
	var bark_vertices: int = int(BodyCutaway.BARK_TRIANGLES.get(str(group.asset_id), 0)) * 3 if mesh == group.full and woody else 0
	if not node.has_meta(BodyCutaway.META_POLICY) or int(node.get_meta("v3_cutaway_bark_vertices", -1)) != bark_vertices:
		for slot in range(node.multimesh.instance_count):
			var data: Color = node.multimesh.get_instance_custom_data(slot)
			node.multimesh.set_instance_custom_data(slot, Color(data.r, float(bark_vertices), 1.0 if woody else 0.0, 0.0))
		node.set_meta(BodyCutaway.META_POLICY, BodyCutaway.POLICY)
		node.set_meta("v3_cutaway_bark_vertices", bark_vertices)

func set_body_cutaway_bounds(world_aabbs: Array, enabled: bool = true) -> Dictionary:
	# Public presentation-only input: actual player/visible pack bounds, never
	# NPCs or guessed pawn dimensions. Only bounded candidate/active sets update.
	var started: int = Time.get_ticks_usec()
	if not _cutaway_error.is_empty():
		return {"ok": false, "error": _cutaway_error, "reconfigure_required": true}
	if not _configured or not global_transform.is_finite() or global_transform.basis.determinant() == 0.0:
		return _cutaway_failure("cutaway_renderer_unavailable")
	if world_aabbs.size() > BodyCutaway.MAX_BODY_BOUNDS:
		return _cutaway_failure("too_many_body_bounds")
	var local_boxes: Array = []
	var inverse: Transform3D = global_transform.affine_inverse()
	for value in world_aabbs:
		if not value is AABB or not BodyCutaway._valid_box(value):
			return _cutaway_failure("invalid_body_bounds")
		local_boxes.append(inverse * value)
	if enabled and not _cutaway_ready:
		var prepared: Dictionary = _ensure_body_cutaway()
		if not bool(prepared.ok):
			var failed: Dictionary = _cutaway_failure(str(prepared.get("error", "cutaway_prepare_failed")))
			failed["detail"] = prepared
			return failed
	var changed: Dictionary = _cutaway.update_bounds(local_boxes, enabled)
	if not bool(changed.ok):
		return _cutaway_failure(str(changed.error))
	_cutaway_ownership_checks = changed.checked_ids.size()
	var integrity_error: String = _cutaway_integrity(changed.checked_ids)
	if not integrity_error.is_empty():
		return _cutaway_failure(integrity_error)
	var affected_groups: Dictionary = {}
	for suppressed in [true, false]:
		var ids: Array = changed.hide_ids if suppressed else changed.show_ids
		for id in ids:
			if not _slots.has(id):
				return _cutaway_failure("cutaway_unknown_source_slot")
			var slot: Dictionary = _slots[id]
			var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
			var multimesh: MultiMesh = slot.multimesh.get_ref() as MultiMesh
			if not is_instance_valid(node) or node.multimesh != multimesh or multimesh == null or multimesh.instance_count != int(slot.count):
				return _cutaway_failure("cutaway_instance_ownership_changed")
			var mask: Color = multimesh.get_instance_custom_data(int(slot.slot))
			mask.r = 0.0 if suppressed else 1.0
			multimesh.set_instance_custom_data(int(slot.slot), mask)
			var group_index: int = int(slot.group_index)
			_groups[group_index].suppressed_count += 1 if suppressed else -1
			affected_groups[group_index] = true
	for index in affected_groups:
		_refresh_cutaway_group(_groups[index])
	_cutaway_error = ""
	_sync_selection()
	_cutaway_update_us = Time.get_ticks_usec() - started
	return changed

func _cutaway_integrity(ids: Array) -> String:
	# Source-bound instance transforms are private and immutable after configure.
	# This detects ownership/transform changes only in local candidates and the
	# active suppressed set; arbitrary writes to far private slots are outside
	# the ownership contract, not hidden behind a global per-frame buffer scan.
	if not is_instance_valid(_content) or _content.transform != Transform3D.IDENTITY:
		return "cutaway_content_transform_changed"
	for id in ids:
		if not _slots.has(id):
			return "cutaway_unknown_source_slot"
		var slot: Dictionary = _slots[id]
		var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
		var multimesh: MultiMesh = slot.multimesh.get_ref() as MultiMesh
		if not is_instance_valid(node) or multimesh == null or node.multimesh != multimesh or multimesh.instance_count != int(slot.count):
			return "cutaway_instance_ownership_changed"
		if node.get_parent() != _content or node.transform != Transform3D.IDENTITY or multimesh.get_instance_transform(int(slot.slot)) != slot.transform:
			return "cutaway_immutable_transform_changed"
	return ""

func _cutaway_failure(error: String) -> Dictionary:
	_cutaway_error = error
	if is_instance_valid(_content):
		_content.visible = false
	_picker.last_query = {"complete": false, "error": error, "hits": 0}
	return {"ok": false, "error": error, "presentation_hidden": true, "reconfigure_required": true}

func is_canopy_cut_away(id: String) -> bool:
	if not _cutaway_ready or not _slots.has(id):
		return false
	var slot: Dictionary = _slots[id]
	if not BodyCutaway.BARK_TRIANGLES.has(str(slot.asset_id)):
		return false
	var multimesh: MultiMesh = slot.multimesh.get_ref() as MultiMesh
	var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
	return is_instance_valid(node) and multimesh != null and node.multimesh == multimesh and multimesh.instance_count == int(slot.count) and multimesh.get_instance_custom_data(int(slot.slot)).r < BodyCutaway.PICK_THRESHOLD

func _process(_delta: float) -> void:
	if is_inside_tree():
		update_lod(get_viewport().get_camera_3d())

func _exit_tree() -> void:
	_picker.clear()
	_configured = false

func pick(origin: Vector3, direction: Vector3, limit: float) -> Array[Dictionary]:
	if not _cutaway_error.is_empty():
		_picker.last_query = {"complete": false, "error": _cutaway_error, "hits": 0}
		return []
	if not _configured or not is_inside_tree() or not is_visible_in_tree():
		return []
	return _picker.query(origin, direction, limit)

func select(id: String) -> bool:
	_selected_id = id if _slots.has(id) else ""
	_sync_selection()
	return not _selected_id.is_empty()

func _sync_selection() -> void:
	if is_instance_valid(_highlight):
		_highlight.visible = false
	if _selected_id.is_empty() or not _slots.has(_selected_id) or not _configured:
		return
	var selected: Dictionary = _slots[_selected_id]
	var node: MultiMeshInstance3D = selected.node.get_ref() as MultiMeshInstance3D
	var multimesh: MultiMesh = selected.multimesh.get_ref() as MultiMesh
	var slot: int = int(selected.slot)
	if not Picker._attached_alive(node) or not node.is_visible_in_tree() or multimesh == null or node.multimesh != multimesh:
		return
	if multimesh.instance_count != int(selected.count) or slot >= multimesh.instance_count or (multimesh.visible_instance_count >= 0 and slot >= multimesh.visible_instance_count):
		return
	var mesh: ArrayMesh = multimesh.mesh as ArrayMesh
	var current: Transform3D = node.global_transform * multimesh.get_instance_transform(slot)
	if _cutaway_ready and multimesh.get_instance_custom_data(slot).r < BodyCutaway.PICK_THRESHOLD:
		mesh = _cutaway_visual_assets.bark_meshes.get(str(selected.asset_id), mesh)
	if mesh == null or not current.is_finite() or current.basis.determinant() == 0.0:
		return
	# The shell is optional presentation and cannot push the hard primitive
	# budget over 80k. Selection/picking identity remains valid without a shell.
	var stats: Dictionary = _mesh_stats.get(mesh.get_instance_id(), {})
	if stats.is_empty():
		stats = Picker.read_mesh(mesh)
	var shell_triangles: int = int(stats.triangles)
	if _full_triangles + shell_triangles > MAX_FULL_TRIANGLES:
		return
	if not is_instance_valid(_highlight):
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_material.albedo_color = Color(1.0, 0.85, 0.2, 0.35)
		_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_highlight_material.grow = true
		_highlight_material.grow_amount = 0.008
		_highlight = MeshInstance3D.new()
		_highlight.name = "SelectedVegetationGlow"
		_highlight.material_override = _highlight_material
		_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_content.add_child(_highlight)
	_highlight.mesh = mesh
	_highlight.global_transform = current
	_highlight.visible = true

func report() -> Dictionary:
	var active_batches: int = 0
	var visible_plants: int = 0
	var active_triangles: int = 0
	var current_stats: Dictionary = {}
	var forced_groups: int = 0
	var forced_triangles: int = 0
	for group in _groups:
		var node: MultiMeshInstance3D = group.node
		if not Picker._attached_alive(node) or not node.is_visible_in_tree() or node.multimesh == null:
			continue
		var multimesh: MultiMesh = node.multimesh
		var count: int = multimesh.instance_count
		if multimesh.visible_instance_count >= 0:
			count = mini(count, multimesh.visible_instance_count)
		var mesh: ArrayMesh = multimesh.mesh as ArrayMesh
		if count <= 0 or mesh == null:
			continue
		if not current_stats.has(mesh.get_instance_id()):
			current_stats[mesh.get_instance_id()] = Picker.read_mesh(mesh)
		active_batches += mesh.get_surface_count()
		visible_plants += count
		active_triangles += count * int(current_stats[mesh.get_instance_id()].triangles)
		if _far and int(group.suppressed_count) > 0:
			forced_groups += 1
			forced_triangles += count * int(current_stats[mesh.get_instance_id()].triangles)
	var shell_draws: int = 0
	var shell_triangles: int = 0
	if is_instance_valid(_highlight) and _highlight.is_visible_in_tree() and _highlight.mesh != null:
		shell_draws = _highlight.mesh.get_surface_count()
		shell_triangles = int(Picker.read_mesh(_highlight.mesh as ArrayMesh).triangles)
	var cutaway_report: Dictionary = _cutaway.report()
	cutaway_report["prepared"] = _cutaway_ready
	cutaway_report["index_elapsed_us"] = cutaway_report.get("elapsed_us", 0)
	cutaway_report["elapsed_us"] = _cutaway_update_us
	cutaway_report["ownership_checks"] = _cutaway_ownership_checks
	cutaway_report["instance_transform_contract"] = "immutable source-bound private slots; local candidate/active integrity detection only"
	if not _cutaway_error.is_empty():
		cutaway_report["error"] = _cutaway_error
	cutaway_report["invalid_input_policy"] = "latched error hides vegetation and blocks picking until configure"
	cutaway_report["reconfigure_required"] = not _cutaway_error.is_empty()
	cutaway_report["source_pins"] = _cutaway_visual_assets.get("source_pins", {})
	cutaway_report["original_position_index_normal_color_arrays_preserved"] = _cutaway_visual_assets.get("original_position_index_normal_color_arrays_preserved", false)
	cutaway_report["forced_full_cutaway_groups"] = forced_groups
	cutaway_report["forced_full_cutaway_triangles"] = forced_triangles
	cutaway_report["forced_full_cutaway_draw_count"] = forced_groups
	cutaway_report["triangle_sets"] = _cutaway_visual_assets.get("triangle_sets", {})
	var result: Dictionary = diagnostics.duplicate(true)
	result.merge({"configured": _configured, "plants": _slots.size(), "visible_plants": visible_plants,
		"batch_nodes": _groups.size(), "active_batches": active_batches, "active_draw_calls": active_batches + shell_draws,
		"full_plant_triangles": _full_triangles, "far_plant_triangles": _far_triangles,
		"full_triangles": _full_triangles, "far_triangles": _far_triangles,
		"active_plant_triangles": active_triangles, "active_triangles_with_selection": active_triangles + shell_triangles,
		"selection_draw_calls": shell_draws, "selection_triangles": shell_triangles, "selected_id": _selected_id,
		"lod": "far_same_footprint" if _far else "full", "lod_switches": _lod_switches, "mesh_swaps": _mesh_swaps,
		"lod_far_enter_size": LOD_FAR_ENTER, "lod_full_return_size": LOD_FULL_RETURN,
		"chunk_size": CHUNK_SIZE, "chunk_offset_xz": [CHUNK_OFFSET, CHUNK_OFFSET],
		"expected_r12_max_batches": EXPECTED_R12_MAX_BATCHES, "max_active_batches": MAX_BATCHES,
		"shared_mesh_resources": _mesh_stats.size(), "shared_material_resources": 1 if _material != null else 0,
		"instance_buffer_bytes": _instance_buffer_bytes, "known_mesh_array_bytes": _known_mesh_array_bytes,
		"memory_note": "buffer accounting only; excludes engine objects, allocator and driver overhead",
		"draw_count_note": "submitted visible geometry; actual GPU/frustum counts require native measurement",
		"picker": _picker.report(), "cutaway": cutaway_report}, true)
	return result

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _numeric_array(value: Variant, length_: int) -> bool:
	if not value is Array or value.size() != length_:
		return false
	for number in value:
		if not _finite_number(number):
			return false
	return true

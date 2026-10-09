extends Node3D
## Presentation of an already-admitted V3 placement. No terrain, authority,
## navigation, save, actor or economy writes are performed by this renderer.
## All procedural coordinates remain in the admitted source mesh's frame.
const Assets = preload("res://core/generated_v3_placement/asset_catalog.gd")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "generated_v3_placement/v1"
const PROFILE := "dry_village/v1"
const KIT_ROOT := "res://assets/city_districts/"
const KIT_MATERIAL := KIT_ROOT + "city_vertex_color.tres"
const ASSET_NAMES := ["village_cottage_a", "village_barn", "village_cottage_b"]
const EPSILON := 0.00001
const BOUNDS_EPSILON := 0.00002
const LOD_ENTER_PIXELS := 32.0
const LOD_EXIT_PIXELS := 44.0
const CENTERLINE_SCALE: int = 1099511627776
const ROAD_WIDTH := 0.40
const ROAD_LIFT := 0.012
const FOUNDATION_COLOR := Color("9b9985")
const ROAD_COLOR := Color("ceac64")
const ROAD_EDGE_COLOR := Color("b19463")

var manifest: Dictionary = {}
var diagnostics: Dictionary = {}
var _configured: bool = false
var _content: Node3D
var _surface: RefCounted
var _kit_material: Material
var _ground_material: StandardMaterial3D
var _asset_rows: Dictionary = {}
var _selection: Array = []
var _lod_entries: Array = []
var _lod_switches: int = 0
var _camera_signature: Array = []

func configure(placement_result: Dictionary) -> Dictionary:
	_clear()
	diagnostics = {"configured": false, "errors": [], "buildings": [], "roads": [], "asset_bounds_checks": [],
		"triangles": 0, "full_kit_triangles": 0, "foundation_triangles": 0,
		"road_triangles": 0, "mesh_nodes": 0, "physics_nodes": 0,
		"terrain_mutated": false, "gameplay_mutated": false, "fallback_art": false,
		"support_source": "actual_native_ground_triangles", "road_visual_lift": ROAD_LIFT}
	if not bool(placement_result.get("ok", false)):
		return _fail("placement_not_admitted")
	var supplied: Variant = placement_result.get("manifest")
	if not supplied is Dictionary or not Canonical.safe(supplied):
		return _fail("missing_manifest")
	manifest = supplied.duplicate(true)
	if manifest.get("schema_version") != SCHEMA or manifest.get("profile_id") != PROFILE:
		return _fail("unsupported_manifest_profile")
	for key in ["placement_hash", "source_hash", "geometry_hash", "asset_catalog_hash"]:
		if str(manifest.get(key, "")).is_empty(): return _fail("missing_identity:" + key)
	var unsigned: Dictionary = manifest.duplicate(true)
	unsigned.erase("placement_hash")
	if Canonical.digest(unsigned) != str(manifest.placement_hash):
		return _fail("manifest_hash_mismatch")
	if placement_result.has("placement_hash") and placement_result.placement_hash != manifest.placement_hash:
		return _fail("placement_identity_mismatch")
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		return _fail("renderer_requires_identity_source_frame")
	_surface = placement_result.get("surface") as RefCounted
	if _surface == null or not _surface.has_method("clip_polygon") or not _surface.has_method("segment_points"):
		return _fail("missing_exact_source_surface")
	if str(_surface.get("geometry_hash")) != str(manifest.geometry_hash):
		return _fail("surface_geometry_identity_mismatch")
	var asset_error: String = _load_assets()
	if not asset_error.is_empty(): return _fail(asset_error)
	_ground_material = StandardMaterial3D.new()
	_ground_material.vertex_color_use_as_albedo = true
	_ground_material.vertex_color_is_srgb = true
	_ground_material.roughness = 0.96
	_ground_material.cull_mode = BaseMaterial3D.CULL_BACK
	_content = Node3D.new()
	_content.name = "AdmittedGeneratedVillage"
	var roots: Dictionary = {}
	var centers: Dictionary = {}
	var used_ids: Dictionary = {}
	var settlements: Variant = manifest.get("settlements", [])
	var buildings: Variant = manifest.get("buildings", [])
	var roads: Variant = manifest.get("roads", [])
	if not settlements is Array or not buildings is Array or not roads is Array:
		return _fail("invalid_entity_lists")
	if settlements.size() != 1 or buildings.size() != 3 or roads.is_empty():
		return _fail("unsupported_profile_entity_counts")
	for row in settlements:
		if not row is Dictionary or not _valid_id(row, used_ids): return _fail("invalid_settlement_identity")
		var root: Node3D = Node3D.new()
		root.name = "Village"
		_set_entity_metadata(root, row, "settlement")
		_content.add_child(root)
		roots[str(row.id)] = root
		centers[str(row.id)] = row.get("center_hex", []).duplicate()
	for row in buildings:
		if not row is Dictionary or not _valid_id(row, used_ids): return _fail("invalid_building_identity")
		var settlement_id: String = str(row.get("settlement_id", ""))
		if not roots.has(settlement_id): return _fail("unknown_building_settlement")
		var result: Dictionary = _build_building(row, roots[settlement_id])
		if not result.ok: return _fail(str(row.id) + ":" + str(result.error))
		_selection.append({"id": str(row.id), "kind": "building", "node": result.node,
			"hex": centers[settlement_id].duplicate()})
	for row in roads:
		if not row is Dictionary or not _valid_id(row, used_ids): return _fail("invalid_road_identity")
		var settlement_id: String = str(row.get("settlement_id", ""))
		if not roots.has(settlement_id): return _fail("unknown_road_settlement")
		var result: Dictionary = _build_road(row, roots[settlement_id])
		if not result.ok: return _fail(str(row.id) + ":" + str(result.error))
		var route: Array = row.get("route_hexes", [])
		var focus_hex: Array = route[0] if not route.is_empty() else centers[settlement_id]
		_selection.append({"id": str(row.id), "kind": "road", "node": result.node,
			"hex": focus_hex.duplicate()})
	# Specific entities precede their aggregate so equal-depth picking can retain
	# the building/road identity instead of swallowing it into the village.
	for row in settlements:
		_selection.append({"id": str(row.id), "kind": "settlement", "node": roots[str(row.id)],
			"hex": centers[str(row.id)].duplicate()})
	add_child(_content)
	_configured = true
	visible = true
	diagnostics.configured = true
	for key in ["placement_hash", "source_hash", "geometry_hash", "renderer_profile", "asset_catalog_hash", "context_hash"]:
		diagnostics[key] = manifest.get(key, "")
	diagnostics["selection_count"] = _selection.size()
	set_process(true)
	return {"ok": true, "placement_hash": manifest.placement_hash, "report": report()}

func _clear() -> void:
	set_process(false)
	_configured = false
	visible = false
	if is_instance_valid(_content):
		if _content.get_parent() != null: _content.get_parent().remove_child(_content)
		_content.free()
	_content = null
	_surface = null
	manifest = {}
	_selection.clear()
	_lod_entries.clear()
	_camera_signature.clear()
	_lod_switches = 0
	_asset_rows.clear()

func _fail(reason: String) -> Dictionary:
	if is_instance_valid(_content):
		if _content.get_parent() != null: _content.get_parent().remove_child(_content)
		_content.free()
	_content = null
	_selection.clear()
	_lod_entries.clear()
	_configured = false
	visible = false
	diagnostics.errors.append(reason)
	diagnostics.configured = false
	return {"ok": false, "error": reason, "report": report()}

func _valid_id(row: Dictionary, used: Dictionary) -> bool:
	var id: String = str(row.get("id", ""))
	if id.is_empty() or used.has(id): return false
	used[id] = true
	return true

func _load_assets() -> String:
	var approved: Dictionary = Assets.read()
	if not approved.get("ok", false): return "approved_asset_catalog_rejected"
	if manifest.asset_catalog_hash != approved.hash: return "asset_catalog_identity_mismatch"
	var kit: Dictionary = approved.data
	if kit.get("asset_root") != KIT_ROOT or kit.get("material_path") != KIT_MATERIAL:
		return "unexpected_approved_kit_paths"
	if not ResourceLoader.exists(KIT_MATERIAL): return "missing_original_kit_material"
	_kit_material = load(KIT_MATERIAL) as Material
	if _kit_material == null: return "invalid_original_kit_material"
	for asset_id in ASSET_NAMES:
		if not kit.assets.has(asset_id): return "missing_approved_asset:" + str(asset_id)
		var row: Dictionary = kit.assets[asset_id]
		if row.get("glb") != "models/" + asset_id + ".glb": return "unexpected_kit_asset_path"
		if row.get("lod1_glb") != "lod1/" + asset_id + "_lod1.glb": return "unexpected_kit_lod_path"
		_asset_rows[asset_id] = row.duplicate(true)
	return ""

func _build_building(row: Dictionary, parent: Node3D) -> Dictionary:
	var asset_id: String = str(row.get("asset_id", ""))
	if not _asset_rows.has(asset_id): return {"ok": false, "error": "unapproved_asset"}
	var source: Dictionary = _asset_rows[asset_id]
	for key in ["asset_sha256", "lod1_sha256"]:
		var source_key: String = "sha256" if key == "asset_sha256" else str(key)
		if row.get(key) != source.get(source_key): return {"ok": false, "error": "manifest_asset_hash_mismatch"}
	var path: String = KIT_ROOT + str(source.glb)
	var low_path: String = KIT_ROOT + str(source.lod1_glb)
	if not _valid_asset_file(path, str(source.sha256)) or not _valid_asset_file(low_path, str(source.lod1_sha256)):
		return {"ok": false, "error": "asset_bytes_or_import_missing"}
	if not _numeric_array(row.get("position"), 3) or not _numeric_array(row.get("foundation_plane"), 3):
		return {"ok": false, "error": "invalid_building_transform"}
	if not _finite_number(row.get("scale")) or not _finite_number(row.get("yaw_radians")):
		return {"ok": false, "error": "invalid_building_transform"}
	var fit: float = float(row.scale)
	var plane: Array = row.foundation_plane
	if fit <= 0.0 or absf(float(plane[0])) > EPSILON or absf(float(plane[1])) > EPSILON:
		return {"ok": false, "error": "unsupported_scale_or_support_plane"}
	var position_: Vector3 = _vector3(row.position)
	var support_y: float = float(plane[2])
	if absf(position_.y - support_y) > EPSILON: return {"ok": false, "error": "pivot_support_mismatch"}
	var footprint: Variant = row.get("footprint")
	if not _valid_polygon(footprint): return {"ok": false, "error": "invalid_building_footprint"}
	var packed: PackedScene = load(path) as PackedScene
	var low_packed: PackedScene = load(low_path) as PackedScene
	if packed == null or low_packed == null: return {"ok": false, "error": "asset_not_packed_scene"}
	var model: Node3D = packed.instantiate() as Node3D
	var low_model: Node3D = low_packed.instantiate() as Node3D
	if model == null or low_model == null:
		if model != null: model.free()
		if low_model != null: low_model.free()
		return {"ok": false, "error": "asset_not_node3d"}
	var full: Dictionary = _hierarchy_geometry(model)
	var low: Dictionary = _hierarchy_geometry(low_model)
	var error: String = ""
	var bounds_check: Dictionary = {}
	var full_points_check: Dictionary = {}
	var low_points_check: Dictionary = {}
	if not full.ok or not low.ok: error = "invalid_asset_geometry"
	elif not model.transform.is_equal_approx(Transform3D.IDENTITY) or not low_model.transform.is_equal_approx(Transform3D.IDENTITY):
		error = "unexpected_authored_root_transform"
	elif not _numeric_array(source.get("aabb_min_xyz"), 3) or not _numeric_array(source.get("aabb_max_xyz"), 3):
		error = "invalid_declared_asset_bounds"
	else:
		var declared: AABB = AABB(_vector3(source.aabb_min_xyz), _vector3(source.aabb_max_xyz) - _vector3(source.aabb_min_xyz))
		bounds_check = _bounds_comparison(full.bounds, declared)
		bounds_check["id"] = str(row.id)
		bounds_check["asset_id"] = asset_id
		bounds_check["lod1_native_bounds"] = _box_json(low.bounds)
		diagnostics.asset_bounds_checks.append(bounds_check)
		if not bool(bounds_check.matches): error = "actual_asset_bounds_mismatch"
		elif not _contains_box(full.bounds, low.bounds): error = "lod_exceeds_full_asset_bounds"
	var placement: Transform3D = Transform3D(Basis(Vector3.UP, float(row.yaw_radians)).scaled(Vector3.ONE * fit), position_)
	if full.ok and low.ok:
		# Check every native ARRAY_VERTEX for both full and LOD geometry. These
		# hard admission checks do not inherit any import-space AABB tolerance.
		full_points_check = _points_admitted(full.points, placement, footprint, support_y)
		low_points_check = _points_admitted(low.points, placement, footprint, support_y)
		bounds_check["full_points"] = full_points_check
		bounds_check["lod1_points"] = low_points_check
		if error.is_empty() and not full_points_check.ok:
			error = "full_" + str(full_points_check.error)
		if error.is_empty() and not low_points_check.ok:
			error = "lod1_" + str(low_points_check.error)
	if error.is_empty():
		# Retain the stronger full projected-AABB envelope check as well.
		for corner in _box_corners(full.bounds):
			var world: Vector3 = placement * corner
			if not _inside_convex(Vector2(world.x, world.z), footprint): error = "asset_outside_manifest_footprint"
	if not error.is_empty():
		model.free()
		low_model.free()
		return {"ok": false, "error": error}
	var root: Node3D = Node3D.new()
	root.name = "Building_" + asset_id
	_set_entity_metadata(root, row, "building")
	parent.add_child(root)
	model.name = "OriginalKitModel"
	model.transform = placement
	root.add_child(model)
	for node in full.nodes:
		node.material_override = _kit_material
		node.set_meta("entity_id", str(row.id))
		node.set_meta("full_asset_sha256", str(row.asset_sha256))
		node.set_meta("city_lod", "full")
	var lod_supported: bool = false
	if full.nodes.size() == 1 and low.nodes.size() == 1:
		var high_node: MeshInstance3D = full.nodes[0]
		var low_node: MeshInstance3D = low.nodes[0]
		if _local_transform(model, high_node).is_equal_approx(_local_transform(low_model, low_node)):
			lod_supported = true
			_lod_entries.append({"id": str(row.id), "node": high_node, "near": high_node.mesh,
				"far": low_node.mesh, "bounds": high_node.mesh.get_aabb(), "low": false,
				"pixels": 0.0, "full_sha256": str(row.asset_sha256), "lod1_sha256": str(row.lod1_sha256),
				"full_triangles": full.triangles, "lod1_triangles": low.triangles})
	low_model.free()
	var foundation: Dictionary = _build_foundation(row, root)
	if not foundation.ok: return foundation
	var measured: Dictionary = {"id": str(row.id), "asset_id": asset_id, "asset_path": path,
		"asset_sha256": row.asset_sha256, "lod1_path": low_path, "lod1_sha256": row.lod1_sha256,
		"position": row.position.duplicate(), "yaw_radians": row.yaw_radians, "scale": fit,
		"footprint": footprint.duplicate(true), "foundation_plane": plane.duplicate(),
		"actual_local_bounds": _box_json(full.bounds), "actual_world_bounds": _box_json(placement * full.bounds),
		"lod1_local_bounds": _box_json(low.bounds), "full_triangles": full.triangles,
		"lod1_triangles": low.triangles, "lod_contained": true, "lod_mesh_swap_supported": lod_supported,
		"bounds_fit_verified": true, "bounds_comparison": bounds_check,
		"full_points_verified": full_points_check, "lod1_points_verified": low_points_check,
		"foundation": foundation.report}
	diagnostics.buildings.append(measured)
	diagnostics.full_kit_triangles += int(full.triangles)
	diagnostics.triangles += int(full.triangles)
	diagnostics.mesh_nodes += full.nodes.size()
	return {"ok": true, "node": root}

func _valid_asset_file(path: String, sha: String) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == sha and ResourceLoader.exists(path)

func _hierarchy_geometry(root: Node3D) -> Dictionary:
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: nodes.push_front(root)
	var found: bool = false
	var bounds: AABB = AABB()
	var triangles: int = 0
	var points: PackedVector3Array = PackedVector3Array()
	for node in nodes:
		if node.mesh == null: return {"ok": false}
		var transform_: Transform3D = _local_transform(root, node)
		for surface_index in range(node.mesh.get_surface_count()):
			if node.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				return {"ok": false}
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				return {"ok": false}
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var index_count: int = vertices.size() if indices.is_empty() else indices.size()
			if vertices.is_empty() or index_count % 3 != 0: return {"ok": false}
			for index in indices:
				if index < 0 or index >= vertices.size(): return {"ok": false}
			# Mesh.get_faces() goes through TriangleMesh, which snaps vertices to
			# 0.0001 for its BVH. Raw native arrays avoid that picking-proxy drift.
			for vertex in vertices:
				var point: Vector3 = transform_ * vertex
				if not point.is_finite(): return {"ok": false}
				bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
				points.append(point)
				found = true
			triangles += int(index_count / 3)
	return {"ok": found, "nodes": nodes, "bounds": bounds, "triangles": triangles, "points": points}

func _points_admitted(points: PackedVector3Array, placement: Transform3D, footprint: Array, floor_y: float) -> Dictionary:
	var minimum_floor_gap: float = INF
	for index in range(points.size()):
		var point: Vector3 = placement * points[index]
		minimum_floor_gap = minf(minimum_floor_gap, point.y - floor_y)
		if not _inside_convex(Vector2(point.x, point.z), footprint):
			return {"ok": false, "error": "native_vertex_outside_manifest_footprint",
				"vertex_index": index, "local": _array3(points[index]), "world": _array3(point)}
		if point.y < floor_y - EPSILON:
			return {"ok": false, "error": "native_vertex_below_support_floor",
				"vertex_index": index, "local": _array3(points[index]), "world": _array3(point), "floor_y": floor_y}
	return {"ok": true, "native_vertex_count": points.size(), "minimum_floor_gap": minimum_floor_gap,
		"physical_epsilon": EPSILON, "vertex_source": "surface_get_arrays"}

func _bounds_comparison(actual: AABB, declared: AABB) -> Dictionary:
	var minimum_delta: Vector3 = actual.position - declared.position
	var maximum_delta: Vector3 = actual.end - declared.end
	return {"actual_native_bounds": _box_json(actual), "declared_glb_bounds": _box_json(declared),
		"minimum_delta": _array3(minimum_delta), "maximum_delta": _array3(maximum_delta),
		"minimum_delta_length": minimum_delta.length(), "maximum_delta_length": maximum_delta.length(),
		"import_space_epsilon": BOUNDS_EPSILON, "matches": _same_box(actual, declared),
		"vertex_source": "surface_get_arrays", "get_faces_proxy_used": false}

func _local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != root:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

func _build_foundation(row: Dictionary, parent: Node3D) -> Dictionary:
	var polygon: Array = row.footprint
	var plane_y: float = float(row.foundation_plane[2])
	var coverage: Dictionary = _clipped_coverage(polygon)
	if not coverage.ok: return {"ok": false, "error": "foundation_" + str(coverage.error)}
	var mesh_data: Dictionary = _geometry()
	var top: Array[Vector3] = []
	for point in polygon: top.append(Vector3(float(point[0]), plane_y, float(point[1])))
	for i in range(1, top.size() - 1): _up_triangle(mesh_data, top[0], top[i], top[i + 1], FOUNDATION_COLOR.lightened(0.05))
	var maximum_depth: float = 0.0
	for piece in coverage.pieces:
		for point in piece.polygon:
			if point.y > plane_y + EPSILON: return {"ok": false, "error": "foundation_top_below_actual_terrain"}
			maximum_depth = maxf(maximum_depth, plane_y - point.y)
	var sides: Array = []
	var winding: float = _signed_area(polygon)
	for edge_index in range(polygon.size()):
		var a: Array = polygon[edge_index]
		var b: Array = polygon[(edge_index + 1) % polygon.size()]
		var samples: Array = _surface.call("segment_points", a, b)
		if samples.size() < 2: return {"ok": false, "error": "foundation_edge_uncovered"}
		var start: Vector2 = Vector2(float(a[0]), float(a[1]))
		var finish: Vector2 = Vector2(float(b[0]), float(b[1]))
		var direction: Vector2 = finish - start
		var previous_t: float = -EPSILON
		var points: Array = []
		for point in samples:
			if not point is Vector3 or not point.is_finite(): return {"ok": false, "error": "invalid_foundation_sample"}
			var xz: Vector2 = Vector2(point.x, point.z)
			var t: float = (xz - start).dot(direction) / direction.length_squared()
			if t < previous_t - EPSILON or t < -EPSILON or t > 1.0 + EPSILON:
				return {"ok": false, "error": "unordered_foundation_sample"}
			if xz.distance_to(start + t * direction) > EPSILON or point.y > plane_y + EPSILON:
				return {"ok": false, "error": "foundation_sample_outside_support"}
			previous_t = t
			points.append(_array3(point))
		if Vector2(samples[0].x, samples[0].z).distance_to(start) > EPSILON or Vector2(samples[-1].x, samples[-1].z).distance_to(finish) > EPSILON:
			return {"ok": false, "error": "foundation_edge_endpoint_missing"}
		for i in range(samples.size() - 1):
			var low_a: Vector3 = samples[i]
			var low_b: Vector3 = samples[i + 1]
			var high_a: Vector3 = Vector3(low_a.x, plane_y, low_a.z)
			var high_b: Vector3 = Vector3(low_b.x, plane_y, low_b.z)
			var tone: Color = FOUNDATION_COLOR * (0.92 + 0.025 * float(edge_index % 3))
			if winding > 0.0: _quad(mesh_data, low_a, high_a, high_b, low_b, tone)
			else: _quad(mesh_data, low_b, high_b, high_a, low_a, tone)
		sides.append({"edge_index": edge_index, "terrain_points": points})
	var node: MeshInstance3D = _commit_mesh("ExactTerrainFoundation", mesh_data, parent, true)
	var triangles: int = int(mesh_data.vertices.size() / 3)
	diagnostics.foundation_triangles += triangles
	return {"ok": true, "report": {"triangles": triangles, "top_y": plane_y,
		"maximum_depth": maximum_depth, "covered_area": coverage.area, "footprint_area": coverage.expected_area,
		"native_triangle_ids": coverage.triangle_ids, "edge_samples": sides,
		"actual_bounds": _box_json(node.mesh.get_aabb()), "source_conforming": true}}

func _build_road(row: Dictionary, parent: Node3D) -> Dictionary:
	if not _valid_polygon(row.get("footprint")): return {"ok": false, "error": "invalid_road_footprint"}
	if not _finite_number(row.get("width")) or absf(float(row.width) - ROAD_WIDTH) > EPSILON:
		return {"ok": false, "error": "undeclared_road_width"}
	if not _finite_number(row.get("visual_lift")) or absf(float(row.visual_lift) - ROAD_LIFT) > EPSILON:
		return {"ok": false, "error": "undeclared_road_lift"}
	var decoded: Dictionary = _decode_centerline(row)
	if not decoded.ok: return decoded
	var centerline: Array = decoded.points
	var coverage: Dictionary = _clipped_coverage(row.footprint)
	if not coverage.ok: return {"ok": false, "error": "road_" + str(coverage.error)}
	var mesh_data: Dictionary = _geometry()
	var exported_pieces: Array = []
	for piece in coverage.pieces:
		var polygon: Array = piece.polygon
		var lifted: Array[Vector3] = []
		var source_vertices: Array = []
		for point in polygon:
			lifted.append(point + Vector3.UP * ROAD_LIFT)
			source_vertices.append(_array3(point))
		for i in range(1, lifted.size() - 1):
			var center: Vector3 = (lifted[0] + lifted[i] + lifted[i + 1]) / 3.0
			_up_triangle(mesh_data, lifted[0], lifted[i], lifted[i + 1], _road_color(center, centerline, int(piece.triangle_id)))
		exported_pieces.append({"triangle_id": int(piece.triangle_id), "source_vertices": source_vertices})
	var node: MeshInstance3D = _commit_mesh("SourceConformingRoad", mesh_data, parent, false)
	_set_entity_metadata(node, row, "road")
	var triangles: int = int(mesh_data.vertices.size() / 3)
	diagnostics.road_triangles += triangles
	diagnostics.roads.append({"id": str(row.id), "width": ROAD_WIDTH, "visual_lift": ROAD_LIFT,
		"centerline": centerline.duplicate(true), "centerline_q40": row.centerline_q40.duplicate(true),
		"centerline_scale": CENTERLINE_SCALE, "footprint": row.footprint.duplicate(true),
		"triangles": triangles, "covered_area": coverage.area, "footprint_area": coverage.expected_area,
		"actual_bounds": _box_json(node.mesh.get_aabb()), "native_triangle_ids": coverage.triangle_ids,
		"native_pieces": exported_pieces, "source_conforming": true, "terrain_cost_modifier": 1})
	return {"ok": true, "node": node}

func _decode_centerline(row: Dictionary) -> Dictionary:
	# JSON readers may return integral numbers as floats. Require exact, finite,
	# safe integers rather than a particular Variant storage tag. Never insert
	# decoded floats into the admitted or caller-owned manifest.
	var wire_scale: Variant = row.get("centerline_scale")
	if not Canonical.integer(wire_scale) or int(wire_scale) != CENTERLINE_SCALE:
		return {"ok": false, "error": "invalid_road_centerline_scale"}
	var encoded: Variant = row.get("centerline_q40")
	if not encoded is Array or encoded.size() < 2:
		return {"ok": false, "error": "invalid_road_centerline_q40"}
	var points: Array = []
	for encoded_point in encoded:
		if not encoded_point is Array or encoded_point.size() != 3:
			return {"ok": false, "error": "invalid_road_centerline_q40"}
		var point: Array = []
		for coordinate in encoded_point:
			if not Canonical.integer(coordinate):
				return {"ok": false, "error": "noninteger_road_centerline_q40"}
			point.append(float(coordinate) / float(CENTERLINE_SCALE))
		points.append(point)
	return {"ok": true, "points": points}

func _clipped_coverage(polygon: Array) -> Dictionary:
	var pieces: Array = _surface.call("clip_polygon", polygon)
	var area: float = 0.0
	var ids: Array = []
	for piece in pieces:
		if not piece is Dictionary or not piece.get("polygon") is Array or not piece.has("triangle_id"):
			return {"ok": false, "error": "invalid_native_triangle_piece"}
		var points: Array = piece.polygon
		if points.size() < 3: return {"ok": false, "error": "degenerate_native_triangle_piece"}
		var xz: Array = []
		for point in points:
			if not point is Vector3 or not point.is_finite(): return {"ok": false, "error": "invalid_native_triangle_vertex"}
			if not _inside_convex(Vector2(point.x, point.z), polygon): return {"ok": false, "error": "native_clip_outside_footprint"}
			xz.append([point.x, point.z])
		area += absf(_signed_area(xz))
		ids.append(int(piece.triangle_id))
	var expected: float = absf(_signed_area(polygon))
	if pieces.is_empty() or absf(area - expected) > maxf(0.000001, expected * 0.0001):
		return {"ok": false, "error": "native_surface_coverage_mismatch"}
	return {"ok": true, "pieces": pieces, "area": area, "expected_area": expected, "triangle_ids": ids}

func _road_color(point: Vector3, centerline: Array, triangle_id: int) -> Color:
	var distance_: float = INF
	var point_xz: Vector2 = Vector2(point.x, point.z)
	for i in range(centerline.size() - 1):
		var a: Vector2 = Vector2(float(centerline[i][0]), float(centerline[i][2]))
		var b: Vector2 = Vector2(float(centerline[i + 1][0]), float(centerline[i + 1][2]))
		var direction: Vector2 = b - a
		var t: float = clampf((point_xz - a).dot(direction) / maxf(direction.length_squared(), EPSILON), 0.0, 1.0)
		distance_ = minf(distance_, point_xz.distance_to(a + t * direction))
	var edge: float = smoothstep(ROAD_WIDTH * 0.32, ROAD_WIDTH * 0.50, distance_)
	return ROAD_COLOR.lerp(ROAD_EDGE_COLOR, edge) * (0.97 + 0.015 * float(posmod(triangle_id, 4)))

func selection_nodes() -> Array:
	if not _configured or not visible: return []
	var result: Array = []
	for row in _selection:
		result.append({"id": row.id, "kind": row.kind, "node": row.node, "hex": row.hex.duplicate()})
	return result

func report() -> Dictionary:
	var result: Dictionary = diagnostics.duplicate(true)
	result["configured"] = _configured
	result["visible"] = visible
	result["lod"] = lod_report()
	return result

func lod_report() -> Dictionary:
	var result: Dictionary = {"tracked_models": _lod_entries.size(), "full_models": 0, "simplified_models": 0,
		"displayed_kit_triangles": 0, "full_kit_triangles": 0, "switches": _lod_switches,
		"enter_pixels": LOD_ENTER_PIXELS, "exit_pixels": LOD_EXIT_PIXELS,
		"mesh_only_swap": true, "authoritative_bounds": "full_asset", "models": []}
	for entry in _lod_entries:
		if not is_instance_valid(entry.node): continue
		var is_low: bool = bool(entry.low)
		result["simplified_models" if is_low else "full_models"] += 1
		result.displayed_kit_triangles += int(entry.lod1_triangles if is_low else entry.full_triangles)
		result.full_kit_triangles += int(entry.full_triangles)
		result.models.append({"id": entry.id, "lod": "lod1" if is_low else "full", "pixels": entry.pixels,
			"displayed_sha256": entry.lod1_sha256 if is_low else entry.full_sha256,
			"full_sha256": entry.full_sha256, "lod1_sha256": entry.lod1_sha256})
	return result

func update_lod(camera: Camera3D) -> void:
	if not _configured or not is_instance_valid(camera): return
	var signature: Array = [camera.global_transform, camera.projection, camera.size, camera.fov,
		camera.keep_aspect, camera.get_viewport().get_visible_rect().size]
	if signature == _camera_signature: return
	_camera_signature = signature
	for entry in _lod_entries:
		var pixels: float = _projected_pixels(entry, camera)
		entry.pixels = pixels if is_finite(pixels) else -1.0
		var low: bool = pixels < (LOD_EXIT_PIXELS if bool(entry.low) else LOD_ENTER_PIXELS)
		if low == bool(entry.low): continue
		entry.low = low
		var node: MeshInstance3D = entry.node
		node.mesh = entry.far if low else entry.near
		node.set_meta("city_lod", "simplified" if low else "full")
		var outline: MeshInstance3D = node.get_node_or_null("SelectedEdgeGlow") as MeshInstance3D
		if outline != null: outline.mesh = node.mesh
		_lod_switches += 1

func _process(_delta: float) -> void:
	if is_inside_tree() and visible: update_lod(get_viewport().get_camera_3d())

func _projected_pixels(entry: Dictionary, camera: Camera3D) -> float:
	var rectangle: Rect2 = Rect2()
	var node: MeshInstance3D = entry.node
	var box: AABB = entry.bounds
	for i in range(8):
		var world: Vector3 = node.global_transform * box.get_endpoint(i)
		if camera.is_position_behind(world): return INF
		var point: Vector2 = camera.unproject_position(world)
		rectangle = Rect2(point, Vector2.ZERO) if i == 0 else rectangle.expand(point)
	return maxf(rectangle.size.x, rectangle.size.y)

func _set_entity_metadata(node: Node3D, row: Dictionary, kind: String) -> void:
	node.set_meta("entity_id", str(row.id))
	node.set_meta("entity_kind", kind)
	node.set_meta("placement_hash", str(manifest.placement_hash))
	node.set_meta("source_hash", str(manifest.source_hash))

func _numeric_array(value: Variant, length_: int) -> bool:
	if not value is Array or value.size() != length_: return false
	for number in value:
		if not _finite_number(number): return false
	return true

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_polygon(value: Variant) -> bool:
	if not value is Array or value.size() < 3: return false
	for point in value:
		if not _numeric_array(point, 2): return false
	var winding: float = _signed_area(value)
	if absf(winding) < EPSILON * EPSILON: return false
	for i in range(value.size()):
		var a: Vector2 = Vector2(float(value[i][0]), float(value[i][1]))
		var b: Vector2 = Vector2(float(value[(i + 1) % value.size()][0]), float(value[(i + 1) % value.size()][1]))
		var c: Vector2 = Vector2(float(value[(i + 2) % value.size()][0]), float(value[(i + 2) % value.size()][1]))
		if a.distance_squared_to(b) < EPSILON * EPSILON: return false
		if (b - a).cross(c - b) * winding < -EPSILON * EPSILON: return false
	return true

func _inside_convex(point: Vector2, polygon: Array) -> bool:
	var winding: float = _signed_area(polygon)
	for i in range(polygon.size()):
		var a: Vector2 = Vector2(float(polygon[i][0]), float(polygon[i][1]))
		var b: Vector2 = Vector2(float(polygon[(i + 1) % polygon.size()][0]), float(polygon[(i + 1) % polygon.size()][1]))
		var cross_: float = (b - a).cross(point - a)
		if cross_ * signf(winding) < -EPSILON * (b - a).length(): return false
	return true

func _signed_area(polygon: Array) -> float:
	var area: float = 0.0
	for i in range(polygon.size()):
		var a: Array = polygon[i]
		var b: Array = polygon[(i + 1) % polygon.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return area * 0.5

func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _box_json(box: AABB) -> Dictionary:
	return {"min": _array3(box.position), "max": _array3(box.end), "size": _array3(box.size)}

func _box_corners(box: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(8): result.append(box.get_endpoint(i))
	return result

func _same_box(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) <= BOUNDS_EPSILON and a.end.distance_to(b.end) <= BOUNDS_EPSILON

func _contains_box(outer: AABB, inner: AABB) -> bool:
	var expanded: AABB = outer.grow(BOUNDS_EPSILON)
	for point in _box_corners(inner):
		if not expanded.has_point(point): return false
	return true

func _geometry() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}

func _triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var cross_: Vector3 = (b - a).cross(c - a)
	if cross_.length_squared() < 0.0000000000000001: return
	var normal: Vector3 = cross_.normalized()
	# Outward normals use mathematical CCW; Godot front faces are clockwise.
	for point in [a, c, b]:
		data.vertices.append(point)
		data.normals.append(normal)
		data.colors.append(color)

func _up_triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y < 0.0: _triangle(data, a, c, b, color)
	else: _triangle(data, a, b, c, color)

func _quad(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(data, a, b, c, color)
	_triangle(data, a, c, d, color)

func _commit_mesh(label: String, data: Dictionary, parent: Node3D, shadows: bool) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _ground_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	diagnostics.mesh_nodes += 1
	diagnostics.triangles += int(data.vertices.size() / 3)
	return node

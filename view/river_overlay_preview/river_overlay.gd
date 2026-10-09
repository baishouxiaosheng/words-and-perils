extends Node3D
## Read-only real-source local river. Meshes and physics use the same packed triangles.
## Integrator must retire contract.retire_original_ground_face_indices first.
signal surface_picked(context: Dictionary)
var manifest: Dictionary = {}
var contract: Dictionary = {}
var last_error := ""
var draw_triangles := 0
var terrain_triangles := 0
var water_triangles := 0
var mesh_views: Array[MeshInstance3D] = []
var source_manifest := ""

func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

func _binary(base: String, row: Dictionary, key: String) -> PackedByteArray:
	var filename: String = row[key]
	var packed := FileAccess.get_file_as_bytes(base.path_join(filename))
	if _sha(packed) != row["file_sha256"][filename]:
		last_error = "River cache SHA mismatch: " + filename
		return PackedByteArray()
	return packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)

func load_cache(path: String, options: Dictionary = {}) -> bool:
	if not mesh_views.is_empty():
		last_error = "River overlay already loaded"
		return false
	source_manifest = path
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		last_error = "Unreadable local river manifest"
		return false
	manifest = data
	if manifest.get("accepted_mode_allowed", true) or manifest.get("status", "") != "DIAGNOSTIC_PENDING_LOCAL_RENDER_CACHE":
		last_error = "Expected explicitly local preview river cache"
		return false
	var base := path.get_base_dir()
	var contract_bytes := FileAccess.get_file_as_bytes(base.path_join(manifest.get("overlay_contract_file", "overlay_contract.json")))
	if _sha(contract_bytes) != manifest.get("overlay_contract_sha256", ""):
		last_error = "River overlay integration contract SHA mismatch"
		return false
	var decoded = JSON.parse_string(contract_bytes.get_string_from_utf8())
	if not decoded is Dictionary:
		last_error = "Unreadable river integration contract"
		return false
	contract = decoded
	var affected := {}
	for fi in contract["retire_original_ground_face_indices"]: affected[int(fi)] = true
	var include_context: bool = options.get("include_context_ground", false)
	var include_old_water: bool = options.get("include_existing_water", false)
	for row in manifest["meshes"]:
		var vb := _binary(base, row, "vertex_file")
		var ib := _binary(base, row, "index_file")
		var pb := _binary(base, row, "triangle_provenance_file")
		if not last_error.is_empty(): return false
		var provenance = JSON.parse_string(pb.get_string_from_utf8())
		var floats := vb.to_float32_array()
		var count := int(row["vertices"])
		if floats.size() != count * 14 or ib.size() != int(row["indices"]) * 4 or not provenance is Array or provenance.size() * 3 != int(row["indices"]):
			last_error = "Invalid river packed vertex/index/provenance sizes"
			return false
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var selected_metadata: Array = []
		for ti in range(provenance.size()):
			var meta: Dictionary = provenance[ti]
			var is_old_water: bool = meta.get("kind", "") == "existing_body_water"
			if row["kind"] == "water":
				if is_old_water and not include_old_water: continue
			elif not include_context and not affected.has(int(meta["original_face"])): continue
			selected_metadata.append(meta)
			for k in range(3):
				var ix := int(ib.decode_u32((ti * 3 + k) * 4))
				if ix < 0 or ix >= count:
					last_error = "River packed index out of range"
					return false
				var j := ix * 14
				vertices.append(Vector3(floats[j], floats[j+1], floats[j+2]))
				normals.append(Vector3(floats[j+3], floats[j+4], floats[j+5]))
				colors.append(Color(floats[j+6],floats[j+7],floats[j+8],floats[j+9]))
				uvs.append(Vector2(floats[j+10],floats[j+11]))
				uv2s.append(Vector2(floats[j+12],floats[j+13]))
		if vertices.is_empty(): continue
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var supplied_materials: Dictionary = options.get("materials", {})
		var material: Material = supplied_materials.get(str(row["kind"]), _material(str(row["kind"])))
		mesh.surface_set_material(0, material)
		var view := MeshInstance3D.new()
		view.name = "RealRiver_" + str(row["kind"])
		view.mesh = mesh
		view.set_meta("river_surface_kind", str(row["kind"]))
		add_child(view)
		mesh_views.append(view)
		var body := StaticBody3D.new()
		body.name = "SameCache_" + str(row["kind"])
		body.collision_layer = int(options.get("water_collision_layer",2)) if row["kind"] == "water" else int(options.get("ground_collision_layer",1))
		body.collision_mask = 0
		body.set_meta("river_triangle_provenance", selected_metadata)
		body.set_meta("river_surface_kind", str(row["kind"]))
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(vertices)
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		draw_triangles += vertices.size() / 3
		if row["kind"] == "water": water_triangles += vertices.size() / 3
		else: terrain_triangles += vertices.size() / 3
	return true

func _material(kind: String) -> Material:
	var material := StandardMaterial3D.new()
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		"water":
			material.albedo_color = Color(0.12,0.38,0.43,0.74)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.36
			material.metallic_specular = 0.45
		"bank": material.albedo_color = Color(0.54,0.43,0.27)
		"bed": material.albedo_color = Color(0.30,0.25,0.15)
		_: material.albedo_color = Color(0.40,0.48,0.28)
	return material

func contains_footprint(world_point: Vector3) -> bool:
	if contract.is_empty(): return false
	var b: Array = contract["footprint_bounds_xz"]
	if world_point.x < b[0] or world_point.z < b[1] or world_point.x > b[2] or world_point.z > b[3]: return false
	var poly := PackedVector2Array()
	for p in contract["footprint_polygon_xz"]: poly.append(Vector2(p[0],p[1]))
	return Geometry2D.is_point_in_polygon(Vector2(world_point.x,world_point.z),poly)

func pick_surface(ray_from: Vector3, ray_to: Vector3, mask: int = 3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(ray_from,ray_to,mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var body: Object = hit["collider"]
	if not body.has_meta("river_triangle_provenance"): return {}
	var provenance: Array = body.get_meta("river_triangle_provenance")
	var face := int(hit.get("face_index",-1))
	var context: Dictionary = provenance[face].duplicate(true) if face >= 0 and face < provenance.size() else {}
	var pos: Vector3 = hit["position"]
	context["position"] = pos
	context["surface_kind"] = body.get_meta("river_surface_kind")
	context["inside_river_footprint"] = contains_footprint(pos)
	context["water_bodies"] = contract.get("water_bodies",{}).duplicate(true)
	context["scope"] = "LOCAL_REAL_RIVER_PREVIEW_NO_MOVEMENT_RULE"
	surface_picked.emit(context)
	return context

func get_integration_contract() -> Dictionary:
	return contract.duplicate(true)

func set_surface_material(kind: String, material: Material) -> void:
	# World integration supplies its own terrain/water palette and lighting.
	# This changes appearance only; source geometry and all physics stay unchanged.
	for view in mesh_views:
		if str(view.get_meta("river_surface_kind", "")) == kind:
			view.mesh.surface_set_material(0,material)

const WaterQueries = preload("river_water_queries.gd")
var _water_queries: RefCounted

func _prepare_water_queries() -> bool:
	if is_instance_valid(_water_queries): return _water_queries.ready
	_water_queries = WaterQueries.new()
	var query_path := source_manifest.get_base_dir().path_join("new_water_query.json")
	return _water_queries.load_file(query_path)

func segment_intersects_water(from_xz: Vector2, to_xz: Vector2) -> Dictionary:
	if not _prepare_water_queries(): return {"ok":false,"error":_water_queries.last_error,"intersects":false}
	return _water_queries.segment_intersects_water(from_xz,to_xz)

func water_endpoint_context(xz: Vector2) -> Dictionary:
	if not _prepare_water_queries(): return {"ok":false,"error":_water_queries.last_error,"is_new_river_water":false}
	return _water_queries.water_endpoint_context(xz)

func nearest_dry_candidate(origin_xz: Vector2, prevalidated_candidates: Array) -> Dictionary:
	if not _prepare_water_queries(): return {"ok":false,"error":_water_queries.last_error,"found":false}
	return _water_queries.nearest_dry_candidate(origin_xz,prevalidated_candidates)

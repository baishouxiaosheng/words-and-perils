extends Node3D
## Isolated view of stored PL triangles. No gameplay, save, provider or AI state.
const Loader := preload("res://view/recovered_terrain_loader.gd")
const WaterLoader := preload("res://view/recovered_terrain_water_loader.gd")
const SURFACE := preload("res://view/recovered_terrain/recovered_surface.gdshader")
var world: Dictionary = {}
var water: Dictionary = {}
var content_root: Node3D
var height_scale := 1.0
var terrain_root: Node3D
var grid_root: Node3D
var water_root: Node3D
var camera: Camera3D
var target := Vector3.ZERO
var distance := 24.0
var yaw := 0.0
var pitch := 0.75
var overview := true
var grid_enabled := true
var build_ms := 0.0
var chunk_count := 0
var grid_segment_count := 0
var selected_hex := ""
var material: ShaderMaterial
var grid_material: ShaderMaterial

func _ready() -> void:
	content_root = Node3D.new()
	content_root.name = "ReadOnlyDisplayScaleOnly"
	add_child(content_root)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = 2048.0
	add_child(camera)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("263235")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("99b3c7")
	environment.ambient_light_energy = 0.14
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	add_child(env_node)
	_add_light(Color("fff0cf"), 1.20, Vector3(-35, -34, 0))
	_add_light(Color("b5d1f2"), 0.18, Vector3(-22, 125, 0))
	_add_light(Color("ffdbb6"), 0.22, Vector3(-20, -140, 0))
	material = ShaderMaterial.new()
	material.shader = SURFACE
	for kind in ["grass", "rock"]:
		var asset := "leafy_grass" if kind == "grass" else "rock_face"
		material.set_shader_parameter(kind + "_albedo", load("res://assets/materials/polyhaven/" + asset + "_diff_1k.jpg"))
		material.set_shader_parameter(kind + "_roughness", load("res://assets/materials/polyhaven/" + asset + "_rough_1k.jpg"))
	material.set_shader_parameter("texture_patch", 2.4)

func _add_light(color: Color, energy: float, rotation: Vector3) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.rotation_degrees = rotation
	light.shadow_enabled = false
	add_child(light)

func clear_world() -> void:
	for node in [terrain_root, grid_root, water_root]:
		if is_instance_valid(node):
			content_root.remove_child(node)
			node.queue_free()
	terrain_root = null
	grid_root = null
	water_root = null
	world = {}
	water = {}
	chunk_count = 0
	grid_segment_count = 0
	selected_hex = ""

func show_world(data: Dictionary, water_data: Dictionary = {}) -> void:
	clear_world()
	var started := Time.get_ticks_usec()
	world = data
	water = water_data
	terrain_root = Node3D.new()
	terrain_root.name = "StoredPLTerrain"
	content_root.add_child(terrain_root)
	grid_root = Node3D.new()
	grid_root.name = "CanonicalHexGrid"
	content_root.add_child(grid_root)
	water_root = Node3D.new()
	water_root.name = "ExplicitPLWaterOnly"
	content_root.add_child(water_root)
	var chunks := {}
	for fi in range(world.face_ids.size()):
		var cell: Dictionary = world.cells[world.face_owners[fi]]
		var key := Vector2i(floori(float(cell.q) / 6.0), floori(float(cell.r) / 6.0))
		if not chunks.has(key): chunks[key] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}
		var a: Vector3 = world.positions[world.indices[fi * 3]]
		var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
		var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
		var n := (c - a).cross(b - a).normalized()
		var tint := Color("8a9a68").srgb_to_linear() if cell.domain == "land" else Color("927446").srgb_to_linear()
		# Facet normals are global per face, identical across chunk partitions.
		for p in [a, c, b]:
			chunks[key].vertices.append(p)
			chunks[key].normals.append(n)
			chunks[key].colors.append(tint)
	for key in chunks:
		_add_mesh(terrain_root, chunks[key], material, "Chunk_%d_%d" % [key.x, key.y])
	chunk_count = chunks.size()
	_add_rim()
	if not water.is_empty(): _build_water()
	_build_grid()
	set_grid_visible(grid_enabled)
	build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	fit_overview()

func _add_mesh(parent: Node3D, data: Dictionary, mat: Material, label: String) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	if data.has("colors"): arrays[Mesh.ARRAY_COLOR] = data.colors
	if data.has("uv2"): arrays[Mesh.ARRAY_TEX_UV2] = data.uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _add_rim() -> void:
	var data := {"vertices": PackedVector3Array(), "normals": PackedVector3Array()}
	var bottom: float = world.bounds.position.y - 0.8
	for j in range(world.boundary_loop.size()):
		var a: Vector3 = world.positions[int(world.boundary_loop[j])]
		var b: Vector3 = world.positions[int(world.boundary_loop[(j + 1) % world.boundary_loop.size()])]
		var c := Vector3(a.x, bottom, a.z)
		var d := Vector3(b.x, bottom, b.z)
		var n := (b - a).cross(c - a).normalized()
		for p in [a, b, c, b, d, c]:
			data.vertices.append(p)
			data.normals.append(n)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("3c3324")
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(terrain_root, data, mat, "NonGameplayBoundaryRim")

func _build_grid() -> void:
	var data := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uv2": PackedVector2Array()}
	for edge in world.edges:
		# Straight original hex segment, split at every stored PL triangle edge.
		var aa: Vector3 = world.positions[edge[0]]
		var bb: Vector3 = world.positions[edge[4]]
		var a := Vector2(aa.x, aa.z)
		var b := Vector2(bb.x, bb.z)
		var direction := b - a
		var cuts := [0.0, 1.0]
		var candidates := {}
		for x in range(floori(minf(a.x, b.x) / 2.0) - 1, floori(maxf(a.x, b.x) / 2.0) + 2):
			for z in range(floori(minf(a.y, b.y) / 2.0) - 1, floori(maxf(a.y, b.y) / 2.0) + 2):
				for fi in world.buckets.get(Vector2i(x, z), PackedInt32Array()): candidates[fi] = true
		for fi in candidates:
			for j in range(3):
				var pp: Vector3 = world.positions[world.indices[fi * 3 + j]]
				var qq: Vector3 = world.positions[world.indices[fi * 3 + (j + 1) % 3]]
				var p := Vector2(pp.x, pp.z)
				var e := Vector2(qq.x, qq.z) - p
				var cross := direction.cross(e)
				if absf(cross) < 0.00000001: continue
				var t := (p - a).cross(e) / cross
				var u := (p - a).cross(direction) / cross
				if t > 0.000001 and t < 0.999999 and u >= -0.000001 and u <= 1.000001: cuts.append(t)
		if not water.is_empty():
			for fi in candidates:
				for idx in water.by_face.get(fi, PackedInt32Array()):
					var polygon: PackedVector2Array = water.footprints[idx].polygon
					for j in range(polygon.size()):
						var p := polygon[j]
						var e := polygon[(j + 1) % polygon.size()] - p
						var cross := direction.cross(e)
						if absf(cross) < 0.00000001: continue
						var t := (p - a).cross(e) / cross
						var u := (p - a).cross(direction) / cross
						if t > 0.000001 and t < 0.999999 and u >= -0.000001 and u <= 1.000001: cuts.append(t)
		cuts.sort()
		var clean := []
		for t in cuts:
			if clean.is_empty() or absf(t - clean[-1]) > 0.000001: clean.append(t)
		for j in range(clean.size() - 1):
			var p: Vector2 = a + direction * clean[j]
			var q: Vector2 = a + direction * clean[j + 1]
			var midpoint := (p + q) * 0.5
			var hit := Loader.height_at(world, midpoint)
			if not hit.ok: continue
			var py := _face_height(hit.face, p)
			var qy := _face_height(hit.face, q)
			if not water.is_empty():
				var water_hit := WaterLoader.surface_at(water, hit.face, midpoint)
				if water_hit.ok: py = water_hit.height; qy = water_hit.height
			_add_strip(data, Vector3(p.x, py + 0.014, p.y), Vector3(q.x, qy + 0.014, q.y), 0.012)
			grid_segment_count += 1
	grid_material = ShaderMaterial.new()
	grid_material.shader = preload("res://view/recovered_terrain/recovered_grid.gdshader")
	_add_mesh(grid_root, data, grid_material, "ActualCanonicalGridStrips")

func _face_height(fi: int, p: Vector2) -> float:
	var a: Vector3 = world.positions[world.indices[fi * 3]]
	var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
	var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
	var u := Vector2(b.x - a.x, b.z - a.z)
	var v := Vector2(c.x - a.x, c.z - a.z)
	var rel := p - Vector2(a.x, a.z)
	var wb := rel.cross(v) / u.cross(v)
	var wc := u.cross(rel) / u.cross(v)
	return a.y * (1.0 - wb - wc) + b.y * wb + c.y * wc

func _add_strip(data: Dictionary, a: Vector3, b: Vector3, width: float) -> void:
	var offset := Vector3(-(b.z - a.z), 0, b.x - a.x).normalized() * width * 0.5
	var points := [a - offset, a + offset, b + offset, a - offset, b + offset, b - offset]
	var signs := [-1.0, 1.0, 1.0, -1.0, 1.0, -1.0]
	for i in range(points.size()):
		data.vertices.append(points[i])
		data.normals.append(Vector3.UP)
		data.uv2.append(Vector2(offset.x, offset.z) * signs[i])

func set_grid_visible(enabled: bool) -> void:
	grid_enabled = enabled
	if is_instance_valid(grid_root): grid_root.visible = enabled

func fit_overview() -> void:
	if world.is_empty(): return
	overview = true
	var bounds: AABB = world.bounds
	target = bounds.get_center()
	target.y *= height_scale
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect := maxf(0.1, size.x / maxf(size.y, 1.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.z, bounds.size.x / aspect) * 1.10
	camera.position = Vector3(target.x, bounds.end.y * height_scale + maxf(32.0, bounds.size.length()), target.z)
	camera.look_at(target, Vector3(0, 0, -1))
	_update_grid_width()

func focus_close() -> void:
	if world.is_empty(): return
	overview = false
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 46.0
	distance = 12.0
	pitch = 0.65
	_update_camera()

func orbit(dx: float, dy: float) -> void:
	if world.is_empty(): return
	if overview:
		overview = false
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		distance = maxf(12.0, camera.size * 0.8)
	yaw -= dx
	pitch = clampf(pitch + dy, 0.20, 1.48)
	_update_camera()

func zoom(delta: float) -> void:
	if world.is_empty(): return
	if overview:
		camera.size = clampf(camera.size * exp(delta * 0.12), 4.0, 180.0)
		_update_grid_width()
	else:
		distance = clampf(distance * exp(delta * 0.12), 4.0, 180.0)
		_update_camera()

func pan(dx: float, dy: float) -> void:
	if world.is_empty(): return
	var scale_ := camera.size if overview else distance * 0.6
	var right := camera.global_basis.x
	var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
	if overview: forward = Vector3(0, 0, 1)
	target += (right * -dx + forward * -dy) * scale_ / maxf(1.0, get_viewport().get_visible_rect().size.y)
	target.x = clampf(target.x, world.bounds.position.x - 2.0, world.bounds.end.x + 2.0)
	target.z = clampf(target.z, world.bounds.position.z - 2.0, world.bounds.end.z + 2.0)
	if overview:
		camera.position.x = target.x
		camera.position.z = target.z
	else: _update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var support := Loader.height_at(world, Vector2(camera.position.x, camera.position.z))
	if support.ok: camera.position.y = maxf(camera.position.y, support.height * height_scale + 0.40)
	camera.look_at(target, Vector3.UP)
	_update_grid_width()

func inspect(screen: Vector2) -> Dictionary:
	if world.is_empty(): return {"ok": false}
	var inverse := content_root.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(screen)
	var direction := (inverse.basis * camera.project_ray_normal(screen)).normalized()
	var result := Loader.ray_pick(world, origin, direction)
	if not water.is_empty():
		var water_hit := _water_pick(origin, direction)
		if water_hit.ok and (not result.ok or water_hit.distance < result.distance - 0.000001): result = water_hit
	if result.ok:
		var p: Vector3 = result.position
		var canonical := canonical_hex(p)
		result.canonical_hex = canonical
		selected_hex = canonical
		result.display_position = content_root.global_transform * p
		result.display_height = result.display_position.y
		target = result.display_position
	return result

static func canonical_hex(point: Vector3) -> String:
	var qf := point.x / sqrt(3.0) - point.z / 3.0
	var rf := point.z * 2.0 / 3.0
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds: q = -r - s
	elif dr > ds: r = -q - s
	return "hex:%d,%d" % [q, r]

func metrics() -> Dictionary:
	return {"build_ms": build_ms, "chunks": chunk_count, "grid_segments": grid_segment_count, "grid_visible": grid_enabled, "terrain_faces": world.face_ids.size() if not world.is_empty() else 0, "water_triangles": water.get("triangles", 0), "height_scale": height_scale, "projection": camera.projection, "distance": distance, "pitch": pitch, "yaw": yaw, "target": [target.x, target.y, target.z], "camera_size": camera.size, "camera_position": [camera.position.x, camera.position.y, camera.position.z], "camera_forward": [-camera.global_basis.z.x, -camera.global_basis.z.y, -camera.global_basis.z.z], "llvmpipe_only_no_target_hardware_claim": true}

func _update_grid_width() -> void:
	if grid_material == null: return
	var pixel_world := camera.size / maxf(1.0, get_viewport().get_visible_rect().size.y) if overview else distance * 2.0 * tan(deg_to_rad(camera.fov * 0.5)) / maxf(1.0, get_viewport().get_visible_rect().size.y)
	grid_material.set_shader_parameter("width_scale", clampf(pixel_world * 0.8 / 0.012, 1.0, 15.0))

func set_height_scale(value: float) -> void:
	var next := 2.0 if value == 2.0 else 1.0
	target.y *= next / height_scale
	height_scale = next
	content_root.scale = Vector3(1.0, height_scale, 1.0)
	if world.is_empty(): return
	if overview: fit_overview()
	else: _update_camera()

func _build_water() -> void:
	var chunks := {}
	for footprint in water.footprints:
		var cell: Dictionary = world.cells[world.face_owners[footprint.face]]
		var key := "%s_%d_%d" % [footprint.kind, floori(float(cell.q) / 6.0), floori(float(cell.r) / 6.0)]
		if not chunks.has(key): chunks[key] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "kind": footprint.kind}
		var polygon: PackedVector2Array = footprint.polygon
		for j in range(1, polygon.size() - 1):
			for idx in [0, j + 1, j]:
				var p := polygon[idx]
				chunks[key].vertices.append(Vector3(p.x, footprint.level, p.y))
				chunks[key].normals.append(Vector3.UP)
	var materials := {}
	for kind in ["ocean", "lake_candidate"]:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://view/recovered_terrain/recovered_water.gdshader")
		mat.set_shader_parameter("water_color", Color("397c88") if kind == "ocean" else Color("537b80"))
		materials[kind] = mat
	for key in chunks: _add_mesh(water_root, chunks[key], materials[chunks[key].kind], key)

func _water_pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var nearest := INF
	var answer := {"ok": false}
	for footprint in water.footprints:
		if absf(direction.y) < 0.00000001: continue
		var t: float = (footprint.level - origin.y) / direction.y
		if t < 0.0 or t >= nearest: continue
		var p := origin + direction * t
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), footprint.polygon):
			nearest = t
			answer = {"ok": true, "position": p, "height": footprint.level, "distance": t, "face": footprint.face, "face_id": world.face_ids[footprint.face], "owner": world.face_owners[footprint.face], "body_id": footprint.body_id, "water_kind": footprint.kind, "terrain_height": _face_height(footprint.face, Vector2(p.x,p.z))}
	return answer

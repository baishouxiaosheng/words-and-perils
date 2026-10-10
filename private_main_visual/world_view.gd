extends "res://view/integrated_ecology_world/performance_variant/world_view66.gd"
signal private_visual_bounds_dirty
## Character view: a perspective camera whose visible height at the target is
## camera.size, so zoom-dependent code keeps reading size. The closest view
## (VIEW_MIN) has a mild 40 degree perspective; lifting narrows the field of
## view toward a weak telephoto, so a wide view stays nearly as flat as a map.
## Pitch stays in a small band and is raised only while terrain would block
## the sightline. Overview (the whole-map button) stays orthographic.
const VIEW_MIN := 6.0
const VIEW_MAX := 40.0
const FOV_NEAR := 40.0
const FOV_FAR := 14.0
const PITCH_MIN := .62
const PITCH_MAX := .86
const PITCH_CLEAR_MAX := 1.25
const CELL := 1.5
## World point the depth of field focuses on; the board keeps it on the player
## or the first selected object. A NAN x focuses on the view target.
var focus_point := Vector3(NAN, 0, 0)
var _attributes: CameraAttributesPractical
var _heights: Dictionary = {}
var _heights_dirty := true
var _height_queue: Array = []
var _height_count := -1
var _shadow_reach := NAN
var _shadow_split := .3
var _far_depth := 0.0
var _board_box := AABB()
var _veil: MeshInstance3D
var _sky: Environment

## 0 at the closest view, 1 at the widest.
static func view_lift(size: float) -> float:
	return clampf(log(maxf(size, .01) / VIEW_MIN) / log(VIEW_MAX / VIEW_MIN), 0.0, 1.0)

## The base places the whole-map camera directly without _update_camera, so the
## depth of field and atmosphere of the previous view are cleared here.
func set_scope(name_: String) -> void:
	super.set_scope(name_)
	if overview:
		camera.attributes = null
		_update_atmosphere()

func orbit(dx: float, dy: float) -> void:
	if overview: scope_name = "free"; overview = false; camera.size = 12
	yaw -= dx; pitch = clampf(pitch + dy, PITCH_MIN, PITCH_MAX); _update_camera()

func _update_camera() -> void:
	if overview:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.attributes = null
		super._update_camera()
		_update_atmosphere()
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = lerpf(FOV_NEAR, FOV_FAR, view_lift(camera.size))
	distance = camera.size * .5 / tan(deg_to_rad(camera.fov) * .5)
	var chosen := pitch
	pitch = _clear_pitch(pitch)
	super._update_camera()
	pitch = chosen
	_update_shadow_range()
	_update_focus()
	_update_atmosphere()

## Lowest pitch at or above the chosen one whose sightline from the target to
## the camera stays above ground and mountains.
func _clear_pitch(from: float) -> float:
	var heights := _height_grid()
	if heights.is_empty(): return from
	var p := from
	while p < PITCH_CLEAR_MAX:
		var blocked := false
		for i in range(1, 11):
			var at := target + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * (i / 10.0 * distance)
			var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
			if heights.has(cell) and at.y < float(heights[cell]) + .6: blocked = true; break
		if not blocked: return p
		p += .03
	return PITCH_CLEAR_MAX

## Height field of the terrain-scale meshes (ground, shoreline, mountains);
## pieces, buildings and MultiMesh trees are left out so they never tilt the
## view. Fine meshes record their vertices per cell; meshes with large faces
## (the faceted mountains) record each face's highest vertex over its footprint.
## Reading mesh data back is slow, so a few meshes are added per frame and the
## sightline test uses whatever part of the field is ready.
func _height_grid() -> Dictionary:
	if _heights_dirty:
		if not content_root.child_entered_tree.is_connected(_mark_heights_dirty):
			content_root.child_entered_tree.connect(_mark_heights_dirty)
			content_root.child_exiting_tree.connect(_mark_heights_dirty)
		_heights_dirty = false
		# Pieces and effects come and go under the same root; only a change in
		# the terrain-scale meshes rebuilds the field.
		var meshes: Array = content_root.find_children("*", "MeshInstance3D", true, false).filter(_terrain_scale)
		if meshes.size() != _height_count:
			_height_count = meshes.size(); _heights = {}; _height_queue = meshes
			_board_box = AABB()
			for instance: MeshInstance3D in meshes:
				var box := instance.global_transform * instance.mesh.get_aabb()
				_board_box = box if _board_box.size == Vector3.ZERO else _board_box.merge(box)
	return _heights
func _add_heights(instance: MeshInstance3D) -> void:
	var xf := instance.global_transform
	for s in range(instance.mesh.get_surface_count()):
		if instance.mesh is ArrayMesh and instance.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := instance.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = xf * PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		var box := xf * instance.mesh.get_aabb()
		if box.size.x * box.size.z / maxf(1.0, count / 3.0) < CELL * CELL * .25:
			# Faces far smaller than a cell: every third vertex still lands in each cell.
			for i in range(0, vertices.size(), 3): _raise(Vector2i(floori(vertices[i].x / CELL), floori(vertices[i].z / CELL)), vertices[i].y)
			continue
		for i in range(0, count - 2, 3):
			var a: Vector3 = vertices[indices[i] if not indices.is_empty() else i]
			var b: Vector3 = vertices[indices[i + 1] if not indices.is_empty() else i + 1]
			var c: Vector3 = vertices[indices[i + 2] if not indices.is_empty() else i + 2]
			var top := maxf(a.y, maxf(b.y, c.y))
			for x in range(floori(minf(a.x, minf(b.x, c.x)) / CELL), floori(maxf(a.x, maxf(b.x, c.x)) / CELL) + 1):
				for z in range(floori(minf(a.z, minf(b.z, c.z)) / CELL), floori(maxf(a.z, maxf(b.z, c.z)) / CELL) + 1):
					_raise(Vector2i(x, z), top)
func _mark_heights_dirty(_node: Node = null) -> void:
	_heights_dirty = true
func _raise(cell: Vector2i, height: float) -> void:
	if height > float(_heights.get(cell, -INF)): _heights[cell] = height
static func _terrain_scale(node: MeshInstance3D) -> bool:
	if node.mesh == null or not node.is_visible_in_tree(): return false
	var box := node.global_transform * node.mesh.get_aabb()
	return maxf(box.size.x, box.size.z) >= 3.0

## Visible ground footprint: the screen corners cast onto the target's level.
func _footprint() -> PackedVector3Array:
	var size := get_viewport().get_visible_rect().size
	var points := PackedVector3Array()
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var origin := camera.project_ray_origin(corner)
		var direction := camera.project_ray_normal(corner)
		var along := (target.y - origin.y) / direction.y if direction.y < -.02 else INF
		points.append(origin + direction * minf(along, distance * 4.0))
	return points

## The palette sun's shadows reach the far edge of the visible ground. The sun
## is installed after the first view, so the range is re-applied every frame.
func _update_shadow_range() -> void:
	var forward := -camera.global_basis.z
	var depth := 0.0
	for point in _footprint(): depth = maxf(depth, (point - camera.global_position).dot(forward))
	_far_depth = depth
	_shadow_reach = clampf(depth * 1.08, 24.0, 400.0)
	_shadow_split = clampf((distance + camera.size * .5) / _shadow_reach, .15, .7)
func _process(_delta: float) -> void:
	if not _height_queue.is_empty():
		var started := Time.get_ticks_usec()
		while not _height_queue.is_empty() and Time.get_ticks_usec() - started < 3000:
			var instance: MeshInstance3D = _height_queue.pop_back()
			if is_instance_valid(instance) and instance.mesh != null: _add_heights(instance)
		if _height_queue.is_empty() and not overview: _update_camera()
	if overview or is_nan(_shadow_reach): return
	var sun := get_parent().get_node_or_null("SinglePaletteShadowSun") as DirectionalLight3D if get_parent() else null
	if sun and not is_equal_approx(sun.directional_shadow_max_distance, _shadow_reach):
		sun.directional_shadow_max_distance = _shadow_reach
		sun.directional_shadow_split_1 = _shadow_split

## Depth of field around the focus point: strongest at the closest view, gone
## once the view is wide enough to read a region.
func _update_focus() -> void:
	var t := view_lift(camera.size)
	var strength := 1.0 - smoothstep(0.0, .55, t)
	if strength <= .01:
		camera.attributes = null
		return
	if _attributes == null:
		_attributes = CameraAttributesPractical.new()
		_attributes.dof_blur_far_enabled = true
		_attributes.dof_blur_near_enabled = true
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_LOW, false)
	var point := target if is_nan(focus_point.x) else focus_point
	var focus := maxf(camera.global_position.distance_to(point), 1.0)
	var band := focus * lerpf(.16, .45, t)
	_attributes.dof_blur_far_distance = focus + band
	_attributes.dof_blur_far_transition = focus * .9
	_attributes.dof_blur_near_distance = maxf(focus - band, .1)
	_attributes.dof_blur_near_transition = focus * .35
	_attributes.dof_blur_amount = .11 * strength
	camera.attributes = _attributes

## Far-view atmosphere, all continuous in the view lift: haze rises from the
## target's depth to the far edge of the visible ground, and a mist band inside
## the board's hexagonal outline (measured from the terrain extent) hides the
## stepped map edge. Both fade toward the sky colour so they never show as a
## band against the background.
func _update_atmosphere() -> void:
	if not is_inside_tree(): return
	if _veil == null:
		var material := ShaderMaterial.new()
		material.shader = preload("atmosphere.gdshader")
		material.render_priority = Material.RENDER_PRIORITY_MIN
		var quad := QuadMesh.new()
		_veil = MeshInstance3D.new()
		_veil.name = "FarViewAtmosphere"
		_veil.mesh = quad
		_veil.material_override = material
		_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_veil.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
		# Outside the board, so the palette audit of the board's surfaces never sees it.
		get_viewport().add_child.call_deferred(_veil)
		tree_exiting.connect(_veil.queue_free)
	if _sky == null:
		for node: WorldEnvironment in find_children("*", "WorldEnvironment", true, false): _sky = node.environment
	var material: ShaderMaterial = _veil.material_override
	var t := 1.0 if overview else view_lift(camera.size)
	if _sky: material.set_shader_parameter("haze_color", _sky.background_color)
	material.set_shader_parameter("haze_amount", 0.0 if overview else .5 * smoothstep(.15, 1.0, t))
	material.set_shader_parameter("haze_depth", Vector2(distance, maxf(_far_depth, distance + 1.0)))
	if _board_box.size != Vector3.ZERO:
		var centre := _board_box.get_center()
		var half := Vector2(_board_box.size.x, _board_box.size.z) * .5
		var corners_on_x := half.x >= half.y
		var apothem := minf(half.y, half.x * .8660254) if corners_on_x else minf(half.x, half.y * .8660254)
		material.set_shader_parameter("board", Vector4(centre.x, centre.z, apothem, 1.0 if corners_on_x else 0.0))
		material.set_shader_parameter("edge_mist", lerpf(1.5, 7.0, t))

## Canopy detail is chosen in a circle around the target sized from
## camera.size; a perspective view reaches farther up the screen than down, so
## the circle is centred on the visible footprint and sized to cover it.
func _update_budget()->void:
	if overview or camera.projection!=Camera3D.PROJECTION_PERSPECTIVE:
		super._update_budget()
		private_visual_bounds_dirty.emit()
		return
	var points:=_footprint()
	var centre:=Vector3.ZERO
	for point in points:centre+=point
	centre/=4.0;centre.y=target.y
	var radius:=0.0
	for point in points:radius=maxf(radius,Vector2(point.x-centre.x,point.z-centre.z).length())
	var size:=get_viewport().get_visible_rect().size
	var aspect:=maxf(1.0,size.x/maxf(1.0,size.y))
	var kept_target:=target;var kept_size:=camera.size
	target=centre;camera.size=maxf(kept_size,(radius-6.0)/(aspect*.8))
	super._update_budget()
	target=kept_target;camera.size=kept_size
	private_visual_bounds_dirty.emit()
func _new_world_canopies()->Node3D:
	return preload("sapling_display_loader.gd").new()
func apply_clear_daylight_profile()->void:
	if not clear_daylight_enabled or not is_instance_valid(whole_canopies) or whole_canopies.selected_variant!="natural_v2":return
	clear_daylight_profile=preload("daylight_profile.gd").attach_to(self)
	if natural_shorelines_enabled:apply_natural_shorelines()
	apply_faceted_mountains()

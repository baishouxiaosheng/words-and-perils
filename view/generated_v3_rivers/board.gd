extends Node3D
## Native triangle rendering and picking share the admitted, immutable bundle.
## This view has no transaction authority. A click only emits a tile selection.
const Picking = preload("res://view/generated_v3_adventure/picking.gd")
signal hex_selected(hex: Array)
var admitted_source: RefCounted
var world_state: Dictionary = {}
var camera: Camera3D
var terrain_root: Node3D
var actor_token: Node3D
var selection_root: Node3D
var route_root: Node3D
var picking = Picking.new()
var selected_hex: Array = []
var view_focus := Vector3.ZERO
var view_angle := 0.18
var view_pitch := 0.85
var load_error := ""
var route_signature := ""
var geometry_signature := ""
var token_support_metrics: Dictionary = {}
var _orbit_dragging := false
var _top_down := false

func _init(source_: RefCounted = null) -> void:
	admitted_source = source_

func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.near = 0.02
	camera.far = 250.0
	camera.current = true
	add_child(camera)
	selection_root = Node3D.new(); selection_root.name = "ReadOnlySelection"; add_child(selection_root)
	route_root = Node3D.new(); route_root.name = "ReadOnlyRoutePreview"; add_child(route_root)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b9d8d9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d6e4ec")
	settings.ambient_light_energy = 0.5
	environment.environment = settings; add_child(environment)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.0; light.rotation_degrees = Vector3(-60,-34,0); add_child(light)
	_install_geometry()
	normal_zoom()

func _install_geometry() -> void:
	if admitted_source == null:
		load_error = "No admitted river source; no substitute map was displayed."; return
	var built: Dictionary = admitted_source.renderer_bundle
	if not built.get("ok",false) or built.get("source_hash") != admitted_source.identity.content_hash or built.get("geometry_hash") != admitted_source.identity.geometry_hash or built.get("water_hash") != admitted_source.identity.water_hash or built.get("river_layout_hash") != admitted_source.identity.river_layout_hash or built.get("river_surface_hash") != admitted_source.identity.river_surface_hash:
		load_error = "Rendered ground/water identity differs from the admitted world."; return
	var signature: String = str(built.geometry_hash) + str(built.water_hash)
	if signature == geometry_signature: return
	if is_instance_valid(terrain_root):
		remove_child(terrain_root); terrain_root.queue_free()
	terrain_root = Node3D.new(); terrain_root.name = "ActualCarvedGroundAndWater"; add_child(terrain_root)
	for layer in ["ground","water"]:
		var mesh: Mesh = built.get(layer+"_mesh")
		if mesh == null: continue
		var instance := MeshInstance3D.new()
		instance.name = layer; instance.mesh = mesh; instance.material_override = built[layer+"_material"]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_root.add_child(instance)
	picking.build(built.ground_mesh,built.water_mesh)
	geometry_signature = signature
	set_meta("renderer_profile",built.renderer_profile)
	set_meta("source_hash",built.source_hash)
	set_meta("geometry_hash",built.geometry_hash)
	set_meta("water_hash",built.water_hash)
	set_meta("river_layout_hash",built.river_layout_hash)
	load_error = ""

func set_world(state: Dictionary) -> void:
	if admitted_source == null or not admitted_source.validate_state(state).ok:
		load_error = "World failed validation; the existing view was preserved."; return
	_install_geometry()
	if not load_error.is_empty(): return
	world_state = state.duplicate(true)
	if not is_instance_valid(actor_token):
		actor_token = _make_actor(); add_child(actor_token)
	var center: Vector3 = admitted_source.navigation.cell_center(state.actors.actor_player.hex)
	token_support_metrics = token_support_pose(center)
	actor_token.position = token_support_metrics.position
	actor_token.rotation = token_support_metrics.rotation
	actor_token.set_meta("actor_id","actor_player")
	actor_token.set_meta("hex",state.actors.actor_player.hex.duplicate())
	_refresh_selection()

func _make_actor() -> Node3D:
	var root := Node3D.new(); root.name = "Traveler"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f2e1b0"); material.roughness = 0.9
	var base := CylinderMesh.new(); base.top_radius = 0.31; base.bottom_radius = 0.33; base.height = 0.08; base.radial_segments = 24
	var body := CylinderMesh.new(); body.top_radius = 0.10; body.bottom_radius = 0.19; body.height = 0.40; body.radial_segments = 20
	var head := SphereMesh.new(); head.radius = 0.14; head.height = 0.28; head.radial_segments = 20; head.rings = 10
	for pair in [[base,0.04],[body,0.28],[head,0.60]]:
		var node := MeshInstance3D.new(); node.mesh = pair[0]; node.position.y = pair[1]; node.material_override = material; root.add_child(node)
	return root

func token_support_pose(center: Vector3) -> Dictionary:
	var radius := 0.33
	var samples: Array = []
	for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var hit: Dictionary = admitted_source.navigation.height_at_xz(Vector2(center.x,center.z)+offset)
		samples.append(float(hit.height) if hit.get("ok",false) else center.y)
	var gx: float = (samples[0]-samples[1])/(2.0*radius)
	var gz: float = (samples[2]-samples[3])/(2.0*radius)
	var normal := Vector3(-gx,1,-gz).normalized()
	var basis := Basis(Quaternion(Vector3.UP,normal))
	var origin_y := center.y
	var missing := 0
	for index in range(32):
		var angle := TAU*float(index)/32.0
		var point: Vector3 = basis*Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var hit: Dictionary = admitted_source.navigation.height_at_xz(Vector2(center.x+point.x,center.z+point.z))
		if hit.get("ok",false): origin_y = maxf(origin_y,float(hit.height)-point.y)
		else: missing += 1
	return {"position":Vector3(center.x,origin_y+0.004,center.z),"rotation":basis.get_euler(),"unsupported_samples":missing,"lift":origin_y-center.y+0.004,"radius":radius}

func select_hex(hex: Array) -> void:
	if hex.size() != 2 or not world_state.hexes.has("%d,%d" % hex): return
	selected_hex = hex.duplicate()
	_refresh_selection()

func _surface_position(xz: Vector2) -> Vector3:
	var hit: Dictionary = picking.raycast(Vector3(xz.x,100.0,xz.y),Vector3.DOWN)
	if hit.is_empty(): return Vector3.INF
	return hit.point + Vector3(0,0.03,0)

func _refresh_selection() -> void:
	if not is_instance_valid(selection_root): return
	_clear(selection_root)
	if selected_hex.is_empty(): return
	var center: Vector3 = admitted_source.navigation.cell_center(selected_hex)
	var previous := Vector3.INF
	for index in range(25):
		var angle := TAU*float(index)/24.0
		var point := _surface_position(Vector2(center.x+cos(angle)*0.78,center.z+sin(angle)*0.78))
		if point.is_finite() and previous.is_finite(): _line(selection_root,previous,point,0.018,Color("fff1ae"))
		previous = point

func set_route_preview(route: Array) -> void:
	if not is_instance_valid(route_root): return
	var signature := str(route)+geometry_signature
	if signature == route_signature: return
	route_signature = signature; _clear(route_root)
	if route.size() < 2: return
	var points: Array = admitted_source.navigation.route_points(route)
	for index in range(1,points.size()):
		_line(route_root,points[index-1]+Vector3(0,0.055,0),points[index]+Vector3(0,0.055,0),0.025,Color("f1d884"))

func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func _line(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	if a.distance_to(b) < 0.00001: return
	var mesh := CylinderMesh.new()
	mesh.top_radius = width; mesh.bottom_radius = width; mesh.height = a.distance_to(b); mesh.radial_segments = 5
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new(); node.mesh = mesh; node.material_override = material; node.position = (a+b)/2.0
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized()); node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func normal_zoom() -> void:
	_top_down = false; view_focus = Vector3.ZERO; camera.size = 18.0; _update_camera()

func closer_zoom() -> void:
	_top_down = false; focus_player(); camera.size = 9.0; _update_camera()

func focus_player() -> void:
	if world_state.is_empty(): return
	view_focus = admitted_source.navigation.cell_center(world_state.actors.actor_player.hex)+Vector3(0,0.25,0)
	_update_camera()

func top_down() -> void:
	_top_down = true; view_focus = Vector3.ZERO; camera.size = 17.0; _update_camera()

func rotate_view(amount: float) -> void:
	_top_down = false; view_angle += amount; _update_camera()

func _update_camera() -> void:
	if _top_down:
		camera.position = view_focus+Vector3(0,70,0); camera.look_at(view_focus,Vector3.FORWARD)
	else:
		camera.position = view_focus+Vector3(sin(view_angle)*cos(view_pitch),sin(view_pitch),cos(view_angle)*cos(view_pitch))*35.0
		camera.look_at(view_focus)

func pick(point: Vector2) -> Dictionary:
	if world_state.is_empty() or not load_error.is_empty(): return {}
	var hit: Dictionary = picking.raycast(camera.project_ray_origin(point),camera.project_ray_normal(point))
	if hit.is_empty(): return {}
	var cell: Dictionary = admitted_source.navigation.cell_at_xz(Vector2(hit.point.x,hit.point.z))
	if not cell.get("ok",false): return {}
	return {"hex":cell.hex,"surface":hit.surface,"point":hit.point}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_dragging = event.pressed; get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hit := pick(event.position)
			if not hit.is_empty(): hex_selected.emit(hit.hex)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size+(-0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8),6.0,26.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbit_dragging:
		if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0: _orbit_dragging = false; return
		_top_down = false; view_angle -= event.relative.x*0.006; view_pitch = clampf(view_pitch+event.relative.y*0.004,0.4,1.30)
		_update_camera(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_FOCUS_OUT]: _orbit_dragging = false

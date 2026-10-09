extends Node3D
# Independent read-only local river viewer; shared API is used by the main renderer.
const RiverOverlay = preload("river_overlay.gd")
var overlay: Node3D
var camera: Camera3D
var target := Vector3.ZERO
var default_target := Vector3.ZERO
var yaw := 0.63
var pitch := 0.72
var camera_size := 3.8
var drag := false
var pan := false
var info: Label
var capture_path := ""

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest_path := ProjectSettings.globalize_path("res://../../artifacts/river_overlay_portfix_20261002/optimized_same_footprint/render_cache_manifest_PENDING.json")
	var portable_manifest := ProjectSettings.globalize_path("res://../data/render_cache_manifest_PENDING.json")
	if FileAccess.file_exists(portable_manifest): manifest_path = portable_manifest
	var smoke := false
	var filtered := false
	for i in range(args.size()):
		if args[i] == "--river-cache" and i + 1 < args.size(): manifest_path = args[i + 1]
		if args[i] == "--screenshot" and i + 1 < args.size(): capture_path = args[i + 1]
		if args[i] == "--smoke": smoke = true
		if args[i] == "--filtered-integration": filtered = true
	overlay = RiverOverlay.new()
	add_child(overlay)
	if not overlay.load_cache(manifest_path,{"include_context_ground":not filtered,"include_existing_water":not filtered}):
		_fail(overlay.last_error)
		return
	var t: Array = overlay.manifest["camera_target_world"]
	target = Vector3(t[0],t[1],t[2])
	default_target = target
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100.0
	add_child(camera)
	camera.current = true
	_update_camera()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-40,0)
	light.light_energy = 1.05
	light.shadow_enabled = false
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055,0.073,0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.82,0.86,0.91)
	e.ambient_light_energy = 0.65
	env.environment = e
	add_child(env)
	_build_ui()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var actual_probes: Array = []
	for probe in overlay.manifest["collision_probes"]:
		var xz: Array = probe["xz"]
		var from := Vector3(xz[0],2.5,xz[1])
		var to := Vector3(xz[0],-1.5,xz[1])
		var wet_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,2))
		var ground_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
		if wet_hit.is_empty() or ground_hit.is_empty():
			_fail("Same-cache water/bed ray missed")
			return
		var wet_pos: Vector3 = wet_hit["position"]
		var ground_pos: Vector3 = ground_hit["position"]
		if abs(wet_pos.y-float(probe["water_y_from_packed_triangles"])) > 0.00002 or abs(ground_pos.y-float(probe["ground_y_from_same_packed_collision_triangles"])) > 0.00002:
			_fail("Same-cache collision and rendered height disagree")
			return
		var ctx: Dictionary = overlay.pick_surface(from,to,3)
		if not ctx.has("original_face") or not ctx.has("original_hex_id") or not ctx.get("inside_river_footprint",false):
			_fail("River picking lost original face/hex/footprint context")
			return
		actual_probes.append({"xz":xz,"actual_water_pick_y":wet_pos.y,"actual_ground_collision_y":ground_pos.y,"depth":wet_pos.y-ground_pos.y,"original_face":ctx["original_face"],"original_hex_id":ctx["original_hex_id"]})
	print(JSON.stringify({"status":"PASS_HEADLESS_COMPATIBILITY_SHARED_CACHE_RAY_PROBES","draw_triangles":overlay.draw_triangles,"terrain_collision_triangles_same_cache":overlay.terrain_triangles,"water_picking_triangles_same_cache":overlay.water_triangles,"actual_physics_ray_probes":actual_probes,"filtered_for_world_integration":filtered,"original_macro_modified":false,"full_world_science_acceptance":false}))
	if not capture_path.is_empty():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(capture_path)
		print("RIVER_NATIVE_CAPTURE ",capture_path," error=",err)
		if err != OK:
			_fail("Native screenshot save failed")
			return
		get_tree().quit(0)
	elif smoke:
		get_tree().quit(0)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24,24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",9)
	margin.add_child(box)
	var title := Label.new()
	title.text = "RIVER REACH  /  TWO REAL LAKE PORTS"
	title.add_theme_font_size_override("font_size",21)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "lake:28127  →  lake:31    |    water width 0.12    |    shallow carved bed"
	subtitle.add_theme_color_override("font_color",Color(0.73,0.83,0.84))
	box.add_child(subtitle)
	var controls := Label.new()
	controls.text = "Drag right: orbit   •   Middle drag: pan   •   Wheel: zoom   •   R: reset   •   Click: inspect"
	controls.add_theme_font_size_override("font_size",13)
	box.add_child(controls)
	info = Label.new()
	info.text = "Click water, bank or ground to inspect its original face and hex\nLocal real-source preview. No whole-river-network or movement-rule claim."
	info.add_theme_font_size_override("font_size",13)
	box.add_child(info)

func _update_camera() -> void:
	camera.size = camera_size
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*5.0
	camera.look_at(target,Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: drag = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE: pan = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_size = maxf(3.8,camera_size*0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_size = minf(9.0,camera_size/0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var origin := camera.project_ray_origin(event.position)
			var context: Dictionary = overlay.pick_surface(origin,origin+camera.project_ray_normal(event.position)*30.0)
			if not context.is_empty():
				var pos: Vector3 = context["position"]
				info.text = "%s  |  original face %s  |  %s\nXYZ %.4f, %.4f, %.4f  |  same render / collision / picking surface" % [context.get("kind","surface"),context.get("original_face","?"),context.get("original_hex_id","?"),pos.x,pos.y,pos.z]
		_update_camera()
	elif event is InputEventMouseMotion:
		if drag:
			yaw -= event.relative.x*0.006
			pitch = clampf(pitch+event.relative.y*0.006,0.30,1.35)
		if pan:
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
			target += (-right*event.relative.x-forward*event.relative.y)*camera_size/get_viewport().get_visible_rect().size.y
		_update_camera()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		target = default_target
		yaw = 0.63
		pitch = 0.72
		camera_size = 3.8
		_update_camera()

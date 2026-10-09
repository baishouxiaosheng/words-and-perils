extends SceneTree
## Isolated renderer lifetime reproduction. No game code or saved state.
var variant := "no_sky"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args(): variant = arg
	run.call_deferred()
func make_scene(with_sky: bool) -> Node3D:
	var scene := Node3D.new()
	var camera := Camera3D.new(); camera.position.z = 3; scene.add_child(camera)
	var owner := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("758e97")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if with_sky:
		var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new()
		environment.sky = sky
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	owner.environment = environment; scene.add_child(owner)
	return scene
func settle(count: int) -> void:
	for i in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
func run() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(320,240)
	viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := make_scene(variant != "no_sky")
	viewport.add_child(scene)
	if variant == "settled_sky": await settle(3)
	viewport.remove_child(scene); scene.free()
	await settle(5)
	viewport.queue_free(); await settle(3)
	print("SKY_DIAG_COMPLETED ",variant," NO_GAME_STATE")
	quit(0)

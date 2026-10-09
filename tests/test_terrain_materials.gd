extends SceneTree
## Material API/import assertions. Optional --render proves native GPU shader
## compilation on a small isolated mesh, not the game's native screenshot QA.
const TerrainMaterials = preload("res://view/terrain_materials.gd")
var errors: Array[String] = []
var render_requested := false
var sample_viewport: SubViewport

func _initialize() -> void:
	call_deferred("_verify")

func require(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func _verify() -> void:
	var detailed: ShaderMaterial = TerrainMaterials.ground_material(false)
	require(detailed != null, "Detailed material exists")
	require(detailed.shader != null, "Terrain shader loads")
	var uniform_names: Array[String] = []
	for item in detailed.shader.get_shader_uniform_list():
		uniform_names.append(String(item.name))
	for name_ in ["grass_patch_m", "rock_patch_m", "texel_density", "software_preview", "grass_palette_strength", "rock_palette_strength"]:
		require(uniform_names.has(name_), "Shader parses/exported uniform: " + name_)
	for kind in ["grass", "rock"]:
		for map_ in ["albedo", "normal", "roughness"]:
			var texture_: Texture2D = detailed.get_shader_parameter(kind + "_" + map_)
			require(texture_ != null, kind + " " + map_ + " loads")
			if texture_ != null:
				require(texture_.get_size() == Vector2(1024, 1024), kind + " " + map_ + " keeps native 1K size")
				var image: Image = texture_.get_image()
				require(image != null and image.has_mipmaps(), kind + " " + map_ + " imports mipmaps")
				var config := ConfigFile.new()
				require(config.load(texture_.resource_path + ".import") == OK, kind + " " + map_ + " sidecar loads")
				require(config.get_value("params", "compress/mode") == 0, "Lossless terrain import")
				require(config.get_value("params", "process/normal_map_invert_y") == false, "Keep +Y normals")
				if map_ == "normal":
					require(config.get_value("params", "compress/normal_map") == 1, "Data normal import")
	TerrainMaterials.set_software_preview(true)
	require(detailed.get_shader_parameter("software_preview") == true, "Preset updates already shared material")
	require("Software" in TerrainMaterials.quality_label(), "Reduced preset is labeled")
	var preview: ShaderMaterial = TerrainMaterials.ground_material(true)
	require(preview == detailed, "Quality changes keep material identity")
	TerrainMaterials.set_software_preview(false)
	require(preview.get_shader_parameter("software_preview") == false, "Full PBR can be restored")
	require(TerrainMaterials.material_metadata().normal_convention.contains("+Y"), "Normal convention is explicit")
	if OS.get_cmdline_user_args().has("--render"):
		if DisplayServer.get_name() == "headless":
			push_error("--render requires a real display/GLCompatibility; headless is only API/import verification")
			quit(2)
			return
		render_requested = true
		await _render_hook(detailed)
	print("TERRAIN_MATERIALS: ", "PASS" if errors.is_empty() else "FAIL", " (", "native render hook" if render_requested else "headless API/import", ")")
	quit(0 if errors.is_empty() else 1)

func _render_hook(material: ShaderMaterial) -> void:
	sample_viewport = SubViewport.new()
	sample_viewport.size = Vector2i(900, 600)
	sample_viewport.own_world_3d = true
	sample_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sample_viewport)
	var stage := Node3D.new()
	sample_viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("29333a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d7e0e4")
	environment.environment.ambient_light_energy = 0.30
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -34, 0)
	light.light_energy = 1.0
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(4.7, 4.4, 5.6)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.6, 0))
	camera.current = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Same continuous world positions cross repeated patches and several facets.
	for z in range(-18, 18):
		for x in range(-18, 18):
			var a := Vector3(float(x) / 6.0, 0, float(z) / 6.0)
			var b := a + Vector3(1.0 / 6.0, 0, 0)
			var c := a + Vector3(0, 0, 1.0 / 6.0)
			var d := b + Vector3(0, 0, 1.0 / 6.0)
			for p: Vector3 in [a, c, b, b, c, d]:
				p.y = 0.14 + maxf(0.0, 2.1 - p.distance_to(Vector3(0.6, 0, -0.1)) * 1.1)
				surface.set_color(Color("95a879").srgb_to_linear())
				surface.set_smooth_group(-1 if p.y > 0.48 else 0)
				surface.add_vertex(p)
	surface.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.mesh = surface.commit()
	terrain.material_override = material
	stage.add_child(terrain)
	var output := "res://artifacts/terrain_material_check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var detailed_frame: Image
	for preview in [false, true]:
		TerrainMaterials.set_software_preview(preview)
		for i in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = sample_viewport.get_texture().get_image()
		require(image != null and not image.is_empty(), "GPU frame is readable")
		if image != null:
			if not preview: detailed_frame = image
			var path := output + ("/software.png" if preview else "/detailed.png")
			require(image.save_png(path) == OK, "Native GPU hook image saves")
			print("GPU TERRAIN FRAME: ", ProjectSettings.globalize_path(path))
	TerrainMaterials.set_software_preview(false)
	# Same light/camera/geometry; isolate real normal and roughness response.
	for probe in ["normals_off", "roughness_low"]:
		if probe == "normals_off":
			material.set_shader_parameter("grass_normal_strength", 0.0)
			material.set_shader_parameter("rock_normal_strength", 0.0)
		else:
			material.set_shader_parameter("roughness_scale", 0.25)
		for i in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var probe_frame: Image = sample_viewport.get_texture().get_image()
		var delta := _image_delta(detailed_frame, probe_frame)
		print("GPU MATERIAL RESPONSE ", probe, ": mean RGB change = ", delta)
		require(delta > 0.00002, probe + " visibly changes real shaded pixels")
		probe_frame.save_png(output + "/" + probe + ".png")
		material.set_shader_parameter("grass_normal_strength", 0.58)
		material.set_shader_parameter("rock_normal_strength", 0.72)
		material.set_shader_parameter("roughness_scale", 1.0)

func _image_delta(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size(): return 0.0
	var difference := 0.0
	var count := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var aa := a.get_pixel(x,y)
			var bb := b.get_pixel(x,y)
			difference += (absf(aa.r-bb.r) + absf(aa.g-bb.g) + absf(aa.b-bb.b)) / 3.0
			count += 1
	return difference / maxf(count, 1)

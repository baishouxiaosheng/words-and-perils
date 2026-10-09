extends SceneTree
## Low-memory native component proof, NOT full-coast or GTX1660Ti acceptance.
const Quality = preload("res://view/render_quality.gd")
const Trees = preload("res://view/ecology_preview/vegetation_meshes.gd")
const Tokens = preload("res://view/chess_tokens.gd")
const OUT = "res://artifacts/render_quality_20261003/components"
var viewport: SubViewport
var holder: SubViewportContainer
var water: ShaderMaterial
var failures := 0
var report := {"scope": "native_component_only_no_full_coast", "target_gpu_tested": false, "captures": []}
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in range(8): await process_frame
func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = color
	return m
func plane(parent: Node3D, size_: Vector2, position_: Vector3, mat: Material) -> void:
	var mesh := PlaneMesh.new(); mesh.size = size_
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = position_; parent.add_child(mi)
func shot(tag: String, index: int, filtered: bool) -> void:
	Quality.apply(viewport, root, holder, index)
	water.set_shader_parameter("ripple_antialiasing", filtered)
	await settle(); await RenderingServer.frame_post_draw
	var image_: Image = root.get_texture().get_image()
	if image_.get_size() != Vector2i(1280,720):
		failures += 1; printerr("Native dimensions wrong: ", image_.get_size()); return
	var path := OUT + "/" + tag + ".png"
	if image_.save_png(path) != OK:
		failures += 1; printerr("Could not save native PNG: ", path); return
	report.captures.append({"tag": tag, "native_pixels": [1280,720], "msaa_requested": viewport.msaa_3d, "ripple_filter": filtered, "png_sha256": FileAccess.get_sha256(path), "resampled": false})
	var f := FileAccess.open(OUT + "/comparison.json", FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
func run() -> void:
	if DisplayServer.get_name() == "headless": printerr("Native component capture needs the actual Compatibility renderer"); quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	holder = SubViewportContainer.new(); holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); holder.stretch = true; root.add_child(holder)
	viewport = SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; holder.add_child(viewport)
	var world := Node3D.new(); viewport.add_child(world)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color("203038"); env.environment = e; world.add_child(env)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 11.5; world.add_child(camera); camera.position = Vector3(5,8,12); camera.look_at(Vector3(0,0.6,0)); camera.current = true
	plane(world,Vector2(13,10),Vector3(0,-.02,0),material(Color("a8c95f")))
	water = ShaderMaterial.new(); water.shader = load("res://view/integrated_ecology_world/tabs_style/water.gdshader")
	plane(world,Vector2(6,10),Vector3(4,0,0),water)
	var foliage := ShaderMaterial.new(); foliage.shader = load("res://view/integrated_ecology_world/tabs_style/vegetation.gdshader")
	for i in range(6):
		var tree := MeshInstance3D.new(); tree.mesh = Trees.make("temperate" if i % 2 == 0 else "tropical"); tree.material_override = foliage
		tree.position = Vector3(-4.3 + float(i % 3)*1.7,0,-2.4+float(i/3)*2.1); tree.scale = Vector3(.62,2.2+float(i%2)*.3,.62); world.add_child(tree)
	var token := Tokens.build("actor_player",{}); world.add_child(token); token.position = Vector3(-.7,0,1.6); token.scale = Vector3.ONE*1.35
	for mi in token.find_children("*","MeshInstance3D",true,false):
		var source: Material = mi.get_active_material(0)
		var styled := ShaderMaterial.new(); styled.shader = load("res://view/integrated_ecology_world/tabs_style/prop.gdshader")
		styled.set_shader_parameter("base_color",source.albedo_color if source is StandardMaterial3D else Color("cfc6b2")); mi.material_override = styled
	# Thin solid diagonals show coverage separately from shader detail.
	for i in range(4):
		var pole := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size = Vector3(.025,2.2,.025); pole.mesh = shape; pole.material_override = material(Color("fff7d9")); pole.position = Vector3(.0+float(i)*.22,1.1,-1.3); pole.rotation_degrees.z = -27.0; world.add_child(pole)
	report.merge({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "camera": str(camera.global_transform), "camera_size": camera.size, "actual_project_components": ["vegetation_meshes.gd", "chess_tokens.gd", "tabs_style/vegetation.gdshader", "tabs_style/prop.gdshader", "tabs_style/water.gdshader"], "static_memory_before_capture": Performance.get_monitor(Performance.MEMORY_STATIC), "not_a_performance_benchmark": true})
	await shot("01_off",Quality.Preset.LOW_LOAD,false)
	await shot("02_2x",Quality.Preset.BALANCED,false)
	await shot("03_4x",Quality.Preset.FINE,false)
	await shot("04_4x_filtered_water",Quality.Preset.FINE,true)
	report["failures"] = failures
	var final_report := FileAccess.open(OUT + "/comparison.json",FileAccess.WRITE); final_report.store_string(JSON.stringify(report,"\t")); final_report.close()
	print("AA COMPONENT NATIVE COMPLETE ",JSON.stringify(report))
	world.queue_free(); await process_frame; quit(0 if failures == 0 and report.captures.size() == 4 else 1)

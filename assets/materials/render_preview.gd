extends SceneTree
## Optional real-renderer material swatch. Never passes under --headless.
## Actual integrated board/UI captures remain the final visual acceptance source.
const Materials=preload("res://view/miniature_materials.gd")
func _initialize() -> void:
	call_deferred("render")
func add_mesh(parent:Node3D,mesh:Mesh,material:Material,pos:Vector3) -> MeshInstance3D:
	var obj=MeshInstance3D.new();obj.mesh=mesh;obj.material_override=material;obj.position=pos;parent.add_child(obj);return obj
func render() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("Material visual check requires an actual renderer/display");quit(2);return
	root.size=Vector2i(1400,900)
	root.msaa_3d=Viewport.MSAA_4X
	var scene=Node3D.new();root.add_child(scene)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("18252a")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("98b6cb");env.ambient_light_energy=.42
	env.ssao_enabled=true;env.ssao_radius=.4;env.ssao_intensity=.6
	var world=WorldEnvironment.new();world.environment=env;scene.add_child(world)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-34,0);sun.light_color=Color("ffe1aa");sun.light_energy=1.1;sun.shadow_enabled=true;scene.add_child(sun)
	var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-24,130,0);fill.light_color=Color("8bb7d3");fill.light_energy=.27;scene.add_child(fill)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8.7;camera.position=Vector3(6,8,10);scene.add_child(camera);camera.look_at(Vector3(0,.4,0));camera.current=true
	var floor=BoxMesh.new();floor.size=Vector3(9,.12,4.6)
	var ground=Materials.ground_material().duplicate();ground.vertex_color_use_as_albedo=false;ground.albedo_color=Color("849965")
	add_mesh(scene,floor,ground,Vector3(0,-.1,0))
	var poses=[-3.0,-1.5,0.0,1.5,3.0]
	var mats=[Materials.stone_material(),Materials.wood_material(),Materials.token_stone_material(Color("e7ddc4")),Materials.token_stone_material(Color("30464b"),.48),Materials.metal_material(Color("b69564"),.8,.37)]
	for i in range(mats.size()):
		var mesh=CylinderMesh.new();mesh.top_radius=.42;mesh.bottom_radius=.48;mesh.height=1.2;mesh.radial_segments=8
		add_mesh(scene,mesh,mats[i],Vector3(poses[i],.56,0))
	var layer=CanvasLayer.new();root.add_child(layer)
	for i in range(3):
		var panel=Panel.new();panel.position=Vector2(40+i*440,690);panel.size=Vector2(410,170)
		panel.add_theme_stylebox_override("panel",Materials.frame_style([Color("e9e1ce"),Color("243a3c"),Color("41514b")][i],Color("a48b5b"),16.0,["parchment","dark","pressed"][i]));layer.add_child(panel)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var output=root.get_texture().get_image();output.save_png("res://assets/materials/material_render_preview.png")
	print("ACTUAL MATERIAL RENDER ",DisplayServer.get_name()," ",RenderingServer.get_video_adapter_name()," ",output.get_size())
	quit(0)

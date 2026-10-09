extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const Geometry=preload("res://view/generated_v3_runtime/geometry.gd")
const Nav=preload("res://view/generated_v3_runtime/navigation.gd")
const Source=preload("res://view/generated_v3_adventure/source.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const Village=preload("res://view/generated_v3_settlement/settlement_view.gd")
var checks=0
var failures: Array=[]
var rows: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func _initialize() -> void:call_deferred("run")
func write_json(name: String,value: Variant) -> void:
	var f=FileAccess.open("res://artifacts/generated_v3_placement/"+name,FileAccess.WRITE);f.store_string(C.bytes(value));f.close()
func run() -> void:
	root.size=Vector2i(1280,900);root.msaa_3d=Viewport.MSAA_2X
	for recipe in G.RECIPES:
		var generated=G.generate(726381,12,recipe);check(generated.ok,recipe+" generate")
		if not generated.ok:continue
		var built=Geometry.build(generated.source);check(built.ok,recipe+" native ground")
		if not built.ok:continue
		var nav=Nav.new();check(nav.build(generated.source,built).ok,recipe+" native navigation")
		var spawn=Source.choose_spawn(generated.source,nav);check(spawn.ok,recipe+" source spawn")
		if not spawn.ok:continue
		var placement=Planner.build(generated.source,built,nav,spawn.hex);check(placement.ok,recipe+" placement")
		if not placement.ok:continue
		var original=C.bytes(placement.manifest);var source_original=C.bytes(generated.source)
		var world=Node3D.new();root.add_child(world);Geometry.install_lighting(world);world.add_child(Geometry.create_view(built))
		var village=Village.new();world.add_child(village);var installed=village.configure(placement)
		check(installed.ok,recipe+" approved physical village render")
		if not installed.ok:write_json(recipe+"_render_failure.json",installed);world.queue_free();await process_frame;continue
		check(village.selection_nodes().size()==5,recipe+" five source-bound selection identities")
		var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=200;camera.current=true;world.add_child(camera)
		var hud=CanvasLayer.new();world.add_child(hud)
		var label=Label.new();label.position=Vector2(18,14);label.add_theme_font_size_override("font_size",18);label.add_theme_color_override("font_color",Color("183342"));hud.add_child(label)
		var center=nav.cell_center(placement.manifest.settlements[0].center_hex);var entry=nav.cell_center(placement.manifest.settlements[0].entry_hex)
		var focus=center.lerp(entry,.20)+Vector3.UP*.12
		for view in ["overview","normal_12","closest_7_5"]:
			if view=="overview":camera.size=41.6;camera.position=Vector3(0,26,32);camera.look_at(Vector3.ZERO)
			else:camera.size=12.0 if view=="normal_12" else 7.5;camera.position=focus+Vector3(0,14,18);camera.look_at(focus)
			label.text="V3 · "+recipe+" · 1-hex village / 3 original buildings / source-bound dry entry"
			village.update_lod(camera);await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var picture=root.get_texture().get_image();var path="res://artifacts/generated_v3_placement/"+recipe+"__"+view+".png"
			check(picture.save_png(path)==OK,"capture "+path)
			var report=village.report();rows.append({"recipe":recipe,"view":view,"width":picture.get_width(),"height":picture.get_height(),"camera_transform":str(camera.transform),"camera_size":camera.size,"source_hash":generated.source.content_hash,"geometry_hash":built.geometry_hash,"placement_hash":placement.placement_hash,"site":placement.manifest.settlements[0].center_hex,"entry":placement.manifest.settlements[0].entry_hex,"render_report":report})
			check(report.configured and report.errors.is_empty(),recipe+" configured clear "+view)
		check(C.bytes(generated.source)==source_original and C.bytes(placement.manifest)==original,recipe+" render preserves source and placement")
		write_json(recipe+"_render_report.json",village.report())
		world.queue_free();await process_frame;await process_frame
	write_json("capture_report.json",{"checks":checks,"failures":failures,"captures":rows})
	print("V3 VILLAGE VISUAL ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)

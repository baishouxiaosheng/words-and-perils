extends SceneTree
const Main=preload("res://main.tscn")
const Contract=preload("res://core/world_generation_contract.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Quality=preload("res://view/render_quality.gd")
const OUT="res://tests/generated_adventure/visual_style/"
var checks:=0
var failures: Array[String]=[]
var captures: Array=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,what: String) -> void:
	checks+=1
	if not value:failures.append(what);printerr("FAIL "+what)
func mesh_signature(board: Node3D) -> Dictionary:
	var entries:=[];var vertices:=0
	for mi in board.terrain_root.find_children("*","MeshInstance3D",true,false):
		if mi.is_queued_for_deletion() or mi.mesh==null:continue
		var hashes:=[]
		for i in range(mi.mesh.get_surface_count()):
			var a: Array=mi.mesh.surface_get_arrays(i)
			vertices+=a[Mesh.ARRAY_VERTEX].size()
			var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
			context.update(var_to_bytes(a));hashes.append(context.finish().hex_encode())
		entries.append({"path":str(board.terrain_root.get_path_to(mi)),"mesh_id":str(mi.mesh.get_instance_id()),"transform":str(mi.transform),"arrays_sha256":hashes})
	return {"digest":C.digest(entries),"vertices_including_whole_and_chunks":vertices,"meshes":entries.size()}
func stable_wait() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func capture(app: Node,tag: String) -> void:
	await stable_wait()
	var image_: Image=root.get_texture().get_image()
	image_.save_png(OUT+tag+".png")
	captures.append({"name":tag,"root_pixels":[image_.get_width(),image_.get_height()],"world_pixels":[app.viewport.size.x,app.viewport.size.y],"world_msaa":app.viewport.msaa_3d,"camera_transform":str(app.board.camera.global_transform),"projection":app.board.camera.projection,"camera_size":app.board.camera.size,"camera_fov":app.board.camera.fov,"labels":app.board.get_node("WorldLabelLayout").report()})
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("NATIVE DISPLAY REQUIRED");quit(2);return
	root.size=Vector2i(1180,812)
	var app=Main.instantiate();app.startup_legacy=true;root.add_child(app)
	await process_frame;await process_frame
	var envelope: Dictionary = Contract.generate(726381,"coast_exploration",12)
	var source: Dictionary = envelope.source
	var prepared: Dictionary=app.prepare_world_candidate(source)
	check(prepared.ok and app.commit_world_candidate(prepared.candidate).ok,"exact existing r12 source admitted as preview")
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	await app.start_generated_from_preview();await process_frame
	check(app.generated_mode,"explicit generated mode only")
	var board: Node3D=app.board
	var profile: Node=board.visual_profile
	check(profile!=null and profile.enabled,"generated-only profile enabled")
	var original:=mesh_signature(board)
	check(original.digest.length()==64,"geometry fingerprint is a real nonempty SHA-256")
	var nav_hash: String=C.digest({"allowed":app.playtest.source.navigation.allowed,"support":app.playtest.source.navigation.support_heights,"identity":app.playtest.source.identity})
	var state_hash: String=C.digest(app.playtest.save_data())
	var heights:=[]
	for cell in source.hexes.values():
		var p: Vector3=board.hex_pos(Vector2i(cell.q,cell.r));heights.append([board.terrain_field.land_height(p),board.terrain_field.water_height(p)])
	var height_hash: String=C.digest(heights)
	for preset in [Quality.Preset.LOW_LOAD,Quality.Preset.FINE,Quality.Preset.BALANCED]:
		var settings: Dictionary=Quality.apply(app.viewport,root,app.board_container,preset)
		check(app.viewport.msaa_3d==settings.msaa and app.viewport.scaling_3d_scale==1.0 and app.viewport.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED and not app.viewport.use_taa,"actual world viewport AA preset "+str(preset))
	for scope in ["focus","overview"]:
		if scope=="focus":board.focus_player()
		else:board.reset_camera();app.set_map_dialogue_hidden(true)
		var camera: Transform3D=board.camera.global_transform;var camera_size: float=board.camera.size
		for enabled in [false,true]:
			profile.set_enabled(enabled)
			await capture(app,"r12_"+scope+("_after" if enabled else "_before"))
			check(board.camera.global_transform==camera and board.camera.size==camera_size,"exact camera preserved in "+scope+" "+str(enabled))
			check(mesh_signature(board)==original,"same mesh resources, coordinates, normals, indices and transforms in "+scope+" "+str(enabled))
			for water in board.water_layers:
				if enabled:check(water.material_override==profile.materials.water,"whole/chunk water uses matte material")
		check(board.get_node("WorldLabelLayout").report().get("overlap_count",-1)==0,"labels avoid overlap "+scope)
	check(C.digest(app.playtest.save_data())==state_hash,"visual toggles preserve exact gameplay save, RNG and pending state")
	# Existing three-action UI remains usable under the profile.
	var state: Dictionary=app.playtest.state_copy();var actor: Dictionary=state.actors.actor_player
	var key: String=app.playtest.source.navigation.allowed["%d,%d"%actor.hex][0]
	var target: Dictionary=state.hexes[key]
	app.on_hex_selected(Vector2i(target.q,target.r));app.fill_generated_sample("move");app.submit_action();app.playtest_fixture();app.advance_playtest()
	check(app.playtest.phase()=="rolled","matte board still locks assessed dry movement")
	app.advance_playtest();app.advance_playtest()
	while board.presentation.actors.actor_player.moving:await process_frame
	check(app.playtest.state_copy().actors.actor_player.hex==[target.q,target.r],"matte board commits exact dry movement")
	check(profile.enabled and board.water_layers[0].material_override==profile.materials.water,"refresh after action preserves visual profile")
	check(C.digest({"allowed":app.playtest.source.navigation.allowed,"support":app.playtest.source.navigation.support_heights,"identity":app.playtest.source.identity})==nav_hash,"navigation, support and source identity unchanged")
	var after_heights:=[]
	for cell in source.hexes.values():
		var p: Vector3=board.hex_pos(Vector2i(cell.q,cell.r));after_heights.append([board.terrain_field.land_height(p),board.terrain_field.water_height(p)])
	check(C.digest(after_heights)==height_hash,"all r12 anchor land/water heights unchanged")
	check(mesh_signature(board)==original,"action refresh preserves geometry too")
	root.size=Vector2i(900,640);app.set_map_dialogue_hidden(false);board.focus_player();await capture(app,"r12_narrow_after")
	check(app.viewport.size.x==root.size.x and app.viewport.size.y==root.size.y,"responsive world viewport matches real resized HUD")
	var report:={"checks":checks,"failures":failures,"captures":captures,"mesh":original,"navigation_and_support_sha256":nav_hash,"rendered_anchor_heights_sha256":height_hash,"state_before_actions_sha256":state_hash,"profile":profile.report(),"display":DisplayServer.get_name(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"target_hardware_tested":false}
	var file:=FileAccess.open(OUT+"report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("GENERATED_MATTE_REPORT ",JSON.stringify(report));print("GENERATED MATTE ",checks-failures.size(),"/",checks)
	app.free();quit(0 if failures.is_empty() else 1)

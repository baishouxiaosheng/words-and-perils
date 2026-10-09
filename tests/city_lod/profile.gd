extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content=preload("res://view/playable_build/settlement_content.gd")
var app
var out:=OS.get_environment("FOGBANK_CITY_OUT")
var report:Dictionary={"checks":[],"frames":[],"target_gpu_tested":false}
var failures:=0
func _initialize()->void:run.call_deferred()
func frames(n:=10)->void:
	for _i in range(n):await process_frame
func check(ok:bool,label:String)->void:
	report.checks.append({"passed":ok,"name":label})
	if not ok:failures+=1;printerr("CITY_FAIL ",label)
func save()->void:
	report["failures"]=failures
	var f:=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
func walk(node:Node,r:Dictionary)->void:
	if node is Light3D:r.lights.append({"path":str(node.get_path()),"visible":node.is_visible_in_tree(),"shadow_enabled":node.shadow_enabled,"energy":node.light_energy})
	if node is WorldEnvironment:r.environments.append({"path":str(node.get_path()),"ssao":node.environment.ssao_enabled,"ssil":node.environment.ssil_enabled,"sdfgi":node.environment.sdfgi_enabled})
	for child in node.get_children():walk(child,r)
func city_inventory()->Dictionary:
	var r:Dictionary={"mesh_nodes":0,"mesh_triangles":0,"casters_flag_on":0,"material_ids":{},"mesh_ids":{},"kit_meshes":[],"structural_meshes":[]}
	for node in app.board.settlement_view.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null:continue
		r.mesh_nodes+=1;r.mesh_triangles+=node.mesh.get_faces().size()/3
		if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:r.casters_flag_on+=1
		r.mesh_ids[node.mesh.get_instance_id()]=true
		if node.material_override!=null:r.material_ids[node.material_override.get_instance_id()]=true
		var item:Dictionary={"path":str(node.get_path()),"triangles":node.mesh.get_faces().size()/3,"transform":str(node.global_transform),"aabb":str(node.mesh.get_aabb()),"shadow_enum":node.cast_shadow}
		if node.get_meta("city_lod","")!="":item["lod"]=node.get_meta("city_lod")
		if node.get_parent().has_meta("source_asset") or node.has_meta("source_asset"):r.kit_meshes.append(item)
		else:r.structural_meshes.append(item)
	r["unique_materials"]=r.material_ids.size();r.erase("material_ids");r["unique_meshes"]=r.mesh_ids.size();r.erase("mesh_ids")
	return r
func camera(size_:float)->void:
	var v=app.board.world_view
	v.overview=false;v.target=app.board._position(Content.manifest().center_hex)+Vector3(0,.45,0);v.distance=14;v.pitch=.72;v.yaw=.2;app.board.camera.size=size_;v._update_camera()
func measure(label:String)->void:
	await frames(24)
	var times:Array[float]=[];var calls:Array[float]=[];var primitives:Array[float]=[];var shadow_calls:Array[float]=[]
	var start:=Time.get_ticks_usec();var previous:=start
	while Time.get_ticks_usec()-start<4000000:
		await process_frame
		var now:=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		calls.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		primitives.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		shadow_calls.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	times.sort()
	var r:Dictionary={"label":label,"sample_frames":times.size(),"mean_ms":times.reduce(func(a,b):return a+b,0.0)/times.size(),"p95_ms":times[int(times.size()*.95)],"draw_calls":calls.reduce(func(a,b):return a+b,0.0)/calls.size(),"primitives":primitives.reduce(func(a,b):return a+b,0.0)/primitives.size(),"shadow_draw_calls":shadow_calls.reduce(func(a,b):return a+b,0.0)/shadow_calls.size(),"camera_transform":str(app.board.camera.global_transform),"camera_size":app.board.camera.size,"city":city_inventory()}
	if app.board.settlement_view.has_method("lod_report"):r["lod_report"]=app.board.settlement_view.lod_report()
	report.frames.append(r);print("CITY_FRAME ",label," ",r.mean_ms,"ms draws=",r.draw_calls," primitives=",r.primitives," shadows=",r.shadow_draw_calls);save()
	await RenderingServer.frame_post_draw
	app.viewport.get_texture().get_image().save_png(out+"/"+label+".png")
func run()->void:
	if out.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(out);OS.set_environment("FOGBANK_QA_WINDOWED","1")
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var start:=Time.get_ticks_usec();app=load("res://main.tscn").instantiate();root.add_child(app);await frames(24)
	report.merge({"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"effective_vsync_verified":false,"startup_through_settled_ms":(Time.get_ticks_usec()-start)/1000.0,"lights":[],"environments":[]})
	walk(app,report)
	check(app.coast_mode and Content.active(app.playtest.state_copy()),"actual new coast with source-bound 1/1/3 settlements")
	check(app.viewport.size==Vector2i(1280,720),"native 1280x720 world raster")
	var before:=C.digest(app.playtest.engine.save_data())
	camera(6.0);await measure("normal")
	camera(4.0);await measure("closest")
	camera(16.0);await measure("distant_city")
	app.toggle_overview();await measure("overview")
	camera(6.0);await frames(8)
	if app.board.settlement_view.has_method("lod_report"):report["restored_normal_lod"]=app.board.settlement_view.lod_report()
	check(C.digest(app.playtest.engine.save_data())==before,"all camera and LOD operations preserve authority bytes")
	report["settlement_report"]=app.board.settlement_view.report()
	report["static_bytes"]=Performance.get_monitor(Performance.MEMORY_STATIC)
	save();app.queue_free();await frames(4);print("CITY_PROFILE_COMPLETE failures=",failures);quit(0 if failures==0 else 1)

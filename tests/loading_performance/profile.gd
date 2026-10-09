extends SceneTree
const Trace = preload("res://tests/loading_performance/trace.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Contract = preload("res://core/world_generation_contract.gd")
var app
var report: Dictionary = {"checks":[],"frames":[],"snapshots":[],"target_gpu_tested":false}
var out := ""
var scenario := "coast"
var failures := 0
func _initialize() -> void:
	out=OS.get_environment("FOGBANK_PERF_OUT")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):scenario=arg.trim_prefix("--scenario=")
	run.call_deferred()
func check(ok: bool,label_:String)->void:
	report.checks.append({"passed":ok,"name":label_})
	if not ok: failures+=1;printerr("PERF_FAIL ",label_)
func frames(count:=12)->void:
	for _i in range(count):await process_frame
func save()->void:
	report["stages"]=Trace.rows;report["failures"]=failures
	var f:=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
func snapshot(label_:String)->void:
	var row:Dictionary={"label":label_,"time_us":Time.get_ticks_usec(),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_memory_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)}
	row["native_proc_status"]=FileAccess.get_file_as_string("/proc/self/status")
	report.snapshots.append(row);print("LOAD_SNAPSHOT ",JSON.stringify(row));save()
func measure(label_:String)->void:
	await frames(20)
	var times:Array[float]=[];var process_times:Array[float]=[];var draw_calls:Array[float]=[];var primitives:Array[float]=[];var objects:Array[float]=[]
	var start:=Time.get_ticks_usec();var previous:=start
	while Time.get_ticks_usec()-start<4000000:
		await process_frame
		var now:=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		draw_calls.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		primitives.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		objects.append(app.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	times.sort()
	var row:Dictionary={"label":label_,"frames":times.size(),"mean_ms":times.reduce(func(a,b):return a+b,0.0)/times.size(),"p50_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"engine_process_ms_mean":process_times.reduce(func(a,b):return a+b,0.0)/process_times.size(),"draw_calls_mean":draw_calls.reduce(func(a,b):return a+b,0.0)/draw_calls.size(),"primitives_mean":primitives.reduce(func(a,b):return a+b,0.0)/primitives.size(),"draw_objects_mean":objects.reduce(func(a,b):return a+b,0.0)/objects.size(),"camera_transform":str(app.board.camera.global_transform),"camera_size":app.board.camera.size,"viewport":str(app.viewport.size),"msaa_enum":app.viewport.msaa_3d}
	report.frames.append(row);print("LOAD_FRAMES ",JSON.stringify(row));save()
func inventory(node:Node)->Dictionary:
	var result:Dictionary={"nodes":0,"mesh_instances":0,"visible_mesh_instances":0,"multimesh_nodes":0,"multimesh_instances":0,"unique_meshes":{},"unique_materials":{},"groups":[]}
	collect(node,result)
	result["unique_mesh_count"]=result.unique_meshes.size();result.erase("unique_meshes")
	result["unique_material_count"]=result.unique_materials.size();result.erase("unique_materials")
	return result
func collect(node:Node,result:Dictionary)->void:
	result.nodes+=1
	if node is MeshInstance3D:
		result.mesh_instances+=1
		if node.is_visible_in_tree():result.visible_mesh_instances+=1
		if node.mesh!=null:result.unique_meshes[node.mesh.get_instance_id()]=true
		if node.material_override!=null:result.unique_materials[node.material_override.get_instance_id()]=true
	if node is MultiMeshInstance3D:
		result.multimesh_nodes+=1
		if node.multimesh!=null:result.multimesh_instances+=node.multimesh.instance_count
	if node is Node3D and node.get_child_count()>10:
		result.groups.append({"path":str(node.get_path()),"children":node.get_child_count(),"visible":node.is_visible_in_tree()})
	for child in node.get_children():collect(child,result)
func run()->void:
	if out.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("FOGBANK_QA_WINDOWED","1")
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	Engine.max_fps=0
	if DisplayServer.get_name()!="headless":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	report.merge({"scenario":scenario,"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"engine":Engine.get_version_info(),"resolution":[1280,720],"effective_vsync_verified":false,"process_id":OS.get_process_id()})
	snapshot("before_scene_load")
	var t:=Time.get_ticks_usec();var mem:=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var packed=load("res://main.tscn");Trace.record("harness:load_main_scene",t,mem)
	t=Time.get_ticks_usec();mem=int(Performance.get_monitor(Performance.MEMORY_STATIC));app=packed.instantiate();Trace.record("harness:instantiate",t,mem)
	if scenario=="generated":app.startup_legacy=true
	t=Time.get_ticks_usec();mem=int(Performance.get_monitor(Performance.MEMORY_STATIC));root.add_child(app);Trace.record("harness:add_child_ready_sync",t,mem)
	await frames(24)
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	Trace.record("harness:first_settled_scene",t,mem)
	if scenario=="coast":
		check(app.coast_mode and app.board.tiles.size()==1801 and app.board.load_error.is_empty(),"full actual 1801-cell coast")
		check(app.board.world_view.natural_shorelines.visible and app.board.world_view.faceted_mountains.visible,"current shore and mountains active")
		report["world_metrics"]=app.board.world_view.metrics()
	else:
		t=Time.get_ticks_usec();mem=int(Performance.get_monitor(Performance.MEMORY_STATIC));var envelope:Dictionary=Contract.generate("726381","wide_coast",24);Trace.record("harness:generate_r24",t,mem)
		check(envelope.ok,"fixed r24 seed valid")
		var candidate:RefCounted=app.prepare_inventory_adventure(envelope)
		check(candidate.ready().ok,"fixed r24 inventory adventure admitted")
		app.generated_adventure=candidate
		t=Time.get_ticks_usec();mem=int(Performance.get_monitor(Performance.MEMORY_STATIC));app._switch_mode("generated");Trace.record("harness:generated_switch",t,mem)
		await frames(24)
		check(app.generated_mode and app.board.tiles.size()==1801 and app.board.load_error.is_empty(),"actual r24 generated renderer")
		report["source_hash"]=envelope.source.content_hash
		check(app.playtest.state_copy().actors.actor_player.inventory==["item_travel_bundle"],"one opt-in starting item")
		envelope.clear()
	check(app.viewport.size==Vector2i(1280,720),"exact 1:1 native raster")
	snapshot("ready_"+scenario)
	report["scene_inventory"]=inventory(app.board)
	var before:=C.digest(app.playtest.engine.save_data())
	await measure("focus")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out+"/focus.png")
	app.toggle_overview();await measure("overview")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out+"/overview.png")
	check(C.digest(app.playtest.engine.save_data())==before,"profiling and camera leave authority byte-identical")
	check(report.frames.size()==2,"both camera samples completed")
	snapshot("after_measurement")
	app.queue_free();await frames(4);packed=null;app=null
	snapshot("after_scene_free")
	save();print("LOADING_PERF_COMPLETE failures=",failures);quit(0 if failures==0 else 1)

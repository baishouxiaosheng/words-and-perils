extends SceneTree
## Bounded repeated lifecycle sample. No input, action, screenshots or video.
## Streams rows to disk instead of retaining per-round dictionaries in memory.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Custody=preload("res://view/generated_v3_river_entry/host_custody.gd")
const OUT="res://artifacts/generated_v3_river_entry/residency/"
const ROUNDS=20
const SETTLE_FRAMES=30
var app:Control
var stream:FileAccess
var failures:Array=[]
var host_hash:=""
var ui_hash:=""
func _initialize()->void:run.call_deferred()
func settle()->void:
	for _i in range(SETTLE_FRAMES):await process_frame
	await create_timer(0.25).timeout
func check(ok:bool,name_:String)->bool:
	if not ok:failures.append(name_);printerr("RIVER_RESIDENCY_FAIL ",name_)
	return ok
func refs_for(entry:Node)->Dictionary:
	var source:RefCounted=entry.session.river.source
	return {"view":weakref(entry.view),"adapter":weakref(entry.session.river),"source":weakref(source),"navigation":weakref(source.navigation),"ground_mesh":weakref(source.renderer_bundle.ground_mesh),"water_mesh":weakref(source.renderer_bundle.water_mesh),"ground_material":weakref(source.renderer_bundle.ground_material),"water_material":weakref(source.renderer_bundle.water_material)}
func live_names(refs:Dictionary)->Array:
	var names:Array=[]
	for key in refs:
		if refs[key].get_ref()!=null:names.append(key)
	return names
func sample(kind:String,round_:int,refs:Dictionary={})->void:
	var parked_bytes:int=0
	var parked_hash:String=""
	if app.river_entry_controller!=null:
		var parked:Dictionary=app.river_entry_controller.session._parked_river_save
		var serialized:String=C.bytes(parked)
		parked_bytes=serialized.to_utf8_buffer().size();parked_hash=serialized.sha256_text()
	var output:Array=[]
	var code:int=OS.execute("cat",PackedStringArray(["/proc/"+str(OS.get_process_id())+"/status"]),output)
	var rss_kib:int=-1;var hwm_kib:int=-1
	if code==0 and not output.is_empty():
		for line in str(output[0]).split("\n"):
			if line.begins_with("VmRSS:"):rss_kib=int(line.split(":")[1].strip_edges().split(" ",false)[0])
			if line.begins_with("VmHWM:"):hwm_kib=int(line.split(":")[1].strip_edges().split(" ",false)[0])
	var row:Dictionary={"kind":kind,"round":round_,"ticks_ms":Time.get_ticks_msec(),"static_bytes":OS.get_static_memory_usage(),"peak_static_bytes":OS.get_static_memory_peak_usage(),"rss_kib":rss_kib,"hwm_kib":hwm_kib,"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"parked_json_bytes":parked_bytes,"parked_json_sha256":parked_hash,"live_guest_refs":live_names(refs),"settle_frames":SETTLE_FRAMES,"settle_seconds":0.25}
	stream.store_line(C.bytes(row));stream.flush()
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);stream=FileAccess.open(OUT+"samples.jsonl",FileAccess.WRITE)
	app=Main.instantiate();root.add_child(app);await settle()
	var state:Dictionary=app.playtest.state_copy()
	if not check(app.coast_mode and app.board.tiles.size()==1801 and state.world_id=="natural_coast_shore_v03_adventure" and state.generated_world.bundle_id=="natural-shore-v03-2f6a1a215a0d44a374f01c4a","exact full1801 coast before repeated entry"):finish();return
	var custody:Dictionary=Custody.capture(app.playtest)
	if not check(custody.ok and not C.bytes(custody.snapshot).is_empty() and not C.bytes(app._river_entry_ui_snapshot()).is_empty(),"complete nonempty custody witnesses"):finish();return
	host_hash=C.digest(custody.snapshot);ui_hash=C.digest(app._river_entry_ui_snapshot())
	state={};custody={}
	for round_ in range(5):await settle();sample("idle_control",round_)
	for round_ in range(ROUNDS):
		app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID);await settle()
		var entry:Node=app.river_entry_controller
		if not check(entry!=null and entry.session.is_open() and entry.view!=null,"round%d admitted"%round_):finish();return
		var refs:Dictionary=refs_for(entry)
		sample("entered",round_,refs)
		if not check(entry.close().ok,"round%d explicit no-action return"%round_):finish();return
		await settle()
		check(live_names(refs).is_empty(),"round%d all eight guest ownership weakrefs expired"%round_)
		check(C.digest(Custody.capture(app.playtest).get("snapshot"))==host_hash and C.digest(app._river_entry_ui_snapshot())==ui_hash,"round%d host custody exact"%round_)
		sample("returned",round_,refs)
		refs={}
		if not failures.is_empty():finish();return
	await settle();sample("final_idle",ROUNDS)
	finish()
func finish()->void:
	if stream!=null:stream.close()
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"failures":failures,"rounds_requested":ROUNDS,"pid":OS.get_process_id(),"scope":"bounded full1801 repeated no-action entry/return and fixed settling samples; no claim of zero residue or indefinite stability","host_hash":host_hash,"ui_hash":ui_hash},"\t",true,true))
	print("RIVER_RESIDENCY ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)

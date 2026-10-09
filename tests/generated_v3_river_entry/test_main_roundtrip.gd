extends SceneTree
## Run only after explicit serial slot release, through the original native guard.
## Supply one proven, alive v24-compatible equipment save after --. No fixture
## regeneration, RNG reselection, import/editor run or canonical write is allowed.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const MainScene=preload("res://main.tscn")
const Equipment=preload("res://view/generated_v3_equipment/adapter.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const HostCustody=preload("res://view/generated_v3_river_entry/host_custody.gd")
var checks:=0
var failures:Array=[]
var report:Dictionary={}
var completed:=false
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->bool:
	checks+=1
	if not value:failures.append(label);printerr("RIVER_V24_FAIL ",label)
	return value
func frames(count:int=4)->void:
	for _i in range(count):await process_frame
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if not check(args.size()==1 and FileAccess.file_exists(args[0]),"one explicit proven equipment input supplied"):finish();return
	var original_file_hash:=FileAccess.get_sha256(args[0])
	var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var equipment:=Equipment.new();var loaded:Dictionary=equipment.load_data(saved)
	report["equipment_load"]={"ok":loaded.get("ok",false),"code":loaded.get("code",""),"errors":loaded.get("errors",[]),"roundtrip_equal":C.bytes(equipment.save_data())==C.bytes(saved)}
	if not check(loaded.ok and report.equipment_load.roundtrip_equal,"current equipment history loads exactly "+str(report.equipment_load)):finish();return
	if not check(equipment.state_copy().actors.actor_player.health.current>0,"fixture traveler is alive"):finish();return
	var app:Control=MainScene.instantiate();root.add_child(app);await frames()
	check(app.river_entry_controller==null,"default startup has no experimental session/controller")
	if not verify_default_world(app):app.queue_free();finish();return
	var coast_visit_ok:bool=await verify_full_coast_visit(app)
	if not coast_visit_ok:app.queue_free();finish();return
	app._switch_mode_to("generated_v3_equipment",equipment);await frames()
	if not check(app.playtest==equipment and app.generated_v3_equipment_mode,"actual Main installs the proven equipment adapter"):app.queue_free();finish();return
	var actor:Dictionary=equipment.state_copy().actors.actor_player
	# The current UI exposes map-tile focus; equipped weapons are inventory
	# records, not map silhouettes with a hex. Preserve equipment via full save.
	var focus:Dictionary=equipment.tile_reference(actor.hex)
	app._apply_focus(focus)
	if not check(not app.selected_focus.is_empty() and C.bytes(app.selected_focus)==C.bytes(focus) and app.selected==Vector2i(actor.hex[0],actor.hex[1]),"actual supported map focus is installed before custody"):app.queue_free();finish();return
	app.set_player_intent("保留这段主旅程草稿")
	# Actual pending intent is denied entry without auto-cancel or state loss.
	check(equipment.begin_intent("观察当前地点",{}).ok,"host pending intention created through normal API")
	var pending:=C.bytes(equipment.save_data())
	app.open_river_experiment()
	check(C.bytes(equipment.save_data())==pending and equipment.phase()=="awaiting_assessment","busy entry leaves actual pending history exact")
	check(equipment.cancel().ok,"host intent cancelled explicitly by test")
	var host_bytes:=C.bytes(equipment.save_data());var focus_snapshot:Dictionary=app._river_entry_ui_snapshot()
	if not check(C.safe(focus_snapshot) and not C.bytes(focus_snapshot).is_empty(),"equipment focus snapshot is safe and nonempty before custody"):app.queue_free();finish();return
	var focus_bytes:=C.bytes(focus_snapshot)
	var old_mode:int=app.process_mode;var draw_mode:int=app.viewport.render_target_update_mode;var input_disabled:bool=app.viewport.gui_disable_input
	app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID);await frames(8)
	var entry:Node=app.river_entry_controller
	if not check(entry!=null and entry.session.is_open() and entry.view!=null,"explicit Main menu opens the experimental overlay"):app.queue_free();finish();return
	check(app.process_mode==Node.PROCESS_MODE_DISABLED and app.viewport.gui_disable_input and app.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"host processing/input/draw are parked")
	check(C.bytes(equipment.save_data())==host_bytes and ui_equal(app,focus_bytes),"entry preserves authority equipment draft and focus identity")
	var view:Control=entry.view
	view._select_neighbor();view._choose_example("move");view._assess()
	check(view.adapter.phase()=="ready_roll" and not entry.close().ok and entry.session.is_open(),"guest pending return refuses without implicit cancellation")
	view._apply();await frames()
	check(view.adapter.state_copy().turn==1,"guest move commits independently")
	var guest_bytes:=C.bytes(view.adapter.save_data())
	# Drop test-only strong guest references before the controller measures release.
	view=null
	check(entry.close().ok,"verified explicit return succeeds");await frames(6)
	check(C.bytes(equipment.save_data())==host_bytes and ui_equal(app,focus_bytes),"returned host save and target identity are exact")
	check(app.process_mode==old_mode and app.viewport.render_target_update_mode==draw_mode and app.viewport.gui_disable_input==input_disabled,"host presentation modes restore exactly")
	check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"guest adapter/view really release through weak references")
	report["first_return_metrics"]=entry.metrics.duplicate(true)
	app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID);await frames(8)
	check(entry.session.is_open() and C.bytes(entry.session.river.save_data())==guest_bytes,"reentry reconstructs exact guest JSON and history")
	check(entry.close().ok,"second return succeeds");await frames(6)
	check(C.bytes(equipment.save_data())==host_bytes and FileAccess.get_sha256(args[0])==original_file_hash,"original adapter and original disk save remain byte-exact")
	report["second_return_metrics"]=entry.metrics.duplicate(true);report["equipment_file_sha256"]=original_file_hash
	report["host_save_hash"]=C.digest(equipment.save_data());report["host_ui"]=app._river_entry_ui_snapshot()
	app.queue_free();await frames();completed=true;finish()

func verify_full_coast_visit(app: Control)->bool:
	# Exercise the real peak: retained 1801-cell presentation plus guest r4.
	# A visit after switching to a smaller equipment board cannot prove this.
	var host: RefCounted=app.playtest
	var captured:Dictionary=HostCustody.capture(host)
	if not check(captured.ok and captured.kind=="coast_engine_and_narration/v1","full coast uses its explicit engine/narration read-only save capability"):return false
	var host_bytes:=C.bytes(captured.snapshot)
	var ui_snapshot:Dictionary=app._river_entry_ui_snapshot()
	report["full_coast_ui_before"]=ui_snapshot
	if not check(C.safe(ui_snapshot) and not C.bytes(ui_snapshot).is_empty(),"host UI identity has lossless JSON-safe nonempty instance tokens"):return false
	var ui_bytes:=C.bytes(ui_snapshot)
	var board_id:int=app.board.get_instance_id()
	var old_mode:int=app.process_mode
	var draw_mode:int=app.viewport.render_target_update_mode
	var input_disabled:bool=app.viewport.gui_disable_input
	app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID);await frames(8)
	var entry:Node=app.river_entry_controller
	report["coast_entry_status"]={"text":app.status_label.text,"has_controller":entry!=null,"host_phase":host.phase()}
	if not check(entry!=null and entry.session.is_open() and entry.view!=null,"full1801 coast explicitly enters river without replacing host"):return false
	var exact:bool=true
	exact=check(app.playtest==host and app.board.get_instance_id()==board_id and app.board.tiles.size()==1801,"full1801 coast presentation remains resident during guest visit") and exact
	exact=check(app.process_mode==Node.PROCESS_MODE_DISABLED and app.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and app.viewport.gui_disable_input,"full coast input processing and drawing are parked") and exact
	exact=check(C.bytes(HostCustody.capture(host).get("snapshot"))==host_bytes and ui_equal(app,ui_bytes),"full coast authority and focus stay exact while river renders") and exact
	if not check(entry.close().ok,"full coast return succeeds without a guest action"):return false
	await frames(6)
	exact=check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"full coast return releases actual guest view and adapter") and exact
	exact=check(app.playtest==host and app.board.get_instance_id()==board_id and C.bytes(HostCustody.capture(host).get("snapshot"))==host_bytes and ui_equal(app,ui_bytes),"full coast return preserves the same authority board and focus") and exact
	exact=check(app.process_mode==old_mode and app.viewport.render_target_update_mode==draw_mode and app.viewport.gui_disable_input==input_disabled,"full coast presentation modes restore exactly") and exact
	report["full_coast_return_metrics"]=entry.metrics.duplicate(true)
	report["full_coast_host_save_hash"]=C.digest(HostCustody.capture(host).snapshot)
	return exact

func ui_equal(app: Control, expected: String)->bool:
	var current:Dictionary=app._river_entry_ui_snapshot()
	return not expected.is_empty() and C.safe(current) and not C.bytes(current).is_empty() and C.bytes(current)==expected

func verify_default_world(app: Control)->bool:
	# Stop before any switch/river entry. A successful small fallback is failure.
	if not check(app.coast_mode and app.playtest_mode and app.playtest!=null,"actual coast startup is active, no preview fallback"):return false
	var expected:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/generated_v3_river_entry/expected_default_world.json"))
	if not check(expected is Dictionary and expected.get("hex_count")==1801 and expected.get("world_id")=="natural_coast_shore_v03_adventure","fixed full-world acceptance expectation"):return false
	var state:Dictionary=app.playtest.state_copy()
	var identity:Dictionary=state.get("generated_world",{})
	var actual:Dictionary={"world_id":state.get("world_id"),"hex_count":state.get("hexes",{}).size(),"scene_id":state.get("actors",{}).get("actor_player",{}).get("scene_id"),"scene_hex_count":state.get("scenes",{}).get("scene_coast",{}).get("hex_ids",[]).size(),"bundle_id":identity.get("bundle_id"),"source_mesh_sha256":identity.get("source_mesh_sha256"),"source_drainage_sha256":identity.get("source_drainage_sha256"),"catalog_sha256":identity.get("catalog_sha256")}
	report["default_world_identity"]=actual
	var matched:bool=true
	for field in expected:
		matched=check(actual.get(field)==expected[field],"actual1801 default identity: "+field) and matched
	matched=check(actual.scene_hex_count==1801,"actual coast scene contains all1801 hexes") and matched
	matched=check(Bundle.ready() and Bundle.bundle_id()==expected.bundle_id and Bundle.catalog_sha256()==expected.catalog_sha256,"loaded authoritative bundle matches fixed default identity") and matched
	matched=check(is_instance_valid(app.board) and app.board.get_script().resource_path=="res://view/playable_build/board.gd","full coast renderer class, no legacy board fallback") and matched
	return matched

func finish()->void:
	if not completed and failures.is_empty():failures.append("required Main roundtrip stages did not complete")
	report["completed"]=completed
	report["checks"]=checks;report["failures"]=failures;report["engine"]=Engine.get_version_info().string;report["pid"]=OS.get_process_id()
	report["scope"]="actual Main method-driven equipment/river roundtrip and release witnesses; real pointer and cgroup/RSS capture remain separate"
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_river_entry")
	var file:=FileAccess.open("res://artifacts/generated_v3_river_entry/main_roundtrip_report.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("RIVER_V24_ROUNDTRIP ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)

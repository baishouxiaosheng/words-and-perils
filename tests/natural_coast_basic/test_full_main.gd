extends SceneTree
## Run only after explicit serial slot release, through the original native guard.
## Supply one proven, alive v24-compatible equipment save after --. No fixture
## regeneration, RNG reselection, import/editor run or canonical write is allowed.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const MainScene=preload("res://main.tscn")
const Equipment=preload("res://view/generated_v3_equipment/adapter.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const HostCustody=preload("res://view/generated_v3_river_entry/host_custody.gd")
const CHECK_SCHEMA := "natural_coast_full_scene_gate/v2_localized_view"
const EXPECTED_CHECK_IDS := ["full_001", "full_002", "full_003", "full_004", "full_005", "full_006", "full_007", "full_008", "full_009", "full_010", "full_011", "full_012", "full_013", "full_014", "full_015", "full_016", "full_017", "full_018_drop_item", "full_018_observe", "full_018_pickup_item", "full_018_rest", "full_019", "full_020", "full_021", "full_022", "full_023", "full_024", "full_025", "full_026", "full_027", "full_028", "full_029", "full_030", "full_031", "full_032", "full_033", "full_034", "full_035", "full_036", "full_037", "full_038", "full_039", "full_040", "full_041", "full_042", "full_043", "full_044", "full_045", "full_046", "full_047", "full_048", "full_049", "full_050_adapter", "full_050_ground_material", "full_050_ground_mesh", "full_050_navigation", "full_050_physical_base", "full_050_physical_custody", "full_050_physical_navigation", "full_050_source", "full_050_view", "full_050_water_material", "full_050_water_mesh", "full_051", "full_052", "full_053_bundle_id", "full_053_catalog_sha256", "full_053_hex_count", "full_053_scene_id", "full_053_source_drainage_sha256", "full_053_source_mesh_sha256", "full_053_world_id", "full_054", "full_055", "full_056", "full_057_01_full_default", "full_057_02_full_host_natural_coast_entry", "full_057_03_guest_move", "full_057_04_guest_five_actions", "full_057_05_returned_equipment", "full_057_06_plateau_entry"]
var executed_check_ids: Array = []
var checks:=0
var failures:Array=[]
var report:Dictionary={}
var completed:=false
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->bool:
	checks+=1
	if label in executed_check_ids: failures.append("duplicate check ID: "+label)
	else: executed_check_ids.append(label)
	if label not in EXPECTED_CHECK_IDS: failures.append("unregistered check ID: "+label)
	if not value:failures.append(label);printerr("COAST_FULL_FAIL ",label)
	return value
func frames(count:int=4)->void:
	for _i in range(count):await process_frame
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if not check(args.size()==1 and FileAccess.file_exists(args[0]),"full_001"):finish();return
	var original_file_hash:=FileAccess.get_sha256(args[0])
	var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var equipment:=Equipment.new();var loaded:Dictionary=equipment.load_data(saved)
	report["equipment_load"]={"ok":loaded.get("ok",false),"code":loaded.get("code",""),"errors":loaded.get("errors",[]),"roundtrip_equal":C.bytes(equipment.save_data())==C.bytes(saved)}
	if not check(loaded.ok and report.equipment_load.roundtrip_equal,"full_002"):finish();return
	if not check(equipment.state_copy().actors.actor_player.health.current>0,"full_003"):finish();return
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,800)
	var app:Control=MainScene.instantiate();root.add_child(app);await frames()
	check(DisplayServer.get_name() != "headless","full_004")
	await capture("01_full_default")
	check(app.natural_coast_entry_controller==null,"full_005")
	if not verify_default_world(app):app.queue_free();finish();return
	var coast_visit_ok:bool=await verify_full_coast_visit(app)
	if not coast_visit_ok:app.queue_free();finish();return
	app._switch_mode_to("generated_v3_equipment",equipment);await frames()
	if not check(app.playtest==equipment and app.generated_v3_equipment_mode,"full_006"):app.queue_free();finish();return
	var actor:Dictionary=equipment.state_copy().actors.actor_player
	# The current UI exposes map-tile focus; equipped weapons are inventory
	# records, not map silhouettes with a hex. Preserve equipment via full save.
	var focus:Dictionary=equipment.tile_reference(actor.hex)
	app._apply_focus(focus)
	if not check(not app.selected_focus.is_empty() and C.bytes(app.selected_focus)==C.bytes(focus) and app.selected==Vector2i(actor.hex[0],actor.hex[1]),"full_007"):app.queue_free();finish();return
	app.set_player_intent("保留这段主旅程草稿")
	# Actual pending intent is denied entry without auto-cancel or state loss.
	check(equipment.begin_intent("观察当前地点",{}).ok,"full_008")
	var pending:=C.bytes(equipment.save_data())
	app.open_natural_coast_experiment("coastal_range")
	check(C.bytes(equipment.save_data())==pending and equipment.phase()=="awaiting_assessment","full_009")
	check(equipment.cancel().ok,"full_010")
	var host_bytes:=C.bytes(equipment.save_data());var focus_snapshot:Dictionary=app._river_entry_ui_snapshot()
	if not check(C.safe(focus_snapshot) and not C.bytes(focus_snapshot).is_empty(),"full_011"):app.queue_free();finish();return
	var focus_bytes:=C.bytes(focus_snapshot)
	var old_mode:int=app.process_mode;var draw_mode:int=app.viewport.render_target_update_mode;var input_disabled:bool=app.viewport.gui_disable_input
	app.on_tool_selected(app.NATURAL_COAST_MENU_ID);await frames(8)
	var entry:Node=app.natural_coast_entry_controller
	if not check(entry!=null and entry.session.is_open() and entry.view!=null,"full_012"):app.queue_free();finish();return
	check(app.process_mode==Node.PROCESS_MODE_DISABLED and app.viewport.gui_disable_input and app.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"full_013")
	check(C.bytes(equipment.save_data())==host_bytes and ui_equal(app,focus_bytes),"full_014")
	var view:Control=entry.view
	view._select_neighbor();view._choose_example("move");view._assess()
	check(view.adapter.phase()=="ready_roll" and not entry.close().ok and entry.session.is_open(),"full_015")
	check(view.load_button.disabled,"full_016")
	view._apply();await frames()
	check(view.adapter.state_copy().turn==1,"full_017")
	await capture("03_guest_move")
	for kind in ["drop_item","pickup_item","observe","rest"]:
		if kind == "observe": view._select(view.adapter.state_copy().actors.actor_player.hex)
		view._choose_example(kind); view._assess()
		check(view.adapter.phase() == "ready_roll","full_018_"+kind)
		view._apply(); await frames()
	check(view.adapter.state_copy().turn == 5 and view.adapter.state_copy().items.item_travel_bundle.owner_actor_id == "actor_player","full_019")
	var localized_biomes := true
	for biome in view.BIOME_LABELS: localized_biomes = localized_biomes and not view.selection_label.text.contains(" · "+biome+"\n")
	var selected_biome: String = view.adapter.state_copy().hexes["%d,%d" % view.selected_focus.hex].biome
	check(localized_biomes and not view.selection_label.text.is_empty() and view.selection_label.text.contains(" · "+view.BIOME_LABELS[selected_biome]+"\n"),"full_020")
	await capture("04_guest_five_actions")
	var guest_bytes:=C.bytes(view.adapter.save_data())
	# Drop test-only strong guest references before the controller measures release.
	view=null
	check(entry.close().ok,"full_021");await frames(6)
	check(C.bytes(equipment.save_data())==host_bytes and ui_equal(app,focus_bytes),"full_022")
	check(app.process_mode==old_mode and app.viewport.render_target_update_mode==draw_mode and app.viewport.gui_disable_input==input_disabled,"full_023")
	check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"full_024")
	await capture("05_returned_equipment")
	report["first_return_metrics"]=entry.metrics.duplicate(true)
	app.on_tool_selected(app.NATURAL_COAST_MENU_ID);await frames(8)
	check(entry.session.is_open() and C.bytes(entry.session.coast.save_data())==guest_bytes,"full_025")
	check(entry.close().ok,"full_026");await frames(6)
	check(C.bytes(equipment.save_data())==host_bytes and FileAccess.get_sha256(args[0])==original_file_hash,"full_027")
	report["second_return_metrics"]=entry.metrics.duplicate(true);report["equipment_file_sha256"]=original_file_hash
	app.on_tool_selected(app.NATURAL_PLATEAU_MENU_ID); await frames(8)
	check(entry.session.is_open() and entry.session.coast.source.data.recipe.id == "plateau_hinterland" and entry.session.coast.state_copy().turn == 0,"full_028")
	var plateau_before := C.bytes(entry.session.coast.state_copy()); var plateau_rng := C.bytes(entry.session.coast.engine.save_data().rng)
	entry.view._select(entry.session.coast.state_copy().actors.actor_player.hex)
	check(C.bytes(entry.session.coast.state_copy()) == plateau_before and C.bytes(entry.session.coast.engine.save_data().rng) == plateau_rng,"full_029")
	entry.view._choose_example("observe"); entry.view._assess()
	check(entry.session.coast.phase() == "ready_roll" and entry.view.load_button.disabled,"full_030")
	entry.view._cancel()
	check(entry.session.coast.phase() == "idle" and C.bytes(entry.session.coast.state_copy()) == plateau_before and C.bytes(entry.session.coast.engine.save_data().rng) == plateau_rng,"full_031")
	check(C.bytes(entry.session._parked_coast_saves.coastal_range) == guest_bytes,"full_032")
	await capture("06_plateau_entry")
	check(entry.close().ok,"full_033"); await frames(6)
	check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"full_034")
	check(C.bytes(equipment.save_data()) == host_bytes and ui_equal(app,focus_bytes) and app.process_mode == old_mode and app.viewport.render_target_update_mode == draw_mode and app.viewport.gui_disable_input == input_disabled,"full_035")
	app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID); await frames(8)
	var old_river: Node = app.river_entry_controller
	check(old_river != null and old_river.session.is_open() and old_river.session.river.source.identity.renderer_profile == "structured_rivers_v1","full_036")
	if old_river != null and old_river.session.is_open(): check(old_river.close().ok,"full_037")
	await frames(6)
	check(C.bytes(equipment.save_data()) == host_bytes and FileAccess.get_sha256(args[0]) == original_file_hash,"full_038")
	check(ui_equal(app,focus_bytes) and app.process_mode == old_mode and app.viewport.render_target_update_mode == draw_mode and app.viewport.gui_disable_input == input_disabled,"full_039")
	report["host_save_hash"]=C.digest(equipment.save_data());report["host_ui"]=app._river_entry_ui_snapshot()
	app.queue_free();await frames();completed=true;finish()

func verify_full_coast_visit(app: Control)->bool:
	# Exercise the real peak: retained 1801-cell presentation plus guest r4.
	# A visit after switching to a smaller equipment board cannot prove this.
	var host: RefCounted=app.playtest
	var captured:Dictionary=HostCustody.capture(host)
	if not check(captured.ok and captured.kind=="coast_engine_and_narration/v1","full_040"):return false
	var host_bytes:=C.bytes(captured.snapshot)
	var ui_snapshot:Dictionary=app._river_entry_ui_snapshot()
	report["full_coast_ui_before"]=ui_snapshot
	if not check(C.safe(ui_snapshot) and not C.bytes(ui_snapshot).is_empty(),"full_041"):return false
	var ui_bytes:=C.bytes(ui_snapshot)
	var board_id:int=app.board.get_instance_id()
	var old_mode:int=app.process_mode
	var draw_mode:int=app.viewport.render_target_update_mode
	var input_disabled:bool=app.viewport.gui_disable_input
	app.on_tool_selected(app.NATURAL_COAST_MENU_ID);await frames(8)
	var entry:Node=app.natural_coast_entry_controller
	report["coast_entry_status"]={"text":app.status_label.text,"has_controller":entry!=null,"host_phase":host.phase()}
	if not check(entry!=null and entry.session.is_open() and entry.view!=null,"full_042"):return false
	var ownership: Dictionary = guest_refs(entry)
	var exact:bool=true
	exact=check(app.playtest==host and app.board.get_instance_id()==board_id and app.board.tiles.size()==1801,"full_043") and exact
	exact=check(app.process_mode==Node.PROCESS_MODE_DISABLED and app.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and app.viewport.gui_disable_input,"full_044") and exact
	exact=check(C.bytes(HostCustody.capture(host).get("snapshot"))==host_bytes and ui_equal(app,ui_bytes),"full_045") and exact
	await capture("02_full_host_natural_coast_entry")
	if not check(entry.close().ok,"full_046"):return false
	await frames(6)
	exact=check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"full_047") and exact
	exact=check(app.playtest==host and app.board.get_instance_id()==board_id and C.bytes(HostCustody.capture(host).get("snapshot"))==host_bytes and ui_equal(app,ui_bytes),"full_048") and exact
	exact=check(app.process_mode==old_mode and app.viewport.render_target_update_mode==draw_mode and app.viewport.gui_disable_input==input_disabled,"full_049") and exact
	for key in ownership: exact = check(ownership[key].get_ref() == null,"full_050_"+key) and exact
	report["full_coast_return_metrics"]=entry.metrics.duplicate(true)
	report["full_coast_host_save_hash"]=C.digest(HostCustody.capture(host).snapshot)
	return exact

func ui_equal(app: Control, expected: String)->bool:
	var current:Dictionary=app._river_entry_ui_snapshot()
	return not expected.is_empty() and C.safe(current) and not C.bytes(current).is_empty() and C.bytes(current)==expected

func verify_default_world(app: Control)->bool:
	# Stop before any switch/river entry. A successful small fallback is failure.
	if not check(app.coast_mode and app.playtest_mode and app.playtest!=null,"full_051"):return false
	var expected:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/generated_v3_river_entry/expected_default_world.json"))
	if not check(expected is Dictionary and expected.get("hex_count")==1801 and expected.get("world_id")=="natural_coast_shore_v03_adventure","full_052"):return false
	var state:Dictionary=app.playtest.state_copy()
	var identity:Dictionary=state.get("generated_world",{})
	var actual:Dictionary={"world_id":state.get("world_id"),"hex_count":state.get("hexes",{}).size(),"scene_id":state.get("actors",{}).get("actor_player",{}).get("scene_id"),"scene_hex_count":state.get("scenes",{}).get("scene_coast",{}).get("hex_ids",[]).size(),"bundle_id":identity.get("bundle_id"),"source_mesh_sha256":identity.get("source_mesh_sha256"),"source_drainage_sha256":identity.get("source_drainage_sha256"),"catalog_sha256":identity.get("catalog_sha256")}
	report["default_world_identity"]=actual
	var matched:bool=true
	for field in expected:
		matched=check(actual.get(field)==expected[field],"full_053_"+field) and matched
	matched=check(actual.scene_hex_count==1801,"full_054") and matched
	matched=check(Bundle.ready() and Bundle.bundle_id()==expected.bundle_id and Bundle.catalog_sha256()==expected.catalog_sha256,"full_055") and matched
	matched=check(is_instance_valid(app.board) and app.board.get_script().resource_path=="res://view/playable_build/board.gd","full_056") and matched
	return matched

func guest_refs(entry: Node) -> Dictionary:
	var source: RefCounted = entry.session.coast.source
	return {"view":weakref(entry.view),"adapter":weakref(entry.session.coast),"source":weakref(source),"physical_base":weakref(source.physical_base),"physical_custody":weakref(source.physical_base.custody),"navigation":weakref(source.navigation),"physical_navigation":weakref(source.physical_base.custody.navigation),"ground_mesh":weakref(source.renderer_bundle.ground_mesh),"water_mesh":weakref(source.renderer_bundle.water_mesh),"ground_material":weakref(source.renderer_bundle.ground_material),"water_material":weakref(source.renderer_bundle.water_material)}
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OS.get_environment("COAST_PLAY_OUTPUT").path_join(label+".png")
	var error := image.save_png(path)
	check(error == OK and image.get_width() > 0 and image.get_height() > 0,"full_057_"+label)
	if not report.has("captures"): report.captures = []
	report.captures.append({"label":label,"path":path,"width":image.get_width(),"height":image.get_height(),"sha256":FileAccess.get_sha256(path)})
func finish()->void:
	executed_check_ids.sort()
	if executed_check_ids != EXPECTED_CHECK_IDS: failures.append("missing or unexpected full-scene check IDs")
	if not completed and failures.is_empty():failures.append("required Main roundtrip stages did not complete")
	report["check_schema"]=CHECK_SCHEMA; report["expected_check_ids"]=EXPECTED_CHECK_IDS; report["executed_check_ids"]=executed_check_ids
	report["completed"]=completed; report["ok"]=failures.is_empty()
	report["checks"]=checks;report["failures"]=failures;report["engine"]=Engine.get_version_info().string;report["owned_pid"]=OS.get_process_id()
	report["run_id"]=OS.get_environment("COAST_PLAY_RUN_ID");report["script_sha256"]=FileAccess.get_sha256(get_script().resource_path)
	report["scope"]="actual1801 Main method-driven natural-coast/equipment/old-river roundtrip, five UI actions and release witnesses; real OS-pointer test remains separate"
	var output := OS.get_environment("COAST_PLAY_OUTPUT")
	var encoded := JSON.stringify(report,"\t",true,true)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(encoded)
	FileAccess.open(output.path_join("completed.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":report.run_id,"owned_pid":report.owned_pid,"checks":checks,"result_sha256":encoded.sha256_text(),"script_sha256":report.script_sha256}))
	print("NATURAL_COAST_FULL ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)

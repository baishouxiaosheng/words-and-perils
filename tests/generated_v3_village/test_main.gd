extends SceneTree
const Main=preload("res://main.tscn")
const Adapter=preload("res://view/generated_v3_village/adapter.gd")
const Inventory=preload("res://view/generated_v3_inventory/adapter.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_village_ui/"
var app
var checks:=0
var failures:Array=[]
var shots:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("V3_VILLAGE_UI_FAIL ",label)
	return ok
func frames(n:int=4) -> void:
	for i in range(n):await process_frame
func capture(label_:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var image_:Image=root.get_texture().get_image();var path:String=OUT+label_+".png"
	check(image_.save_png(path)==OK,"capture "+label_)
	var decoded:=Image.load_from_file(path)
	check(decoded.get_size()==root.size and app.viewport.size==root.size,"actual root/world/PNG extent "+label_)
	shots.append({"name":label_,"root":[root.size.x,root.size.y],"world":[app.viewport.size.x,app.viewport.size.y],"png":[decoded.get_width(),decoded.get_height()]})
func sample(kind:String) -> bool:
	var turn:int=app.playtest.state_copy().turn
	app.fill_generated_sample(kind);app.end_turn()
	if not check(app.playtest.phase()=="awaiting_assessment",kind+" awaits assessment"):return false
	app.playtest_fixture()
	return check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,kind+" commits once")
func motion() -> void:
	var begun:int=Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()-begun<20000:await process_frame
	check(not app.board.presentation.actors.actor_player.moving,"route presentation completes")
func select(hex:Array) -> void:app.on_hex_selected(Vector2i(hex[0],hex[1]))
func walk_to(target:Array) -> bool:
	for iteration in range(32):
		var state:Dictionary=app.playtest.state_copy()
		if state.actors.actor_player.hex==target:return true
		var current_key:String=Planner.key(state.actors.actor_player.hex)
		var distances:Dictionary=Planner.distances(app.playtest.source.navigation.allowed,Planner.key(target))
		if not check(distances.has(current_key),"effective graph offers route to village"):return false
		var neighbors:Array=app.playtest.source.navigation.allowed[current_key].duplicate();neighbors.sort()
		var next:Array=[]
		for neighbor in neighbors:
			if distances.has(neighbor) and distances[neighbor]<distances[current_key]:next=Planner.hex_(neighbor);break
		if not check(not next.is_empty(),"verified next edge approaches target"):return false
		if not app.playtest.movement_preview(next).get("ok",false):
			if state.actors.actor_player.stamina.current>=state.actors.actor_player.stamina.max:return check(false,"legal edge cannot resolve with full stamina")
			if not sample("rest"):return false
			continue
		select(next)
		if not sample("move"):return false
		await motion()
	return false
func close_village_camera(hex:Array) -> void:
	app.board.view_focus=app.playtest.source.navigation.cell_center(hex)
	app.board.camera_distance=7.5;app.board.overview_mode=false;app.board.orbit_camera(0,0)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1280,720)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	check(not app.v3_village_choice.button_pressed,"village remains explicit opt-in")
	app.v3_inventory_choice.button_pressed=true;await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_inventory_mode and not app.generated_v3_village_mode,"ordinary inventory still enters"):finish();return
	var old:RefCounted=app.playtest;app.save_game();var old_bytes:String=C.bytes(old.save_data());var old_file:String=FileAccess.get_file_as_string(Inventory.INVENTORY_SAVE)
	app.set_player_intent("原行囊旅程的未提交草稿",false);var old_draft:String=app.goal.text
	app.show_v3_setup();app.v3_village_choice.button_pressed=true;await capture("village_setup");app.v3_setup_dialog.hide()
	await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_village_mode and app.playtest.ready().ok and app.board.load_error.is_empty(),"explicit village source enters real Main"):printerr(app.playtest.ready());finish();return
	var source:RefCounted=app.playtest.source;var manifest:Dictionary=source.placement_result.manifest
	var site:Array=manifest.settlements[0].center_hex;var entry:Array=manifest.settlements[0].entry_hex
	check(C.bytes(source.data)==C.bytes(old.source.data) and source.identity.geometry_hash==old.source.identity.geometry_hash,"village uses exact original source/mesh")
	check(app.playtest.save_data().schema_version==Adapter.VILLAGE_SAVE_SCHEMA and source.identity.placement_hash==manifest.placement_hash,"distinct placement/save identity")
	check(app.generated_v3_inventory_adventure==old and C.bytes(old.save_data())==old_bytes,"ordinary inventory session preserved")
	check(app.board.village_report().collision_subject_count==3 and app.board.village_report().shared_surface,"three opaque buildings share exact bag support surface")
	var before:String=C.bytes(app.playtest.save_data());var kinds:Dictionary={}
	for id in source.identity.static_entity_catalog.entries:
		var ref:Dictionary=app.playtest.static_reference(id);app._apply_focus(ref);kinds[ref.kind]=true
		check(app.selected_focus.get("id")==id and app.resolved_focus.facts.descriptor.id==id,"exact registered static selection "+ref.kind)
	check(kinds.size()==3 and C.bytes(app.playtest.save_data())==before,"all static selection kinds have no turn/RNG effect")
	app.clear_target();close_village_camera(site);app.set_map_dialogue_hidden(true);await capture("village_overview")
	check(await walk_to(entry),"legitimate actions reach clear village entry")
	check(source.navigation.step(entry,site).ok,"actual road entry remains traversable")
	for _rest in range(4):
		if app.playtest.movement_preview(site).get("ok",false):break
		if not sample("rest"):break
	select(site);var preview:Dictionary=app.playtest.movement_preview(site)
	if not check(preview.get("ok",false),"plaza route preview admitted"):finish();return
	var expected_cost:int=preview.cost;var stamina:int=app.playtest.state_copy().actors.actor_player.stamina.current
	app.fill_generated_sample("move");app.end_turn()
	var frozen:String=C.bytes(app.playtest.action_copy().focus);var request:String=C.bytes(app.playtest.request())
	var building_id:String=manifest.buildings[0].id;app._apply_focus(app.playtest.static_reference(building_id))
	check(C.bytes(app.playtest.action_copy().focus)==frozen and C.bytes(app.playtest.request())==request,"new building selection leaves pending route witness exact")
	app.save_game();var pending:String=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==pending,"pending source/placement/graph/focus survive load")
	app.playtest.prepare_fixture();app.playtest.roll_once();app.sync_playtest_request();app.save_game();var locked:String=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==locked and app.playtest.phase()=="rolled","locked route reload exact")
	app.cancel_pending();check(C.bytes(app.playtest.save_data())==locked,"locked route cannot cancel")
	app.advance_playtest();app.advance_playtest();await motion()
	check(app.playtest.state_copy().actors.actor_player.hex==site and app.playtest.state_copy().actors.actor_player.stamina.current==stamina-expected_cost,"committed road route lands at original plaza with exact cost")
	var committed:String=C.bytes(app.playtest.save_data());app.playtest.commit();check(C.bytes(app.playtest.save_data())==committed,"repeat route commit is idempotent")
	close_village_camera(site);app.set_map_dialogue_hidden(true);await capture("village_arrival")
	app._apply_focus(app.playtest.static_reference(building_id));app.show_focus_details();await capture("building_details");app.focus_details_dialog.hide()
	before=C.bytes(app.playtest.save_data());app.set_player_intent("和这座房子里的店主交易",false);app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and not app.playtest.fixture_available(),"unsupported conversation/trade not silently manufactured")
	app.cancel_pending();check(app.playtest.phase()=="idle" and C.bytes(app.playtest.state_copy())==C.bytes(JSON.parse_string(before).engine.state),"unassessed action cancels without world effect")
	app.select_generated_item("item_travel_bundle");app.focus_details_dialog.hide();sample("drop_item");await frames()
	check(not app.playtest.state_copy().items.item_travel_bundle.has("owner_actor_id") and app.board.inventory_pack.ground_pose.get("footprint_verified",false),"bag drops onto full-area dry prop-clear ground in village")
	check(await walk_to(entry),"traveler legitimately leaves dropped bag at village")
	close_village_camera(site);await capture("village_ground_pack")
	check(app.playtest.state_copy().items.item_travel_bundle.hex==site,"walking away keeps bag at village cell")
	app.select_generated_item("item_travel_bundle");app.focus_details_dialog.hide();sample("pickup_item")
	check(app.playtest.state_copy().items.item_travel_bundle.get("owner_actor_id")=="actor_player","pickup through clear entry reuses original item rules")
	app.save_game();committed=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==committed,"combined committed history reload exact")
	app.playtest.save_file(OUT+"committed.json")
	app.set_player_intent("村落旅程的独立草稿",false);var village_draft:String=app.goal.text
	app.continue_v3_inventory_adventure();await frames()
	check(not app.generated_v3_village_mode and app.playtest==old and C.bytes(old.save_data())==old_bytes and app.goal.text==old_draft,"ordinary inventory session and draft return exact")
	check(FileAccess.get_file_as_string(Inventory.INVENTORY_SAVE)==old_file,"combined save never overwrites ordinary inventory file")
	app.continue_v3_village_adventure();await frames()
	check(app.generated_v3_village_mode and C.bytes(app.playtest.save_data())==committed and app.goal.text==village_draft,"combined session and draft return exact")
	app.reset_playtest();await frames()
	check(app.playtest.state_copy().turn==0 and app.playtest.source.identity.placement_hash==manifest.placement_hash and app.board.load_error.is_empty(),"restart reproduces same source-bound village with one starting bundle")
	check(C.bytes(old.save_data())==old_bytes,"restart leaves prior inventory authority unchanged")
	finish()
func finish() -> void:
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":shots}
	var file:=FileAccess.open(OUT+"main_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("V3_VILLAGE_UI_RESULT ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)

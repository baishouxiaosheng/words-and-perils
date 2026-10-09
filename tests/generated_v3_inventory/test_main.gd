extends SceneTree
const Main=preload("res://main.tscn")
const Adapter=preload("res://view/generated_v3_inventory/adapter.gd")
const BaseAdapter=preload("res://view/generated_v3_adventure/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_inventory_ui/"
var app
var checks:=0
var failures:Array=[]
var shots:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("V3_ITEM_UI_FAIL ",label)
	return ok
func frames(n:int=5) -> void:
	for i in range(n):await process_frame
func capture(label_:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var image_:Image=root.get_texture().get_image();var path:String=OUT+label_+".png"
	check(image_.save_png(path)==OK,"capture written "+label_)
	var decoded:=Image.load_from_file(path)
	check(decoded.get_size()==image_.get_size() and decoded.get_size()==root.size,"actual decoded raster "+label_)
	shots.append({"name":label_,"root":[root.size.x,root.size.y],"world":[app.viewport.size.x,app.viewport.size.y],"png":[decoded.get_width(),decoded.get_height()]})
func select(hex:Array) -> void:app.on_hex_selected(Vector2i(hex[0],hex[1]))
func sample(kind:String) -> bool:
	var turn:int=app.playtest.state_copy().turn
	app.fill_generated_sample(kind);app.end_turn()
	if not check(app.playtest.phase()=="awaiting_assessment",kind+" waits for assessment"):return false
	app.playtest_fixture()
	return check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,kind+" commits once")
func motion() -> void:
	var begun:int=Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()-begun<15000:await process_frame
	check(not app.board.presentation.actors.actor_player.moving,"committed movement completes")
func inspect_pack(label_:String) -> void:
	var before:String=C.bytes(app.playtest.save_data())
	app.show_inventory()
	var found:Button
	for node in app.inventory_box.get_children():
		if node is Button and not node.is_queued_for_deletion() and node.text=="查看行礼包":found=node;break
	if not check(is_instance_valid(found),label_+" inventory exposes known pack"):return
	found.pressed.emit()
	check(app.selected_focus.get("id")=="item_travel_bundle" and app.focus_details_dialog.visible,label_+" selects exact item details")
	check(C.bytes(app.playtest.save_data())==before,label_+" view has no authoritative effect")
	app.focus_details_dialog.hide()
func visible_pack() -> Dictionary:
	var view:Node=app.board.inventory_pack
	for part in view.mesh_parts:
		var faces:PackedVector3Array=part.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var world:Vector3=part.global_transform*((faces[i]+faces[i+1]+faces[i+2])/3.0)
			var point:Vector2=app.board.camera.unproject_position(world)
			var candidates:Array=app.board.pick_focus(point)
			if not candidates.is_empty() and candidates[0].reference.get("id")=="item_travel_bundle":return {"point":point,"candidates":candidates}
	return {}
func click_ground_pack() -> void:
	var before:String=C.bytes(app.playtest.save_data());var hit:=visible_pack()
	if not check(not hit.is_empty(),"unobscured ground mesh is truly pickable"):return
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=hit.point
	app.board._input(event)
	check(app.selected_focus.get("kind")=="item" and app.selected_focus.get("catalog_version")=="source-entity-focus/v1","real input chooses stable catalog ID")
	check(C.bytes(app.playtest.save_data())==before,"world click cannot pick up or advance turn")
func distance(a:Array,b:Array) -> int:return maxi(absi(a[0]-b[0]),maxi(absi(a[1]-b[1]),absi(a[0]-b[0]+a[1]-b[1])))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1280,720)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	check(not app.v3_inventory_choice.button_pressed,"inventory is explicit opt-in")
	await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_mode and not app.generated_v3_inventory_mode,"base V3 remains ordinary entry"):finish();return
	var base:RefCounted=app.playtest;app.save_game()
	var base_bytes:String=C.bytes(base.save_data());var base_file:String=FileAccess.get_file_as_string(BaseAdapter.GENERATED_SAVE)
	app.set_player_intent("普通探索未提交的草稿",false);var base_draft:String=app.goal.text
	app.show_v3_setup();app.v3_inventory_choice.button_pressed=true;await capture("inventory_setup");app.v3_setup_dialog.hide()
	await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_inventory_mode and app.playtest.ready().ok and app.board.load_error.is_empty(),"explicit inventory profile enters real Main"):finish();return
	check(app.playtest.source.identity.inventory_profile=="generated_v3_inventory/v1" and app.playtest.save_data().schema_version==Adapter.INVENTORY_SAVE_SCHEMA,"explicit inventory identities")
	check(app.generated_v3_adventure==base and base.state_copy().items.is_empty() and C.bytes(base.save_data())==base_bytes,"base V3 neither replaced nor injected with items")
	check(C.bytes(app.playtest.source.data)==C.bytes(base.source.data) and app.playtest.source.identity.geometry_hash==base.source.identity.geometry_hash,"same raw source and geometry retained")
	check(app.board.inventory_packs.keys()==["item_travel_bundle"] and app.board.inventory_pack.carried and app.board.inventory_pack.pack.visible,"existing pack model follows carried state")
	var origin:Array=app.playtest.state_copy().actors.actor_player.hex
	inspect_pack("carried");await capture("carried_pack")
	var initial:String=C.bytes(app.playtest.state_copy())
	app.fill_generated_sample("drop_item");app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and C.bytes(app.playtest.state_copy())==initial and app.board.inventory_pack.carried,"unassessed drop leaves carried item untouched")
	var frozen:String=C.bytes(app.playtest.action_copy().focus)
	select(origin);app.save_game();var pending:String=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==pending and C.bytes(app.playtest.action_copy().focus)==frozen,"pending inventory save/reload preserves exact frozen item witness")
	check(FileAccess.get_file_as_string(BaseAdapter.GENERATED_SAVE)==base_file,"inventory save never overwrites base exploration file")
	app.playtest.prepare_fixture();app.playtest.roll_once();app.sync_playtest_request();app.save_game();var locked:String=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and app.playtest.phase()=="rolled" and C.bytes(app.playtest.save_data())==locked,"locked item outcome survives reload exactly")
	app.cancel_pending();check(C.bytes(app.playtest.save_data())==locked,"locked item result cannot cancel")
	app.advance_playtest();app.advance_playtest();await frames()
	check(app.playtest.phase()=="idle" and not app.playtest.state_copy().items.item_travel_bundle.has("owner_actor_id"),"drop commits ground custody once")
	check(not app.board.inventory_pack.carried and app.board.inventory_pack.ground_pose.get("footprint_verified",false),"ground model uses full-area actual-mesh dry support")
	var dropped:String=C.bytes(app.playtest.save_data());app.playtest.commit();check(C.bytes(app.playtest.save_data())==dropped,"repeated drop commit is idempotent")
	inspect_pack("ground");app.playtest.save_file(OUT+"dropped.json")
	var state:Dictionary=app.playtest.state_copy();var from:String="%d,%d"%origin
	var next_key:String=app.playtest.source.navigation.allowed[from][0];var next_cell:Dictionary=state.hexes[next_key];var neighbor:Array=[next_cell.q,next_cell.r]
	select(neighbor);sample("move");await motion()
	check(app.playtest.state_copy().items.item_travel_bundle.hex==origin,"walking away does not drag a dropped bag")
	app.set_map_dialogue_hidden(true);await frames();click_ground_pack();await capture("ground_after_departure");app.set_map_dialogue_hidden(false)
	var far:Array=[];var far_cost:=1000000;state=app.playtest.state_copy()
	for cell in state.hexes.values():
		var target:Array=[cell.q,cell.r]
		if distance(origin,target)<2:continue
		var plan:Dictionary=app.playtest.movement_preview(target)
		if plan.get("ok",false) and int(plan.cost)<far_cost:far=target;far_cost=plan.cost
	if check(not far.is_empty(),"fixture has a reachable farther cell"):
		select(far);sample("move");await motion();inspect_pack("known remote ground")
		var facts:String=C.bytes(app.playtest.state_copy());app.fill_generated_sample("pickup_item");app.end_turn();app.playtest_fixture()
		check(app.playtest.phase()=="awaiting_assessment" and C.bytes(app.playtest.state_copy())==facts,"remote inspection never grants pickup reach")
		app.cancel_pending();check(app.playtest.phase()=="idle","invalid reach can cancel before lock")
		for _i in range(4):
			if app.playtest.movement_preview(origin).get("ok",false) or app.playtest.state_copy().actors.actor_player.stamina.current>=8:break
			if not sample("rest"):break
		select(origin);sample("move");await motion()
	inspect_pack("return");sample("pickup_item");await frames()
	check(app.playtest.state_copy().items.item_travel_bundle.get("owner_actor_id")=="actor_player" and app.board.inventory_pack.carried,"pickup restores exact carried item/model")
	var committed:String=C.bytes(app.playtest.save_data());app.save_game();app.load_game();check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==committed,"committed inventory save/load exact")
	app.playtest.save_file(OUT+"committed.json");await capture("picked_up")
	app.set_player_intent("行囊探索的独立草稿",false);var inventory_draft:String=app.goal.text
	app.continue_v3_adventure();await frames()
	check(app.playtest==base and not app.generated_v3_inventory_mode and C.bytes(base.save_data())==base_bytes and app.goal.text==base_draft,"base session state and draft return intact")
	app.continue_v3_inventory_adventure();await frames()
	check(app.generated_v3_inventory_mode and C.bytes(app.playtest.save_data())==committed and app.goal.text==inventory_draft,"inventory session state and draft return intact")
	app.reset_playtest();check(app.playtest.state_copy().turn==0 and app.playtest.state_copy().items.item_travel_bundle.custody_revision==0 and app.playtest.state_copy().actors.actor_player.hex==origin,"reset remains same explicit inventory profile")
	check(C.bytes(base.save_data())==base_bytes and FileAccess.get_file_as_string(BaseAdapter.GENERATED_SAVE)==base_file,"reset does not inject or alter base exploration")
	finish()
func finish() -> void:
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":shots}
	var file:=FileAccess.open(OUT+"main_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("V3_ITEM_UI_RESULT ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)

extends SceneTree
const Main=preload("res://main.tscn")
const Contract=preload("res://core/world_generation_contract.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Inventory=preload("res://view/generated_inventory/adapter.gd")
const Focus=preload("res://view/generated_inventory/item_focus.gd")
const OUT="res://artifacts/generated_pack_selection/"
var app
var checks:=0
var failures:Array[String]=[]
var checkpoints:Dictionary={}
var capture_metrics:Array=[]
var mode_:="create"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):mode_=arg.trim_prefix("--phase=")
	run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("PACK_NATIVE_FAIL ",label)
	return ok
func frames(count_:int=5) -> void:
	for i in range(count_):await process_frame
func capture(name_:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var image_:Image=root.get_texture().get_image()
	var path:String=OUT+name_+".png"
	check(image_.save_png(path)==OK,"capture written "+name_)
	var decoded:Image=Image.load_from_file(path)
	check(not decoded.is_empty() and decoded.get_size()==image_.get_size(),"decoded PNG pixel dimensions verified "+name_)
	capture_metrics.append({"name":name_,"root_window":[root.size.x,root.size.y],"world_viewport":[app.viewport.size.x,app.viewport.size.y],"png":[decoded.get_width(),decoded.get_height()]})
	var metric_file:=FileAccess.open(OUT+"native_"+mode_+"_capture_metrics.json",FileAccess.WRITE);metric_file.store_string(C.bytes(capture_metrics));metric_file.close()
func sample(kind:String) -> bool:
	var turn:int=app.playtest.state_copy().turn
	app.fill_generated_sample(kind);app.end_turn()
	if not check(app.playtest.phase()=="awaiting_assessment",kind+" waits for valid assessment"):return false
	app.playtest_fixture()
	return check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,kind+" commits exactly once")
func checkpoint(name_:String) -> void:
	check(app.playtest.save_file(OUT+"native_"+name_+".json").ok,name_+" checkpoint saved")
	checkpoints[name_]={"digest":C.digest(app.playtest.save_data()),"phase":app.playtest.phase(),"state":app.playtest.state_copy(),"rng":app.playtest.engine.save_data().rng,"focus":app.playtest.item_reference()}
func camera_to(hex:Array) -> void:
	app.board.overview_mode=false
	app.board.view_focus=app.board._source_position(hex)+Vector3(0,.2,0)
	app.board.camera_distance=8.0;app.board.orbit_pitch=1.05;app.board.view_angle=.15
	app.board.orbit_camera(0)
func pick_pack() -> Dictionary:
	var layer:Node=app.board.inventory_pack
	for mesh in layer.mesh_parts:
		var faces_:PackedVector3Array=mesh.mesh.get_faces()
		for i in range(0,faces_.size(),3):
			var center:Vector3=mesh.global_transform*((faces_[i]+faces_[i+1]+faces_[i+2])/3.0)
			var point:Vector2=app.board.camera.unproject_position(center)
			var candidates:Array=app.board.pick_focus(point)
			if not candidates.is_empty() and candidates[0].reference.get("id")==Focus.ITEM:return {"point":point,"candidates":candidates}
	return {}
func click_pack(label_:String) -> bool:
	var before:String=C.digest(app.playtest.save_data());var pick_:Dictionary=pick_pack()
	if not check(not pick_.is_empty(),label_+" actual visible mesh ray finds pack"):return false
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=pick_.point
	app.board._input(event)
	check(app.selected_focus.get("id")==Focus.ITEM and app.resolved_focus.get("kind")=="item",label_+" native input selects exact pack")
	check(C.digest(app.playtest.save_data())==before and app.playtest.phase()=="idle",label_+" click never starts a turn")
	check(app.board.inventory_pack.selected and app.target_label.text.contains("行礼包"),label_+" readable caption and selected ring")
	return true
func inspect_pack_from_inventory(label_:String) -> bool:
	var before:String=C.digest(app.playtest.save_data())
	app.show_inventory()
	var chosen:Button
	for child in app.inventory_box.get_children():
		if child is Button and child.text=="查看行礼包" and not child.is_queued_for_deletion():chosen=child;break
	if not check(is_instance_valid(chosen),label_+" inventory exposes the known pack"):return false
	chosen.pressed.emit()
	check(app.selected_focus.get("id")==Focus.ITEM and app.focus_details_dialog.visible,label_+" read-only inventory selection identifies exact pack")
	check(C.digest(app.playtest.save_data())==before,label_+" inspection cannot move or pick up")
	app.focus_details_dialog.hide()
	return true

func wait_motion() -> void:
	var start:int=Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()-start<15000:await process_frame
	check(not app.board.presentation.actors.actor_player.moving,"committed route animation finishes")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,720)
	app=Main.instantiate();root.add_child(app);await frames(10)
	if not check(app.coast_mode and app.board.load_error.is_empty(),"unchanged real Main coast starts"):finish();return
	if mode_=="resume_locked":await resume_locked()
	else:await create_journey()
	finish()
func start_inventory() -> bool:
	app.switch_playtest(false)
	var envelope:Dictionary=Contract.generate("雪岸-行囊","compact_coast",4)
	var prepared:Dictionary=app.prepare_world_candidate(envelope.source)
	if not check(prepared.ok and app.commit_world_candidate(prepared.candidate).ok,"real generated preview admitted"):return false
	app.last_world_generation_metadata=envelope.metadata.duplicate(true)
	app.generated_inventory_choice.button_pressed=true
	await app.start_generated_from_preview();await frames()
	return check(app.generated_mode and app.playtest.save_data().schema_version==Inventory.INVENTORY_SAVE_SCHEMA,"existing explicit start selects inventory profile")
func create_journey() -> void:
	if not await start_inventory():return
	var initial:Dictionary=app.playtest.state_copy();var origin:Array=initial.actors.actor_player.hex.duplicate()
	camera_to(origin);await frames()
	check_support_cases()
	check(app.runtime_ai._adapter==null and not app.runtime_ai.client.configured(),"no model setting or live provider added")
	check(app.board.inventory_pack.diagnostic().visible and app.board.inventory_pack.carried,"one real carried pack visible")
	if not click_pack("carried"):return
	if not click_pack("repeat carried"):return
	app.show_focus_details();check(app.focus_details_text.text.contains("整件放下"),"details describe actual pack capability");await capture("native_carried_details");app.focus_details_dialog.hide()
	app.show_inventory();await frames()
	var before:String=C.digest(app.playtest.save_data());var button_:Button
	for child in app.inventory_box.get_children():
		if child is Button and child.text=="查看行礼包":button_=child;break
	check(is_instance_valid(button_),"inventory has read-only pack selection")
	if is_instance_valid(button_):button_.pressed.emit()
	check(app.focus_details_dialog.visible and app.selected_focus.id==Focus.ITEM and C.digest(app.playtest.save_data())==before,"inventory selection opens correct details without action")
	app.inventory_dialog.hide();app.focus_details_dialog.hide()
	var ref:Dictionary=app.selected_focus.duplicate(true)
	app.set_player_intent("把选中的行礼包放在脚边。")
	app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and app.board.inventory_pack.carried,"natural selected intent awaits assessment without visual relocation")
	var request:String=C.bytes(app.current_request)
	app.on_hex_selected(Vector2i(origin[0],origin[1]))
	check(C.bytes(app.current_request)==request,"next selection cannot rewrite frozen bag context")
	checkpoint("pending")
	app.cancel_pending();check(app.playtest.phase()=="idle" and app.board.inventory_pack.carried and app.playtest.state_copy().turn==0,"cancel keeps original carried pack")
	app._apply_focus(ref);app.fill_generated_sample("drop_item");app.submit_action();app.playtest_fixture();app.advance_playtest()
	if not check(app.playtest.phase()=="rolled" and app.board.inventory_pack.carried,"locked drop still carried until commit"):return
	checkpoint("locked");app.save_game();check(app.last_save_result.ok,"actual Save action stores locked item turn")
	var locked:String=C.digest(app.playtest.save_data());app.load_game();check(app.last_load_result.ok and C.digest(app.playtest.save_data())==locked,"actual Load restores exact locked item focus/RNG")
	app.end_turn();await frames()
	if not check(app.playtest.phase()=="idle" and not app.board.inventory_pack.carried,"primary completion drops visible same pack exactly once"):return
	check(app.board.inventory_pack.reference.entity_revision==1 and app.playtest.state_copy().items.size()==1,"ground view observes real custody revision and single item")
	camera_to(origin);await frames()
	if not inspect_pack_from_inventory("co-located ground"):return
	check(app.target_label.text.contains("落地"),"ground target caption reflects real location")
	checkpoint("committed");await capture("native_ground_selected")
	# Ordinary movement leaves the ground pack anchored while the pawn travels.
	var target:Array=[];var best:int=999
	for cell in app.playtest.state_copy().hexes.values():
		var dq:int=cell.q-origin[0];var dr:int=cell.r-origin[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))<2:continue
		var route:Dictionary=app.playtest.movement_preview([cell.q,cell.r])
		if route.get("ok",false) and int(route.cost)<best:target=[cell.q,cell.r];best=int(route.cost)
	if not check(not target.is_empty() and best<=4,"bounded two-cell affordable route for distance test"):return
	var position_before:Vector3=app.board.inventory_pack.pack.global_position
	app.on_hex_selected(Vector2i(target[0],target[1]));if not sample("move"):return
	await wait_motion()
	check(app.board.inventory_pack.pack.global_position.is_equal_approx(position_before) and app.playtest.state_copy().items.item_travel_bundle.hex==origin,"dropped pack stays at exact location after real movement")
	camera_to(origin);app.set_map_dialogue_hidden(true);await frames();if not click_pack("distant ground"):return
	await capture("native_ground_after_departure");app.set_map_dialogue_hidden(false)
	before=C.bytes(app.playtest.state_copy());var rng:String=C.bytes(app.playtest.engine.save_data().rng)
	app.fill_generated_sample("pickup_item");app.end_turn();app.playtest_fixture()
	check(app.playtest.phase()=="awaiting_assessment" and C.bytes(app.playtest.state_copy())==before and C.bytes(app.playtest.engine.save_data().rng)==rng,"out-of-range pickup rejected without visible teleport or charge")
	app.cancel_pending()
	app.on_hex_selected(Vector2i(origin[0],origin[1]));if not sample("move"):return
	await wait_motion();camera_to(origin);await frames()
	if not inspect_pack_from_inventory("returned ground"):return
	if not sample("pickup_item"):return
	await frames()
	check(app.board.inventory_pack.carried and app.board.inventory_pack.reference.entity_revision==2 and app.selected_focus.entity_revision==2,"pickup and transient selection refresh same real pack")
	check(app.playtest.state_copy().items.size()==1 and app.playtest.state_copy().items.item_travel_bundle.quantity==1,"full journey never duplicates supply")
	await capture("native_picked_up")
	var f:=FileAccess.open(OUT+"native_checkpoints.json",FileAccess.WRITE);f.store_string(C.bytes(checkpoints));f.close()
func check_support_cases() -> void:
	var before:String=C.digest(app.playtest.save_data())
	var slope_hex:Array=[];var shore_hex:Array=[];var slope_score:float=-1.0
	for cell in app.playtest.state_copy().hexes.values():
		var hex:Array=[cell.q,cell.r]
		if not app.board.admitted_source.navigation.supported.get("%d,%d"%hex,false):continue
		var center:Vector3=app.board._source_position(hex)
		var h0:float=app.board.terrain_field.land_height(center+Vector3(.25,0,0))
		var h1:float=app.board.terrain_field.land_height(center-Vector3(.25,0,0))
		if absf(h1-h0)>slope_score:slope_score=absf(h1-h0);slope_hex=hex
		for direction in [Vector3(.70,0,0),Vector3(-.70,0,0),Vector3(0,0,.70),Vector3(0,0,-.70)]:
			var point:Vector3=center+direction
			if app.board.terrain_field.land_height(point)<=app.board.terrain_field.water_height(point):shore_hex=hex;break
	check(not slope_hex.is_empty() and slope_score>0.0001,"actual source provides a sloped dry support case")
	check(not shore_hex.is_empty(),"actual source provides a mixed shoreline support case")
	var evidence:Array=[]
	for hex in [slope_hex,shore_hex]:
		if hex.is_empty():continue
		var pose:Dictionary=app.board.inventory_pack.placement_for(hex)
		check(pose.get("footprint_verified",false) and pose.get("minimum_dry_clearance",0.0)>0.0001,"pack actual footprint wholly dry on case "+str(hex))
		check(pose.get("support_residual_spread",99.0)<=0.08*float(pose.get("scale",0.0)),"tilted support residual bounded relative to pack body "+str(hex))
		check(pose.get("covered_area",0.0)>=pose.get("footprint_area",1.0)-0.000001,"same PL mesh fully covers pack footprint "+str(hex))
		var public_pose:Dictionary=pose.duplicate(true)
		if pose.get("position") is Vector3:public_pose.position=[pose.position.x,pose.position.y,pose.position.z]
		evidence.append({"hex":hex,"pose":public_pose})
	check(C.digest(app.playtest.save_data())==before,"slope/shore placement probes cannot mutate game state")
	var f:=FileAccess.open(OUT+"native_support_cases.json",FileAccess.WRITE);f.store_string(C.bytes(evidence));f.close()

func resume_locked() -> void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"native_checkpoints.json"))
	var restored:=Inventory.new()
	if not check(restored.load_file(OUT+"native_locked.json").ok and C.digest(restored.save_data())==expected.locked.digest,"new OS process restores exact locked pack transaction"):return
	app.generated_adventure=restored;app._switch_mode("generated");await frames()
	check(app.generated_mode and app.playtest.phase()=="rolled" and app.board.inventory_pack.carried,"fresh native view keeps uncommitted pack carried")
	app.end_turn();await frames()
	check(app.playtest.phase()=="idle" and not app.board.inventory_pack.carried and app.playtest.state_copy().items.item_travel_bundle.custody_revision==1,"fresh native locked result commits once to ground")
	var before:String=C.digest(app.playtest.save_data());app.complete_requested_turn()
	check(C.digest(app.playtest.save_data())==before,"duplicate UI completion does not duplicate restarted pack")
	camera_to(app.playtest.state_copy().actors.actor_player.hex);await frames();inspect_pack_from_inventory("restarted co-located ground");await capture("native_restart_ground")
func finish() -> void:
	var report:Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","phase":mode_,"checks":checks,"failures":failures}
	var f:=FileAccess.open(OUT+"native_"+mode_+"_report.json",FileAccess.WRITE);f.store_string(C.bytes(report));f.close()
	print("PACK_NATIVE_RESULT ",mode_," ",report.status," ",checks-failures.size(),"/",checks)
	if is_instance_valid(app):app.queue_free();await frames(3)
	quit(0 if failures.is_empty() else 1)

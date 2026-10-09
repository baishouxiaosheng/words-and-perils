extends SceneTree
## Independent whole-Main native mouse/keyboard QA. No scripted game actions.
## Starts the ordinary default. The reviewer enters V3 using its visible menu.
## F8 writes evidence. F9/normal close finishes and verifies coast preservation.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var app: Control
var out := ""
var initial_coast := ""
var last_f8 := false
var last_f9 := false
var finishing := false
var capture_busy := false
var observed_v3 := false
var records: Array = []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	run.call_deferred()
func authority_data(adapter:RefCounted) -> Dictionary:
	return adapter.save_data() if adapter.has_method("save_data") else adapter.engine.save_data()
func frames(n:int=5) -> void:
	for i in range(n): await process_frame
func run() -> void:
	if out.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("FOGBANK_QA_WINDOWED","1")
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);await frames()
	if not app.coast_mode or app.generated_v3_mode:printerr("MANUAL_V3_DEFAULT_CHANGED");quit(2);return
	initial_coast=C.digest(authority_data(app.playtest))
	auto_accept_quit=false;root.close_requested.connect(finish);process_frame.connect(poll_keys)
	await record("default_coast")
	print("MANUAL_V3_READY F8=capture F9=finish default_coast=",initial_coast)
func poll_keys() -> void:
	if finishing:return
	var f8:=Input.is_physical_key_pressed(KEY_F8);var f9:=Input.is_physical_key_pressed(KEY_F9)
	if f8 and not last_f8:record.call_deferred("manual_"+str(records.size()))
	if f9 and not last_f9:finish.call_deferred()
	last_f8=f8;last_f9=f9
func record(label_:String) -> void:
	if capture_busy or not is_instance_valid(app):return
	capture_busy=true
	await RenderingServer.frame_post_draw
	var picture:Image=root.get_texture().get_image();var path:=out.path_join(label_+".png");var png_result:=picture.save_png(path)
	var authority:Dictionary=authority_data(app.playtest);var state:Dictionary=app.playtest.state_copy();var action:Dictionary=app.playtest.action_copy()
	var row:Dictionary={"label":label_,"path":path,"png_saved":png_result==OK,"native_root":[root.size.x,root.size.y],"world_raster":[app.viewport.size.x,app.viewport.size.y],"png_size":[picture.get_width(),picture.get_height()],"coast_mode":app.coast_mode,"v3_mode":app.generated_v3_mode,"authority_hash":C.digest(authority),"state_hash":C.digest(state),"action_hash":C.digest(action),"phase":app.playtest.phase(),"turn":state.get("turn",-1),"selected_focus":app.selected_focus.duplicate(true),"frozen_focus":action.get("focus",{}).duplicate(true),"target_caption":app.target_label.text,"details_visible":app.focus_details_dialog.visible,"details":app.focus_details_text.text,"inventory_visible":app.inventory_dialog.visible,"advanced_visible":app.advanced_dialog.visible,"intent":app.goal.text,"board_error":app.board.load_error,"last_save":app.last_save_result.duplicate(true),"last_load":app.last_load_result.duplicate(true),"source":state.get("generated_world",{}).duplicate(true),"actor":state.get("actors",{}).get("actor_player",{}).duplicate(true)}
	if app.generated_v3_mode:
		observed_v3=true
		row["support_pose"]=app.board.token_support_metrics.duplicate(true)
		row["camera"]={"overview":app.board.overview_mode,"size":app.board.camera.size,"position":[app.board.camera.position.x,app.board.camera.position.y,app.board.camera.position.z]}
		var save_path:=out.path_join(label_+"_authority.json");var file:=FileAccess.open(save_path,FileAccess.WRITE);file.store_string(C.bytes(authority));file.close();row["authority_file"]=save_path
	if app.coast_adventure!=null:row["coast_preserved"]=C.digest(authority_data(app.coast_adventure))==initial_coast
	records.append(row);write_report(false);capture_busy=false
func write_report(done:bool) -> void:
	var file:=FileAccess.open(out.path_join("manual_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":done,"scope":"Independent real-window pointer/keyboard V3 opt-in interaction with ordinary coast default; actions are performed only through visible UI","initial_coast_authority":initial_coast,"observed_v3":observed_v3,"records":records},"\t"));file.close()
func finish() -> void:
	if finishing:return
	finishing=true
	while capture_busy:await process_frame
	await record("final");write_report(true)
	var good:bool=observed_v3 and app.board.load_error.is_empty() and app.coast_adventure!=null and C.digest(authority_data(app.coast_adventure))==initial_coast
	print("MANUAL_V3_COMPLETE records=",records.size()," observed_v3=",observed_v3," default_coast_preserved=",good)
	app.queue_free();await frames(4);quit(0 if good else 1)

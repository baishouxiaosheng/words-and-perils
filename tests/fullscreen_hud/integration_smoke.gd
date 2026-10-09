extends SceneTree
## Bounded final-package validation: real entry point, one default turn, one
## locked pending save/reload, and native evidence. No scientific re-audit.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/integration_update_20261002/"
var scene
var count:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	count+=1
	if not value: failures.append(message);printerr("INTEGRATION_FAIL: "+message)
func _initialize()->void:call_deferred("run")
func settle()->void:
	for i in range(8):await process_frame
func capture(name_:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1920,1080)
	scene=Main.instantiate();root.add_child(scene);await settle()
	check(scene.coast_mode,"main entry enters coast")
	check(scene.board.load_error.is_empty(),"base world and river resources load")
	check(scene.board.tiles.size()==1801 and scene.board.token_nodes.size()==3,"base world cells and characters intact")
	var view=scene.board.world_view
	check(is_instance_valid(view.clear_daylight_profile),"two-tone profile instantiated")
	if is_instance_valid(view.clear_daylight_profile):check(view.clear_daylight_profile.last_error.is_empty() and view.clear_daylight_profile.enabled,"contact cache dependency verified and enabled")
	check(is_instance_valid(view.faceted_mountains),"mountain cache instantiated")
	if is_instance_valid(view.faceted_mountains):check(view.faceted_mountains.last_error.is_empty() and view.faceted_mountains.triangles==int(view.faceted_mountains.manifest.triangles) and view.faceted_mountains.triangles>0 and view.faceted_mountains.triangles<=25000,"mountain cache verified")
	check(scene.board_container.get_global_rect()==Rect2(0,0,1920,1080),"world fills native 1080p window")
	var initial:=C.bytes(scene.playtest.state_copy())
	scene.goal.text="我看看附近有什么。";scene.end_turn();scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.state_copy())==initial,"double submit remains offline and leaves facts intact")
	scene.cancel_pending();check(C.bytes(scene.playtest.state_copy())==initial,"cancel remains safe")
	scene.fill_coast_sample("observe");scene.end_turn();scene.playtest_fixture()
	check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==1,"single end-turn completes exactly one accepted action")
	var one:=C.bytes(scene.playtest.state_copy());scene.end_turn()
	check(C.bytes(scene.playtest.state_copy())==one,"empty repeated primary does not duplicate commit")
	# Save an already locked pending action, then restore the exact result.
	scene.fill_coast_sample("move");scene.submit_action();scene.playtest_fixture();scene.advance_playtest()
	check(scene.playtest.phase()=="rolled","pending result is locked")
	var locked:=C.bytes(scene.playtest.action_copy())
	scene.save_game();scene.load_game()
	check(C.bytes(scene.playtest.action_copy())==locked,"save/load preserves pending result and RNG")
	scene.end_turn()
	check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==2,"restored turn completes once through primary button")
	check(scene.board.world_state==scene.playtest.state_copy(),"rendered and saved authoritative state agree")
	# Fresh visual state for deliverable screenshot, without overwriting user saves.
	scene.reset_playtest();await settle()
	scene.toggle_overview();await capture("01_full_map_integrated_1920")
	scene.set_map_dialogue_hidden(false)
	view.overview=false;view.scope_name="mountain_integrated"
	view.target=Vector3(5.2,1.6,14);view.distance=18;view.pitch=.64;view.yaw=.18;scene.board.camera.size=13.0;view._update_camera()
	await capture("02_mountain_hud_integrated_1920")
	var report={"passed":count-failures.size(),"total":count,"failures":failures,"display":DisplayServer.get_name(),"viewport":[root.size.x,root.size.y],"profile":view.clear_daylight_profile.report() if is_instance_valid(view.clear_daylight_profile) else {},"mountains":view.faceted_mountains.report() if is_instance_valid(view.faceted_mountains) else {},"isolated_user_data":OS.get_environment("XDG_DATA_HOME")}
	var f:=FileAccess.open(OUT+"verification.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("INTEGRATED_PACKAGE ",count-failures.size(),"/",count)
	scene.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

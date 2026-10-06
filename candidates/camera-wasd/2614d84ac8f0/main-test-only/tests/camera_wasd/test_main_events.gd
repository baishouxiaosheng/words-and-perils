extends SceneTree
## Real Main and real GUI focus with synthetic Godot InputEventKey dispatch.
## Headless window focus is a backend stub; no OS keyboard/display-focus claim.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const MAIN_SHA="b17a361b0ee8a1c671b90e2bd3a0d5774a373a66ecc618042d2bbf7c8f0aa32c"
const MODULE_SHA="c26abf87dd3ff1d0b76b318a6887fa5ca9c6342571d128f0ef2662d9a6a29ef0"
const KEYS=[KEY_W,KEY_A,KEY_S,KEY_D]
var checks:=0
var failures:Array=[]
var event_count:=0
var samples:Array=[]
var scene:Control
var pan:Node
var camera:Camera3D
var before_authority:=""
var saved_goal:=""
var eligibility:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->bool:
	checks+=1
	if not ok:failures.append(label_);printerr("WASD_MAIN_FAIL ",label_)
	return ok
func frames(count:int=3)->void:
	for _i in range(count):await process_frame
func key(code:int,down:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.echo=false
	event.unicode={KEY_W:119,KEY_A:97,KEY_S:115,KEY_D:100}.get(code,0) if down else 0
	Input.parse_input_event(event);Input.flush_buffered_events();event_count+=1
func release_all()->void:
	for code in KEYS:key(code,false)
func tick(delta:float=0.25)->void:
	# Controlled dt, actual production _process reading actual Input key state
	# and actual Main/Control tree. No allowed=false/helper latch injection.
	pan.call("_process",delta)
func near(actual:Vector3,expected:Vector3,label_:String)->void:check(actual.distance_to(expected)<0.0001,label_)
func sample(label_:String)->void:
	samples.append({"label":label_,"camera":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"physical_w":Input.is_physical_key_pressed(KEY_W),"api_modal_open":scene._api_settings_open()})
func clear_focus()->void:
	scene.goal.release_focus();root.gui_release_focus();scene.board.get_viewport().gui_release_focus()
func move_check(codes:Array,label_:String)->void:
	release_all();tick();var before:Vector3=camera.global_position
	var forward:Vector3=-camera.global_basis.z;forward.y=0.0;forward=forward.normalized()
	var right:Vector3=camera.global_basis.x;right.y=0.0;right=right.normalized()
	var direction:=Vector3.ZERO
	for code in codes:
		key(code,true)
		var selected_direction:Vector3={KEY_W:forward,KEY_S:-forward,KEY_D:right,KEY_A:-right}[code]
		direction+=selected_direction
	check(Input.is_physical_key_pressed(codes[0]),label_+": synthetic physical key state reached Input")
	tick()
	near(camera.global_position,before+direction.normalized()*1.5,label_+": real camera moves along independently projected ground direction at 6 units/s")
	check(is_equal_approx(camera.global_position.y,before.y),label_+": global height unchanged")
	sample(label_);release_all();var stopped:Vector3=camera.global_position;tick();near(camera.global_position,stopped,label_+": release stops motion")
func run()->void:
	var expected:=OS.get_environment("FOGBANK_WASD_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/")!=expected:
		printerr("WASD_MAIN_REFUSED isolated user directory mismatch");quit(2);return
	if FileAccess.file_exists("user://r24_coast_adventure_save.json") or FileAccess.file_exists("user://r24_coast_adventure_save.json.narration.json"):
		printerr("WASD_MAIN_REFUSED fresh test user directory required");quit(2);return
	if not check(FileAccess.get_sha256("res://main.gd")==MAIN_SHA and FileAccess.get_sha256("res://view/tabletop_interaction/wasd_camera_pan.gd")==MODULE_SHA,"exact API Main plus one-line WASD and module source"):
		quit(2);return
	root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
	scene=Main.instantiate();root.add_child(scene);current_scene=scene;await frames(6)
	if not check(scene.coast_mode and scene.playtest!=null and Bundle.ready(),"real Main admitted default production Coast bundle"):
		finish();return
	var state:Dictionary=scene.playtest.state_copy();var catalog:Dictionary=Bundle.document("catalog")
	check(state.hexes.size()==1801 and state.world_id==catalog.world_id and state.actors.actor_player.scene_id=="scene_coast" and scene.playtest.engine.rule_id()=="coast_release/v1","real 1801-cell current bundle/world/Coast profile without fallback")
	pan=scene.get_node_or_null("WASDCameraPan");camera=scene.board.camera
	if not check(pan!=null and pan.get_script().resource_path=="res://view/tabletop_interaction/wasd_camera_pan.gd" and camera!=null,"one actual installed production controller and real board camera"):
		finish();return
	# Disable only autonomous test timing; _input remains enabled and all input
	# events are dispatched through Input/Viewport into the installed controller.
	pan.set_process(false)
	clear_focus();await frames();release_all();tick()
	eligibility={"host_can_process":scene.can_process(),"root_focused":root.has_focus(),"board_visible":scene.board.is_visible_in_tree(),"board_input_enabled":scene.board.is_processing_input(),"camera_current":camera.is_current(),"api_modal_open":scene._api_settings_open(),"window_count":pan._windows.size()}
	if not check(pan.call("_pan_allowed"),"unfocused real Main is eligible for camera input under this display backend"):
		finish();return
	before_authority=C.bytes(scene.playtest.engine.save_data());saved_goal=scene.goal.text
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured(),"fresh Main has no API configuration or enabled connection")
	move_check([KEY_W],"W");move_check([KEY_A],"A");move_check([KEY_S],"S");move_check([KEY_D],"D");move_check([KEY_W,KEY_D],"W+D normalized diagonal")
	# Use the existing real mouse-orbit method; the projected forward must change.
	var basis_before:Basis=camera.global_basis
	scene.board.world_view.orbit(PI/2.0,0.0)
	check(not camera.global_basis.is_equal_approx(basis_before),"existing orbit changes the actual camera heading")
	move_check([KEY_W],"W after existing orbit")
	scene.goal.grab_focus();await frames();check(scene.goal.has_focus(),"actual Main TextEdit owns GUI focus")
	var before:Vector3=camera.global_position;key(KEY_W,true);tick();near(camera.global_position,before,"focused TextEdit blocks real dispatched W")
	check(scene.goal.text!=saved_goal,"real focused TextEdit receives typed character instead of camera handling")
	scene.goal.release_focus();await frames();tick();near(camera.global_position,before,"leaving text focus while W held does not resume camera")
	release_all();tick();move_check([KEY_W],"fresh W after TextEdit release")
	# The actual API Window and its actual endpoint LineEdit, with no key reading.
	scene.show_ai_connection();await frames(3)
	var panel:Control=scene.runtime_connection_panel;var field:Dictionary=panel.role_fields.narration
	field.toggle.button_pressed=true;field.advanced.show();panel.dialog_scroll.ensure_control_visible(field.endpoint);await frames(3);field.endpoint.grab_focus();await frames()
	check(panel.settings_dialog.visible and scene._api_settings_open() and field.endpoint.has_focus(),"actual API modal and actual LineEdit focus are active")
	before=camera.global_position;key(KEY_W,true);tick();near(camera.global_position,before,"API modal and focused LineEdit block dispatched W")
	field.endpoint.release_focus();panel.close_settings();tick();near(camera.global_position,before,"API closing-frame guard prevents immediate camera movement")
	await frames(3);tick();near(camera.global_position,before,"closing modal while W held requires release before resume")
	clear_focus();release_all();tick();move_check([KEY_W],"fresh W after API close")
	# Actual GUI popup state is discovered by the production Window watcher.
	scene.tools_menu.get_popup().popup(Rect2i(20,20,300,300));await frames();before=camera.global_position;key(KEY_D,true);tick();near(camera.global_position,before,"actual PopupMenu blocks dispatched D")
	scene.close_tool_menus();await frames();tick();near(camera.global_position,before,"closing popup with held key cannot resume")
	release_all();tick();move_check([KEY_D],"fresh D after menu release")
	# Actual SceneTree pause, followed by fresh-release requirement.
	key(KEY_W,true);tick();before=camera.global_position;paused=true;tick();near(camera.global_position,before,"paused SceneTree blocks camera")
	paused=false;tick();near(camera.global_position,before,"unpause does not resume a held key");release_all();tick();move_check([KEY_W],"fresh W after pause")
	# Headless has no real OS focus; deliver the genuine Window signal to the
	# installed listener and verify its latch, without claiming an OS app switch.
	key(KEY_W,true);tick();before=camera.global_position;root.focus_exited.emit();tick();near(camera.global_position,before,"injected real Window focus-exited signal clears held movement")
	release_all();tick();move_check([KEY_W],"fresh W after injected focus-out")
	key(KEY_W,true);key(KEY_A,true);key(KEY_S,true);key(KEY_D,true);before=camera.global_position;tick();near(camera.global_position,before,"opposed real dispatched keys cancel")
	release_all();tick();scene.goal.text=saved_goal
	check(C.bytes(scene.playtest.engine.save_data())==before_authority,"all camera/UI events preserve complete engine facts actor position resources RNG and history")
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured() and not scene.runtime_ai.busy(),"no API configuration or request started by camera/focus/modal events")
	finish()
func finish()->void:
	paused=false;release_all()
	var report:Dictionary={"schema":"camera_wasd_real_main_events/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"display_backend":DisplayServer.get_name(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"module_sha256":FileAccess.get_sha256("res://view/tabletop_interaction/wasd_camera_pan.gd"),"initial_eligibility":eligibility,"synthetic_key_events":event_count,"samples":samples,"network_calls":0,"scope":"actual Main/Control/InputEventKey dispatch with controlled dt; no OS physical keyboard or true OS focus loss, no rendered visual acceptance","headless_focus_is_stub":DisplayServer.get_name()=="headless","automatic_frame_timing_disabled_for_exact_dt":true}
	var path:=OS.get_environment("FOGBANK_WASD_TEST_REPORT")
	if path.is_empty():path="user://camera_wasd_main_events.json"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:printerr("WASD_MAIN_REPORT_WRITE_FAILED");quit(2);return
	f.store_string(JSON.stringify(report,"\t"));f.close()
	if is_instance_valid(scene):scene.free()
	print("WASD_MAIN_EVENTS_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

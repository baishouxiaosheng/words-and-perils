extends SceneTree
## Observer only after initial draft setup. Menu, guest actions, return and final
## host text input must come from bound native OS input, never emitted signals.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Custody=preload("res://view/generated_v3_river_entry/host_custody.gd")
const OUT="res://artifacts/generated_v3_river_entry/pointer/"
const DRAFT="原旅程草稿：先观察海岸，再决定下一步。"
class InputProbe extends Node:
	var host:Control
	var events:Array=[]
	func _input(event:InputEvent)->void:
		if not event is InputEventKey and not event is InputEventMouseButton:return
		var guest_open:bool=host!=null and host.river_entry_controller!=null and host.river_entry_controller.session.is_open()
		var focus:Control=get_viewport().gui_get_focus_owner()
		var row:Dictionary={"ticks_ms":Time.get_ticks_msec(),"pressed":event.pressed,"guest_open":guest_open,"focus_class":focus.get_class() if focus!=null else "none"}
		if event is InputEventKey:
			row.merge({"kind":"key","keycode":event.keycode,"physical_keycode":event.physical_keycode,"echo":event.echo,"accept_enter":event.keycode in [KEY_ENTER,KEY_KP_ENTER]})
		else:row.merge({"kind":"mouse","button":event.button_index,"position":[event.position.x,event.position.y]})
		events.append(row)
var app:Control
var input_probe:InputProbe
var failures:Array=[]
var stages:Array=[]
var entered:=false
var guest_committed:=false
var returned:=false
var menu_seen:=false
var host_bytes:=""
var host_ui:=""
var host_camera:Transform3D
var guest_save_hash:=""
func _initialize()->void:run.call_deferred()
func frames(count:int=3)->void:
	for _i in range(count):await process_frame
func write_json(name_:String,value:Dictionary)->void:
	FileAccess.open(OUT+name_,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true))
func center(control:Control)->Array:
	var p:Vector2=root.get_final_transform()*control.get_global_rect().get_center()
	return [p.x,p.y]
func button_named(node:Node,text_:String)->Button:
	if node is Button and node.text==text_:return node
	for child in node.get_children():
		var found:=button_named(child,text_)
		if found!=null:return found
	return null
func check(value:bool,label_:String)->void:
	if not value:failures.append(label_);printerr("RIVER_POINTER_FAIL ",label_)
func capture(name_:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func stage(name_:String,data:Dictionary={})->void:
	stages.append({"name":name_,"ticks_ms":Time.get_ticks_msec(),"data":data})
	write_json("progress.json",{"stages":stages,"failures":failures})
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,800)
	app=Main.instantiate();root.add_child(app)
	input_probe=InputProbe.new();input_probe.host=app;input_probe.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(input_probe)
	await frames(12)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,800);await frames(8)
	check(DisplayServer.get_name()!="headless","native renderer required")
	var state:Dictionary=app.playtest.state_copy()
	check(app.coast_mode and app.board.tiles.size()==1801 and state.world_id=="natural_coast_shore_v03_adventure" and state.generated_world.bundle_id=="natural-shore-v03-2f6a1a215a0d44a374f01c4a","actual full1801 accepted coast required")
	app.set_player_intent(DRAFT)
	var custody:Dictionary=Custody.capture(app.playtest)
	check(custody.ok,"real coast custody capability")
	host_bytes=C.bytes(custody.snapshot);host_ui=C.bytes(app._river_entry_ui_snapshot());host_camera=app.board.camera.transform
	check(not host_bytes.is_empty() and not host_ui.is_empty(),"nonempty canonical host and focus witnesses")
	if not failures.is_empty():finish();return
	await capture("01_default_main")
	write_json("targets.json",{"scope":"coordinates relative to actual game window; no synthetic input","menu":center(app.tools_menu),"host_goal":center(app.goal),"window":[root.size.x,root.size.y]})
	stage("await_real_menu")
	var started:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<150000:
		await frames(2)
		var entry:Node=app.river_entry_controller
		if not menu_seen and app.advanced_menu.visible:
			menu_seen=true;await capture("02_advanced_menu");stage("real_advanced_menu_visible",{"river_item_index":app.advanced_menu.get_item_index(app.RIVER_EXPERIMENT_MENU_ID)})
		if entry!=null and entry.session.is_open() and entry.view!=null and not entered:
			entered=true
			check(menu_seen,"entry follows real visible advanced menu")
			check(app.process_mode==Node.PROCESS_MODE_DISABLED and app.viewport.gui_disable_input and app.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"background input and drawing are parked")
			check(C.bytes(Custody.capture(app.playtest).snapshot)==host_bytes and C.bytes(app._river_entry_ui_snapshot())==host_ui and app.board.camera.transform==host_camera,"entry preserves actual host authority focus draft and camera")
			var view:Control=entry.view
			var choose:=button_named(view,"选择相邻干地（仅选择）");var back:=button_named(entry,"返回原旅程")
			check(choose!=null and back!=null,"visible choose and return controls exist")
			check(view.has_focus() and not back.has_focus(),"new view focuses a neutral container, not return navigation")
			write_json("guest_targets.json",{"choose_neighbor":center(choose),"move_example":center(view.example_buttons[0]),"assess":center(view.assess_button),"apply":center(view.apply_button),"back":center(back)})
			await capture("03_river_overlay");stage("await_real_guest_action")
		if entered and entry!=null and entry.session.is_open() and int(entry.session.river.state_copy().turn)==1 and not guest_committed:
			guest_committed=true;guest_save_hash=C.digest(entry.session.river.save_data())
			check(C.bytes(Custody.capture(app.playtest).snapshot)==host_bytes and C.bytes(app._river_entry_ui_snapshot())==host_ui and app.board.camera.transform==host_camera,"guest OS action never alters background host or camera")
			await capture("04_guest_committed");stage("await_real_return",{"guest_turn":1,"guest_save_hash":guest_save_hash})
		if entered and guest_committed and entry!=null and not entry.session.is_open() and not returned:
			returned=true;await frames(6)
			check(C.bytes(Custody.capture(app.playtest).snapshot)==host_bytes and C.bytes(app._river_entry_ui_snapshot())==host_ui,"OS return preserves complete original journey and focus")
			check(app.process_mode!=Node.PROCESS_MODE_DISABLED and not app.viewport.gui_disable_input and app.viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED,"background processing input and drawing resume")
			check(entry.metrics.get("guest_view_released",false) and entry.metrics.get("guest_adapter_released",false),"guest resources release after OS return")
			await capture("05_returned_main");stage("await_real_host_typing",{"host_goal":center(app.goal),"metrics":entry.metrics})
		if entered and not guest_committed and entry!=null and not entry.session.is_open():
			failures.append("OS returned before the required guest action; input sequence incomplete")
			stage("early_return_before_guest_action",{"host_phase":app.playtest.phase(),"status":app.status_label.text})
			await capture("early_return_before_guest_action");finish();return
		if returned and app.goal.text==DRAFT+"x":
			check(C.bytes(Custody.capture(app.playtest).snapshot)==host_bytes,"restored host typing cannot spend an action")
			check(app.goal.has_focus(),"returned original text control accepts actual OS input")
			check(input_probe.events.any(func(row):return row.get("accept_enter",false) and not row.pressed and row.guest_open and row.focus_class=="Control"),"native Enter release is observed on the neutral guest container without returning")
			await capture("06_host_input_restored");stage("complete");finish();return
	failures.append("real OS menu/action/return/input sequence timed out");finish()
func finish()->void:
	write_json("native_input_events.json",{"scope":"actual native events observed by an always-process root sibling; no synthetic input","events":input_probe.events if input_probe!=null else []})
	write_json("report.json",{"ok":failures.is_empty() and returned and guest_committed,"failures":failures,"menu_seen":menu_seen,"entered":entered,"guest_committed":guest_committed,"returned":returned,"stages":stages,"host_save_hash":host_bytes.sha256_text(),"guest_save_hash":guest_save_hash,"scope":"actual OS menu entry, river action, return and resumed host typing; observer emits no input"})
	print("RIVER_ENTRY_OS_POINTER ","PASS" if failures.is_empty() and returned and guest_committed else "FAIL")
	quit(0 if failures.is_empty() and returned and guest_committed else 1)

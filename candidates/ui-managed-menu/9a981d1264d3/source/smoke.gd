extends SceneTree
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var app
var failures:Array=[]
var checks:=0
var finished:=false
var started:int=Time.get_ticks_msec()
func _initialize()->void:run.call_deferred()
func _process(_delta:float)->bool:
	if not finished and Time.get_ticks_msec()-started>150000:finish("Menu focused check exceeded 150 seconds")
	return false
func frames(n:int)->void:
	for _i in range(n):await process_frame
func expect(value:bool,label_:String)->void:
	checks+=1
	if not value:failures.append(label_)
func key(code:int)->void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true;Input.parse_input_event(e)
	await frames(1);e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=false;Input.parse_input_event(e);await frames(1)
func finish(error:String="")->void:
	if finished:return
	finished=true
	if not error.is_empty():failures.append(error)
	var r={"schema":"managed_menu_focused/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"scope":"One actual tools-menu hierarchy through root Input events, Back, delayed original API command once, closing input lock, outside dismissal, complete authority preserved. Configuration-driven shared preset Window. No full menu matrix or performance claim."}
	var f=FileAccess.open(OS.get_environment("MENU_MOTION_OUTPUT").path_join("report.json"),FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(r,"\t"));f.close()
	print("MANAGED_MENU_RESULT ",r.ok," checks ",checks," failures ",JSON.stringify(failures))
	if is_instance_valid(app):app.free()
	quit(0 if failures.is_empty() else 1)
func run()->void:
	root.gui_embed_subwindows=true;app=Main.instantiate();root.add_child(app);current_scene=app;await frames(12)
	var authority:String=C.bytes(app.playtest.engine.save_data())
	var manager=app.ui_presenter.menus
	app.tools_menu.show_popup();await frames(12)
	expect(manager.is_open() and manager.surface.visible,"right HUD button opens managed tools menu")
	expect(not app.tools_menu.get_popup().visible,"original PopupMenu retains data without native auto-hide view")
	expect(manager.scroll.get_v_scroll_bar().max_value<=manager.scroll.get_v_scroll_bar().page,"short four-item tools menu expands all original entries without scrolling")
	expect(manager.surface.get_meta(&"ui_motion_kind")==&"small" and app.ui_presenter.entries[manager.surface.get_instance_id()].profile.travel==48.0,"menu uses actual small shared preset before registration")
	expect(Rect2(Vector2.ZERO,app.get_viewport_rect().size).encloses(Rect2(Vector2(manager.surface.position),Vector2(manager.surface.size))),"menu stays inside actual viewport safe bounds")
	await key(KEY_RIGHT);await frames(10)
	expect(manager.stack.size()==2 and manager.stack.back().source==app.adventure_menu,"root Right opens original Adventure submenu")
	await key(KEY_LEFT);await frames(10)
	expect(manager.stack.size()==1 and manager.is_open() and not manager.closing,"Left/Back keeps shared surface open at original parent")
	await key(KEY_DOWN);await key(KEY_DOWN);await key(KEY_RIGHT);await frames(10)
	expect(manager.stack.size()==2 and manager.stack.back().source==app.advanced_menu,"original Advanced submenu reached without changing command data")
	expect(manager.scroll.get_v_scroll_bar().max_value>manager.scroll.get_v_scroll_bar().page,"long original Advanced menu has real scroll")
	await key(KEY_DOWN);await key(KEY_DOWN)
	var count:={"api":0};app.advanced_menu.id_pressed.connect(func(id:int):
		if id==24:count.api+=1)
	await key(KEY_ENTER)
	expect(manager.closing and manager.surface.visible and manager.surface.gui_disable_input,"selected command locks visible menu throughout eased exit")
	expect(count.api==0,"original command waits for completed close")
	await key(KEY_ENTER);await frames(14)
	expect(count.api==1 and app.runtime_connection_panel.settings_dialog.visible,"original API command dispatches exactly once after close")
	expect(not manager.is_open() and not manager.surface.gui_disable_input,"menu closes and restores its input flags")
	app.runtime_connection_panel.close_settings();await frames(14)
	app.tools_menu.show_popup();await frames(12)
	var click:=InputEventMouseButton.new();click.position=Vector2(12,12);click.global_position=click.position;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;Input.parse_input_event(click);await frames(1)
	click=InputEventMouseButton.new();click.position=Vector2(12,12);click.global_position=click.position;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=false;Input.parse_input_event(click);await frames(14)
	expect(not manager.is_open(),"outside root Input click dismisses menu with focus handoff")
	expect(C.bytes(app.playtest.engine.save_data())==authority,"menu commands preserve complete authority/RNG/history")
	expect(not app.runtime_ai.busy() and not app.runtime_ai.client.any_role_configured(),"empty API configuration produces no provider work")
	finish()

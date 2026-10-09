extends SceneTree
const Main=preload("res://main.tscn")
const Rules=preload("res://view/ui_motion/presets.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var app
var checks:=0
var failures:Array=[]
var samples:Array=[]
var started:int=Time.get_ticks_msec()
var finished:=false
func _initialize()->void:run.call_deferred()
func _process(_delta:float)->bool:
	if not finished and Time.get_ticks_msec()-started>150000:push_error("Preset focused check exceeded 150 seconds");quit(2)
	return false
func frames(count:int)->void:
	for _i in range(count):await process_frame
func expect(ok:bool,label_:String)->void:
	checks+=1
	if not ok:failures.append(label_)
func run()->void:
	root.gui_embed_subwindows=true;app=Main.instantiate();root.add_child(app);current_scene=app;await frames(10)
	var authority:String=C.bytes(app.playtest.engine.save_data())
	var sizes:Array=[]
	for id:int in [9901,9902,9903,9904]:
		app.advanced_menu.id_pressed.emit(id);await frames(14)
		var frame:Window=app.get_meta(&"ui_preset_examples")[id]
		var rule:Dictionary=Rules.profile(frame.get_meta(&"ui_motion_kind"),frame.get_meta(&"ui_motion_options"))
		var bounds:Vector2=app.get_viewport_rect().size
		var expected:Rect2=Rules.geometry(frame.get_meta(&"ui_motion_kind"),bounds,Vector2.ZERO,frame.get_meta(&"ui_motion_options"))
		expect(frame.visible and frame.size==Vector2i(expected.size),"configured sample "+str(id)+" actual extent")
		expect(Rect2(Vector2.ZERO,bounds).encloses(Rect2(Vector2(frame.position),Vector2(frame.size))),"configured sample "+str(id)+" stays inside actual viewport")
		sizes.append(frame.size)
		if id==9903:
			var scroll:ScrollContainer=frame.get_child(0)
			expect(scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page,"large sample has real long-content scroll")
			scroll.scroll_vertical=180;await frames(12);expect(scroll.scroll_vertical>0,"large sample scroll moves actual contents")
		await frames(10)
		frame.call("request_motion_close")
		expect(frame.visible and frame.gui_disable_input,"configured sample "+str(id)+" blocks input throughout exit")
		await frames(14);expect(not frame.visible and not frame.gui_disable_input,"configured sample "+str(id)+" closes and restores input")
		samples.append({"id":id,"kind":frame.get_meta(&"ui_motion_kind"),"size":frame.size,"expected":expected,"duration":rule.duration})
	expect(sizes[0]!=sizes[1] and sizes[1]!=sizes[2] and sizes[1]!=sizes[3],"three type sizes and fourth config-only size are distinct")
	app.show_ai_connection();await frames(14);app.runtime_connection_panel.close_settings();await frames(14)
	expect(not app._api_settings_open() and app.board.is_processing_input(),"existing API cancel/input lock remains intact")
	expect(C.bytes(app.playtest.engine.save_data())==authority,"shared presentation preserves complete authority/RNG/history")
	expect(not app.runtime_ai.busy() and not app.runtime_ai.client.any_role_configured(),"no keys/configuration or provider work")
	finished=true
	var report={"schema":"ui_presets_focused/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"presets_sha256":FileAccess.get_sha256("res://view/ui_motion/presets.gd"),"samples":samples,"scope":"Three configured Window sizes and one new config-only size in actual Main, real long-content scroll, common eased exit/input restore, existing API cancel, complete authority unchanged. Authored connected menu signals; native menus still use original closing behavior. Not a full UI matrix or real-time performance claim."}
	var f=FileAccess.open(OS.get_environment("POPUP_MOTION_REPORT"),FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(report,"\t"));f.close()
	print("ACTUAL_UI_PRESETS_RESULT ",report.ok," checks ",checks," failures ",JSON.stringify(failures));app.free();quit(0 if failures.is_empty() else 1)

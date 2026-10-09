extends SceneTree
const Main=preload("res://main.tscn")
const Adapter=preload("res://view/generated_v3_inventory/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_inventory_ui/"
var app
var checks:=0
var failures:Array=[]
var screenshots:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("ITEM_LAYOUT_FAIL ",label)
func frames(n:int=5) -> void:
	for i in range(n):await process_frame
func capture(name_:String) -> void:
	await frames();await RenderingServer.frame_post_draw
	var image_:Image=root.get_texture().get_image();var path:String=OUT+name_+".png"
	check(image_.save_png(path)==OK,"write "+name_)
	var decoded:=Image.load_from_file(path);check(decoded.get_size()==Vector2i(1280,720) and root.size==Vector2i(1280,720) and app.viewport.size==Vector2i(1280,720),"actual root/world/PNG1280×720 "+name_)
	screenshots.append({"name":name_,"root":[root.size.x,root.size.y],"world":[app.viewport.size.x,app.viewport.size.y],"png":[decoded.get_width(),decoded.get_height()]})
func run() -> void:
	root.size=Vector2i(1280,720);app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	app.show_v3_setup();app.v3_inventory_choice.button_pressed=true
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:check(app.v3_inventory_choice.get_theme_color(key)==Color("2d403e"),"readable checkbox "+key)
	await capture("final_checked_setup");app.v3_setup_dialog.hide()
	var adapter:=Adapter.new();var loaded:Dictionary=adapter.load_file(OUT+"dropped.json")
	check(loaded.ok,"load exact previously tested ground checkpoint")
	if not loaded.ok:finish();return
	var before:String=C.bytes(adapter.save_data())
	app._switch_mode_to("generated_v3_inventory",adapter);await frames();app.select_generated_item("item_travel_bundle");await frames()
	check(app.focus_details_dialog.visible and app.resolved_focus.kind=="item" and not app.resolved_focus.facts.item.has("owner_actor_id"),"ground details are open")
	check(app.focus_details_text.get_content_height()<=app.focus_details_text.size.y,"entire ground text fits without clipped last line")
	check(app.focus_details_text.scroll_active,"long future descriptions remain explicitly scrollable")
	check(C.bytes(adapter.save_data())==before,"layout inspection is read-only")
	await capture("final_ground_details");finish()
func finish() -> void:
	var file:=FileAccess.open(OUT+"layout_report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":screenshots},"  "));file.close()
	print("V3_ITEM_LAYOUT ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)

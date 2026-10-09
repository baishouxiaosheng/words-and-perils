extends SceneTree
## Read-only native render of the actual mouse-run save. Uses UI callbacks to
## inspect, not physical-mouse coverage; that is recorded in manual_native_mouse.
const Main=preload("res://main.tscn")
const A=preload("res://view/generated_v3_equipment/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_equipment/inventory_render/"
var app:Node
var checks=0
var failures:Array=[]
var labels:Array=[]
var enemy_description=""
var player_description=""
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("INVENTORY_RENDER_FAIL ",label_)
	return value
func frames()->void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
func shot(name_:String)->void:
	await frames();root.get_texture().get_image().save_png(OUT+name_+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var a=A.new();var args:PackedStringArray=OS.get_cmdline_user_args()
	var loaded:Dictionary=a.load_file(args[0] if not args.is_empty() else a.default_save_path())
	if not check(loaded.ok,"actual native mouse save reload "+str(loaded)):finish();return
	var exact:String=C.bytes(a.save_data());var state:Dictionary=a.state_copy()
	if not check(state.items.item_raider_blade.owner_actor_id=="actor_player" and state.actors.actor_village_hostile.health.current==0,"real history contains downed looted owner"):finish();return
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1280,720));root.size=Vector2i(1280,720)
	DisplayServer.window_set_title("Equipment Inventory QA - Saved Offline History")
	app._switch_mode_to("generated_v3_equipment",a);await frames()
	if not check(app.generated_v3_equipment_mode and app.playtest==a and app.board.load_error.is_empty(),"final Main admits same source and renderer"):finish();return
	check(app.board.inventory_packs.size()==1 and app.board.inventory_packs.has("item_travel_bundle"),"only real bundle has a three-dimensional pack view")
	check(app.board.committed_effects.pending.is_empty() and app.board.committed_effects.active_count()==0,"inspection load has no combat replay")
	app.show_inventory();await frames()
	var equipped_rows=0
	for child in app.inventory_box.get_children():
		if child is Label:
			labels.append(child.text)
			if "已装备" in child.text:equipped_rows+=1
	var text_:String="\n".join(labels)
	check("苦叶短刃 ×1" in text_ and "潮岸木杖 ×1" in text_,"both conserved weapon rows visible in inspectable inventory")
	check(equipped_rows==1,"exactly one equipped marker")
	check(str(state.items[state.actors.actor_player.equipment.weapon].name)+" ×1 · 已装备" in text_,"equipped marker agrees with loaded authority")
	check(state.items.item_raider_blade.description in text_ and state.items.item_coast_staff.description in text_,"authored damage and poison descriptions shown unchanged")
	check("不能丢弃或转交" in app.inventory_note.text and "行礼包" in app.inventory_note.text,"new-profile note distinguishes bundle custody from weapon swapping")
	await shot("inventory_top")
	var scroll:ScrollContainer=app.inventory_box.get_parent();scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await shot("inventory_weapons")
	app.inventory_dialog.hide();app._apply_focus(a.enemy_reference());await frames()
	enemy_description=app._focus_details_description()
	check("短刃已由旅人取走" in enemy_description and "仍占据原格" in enemy_description,"current enemy details report durable transferred custody and occupancy")
	app.show_focus_details();await shot("looted_enemy_details");app.focus_details_dialog.hide()
	var player:Dictionary=state.actors.actor_player
	app._apply_focus({"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":player.hex.duplicate(),"scene_id":player.scene_id});await frames()
	player_description=app._focus_details_description()
	check("当前装备："+str(state.items[player.equipment.weapon].name) in player_description,"current player detail reports loaded equipped weapon")
	check(C.bytes(a.save_data())==exact,"every inspection preserves authority, receipts, pending and RNG byte-exact")
	finish()
func finish()->void:
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inventory_labels":labels,"enemy_description":enemy_description,"player_description":player_description,"mock_only":true,"network_calls":0,"scope":"final-Main read-only native rendering from exact earlier physical mouse-run save; not additional physical clicks"}
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EQUIPMENT_INVENTORY_RENDER ",checks," ",failures);quit(0 if failures.is_empty() else 1)

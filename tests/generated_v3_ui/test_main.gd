extends SceneTree
const Main=preload("res://main.tscn")
const Adapter=preload("res://view/generated_v3_adventure/adapter.gd")
const Inventory=preload("res://view/generated_inventory/adapter.gd")
const Contract=preload("res://core/world_generation_contract.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_ui/"
var app
var checks:=0
var failures:Array=[]
var shots:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("V3_UI_FAIL ",label)
	return ok
func frames(n:int=5) -> void:
	for i in range(n):await process_frame
func capture(label_:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var image_:Image=root.get_texture().get_image();var path:String=OUT+label_+".png"
	check(image_.save_png(path)==OK,"write "+label_)
	var decoded:=Image.load_from_file(path)
	check(decoded.get_size()==image_.get_size() and image_.get_size()==root.size,"decoded actual raster "+label_)
	shots.append({"name":label_,"root":[root.size.x,root.size.y],"world":[app.viewport.size.x,app.viewport.size.y],"png":[decoded.get_width(),decoded.get_height()]})
func select(hex:Array) -> void:app.on_hex_selected(Vector2i(hex[0],hex[1]))
func sample(kind:String) -> bool:
	var turn:int=app.playtest.state_copy().turn
	app.fill_generated_sample(kind);app.end_turn()
	if not check(app.playtest.phase()=="awaiting_assessment",kind+" waits for assessment"):return false
	app.playtest_fixture()
	return check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,kind+" exactly one committed turn")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,720)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames(5)
	check(app.is_map_preview() and not app.generated_v3_mode,"v3 is opt-in only")
	check(app.adventure_menu.get_item_index(16)>=0 and app.adventure_menu.get_item_index(17)>=0,"new and continue entries are accessible")
	app.show_v3_setup();await frames()
	check(app.v3_setup_dialog.visible and not app.v3_setup_dialog.get_ok_button().disabled and app.v3_setup_dialog.cancel_button_text=="取消","explicit readable setup opens")
	app.v3_radius_choice.select(1)
	await capture("setup")
	app.v3_setup_dialog.hide();await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_mode and app.playtest.ready().ok and app.board.load_error.is_empty(),"Main enters actual radius12 v3 board"):finish();return
	check(app.playtest.source.data.board_radius==12 and app.playtest.state_copy().hexes.size()==469,"selected radius/source preserved")
	check(app.generated_adventure==null and app.generated_v3_adventure==app.playtest,"v2 slot remains separate")
	app.show_help();check(app.latest_dialogue.text.contains("尚未接入实时AI") and not app.latest_dialogue.text.contains("gate/listen"),"V3 help matches actual action scope");app.toggle_journal()
	check(app.playtest_panel==app.generated_v3_panel and app.generated_v3_panel.fixture_button.text=="应用预设裁定","plain offline panel labels")
	var start:Array=app.playtest.state_copy().actors.actor_player.hex
	var neighbor:String=app.playtest.source.navigation.allowed["%d,%d"%start][0]
	var cell:Dictionary=app.playtest.state_copy().hexes[neighbor];var target:Array=[cell.q,cell.r]
	var initial:String=C.bytes(app.playtest.save_data())
	select(target);select(target);app.show_focus_details();await capture("target_details");app.focus_details_dialog.hide()
	check(C.bytes(app.playtest.save_data())==initial,"selection and details never mutate authority")
	check(app._focus_details_description().contains("生态：") and not app._focus_details_description().contains("q4096"),"V3 details use exact descriptors with readable labels")
	check(sample("move"),"move via real Main callbacks")
	await create_timer(1.1).timeout
	check(app.playtest.state_copy().actors.actor_player.hex==target and not app.board.presentation.actors.actor_player.moving,"committed movement lands once")
	await capture("move_arrival")
	select(target);sample("observe");sample("rest")
	check(app.playtest.state_copy().flags.observations==1,"observation persists")
	var committed:String=C.bytes(app.playtest.save_data())
	app.playtest.commit();check(C.bytes(app.playtest.save_data())==committed,"repeated commit leaves all authority unchanged")
	app.save_game();check(app.last_save_result.ok and FileAccess.file_exists(Adapter.GENERATED_SAVE),"separate V3 default save")
	app.playtest.save_file(OUT+"ui_committed.json")
	app.set_player_intent("仔细看看周围的路",false);app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and not app.playtest.fixture_available(),"free intent has no fabricated model decision")
	var frozen:String=C.bytes(app.playtest.action_copy().focus);var pending:String=C.bytes(app.playtest.save_data())
	select(start);check(C.bytes(app.playtest.action_copy().focus)==frozen,"next click cannot rewrite frozen focus")
	app.continue_generated_adventure();check(app.generated_v3_mode and C.bytes(app.playtest.save_data())==pending,"pending blocks cross-mode switch without data loss")
	app.save_game();app.load_game();check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==pending,"Main pending default save/load exact")
	app.cancel_pending();check(app.playtest.phase()=="idle","pending cancellation recovers")
	select(target);app.fill_generated_sample("observe");app.end_turn();app.playtest.prepare_fixture();app.playtest.roll_once();app.sync_playtest_request()
	var locked:String=C.bytes(app.playtest.save_data())
	app.save_game();app.load_game();check(app.last_load_result.ok and app.playtest.phase()=="rolled" and C.bytes(app.playtest.save_data())==locked,"Main locked default save/load exact")
	app.cancel_pending();check(C.bytes(app.playtest.save_data())==locked,"locked result cannot cancel or reroll")
	app.advance_playtest();app.advance_playtest();check(app.playtest.phase()=="idle","locked result resumes once")
	app.set_player_intent("下一次想仔细看看山坡",false);select(start)
	var v3_saved:String=C.bytes(app.playtest.save_data());var v3_draft:String=app.goal.text;var v3_focus:String=C.bytes(app.selected_focus)
	var legacy:RefCounted=Inventory.new();check(legacy.start_seeded(Contract.generate("v3-ui-regression","compact_coast",4)).ok,"old inventory still admits")
	app.generated_adventure=legacy;app._switch_mode("generated");await frames()
	check(not app.generated_v3_mode and app.playtest==legacy and app.playtest.has_method("item_reference"),"explicit old inventory slot is independent")
	app.set_player_intent("旧地图未提交的草稿",false);var old_draft:String=app.goal.text;var old_saved:String=C.bytes(legacy.save_data())
	app.continue_v3_adventure();await frames()
	check(app.generated_v3_mode and C.bytes(app.playtest.save_data())==v3_saved and app.goal.text==v3_draft and C.bytes(app.selected_focus)==v3_focus,"V3 state draft and target return intact")
	app.continue_generated_adventure();await frames()
	check(app.playtest==legacy and C.bytes(legacy.save_data())==old_saved and app.goal.text==old_draft,"old inventory state and draft return intact")
	app.continue_v3_adventure();app.clear_target();app.focus_player_view();await capture("exploration")
	app.toggle_overview();check(app.board.overview_mode,"overview entry works");await capture("whole_map");app.toggle_overview();check(not app.board.overview_mode,"overview returns to traveler")
	app.reset_playtest();check(app.generated_v3_adventure==app.playtest and app.playtest.state_copy().turn==0 and app.playtest.state_copy().actors.actor_player.hex==start,"restart keeps exact V3 source and deterministic spawn")
	check(C.bytes(legacy.save_data())==old_saved,"V3 restart cannot alter old inventory")
	app.playtest.save_file(OUT+"ui_initial.json")
	await capture("spawn_support")
	finish()
func finish() -> void:
	var result:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":shots}
	var file:=FileAccess.open(OUT+"main_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("V3_UI_RESULT ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)

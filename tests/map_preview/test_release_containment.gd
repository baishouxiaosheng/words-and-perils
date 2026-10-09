extends SceneTree
## Release UI containment, not a generated-world gameplay acceptance test.
const Main = preload("res://main.tscn")
const Legacy = preload("res://core/game_state.gd")
const Generator = preload("res://core/world_generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func encoded(value: Dictionary) -> String: return C.bytes(value)
func run() -> void:
	var app=Main.instantiate(); root.add_child(app)
	await process_frame; await process_frame
	check(app.coast_mode and app.playtest.phase()=="idle","default still opens the fixed-rule coast")
	check(app.radius_input.min_value==4 and app.radius_input.max_value==24,"preview retains seed/radius4–24 controls")
	check(app.adventure_menu.get_item_index(12)>=0,"preview has an explicit adventure-menu entry")
	var original: String=encoded(app.playtest.engine.save_data())
	app.set_player_intent("保留这段未提交的海岸草稿")
	app.show_map_preview_selector()
	check(app.world_dialog.visible and app.coast_mode,"opening selector does not switch or mutate coast")
	app.world_dialog.hide()
	check(encoded(app.playtest.engine.save_data())==original and app.goal.text=="保留这段未提交的海岸草稿","closing selector preserves coast and draft")
	app.end_turn()
	var pending:String=encoded(app.playtest.engine.save_data())
	var pending_action:String=app.active_action
	app.show_map_preview_selector(); app.request_world_build(true); app.switch_playtest(false)
	check(app.coast_mode and not app.world_dialog.visible and not app.world_build_busy,"pending coast action blocks every preview-entry route")
	check(encoded(app.playtest.engine.save_data())==pending and app.active_action==pending_action,"blocked preview preserves pending action/RNG/history exactly")
	app.cancel_pending()
	app.fill_coast_sample("observe"); app.submit_action(); app.playtest_fixture()
	check(app.playtest.phase()=="ready_roll","current fixed-rule sample can still prepare")
	app.advance_playtest()
	var locked:String=encoded(app.playtest.engine.save_data())
	app.switch_playtest(false); app.request_world_build(true)
	check(app.coast_mode and encoded(app.playtest.engine.save_data())==locked,"locked result cannot disappear into preview or reroll")
	app.advance_playtest(); app.advance_playtest()
	check(app.playtest.phase()=="idle","current fixed-rule sample still commits")
	app.set_player_intent("回到海岸后继续观察，不自动提交")
	app.on_hex_selected(Vector2i(-2,15))
	app.board.reset_camera()
	var coast:String=encoded(app.playtest.engine.save_data())
	var draft:String=app.goal.text
	var journal:String=app.journal.text
	var focus:Dictionary=app.selected_focus.duplicate(true)
	var camera_transform:Transform3D=app.board.camera.transform
	var camera_size:float=app.board.camera.size
	var coast_path:="user://preview_guard_coast.json"
	check(app.playtest.save_file(coast_path).ok,"test coast save is created in isolated test profile")
	var coast_file:PackedByteArray=FileAccess.get_file_as_bytes(coast_path)
	app.show_import(); app.show_import_file()
	var prior_epoch:int=app._mode_epoch
	app.switch_playtest(false)
	check(app.is_map_preview() and not app.coast_mode and app.runtime_ai._adapter==null,"legacy mode is detached read-only preview")
	check(app._mode_epoch>prior_epoch and not app.import_dialog.visible and not app.import_file_dialog.visible,"mode switch dismisses and invalidates old import dialogs")
	check(app.submit_button.disabled and not app.submit_button.visible and not app.goal.editable,"preview action controls are disabled and hidden")
	check(app.phase_label.text.contains("尚未接入当前行动规则"),"visible preview states current-rule limitation")
	app.update_turn_controls(); app.update_playtest_controls(); app._process(0.1)
	check(app.submit_button.disabled and app.export_button.disabled and app.import_button.disabled and app.demo_button.disabled,"frame/update callbacks never re-enable legacy authority")
	var generated:Dictionary=Generator.generate(726381,4,{"generator_version":Generator.BIOMES_VERSION})
	var candidate:Dictionary=app.prepare_world_candidate(generated)
	check(candidate.ok and app.commit_world_candidate(candidate.candidate).ok,"small deterministic biome snapshot still renders in preview")
	check(app.map_title.text.contains("预览") and app.map_title.text.contains("只读"),"generated map keeps visible read-only title")
	var tile:Dictionary=app.game.state.hexes.values()[0]
	for cell in app.game.state.hexes.values():
		if cell.get("landform")=="plateau": tile=cell; break
	app.on_hex_selected(Vector2i(tile.q,tile.r)); app.show_focus_details()
	check(not app.selected_focus.is_empty() and app.focus_details_text.text.contains("地貌：") and app.focus_details_text.text.contains("温度："),"picking and biome/climate detail remain available")
	app.focus_details_dialog.hide(); app.board.reset_camera(); app.board.focus_player()
	var preview:String=encoded(app.game.state)
	app.goal.text="不得执行的旧版意图"
	for method in ["end_turn","submit_action","submit_playtest","roll_dice","advance_playtest","complete_requested_turn","start_demo","_begin_demo","finish_demo","cancel_pending","restart_game","auto_export","export_request","show_import","show_import_file","import_decision","playtest_fixture","sync_playtest_request","reset_playtest"]:
		app.call(method)
		check(encoded(app.game.state)==preview and encoded(app.coast_adventure.engine.save_data())==coast,"backend blocks preview entrypoint: "+method)
	check(not app.apply_decision({"phase":"planning"}) and not app.apply_decision({"phase":"resolution","state_patch":{"actors":{}}}),"parsed legacy planning/resolution are rejected")
	check(not app.apply_playtest_reply({"schema_version":"ai_gm_assessment/v1"}),"direct current-engine reply cannot mutate retained coast from preview")
	var bogus_path:="user://preview_guard_delayed.json"
	var file:=FileAccess.open(bogus_path,FileAccess.WRITE); file.store_string('{"phase":"resolution"}'); file.close()
	app._on_import_file_selected(bogus_path); app._on_import_file_canceled(); app.on_file_selected("user://preview_guard_should_not_export.json")
	check(app.import_text.text.is_empty() and not app.import_dialog.visible and not FileAccess.file_exists("user://preview_guard_should_not_export.json"),"delayed import/cancel/export callbacks are inert")
	app.save_game()
	check(app.last_save_result.code=="READ_ONLY_PREVIEW" and FileAccess.get_file_as_bytes(coast_path)==coast_file,"preview cannot overwrite coast save")
	# The old core protocol remains usable as a test fixture, not through release UI.
	var legacy:=Legacy.new()
	var request:Dictionary=legacy.request("保留旧版待处理行动",Vector2i(1,-1)).request
	var planning:Dictionary={"schema_version":1,"action_id":request.action_id,"state_version":request.state_version,"phase":"planning","narration":"仅供回归测试","context":"read-only import fixture","needs_roll":true,"difficulty":10}
	check(legacy.apply_planning(planning).ok and legacy.roll_action(request.action_id,9).ok,"legacy core regression fixture still retains a locked roll")
	var legacy_path:="user://preview_guard_legacy_pending.json"
	check(legacy.save_to_file(legacy_path).ok,"pending legacy test fixture saved")
	var legacy_file:PackedByteArray=FileAccess.get_file_as_bytes(legacy_path)
	app.load_legacy_preview(legacy_path)
	check(app.last_load_result.ok and app.last_load_result.read_only and not app.last_load_result.pending_resumed,"legacy load explicitly reports inspection only")
	check(encoded(app.game.state)==encoded(legacy.state) and app.active_action.is_empty() and app.current_request.is_empty(),"loaded legacy pending state is exact but never resumed")
	app.roll_dice(); app.finish_demo(); app.apply_decision(planning); app.save_game(); app.cancel_pending()
	check(encoded(app.game.state)==encoded(legacy.state) and FileAccess.get_file_as_bytes(legacy_path)==legacy_file,"loaded pending actions cannot run, cancel or overwrite source file")
	app.seed_input.text="654321"; app.radius_input.value=24
	app.world_build_requested=true; app.world_build_seed=654321; app.world_build_radius=24
	app.begin_world_build(); app.begin_world_build()
	check(app.world_build_busy,"repeated build request is coalesced")
	app.return_from_map_preview()
	await process_frame; await process_frame
	check(app.coast_mode and not app.world_build_busy and encoded(app.playtest.engine.save_data())==coast,"Back cancels deferred generation without publishing over coast")
	check(app.goal.text==draft and app.journal.text==journal and app.selected_focus==focus,"coast draft/history/focus are restored exactly")
	check(app.board.camera.transform.is_equal_approx(camera_transform) and is_equal_approx(app.board.camera.size,camera_size),"coast camera returns to previous view")
	check(app.seed_input.text=="654321" and app.radius_input.value==24,"chosen preview seed and large-radius option survive roundtrip")
	app._on_import_file_selected(bogus_path); app._on_import_file_canceled(); app.import_decision()
	check(not app.import_dialog.visible and encoded(app.playtest.engine.save_data())==coast,"stale import callback remains rejected after returning to coast")
	app.switch_playtest(false); app.switch_playtest(false); app.return_from_map_preview(); app.return_from_map_preview()
	check(app.coast_mode and encoded(app.playtest.engine.save_data())==coast and app.journal.text==journal,"repeated preview/back calls preserve exact coast progress")
	app.switch_playtest(true)
	check(app.playtest_mode and not app.coast_mode,"laboratory remains a separate fixed-rule regression mode")
	app.switch_playtest(false)
	check(app.is_map_preview(),"laboratory can enter the same read-only preview")
	app.return_from_map_preview(); app.return_from_map_preview()
	check(app.coast_mode and encoded(app.playtest.engine.save_data())==coast and app.journal.text==journal,"Back labelled coast always returns coast, including laboratory→preview and repeated Back")
	check(FileAccess.get_file_as_bytes(coast_path)==coast_file and FileAccess.get_file_as_bytes(legacy_path)==legacy_file,"both save files remain byte-for-byte intact")
	print("READ-ONLY MAP PREVIEW CONTAINMENT ",checks-failures.size(),"/",checks)
	app.free(); quit(0 if failures.is_empty() else 1)

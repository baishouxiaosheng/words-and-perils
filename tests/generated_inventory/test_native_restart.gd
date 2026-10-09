extends SceneTree
## Actual Main and native renderer in two separate guarded OS processes.
const Main = preload("res://main.tscn")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Inventory = preload("res://view/generated_inventory/adapter.gd")
const Seeded = preload("res://view/generated_adventure/seeded_adapter.gd")
var app
var checks := 0
var failures: Array[String] = []
var phase_ := "create"
var output := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase_ = arg.trim_prefix("--phase=")
	output = OS.get_environment("FOGBANK_DELIVERY_EVIDENCE")
	run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
	return ok
func frames(n := 4) -> void:
	for _i in range(n): await process_frame
func sample(kind: String) -> bool:
	var before: int = app.playtest.state_copy().turn
	app.fill_generated_sample(kind); app.end_turn()
	if not check(app.playtest.phase() == "awaiting_assessment", kind + " button still waits for assessment"): return false
	app.playtest_fixture()
	return check(app.playtest.phase() == "idle" and int(app.playtest.state_copy().turn) == before + 1, kind + " fixed program commits exactly once")
func capture(name_: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name_ + ".png")
func labels_in(node: Node) -> String:
	var text := ""
	for child in node.get_children():
		if child is Label: text += child.text + "\n"
		text += labels_in(child)
	return text
func run() -> void:
	if not check(not output.is_empty(), "explicit isolated evidence path"): finish(); return
	app = Main.instantiate(); root.add_child(app); await frames()
	if not check(app.coast_mode and app.board.load_error.is_empty(), "fresh Main still opens full coast"): finish(); return
	if phase_ == "create": await create_locked()
	elif phase_ == "resume": await resume_locked()
	else: check(false, "known process phase")
	finish()
func create_locked() -> void:
	app.fill_coast_sample("observe"); app.end_turn(); app.playtest_fixture(); app.save_game()
	if not check(app.playtest.state_copy().turn == 1 and app.last_save_result.get("ok", false), "assessed coast observation and its separate save still work"): return
	var coast := C.digest(app.playtest.engine.save_data())
	app.set_player_intent("海岸草稿继续保留")
	app.switch_playtest(false)
	var envelope := Contract.generate("雪岸-行囊", "compact_coast", 4)
	var prepared: Dictionary = app.prepare_world_candidate(envelope.source)
	if not check(prepared.ok and app.commit_world_candidate(prepared.candidate).ok, "native preview uses admitted seed source"): return
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	var old := Seeded.new(); old.start_seeded(envelope); old.save_file()
	var old_hash := FileAccess.get_sha256(Seeded.SEEDED_SAVE)
	check(not app.generated_inventory_choice.button_pressed, "new carry option is an explicit opt-in")
	check(app.generated_inventory_choice.get_theme_color("font_pressed_color").r < 0.5 and app.generated_inventory_choice.get_theme_color("font_hover_pressed_color").r < 0.5, "checked opt-in text remains dark and readable")
	app.generated_inventory_choice.button_pressed = true
	app.world_dialog.popup_centered(); await capture("native_inventory_choice"); app.world_dialog.hide()
	await app.start_generated_from_preview(); await frames()
	if not check(app.generated_mode and app.playtest.save_data().schema_version == Inventory.INVENTORY_SAVE_SCHEMA, "existing start entry honors chosen carry option"): return
	check(app.runtime_ai._adapter == null and app.board.admitted_source == app.playtest.source and app.board.load_error.is_empty(), "same admitted renderer/authority and no live API")
	check(app.playtest.state_copy().actors.actor_player.inventory == ["item_travel_bundle"], "new adventure carries exactly one bundle")
	check(app.generated_panel.sample_buttons[3].visible and app.generated_panel.sample_buttons[4].visible and app.quest_label.text.contains("行礼包"), "new family reuses existing panel and accurate capability label")
	app.show_inventory(); await frames()
	check(labels_in(app.inventory_box).contains("行礼包 ×1") and labels_in(app.inventory_box).contains("随身物品"), "actual inventory UI shows carried stack")
	await capture("native_inventory_carried"); app.inventory_dialog.hide()
	var before := C.digest(app.playtest.save_data())
	var hex: Array = app.playtest.state_copy().actors.actor_player.hex
	app.on_hex_selected(Vector2i(hex[0], hex[1])); app.fill_generated_sample("drop_item")
	check(C.digest(app.playtest.save_data()) == before and not app.goal.text.contains("署名"), "selection and ordinary display draft cannot perform action")
	app.submit_action(); app.playtest_fixture(); app.advance_playtest()
	if not check(app.playtest.phase() == "rolled", "advanced controls lock assessed drop without committing"): return
	var locked := C.digest(app.playtest.save_data())
	check(app.playtest.state_copy().actors.actor_player.inventory == ["item_travel_bundle"], "locked drop still carries original item")
	app.return_from_map_preview(); check(app.generated_mode and C.digest(app.playtest.save_data()) == locked, "locked turn blocks world switch without loss")
	app.save_game()
	check(app.last_save_result.get("ok", false) and FileAccess.file_exists(Inventory.INVENTORY_SAVE), "main saves separate inventory profile")
	check(FileAccess.get_sha256(Seeded.SEEDED_SAVE) == old_hash and C.digest(app.coast_adventure.engine.save_data()) == coast, "new save cannot overwrite old v2 or coast")
	var expected := {"locked": locked, "rng": app.playtest.engine.save_data().rng, "coast": coast, "source_hash": envelope.source.content_hash, "old_hash": old_hash, "save_hash": FileAccess.get_sha256(Inventory.INVENTORY_SAVE), "hex": hex}
	var file := FileAccess.open(output + "/native_expected.json", FileAccess.WRITE); file.store_string(C.bytes(expected)); file.close()
func resume_locked() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/native_expected.json"))
	app.load_game(); await frames()
	if not check(app.last_load_result.get("ok", false) and C.digest(app.playtest.engine.save_data()) == expected.coast, "fresh process restores original coast"): return
	app.set_player_intent("第二进程海岸草稿")
	var draft: String = app.goal.text; var journal: String = app.journal.text
	var coast_object: RefCounted = app.playtest
	check(FileAccess.get_sha256(Inventory.INVENTORY_SAVE) == expected.save_hash, "locked inventory file survives process boundary exactly")
	app.continue_generated_adventure(); await frames()
	if not check(app.generated_mode and app.playtest.phase() == "rolled", "Continue picks exact saved inventory profile without upgrading v2"): return
	check(C.digest(app.playtest.save_data()) == expected.locked and C.bytes(app.playtest.engine.save_data().rng) == C.bytes(expected.rng), "pending result/context/profile/source/RNG restored exactly")
	check(app.playtest.source.identity.content_hash == expected.source_hash and app.board.load_error.is_empty(), "readmitted exact source renders successfully")
	app.end_turn(); await frames()
	if not check(app.playtest.phase() == "idle" and app.playtest.state_copy().turn == 1, "main completes locked drop once"): return
	var item: Dictionary = app.playtest.state_copy().items.item_travel_bundle
	check(not item.has("owner_actor_id") and C.bytes(item.hex) == C.bytes(expected.hex) and app.playtest.state_copy().actors.actor_player.inventory.is_empty(), "same bundle now lies at exact prior feet")
	var committed := C.digest(app.playtest.save_data()); app.complete_requested_turn()
	check(C.digest(app.playtest.save_data()) == committed, "repeated finish cannot duplicate drop")
	app.show_inventory(); await frames()
	check(labels_in(app.inventory_box).contains("脚边物品") and labels_in(app.inventory_box).contains("行礼包 ×1"), "actual UI shows ground custody instead of carried stack")
	await capture("native_inventory_ground"); app.inventory_dialog.hide()
	check(app.generated_panel.authority.text.contains("地上"), "authoritative display exposes exact known ground location")
	app.show_advanced(); await capture("native_inventory_actions"); app.advanced_dialog.hide()
	if not sample("pickup_item"): return
	check(app.playtest.state_copy().actors.actor_player.inventory == ["item_travel_bundle"] and app.playtest.state_copy().items.size() == 1, "primary UI retrieves exactly one original item")
	if not sample("drop_item") or not sample("pickup_item"): return
	check(C.bytes(app.playtest.engine.save_data().rng) == C.bytes(expected.rng), "four direct item turns never consume random draws")
	var state: Dictionary = app.playtest.state_copy()
	var key: String = app.playtest.source.navigation.allowed["%d,%d" % state.actors.actor_player.hex][0]
	var cell: Dictionary = state.hexes[key]
	app.on_hex_selected(Vector2i(cell.q, cell.r))
	if not sample("move") or not sample("observe") or not sample("rest"): return
	app.save_game(); check(app.last_save_result.get("ok", false), "mixed action history saves through normal main UI")
	var exact := C.digest(app.playtest.save_data()); var saved_hash := FileAccess.get_sha256(Inventory.INVENTORY_SAVE)
	var generated_object: RefCounted = app.playtest
	app.return_from_map_preview(); await frames()
	check(app.coast_mode and app.playtest == coast_object and C.digest(app.playtest.engine.save_data()) == expected.coast, "return retains original coast object and exact facts/RNG")
	check(app.goal.text == draft and app.journal.text == journal, "coast draft/history remain intact")
	app.continue_generated_adventure(); await frames()
	check(app.playtest == generated_object and C.digest(app.playtest.save_data()) == exact, "return keeps ongoing inventory adventure object")
	app.reset_playtest(); await frames()
	check(app.playtest.state_copy().turn == 0 and app.playtest.state_copy().actors.actor_player.inventory == ["item_travel_bundle"], "explicit reset retains carry profile with one starting item")
	check(FileAccess.get_sha256(Inventory.INVENTORY_SAVE) == saved_hash, "reset does not overwrite saved custody")
	app.load_game(); await frames()
	check(app.last_load_result.get("ok", false) and C.digest(app.playtest.save_data()) == exact, "normal reload restores exact mixed-action inventory save")
	check(FileAccess.get_sha256(Seeded.SEEDED_SAVE) == expected.old_hash, "old v2 file stays byte-exact across every native flow")
	app.return_from_map_preview(); await frames()
func finish() -> void:
	var report := {"phase": phase_, "checks": checks, "failures": failures, "passed": failures.is_empty(), "actual_main": true, "display": DisplayServer.get_name(), "live_api": false, "process_id": OS.get_process_id()}
	if not output.is_empty():
		var file := FileAccess.open(output + "/native_" + phase_ + "_report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("INVENTORY NATIVE ", phase_, " ", checks - failures.size(), "/", checks)
	if is_instance_valid(app): app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
const Main = preload("res://main.tscn")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
var app
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func menus_closed() -> bool:
	return not app.tools_menu.get_popup().visible and not app.advanced_menu.visible and not app.adventure_menu.visible and not app.display_menu.visible
func run() -> void:
	app = Main.instantiate(); root.add_child(app)
	await process_frame
	var before: String = Canonical.bytes(app.playtest.engine.save_data())
	app.tools_menu.get_popup().show(); app.advanced_menu.show()
	app.on_tool_selected(20)
	check(menus_closed(), "manual JSON command dismisses entire popup chain")
	check(app.advanced_dialog.visible, "manual JSON command opens its dialog")
	app.advanced_dialog.hide()
	app.tools_menu.get_popup().show(); app.advanced_menu.show()
	app.on_tool_selected(21)
	check(menus_closed(), "advanced tools command dismisses entire popup chain")
	app.advanced_dialog.hide()
	app.tools_menu.get_popup().show(); app.adventure_menu.show()
	app.on_tool_selected(12)
	check(menus_closed(), "world selector command dismisses entire popup chain")
	check(app.world_dialog.visible, "selector still opens normally")
	app.world_dialog.hide()
	app.tools_menu.get_popup().show(); app.display_menu.show()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	app._input(escape)
	check(menus_closed(), "Escape closes menu chain in one action")
	check(Canonical.bytes(app.playtest.engine.save_data()) == before, "menu actions do not mutate world or RNG")
	app.fill_coast_sample("observe"); app.end_turn()
	var pending: String = Canonical.bytes(app.playtest.engine.save_data())
	app.show_advanced(); app.show_import()
	check(app.import_dialog.visible and not app.advanced_dialog.visible, "import replaces advanced exclusive dialog")
	app.import_text.text = "{bad"; app.import_decision()
	check(app.import_dialog.visible and not app.import_error_label.text.is_empty(), "malformed JSON remains visible with error")
	check(Canonical.bytes(app.playtest.engine.save_data()) == pending, "malformed import preserves complete pending action")
	app.show_import_file()
	check(app.import_file_dialog.visible and not app.import_dialog.visible, "file chooser replaces import dialog")
	app._on_import_file_canceled()
	check(app.import_dialog.visible and not app.import_file_dialog.visible, "file cancel restores only import dialog")
	app.import_dialog.hide(); app.show_advanced(); app.export_request()
	check(app.file_dialog.visible and not app.advanced_dialog.visible, "export replaces advanced exclusive dialog")
	app.file_dialog.hide(); app.cancel_pending(); app.show_advanced(); app.ask_reset_playtest()
	check(app.playtest_reset_dialog.visible and not app.advanced_dialog.visible, "reset confirmation replaces advanced dialog")
	app.playtest_reset_dialog.hide()
	var report := {"passed":checks-failures.size(),"total":checks,"failures":failures,"live_ai":false,"manual_ui":false}
	var f := FileAccess.open("res://artifacts/player_qa_20261003/menu_regression.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("PLAYER_MENU_REGRESSION ",checks-failures.size(),"/",checks," ",JSON.stringify(failures))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

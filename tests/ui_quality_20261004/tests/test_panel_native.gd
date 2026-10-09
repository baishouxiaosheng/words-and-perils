extends SceneTree
## Actual v15 Main with only the candidate panel component replaced in memory.
## No production file is rewritten, and no authority method is substituted.
const Candidate = preload("../candidate/view/playable_build/panel.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var app: Control
var panel: VBoxContainer
var out := ""
var failures := 0
var report: Dictionary = {"checks": [], "captures": [], "integration": "candidate panel component injected after unmodified main startup", "live_provider": false, "fps_claim": false}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	call_deferred("run")
func frames(n: int = 4) -> void:
	for i in range(n): await process_frame
func check(ok: bool, label_: String) -> void:
	report.checks.append({"passed": ok, "name": label_})
	if not ok: failures += 1; printerr("PANEL_NATIVE_FAIL ", label_)
func capture(name_: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(1280, 720), name_ + " native1280x720")
	var path := out.path_join(name_ + ".png")
	check(image.save_png(path) == OK, name_ + " saved native screenshot")
	report.captures.append(path)
func sample(kind: String) -> Button:
	for b in panel.sample_buttons:
		if b.get_meta("sample_kind", "") == kind: return b
	return null
func run() -> void:
	if out.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	app = load("res://main.tscn").instantiate(); root.add_child(app); await frames(18)
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720); await frames()
	check(app.coast_mode and app.board.load_error.is_empty(), "full actual coast starts")
	check(app.viewport.size == Vector2i(1280, 720), "world remains1:1 native raster")
	var original: String = C.bytes(app.playtest.engine.save_data())
	var old: VBoxContainer = app.coast_panel
	var parent: Node = old.get_parent()
	var index := old.get_index()
	panel = Candidate.new(); parent.add_child(panel); parent.move_child(panel, index)
	panel.fixture_pressed.connect(app.playtest_fixture)
	panel.reset_pressed.connect(app.ask_reset_playtest)
	panel.sample_requested.connect(app.fill_coast_sample)
	app.coast_panel = panel; app.playtest_panel = panel
	parent.remove_child(old); old.free()
	app.restyle_advanced_text(panel)
	app.update_playtest_controls(); await frames()
	check(C.bytes(app.playtest.engine.save_data()) == original, "component replacement preserves all authoritative bytes")
	check(panel.sample_buttons.size() == 24 and not sample("observe").disabled, "candidate idle controls current")
	for i in range(2):
		app.show_advanced(); await frames(2)
		check(app.advanced_dialog.visible and not sample("observe").disabled, "open advanced shows current idle state")
		app.advanced_dialog.hide(); await frames(2)
		check(not app.advanced_dialog.visible, "close advanced returns to game")
	app.show_advanced(); await frames(2)
	sample("observe").pressed.emit()
	check(app.playtest.phase() == "idle" and C.bytes(app.playtest.engine.save_data()) == original, "sample button only fills intent")
	app.advanced_dialog.hide()
	app.end_turn(); await frames(2)
	check(app.playtest.phase() == "awaiting_assessment", "real EndTurn waits for assessment")
	check(not panel.fixture_button.disabled and sample("observe").disabled and panel.reset_button.disabled, "hidden panel refreshes pending controls")
	app.show_advanced(); await capture("pending_advanced")
	check(not panel.fixture_button.disabled and sample("observe").disabled, "reopening keeps pending state fresh")
	panel.fixture_button.pressed.emit(); await frames(8)
	check(app.playtest.phase() == "idle" and app.playtest.state_copy().turn == 1 and app.playtest.state_copy().flags.coast_observed, "real fixture button commits one observation")
	check(not app.advanced_dialog.visible and not sample("observe").disabled and not panel.reset_button.disabled, "commit closes modal and refreshes idle controls")
	var committed := C.bytes(app.playtest.engine.save_data())
	panel.fixture_button.pressed.emit()
	check(C.bytes(app.playtest.engine.save_data()) == committed, "duplicate fixture callback cannot commit twice")
	app.show_advanced(); await capture("committed_advanced")
	app.advanced_dialog.hide()
	app.set_player_intent("看看海风吹来的方向。")
	app.end_turn(); await frames(2)
	check(app.playtest.phase() == "awaiting_assessment" and panel.fixture_button.disabled, "free text cannot use signed fixture")
	app.show_advanced(); await frames(2)
	app.cancel_button.pressed.emit(); await frames(2)
	check(app.playtest.phase() == "idle" and not sample("observe").disabled, "actual cancel button refreshes idle controls")
	check(app.playtest.state_copy().turn == 1, "cancel adds no committed turn")
	app.advanced_dialog.hide(); await capture("returned_game")
	report["failures"] = failures
	report["world_cells"] = app.playtest.state_copy().hexes.size()
	report["world_msaa"] = app.viewport.msaa_3d
	report["adapter"] = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(out.path_join("panel_native_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	app.queue_free(); await frames(4)
	print("PANEL_NATIVE_COMPLETE checks=", report.checks.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)

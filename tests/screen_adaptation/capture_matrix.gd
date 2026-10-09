extends SceneTree
## One native process per resolution; never resample a screenshot.
const Main = preload("res://main.tscn")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
var scene
var target := Vector2i(1280, 720)
var out := "res://artifacts/screen_adaptation_20261003"
var report: Dictionary = {"checks": [], "captures": []}
var failure_count := 0

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in range(10): await process_frame
func record(ok: bool, name_: String) -> void:
	report.checks.append({"passed": ok, "name": name_})
	if not ok: failure_count += 1; printerr("SCREEN FAIL: ", name_)
func rect_array(r: Rect2) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y]
func write_report() -> void:
	report["failures"] = failure_count
	var file := FileAccess.open(out + "/manifest_%dx%d.json" % [target.x, target.y], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
func fit(control: Control) -> bool:
	return Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(control.get_global_rect())
func capture(label_: String) -> void:
	await settle()
	var frame: Dictionary = {"scenario": label_, "requested_pixels": [target.x, target.y], "actual_window_pixels": [root.size.x, root.size.y], "root_viewport_pixels": [root.get_visible_rect().size.x, root.get_visible_rect().size.y], "world_viewport_pixels": [scene.viewport.size.x, scene.viewport.size.y], "panels": {}}
	for control in [scene.area_panel, scene.map_cluster, scene.hero_panel, scene.action_panel, scene.journal_panel]:
		frame.panels[control.name] = {"visible": control.is_visible_in_tree(), "rect": rect_array(control.get_global_rect())}
	if is_instance_valid(scene.board.committed_camera):
		var safe: Rect2 = scene.board.committed_camera.usable_rect()
		frame["action_safe_rect"] = rect_array(safe)
		record(safe.size.x >= 120 and safe.size.y >= 120, label_ + ": action framing retains a useful safe area")
		for obstruction in [scene.area_panel, scene.map_cluster, scene.hero_panel, scene.action_panel, scene.journal_panel]:
			if obstruction.is_visible_in_tree(): record(not safe.intersects(obstruction.get_global_rect()), label_ + ": action safe area avoids " + str(obstruction.name))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image_ := root.get_texture().get_image()
		frame["rendered_image_pixels"] = [image_.get_width(), image_.get_height()]
		frame["capture_kind"] = "native_window_framebuffer_no_resampling"
		var path := out + "/%dx%d_%s.png" % [target.x, target.y, label_]
		var saved := image_.save_png(path)
		var decoded := Image.load_from_file(path)
		frame["png_pixels"] = [decoded.get_width(), decoded.get_height()]
		record(saved == OK and image_.get_size() == target and decoded.get_size() == target, label_ + ": rendered and PNG pixels equal requested size")
	else:
		frame["capture_kind"] = "headless_geometry_only_no_screenshot"
		report["native_capture_blocked"] = true
	record(root.size == target, label_ + ": actual window size matches request")
	record(scene.viewport.size == root.size, label_ + ": world renders at 1:1 client pixels")
	record(scene.board_container.get_global_rect() == Rect2(Vector2.ZERO, Vector2(root.size)), label_ + ": world fills client without letterbox")
	for control in [scene.area_panel, scene.map_cluster, scene.hero_panel, scene.action_panel, scene.journal_panel]:
		if control.is_visible_in_tree(): record(fit(control), label_ + ": " + str(control.name) + " stays inside client")
	if scene.action_panel.visible:
		record(not scene.hero_panel.get_global_rect().intersects(scene.action_panel.get_global_rect()), label_ + ": hero and dialogue do not overlap")
		record(fit(scene.goal) and fit(scene.submit_button), label_ + ": writing and submit remain reachable")
	if scene.journal_panel.visible:
		record(scene.journal_panel.get_global_rect().end.y <= scene.action_panel.position.y + 1, label_ + ": history stays above dialogue")
	for button in [scene.submit_button, scene.journal_toggle, scene.intent_expand_button, scene.tools_menu, scene.dialogue_restore_button]:
		if button.is_visible_in_tree(): record(minf(button.get_global_rect().size.x, button.get_global_rect().size.y) >= 31.9, label_ + ": " + str(button.name) + " has at least 32px pointer target")
	var name_layout: Node = scene.board.get_node_or_null("WorldLabelLayout")
	if name_layout != null:
		frame["world_labels"] = name_layout.report()
		record(int(frame.world_labels.get("overlap_count", -1)) == 0, label_ + ": visible world names do not overlap")
		if is_instance_valid(scene.board.creative_view):
			var visible_creative := 0
			for item in scene.board.creative_view.labels:
				if item.is_visible_in_tree(): visible_creative += 1
			frame["visible_creative_labels"] = visible_creative
			record(visible_creative == 0, label_ + ": unselected small objects add no permanent name clutter")
	report.captures.append(frame)
	write_report()
	print("SCREEN CAPTURE ", target, " ", label_, " ", frame.get("rendered_image_pixels", []))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2: target = Vector2i(int(parts[0]), int(parts[1]))
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	DirAccess.make_dir_recursive_absolute(out)
	root.mode = Window.MODE_WINDOWED; root.size = target
	report.merge({"requested_pixels": [target.x, target.y], "display_server": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "physical_monitor_dpi_tested": false, "hardware_target_tested": false, "upscaled": false})
	if DisplayServer.get_name() != "headless":
		var screen_size := DisplayServer.screen_get_size()
		report["desktop_pixels"] = [screen_size.x, screen_size.y]
		report["window_exceeds_desktop"] = target.x > screen_size.x or target.y > screen_size.y
	scene = Main.instantiate(); root.add_child(scene); await settle()
	root.mode = Window.MODE_WINDOWED; root.size = target; await settle()
	var state_before := Canonical.bytes(scene.playtest.state_copy())
	await capture("default")
	report["body_font_pixels"] = scene.latest_dialogue.get_theme_font_size("font_size")
	report["hud_scale"] = scene.get_meta(&"responsive_hud_scale", 1.0)
	scene.toggle_journal(); await capture("history")
	scene.toggle_intent(); await capture("history_expanded")
	scene.toggle_intent(); scene.toggle_journal()
	scene.toggle_overview(); await capture("overview")
	scene.dialogue_restore_button.pressed.emit(); await capture("overview_dialogue_restored")
	scene.toggle_overview()
	scene.show_advanced(); await capture("advanced")
	var advanced_rect := Rect2(Vector2(scene.advanced_dialog.position), Vector2(scene.advanced_dialog.size))
	record(Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(advanced_rect), "advanced dialog fits client")
	scene.advanced_dialog.hide()
	record(Canonical.bytes(scene.playtest.state_copy()) == state_before, "resize/history/map/advanced checks preserve authoritative state")
	write_report()
	print("SCREEN MATRIX RESULT ", target, " failures=", failure_count, " native=", DisplayServer.get_name() != "headless")
	scene.queue_free(); await process_frame; quit(0 if failure_count == 0 else 1)

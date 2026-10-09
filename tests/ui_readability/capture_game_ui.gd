extends "res://tests/screen_adaptation/capture_matrix.gd"
## Actual production HUD. Run only after explicit native/memory admission.
## Does not submit an action or reload/rebuild a world.
const TypeRamp = preload("res://view/fullscreen_hud/readability.gd")
const Layout = preload("res://view/fullscreen_hud/responsive_layout.gd")

func round_caption_fits(label_: String) -> void:
	var button: Button = scene.submit_button
	record(absf(button.size.x - button.size.y) < 1.0, label_ + ": primary button stays circular")
	var face := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var lines := button.text.split("\n")
	var width := 0.0
	for line in lines: width = maxf(width, face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var glyph_height := face.get_height(font_size) * lines.size()
	record(width <= button.size.x * 0.70, label_ + ": two-line caption has horizontal inner-face clearance")
	record(glyph_height <= button.size.y * 0.74, label_ + ": two-line caption has vertical inner-face clearance")
	record(button.size_flags_vertical == Control.SIZE_SHRINK_CENTER, label_ + ": primary stays vertically centered beside writing")

func run() -> void:
	out = "res://artifacts/ui_readability_20261003/game"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2: target = Vector2i(int(parts[0]), int(parts[1]))
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	DirAccess.make_dir_recursive_absolute(out)
	root.mode = Window.MODE_WINDOWED; root.size = target
	report.merge({"scope": "actual_game_HUD_after_typography_revision", "requested_pixels": [target.x, target.y], "display_server": DisplayServer.get_name(), "physical_dpi_verified": false})
	scene = Main.instantiate(); root.add_child(scene); await settle()
	root.mode = Window.MODE_WINDOWED; root.size = target; await settle()
	var before := Canonical.bytes(scene.playtest.state_copy())
	var expected_font := roundi(TypeRamp.BODY_SIZE * Layout.scale_for(Vector2(target)))
	record(scene.latest_dialogue.get_theme_font_size("font_size") == expected_font, "native body size follows new type ramp")
	record(scene.journal_toggle.text == "对话记录", "compact history caption contains no compressed arrow ornament")
	round_caption_fits("default")
	await capture("ui_default")
	scene.goal.text = "沿着岸线观察潮水留下的痕迹，再向守灯人询问旧灯熄灭的经过。\n如果发现异样，我会先停下来仔细检查，不急着进入城门。"
	scene.toggle_intent(); await settle()
	round_caption_fits("expanded_input")
	record(scene.goal.size.y > scene.submit_button.size.y, "expanded text field can grow without stretching the turn circle")
	await capture("ui_expanded_input")
	var narration := "潮水正在退去，湿润的石阶露出一道清晰的盐痕。守灯人指向岸边的旧灯，说昨夜的风忽然转向了北方。你可以沿着岸线检查，也可以先向附近的人询问经过。"
	scene.append_journal("芦灯", narration)
	scene.toggle_journal(); await settle()
	record(scene.journal.get_parsed_text().contains(narration), "history retains the complete long narrative")
	record(scene.latest_dialogue.tooltip_text == narration, "bounded preview preserves the full-text tooltip")
	record(scene.journal_toggle.text == "收起记录", "open history has a concise stable-width action label")
	round_caption_fits("history")
	await capture("ui_long_history")
	scene.toggle_journal(); scene.toggle_intent(); await settle()
	round_caption_fits("restored")
	record(Canonical.bytes(scene.playtest.state_copy()) == before, "visual review does not change authoritative world facts")
	write_report()
	print("ACTUAL HUD READABILITY ", target, " failures=", failure_count)
	scene.queue_free(); await process_frame; quit(0 if failure_count == 0 else 1)

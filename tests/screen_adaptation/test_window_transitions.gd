extends SceneTree
const Main = preload("res://main.tscn")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Labels = preload("res://view/fullscreen_hud/world_label_layout.gd")
const Creative = preload("res://view/playable_build/creative_content.gd")
const UIType = preload("res://view/fullscreen_hud/readability.gd")
const UILayout = preload("res://view/fullscreen_hud/responsive_layout.gd")
const OUT = "res://artifacts/screen_adaptation_20261003/transitions/"
var scene
var failures: Array = []
var checks: Array = []
var snapshots: Array = []

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in range(12): await process_frame
func check(ok: bool, text_: String) -> void:
	checks.append({"passed": ok, "name": text_})
	if not ok: failures.append(text_); printerr("TRANSITION FAIL: ", text_)
func snapshot(label_: String) -> void:
	await settle()
	var row: Dictionary = {"name": label_, "actual_pixels": [root.size.x, root.size.y], "window_mode": root.mode, "body_font_pixels": scene.latest_dialogue.get_theme_font_size("font_size")}
	check(scene.viewport.size == root.size, label_ + ": world texture remains native size")
	var layout: Node = scene.board.get_node_or_null("WorldLabelLayout")
	if layout != null:
		row["labels"] = layout.report()
		check(int(row.labels.get("overlap_count", -1)) == 0, label_ + ": visible labels do not overlap")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image_ := root.get_texture().get_image()
		row["png_pixels"] = [image_.get_width(), image_.get_height()]
		check(image_.get_size() == root.size, label_ + ": saved screenshot is actual rendered pixels")
		image_.save_png(OUT + "%s_%dx%d.png" % [label_, root.size.x, root.size.y])
	snapshots.append(row)
func run() -> void:
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	DirAccess.make_dir_recursive_absolute(OUT)
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	scene = Main.instantiate(); root.add_child(scene); await settle()
	var before := Canonical.bytes(scene.playtest.state_copy())
	var base_minimum: Vector2 = scene.action_panel.get_combined_minimum_size()
	await snapshot("windowed_start")
	for resolution in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 720)]:
		root.size = resolution; await settle(); scene.apply_responsive_layout(); await settle()
		check(root.size == resolution, str(resolution) + ": live resize honored")
		check(scene.latest_dialogue.get_theme_font_size("font_size") == roundi(UIType.BODY_SIZE * UILayout.scale_for(Vector2(resolution))), str(resolution) + ": typography uses native pixels at the expected scale")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(scene.action_panel.get_global_rect()), str(resolution) + ": dialogue stays in client")
		await snapshot("resize_%dx%d" % [resolution.x, resolution.y])
	check(scene.latest_dialogue.get_theme_font_size("font_size") == UIType.BODY_SIZE, "720p return restores original font size without scaling drift")
	check(scene.action_panel.get_combined_minimum_size().is_equal_approx(base_minimum), "720p return restores original measured minimum")
	# Exercise the actual F11 input route; resulting desktop size is recorded,
	# never mislabeled as one of the target resolution rows.
	if DisplayServer.get_name() != "headless":
		var key := InputEventKey.new(); key.keycode = KEY_F11; key.pressed = true
		scene._input(key); await settle()
		check(root.mode == Window.MODE_FULLSCREEN, "F11 enters fullscreen")
		await snapshot("f11_fullscreen")
		scene._input(key); await settle()
		check(root.mode == Window.MODE_MAXIMIZED, "F11 returns to maximized")
		await snapshot("f11_maximized")
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720); await settle()
		check(root.mode == Window.MODE_WINDOWED and root.size == Vector2i(1280, 720), "explicit windowed restore returns to720p")
		await snapshot("windowed_restored")
	# Selecting a carried prop exposes exactly that subject, then clears it.
	var item_id: String = Creative.ITEM_IDS[0]
	scene._apply_focus(Creative.make_reference(item_id, scene.playtest.state_copy())); await settle()
	var count := 0
	for label in scene.board.creative_view.labels:
		if label.is_visible_in_tree(): count += 1
	check(count == 1, "one selected small item displays one readable name")
	await snapshot("selected_item")
	scene.clear_target(); await settle()
	count = 0
	for label in scene.board.creative_view.labels:
		if label.is_visible_in_tree(): count += 1
	check(count == 0, "clearing selection removes small-item labels")
	check(Canonical.bytes(scene.playtest.state_copy()) == before, "resize/fullscreen/selection never change authoritative world state")
	# Bounded placement itself rejects an impossible slot rather than stacking.
	var screen := Rect2(0, 0, 300, 200)
	var blockers: Array[Rect2] = [Rect2(80, 80, 140, 35)]
	var slot := Labels.find_slot(Rect2(80, 80, 140, 35), screen, blockers, 80)
	check(slot.get("ok", false) and Vector2(slot.get("shift", Vector2.ZERO)).length() <= 80, "collision avoidance finds a bounded alternate slot")
	var filled: Array[Rect2] = [screen]
	check(not Labels.find_slot(Rect2(80, 80, 140, 35), screen, filled, 40).ok, "fully occupied label area suppresses instead of overlapping")
	var file := FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"native": DisplayServer.get_name() != "headless", "checks": checks, "failures": failures, "snapshots": snapshots}, "\t")); file.close()
	print("WINDOW TRANSITIONS ", checks.size() - failures.size(), "/", checks.size())
	scene.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)

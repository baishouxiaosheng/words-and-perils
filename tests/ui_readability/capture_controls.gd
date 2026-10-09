extends SceneTree
## Lightweight native 2D design review. No main scene, terrain, actor or world
## load. This is clearly labeled a controls preview, not a gameplay screenshot.
const Buttons = preload("res://view/fullscreen_hud/button_theme.gd")
const Craft = preload("res://view/ui_craft.gd")
const OUT = "res://artifacts/ui_readability_20261003/"
var canvas: Control
var tested: Array[Button] = []
var checks: Array = []

func _initialize() -> void: call_deferred("run")
func text_(value: String, at: Vector2, size_: int, strong := false, color := Color("2c423b")) -> Label:
	var node := Label.new(); node.text = value; node.position = at
	node.add_theme_font_override("font", Buttons.strong_font() if strong else Craft.font("body"))
	node.add_theme_font_size_override("font_size", size_)
	node.add_theme_color_override("font_color", color)
	canvas.add_child(node); return node
func check(ok: bool, name_: String) -> void:
	checks.append({"passed": ok, "name": name_})
	if not ok: printerr("READABILITY FAIL: ", name_)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 820)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	canvas = Control.new(); canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(canvas)
	var background := ColorRect.new(); background.color = Color("e8e4cc"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); canvas.add_child(background)
	text_("雾岸纪事 · 文字与按钮", Vector2(40, 28), 26, true)
	text_("原生界面控件预览 · 无3D世界 · 不代表最终游戏截图", Vector2(40, 70), 15, false, Color("667064"))
	var panel := PanelContainer.new(); panel.position = Vector2(40, 114); panel.size = Vector2(1200, 134)
	var skin := Buttons.writing_surface(); skin.set_content_margin(SIDE_LEFT, 20); skin.set_content_margin(SIDE_TOP, 16)
	panel.add_theme_stylebox_override("panel", skin); canvas.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 8); panel.add_child(column)
	var speaker := Label.new(); speaker.text = "芦灯"; speaker.add_theme_font_override("font", Buttons.strong_font()); speaker.add_theme_font_size_override("font_size", 17); speaker.add_theme_color_override("font_color", Color("75553d")); column.add_child(speaker)
	var prose := Label.new(); prose.text = "旧灯已经熄了三夜。先观察岸线，再到我身旁，我们一起把灯点亮。\n你可以自由描述行动，具体结果将在裁定后进入世界。"
	prose.add_theme_font_override("font", Craft.font("body")); prose.add_theme_font_size_override("font_size", 18)
	prose.add_theme_color_override("font_color", Buttons.INK); prose.add_theme_constant_override("line_spacing", 2); column.add_child(prose)
	var states := ["normal", "hover", "pressed", "disabled"]
	for index in range(4): text_(["常态", "悬停", "按下", "不可用"][index], Vector2(232 + index * 244, 269), 16, true)
	var rows := [
		{"role": "secondary", "title": "常用操作", "text": "返回冒险", "y": 314.0},
		{"role": "compact", "title": "轻量操作", "text": "对话记录", "y": 397.0},
		{"role": "compact_round", "title": "图标操作", "text": "", "y": 480.0},
		{"role": "turn", "title": "主要行动", "text": "结束\n回合", "y": 563.0}]
	for row in rows:
		text_(row.title, Vector2(44, row.y + 6), 16, true)
		for index in range(4):
			var button := Button.new(); button.text = row.text
			if row.role == "compact_round": button.icon = preload("res://view/strategy_icons.gd").small_texture("quill", "344740", 18)
			Buttons.apply(button, row.role)
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.position = Vector2(220 + index * 244, row.y)
			if row.role == "secondary": button.custom_minimum_size.x = 184
			elif row.role == "compact": button.custom_minimum_size.x = 126
			# Static state comparison uses the exact shipping state resources.
			if states[index] == "hover":
				button.add_theme_stylebox_override("normal", Buttons.surface(row.role, "hover"))
			elif states[index] == "pressed":
				button.toggle_mode = true; button.button_pressed = true
			elif states[index] == "disabled": button.disabled = true
			canvas.add_child(button); tested.append(button)
	var input := TextEdit.new(); input.position = Vector2(40, 696); input.size = Vector2(1000, 80)
	input.text = "沿着岸线调查旧灯，然后向守灯人询问失火的经过。"
	input.add_theme_font_override("font", Craft.font("body")); input.add_theme_font_size_override("font_size", 18)
	input.add_theme_color_override("font_color", Buttons.INK); input.add_theme_stylebox_override("normal", Buttons.writing_surface())
	input.add_theme_stylebox_override("focus", Buttons.writing_surface(true)); input.add_theme_stylebox_override("read_only", Buttons.writing_surface(false, true))
	canvas.add_child(input)
	var action := Button.new(); action.text = "结束\n回合"; Buttons.apply(action, "turn"); action.position = Vector2(1100, 688); canvas.add_child(action); tested.append(action)
	for i in range(12): await process_frame
	for button in tested:
		var role: String = button.get_meta(&"hud_button_role")
		if role in ["turn", "compact_round"]:
			check(is_equal_approx(button.size.x, button.size.y), role + ": circular controls stay square")
		check(button.size.y >= 36, role + ": minimum physical pointer target")
		var face := button.get_theme_font("font"); var size_ := button.get_theme_font_size("font_size")
		var width := 0.0
		for line in button.text.split("\n"): width = maxf(width, face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x)
		var skin_: StyleBox = button.get_theme_stylebox("normal")
		check(width <= button.size.x - skin_.get_content_margin(SIDE_LEFT) - skin_.get_content_margin(SIDE_RIGHT), role + ": text fits inside content padding")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image_ := root.get_texture().get_image()
		check(image_.get_size() == Vector2i(1280, 820), "preview image uses native1280x820 pixels")
		image_.save_png(OUT + "controls_1280x820.png")
	var file := FileAccess.open(OUT + "controls_checks.json", FileAccess.WRITE)
	var failed := checks.filter(func(row): return not row.passed)
	file.store_string(JSON.stringify({"preview_only": true, "native": DisplayServer.get_name() != "headless", "checks": checks, "failed": failed}, "\t")); file.close()
	print("CONTROLS PREVIEW ", checks.size() - failed.size(), "/", checks.size())
	quit(0 if failed.is_empty() else 1)

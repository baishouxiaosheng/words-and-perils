extends SceneTree
const Subject = preload("res://view/playable_build/player_details.gd")
const Details = preload("res://view/status_gameplay/details.gd")
const OVERLAY_SHA = "e4e20fc6fb269238d3a6116634b6593f92078c5dafbbd055b237eb123b49d883"
var panel: RichTextLabel
var caption: Label
var buttons: Array[Button] = []
var choices: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var shots: Array[String] = []
var failures: Array[String] = []
var frame: int = 0
var current: int = 0
var pressed_events: int = 0
var checks: int = 0
var scheduled_capture: bool = false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(3)
		return
	var data_root := args[0].replace("\\", "/").simplify_path().trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	var global_dir := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/")
	var leaf := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var autoloads: Array = []
	for item in ProjectSettings.get_property_list():
		if str(item.name).begins_with("autoload/"):
			autoloads.append(item.name)
	var isolated := not leaf.is_empty() and not leaf.contains("/") and not leaf.contains("\\") and os_dir.to_lower() == (data_root+"/appdata/"+leaf).to_lower() and os_dir.to_lower() == global_dir.to_lower() and autoloads.is_empty()
	print("LOCAL_SUITE_ISOLATION ", JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads}))
	if not isolated:
		quit(3)
		return
	check(FileAccess.get_sha256("res://view/playable_build/player_details.gd") == OVERLAY_SHA, "exact tested combined production code")
	check(FileAccess.get_file_as_bytes("res://view/playable_build/player_details.gd").size() == 9112, "exact combined source bytes")
	if not failures.is_empty():
		quit(1)
		return
	call_deferred("start")

func start() -> void:
	root.size = Vector2i(1080,700)
	root.title = "Words and Perils - focused display verification (unadopted)"
	root.content_scale_size = Vector2i(1080,700)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var background := ColorRect.new()
	background.color = Color("101a2b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var title := Label.new()
	title.text = "Words and Perils  |  状态计时 + 对象位置"
	title.position = Vector2(38,28)
	title.add_theme_font_size_override("font_size",28)
	root.add_child(title)
	var scope := Label.new()
	scope.text = "独立显示/交互验收 · 固定测试数据 · 非完整 Main 游戏 · 正式 v30 未改动"
	scope.position = Vector2(38,78)
	scope.add_theme_color_override("font_color",Color("a2bbd6"))
	root.add_child(scope)
	var details_a: Dictionary = Details.public_details({}, {"statuses":{"p":{"kind":"poison","remaining_turns":2,"magnitude":1}}})
	var details_b: Dictionary = Details.public_details({}, {"statuses":{"f":{"kind":"flight","remaining_turns":1,"magnitude":0}}})
	check(Details.valid_public_details(details_a) and Details.valid_public_details(details_b), "real legacy adapter produces valid detached public fixtures")
	choices = [{"kind":"actor","id":"fixture_a","hex":[2,-3],"facts":{"name":"角色 A","status_details":details_a}},{"kind":"actor","id":"fixture_b","hex":[-5,7],"facts":{"name":"角色 B","status_details":details_b}},{"kind":"actor","id":"fixture_invalid","hex":["1",2],"facts":{"name":"无效位置输入","status_details":details_a}},{"kind":"tile","id":"fixture_tile","hex":[0,0],"facts":{"name":"地格 (0,0)"}}]
	var names: Array[String] = ["角色 A (2,-3)","角色 B (-5,7)","无效坐标护栏","地格 (0,0)"]
	for index in range(4):
		var button := Button.new()
		button.text = names[index]
		button.position = Vector2(38+250*index,132)
		button.size = Vector2(235,48)
		button.pressed.connect(on_pressed.bind(index))
		buttons.append(button)
		root.add_child(button)
	caption = Label.new()
	caption.position = Vector2(46,210)
	caption.add_theme_font_size_override("font_size",25)
	root.add_child(caption)
	panel = RichTextLabel.new()
	panel.position = Vector2(46,257)
	panel.size = Vector2(985,330)
	panel.add_theme_font_size_override("normal_font_size",23)
	root.add_child(panel)
	var foot := Label.new()
	foot.position = Vector2(38,636)
	foot.text = "真实 Godot 渲染 / Button.pressed 更新面板 / 自动输入事件验收 / 无存档写入"
	foot.add_theme_color_override("font_color",Color("a2bbd6"))
	root.add_child(foot)
	select_choice(0)

func select_choice(index: int) -> void:
	current = index
	var input: Dictionary = choices[index]
	var frozen := var_to_bytes(input)
	var output: String = Subject.description(input)
	check(var_to_bytes(input) == frozen, "complete selection byte-exact after real formatter")
	panel.text = output
	caption.text = Subject.caption(input)
	check(panel.text == Subject.description(input), "actual widget text matches bound production formatter")
	if index == 0:
		check(output.contains("选中地格：（2，-3）") and output.contains("剩余2次已提交行动"), "actor A coordinate and finite legacy timing coexist")
	elif index == 1:
		check(output.contains("选中地格：（-5，7）") and output.contains("剩余1次已提交行动"), "switch actor updates coordinate and clock")
	elif index == 2:
		check(not output.contains("选中地格") and output.contains("剩余2次已提交行动"), "invalid coordinate rejected while timing preserved")
	else:
		check(output.contains("选中地格：（0，0）") and not output.contains("已提交行动"), "tile coordinate without actor timing")
	observations.append({"frame":frame,"selected":index,"caption":caption.text,"description":output,"input_unchanged":var_to_bytes(input)==frozen})

func on_pressed(index: int) -> void:
	pressed_events += 1
	select_choice(index)

func click(index: int) -> void:
	var position := buttons[index].get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = down
		Input.parse_input_event(event)

func capture() -> void:
	scheduled_capture = true
	await RenderingServer.frame_post_draw
	var name := "focused-gui-%03d.png" % frame
	check(root.get_texture().get_image().save_png("user://"+name) == OK, "actual viewport screenshot saved inside isolated user directory")
	shots.append(name)
	scheduled_capture = false

func _process(_delta: float) -> bool:
	if buttons.is_empty():
		return false
	frame += 1
	if frame == 45:
		click(1)
	elif frame == 90:
		click(2)
	elif frame == 135:
		click(3)
	elif frame == 180:
		click(0)
	if frame < 225 and (frame % 3 == 0 or frame in [35,80,125,170,215]):
		capture()
	if frame == 225:
		check(pressed_events == 4 and current == 0, "four real Godot mouse-event Button.pressed dispatches and return selection")
		check(shots.size() == 79 and not scheduled_capture, "79 actual rendered frames including five selected screenshots")
		var result := {"suite":"combined_focused_gui","status":"GUI_PASSED" if failures.is_empty() else "GUI_FAILED","checks":checks,"failures":failures,"pressed_events":pressed_events,"input_source":"programmatic Godot InputEventMouseButton through actual UI dispatch, not physical mouse claim","fixture_only":true,"full_Main_verified":false,"production_sha256":OVERLAY_SHA,"observations":observations,"screenshots":shots,"frames":frame}
		var file := FileAccess.open("user://GUI_RESULT.json",FileAccess.WRITE)
		if file == null:
			printerr("ERROR: GUI result write failed")
			quit(2)
			return false
		file.store_string(JSON.stringify(result,"  "))
		file.close()
		print("FOCUSED_GUI_RESULT ",JSON.stringify(result))
		for failure in failures:
			printerr("FAIL: "+failure)
		quit(0 if failures.is_empty() else 1)
	return false

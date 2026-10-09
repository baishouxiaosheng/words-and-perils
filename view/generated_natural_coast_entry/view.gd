extends "res://view/generated_natural_coast_basic/main.gd"
## Reuses the accepted standalone controls without touching either Main file.
## The launcher assigns entry_session before this node enters the tree.
signal admitted
signal admission_failed(result: Dictionary)
var entry_session: RefCounted
var diagnostics_box:VBoxContainer
var diagnostics_toggle:Button
var preset_summary:Label
const ENTRY_INK=Color("2d403e")
const ENTRY_PAPER=Color("f2dfa6")
const ENTRY_MUTED=Color("667066")
const BIOME_LABELS := {"ocean":"海洋","grassland":"草原","dry_steppe":"干草原","desert":"沙漠","temperate_forest":"温带森林","jungle":"丛林","alpine":"高山","wetland":"湿地"}
const SaveIdentityCanonical = preload("res://core/ai_gm_rebuilt/canonical.gd")

func _existing_save_identity_check(path: String, expected: Dictionary) -> Dictionary:
	# UI-only overwrite protection. Exact admission and adapter identity stay unchanged.
	if not FileAccess.file_exists(path): return {"ok":true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok":false,"code":"COAST_SAVE_UNVERIFIED","errors":["无法校验已有进度，未覆盖。"]}
	if file.get_length() > Adapter.MAX_SAVE_BYTES:
		file.close()
		return {"ok":false,"code":"COAST_SAVE_UNVERIFIED","errors":["已有进度过大，未覆盖。"]}
	var encoded := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	var parser := JSON.new()
	if read_error not in [OK, ERR_FILE_EOF] or parser.parse(encoded) != OK:
		return {"ok":false,"code":"COAST_SAVE_UNVERIFIED","errors":["已有进度无法完整解析，未覆盖。"]}
	var existing: Variant = parser.data
	if not existing is Dictionary or not existing.get("identity") is Dictionary or expected.is_empty() or not SaveIdentityCanonical.safe(expected) or not SaveIdentityCanonical.safe(existing.identity) or SaveIdentityCanonical.bytes(existing.identity) != SaveIdentityCanonical.bytes(expected):
		return {"ok":false,"code":"COAST_SAVE_IDENTITY","errors":["已有进度属于另一发布版本或身份无效，未覆盖。请使用原版本打开，或先另行备份该文件。"]}
	return {"ok":true}

func _save() -> void:
	if _busy or adapter == null or not adapter.ready().get("ok", false): return
	_busy = true
	var checked: Dictionary = _existing_save_identity_check(adapter.default_save_path(), adapter.source.identity)
	if checked.get("ok", false): checked = adapter.save_file()
	_feedback(checked,"自然海岸进度已保存，包括尚未执行的评估。")
	_busy = false
	_refresh()

func _build_ui() -> void:
	var host_theme:Theme=theme
	super._build_ui()
	if host_theme!=null:theme=host_theme
	for child in get_children():
		if child is ColorRect:child.color=ENTRY_PAPER
	for label_ in find_children("*","Label",true,false):
		label_.add_theme_color_override("font_color",ENTRY_INK);label_.modulate=Color.WHITE
		if label_.text.begins_with("PHYSICAL RIVERS"):label_.text="自然海岸基础探索"
		elif label_.text.begins_with("当前通行限制："):label_.text="当前只验证干地路线，暂不支持渡河。"
		elif label_.text.contains("原版 v21"):label_.text="测试进度单独保存，不改原旅程。"
		elif label_.text.begins_with("内置评估"):label_.text="离线预设评估，不连接 AI。评估后仍须确认执行。"
	for panel in find_children("*","PanelContainer",true,false):
		var surface:=StyleBoxFlat.new();surface.bg_color=Color("ead69f");surface.border_color=Color("9b8d6f");surface.set_border_width_all(1);surface.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel",surface)
	# C theme font does not contain the standalone rotation-arrow glyphs.
	for button_ in find_children("*","Button",true,false):
		if button_.text=="↶":button_.text="左转"
		elif button_.text=="↷":button_.text="右转"
	for i in range(example_buttons.size()):example_buttons[i].text=["填入移动","填入观察","填入休息","放下行礼包","拾回行礼包"][i]
	var controls:VBoxContainer=goal_edit.get_parent()
	var old_index:int=goal_edit.get_index()
	preset_summary=_label("尚未填写预设行动。",16);preset_summary.add_theme_color_override("font_color",ENTRY_INK);controls.add_child(preset_summary);controls.move_child(preset_summary,old_index)
	diagnostics_toggle=_button("诊断与离线请求",func():pass);diagnostics_toggle.toggle_mode=true;diagnostics_toggle.add_theme_color_override("font_pressed_color",ENTRY_INK);diagnostics_toggle.add_theme_color_override("font_hover_pressed_color",ENTRY_INK);controls.add_child(diagnostics_toggle)
	diagnostics_box=VBoxContainer.new();diagnostics_box.visible=false;controls.add_child(diagnostics_box)
	diagnostics_toggle.toggled.connect(func(open:bool):diagnostics_box.visible=open)
	for control in [identity_label,goal_edit,export_button]:
		control.get_parent().remove_child(control);diagnostics_box.add_child(control)
	identity_label.modulate=Color.WHITE;identity_label.add_theme_color_override("font_color",ENTRY_MUTED)
	goal_edit.placeholder_text="原始预设文本或待离线评估的自由文字；不自动猜测或执行。"
	var note:=_label("此区保留原始协议文本与地图校验信息。自由文字须另取有效离线评估。",13);note.add_theme_color_override("font_color",ENTRY_MUTED);diagnostics_box.add_child(note)
	goal_edit.text_changed.connect(_update_preset_summary)
	_update_preset_summary()

func _update_preset_summary() -> void:
	if preset_summary==null:return
	var shown:String=goal_edit.text.trim_prefix("【探索示例】").strip_edges()
	preset_summary.text="尚未填写行动。" if shown.is_empty() else "行动草稿："+shown

func _choose_example(kind:String) -> void:
	super._choose_example(kind)
	feedback_label.text=feedback_label.text.replace("示例","预设")
	_update_preset_summary()

func _start() -> void:
	if entry_session == null or not entry_session.is_open() or entry_session.coast == null:
		_fail_entry({"ok":false,"errors":["需要已验证的独立实验会话；未创建或替换世界。"]});return
	adapter = entry_session.coast
	if not adapter.ready().ok: _fail_entry(adapter.ready());_refresh();return
	board = Board.new(adapter.source);viewport.add_child(board);board.set_world(adapter.state_copy());board.hex_selected.connect(_select)
	if not board.load_error.is_empty(): _fail_entry({"ok":false,"errors":[board.load_error]});return
	_select(adapter.state_copy().actors.actor_player.hex)
	feedback_label.text = "原旅程保持不变。返回前请完成或取消测试行动。"
	_refresh()
	admitted.emit()

func _fail_entry(result: Dictionary) -> void:
	_feedback(result);admission_failed.emit(result)

func _refresh() -> void:
	super._refresh()
	var diagnostic_selection:String=selection_label.text if selection_label!=null else ""
	if selection_label!=null:
		selection_label.text=selection_label.text.replace(" · grassland\n"," · 草原\n").replace(" · temperate_forest\n"," · 温带森林\n").replace("中心锚点有实际干地支撑","此格可站立").replace("中心锚点被水面或安全净距阻挡","此处落脚点受水面或岸边间距限制").replace("选中不等于行动目标；行动使用评估时冻结的文字目标。","点击只选中地格。实际目标以已评估的行动文字为准。")
	if selection_label!=null:
		for biome in BIOME_LABELS: selection_label.text = selection_label.text.replace(" · "+biome+"\n"," · "+BIOME_LABELS[biome]+"\n")
	if plan_label!=null:plan_label.text=plan_label.text.replace("示例","预设")
	if feedback_label!=null:feedback_label.text=feedback_label.text.replace("示例","预设")
	_update_preset_summary()
	if adapter != null and adapter.ready().get("ok",false):
		identity_label.text+="\n原始地格判定：\n"+diagnostic_selection
		var phase:String=adapter.phase()
		if phase=="idle":plan_label.text="等待填写与评估，当前不会执行行动。"
		elif phase=="awaiting_assessment":plan_label.text="等待有效离线评估，尚未执行。"
		else:
			identity_label.text+="\n"+plan_label.text
			var action:Dictionary=adapter.action_copy()
			plan_label.text="待确认："+str(action.get("goal","")).trim_prefix("【探索示例】")+"\n离线评估已冻结；确认后才结算。"
			var route:Dictionary=adapter.frozen_movement_preview()
			if not route.is_empty():plan_label.text+="\n路线 %d 步 · 体力 -%d" % [route.route.size()-1,route.cost]

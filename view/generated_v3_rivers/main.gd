extends Control
## Standalone opt-in river slice. Examples populate text; Assess freezes a plan;
## Apply alone resolves and commits. Selection and camera controls never act.
const Adapter = preload("res://view/generated_v3_rivers/adapter.gd")
const Source = preload("res://view/generated_v3_rivers/source.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const Board = preload("res://view/generated_v3_rivers/board.gd")
var adapter: RefCounted
var board: Node3D
var viewport: SubViewport
var selected_focus: Dictionary = {}
var state_label: Label
var selection_label: Label
var plan_label: Label
var feedback_label: Label
var identity_label: Label
var goal_edit: TextEdit
var assess_button: Button
var apply_button: Button
var cancel_button: Button
var example_buttons: Array[Button] = []
var save_button: Button
var load_button: Button
var export_button: Button
var _busy := false

func _ready() -> void:
	_build_ui()
	_start.call_deferred()

func _build_ui() -> void:
	var palette := Theme.new()
	palette.default_font_size = 17
	var font_path := "res://assets/NotoSansCJK-Regular.ttc"
	if ResourceLoader.exists(font_path): palette.default_font = load(font_path)
	theme = palette
	var background := ColorRect.new(); background.color = Color("182b31"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,14)
	add_child(margin)
	var outer := VBoxContainer.new(); outer.add_theme_constant_override("separation",10); margin.add_child(outer)
	var header := HBoxContainer.new(); outer.add_child(header)
	var title := _label("PHYSICAL RIVERS  /  限定测试",24); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(_button("正常视角",func(): if is_instance_valid(board): board.normal_zoom()))
	header.add_child(_button("近看旅人",func(): if is_instance_valid(board): board.closer_zoom()))
	header.add_child(_button("俯视",func(): if is_instance_valid(board): board.top_down()))
	header.add_child(_button("↶",func(): if is_instance_valid(board): board.rotate_view(-0.30)))
	header.add_child(_button("↷",func(): if is_instance_valid(board): board.rotate_view(0.30)))
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",14); outer.add_child(body)
	var map_column := VBoxContainer.new(); map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(map_column)
	var view_container := SubViewportContainer.new()
	view_container.stretch = true; view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL; view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.add_child(view_container)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.handle_input_locally = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view_container.add_child(viewport)
	map_column.add_child(_label("左键只选地格 · 右键拖动旋转 · 滚轮缩放 · 金色棋子是旅人",15))
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = 422; body.add_child(panel)
	var panel_style := StyleBoxFlat.new(); panel_style.bg_color = Color("263c40"); panel_style.set_corner_radius_all(8); panel.add_theme_stylebox_override("panel",panel_style)
	var panel_margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: panel_margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(panel_margin)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; panel_margin.add_child(scroll)
	var controls := VBoxContainer.new(); controls.custom_minimum_size.x = 374; controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls.add_theme_constant_override("separation",10); scroll.add_child(controls)
	state_label = _label("正在校验原始地图、真实河槽和水面…",19); controls.add_child(state_label)
	identity_label = _label("仅已验证样本 · seed 726381 · radius 4 · coastal_range",13); identity_label.modulate = Color("b2c9c7"); controls.add_child(identity_label)
	controls.add_child(HSeparator.new())
	selection_label = _label("尚未选择地格",16); controls.add_child(selection_label)
	controls.add_child(_button("选择相邻干地（仅选择）",_select_neighbor))
	var examples := HBoxContainer.new(); controls.add_child(examples)
	for pair in [["move","移动示例"],["observe","观察示例"],["rest","休息示例"]]:
		var kind: String = pair[0]
		var button := _button(pair[1],func(): _choose_example(kind)); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		examples.add_child(button); example_buttons.append(button)
	goal_edit = TextEdit.new(); goal_edit.custom_minimum_size = Vector2(0,86); goal_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; goal_edit.placeholder_text = "先选择地格，再点一个完整示例；每次行动都必须评估并确认。"; controls.add_child(goal_edit)
	controls.add_child(_label("内置评估由作者预先编写，未调用 AI。编辑成自由文字后，不会自动猜测或执行。",13))
	var actions := HBoxContainer.new(); controls.add_child(actions)
	assess_button = _button("1  评估",_assess); apply_button = _button("2  确认执行",_apply); cancel_button = _button("取消",_cancel)
	for button in [assess_button,apply_button,cancel_button]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(button)
	plan_label = _label("尚未评估；世界没有变化。",15); controls.add_child(plan_label)
	feedback_label = _label("",16); feedback_label.modulate = Color("ffe5a4"); controls.add_child(feedback_label)
	controls.add_child(HSeparator.new())
	var files := HBoxContainer.new(); controls.add_child(files)
	save_button = _button("保存进度",_save); load_button = _button("读取进度",_load)
	for button in [save_button,load_button]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; files.add_child(button)
	export_button = _button("导出待评估请求",_export_request); controls.add_child(export_button)
	controls.add_child(_label("独立河流存档；原版 v21 和旧探索存档保持原样。",13))
	var warning := PanelContainer.new(); outer.add_child(warning)
	var warning_style := StyleBoxFlat.new(); warning_style.bg_color = Color("493d29"); warning_style.content_margin_left = 14; warning_style.content_margin_right = 14; warning_style.content_margin_top = 9; warning_style.content_margin_bottom = 9; warning.add_theme_stylebox_override("panel",warning_style)
	warning.add_child(_label("当前通行限制：暂时每格只有一个中心锚点。河心锚点入水时，此锚点不可达；不代表该格剩余陆地不可通行。河岸锚点与渡河尚未实现，没有桥梁通行。\nTemporary one-anchor-per-cell traversal: wet river-center anchors are blocked; remaining land is not inherently impassable. Bank anchors and crossings are not implemented.",14))
	_refresh()

func _label(value: String, size_: int = 17) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_size_override("font_size",size_); return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = value; button.custom_minimum_size.y = 34; button.pressed.connect(callback); return button

func _start() -> void:
	var generated: Dictionary = Generator.generate(726381,4,"coastal_range")
	if not generated.get("ok",false): _feedback(generated); return
	adapter = Adapter.new(generated.source)
	if not adapter.ready().ok: _feedback(adapter.ready()); _refresh(); return
	board = Board.new(adapter.source); viewport.add_child(board); board.set_world(adapter.state_copy()); board.hex_selected.connect(_select)
	if not board.load_error.is_empty(): _feedback({"ok":false,"errors":[board.load_error]}); return
	_select(adapter.state_copy().actors.actor_player.hex)
	_select_neighbor()
	feedback_label.text = "已在最大实际干地连通区落脚。点地图只选择，不消耗回合或体力。"
	_refresh()

func _select(hex: Array) -> void:
	if adapter == null or not adapter.ready().ok: return
	var reference: Dictionary = adapter.tile_reference(hex)
	var attention: Dictionary = adapter.attention(reference)
	if not attention.get("ok",false): _feedback(attention); return
	selected_focus = reference
	board.select_hex(hex)
	_refresh()

func _select_neighbor() -> void:
	if adapter == null or not adapter.ready().ok: return
	var actor: Dictionary = adapter.state_copy().actors.actor_player
	var key: String = "%d,%d" % actor.hex
	var neighbors: Array = adapter.source.navigation.allowed.get(key,[])
	if neighbors.is_empty(): feedback_label.text = "当前位置没有已验证的相邻干地锚点。"; return
	var choice: String = neighbors[0]
	for neighbor in neighbors:
		if selected_focus.get("hex",[]) != [adapter.source.data.cells[neighbor].q,adapter.source.data.cells[neighbor].r]: choice = neighbor; break
	var cell: Dictionary = adapter.source.data.cells[choice]
	_select([cell.q,cell.r])

func _choose_example(kind: String) -> void:
	if adapter == null or not adapter.ready().ok or adapter.phase() != "idle": return
	goal_edit.text = adapter.sample_goal(kind,selected_focus)
	feedback_label.text = "示例已填入；请先评估。行动尚未执行。"

func _assess() -> void:
	if _busy or adapter == null or not adapter.ready().ok or adapter.phase() != "idle": return
	_busy = true
	var checked: Dictionary = adapter.begin_intent(goal_edit.text,selected_focus)
	if checked.get("ok",false): checked = adapter.prepare_fixture()
	_feedback(checked,"评估已冻结，世界尚未改变。检查下方计划后确认执行，或取消。")
	_busy = false; _refresh()

func _apply() -> void:
	if _busy or adapter == null or not adapter.ready().ok: return
	if not adapter.phase() in ["ready_roll","rolled","staged"]: return
	_busy = true
	var checked := {"ok":true}
	if adapter.phase() == "ready_roll": checked = adapter.roll_once()
	if checked.get("ok",false) and adapter.phase() == "rolled": checked = adapter.stage()
	if checked.get("ok",false) and adapter.phase() == "staged": checked = adapter.commit()
	_feedback(checked,adapter.last_feedback if checked.get("ok",false) else "")
	if checked.get("ok",false):
		board.set_world(adapter.state_copy()); goal_edit.text = ""
	_busy = false; _refresh()

func _cancel() -> void:
	if _busy or adapter == null or not adapter.can_cancel(): return
	_feedback(adapter.cancel(),"已取消；回合、体力和坐标没有变化。")
	_refresh()

func _save() -> void:
	if adapter == null: return
	_feedback(adapter.save_file(),"河流进度已保存，包括尚未执行的评估。")
	_refresh()

func _load() -> void:
	if _busy or adapter == null: return
	_busy = true
	var checked: Dictionary = adapter.load_file()
	if checked.get("ok",false):
		board.admitted_source = adapter.source; board.set_world(adapter.state_copy())
		if not selected_focus.is_empty(): selected_focus = adapter.tile_reference(selected_focus.hex)
		goal_edit.text = str(adapter.action_copy().get("goal",""))
	_feedback(checked,"河流进度已恢复；原始地图、河槽、水面和行动身份校验一致。")
	_busy = false; _refresh()

func _export_request() -> void:
	if adapter == null: return
	_feedback(adapter.export_request(),"已导出独立河流请求："+adapter.default_request_path())

func _feedback(result: Dictionary, success: String = "") -> void:
	feedback_label.text = success if result.get("ok",false) else "%s\n%s" % [result.get("code","NOT_READY"),"\n".join(result.get("errors",["校验未通过，世界保持原样。"]))]

func _refresh() -> void:
	var ready_: bool = adapter != null and adapter.ready().get("ok",false)
	var phase_: String = adapter.phase() if ready_ else "unavailable"
	assess_button.disabled = not ready_ or phase_ != "idle" or _busy
	apply_button.disabled = not ready_ or not phase_ in ["ready_roll","rolled","staged"] or _busy
	cancel_button.disabled = not ready_ or not adapter.can_cancel() or _busy
	for button in example_buttons: button.disabled = not ready_ or phase_ != "idle" or _busy
	goal_edit.editable = ready_ and phase_ == "idle"
	save_button.disabled = not ready_ or _busy; load_button.disabled = not ready_ or _busy
	export_button.disabled = not ready_ or phase_ != "awaiting_assessment"
	if not ready_: return
	var state: Dictionary = adapter.state_copy()
	var actor: Dictionary = state.actors.actor_player
	state_label.text = "旅人 (%d, %d)  ·  回合 %d\n体力 %d / %d  ·  已观察 %d 次" % [actor.hex[0],actor.hex[1],state.turn,actor.stamina.current,actor.stamina.max,state.flags.observations]
	identity_label.text = "仅已验证样本 · seed 726381 · radius 4 · coastal_range\nstructured_rivers_v1 · 最大干地连通区 %d 格\nsource %s  /  mesh %s\nwater %s  /  layout %s" % [adapter.source.spawn_component.size(),str(adapter.source.identity.content_hash).left(8),str(adapter.source.identity.geometry_hash).left(8),str(adapter.source.identity.water_hash).left(8),str(adapter.source.identity.river_layout_hash).left(8)]
	if not selected_focus.is_empty():
		var key: String = "%d,%d" % selected_focus.hex
		var cell: Dictionary = state.hexes[key]
		var supported: bool = adapter.source.navigation.supported.get(key,false)
		selection_label.text = "已选 (%d, %d) · %s\n%s\n选中不等于行动目标；行动使用评估时冻结的文字目标。" % [cell.q,cell.r,cell.biome,"中心锚点有实际干地支撑" if supported else "中心锚点被水面或安全净距阻挡"]
	var route: Array = []
	if phase_ == "idle":
		plan_label.text = "尚未评估；世界没有变化。"
		if not selected_focus.is_empty():
			var preview: Dictionary = adapter.movement_preview(selected_focus.hex)
			if preview.get("ok",false):
				route = preview.route
				plan_label.text = "只读路线预览：%d 步，消耗 %d 点体力。\n仍需明确选择移动示例、评估和确认。" % [preview.route.size()-1,preview.cost]
	elif phase_ == "awaiting_assessment":
		plan_label.text = "已记录意图，等待有效评估。未执行。\n自由文字不会由示例自动补全；可以取消或导出请求。"
	else:
		var action: Dictionary = adapter.action_copy()
		plan_label.text = "已冻结："+str(action.goal)+"\n作者预编写评估 · A=3, D=1, P=0\n程序已校验前提，使用原有固定规则。确认前不改变世界。"
		var frozen: Dictionary = adapter.frozen_movement_preview()
		if not frozen.is_empty():
			route = frozen.route
			plan_label.text += "\n路线 %d 步 · 体力 -%d · 回合 +1" % [frozen.route.size()-1,frozen.cost]
		elif action.get("assessment",{}).get("resolver_id") == "generated_v3_rivers_observe_v1": plan_label.text += "\n观察记录 +1 · 回合 +1"
		elif action.get("assessment",{}).get("resolver_id") == "generated_v3_rivers_rest_v1": plan_label.text += "\n体力恢复最多 2 点 · 回合 +1"
	if is_instance_valid(board): board.set_route_preview(route)

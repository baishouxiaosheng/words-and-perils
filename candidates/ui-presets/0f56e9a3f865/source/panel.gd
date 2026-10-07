extends "res://view/runtime_ai/connection_panel.gd"
## Reuse existing actions, automatic toggles and runtime binding. The old single
## credential form stays hidden; the modal stages both roles atomically.
signal modal_visibility_changed(open: bool)
const TypeStyle = preload("res://view/ui_typography/style.gd")
const Presets = preload("res://view/dual_api_settings/provider_presets.gd")
var dialog_scroll: ScrollContainer
var dialog_content: VBoxContainer
var settings_dialog
var settings_button: Button
var role_fields: Dictionary = {}
var enable_input: CheckBox
var assessment_draft_input: CheckBox
var narration_draft_input: CheckBox
var _request_preferences_saved := false
var dialog_status: Label
var summary_label: Label
var _building := false

func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is Control and child not in [automatic_assessment_input, automatic_narration_input, status_label, assessment_button.get_parent()]: child.hide()
	settings_button = Button.new(); settings_button.text = "API设置 · 叙事 / 快速决策"; settings_button.pressed.connect(open_settings)
	add_child(settings_button); move_child(settings_button, 0); _paper_button(settings_button)
	summary_label = Label.new(); summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(summary_label); move_child(summary_label, 1)
	_build_dialog()
	settings_dialog.get_parent().get_viewport().size_changed.connect(_resize_api_window)
	_refresh()

func _build_dialog() -> void:
	settings_dialog = preload("res://view/ui_motion/modal_window.gd").new(); settings_dialog.configure(&"large",{"preferred":Vector2(780,690)}); settings_dialog.name = "DualAPISettings"
	settings_dialog.set_meta(TypeStyle.META, true) # This form owns explicit semantic typography.
	settings_dialog.title = "API设置"; settings_dialog.ok_button_text = "保存到本次运行"; settings_dialog.cancel_button_text = "取消"
	settings_dialog.dialog_hide_on_ok = false
	settings_dialog.exclusive = true; settings_dialog.unresizable = false
	settings_dialog.min_size = Vector2i(0, 0)
	settings_dialog.confirmed.connect(_save_settings)
	settings_dialog.canceled.connect(_discard_settings)
	# The presentation shell routes X/Escape through the same canceled signal.
	settings_dialog.visibility_changed.connect(func():
		if not settings_dialog.visible: _wipe_inputs()
		modal_visibility_changed.emit(settings_dialog.visible))
	var scene: Node = get_tree().current_scene
	(scene if scene != null else get_tree().root).add_child(settings_dialog)
	dialog_scroll = ScrollContainer.new(); dialog_scroll.name = "APIFormScroll"
	dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog_scroll.follow_focus = true; settings_dialog.add_child(dialog_scroll)
	var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["margin_left", "margin_right"]: margin.add_theme_constant_override(edge, 24)
	for edge in ["margin_top", "margin_bottom"]: margin.add_theme_constant_override(edge, 16)
	dialog_scroll.add_child(margin)
	dialog_content = VBoxContainer.new(); dialog_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_content.add_theme_constant_override("separation", 20); margin.add_child(dialog_content)
	var intro := _copy_label("分别选择叙事与快速决策的服务商、模型和密钥。\n保存只作本地校验，不发送请求；地址不变时，密钥留空保留。", TypeStyle.HELP)
	dialog_content.add_child(intro)
	for role in ["narration", "decision"]:
		var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 8); dialog_content.add_child(card)
		var heading := _copy_label("叙事API" if role == "narration" else "快速决策模型API", TypeStyle.HEADING, true); card.add_child(heading)
		var identity_row := BoxContainer.new(); identity_row.add_theme_constant_override("separation",12); card.add_child(identity_row)
		var preset_box := VBoxContainer.new(); preset_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; preset_box.add_theme_constant_override("separation",6); identity_row.add_child(preset_box)
		preset_box.add_child(_copy_label("服务商 / 区域",TypeStyle.LABEL))
		var preset := OptionButton.new(); preset.custom_minimum_size.y=44; preset.clip_text=true
		for label_ in Presets.LABELS: preset.add_item(label_)
		preset_box.add_child(preset)
		var model_box := VBoxContainer.new(); model_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; model_box.add_theme_constant_override("separation",6); identity_row.add_child(model_box)
		model_box.add_child(_copy_label("模型（预设 / 自定义）",TypeStyle.LABEL))
		var model_choice := OptionButton.new();model_choice.custom_minimum_size.y=44;model_choice.clip_text=true;model_choice.allow_reselect=true;model_box.add_child(model_choice)
		var model := LineEdit.new(); model.placeholder_text="仅自定义模型需要填写 ID"; model.custom_minimum_size.y=42; model.size_flags_horizontal=Control.SIZE_EXPAND_FILL;model.add_theme_color_override("font_uneditable_color",TypeStyle.INK)
		var key := LineEdit.new(); key.secret = true; key.context_menu_enabled = false
		key.placeholder_text = "输入API Key；留空保留本次运行的密钥"
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL; key.custom_minimum_size.y = 44; card.add_child(key)
		key.set_meta(&"type_size", TypeStyle.FIELD)
		var key_note := _copy_label("服务地址已更换，请重新输入该用途的密钥；原密钥仍保留。",TypeStyle.HELP);key_note.hide();card.add_child(key_note)
		var state := _copy_label("", TypeStyle.HELP); card.add_child(state)
		var toggle := Button.new(); toggle.text = "服务地址与模型 · 高级选项"; toggle.toggle_mode = true; card.add_child(toggle)
		var advanced := VBoxContainer.new(); advanced.add_theme_constant_override("separation", 12); card.add_child(advanced); advanced.hide()
		toggle.toggled.connect(func(value: bool):
			advanced.visible = value
			if not value: _reveal_form_control.call_deferred(toggle))
		advanced.add_child(_copy_label("接口协议：OpenAI兼容 Chat Completions JSON\n请填写提供商的实际地址与model ID，密钥不会自动选择模型。", TypeStyle.HELP))
		var endpoint := _dialog_field(advanced, "完整HTTPS请求地址", "https://提供商地址/v1/chat/completions")
		advanced.add_child(_copy_label("精确模型 ID（列表预设只读；自定义可填）",TypeStyle.LABEL));advanced.add_child(model)
		advanced.add_child(_copy_label("模型目录于 "+Presets.MODEL_CATALOG_CHECKED+" 核对；未验证账号权限或真实服务。\n选择模型只修改表单，不发送请求，也不会自动改用其他型号。",TypeStyle.HELP))
		var token_caption := _copy_label("输出上限参数（保留原token预算）",TypeStyle.LABEL);advanced.add_child(token_caption)
		var token_field := OptionButton.new();token_field.add_item("max_completion_tokens");token_field.add_item("max_tokens");token_field.custom_minimum_size.y=42;advanced.add_child(token_field)
		var json_mode := CheckBox.new();json_mode.text="服务端 JSON Object（模型支持时启用）";advanced.add_child(json_mode)
		advanced.add_child(_copy_label("默认兼容模式不附加JSON格式或推理开关；仍严格验证收到的JSON。\nreasoning_effort留空使用服务商默认，不代表关闭思考；不按模型名猜参数。",TypeStyle.HELP))
		var reasoning := _dialog_field(advanced, "reasoning_effort（支持时手动填写）", "默认不发送此参数")
		var time_row := HBoxContainer.new(); time_row.add_theme_constant_override("separation", 12); advanced.add_child(time_row)
		var time_label := _copy_label("等待超时（秒）", TypeStyle.LABEL)
		time_label.autowrap_mode = TextServer.AUTOWRAP_OFF; time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; time_row.add_child(time_label)
		var timeout := SpinBox.new(); timeout.min_value = 1; timeout.max_value = 120; timeout.value = 30; timeout.custom_minimum_size.y = 42; time_row.add_child(timeout)
		var budget := _dialog_field(advanced, "公开JSON上限（字节，最多131072）", "65536")
		var local := CheckBox.new(); local.text = "允许仅本机HTTP（开发选项）"; advanced.add_child(local)
		role_fields[role] = {"custom_model_draft":"","model_choice":model_choice,"preset":preset,"identity_row":identity_row,"key_note":key_note,"draft_endpoint":"","json_mode":json_mode,"token_parameter":token_field,"key": key, "state": state, "toggle": toggle, "advanced": advanced, "endpoint": endpoint, "model": model, "reasoning": reasoning, "timeout": timeout, "budget": budget, "local": local}
		preset.item_selected.connect(func(index: int): _preset_selected(role,index))
		model_choice.item_selected.connect(func(index: int): _model_selected(role,index))
		model.text_changed.connect(func(value: String):
			if not _building and _custom_model_selected(role):
				role_fields[role].custom_model_draft=value
				model_choice.set_item_text(model_choice.selected,"自定义模型…")
				model_choice.tooltip_text="精确 ID："+value)
		endpoint.text_changed.connect(func(_value: String): _endpoint_edited(role))
	var consent_group := VBoxContainer.new(); consent_group.add_theme_constant_override("separation", 6); dialog_content.add_child(consent_group)
	enable_input = CheckBox.new(); enable_input.text = "启用API请求"; consent_group.add_child(enable_input)
	consent_group.add_child(_copy_label("发送公开游戏上下文，可能计费。保存不发送请求；以下两项默认勾选，可分别取消。", TypeStyle.HELP))
	assessment_draft_input = CheckBox.new(); assessment_draft_input.text = "自动请求评估（可能计费）"; consent_group.add_child(assessment_draft_input)
	consent_group.add_child(_copy_label("开启后，你提交行动时才请求评估；关闭则等待手动请求或导入裁定。", TypeStyle.HELP))
	narration_draft_input = CheckBox.new(); narration_draft_input.text = "自动叙事（额外计费）"; consent_group.add_child(narration_draft_input)
	consent_group.add_child(_copy_label("只在回合已结算后请求一次描述；失败不改变结果，不自动重试。", TypeStyle.HELP))
	dialog_content.add_child(_copy_label("仅保存在本次运行内存，关闭游戏后需重新输入。\n密钥不写入存档或历史；取消放弃本次全部修改。", TypeStyle.HELP))
	dialog_status = _copy_label("", TypeStyle.HELP); dialog_status.name = "APIValidationMessage"; dialog_status.hide(); dialog_content.add_child(dialog_status)

func _preset_selected(role: String, index: int) -> void:
	if _building or not role_fields.has(role): return
	var fields: Dictionary=role_fields[role]
	var id: String=Presets.IDS[index]
	if id!="custom":
		fields.endpoint.text=Presets.ENDPOINTS[id]
		fields.draft_endpoint=Presets.endpoint_binding(fields.endpoint.text)
		fields.model.text=""
		fields.key.text=""
		fields.reasoning.text=""
		fields.json_mode.button_pressed=false
		fields.token_parameter.select(1 if Presets.token_parameter(id)=="max_tokens" else 0)
	fields.token_parameter.disabled=id!="custom"
	_populate_models(role,String(fields.model.text),id!="custom")
	_update_key_binding_note(role)

func _custom_model_selected(role: String) -> bool:
	var picker: OptionButton=role_fields[role].model_choice
	return picker.selected<0 or String(picker.get_item_metadata(picker.selected)).is_empty()

func _populate_models(role: String, existing: String, choose_default: bool) -> void:
	var fields: Dictionary=role_fields[role]
	var picker: OptionButton=fields.model_choice
	picker.clear()
	var rows: Array=Presets.models(Presets.IDS[fields.preset.selected])
	var selected: int=-1
	for row in rows:
		picker.add_item(String(row.label))
		var index: int=picker.item_count-1
		picker.set_item_metadata(index,String(row.id));picker.set_item_tooltip(index,String(row.id))
		if String(row.id)==existing:selected=index
	fields.custom_model_draft=existing
	picker.add_item("自定义模型…")
	var custom: int=picker.item_count-1;picker.set_item_metadata(custom,"")
	if choose_default and not rows.is_empty():selected=0
	if selected<0:selected=custom
	picker.select(selected)
	var model_id: String=String(picker.get_item_metadata(selected))
	fields.model.text=existing if model_id.is_empty() else model_id
	fields.model.editable=model_id.is_empty()
	picker.tooltip_text="精确 ID："+fields.model.text if not fields.model.text.is_empty() else "先选择服务商和预设模型；自定义主机请自行指定型号"

func _model_selected(role: String, index: int) -> void:
	if _building or not role_fields.has(role): return
	var fields: Dictionary=role_fields[role]
	var model_id: String=String(fields.model_choice.get_item_metadata(index))
	fields.model.text=String(fields.custom_model_draft) if model_id.is_empty() else model_id
	fields.model.editable=model_id.is_empty() and (not is_instance_valid(runtime) or not runtime.busy())
	fields.model_choice.tooltip_text="精确 ID："+fields.model.text
	if model_id.is_empty():
		fields.toggle.button_pressed=true;fields.advanced.show()
		_reveal_form_control.call_deferred(fields.model)

func _endpoint_edited(role: String) -> void:
	if _building or not role_fields.has(role): return
	var fields: Dictionary=role_fields[role]
	var next_endpoint: String=Presets.endpoint_binding(fields.endpoint.text)
	if next_endpoint!=String(fields.draft_endpoint): fields.key.text=""
	fields.draft_endpoint=next_endpoint
	_update_key_binding_note(role)

func _update_key_binding_note(role: String) -> void:
	var fields: Dictionary=role_fields[role]
	var old: Dictionary=runtime.client.role_configuration(role) if is_instance_valid(runtime) else {}
	var changed: bool=not old.is_empty() and Presets.endpoint_binding(String(old.get("endpoint","")))!=Presets.endpoint_binding(fields.endpoint.text)
	fields.key_note.visible=changed
	fields.key.placeholder_text="地址已更换，请重新输入API Key" if changed else "输入API Key；地址不变时，留空保留本次运行的密钥"

func _copy_label(value: String, size_: int, bold: bool = false) -> Label:
	var label_ := Label.new(); label_.text = value
	label_.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_.set_meta(&"type_size", size_); label_.set_meta(&"type_bold", bold)
	return label_

func _dialog_field(parent_: VBoxContainer, caption: String, placeholder: String) -> LineEdit:
	var group := VBoxContainer.new(); group.add_theme_constant_override("separation", 6); parent_.add_child(group)
	group.add_child(_copy_label(caption, TypeStyle.LABEL))
	var input := LineEdit.new(); input.placeholder_text = placeholder; input.custom_minimum_size.y = 42
	input.set_meta(&"type_size", TypeStyle.FIELD); input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; group.add_child(input)
	return input

func _paper_button(button_: Button) -> void:
	TypeStyle.paper_button(button_, get_theme_default_font())

func _form_fonts(node: Node, face: Font) -> void:
	if node is Label:
		var size_: int = node.get_meta(&"type_size", TypeStyle.HELP)
		TypeStyle.text(node, size_, face, node.get_meta(&"type_bold", false), TypeStyle.INK if size_ >= TypeStyle.LABEL else TypeStyle.MUTED)
	elif node is Button: TypeStyle.paper_button(node, face)
	elif node is LineEdit: TypeStyle.text(node, TypeStyle.FIELD, face)
	for child in node.get_children(): _form_fonts(child, face)

func _reveal_form_control(control: Control) -> void:
	if is_instance_valid(settings_dialog) and settings_dialog.visible and is_instance_valid(control): dialog_scroll.ensure_control_visible(control)

func open_settings() -> void:
	if not is_instance_valid(runtime) or not is_instance_valid(settings_dialog): return
	if settings_dialog.visible: settings_dialog.grab_focus(); return
	_building = true
	for role in role_fields:
		var fields: Dictionary = role_fields[role]
		var config: Dictionary = runtime.client.role_configuration(role)
		fields.key.text = ""
		var preset_id: String=String(config.get("service_preset",Presets.infer(String(config.get("endpoint","")))))
		fields.preset.select(maxi(0,Presets.IDS.find(preset_id)))
		fields.endpoint.text = String(config.get("endpoint", ""))
		fields.draft_endpoint=Presets.endpoint_binding(fields.endpoint.text)
		fields.json_mode.button_pressed=bool(config.get("json_object_mode",not config.is_empty()))
		fields.token_parameter.select(1 if String(config.get("token_parameter",Presets.token_parameter(preset_id)))=="max_tokens" else 0)
		fields.token_parameter.disabled=preset_id!="custom"
		fields.key_note.hide()
		fields.model.text = String(config.get("model", ""))
		_populate_models(role,fields.model.text,false)
		fields.reasoning.text = String(config.get("reasoning_effort", ""))
		fields.timeout.value = float(config.get("timeout_seconds", 30))
		fields.budget.text = str(config.get("public_request_budget_bytes", 65536))
		fields.local.button_pressed = bool(config.get("allow_localhost_http", false))
		fields.toggle.button_pressed = false; fields.advanced.hide()
		fields.state.text = "当前会话："+runtime.client.role_status(role)
		fields.model.placeholder_text="填写完整 provider/model ID" if preset_id=="openrouter" else "填写服务商实际 model ID"
		_update_key_binding_note(role)
	enable_input.button_pressed = runtime.connection_enabled
	assessment_draft_input.set_pressed_no_signal(runtime.automatic_assessment if _request_preferences_saved else true)
	narration_draft_input.set_pressed_no_signal(runtime.automatic_narration if _request_preferences_saved else true)
	dialog_status.text = ""; dialog_status.hide()
	_building = false
	var ancestor: Node = self
	while ancestor != null:
		if ancestor is Control and ancestor.theme != null:
			settings_dialog.theme = ancestor.theme; break
		ancestor = ancestor.get_parent()
	var face: Font = get_theme_default_font()
	settings_dialog.theme = settings_dialog.theme.duplicate() if settings_dialog.theme != null else Theme.new()
	TypeStyle.theme_fonts(settings_dialog.theme, face)
	settings_dialog.theme.set_font_size("title_font_size", "Window", TypeStyle.TITLE)
	_form_fonts(settings_dialog, face)
	TypeStyle.paper_button(settings_dialog.get_ok_button(), face); TypeStyle.paper_button(settings_dialog.get_cancel_button(), face)
	var bounds: Vector2 = settings_dialog.get_parent().get_viewport().get_visible_rect().size
	var extent:Vector2i = settings_dialog.adapted_extent(bounds)
	for fields in role_fields.values(): fields.identity_row.vertical=extent.x<620
	dialog_scroll.custom_minimum_size = Vector2(maxi(260, extent.x - 40), maxi(200, extent.y - 96))
	settings_dialog.popup_centered_clamped(extent, 0.94)
	dialog_scroll.scroll_vertical = 0
	_refresh()

func _resize_api_window() -> void:
	if not is_instance_valid(settings_dialog) or not settings_dialog.visible: return
	var bounds: Vector2 = settings_dialog.get_parent().get_viewport().get_visible_rect().size
	var extent:Vector2i = settings_dialog.adapted_extent(bounds)
	for fields in role_fields.values(): fields.identity_row.vertical=extent.x<620
	dialog_scroll.custom_minimum_size = Vector2(maxi(260, extent.x - 40), maxi(200, extent.y - 96))
	settings_dialog.size = extent
	TypeStyle.settle_dialog_size(settings_dialog, Vector2(extent), bounds)

func _save_settings() -> void:
	_consume_form_event()
	if not is_instance_valid(runtime) or runtime.busy(): return
	var edits: Dictionary = {}
	for role in role_fields:
		var fields: Dictionary = role_fields[role]
		var budget_text: String = fields.budget.text.strip_edges()
		var budget_value := int(budget_text) if budget_text.is_valid_int() and budget_text.length() <= 12 else -1
		var config: Dictionary = runtime.client.role_configuration(role)
		config.merge({"service_preset":Presets.IDS[fields.preset.selected],"token_parameter":"max_tokens" if fields.token_parameter.selected==1 else "max_completion_tokens","json_object_mode":fields.json_mode.button_pressed,"provider": "openai_compatible_json", "endpoint": fields.endpoint.text, "model": fields.model.text, "reasoning_effort": fields.reasoning.text, "timeout_seconds": fields.timeout.value, "public_request_budget_bytes": budget_value, "allow_localhost_http": fields.local.button_pressed}, true)
		edits[role] = {"key": fields.key.text, "config": config}
	var result: Dictionary = runtime.client.configure_roles(edits)
	_wipe_inputs()
	if not result.ok:
		dialog_status.show()
		dialog_status.add_theme_color_override("font_color", TypeStyle.ERROR)
		dialog_status.text = "；".join(result.get("errors", ["设置未保存，原配置保留。"])) + " 两项原配置均保留；请修正后重新输入需要更换的密钥。"
		_focus_validation_error.call_deferred()
		return
	runtime.connection_enabled = enable_input.button_pressed and runtime.client.any_role_configured()
	_request_preferences_saved = true
	runtime.automatic_assessment = assessment_draft_input.button_pressed
	runtime.automatic_narration = narration_draft_input.button_pressed
	automatic_assessment_input.set_pressed_no_signal(runtime.automatic_assessment)
	automatic_narration_input.set_pressed_no_signal(runtime.automatic_narration)
	consent_input.set_pressed_no_signal(runtime.connection_enabled); _dirty = false
	set_status(String(result.message)); configuration_applied.emit(result)
	settings_dialog.request_motion_close(); _refresh()

func _focus_validation_error() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(settings_dialog) and settings_dialog.visible:
		dialog_scroll.ensure_control_visible(dialog_status)
		dialog_scroll.scroll_vertical = int(dialog_scroll.get_v_scroll_bar().max_value)

func close_settings() -> void: _discard_settings()

func _consume_form_event() -> void:
	if is_instance_valid(settings_dialog):
		settings_dialog.set_input_as_handled()
		settings_dialog.get_parent().get_viewport().set_input_as_handled()

func _discard_settings() -> void:
	_consume_form_event()
	_wipe_inputs()
	if is_instance_valid(settings_dialog): settings_dialog.request_motion_close()
	_refresh()

func _wipe_inputs() -> void:
	for role in role_fields:
		if is_instance_valid(role_fields[role].key): role_fields[role].key.text = ""

func _apply() -> void: open_settings()
func _clear() -> void:
	# Retained compatibility entry is explicit, never called for invalid/blank save.
	if is_instance_valid(runtime):
		runtime.invalidate_context(); runtime.connection_enabled = false
	super._clear()
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(runtime) or not is_instance_valid(assessment_button): return
	var working: bool = runtime.busy()
	var enabled: bool = runtime.connection_enabled
	assessment_button.disabled = working or not enabled or not runtime.client.role_configured("decision") or runtime.phase() != "awaiting_assessment" or runtime.cooldown_remaining() > 0.0
	narration_button.disabled = working or not enabled or not runtime.client.role_configured("narration") or runtime.phase() != "committed" or runtime.narration_recorded()
	cancel_button.disabled = not working
	for toggle in [automatic_assessment_input, automatic_narration_input]:
		if is_instance_valid(toggle): toggle.disabled = working
	if is_instance_valid(summary_label): summary_label.text = "叙事：" + runtime.client.role_status("narration") + "\n快速决策：" + runtime.client.role_status("decision") + ("\n连接已启用" if enabled else "\n连接已禁用 · 可继续离线")
	if is_instance_valid(settings_dialog):
		settings_dialog.get_ok_button().disabled = working
		for role in role_fields:
			for name_ in ["key", "endpoint", "reasoning", "budget", "timeout"]: role_fields[role][name_].editable = not working
			role_fields[role].local.disabled = working
			role_fields[role].preset.disabled=working
			role_fields[role].model_choice.disabled=working
			role_fields[role].model.editable=not working and _custom_model_selected(role)
			role_fields[role].json_mode.disabled=working
			role_fields[role].token_parameter.disabled=working or Presets.IDS[role_fields[role].preset.selected]!="custom"
		enable_input.disabled = working
		assessment_draft_input.disabled = working
		narration_draft_input.disabled = working

func _exit_tree() -> void:
	_wipe_inputs()
	if is_instance_valid(settings_dialog): settings_dialog.queue_free()
	super._exit_tree()

func _on_completed(result: Dictionary) -> void:
	if result.get("ok", false) and result.get("phase") == "intention":
		set_status(("真实HTTP响应" if result.get("transport", {}).get("live", false) else "本地mock测试响应（非AI）") + "：意图提案已校验；仍需普通评估，尚未结算。")
		_refresh()
	else: super._on_completed(result)

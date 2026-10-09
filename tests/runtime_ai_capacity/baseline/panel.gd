extends VBoxContainer
## Drop-in settings/actions only. No request is sent on configure, open or load.
## bind_client() takes the runtime client; the caller owns assessment/narration wiring.
signal assessment_requested
signal narration_requested
signal cancellation_requested
signal configuration_applied(result: Dictionary)
var endpoint_input: LineEdit
var model_input: LineEdit
var reasoning_input: LineEdit
var key_input: LineEdit
var timeout_input: SpinBox
var localhost_input: CheckBox
var consent_input: CheckBox
var apply_button: Button
var clear_button: Button
var assessment_button: Button
var narration_button: Button
var cancel_button: Button
var status_label: Label
var _client: Node
var _phase := "idle"
var _dirty := true

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	var title := Label.new(); title.text = "可选AI接口 · 默认离线"; add_child(title)
	var note := Label.new()
	note.text = "ChatGPT会员不等于API额度。没有API也能继续人工JSON与署名样例。\n仅实现可配置Chat Completions JSON接口；提供商与实际模型支持需自行确认。\n游戏偏好标签6.1sol低推理 / 6.0luna不是此处自动猜测的API model ID。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	endpoint_input = _field("完整HTTPS请求地址", "https://提供商地址/v1/chat/completions")
	model_input = _field("提供商实际model ID（必填）", "留空不会调用；不自动改用其他模型")
	reasoning_input = _field("reasoning_effort（可空，按提供商支持填写）", "空值不发送该字段；例如确认支持后填写low")
	key_input = _field("API密钥（仅当前运行内存）", "只在此本地应用输入；不在聊天索取")
	key_input.secret = true
	key_input.context_menu_enabled = false
	var timing := HBoxContainer.new(); add_child(timing)
	var timeout_label := Label.new(); timeout_label.text = "等待超时（秒）"; timing.add_child(timeout_label)
	timeout_input = SpinBox.new(); timeout_input.min_value = 1; timeout_input.max_value = 120; timeout_input.value = 30; timing.add_child(timeout_input)
	localhost_input = CheckBox.new(); localhost_input.text = "开发例外：允许仅本机localhost的HTTP（不加密）"; add_child(localhost_input)
	consent_input = CheckBox.new()
	consent_input.text = "我确认此地址支持该接口；点击AI按钮会发送公开游戏上下文，API可能计费"
	consent_input.toggled.connect(func(_value: bool): _refresh())
	add_child(consent_input)
	var settings := HBoxContainer.new(); add_child(settings)
	apply_button = Button.new(); apply_button.text = "应用到本次运行 · 不联网"; apply_button.pressed.connect(_apply); settings.add_child(apply_button)
	clear_button = Button.new(); clear_button.text = "清除连接与内存密钥"; clear_button.pressed.connect(_clear); settings.add_child(clear_button)
	var actions := HBoxContainer.new(); add_child(actions)
	assessment_button = Button.new(); assessment_button.text = "请求AI评估 · 可能计费"
	assessment_button.pressed.connect(func(): assessment_requested.emit()); actions.add_child(assessment_button)
	narration_button = Button.new(); narration_button.text = "请求只读叙事 · 可能计费"
	narration_button.pressed.connect(func(): narration_requested.emit()); actions.add_child(narration_button)
	cancel_button = Button.new(); cancel_button.text = "取消等待"
	cancel_button.pressed.connect(func():
		if is_instance_valid(_client): _client.cancel()
		cancellation_requested.emit())
	actions.add_child(cancel_button)
	status_label = Label.new(); status_label.text = "尚未配置API。密钥不会写入项目、存档或日志。"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status_label)
	var caution := Label.new(); caution.text = "无自动重试或后台调用。取消/超时可能仍被服务端计费。叙事失败不会回滚已确定数值。\n请勿将带密钥的页面用于截图或共享；关闭游戏后需重新输入。人工JSON路径保留。"
	caution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(caution)
	for input in [endpoint_input, model_input, reasoning_input]: input.text_changed.connect(func(_text: String): _mark_dirty())
	key_input.text_changed.connect(func(text: String):
		if not text.is_empty(): _mark_dirty())
	timeout_input.value_changed.connect(func(_value: float): _mark_dirty())
	localhost_input.toggled.connect(func(_value: bool): _mark_dirty())
	_refresh()

func _mark_dirty() -> void:
	_dirty = true; _refresh()

func _field(label_text: String, placeholder: String) -> LineEdit:
	var label := Label.new(); label.text = label_text; add_child(label)
	var input := LineEdit.new(); input.placeholder_text = placeholder; input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(input)
	return input

func bind_client(client: Node) -> void:
	if is_instance_valid(_client):
		if _client.busy_changed.is_connected(_on_busy): _client.busy_changed.disconnect(_on_busy)
		if _client.completed.is_connected(_on_completed): _client.completed.disconnect(_on_completed)
	_client = client
	if is_instance_valid(_client):
		_client.busy_changed.connect(_on_busy)
		_client.completed.connect(_on_completed)
	_refresh()

func set_action_state(phase: String) -> void:
	_phase = phase; _refresh()
func set_status(text: String) -> void:
	if is_instance_valid(status_label): status_label.text = text

func _apply() -> void:
	if not is_instance_valid(_client): set_status("尚未绑定运行时client，未联网。"); return
	if not consent_input.button_pressed: set_status("请先核对服务与可能计费说明。应用设置本身不联网。"); return
	var result: Dictionary = _client.configure({"endpoint": endpoint_input.text, "model": model_input.text, "reasoning_effort": reasoning_input.text, "timeout_seconds": timeout_input.value, "allow_localhost_http": localhost_input.button_pressed}, key_input.text)
	# Clear the visible input after any attempt; no reusable hidden copy in panel.
	key_input.text = ""
	_dirty = not result.ok
	if not result.ok: _client.clear_configuration()
	set_status(String(result.get("message", "；".join(result.get("errors", [])))))
	configuration_applied.emit(result); _refresh()

func _clear() -> void:
	if is_instance_valid(_client): _client.clear_configuration()
	key_input.text = ""; consent_input.button_pressed = false; _dirty = true
	set_status("连接及内存密钥已清除；继续离线路径。"); _refresh()

func _on_busy(value: bool) -> void:
	if value and is_instance_valid(_client):
		var summary: Dictionary = _client.request_summary()
		set_status("正在请求%s：公开JSON %.1f KiB，超时%.0f秒。不会自动重试。" % ["API" if summary.get("transport_live", false) else "本地mock（非AI）", float(summary.get("request_bytes", 0))/1024.0, float(summary.get("timeout_seconds", 30))])
	_refresh()
func _on_completed(result: Dictionary) -> void:
	if result.get("ok", false):
		var source := "真实HTTP响应" if result.get("transport", {}).get("live", false) else "本地mock测试响应（非AI）"
		set_status(source + ("：评估已由engine校验并准备；尚未结算。" if result.get("phase") == "assessment" else "：只读叙事已校验；语义仍以权威数值栏为准。"))
	else: set_status("；".join(result.get("errors", ["请求失败，数值结果保留。"])))
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(assessment_button): return
	var working: bool = is_instance_valid(_client) and _client.busy()
	var ready: bool = is_instance_valid(_client) and _client.configured() and consent_input.button_pressed and not _dirty
	assessment_button.disabled = working or not ready or _phase != "awaiting_assessment"
	narration_button.disabled = working or not ready or not _phase in ["staged", "committed"]
	cancel_button.disabled = not working
	apply_button.disabled = working
	for field in [endpoint_input, model_input, reasoning_input, key_input]: field.editable = not working
	timeout_input.editable = not working
	localhost_input.disabled = working
	consent_input.disabled = working

func _exit_tree() -> void:
	if is_instance_valid(key_input): key_input.text = ""
	if is_instance_valid(_client):
		if _client.busy_changed.is_connected(_on_busy): _client.busy_changed.disconnect(_on_busy)
		if _client.completed.is_connected(_on_completed): _client.completed.disconnect(_on_completed)

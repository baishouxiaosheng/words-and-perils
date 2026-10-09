extends "res://view/ai_connection_settings/panel.gd"
## Main-game connection UI; opening/applying never sends a request.
var runtime: Node
var automatic_assessment_input: CheckBox
var automatic_narration_input: CheckBox
func _ready() -> void:
	super._ready()
	consent_input.tooltip_text = consent_input.text
	consent_input.text = "我同意发送公开游戏上下文，并确认API可能计费"
	localhost_input.text = "开发选项：仅本机HTTP（不加密）"
	for child in get_children():
		if child is Label and child.text.contains("游戏偏好标签"):
			child.text = "ChatGPT会员不等于API额度。默认离线；可导入人工JSON。\n填写提供商实际HTTPS Chat Completions接口与model ID；需支持JSON输出与max_completion_tokens。\n公开请求限64 KiB；输出上限2048 tokens。不自动猜测或切换模型。"
	automatic_assessment_input = CheckBox.new()
	automatic_assessment_input.text = "结束回合后请求AI评估（可能计费）"
	automatic_assessment_input.tooltip_text = "启用后，每次你点击结束回合，会向已应用的提供商地址发送一次公开游戏上下文。不会自动重试。"
	automatic_assessment_input.toggled.connect(func(value: bool):
		if is_instance_valid(runtime): runtime.automatic_assessment = value
		_refresh())
	add_child(automatic_assessment_input); move_child(automatic_assessment_input, 1)
	automatic_narration_input = CheckBox.new()
	automatic_narration_input.text = "回合提交后请求只读叙事（额外计费）"
	automatic_narration_input.tooltip_text = "仅在程序已原子提交后，再发送一次独立叙事请求；可能额外计费。失败不改变任何数值。"
	automatic_narration_input.toggled.connect(func(value: bool):
		if is_instance_valid(runtime): runtime.automatic_narration = value)
	add_child(automatic_narration_input); move_child(automatic_narration_input, 2)
	assessment_requested.connect(func():
		if is_instance_valid(runtime): runtime.request_assessment())
	narration_requested.connect(func():
		if is_instance_valid(runtime): runtime.request_narration())
func bind_runtime(controller: Node) -> void:
	if is_instance_valid(runtime) and runtime.changed.is_connected(_sync_runtime): runtime.changed.disconnect(_sync_runtime)
	runtime = controller; bind_client(runtime.client)
	runtime.changed.connect(_sync_runtime); _sync_runtime()
func _sync_runtime() -> void:
	if is_instance_valid(runtime): set_action_state(runtime.phase())
func _clear() -> void:
	if is_instance_valid(runtime): runtime.invalidate_context()
	if is_instance_valid(automatic_assessment_input): automatic_assessment_input.button_pressed = false
	if is_instance_valid(automatic_narration_input): automatic_narration_input.button_pressed = false
	super._clear()
func _refresh() -> void:
	super._refresh()
	if not is_instance_valid(runtime): return
	runtime.connection_enabled = is_instance_valid(_client) and _client.configured() and consent_input.button_pressed and not _dirty
	var working: bool = runtime.busy()
	if is_instance_valid(automatic_assessment_input): automatic_assessment_input.disabled = working
	if is_instance_valid(automatic_narration_input): automatic_narration_input.disabled = working
	if working:
		assessment_button.disabled = true; narration_button.disabled = true
	else:
		narration_button.disabled = narration_button.disabled or runtime.phase() != "committed" or runtime.narration_recorded()
		assessment_button.disabled = assessment_button.disabled or runtime.cooldown_remaining() > 0.0

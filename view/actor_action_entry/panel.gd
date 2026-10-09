extends VBoxContainer
## Small addition inside the existing advanced panel, not a parallel action UI.
signal decision_requested
signal cancel_requested
signal consent_changed(enabled:bool)
var authority:RichTextLabel
var decision_button:Button
var cancel_decision:Button
var consent:CheckBox
func _ready()->void:
	var title_=Label.new();title_.text="统一行动测试 · 手工候选与真实接口严格分开";title_.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(title_)
	var costs=Label.new();costs.text="敌方行动最多先请求意图候选，再请求普通评估；可选叙事另一次。每次可能计费，没有自动重试。";costs.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(costs)
	consent=CheckBox.new();consent.text="允许本测试模式发送敌方意图候选请求（可能计费）";consent.button_pressed=false;consent.toggled.connect(func(value:bool):consent_changed.emit(value));add_child(consent)
	decision_button=Button.new();decision_button.text="请求当前敌方意图候选";decision_button.pressed.connect(func():decision_requested.emit());add_child(decision_button)
	cancel_decision=Button.new();cancel_decision.text="取消候选等待（不结束回合）";cancel_decision.pressed.connect(func():cancel_requested.emit());add_child(cancel_decision)
	authority=RichTextLabel.new();authority.bbcode_enabled=false;authority.custom_minimum_size.y=124;add_child(authority)
func update_adapter(adapter:RefCounted)->void:
	if not is_instance_valid(authority):return
	authority.text=adapter.authority_text()
	decision_button.disabled=not adapter.enemy_response_available() or not consent.button_pressed
	cancel_decision.disabled=not adapter.decision_pending()
func reset_consent()->void:
	if is_instance_valid(consent):consent.set_pressed_no_signal(false)

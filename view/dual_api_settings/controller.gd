extends "res://view/runtime_ai/controller.gd"
## Stable-v28 runtime with explicit phase routing; existing scopes are unchanged.
const DualClient = preload("res://view/dual_api_settings/client.gd")
func _ready() -> void:
	client = DualClient.new(); add_child(client)
	client.completed.connect(_on_completed)
	client.assessment_ready.connect(_on_assessment)
	client.narration_ready.connect(_on_narration)
	client.busy_changed.connect(_on_client_busy_changed)
	client.connection_changed.connect(_on_connection_changed)
func _on_connection_changed() -> void: invalidate_context()
func _begin(kind: String) -> Dictionary:
	if _invalidating or busy(): return _report(C.fail("BUSY", "当前请求尚未结束；没有重复发送。"))
	var selected: Dictionary = client.select_phase(kind)
	if not selected.ok: return _report(selected)
	return super._begin(kind)
func automatic_assessment_enabled() -> bool:
	return connection_enabled and automatic_assessment and is_instance_valid(client) and client.role_configured("decision")

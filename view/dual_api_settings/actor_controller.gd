extends "res://view/actor_status_entry_v1/runtime/controller.gd"
## Preserve status/v2/legacy scope, ticket, epoch, receipt and manual-import guards.
const DualClient = preload("res://view/dual_api_settings/actor_client.gd")
func _ready() -> void:
	client = DualClient.new(); add_child(client)
	client.completed.connect(_on_completed)
	client.assessment_ready.connect(_on_assessment)
	client.narration_ready.connect(_on_narration)
	client.intention_ready.connect(_on_intention)
	client.busy_changed.connect(_on_client_busy_changed)
	client.connection_changed.connect(_on_connection_changed)

func _on_connection_changed() -> void:
	# Preserve the provider parent's epoch barrier for legacy profiles too.
	intention_consent = false
	invalidate_context()

func _begin(kind: String) -> Dictionary:
	# Required decision work retains inherited priority over optional narration.
	if _actor_mode() and kind != "narration" and _operation.get("phase") == "narration": cancel()
	if _invalidating or busy(): return _report(C.fail("BUSY", "当前请求尚未结束；没有重复发送。"))
	var selected: Dictionary = client.select_phase(kind)
	if not selected.ok: return _report(selected)
	return super._begin(kind)

func automatic_assessment_enabled() -> bool:
	return connection_enabled and automatic_assessment and is_instance_valid(client) and client.role_configured("decision")

func intention_cost_notice() -> String:
	return "敌方回合的意图提案与普通评估使用快速决策模型API，分别可能计费；可选叙事使用叙事API，另行计费。不会自动重试。"

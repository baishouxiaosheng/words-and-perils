extends "res://view/actor_action_entry/board.gd"
## White downed-nameplate board37af dependency; its support/sweep rules stay exact.
## This wrapper only installs the receipt-bound public status presentation router.
const StatusEffectRouter = preload("res://view/actor_status_entry_v1/committed_effect_router.gd")
func _ready() -> void:
	super._ready()
	if is_instance_valid(committed_effects):
		remove_child(committed_effects); committed_effects.free()
	committed_effects = StatusEffectRouter.new(); add_child(committed_effects)
	committed_effects.motion_presenter = presentation
	committed_effects.feedback_camera = camera
	committed_effects.safe_rect_provider = func(): return feedback_safe_rect
func present_status_receipt(receipt: Dictionary, before: Dictionary, record: Dictionary) -> Dictionary:
	if not load_error.is_empty(): return {"ok": false, "presented": false, "reason": "render_support_suspended"}
	return committed_effects.consume_public(receipt, before, world_state, token_nodes, record)
func present_committed_receipt(_receipt: Dictionary, _before: Dictionary) -> Dictionary:
	return {"ok": false, "presented": false, "reason": "status_public_record_required"}

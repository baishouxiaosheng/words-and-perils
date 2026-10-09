extends "res://core/ai_gm_rebuilt/basic_actions.gd"
## Selected only by the explicit status-gameplay adapter mode. Legacy/generated
## profiles retain the exact original resolver and its serialized source hash.
const StatusWeaponPlan=preload("res://core/status_gameplay/weapon_poison_plan.gd")
func freeze(snapshot:Dictionary,assessment:Dictionary)->Dictionary:
	return StatusWeaponPlan.adapt(snapshot,assessment,super.freeze(snapshot,assessment))

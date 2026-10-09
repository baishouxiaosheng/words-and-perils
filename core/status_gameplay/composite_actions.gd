extends "res://core/ai_gm_rebuilt/composite_actions.gd"
## Composite delegates internally to frozen Basic. Adapt only the completed
## status-mode plan so its original movement/attack gates and one commit remain.
const StatusWeaponPlan=preload("res://core/status_gameplay/weapon_poison_plan.gd")
func freeze(snapshot:Dictionary,assessment:Dictionary)->Dictionary:
	return StatusWeaponPlan.adapt(snapshot,assessment,super.freeze(snapshot,assessment))

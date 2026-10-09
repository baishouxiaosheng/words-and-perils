extends "res://core/ai_gm_rebuilt/generic_actions.gd"
## Deliberately bad trusted test plugin: second same-tree effect must reject whole plan.
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var plan: Dictionary = super.freeze(snapshot, assessment)
	if plan.ok:
		plan.branches[3].patches.append(plan.branches[3].patches[-1].duplicate(true))
	return plan

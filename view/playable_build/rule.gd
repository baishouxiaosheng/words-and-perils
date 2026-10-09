extends RefCounted
## Explicit temporary demonstration calculator. No model calls or language parsing.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Actions = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
func rule_id() -> String: return "ai_gm_test_coast_actions/v1"
func calculate(_snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var checks: Array = []
	for component in assessment.components:
		var p: Dictionary = component.parameters
		if not Actions.validate_numeric_parameters(assessment.resolver_id, component): return C.fail("DEMO_BOUNDS", "演示参数仅A/D 0..4、P -2..2。")
		var threshold := clampi(5000 + 1000 * (int(p.A)-int(p.D)+int(p.P)), 500, 9500)
		var method := "random" if component.disposition == "possible" else ("direct_success" if component.disposition == "certain" else "direct_failure")
		checks.append({"id": component.id, "method": method, "roll_min": 1 if method == "random" else 0, "roll_max": 10000 if method == "random" else 0, "success_at_most": threshold if method == "random" else 0,
			"explanation": "临时演示公式 clamp(5000+1000*(A-D+P),500,9500)，不是正式平衡规则。语义参数来自评估。", "derived_facts": {"probability_basis_points": threshold}})
	return {"ok": true, "rule_id": rule_id(), "checks": checks}

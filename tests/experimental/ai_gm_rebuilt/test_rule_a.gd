extends RefCounted
## Test-only numeric fixture. Explicit injection is mandatory; no final balance rule.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
func rule_id() -> String: return "ai_gm_test_rule_a/v1"
func calculate(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	if not C.exact_fields(assessment.bindings, ["actor_id", "wine_item_id", "target_actor_id"]) or not snapshot.actors.has(assessment.bindings.actor_id) or not snapshot.actors.has(assessment.bindings.target_actor_id) or not snapshot.items.has(assessment.bindings.wine_item_id): return C.fail("INVALID_BINDING", "Test rule A requires stable actor, wine and NPC bindings.")
	var actor: Dictionary = snapshot.actors[assessment.bindings.actor_id]
	var wine: Dictionary = snapshot.items[assessment.bindings.wine_item_id]
	var resource := 0
	if wine.get("owner_actor_id") == actor.id or (wine.get("hex") == actor.hex and wine.get("scene_id") == actor.scene_id): resource = clampi(int(wine.quantity), 0, 2)
	var soldiers := 0; var soldier_ids: Array = []
	var actor_ids: Array = snapshot.actors.keys(); actor_ids.sort()
	for id in actor_ids:
		var npc: Dictionary = snapshot.actors[id]
		if npc.get("role") == "soldier" and npc.scene_id == actor.scene_id and npc.health.current > 0: soldiers += 1; soldier_ids.append(id)
	soldiers = clampi(soldiers, 0, 2)
	var checks: Array = []
	for component in assessment.components:
		var p: Dictionary = component.parameters
		if not C.exact_fields(p, ["A", "D", "P"]) or not C.integer(p.A) or p.A < 0 or p.A > 4 or not C.integer(p.D) or p.D < 0 or p.D > 4 or not C.integer(p.P) or p.P < -2 or p.P > 2: return C.fail("TEST_RULE_BOUNDS", "Rule A requires A/D 0..4 and P -2..2.")
		var basis_points: int = clampi(5000 + 1000 * (int(p.A) - int(p.D) + int(p.P) + clampi(resource - soldiers, -2, 2)), 500, 9500)
		var method := "random" if component.disposition == "possible" else ("direct_success" if component.disposition == "certain" else "direct_failure")
		checks.append({"id": component.id, "method": method, "roll_min": 1 if method == "random" else 0, "roll_max": 10000 if method == "random" else 0, "success_at_most": basis_points if method == "random" else 0,
			"explanation": "TEST ONLY: fixed basis-point rule A; semantic A/D/P and certainty still require a real model assessment.",
			"derived_facts": {"R": resource, "N": soldiers, "wine_item_id": wine.id, "wine_quantity": wine.quantity, "wine_hex": wine.get("hex", []), "soldier_ids": soldier_ids, "probability_basis_points": basis_points}})
	return {"ok": true, "rule_id": rule_id(), "checks": checks}

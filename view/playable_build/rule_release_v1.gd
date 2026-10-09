extends RefCounted
## Release-v1 tunable balance. Never rewrites/reinterprets legacy calculator IDs.
## Parameters assess uncertainty; trusted resolver policy alone decides whether to roll.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Actions = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const ID := "coast_release/v1"
var _resolvers: Dictionary = {}
func _init(resolvers: Dictionary = {}) -> void: _resolvers = resolvers.duplicate()
func rule_id() -> String: return ID
func rule_schema() -> Dictionary:
	return {"schema_version": ID, "balance_status": "release_v1_tunable_not_user_final_agreed", "parameters": {"A": [0, 4], "D": [0, 4], "P": [-2, 2]}, "formula": "clamp(5000 + 750*(A-D) + 500*P + 250*F, 500, 9500)", "F": "public acting actor fatigue -1 at stamina<=2; injury -1 at health<=half; drunk -min(magnitude,2); clamp total -4..0", "random_domain": [1, 10000], "disposition": "advisory_only_ignored_for_authority", "direct_policy": "registered_resolver_check_policy_after_validated_preconditions", "compound": "independent component dice and complete pre-frozen outcome branches"}
func calculate(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	if not _resolvers.has(assessment.resolver_id) or not _resolvers[assessment.resolver_id].has_method("check_policy"): return C.fail("RELEASE_POLICY", "The registered resolver has no release-v1 authority policy.")
	var resolver: RefCounted = _resolvers[assessment.resolver_id]
	var policy: Variant = resolver.check_policy(snapshot.duplicate(true), assessment.duplicate(true))
	if not policy is Dictionary or not policy.get("ok", false): return policy if policy is Dictionary else C.fail("RELEASE_POLICY", "Resolver policy is malformed.")
	if not C.exact_fields(policy, ["ok", "policies"]) or not policy.policies is Dictionary or policy.policies.size() != assessment.components.size(): return C.fail("RELEASE_POLICY", "Each component needs exactly one registered policy.")
	var actor_id: String = assessment.bindings.get("actor_id", "")
	if not snapshot.actors.has(actor_id): return C.fail("RELEASE_ACTOR", "Acting actor must be a frozen public fact.")
	var actor: Dictionary = snapshot.actors[actor_id]
	var fatigue := -1 if int(actor.stamina.current) <= 2 else 0
	var injury := -1 if 2 * int(actor.health.current) <= int(actor.health.max) else 0
	var drunk := 0
	for status in actor.statuses.values():
		if status.kind == "drunk": drunk = -mini(int(status.magnitude), 2)
	var modifier := clampi(fatigue + injury + drunk, -4, 0)
	var checks: Array = []
	for component in assessment.components:
		if not Actions.validate_numeric_parameters(assessment.resolver_id, component): return C.fail("RELEASE_BOUNDS", "Release-v1 requires integer A/D 0..4, P -2..2 and only registered bounded effect parameters.")
		if not policy.policies.has(component.id) or not policy.policies[component.id] in ["safe_direct", "contested", "impossible"]: return C.fail("RELEASE_POLICY", "Unknown resolver-owned check policy.")
		var p: Dictionary = component.parameters
		var threshold := clampi(5000 + 750 * (int(p.A) - int(p.D)) + 500 * int(p.P) + 250 * modifier, 500, 9500)
		var classification: String = policy.policies[component.id]
		var method := "random" if classification == "contested" else ("direct_success" if classification == "safe_direct" else "direct_failure")
		checks.append({"id": component.id, "method": method, "roll_min": 1 if method == "random" else 0, "roll_max": 10000 if method == "random" else 0, "success_at_most": threshold if method == "random" else 0,
			"explanation": "Release-v1 tunable fixed rule. Resolver-owned policy; model disposition cannot bypass a die or force failure. Compound branches are frozen before RNG.", "derived_facts": {"rule_version": ID, "policy": classification, "probability_basis_points": threshold, "fatigue": fatigue, "injury": injury, "drunk": drunk, "F": modifier, "actor_id": actor_id}})
	return {"ok": true, "rule_id": rule_id(), "checks": checks}
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return preload("res://view/playable_build/authored_assessments.gd").verify(snapshot, reply, goal, focus)

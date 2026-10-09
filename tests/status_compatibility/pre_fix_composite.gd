extends RefCounted
## Bounded two-operation intention: frozen dry route, then authored attack.
## New versioned contract; historical resolvers are never reinterpreted.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Generic = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const Basic = preload("res://tests/status_compatibility/pre_fix_basic.gd")
const Move = preload("res://view/playable_build/weighted_movement_resolver.gd")
const ID := "coast_move_then_attack_v1"
func resolver_id() -> String: return ID
func action_schema() -> Dictionary:
	return {"schema_version": "coast_composite/v1", "resolver_id": ID, "bindings": {"actor_id": "actor_player", "target_hex": "explicit coast arrival [q,r] along a legal terrain-costed dry route", "target_actor_id": "living authored hostile in equipped weapon range after arrival", "weapon_item_id": "owned equipped authored weapon"}, "components": ["move", "accuracy", "impact"], "numeric_assessment": {"A": [0, 4], "D": [0, 4], "P": [-2, 2]}, "operations": ["move", "basic_attack"], "maximum_operations": 2, "required_fact_paths": ["/actors/actor_player", "/hexes/<arrival_q,r>", "/actors/<target_actor_id>", "/items/<weapon_item_id>", "/items/<authored_ammunition_if_any>"], "effect_dependencies": "If move fails no route or attack effect is applied. If move succeeds, arrival and attack costs occur; accuracy failure leaves only movement plus paid attack attempt, accuracy-only gives graze, both attack checks give full hit.", "roll_policy": "Three independent contested check slots are drawn exactly once; failed movement suppresses all attack effects regardless of reserved attack rolls.", "resource_policy": "Full legal route and attack costs are reserved before rolling; insufficient combined resources reject the whole intention. Successful movement consumes the full route cost and one authored attack cost even on an attack miss. Failed movement has no effects; unchanged rerolls are forbidden.", "turn_policy": "One intentional composite commit, one status/patrol tick; a reached hostile schedules the mandatory NPC phase.", "every_intent_requires_assessment": true, "unsupported_operations": "Any extra intent part requires another registered family; this does not parse or silently discard arbitrary prose."}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return ID + ":" + C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var attack: Dictionary = _attack_assessment(assessment)
	return {"attack": Basic.new("basic_attack").attempt_fingerprint(snapshot, attack), "hexes": snapshot.hexes, "arrival": b.get("target_hex"), "world": snapshot.get("generated_world", {})}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var plan := freeze(snapshot, assessment)
	if not plan.ok: return plan
	return {"ok": true, "policies": {"move": "contested", "accuracy": "contested", "impact": "contested"}}
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if snapshot.actors.actor_player.scene_id != "scene_coast": return C.fail("COMPOSITE_SCENE", "This version is limited to the authored coast route followed by attack.")
	if not C.exact_fields(b, ["actor_id", "target_hex", "target_actor_id", "weapon_item_id"]) or b.actor_id != "actor_player": return C.fail("COMPOSITE_BINDING", "This version supports a player dry-route movement followed by one authored attack only.")
	if assessment.components.size() != 3: return C.fail("COMPOSITE_COMPONENT", "Move then attack requires exactly move, accuracy and impact.")
	var by_id: Dictionary = {}
	for component in assessment.components:
		if not component.id in ["move", "accuracy", "impact"] or by_id.has(component.id) or not Generic.validate_numeric_parameters(ID, component): return C.fail("COMPOSITE_COMPONENT", "Unknown, repeated or unbounded compound component.")
		by_id[component.id] = component
	if not b.target_hex is Array or b.target_hex.size() != 2 or not C.integer(b.target_hex[0]) or not C.integer(b.target_hex[1]): return C.fail("COMPOSITE_TARGET", "Arrival requires exact integer coordinates.")
	if not Generic._has_ref(assessment, "/actors/actor_player") or not Generic._has_ref(assessment, "/hexes/%d,%d" % b.target_hex): return C.fail("COMPOSITE_FACT", "All components must cite actor and the frozen arrival cell.")
	var move_assessment: Dictionary = assessment.duplicate(true)
	move_assessment.resolver_id = Move.ID
	move_assessment.bindings = {"actor_id": b.actor_id, "target_hex": b.target_hex.duplicate()}
	move_assessment.components = [by_id.move.duplicate(true)]
	var move_plan: Dictionary = Move.new().freeze(snapshot, move_assessment)
	if not move_plan.ok: return move_plan
	var route_patches: Array = move_plan.branches[0].patches
	var arrived: Dictionary = snapshot.duplicate(true)
	for patch in route_patches:
		var applied: Dictionary = World.apply(arrived, patch)
		if not applied.ok: return applied
	# Validate at the predicted arrival with route stamina already reserved, without
	# publishing intermediate facts or ticking hooks between the operations.
	var attack_plan: Dictionary = Basic.new("basic_attack").freeze(arrived, _attack_assessment(assessment))
	if not attack_plan.ok: return attack_plan
	var branches: Array = []
	for mask in range(8):
		var moved: bool = bool(mask & 1); var accurate: bool = bool(mask & 2); var forceful: bool = bool(mask & 4)
		var patches: Array = []
		if moved:
			patches = route_patches.duplicate(true)
			for branch in attack_plan.branches:
				if branch.requires.accuracy == accurate and branch.requires.impact == forceful:
					patches.append_array(branch.patches.duplicate(true)); break
		branches.append({"id": "move_then_attack_" + str(mask), "requires": {"move": moved, "accuracy": accurate, "impact": forceful}, "patches": patches})
	return {"ok": true, "resolver_id": ID, "branches": branches}
static func _attack_assessment(assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings; var result: Dictionary = assessment.duplicate(true)
	result.resolver_id = "coast_basic_attack_v1"
	result.bindings = {"actor_id": b.get("actor_id", ""), "target_actor_id": b.get("target_actor_id", ""), "weapon_item_id": b.get("weapon_item_id", "")}
	result.components = []
	for component in assessment.components:
		if component.id in ["accuracy", "impact"]: result.components.append(component.duplicate(true))
	return result

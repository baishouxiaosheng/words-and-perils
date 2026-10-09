extends RefCounted
## Registered declarative action families. Models bind IDs and bounded numbers only.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
var kind := "manipulate_environment"
func _init(kind_: String = "manipulate_environment") -> void: kind = kind_
func resolver_id() -> String: return "coast_" + kind + "_v1"

func action_schema() -> Dictionary:
	var common := {"schema_version": "coast_typed_actions/v1", "resolver_id": resolver_id(), "numeric_assessment": {"A": [0, 4], "D": [0, 4], "P": [-2, 2]}, "every_intent_requires_assessment": true, "arbitrary_effects_allowed": false, "live_model": false}
	if kind == "manipulate_environment":
		common["bindings"] = {"actor_id": "existing acting actor", "target_entity_id": "source-bound standing tree ID", "operation": "fell"}
		common["components"] = ["control", "force"]
		common["fixed_rule"] = "Both checks must succeed. Cost is 2 stamina on every result. Fell only a same-scene tree within one cell; its owning ground becomes blocked, air/all blocks unchanged."
		common["required_fact_paths"] = ["/actors/<actor_id>", "/hexes/<owning_q,r>", "/attention_focus/facts/entity"]
	elif kind == "apply_condition":
		common["bindings"] = {"actor_id": "existing acting actor", "target_actor_id": "existing living target", "source_item_id": "owned condition_source item"}
		common["components"] = ["delivery", "effect"]
		common["effect_parameters"] = {"duration": [1, Effects.MAX_DURATION], "magnitude": [1, Effects.MAX_MAGNITUDE]}
		common["fixed_rule"] = "Both checks must succeed. Cost is authored source units_per_use (1..3) and 1 stamina on every result. Source profile fixes condition kind and target scope; flight magnitude is exactly 1. No same-kind stacking. New effects start ticking on the next committed turn. Poison floors health at zero; downed actors cannot initiate these actions."
		common["required_fact_paths"] = ["/actors/<actor_id>", "/actors/<target_actor_id>", "/items/<source_item_id>"]
	return common

static func validate_numeric_parameters(resolver: String, component: Dictionary) -> bool:
	var fields := ["A", "D", "P"]
	if resolver == "coast_apply_condition_v1" and component.id == "effect": fields.append_array(["duration", "magnitude"])
	var p: Dictionary = component.parameters
	if not C.exact_fields(p, fields): return false
	if fields.size() > 3:
		if not C.integer(p.duration) or p.duration < 1 or p.duration > Effects.MAX_DURATION or not C.integer(p.magnitude) or p.magnitude < 1 or p.magnitude > Effects.MAX_MAGNITUDE: return false
	return C.integer(p.A) and p.A >= 0 and p.A <= 4 and C.integer(p.D) and p.D >= 0 and p.D <= 4 and C.integer(p.P) and p.P >= -2 and p.P <= 2

func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	# The release calculator treats model certainty as advisory, never as a permission bypass.
	var valid := freeze(snapshot, assessment)
	if not valid.ok: return valid
	var policies: Dictionary = {}
	for component in assessment.components: policies[component.id] = "contested"
	return {"ok": true, "policies": policies}

func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	# No prose, assessment difficulty or proposed potency can manufacture a fresh attempt.
	return resolver_id() + ":" + C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var result := {"actor": snapshot.actors.get(b.get("actor_id"), {})}
	if kind == "manipulate_environment":
		var entity: Dictionary = Catalog.entity(b.get("target_entity_id", ""), snapshot)
		result["entity"] = entity
		if not entity.is_empty(): result["cell"] = snapshot.hexes[Traversal.key(entity.hex)]
	else:
		result["target"] = snapshot.actors.get(b.get("target_actor_id"), {})
		result["source"] = snapshot.items.get(b.get("source_item_id"), {})
	return result

func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var expected := ["actor_id", "target_entity_id", "operation"] if kind == "manipulate_environment" else ["actor_id", "target_actor_id", "source_item_id"]
	if not kind in ["manipulate_environment", "apply_condition"] or not C.exact_fields(b, expected): return C.fail("ACTION_BINDING", "Unknown action family or unexpected declarative binding fields.")
	for value in b.values():
		if not value is String or value.is_empty(): return C.fail("ACTION_BINDING", "Bindings must be explicit nonempty stable IDs or the supported operation enum.")
	if not snapshot.actors.has(b.actor_id): return C.fail("ACTION_ACTOR", "Acting actor does not exist.")
	var actor: Dictionary = snapshot.actors[b.actor_id]
	if actor.health.current <= 0: return C.fail("ACTOR_DOWNED", "A downed actor cannot initiate this action family.")
	var ids := ["control", "force"] if kind == "manipulate_environment" else ["delivery", "effect"]
	if assessment.components.size() != 2: return C.fail("ACTION_COMPONENT", "This compound family requires exactly two named checks.")
	var components: Dictionary = {}
	for component in assessment.components:
		if not component.id in ids or components.has(component.id) or not validate_numeric_parameters(resolver_id(), component): return C.fail("ACTION_COMPONENT", "Compound check IDs or bounded numeric parameters are invalid.")
		components[component.id] = component
	if not _has_ref(assessment, "/actors/" + b.actor_id): return C.fail("ACTION_FACT", "Every component must cite the acting actor's frozen public facts.")
	var cost := 2 if kind == "manipulate_environment" else 1
	if actor.stamina.current < cost: return C.fail("ACTION_RESOURCE", "Insufficient stamina for this family's fixed cost.")
	var costs: Array = [{"type": "actor_pool_delta", "actor_id": b.actor_id, "pool": "stamina", "delta": -cost}]
	var effect: Dictionary = {}
	var engagement: Dictionary = {}
	if kind == "manipulate_environment":
		if b.operation != "fell": return C.fail("ENVIRONMENT_OPERATION", "Only the registered fell operation is installed.")
		var entity: Dictionary = Catalog.entity(b.target_entity_id, snapshot)
		if entity.is_empty() or entity.kind != "tree": return C.fail("ENVIRONMENT_TARGET", "Target is not a verified scene tree.")
		if entity.scene_id != actor.scene_id or Effects.distance(actor.hex, entity.hex) > 1: return C.fail("ENVIRONMENT_RANGE", "Target must be in the acting actor's scene within one cell.")
		var cell: Dictionary = snapshot.hexes[Traversal.key(entity.hex)]
		if entity.state.posture != "standing" or entity.state.revision != 0 or cell.ground_blocked or cell.all_blocked: return C.fail("ENVIRONMENT_PRECONDITION", "The source tree must still stand on unblocked ground.")
		if not _has_ref(assessment, "/hexes/" + Traversal.key(entity.hex)) or not _has_entity_ref(assessment, entity.id): return C.fail("ACTION_FACT", "Both checks must cite the selected source entity and its owning cell.")
		effect = {"type": "environment_fell", "entity_id": entity.id, "expected_revision": entity.state.revision, "cell_id": cell.id}
	else:
		if not snapshot.actors.has(b.target_actor_id) or not snapshot.items.has(b.source_item_id): return C.fail("CONDITION_TARGET", "Condition target or source item is unknown.")
		var target: Dictionary = snapshot.actors[b.target_actor_id]; var item: Dictionary = snapshot.items[b.source_item_id]
		if not item.has("condition_source") or not Effects.validate_source(b.source_item_id, item) or item.get("owner_actor_id") != b.actor_id or not b.source_item_id in actor.inventory or item.quantity < int(item.get("condition_source", {}).get("units_per_use", 1)): return C.fail("CONDITION_SOURCE", "An owned, available, authored condition source is required.")
		var profile: Dictionary = item.condition_source; var params: Dictionary = components.effect.parameters
		if snapshot.has("combat_turn") and actor.id == "actor_player" and profile.kind == "poison" and target.faction in actor.get("combat_profile", {}).get("hostile_factions", []): engagement = BasicEffects.turn_patch(snapshot, "enemy", target.id, int(snapshot.combat_turn.round) + 1)
		if target.health.current <= 0 or target.scene_id != actor.scene_id or Effects.distance(actor.hex, target.hex) > 1 or not "status_tick" in target.hooks: return C.fail("CONDITION_TARGET", "Target must be living, nearby, in this scene, and configured for timed conditions.")
		if profile.target_scope == "self" and b.target_actor_id != b.actor_id: return C.fail("CONDITION_SCOPE", "This condition source can only affect the acting actor.")
		if params.duration > profile.max_duration or params.magnitude > profile.max_magnitude: return C.fail("CONDITION_BOUNDS", "Proposed duration or magnitude exceeds this source's fixed capability.")
		for status in target.statuses.values():
			if status.kind == profile.kind: return C.fail("CONDITION_CONFLICT", "Same-kind condition stacking or refresh is not installed.")
		if not _has_ref(assessment, "/actors/" + b.target_actor_id) or not _has_ref(assessment, "/items/" + b.source_item_id): return C.fail("ACTION_FACT", "Both checks must cite target and source public facts.")
		costs.append({"type": "item_quantity_delta", "item_id": b.source_item_id, "delta": -int(profile.units_per_use)})
		var status_id := "condition_" + str(profile.kind)
		if target.statuses.has(status_id): return C.fail("CONDITION_CONFLICT", "Stable condition ID is already occupied.")
		effect = {"type": "actor_status_set", "actor_id": b.target_actor_id, "status_id": status_id, "status": {"id": status_id, "kind": profile.kind, "remaining_turns": params.duration, "magnitude": params.magnitude}}
	var branches: Array = []
	for mask in range(4):
		var requires: Dictionary = {}; var patches: Array = costs.duplicate(true)
		for i in range(2): requires[ids[i]] = bool(mask & (1 << i))
		if mask == 3: patches.append(effect.duplicate(true))
		if not engagement.is_empty(): patches.append(engagement.duplicate(true))
		branches.append({"id": kind + "_" + str(mask), "requires": requires, "patches": patches})
	return {"ok": true, "resolver_id": resolver_id(), "branches": branches}

static func _has_ref(assessment: Dictionary, path: String) -> bool:
	for ref in assessment.fact_refs:
		if ref.path != path: continue
		for component in assessment.components:
			if not ref.id in component.fact_ref_ids: return false
		return true
	return false
static func _has_entity_ref(assessment: Dictionary, id: String) -> bool:
	for ref in assessment.fact_refs:
		if ref.path != "/attention_focus/facts/entity" or not ref.expected is Dictionary or ref.expected.get("id") != id: continue
		for component in assessment.components:
			if not ref.id in component.fact_ref_ids: return false
		return true
	return false

extends "res://core/ai_gm_rebuilt/generic_actions.gd"
## New retry semantics only. V1's freeze, costs, effects and replay stay unchanged.
## Latest-post-failure baseline, NOT full A->B->A failed-arrangement history.
const RETRY_POLICY := "coast_generic_material_retry/v2"
func resolver_id() -> String: return "coast_" + kind + "_v2"
func action_schema() -> Dictionary:
	var schema := super.action_schema()
	schema.schema_version = "coast_typed_actions/v2"
	schema["retry_policy"] = {"id": RETRY_POLICY, "material_changes": "Actor approach/scene, effective release F or admission capability, actual target state, relevant source availability/profile. No existing felling tool bonus.", "ignored_changes": "Wording, A/D/P, potency proposal, disposition, reference order, names, unrelated actors/inventory, raw resource counts within admission/F bands, status duration, custody/revision/turn counters.", "failure_baseline": "Validated post-cost/post-hook result. Full success ends this attempt. One latest baseline only; historical A-to-B-to-A episode tracking is not installed."}
	return schema

func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var actor: Dictionary = snapshot.actors[b.actor_id]
	var cost := 2 if kind == "manipulate_environment" else 1
	var result := {"policy": RETRY_POLICY, "actor": {"scene_id": actor.scene_id, "hex": actor.hex.duplicate(), "alive": actor.health.current > 0, "can_pay": actor.stamina.current >= cost, "F": _release_modifier(actor)}}
	if kind == "manipulate_environment":
		var entity: Dictionary = Catalog.entity(b.target_entity_id, snapshot)
		if entity.is_empty():
			result["target_available"] = false
		else:
			var cell: Dictionary = snapshot.hexes[Traversal.key(entity.hex)]
			result["target"] = {"id": entity.id, "scene_id": entity.scene_id, "hex": entity.hex.duplicate(), "kind": entity.kind, "posture": entity.state.posture, "ground_blocked": cell.ground_blocked, "all_blocked": cell.all_blocked}
	else:
		var target: Dictionary = snapshot.actors[b.target_actor_id]
		var item: Dictionary = snapshot.items[b.source_item_id]
		var profile: Dictionary = item.condition_source
		var same_kind := false
		for status in target.statuses.values():
			if status.kind == profile.kind: same_kind = true
		result["target"] = {"id": target.id, "scene_id": target.scene_id, "hex": target.hex.duplicate(), "alive": target.health.current > 0, "status_tick": "status_tick" in target.hooks, "same_kind_present": same_kind}
		result["source"] = {"id": item.id, "owned": item.get("owner_actor_id", "") == actor.id and item.id in actor.inventory, "available": item.quantity >= int(profile.units_per_use), "profile": profile.duplicate(true)}
	return result

func retry_commit_policy(snapshot: Dictionary, assessment: Dictionary, outcomes: Dictionary) -> Dictionary:
	# Only real authoritative component outcomes complete the interaction cycle.
	# Partial/failure stores the actual post-hook state, so self-paid deterioration
	# or own status expiry cannot itself buy a fresh roll.
	if not false in outcomes.values(): return {"retain": false}
	return {"retain": true, "fingerprint": attempt_fingerprint(snapshot, assessment)}

func legacy_failure_keys(_snapshot: Dictionary, assessment: Dictionary) -> Array:
	# Old whole-record hashes cannot be safely assigned v2 meaning. Recognize only
	# this exact actor/resolver/bindings identity; unrelated actions remain usable.
	var old_id := "coast_" + kind + "_v1"
	return [C.digest([assessment.bindings.actor_id, old_id, old_id + ":" + C.bytes(assessment.bindings)])]

static func _release_modifier(actor: Dictionary) -> int:
	# Exactly the mechanically used release-v1 F, not raw pools or timer bookkeeping.
	var fatigue := -1 if int(actor.stamina.current) <= 2 else 0
	var injury := -1 if 2 * int(actor.health.current) <= int(actor.health.max) else 0
	var drunk := 0
	for status in actor.statuses.values():
		if status.kind == "drunk": drunk = -mini(int(status.magnitude), 2)
	return clampi(fatigue + injury + drunk, -4, 0)

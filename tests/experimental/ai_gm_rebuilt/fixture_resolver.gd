extends RefCounted
## Trusted test resolver; external replies can select its ID, never edit its code.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var variant := "gate"
func _init(selected: String = "gate") -> void: variant = selected
func resolver_id() -> String: return "fixture_" + variant
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return variant + ":" + assessment.bindings.target_actor_id
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if variant == "listen": return {"actor_hex": snapshot.actors[b.actor_id].hex, "target_dialogue": snapshot.actors[b.target_actor_id].get("observed_dialogue", [])}
	return {"actor_hex": snapshot.actors[b.actor_id].hex, "actor_stamina": snapshot.actors[b.actor_id].stamina.current, "wine": snapshot.items[b.wine_item_id], "guards": [snapshot.actors.actor_guard_a.health.current, snapshot.actors.actor_guard_z.health.current], "gate_open": snapshot.flags.gate_open}
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	if variant == "unknown_patch": return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "only", "requires": {}, "patches": [{"type": "execute_script", "script": "arbitrary code"}]}]}
	if variant == "nonfinite": return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "only", "requires": {}, "patches": [{"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": NAN}]}]}
	if variant == "overlap": return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "a", "requires": {}, "patches": []}, {"id": "b", "requires": {}, "patches": []}]}
	if variant == "listen": return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "listen", "requires": {}, "patches": []}]}
	if variant == "tree": return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "fallen_tree", "requires": {"offer": true}, "patches": [{"type": "cell_blocking_set", "cell_id": "hex_1_0", "ground_blocked": true, "air_blocked": false, "all_blocked": false}]}, {"id": "standing_tree", "requires": {"offer": false}, "patches": []}]}
	var b: Dictionary = assessment.bindings
	if snapshot.items[b.wine_item_id].quantity < 1: return C.fail("MATERIAL_REQUIRED", "No wine remains for a paid attempt.")
	var costs := [{"type": "actor_pool_delta", "actor_id": b.actor_id, "pool": "stamina", "delta": -1}]
	var wine: Dictionary = snapshot.items[b.wine_item_id]
	var actor: Dictionary = snapshot.actors[b.actor_id]
	if wine.get("owner_actor_id") == actor.id or (wine.get("hex") == actor.hex and wine.get("scene_id") == actor.scene_id): costs.push_front({"type": "item_quantity_delta", "item_id": b.wine_item_id, "delta": -1})
	var full: Array = costs.duplicate(true); full.append({"type": "flag_set", "flag_id": "gate_open", "value": true}); full.append({"type": "flag_set", "flag_id": "npc_listened", "value": true})
	var partial: Array = costs.duplicate(true); partial.append({"type": "flag_set", "flag_id": "npc_listened", "value": true})
	return {"ok": true, "resolver_id": resolver_id(), "branches": [
		{"id": "all_success", "requires": {"offer": true, "talk": true}, "patches": full},
		{"id": "partial_success", "requires": {"offer": true, "talk": false}, "patches": partial},
		{"id": "offer_failed", "requires": {"offer": false}, "patches": costs}]}

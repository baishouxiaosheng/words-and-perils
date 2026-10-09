extends RefCounted
const StatusContent=preload("res://core/status_gameplay/content.gd")
## Registered bounded melee and whole-stack item actions. Never parses goal text.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const PublicView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Generic = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const KINDS := ["basic_attack", "pickup_item", "transfer_item", "equip_item", "drop_item"]
var kind := "basic_attack"
func _init(kind_: String = "basic_attack") -> void: kind = kind_
func resolver_id() -> String: return "coast_" + kind + "_v1"
func action_schema() -> Dictionary:
	var b := {"actor_id": "acting actor stable ID", "item_id": "existing authored movable item stable ID"}
	var components: Array = ["interact"]
	if kind == "basic_attack":
		b = {"actor_id": "acting actor stable ID", "target_actor_id": "living actor in combat_profile.hostile_factions", "weapon_item_id": "owned equipped authored melee/ranged/magic weapon"}
		components = ["accuracy", "impact"]
	elif kind == "transfer_item": b.target_actor_id = "living friendly adjacent actor, or retrieve from a downed hostile via pickup_item"
	return {"schema_version": "coast_basic_actions/v1", "resolver_id": resolver_id(), "bindings": b, "components": components, "numeric_assessment": {"A": [0, 4], "D": [0, 4], "P": [-2, 2]}, "every_intent_requires_assessment": true, "disposition": "advisory_only", "quantity_policy": "whole existing stack only; no creation, splitting, arbitrary patches or negative quantity", "required_fact_paths": ["/actors/<actor_id>", "/items/<item_id_or_weapon_item_id>", "/actors/<target_actor_id_if_any>"], "authority": "Attack always rolls independent accuracy/impact: accuracy failure misses; accuracy success with impact failure grazes; both succeed give full authored damage and optional authored poison. Costs and all branches freeze before RNG. Item interactions are direct only after trusted ownership/range/capability checks. HP zero blocks intentional actions."}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return resolver_id() + ":" + C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var actor: Dictionary = snapshot.actors.get(b.get("actor_id", ""), {})
	var item: Dictionary = snapshot.items.get(b.get("weapon_item_id", b.get("item_id", "")), {})
	var result := {"actor": actor, "item": item}
	if b.has("target_actor_id"): result.target = snapshot.actors.get(b.target_actor_id, {})
	if item.has("owner_actor_id"): result.owner = snapshot.actors.get(item.owner_actor_id, {})
	if snapshot.has("settlement_state"): result.settlement = snapshot.settlement_state
	return result
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var plan := freeze(snapshot, assessment)
	if not plan.ok: return plan
	var policies: Dictionary = {}
	for component in assessment.components: policies[component.id] = "contested" if kind == "basic_attack" else "safe_direct"
	return {"ok": true, "policies": policies}
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	if not kind in KINDS: return C.fail("ACTION_FAMILY", "Unknown basic action family.")
	var b: Dictionary = assessment.bindings
	var fields: Array = ["actor_id", "target_actor_id", "weapon_item_id"] if kind == "basic_attack" else (["actor_id", "item_id", "target_actor_id"] if kind == "transfer_item" else ["actor_id", "item_id"])
	if not C.exact_fields(b, fields): return C.fail("ACTION_BINDING", "Basic family requires exact stable ID bindings.")
	for value in b.values():
		if not value is String or value.is_empty(): return C.fail("ACTION_BINDING", "Bindings must be nonempty stable IDs.")
	if not snapshot.actors.has(b.actor_id): return C.fail("ACTION_ACTOR", "Unknown acting actor.")
	var actor: Dictionary = snapshot.actors[b.actor_id]
	if actor.health.current <= 0: return C.fail("ACTOR_DOWNED", "A downed actor cannot act.")
	var ids: Array = ["accuracy", "impact"] if kind == "basic_attack" else ["interact"]
	if assessment.components.size() != ids.size(): return C.fail("ACTION_COMPONENT", "Wrong number of assessed basic components.")
	var seen: Dictionary = {}
	for component in assessment.components:
		if not component.id in ids or seen.has(component.id) or not Generic.validate_numeric_parameters(resolver_id(), component): return C.fail("ACTION_COMPONENT", "Invalid component or bounded parameters.")
		seen[component.id] = true
	if not Generic._has_ref(assessment, "/actors/" + b.actor_id): return C.fail("ACTION_FACT", "All components must cite the frozen public acting actor.")
	var item_id: String = b.get("weapon_item_id", b.get("item_id", ""))
	if not snapshot.items.has(item_id) or not Generic._has_ref(assessment, "/items/" + item_id): return C.fail("ACTION_FACT", "Existing item and its public cited facts are required.")
	var item: Dictionary = snapshot.items[item_id]
	if not Basic.validate_item(item) or not item.has("interaction_profile") or item.quantity <= 0: return C.fail("ITEM_CAPABILITY", "This available item has no authored basic interaction capability.")
	if kind == "basic_attack": return _attack(snapshot, assessment, actor, item)
	return _interaction(snapshot, assessment, actor, item)

func _attack(snapshot: Dictionary, assessment: Dictionary, actor: Dictionary, item: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if not snapshot.actors.has(b.target_actor_id) or not Generic._has_ref(assessment, "/actors/" + b.target_actor_id): return C.fail("ACTION_FACT", "Attack target requires existing public cited actor facts.")
	var target: Dictionary = snapshot.actors[b.target_actor_id]
	if actor.id == target.id or target.health.current <= 0: return C.fail("ATTACK_TARGET", "Cannot attack self or an already downed target.")
	if not target.faction in actor.get("combat_profile", {}).get("hostile_factions", []) or target.faction == actor.faction: return C.fail("ATTACK_FRIENDLY", "The authored hostility profile does not authorize attacking this actor.")
	if item.get("owner_actor_id", "") != actor.id or not item.id in actor.inventory or actor.get("equipment", {}).get("weapon", "") != item.id or not item.has("weapon_profile"): return C.fail("ATTACK_WEAPON", "Attack requires an owned equipped authored weapon.")
	var p: Dictionary = item.weapon_profile
	if actor.scene_id != target.scene_id or Effects.distance(actor.hex, target.hex) < 1 or Effects.distance(actor.hex, target.hex) > int(p.max_range): return C.fail("ATTACK_RANGE", "Target must be inside the equipped capability range in the same scene.")
	var wall_line: Array = [actor.hex] + Basic.attack_line(actor.hex, target.hex)
	if wall_line.back() != target.hex: wall_line.append(target.hex)
	for i in range(1,wall_line.size()):
		if not preload("res://view/playable_build/settlement_content.gd").edge_allowed(snapshot,actor,wall_line[i-1],wall_line[i],true): return C.fail("ATTACK_WALL","The authored binary wall-edge line of sight blocks this attack; no projectile arc or cover simulation is implemented.")
	for point in Basic.attack_line(actor.hex, target.hex):
		var cell: Dictionary = Cells.cell(snapshot, actor.scene_id, point)
		if cell.is_empty(): return C.fail("ATTACK_LINE", "Attack line leaves the authored scene map.")
		if cell.all_blocked or cell.air_blocked or (cell.ground_blocked and cell.terrain not in ["ocean", "sea", "lake", "water"]): return C.fail("ATTACK_LINE", "An authored blocking cell prevents this attack line.")
	if actor.stamina.current < p.stamina_cost: return C.fail("ACTION_RESOURCE", "Not enough stamina for the authored attack cost.")
	var costs: Array = [{"type": "actor_pool_delta", "actor_id": actor.id, "pool": "stamina", "delta": -int(p.stamina_cost)}]
	if not p.cost_item_id.is_empty():
		var ammo: Dictionary = snapshot.items[p.cost_item_id]
		if ammo.get("owner_actor_id", "") != actor.id or not ammo.id in actor.inventory or ammo.quantity < int(p.units_per_attack): return C.fail("ATTACK_RESOURCE", "The weapon requires owned available authored ammunition or charge units.")
		if not Generic._has_ref(assessment, "/items/" + ammo.id): return C.fail("ACTION_FACT", "Attack components must cite their authored ammunition/charge source.")
		costs.append({"type": "item_quantity_delta", "item_id": ammo.id, "delta": -int(p.units_per_attack)})
	var branches: Array = []
	for mask in range(4):
		var hit: bool = bool(mask & 1); var forceful: bool = bool(mask & 2)
		var patches: Array = costs.duplicate(true)
		if hit:
			var damage := mini(int(p.damage if forceful else p.graze_damage), int(target.health.current))
			patches.append({"type": "actor_pool_delta", "actor_id": target.id, "pool": "health", "delta": -damage})
			var poisoned := false
			for status in target.statuses.values():
				if status.kind == "poison": poisoned = true
			if StatusContent.active(snapshot):
				for status in snapshot.status_foundation.instances.values():
					if status.owner_kind=="actor" and status.owner_id==target.id and status.definition_id=="poison":poisoned=true
			if forceful and p.on_full_hit == "poison" and not poisoned and target.health.current > damage and "status_tick" in target.hooks:
				if target.statuses.has("weapon_poison"): return C.fail("ATTACK_STATUS", "Authored weapon condition ID is already occupied.")
				if StatusContent.active(snapshot):
					patches.append({"type":"status_v2_apply","definition_id":"poison","owner_kind":"actor","owner_id":target.id,"source_id":item.id,"parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0}})
				else:
					patches.append({"type": "actor_status_set", "actor_id": target.id, "status_id": "weapon_poison", "status": {"id": "weapon_poison", "kind": "poison", "remaining_turns": 2, "magnitude": 1}})
		var label := "miss" if not hit else ("hit" if forceful else "graze")
		patches.append({"type": "combat_event", "actor_id": actor.id, "target_actor_id": target.id, "weapon_item_id": item.id, "presentation_kind": p.presentation_kind, "outcome": label})
		if snapshot.has("combat_turn"):
			if actor.id == "actor_player":
				patches.append(Basic.turn_patch(snapshot, "enemy", target.id, int(snapshot.combat_turn.round) + 1))
			else:
				patches.append(Basic.turn_patch(snapshot, "player", actor.id, int(snapshot.combat_turn.round)))
		branches.append({"id": "attack_" + label + "_" + str(mask), "requires": {"accuracy": hit, "impact": forceful}, "patches": patches})
	return {"ok": true, "resolver_id": resolver_id(), "branches": branches}

func _interaction(snapshot: Dictionary, assessment: Dictionary, actor: Dictionary, item: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var patch: Dictionary
	if kind == "equip_item":
		if item.get("owner_actor_id", "") != actor.id or not item.id in actor.inventory or item.interaction_profile.equip_slot != "weapon": return C.fail("ITEM_OWNERSHIP", "Equip requires a matching owned item.")
		var previous: String = actor.get("equipment", {}).get("weapon", "")
		if previous == item.id: return C.fail("ITEM_DUPLICATE", "This weapon is already equipped.")
		patch = {"type": "item_equip", "actor_id": actor.id, "item_id": item.id, "slot": "weapon", "expected_item_id": previous}
	else:
		if not item.interaction_profile.movable: return C.fail("ITEM_CAPABILITY", "This item cannot be moved.")
		var old_owner: String = item.get("owner_actor_id", "")
		var destination: String = actor.id; var target_hex: Array = []; var scene := ""
		if kind == "pickup_item":
			if old_owner == actor.id: return C.fail("ITEM_DUPLICATE", "This stack is already in the acting actor's inventory.")
			if old_owner.is_empty():
				if item.get("scene_id", "") != actor.scene_id or not item.has("hex") or Effects.distance(actor.hex, item.hex) > 1: return C.fail("ITEM_RANGE", "Ground stack must be in the same scene within one cell.")
			else:
				var owner: Dictionary = snapshot.actors[old_owner]
				if owner.health.current > 0 or not owner.faction in actor.get("combat_profile", {}).get("hostile_factions", []): return C.fail("ITEM_OWNERSHIP", "Taking owned items is permitted only from a downed authored hostile.")
				if owner.scene_id != actor.scene_id or Effects.distance(actor.hex, owner.hex) > 1: return C.fail("ITEM_RANGE", "Loot owner must be in the same scene within one cell.")
				if not Generic._has_ref(assessment, "/actors/" + old_owner): return C.fail("ACTION_FACT", "Looting requires the downed owner's frozen public facts.")
		elif kind in ["transfer_item", "drop_item"]:
			if old_owner != actor.id or not item.id in actor.inventory: return C.fail("ITEM_OWNERSHIP", "Only the acting actor's owned stack may be transferred or dropped.")
			if kind == "transfer_item":
				if not snapshot.actors.has(b.target_actor_id) or not Generic._has_ref(assessment, "/actors/" + b.target_actor_id): return C.fail("ACTION_FACT", "Transfer requires a cited existing recipient.")
				var recipient: Dictionary = snapshot.actors[b.target_actor_id]
				if recipient.id == actor.id or recipient.health.current <= 0 or recipient.faction in actor.get("combat_profile", {}).get("hostile_factions", []): return C.fail("ITEM_RECIPIENT", "Recipient must be another living non-hostile actor.")
				if recipient.scene_id != actor.scene_id or Effects.distance(actor.hex, recipient.hex) > 1: return C.fail("ITEM_RANGE", "Recipient must be in the same scene within one cell.")
				destination = recipient.id
			else:
				destination = ""; target_hex = actor.hex.duplicate(); scene = actor.scene_id
		patch = {"type": "item_relocate", "item_id": item.id, "expected_owner_id": old_owner, "expected_hex": item.get("hex", []).duplicate(), "owner_actor_id": destination, "scene_id": scene, "hex": target_hex}
	return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": kind + "_success", "requires": {"interact": true}, "patches": [patch]}, {"id": kind + "_failure", "requires": {"interact": false}, "patches": []}]}

static func inspect_item(public_facts: Dictionary, item_id: String) -> Dictionary:
	# Caller passes ModelView only. Selection/inspection never starts a turn.
	if not public_facts.get("items", {}).has(item_id): return C.fail("ITEM_UNKNOWN", "Unknown public item.")
	return {"ok": true, "readonly": true, "item": PublicView.pick(public_facts.items[item_id], PublicView.ITEM_FIELDS)}

static func committed_events(receipt: Dictionary, before: Dictionary) -> Array:
	# Supply only a successfully committed receipt and its actual before-state.
	var events: Array = []
	if not receipt.get("branch_id", "").begins_with("attack_") and not receipt.get("branch_id", "").begins_with("move_then_attack_"): return events
	for patch in receipt.get("patches", []):
		if patch.type == "combat_event":
			var event: Dictionary = patch.duplicate(true)
			event.action_id = receipt.action_id
			event.kind = event.presentation_kind
			event.source_actor_id = event.actor_id
			event.damage = 0
			for effect in receipt.patches:
				if effect.type == "actor_pool_delta" and effect.pool == "health" and effect.actor_id == event.target_actor_id and effect.delta < 0: event.damage -= int(effect.delta)
			event.downed = before.actors.has(event.target_actor_id) and int(before.actors[event.target_actor_id].health.current) <= int(event.damage)
			events.append(event)
		elif patch.type == "actor_status_set":
			events.append({"action_id": receipt.action_id, "kind": "status", "source_actor_id": receipt.actor_id, "target_actor_id": patch.actor_id, "status_kind": patch.status.kind})
	return events

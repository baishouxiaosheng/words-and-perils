extends RefCounted
## Authored whole-stack custody/equipment and bounded melee capabilities.
## This extension is opt-in; legacy items are not silently reinterpreted.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Creative = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const SCHEMA := "coast_item_interaction/v1"
const WEAPON_SCHEMA := "coast_attack_profile/v1"
const COMBAT_SCHEMA := "coast_combatant/v1"

static func interaction(slot: String = "") -> Dictionary:
	return {"schema_version": SCHEMA, "movable": true, "equip_slot": slot}

static func weapon(damage: int = 3, poison: bool = false, presentation_kind: String = "melee", cost_item_id: String = "") -> Dictionary:
	return {"schema_version": WEAPON_SCHEMA, "damage": damage, "graze_damage": 1, "stamina_cost": 1, "max_range": 1 if presentation_kind == "melee" else (3 if presentation_kind == "ranged" else 4), "on_full_hit": "poison" if poison else "none", "presentation_kind": presentation_kind, "cost_item_id": cost_item_id, "units_per_attack": 0 if presentation_kind == "melee" else 1}

static func combatant(hostile_factions: Array) -> Dictionary:
	return {"schema_version": COMBAT_SCHEMA, "hostile_factions": hostile_factions.duplicate()}

static func validate_item(item: Dictionary) -> bool:
	if item.has("custody_revision") and (not C.integer(item.custody_revision) or item.custody_revision < 0 or item.custody_revision > 1000000000): return false
	if item.has("interaction_profile"):
		var p: Variant = item.interaction_profile
		if not C.exact_fields(p, ["schema_version", "movable", "equip_slot"]) or p.schema_version != SCHEMA or not p.movable is bool or not p.equip_slot is String or not p.equip_slot in ["", "weapon"]: return false
	if item.has("weapon_profile"):
		var p: Variant = item.weapon_profile
		if not item.has("interaction_profile") or item.interaction_profile.equip_slot != "weapon" or not C.exact_fields(p, ["schema_version", "damage", "graze_damage", "stamina_cost", "max_range", "on_full_hit", "presentation_kind", "cost_item_id", "units_per_attack"]) or p.schema_version != WEAPON_SCHEMA: return false
		for field in ["damage", "graze_damage", "stamina_cost", "max_range", "units_per_attack"]:
			if not C.integer(p[field]): return false
		if p.damage < 1 or p.damage > 6 or p.graze_damage < 1 or p.graze_damage > p.damage or p.stamina_cost < 1 or p.stamina_cost > 3 or p.max_range < 1 or p.max_range > 4 or not p.on_full_hit in ["none", "poison"]: return false
		if not p.presentation_kind in ["melee", "ranged", "magic"] or not p.cost_item_id is String: return false
		if p.presentation_kind == "melee":
			if p.max_range != 1 or not p.cost_item_id.is_empty() or p.units_per_attack != 0: return false
		elif p.cost_item_id.is_empty() or p.units_per_attack < 1 or p.units_per_attack > 3: return false
	return true

static func validate_state(state: Dictionary) -> Dictionary:
	if state.has("combat_turn"):
		var turn: Variant = state.combat_turn
		if not C.exact_fields(turn, ["schema_version", "phase", "enemy_actor_id", "round"]) or turn.schema_version != "coast_encounter_turn/v1" or not turn.phase in ["player", "enemy"] or not turn.enemy_actor_id is String or not C.integer(turn.round) or turn.round < 0 or not state.actors.has("actor_player"): return C.fail("COMBAT_TURN", "Malformed authoritative encounter phase.")
		if not turn.enemy_actor_id.is_empty() and not state.actors.has(turn.enemy_actor_id): return C.fail("COMBAT_TURN", "Unknown phase actor.")
		if turn.phase == "enemy" and turn.enemy_actor_id.is_empty(): return C.fail("COMBAT_TURN", "Enemy phase requires a stable actor.")
		var player_profile: Variant = state.actors.actor_player.get("combat_profile", {})
		if not player_profile is Dictionary or not player_profile.get("hostile_factions", []) is Array: return C.fail("COMBAT_PROFILE", "Encounter player combat profile is malformed.")
		if not turn.enemy_actor_id.is_empty() and (turn.enemy_actor_id == "actor_player" or not state.actors[turn.enemy_actor_id].faction in player_profile.get("hostile_factions", [])): return C.fail("COMBAT_TURN", "Encounter phase target must be an authored opposing faction.")
	for actor_id in state.actors:
		var actor: Dictionary = state.actors[actor_id]
		if actor.has("combat_profile"):
			var p: Variant = actor.combat_profile
			if not C.exact_fields(p, ["schema_version", "hostile_factions"]) or p.schema_version != COMBAT_SCHEMA or not p.hostile_factions is Array or p.hostile_factions.size() > 8: return C.fail("COMBAT_PROFILE", "Malformed authored combatant profile.")
			var seen: Dictionary = {}
			for faction in p.hostile_factions:
				if not faction is String or faction.is_empty() or faction == actor.faction or seen.has(faction): return C.fail("COMBAT_PROFILE", "Hostile factions must be distinct named opposing factions.")
				seen[faction] = true
		if actor.has("equipment"):
			if not actor.equipment is Dictionary: return C.fail("EQUIPMENT", "Equipment must be a slot map.")
			for slot in actor.equipment:
				var id: Variant = actor.equipment[slot]
				if slot != "weapon" or not id is String or not state.items.has(id): return C.fail("EQUIPMENT", "Unknown equipment slot or item.")
				var item: Dictionary = state.items[id]
				if not validate_item(item) or item.get("interaction_profile", {}).get("equip_slot", "") != slot or item.get("owner_actor_id", "") != actor_id or not id in actor.inventory or item.quantity <= 0: return C.fail("EQUIPMENT", "Equipped item must remain an owned available item of the authored slot.")
	for id in state.items:
		var item: Dictionary = state.items[id]
		if not validate_item(item): return C.fail("ITEM_PROFILE", "Malformed authored item/weapon capability.")
		if item.has("weapon_profile") and not item.weapon_profile.cost_item_id.is_empty() and (not state.items.has(item.weapon_profile.cost_item_id) or item.weapon_profile.cost_item_id == id): return C.fail("ITEM_PROFILE", "Authored ammunition/charge source must be a different existing stack.")
		if not item.has("interaction_profile"): continue
		var owners: Array = []
		for actor_id in state.actors:
			if id in state.actors[actor_id].inventory: owners.append(actor_id)
		if item.has("owner_actor_id"):
			if item.has("hex") or item.has("scene_id") or owners != [item.owner_actor_id]: return C.fail("ITEM_CUSTODY", "An owned movable stack must have exactly one matching inventory and no ground position.")
		elif not item.has("hex") or not item.has("scene_id") or not owners.is_empty(): return C.fail("ITEM_CUSTODY", "An unowned movable stack needs one ground position and no inventory.")
	return {"ok": true}

static func apply(state: Dictionary, patch: Dictionary) -> Dictionary:
	if patch.type == "combat_turn_set": return _set_turn(state, patch)
	if patch.type == "combat_event": return _combat_event(state, patch)
	if patch.type == "item_relocate": return _relocate(state, patch)
	if patch.type == "item_equip": return _equip(state, patch)
	return C.fail("UNKNOWN_PATCH", "Unknown basic item operation.")

static func _relocate(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch, ["type", "item_id", "expected_owner_id", "expected_hex", "owner_actor_id", "scene_id", "hex"]) or not patch.item_id is String or not state.items.has(patch.item_id): return C.fail("ITEM_CUSTODY", "Malformed whole-stack relocation.")
	var item: Dictionary = state.items[patch.item_id]
	if Creative.active_source(state,item.id): return C.fail("CREATIVE_CUSTODY", "Remove the active brace before relocating its source.")
	if not validate_item(item) or not item.get("interaction_profile", {}).get("movable", false) or item.quantity <= 0: return C.fail("ITEM_CAPABILITY", "This stack does not expose an available movable capability.")
	if not patch.expected_owner_id is String or not patch.owner_actor_id is String or not patch.scene_id is String or not patch.expected_hex is Array or not patch.hex is Array: return C.fail("ITEM_CUSTODY", "Relocation identities/locations must have exact types.")
	if item.get("owner_actor_id", "") != patch.expected_owner_id or C.bytes(item.get("hex", [])) != C.bytes(patch.expected_hex): return C.fail("ITEM_STALE", "The expected custody changed before relocation.")
	if patch.owner_actor_id.is_empty():
		if not Cells.valid_hex(patch.hex, state, patch.scene_id): return C.fail("ITEM_CUSTODY", "Dropped stack requires a real cell in its scene.")
	elif not state.actors.has(patch.owner_actor_id) or not patch.hex.is_empty() or not patch.scene_id.is_empty(): return C.fail("ITEM_CUSTODY", "Owned stacks cannot also have a ground position.")
	if patch.owner_actor_id == patch.expected_owner_id and C.bytes(patch.hex) == C.bytes(patch.expected_hex): return C.fail("ITEM_DUPLICATE", "The requested custody is already current.")
	# Validate all references before making any edits. Never duplicate or split IDs.
	for actor_id in state.actors:
		var has_item: bool = patch.item_id in state.actors[actor_id].inventory
		if has_item != (actor_id == patch.expected_owner_id): return C.fail("ITEM_CUSTODY", "Existing custody and inventory disagree.")
	for actor in state.actors.values():
		actor.inventory.erase(patch.item_id)
		for slot in actor.get("equipment", {}).keys():
			if actor.equipment[slot] == patch.item_id: actor.equipment.erase(slot)
	if state.has("creative_placements"): state.creative_placements.erase(item.id)
	item["custody_revision"] = int(item.get("custody_revision", 0)) + 1
	item.erase("owner_actor_id"); item.erase("hex"); item.erase("scene_id")
	if patch.owner_actor_id.is_empty():
		item.hex = patch.hex.duplicate(); item.scene_id = patch.scene_id
	else:
		item.owner_actor_id = patch.owner_actor_id
		state.actors[patch.owner_actor_id].inventory.append(patch.item_id)
	return {"ok": true}

static func _equip(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch, ["type", "actor_id", "item_id", "slot", "expected_item_id"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not patch.item_id is String or not state.items.has(patch.item_id) or patch.slot != "weapon" or not patch.expected_item_id is String: return C.fail("EQUIPMENT", "Malformed equipment patch.")
	var actor: Dictionary = state.actors[patch.actor_id]; var item: Dictionary = state.items[patch.item_id]
	if Creative.active_source(state,item.id): return C.fail("CREATIVE_CUSTODY", "Remove the active brace before equipping its source.")
	if not validate_item(item) or item.get("interaction_profile", {}).get("equip_slot", "") != patch.slot or item.get("owner_actor_id", "") != patch.actor_id or not item.id in actor.inventory or item.quantity <= 0: return C.fail("EQUIPMENT", "Only owned available matching equipment can be equipped.")
	if actor.get("equipment", {}).get(patch.slot, "") != patch.expected_item_id or patch.item_id == patch.expected_item_id: return C.fail("EQUIPMENT_STALE", "Equipment slot changed or already holds this item.")
	if not actor.has("equipment"): actor.equipment = {}
	actor.equipment[patch.slot] = patch.item_id
	item["custody_revision"] = int(item.get("custody_revision", 0)) + 1
	return {"ok": true}

static func _key(hex: Array) -> String: return "%d,%d" % hex
static func _valid_hex(state: Dictionary, hex: Array) -> bool:
	return hex.size() == 2 and C.integer(hex[0]) and C.integer(hex[1]) and state.hexes.has(_key(hex))

static func _combat_event(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch, ["type", "actor_id", "target_actor_id", "weapon_item_id", "presentation_kind", "outcome"]) or not patch.actor_id is String or not patch.target_actor_id is String or not patch.weapon_item_id is String or not state.actors.has(patch.actor_id) or not state.actors.has(patch.target_actor_id) or not state.items.has(patch.weapon_item_id): return C.fail("COMBAT_EVENT", "Combat presentation requires stable authored identities.")
	var actor: Dictionary = state.actors[patch.actor_id]; var item: Dictionary = state.items[patch.weapon_item_id]
	if not validate_item(item) or not item.has("weapon_profile") or patch.presentation_kind != item.weapon_profile.presentation_kind or not patch.outcome in ["miss", "graze", "hit"] or actor.get("equipment", {}).get("weapon", "") != item.id or item.get("owner_actor_id", "") != actor.id: return C.fail("COMBAT_EVENT", "Combat event differs from the equipped authored capability.")
	# This event carries no mutation. It is recorded only as part of the frozen branch.
	return {"ok": true}

static func authorized_actor(state: Dictionary) -> String:
	if not state.has("combat_turn"): return ""
	return state.combat_turn.enemy_actor_id if state.combat_turn.phase == "enemy" else "actor_player"

static func turn_patch(state: Dictionary, phase: String, enemy_id: String, round_: int) -> Dictionary:
	return {"type": "combat_turn_set", "expected_phase": state.combat_turn.phase, "expected_enemy_actor_id": state.combat_turn.enemy_actor_id, "phase": phase, "enemy_actor_id": enemy_id, "round": round_}

static func _set_turn(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not state.has("combat_turn") or not C.exact_fields(patch, ["type", "expected_phase", "expected_enemy_actor_id", "phase", "enemy_actor_id", "round"]) or not patch.phase in ["player", "enemy"] or not patch.enemy_actor_id is String or not state.actors.has(patch.enemy_actor_id) or not C.integer(patch.round): return C.fail("COMBAT_TURN", "Invalid encounter phase transition.")
	if patch.enemy_actor_id == "actor_player" or not state.actors[patch.enemy_actor_id].faction in state.actors.actor_player.get("combat_profile", {}).get("hostile_factions", []): return C.fail("COMBAT_TURN", "Cannot schedule a friendly actor as this encounter's enemy.")
	var current: Dictionary = state.combat_turn
	if patch.expected_phase != current.phase or patch.expected_enemy_actor_id != current.enemy_actor_id or patch.round < current.round or patch.round > current.round + 1: return C.fail("COMBAT_TURN_STALE", "The authoritative phase changed.")
	state.combat_turn = {"schema_version": "coast_encounter_turn/v1", "phase": patch.phase, "enemy_actor_id": patch.enemy_actor_id, "round": patch.round}
	return {"ok": true}

static func finish_turn_hooks(state: Dictionary) -> Dictionary:
	if not state.has("combat_turn") or state.combat_turn.phase != "enemy": return {"ok": true, "patches": []}
	var id: String = state.combat_turn.enemy_actor_id
	if can_authored_attack(state, id, "actor_player"): return {"ok": true, "patches": []}
	# Scheduling only: a downed, empty, blocked or out-of-range melee NPC cannot
	# act. No attack, decision or damage is fabricated by this hook.
	var patch := turn_patch(state, "player", id, int(state.combat_turn.round))
	var applied := _set_turn(state, patch)
	return {"ok": true, "patches": [patch]} if applied.ok else applied

static func can_authored_attack(state: Dictionary, actor_id: String, target_id: String) -> bool:
	if not state.actors.has(actor_id) or not state.actors.has(target_id): return false
	var actor: Dictionary = state.actors[actor_id]; var target: Dictionary = state.actors[target_id]
	var item_id: String = actor.get("equipment", {}).get("weapon", "")
	if actor.health.current <= 0 or target.health.current <= 0 or actor.scene_id != target.scene_id or not target.faction in actor.get("combat_profile", {}).get("hostile_factions", []) or not state.items.has(item_id): return false
	var item: Dictionary = state.items[item_id]
	if not item.has("weapon_profile") or item.get("owner_actor_id", "") != actor_id or not item.id in actor.inventory or item.quantity <= 0: return false
	var p: Dictionary = item.weapon_profile
	var count: int = _distance(actor.hex, target.hex)
	if count < 1 or count > p.max_range or actor.stamina.current < p.stamina_cost: return false
	if not p.cost_item_id.is_empty():
		var ammo: Dictionary = state.items[p.cost_item_id]
		if ammo.get("owner_actor_id", "") != actor_id or not ammo.id in actor.inventory or ammo.quantity < p.units_per_attack: return false
	for point in attack_line(actor.hex, target.hex):
		var cell: Dictionary = Cells.cell(state, actor.scene_id, point)
		if cell.is_empty(): return false
		if cell.all_blocked or cell.air_blocked or (cell.ground_blocked and cell.terrain not in ["ocean", "sea", "lake", "water"]): return false
	return true

static func _distance(a: Array, b: Array) -> int:
	var dq: int = int(a[0]) - int(b[0]); var dr: int = int(a[1]) - int(b[1])
	return maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))
static func attack_line(a: Array, b: Array) -> Array:
	var count: int = _distance(a, b); var result: Array = []
	for i in range(count + 1):
		var t: float = float(i) / float(maxi(count, 1))
		var x: float = lerpf(float(a[0]), float(b[0]), t); var z: float = lerpf(float(a[1]), float(b[1]), t); var y: float = -x - z
		var rx: int = roundi(x); var ry: int = roundi(y); var rz: int = roundi(z)
		var dx: float = absf(float(rx) - x); var dy: float = absf(float(ry) - y); var dz: float = absf(float(rz) - z)
		if dx > dy and dx > dz: rx = -ry - rz
		elif dy > dz: ry = -rx - rz
		else: rz = -rx - ry
		var point: Array = [rx, rz]
		if not point in result: result.append(point)
	return result

static func validate_phase_assessment(state: Dictionary, assessment: Dictionary) -> Dictionary:
	var actor_id := authorized_actor(state)
	if actor_id.is_empty(): return {"ok": true}
	if assessment.bindings.get("actor_id", "") != actor_id: return C.fail("TURN_ACTOR", "The authoritative phase belongs to another actor.")
	if state.combat_turn.phase == "enemy" and (assessment.resolver_id != "coast_basic_attack_v1" or assessment.bindings.get("target_actor_id", "") != "actor_player"): return C.fail("ENEMY_ACTION_SCOPE", "This bounded encounter's enemy phase supports only an assessed attack against the engaged player.")
	return {"ok": true}

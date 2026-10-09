extends RefCounted
## One fail-closed physical melee predicate for UI, resolver and scheduling.
## Scheduling never performs an intentional attack or writes either input state.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Navigation = preload("res://view/generated_v3_enemy/navigation.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const ID = "generated_v3_stationary_enemy_spatial_policy/v1"

static func _actor(state: Dictionary, actor_id: String) -> Dictionary:
	if not state.get("actors") is Dictionary: return {}
	var value: Variant = state.actors.get(actor_id)
	if not value is Dictionary or value.get("id") != actor_id or not value.get("scene_id") is String or not Navigation.valid_hex(value.get("hex")): return {}
	return value

static func melee_range(state: Dictionary, actor_id: String, target_id: String, base_navigation: RefCounted) -> bool:
	if actor_id == target_id or base_navigation == null: return false
	var actor = _actor(state, actor_id); var target = _actor(state, target_id)
	if actor.is_empty() or target.is_empty() or actor.scene_id != target.scene_id: return false
	if Basic._distance(actor.hex, target.hex) != 1: return false
	var identity: Variant = state.get("generated_world", {})
	if not identity is Dictionary or identity.get("source_contract") != "generated_v3_source/v1" or identity.get("content_hash") != base_navigation.get("source_hash") or identity.get("geometry_hash") != base_navigation.get("geometry_hash") or identity.get("renderer_profile") != base_navigation.get("renderer_profile") or identity.get("placement_hash") != base_navigation.get("placement_hash") or identity.get("placement_profile") != base_navigation.get("placement_profile"): return false
	var graph: Variant = base_navigation.get("allowed"); var dry: Variant = base_navigation.get("supported")
	var a = Planner.key(actor.hex); var b = Planner.key(target.hex)
	if not graph is Dictionary or not dry is Dictionary or not dry.get(a) is bool or not dry.get(b) is bool or not dry[a] or not dry[b]: return false
	if not graph.get(a) is Array or not graph.get(b) is Array or not b in graph[a] or not a in graph[b]: return false
	if not state.get("hexes") is Dictionary or not state.get("scenes") is Dictionary or not state.get("scene_hexes", {}) is Dictionary: return false
	if state.get("scene_hexes", {}).has(actor.scene_id) and not state.scene_hexes[actor.scene_id] is Dictionary: return false
	var cell_map: Dictionary = state.get("scene_hexes", {}).get(actor.scene_id, state.hexes)
	for hex in [actor.hex, target.hex]:
		var cell: Variant = cell_map.get(Planner.key(hex))
		if not cell is Dictionary or cell.is_empty() or cell.get("scene_id") != actor.scene_id: return false
		for flag in ["all_blocked", "air_blocked", "ground_blocked"]:
			if not cell.get(flag) is bool or cell[flag]: return false
	# The original overlay includes exact dry-sea coverage and building edges.
	# Never substitute the enemy-occupied movement graph or axial distance alone.
	if not base_navigation.has_method("step"): return false
	return base_navigation.step(actor.hex, target.hex).get("ok", false) and base_navigation.step(target.hex, actor.hex).get("ok", false)

static func can_attack(state: Dictionary, actor_id: String, target_id: String, base_navigation: RefCounted) -> bool:
	if not melee_range(state, actor_id, target_id, base_navigation): return false
	var actor = _actor(state, actor_id); var target = _actor(state, target_id)
	for subject in [actor, target]:
		if not subject.get("health") is Dictionary or not C.integer(subject.health.get("current")) or subject.health.current <= 0: return false
	if not actor.get("stamina") is Dictionary or not C.integer(actor.stamina.get("current")) or not actor.get("inventory") is Array or not actor.get("equipment") is Dictionary or not actor.get("combat_profile") is Dictionary or not actor.get("faction") is String or not target.get("faction") is String: return false
	if not C.exact_fields(actor.combat_profile, ["schema_version", "hostile_factions"]) or actor.combat_profile.schema_version != Basic.COMBAT_SCHEMA: return false
	var hostile: Variant = actor.combat_profile.get("hostile_factions")
	if not hostile is Array or not target.faction in hostile or target.faction == actor.faction: return false
	if not state.get("items") is Dictionary: return false
	var item_id: Variant = actor.equipment.get("weapon", "")
	if not item_id is String or not state.items.get(item_id) is Dictionary: return false
	var item: Dictionary = state.items[item_id]
	if item.get("id") != item_id or not Basic.validate_item(item) or not item.has("weapon_profile") or item.get("owner_actor_id") != actor_id or not item_id in actor.inventory or not C.integer(item.get("quantity")) or item.quantity <= 0: return false
	var weapon: Dictionary = item.weapon_profile
	if weapon.presentation_kind != "melee" or weapon.max_range != 1 or weapon.stamina_cost != 1 or actor.stamina.current < weapon.stamina_cost: return false
	return true

static func occupied(state: Dictionary, hex: Array, except_actor_id: String = "") -> bool:
	if not Navigation.valid_hex(hex) or not state.get("actors") is Dictionary: return true
	var scene = ""
	if not except_actor_id.is_empty():
		var observer = _actor(state, except_actor_id)
		if observer.is_empty(): return true
		scene = observer.scene_id
	for id in state.actors:
		if not id is String: return true
		if id == except_actor_id: continue
		var actor = _actor(state, id)
		if actor.is_empty(): return true
		# Friendly roadside NPCs occupy a proven corner, not their entire cell.
		if actor.get("role") != "enemy" and id != "actor_player": continue
		if not scene.is_empty() and actor.scene_id != scene: continue
		if C.bytes(actor.hex) == C.bytes(hex): return true
	return false

static func schedule_patch(before: Dictionary, candidate: Dictionary, acting_actor_id: String, base_navigation: RefCounted, enemy_id: String) -> Dictionary:
	if not before.get("combat_turn") is Dictionary or not candidate.get("combat_turn") is Dictionary: return {}
	if not WorldSchema.validate(before).ok or not WorldSchema.validate(candidate).ok: return {}
	if C.bytes(before.combat_turn) != C.bytes(candidate.combat_turn): return {}
	if not acting_actor_id in ["actor_player", enemy_id] or Basic.authorized_actor(before) != acting_actor_id or not candidate.actors.has(enemy_id): return {}
	var phase = "player"; var round_ = int(before.combat_turn.round)
	if acting_actor_id == "actor_player":
		# Existing statuses tick once; a newly applied weapon poison does not.
		# Use the same registered hooks as Engine, on a detached candidate only.
		var after_hooks: Dictionary = candidate.duplicate(true)
		var simulated: Dictionary = Hooks.freeze(before, after_hooks)
		if simulated.get("ok", false) and can_attack(after_hooks, enemy_id, "actor_player", base_navigation):
			phase = "enemy"; round_ += 1
	if candidate.combat_turn.phase == phase and candidate.combat_turn.enemy_actor_id == enemy_id and int(candidate.combat_turn.round) == round_: return {}
	return Basic.turn_patch(candidate, phase, enemy_id, round_)

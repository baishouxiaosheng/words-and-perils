extends RefCounted
const StatusContent=preload("res://core/status_gameplay/content.gd")
const StatusFoundation = preload("res://core/status_foundation/engine_bridge.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const SceneTransitions = preload("res://core/ai_gm_rebuilt/scene_transitions.gd")
const TraversalPolicy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Settlement = preload("res://view/playable_build/settlement_content.gd")
const Creative = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const SCHEMA := "ai_gm_world/v1"
const STATUS_KINDS := ["poison", "flight", "drunk"]
const HOOK_IDS := ["status_tick", "patrol"]

static func validate(state: Variant) -> Dictionary:
	if not state is Dictionary or not C.safe(state): return C.fail("INVALID_WORLD", "World must be exact finite JSON data.")
	for field in ["schema_version", "world_id", "state_version", "turn", "actors", "items", "hexes", "scenes", "story_anchors", "flags"]:
		if not state.has(field): return C.fail("INVALID_WORLD", "Missing world field: " + field)
	if not state.schema_version is String or state.schema_version != SCHEMA or not text(state.world_id): return C.fail("INVALID_WORLD", "Unsupported world schema or world ID.")
	for field in ["state_version", "turn"]:
		if not C.integer(state[field]) or state[field] < 0: return C.fail("INVALID_WORLD", "Invalid world counter.")
	for collection in ["actors", "items", "hexes", "scenes", "story_anchors", "flags"]:
		if not state[collection] is Dictionary: return C.fail("INVALID_WORLD", "Collections must be objects.")
	if state.scenes.is_empty() or state.hexes.is_empty(): return C.fail("INVALID_WORLD", "Scenes and cells cannot be empty.")
	var cell_ids: Dictionary = {}
	var maps: Array = [{"scene_id":"","cells":state.hexes}]
	if state.has("scene_hexes"):
		if not state.scene_hexes is Dictionary: return C.fail("INVALID_WORLD", "Scene-local cell maps must be objects.")
		for scene_id in state.scene_hexes:
			if not state.scenes.has(scene_id) or not state.scene_hexes[scene_id] is Dictionary or state.scene_hexes[scene_id].is_empty(): return C.fail("INVALID_WORLD", "Scene-local map requires an installed nonempty scene.")
			for cell in state.hexes.values():
				if cell.scene_id == scene_id: return C.fail("INVALID_WORLD", "Scene-local map cannot shadow a legacy scene map.")
			maps.append({"scene_id":scene_id,"cells":state.scene_hexes[scene_id]})
	for map in maps:
		for cell_key in map.cells:
			var cell: Variant = map.cells[cell_key]
			if not cell is Dictionary or not text(cell.get("id")) or not C.integer(cell.get("q")) or not C.integer(cell.get("r")) or abs(cell.q) > 1000 or abs(cell.r) > 1000: return C.fail("INVALID_WORLD", "Malformed stable cell identity.")
			var expected_id: String = "hex_%d_%d" % [cell.q,cell.r] if map.scene_id.is_empty() else Cells.local_id(map.scene_id,[cell.q,cell.r])
			if cell_key != Traversal.key([cell.q,cell.r]) or cell.id != expected_id or cell_ids.has(cell.id): return C.fail("INVALID_WORLD", "Cell key, scene-local stable ID or coordinates differ.")
			if not state.scenes.has(cell.get("scene_id")) or (not map.scene_id.is_empty() and cell.scene_id != map.scene_id) or not text(cell.get("terrain")): return C.fail("INVALID_WORLD", "Cell scene/terrain is invalid.")
			for blocking in ["ground_blocked", "air_blocked", "all_blocked"]:
				if not cell.get(blocking) is bool: return C.fail("INVALID_WORLD", "Blocking values must be booleans.")
			cell_ids[cell.id] = cell
	for scene_id in state.scenes:
		var scene: Variant = state.scenes[scene_id]
		if not text(scene_id) or not scene is Dictionary or not scene.get("id") is String or scene.get("id") != scene_id or not text(scene.get("name")) or not text(scene.get("layer_id")) or not scene.get("hex_ids") is Array: return C.fail("INVALID_WORLD", "Malformed stable scene.")
		var seen: Dictionary = {}
		for cell_id in scene.hex_ids:
			if not cell_id is String or not cell_ids.has(cell_id) or seen.has(cell_id) or cell_ids[cell_id].scene_id != scene_id: return C.fail("INVALID_WORLD", "Invalid scene cell catalog.")
			seen[cell_id] = true
		for cell in cell_ids.values():
			if cell.scene_id == scene_id and not seen.has(cell.id): return C.fail("INVALID_WORLD", "Scene catalog omits its own cell.")
	for actor_id in state.actors:
		var actor: Variant = state.actors[actor_id]
		if not text(actor_id) or not actor is Dictionary or not actor.get("id") is String or actor.get("id") != actor_id or not text(actor.get("name")) or not actor.get("scene_id") is String or not valid_hex(actor.get("hex"), state, actor.get("scene_id", "")) or not state.scenes.has(actor.get("scene_id")): return C.fail("INVALID_WORLD", "Malformed stable actor.")
		if not text(actor.get("role")) or not text(actor.get("faction")) or (actor.has("observed_dialogue") and not actor.observed_dialogue is Array): return C.fail("INVALID_WORLD", "Public actor role/faction/dialogue must have explicit types.")
		for utterance in actor.get("observed_dialogue", []):
			if not utterance is String: return C.fail("INVALID_WORLD", "Observed dialogue contains text only, never arbitrary private objects.")
		if Cells.cell(state, actor.scene_id, actor.hex).scene_id != actor.scene_id: return C.fail("INVALID_WORLD", "Actor coordinate belongs to another scene.")
		if actor.has("traversal_profile") and not TraversalPolicy.validate_profile(actor.traversal_profile): return C.fail("INVALID_WORLD", "Invalid authored traversal capability profile.")
		for pool_name in ["health", "stamina"]:
			var pool: Variant = actor.get(pool_name)
			if not C.exact_fields(pool, ["current", "max"]) or not C.integer(pool.current) or not C.integer(pool.max) or pool.current < 0 or pool.max < pool.current: return C.fail("INVALID_WORLD", "Invalid actor pool.")
		if not actor.get("inventory") is Array or not actor.get("statuses") is Dictionary or not actor.get("hooks") is Array: return C.fail("INVALID_WORLD", "Actor inventory/status/hooks are malformed.")
		var inventory_seen: Dictionary = {}
		for item_id in actor.inventory:
			if not item_id is String or not state.items.has(item_id) or inventory_seen.has(item_id): return C.fail("INVALID_WORLD", "Invalid or duplicate inventory reference.")
			inventory_seen[item_id] = true
		var hooks_seen: Dictionary = {}
		for hook in actor.hooks:
			if not hook in HOOK_IDS or hooks_seen.has(hook): return C.fail("INVALID_WORLD", "Only explicitly supported, unique hooks are allowed.")
			hooks_seen[hook] = true
		for status_id in actor.statuses:
			if not valid_status(status_id, actor.statuses[status_id]): return C.fail("INVALID_WORLD", "Malformed stable typed status.")
		if "patrol" in actor.hooks:
			var patrol: Variant = actor.get("patrol")
			if not C.exact_fields(patrol, ["route", "index"]) or not patrol.route is Array or patrol.route.is_empty() or not C.integer(patrol.index) or patrol.index < 0 or patrol.index >= patrol.route.size(): return C.fail("INVALID_WORLD", "Malformed configured patrol.")
			for target in patrol.route:
				if not valid_hex(target, state, actor.scene_id): return C.fail("INVALID_WORLD", "Patrol route leaves its configured scene.")
	var environment_check := Effects.validate_environment(state)
	if not environment_check.ok: return environment_check
	for item_id in state.items:
		var item: Variant = state.items[item_id]
		if not text(item_id) or not item is Dictionary or not item.get("id") is String or item.get("id") != item_id or not text(item.get("name")) or not item.get("description") is String or not C.integer(item.get("quantity")) or item.quantity < 0: return C.fail("INVALID_WORLD", "Malformed stable item.")
		if not Effects.validate_source(item_id, item): return C.fail("INVALID_WORLD", "Condition sources must match an authored bounded profile.")
		if item.has("hex") and (not item.get("scene_id") is String or not valid_hex(item.hex, state, item.get("scene_id", ""))): return C.fail("INVALID_WORLD", "Item position/scene is invalid.")
		if item.has("owner_actor_id") and not state.actors.has(item.owner_actor_id): return C.fail("INVALID_WORLD", "Item owner is invalid.")
	for anchor_id in state.story_anchors:
		var anchor: Variant = state.story_anchors[anchor_id]
		if not text(anchor_id) or not anchor is Dictionary or not anchor.get("id") is String or anchor.get("id") != anchor_id or not text(anchor.get("text")): return C.fail("INVALID_WORLD", "Malformed stable story anchor.")
	for flag_id in state.flags:
		if not text(flag_id) or (state.flags[flag_id] is Dictionary or state.flags[flag_id] is Array): return C.fail("INVALID_WORLD", "Flags are scalar facts with stable names.")
	var creative_check := Creative.validate_state(state)
	if not creative_check.ok: return creative_check
	var settlement_check := Settlement.validate(state)
	if not settlement_check.ok: return settlement_check
	var scene_check := SceneTransitions.validate_state(state)
	if not scene_check.ok: return scene_check
	var basic_check := BasicEffects.validate_state(state)
	if not basic_check.ok: return basic_check
	var gameplay_check:Dictionary=StatusContent.validate(state)
	if not gameplay_check.ok:return gameplay_check
	var status_check: Dictionary = StatusFoundation.validate_world(state)
	if not status_check.ok: return status_check
	return NPCState.validate_world(state)

static func text(value: Variant) -> bool: return value is String and not value.strip_edges().is_empty()
static func valid_hex(value: Variant, state: Dictionary, scene_id: String = "") -> bool:
	if not scene_id.is_empty(): return Cells.valid_hex(value, state, scene_id)
	return value is Array and value.size() == 2 and C.integer(value[0]) and C.integer(value[1]) and abs(value[0]) <= 1000 and abs(value[1]) <= 1000 and state.hexes.has(Traversal.key(value))

static func valid_status(status_id: String, status: Variant) -> bool:
	return text(status_id) and C.exact_fields(status, ["id", "kind", "remaining_turns", "magnitude"]) and status.id is String and status.id == status_id and status.kind is String and status.kind in STATUS_KINDS and C.integer(status.remaining_turns) and status.remaining_turns > 0 and status.remaining_turns <= 10000 and C.integer(status.magnitude) and status.magnitude >= 0 and status.magnitude <= 10000

static func apply(state: Dictionary, patch: Variant, internal_hook: bool = false) -> Dictionary:
	if not patch is Dictionary or not C.safe(patch) or not patch.get("type") is String: return C.fail("INVALID_PATCH", "Typed patch must be finite exact JSON.")
	match patch.type:
		"status_v2_apply", "status_v2_remove", "status_v2_store", "status_v2_world_step", "status_v2_event":
			return StatusFoundation.apply(state, patch, internal_hook)
		"npc_conversation_record":
			if internal_hook:return C.fail("NPC_HOOK","交谈只能由已评估的行动结算，不能作为回合钩子。")
			return NPCState.apply(state,patch)
		"creative_source_place", "creative_relation_set":
			return Creative.apply(state, patch)
		"settlement_gate_set":
			return Settlement.apply_gate(state, patch)
		"actor_scene_transition":
			return SceneTransitions.apply(state, patch)
		"item_relocate", "item_equip", "combat_event", "combat_turn_set":
			return BasicEffects.apply(state, patch)
		"environment_fell":
			return Effects.apply_fell(state, patch)
		"actor_pool_delta":
			if not C.exact_fields(patch, ["type", "actor_id", "pool", "delta"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not patch.pool is String or not patch.pool in ["health", "stamina"] or not C.integer(patch.delta): return C.fail("INVALID_PATCH", "Invalid actor pool delta.")
			var pool: Dictionary = state.actors[patch.actor_id][patch.pool]
			if pool.current + patch.delta < 0 or pool.current + patch.delta > pool.max: return C.fail("INVALID_PATCH", "Actor pool delta is out of bounds.")
			pool.current += patch.delta
		"item_quantity_delta":
			if Creative.active_source(state, str(patch.get("item_id",""))): return C.fail("CREATIVE_CUSTODY", "Release the active brace before consuming or moving its source.")
			if not C.exact_fields(patch, ["type", "item_id", "delta"]) or not patch.item_id is String or not state.items.has(patch.item_id) or not C.integer(patch.delta) or state.items[patch.item_id].quantity + patch.delta < 0: return C.fail("INVALID_PATCH", "Invalid item quantity delta.")
			state.items[patch.item_id].quantity += patch.delta
		"actor_move":
			if not C.exact_fields(patch, ["type", "actor_id", "scene_id", "hex"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not valid_hex(patch.hex, state, patch.get("scene_id", "")): return C.fail("INVALID_PATCH", "Invalid actor move identity.")
			if not patch.scene_id is String or patch.scene_id != state.actors[patch.actor_id].scene_id or Traversal.path(state, patch.actor_id, patch.hex, Cells.cells(state, patch.scene_id).size(), false).is_empty(): return C.fail("INVALID_PATCH", "Move is unreachable under the unified traversal rule.")
			if state.has("settlement_state") or state.has("physical_catalog"):
				var actor: Dictionary = state.actors[patch.actor_id]
				var dq: int = patch.hex[0]-actor.hex[0]; var dr: int = patch.hex[1]-actor.hex[1]
				if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))!=1 or not Traversal.edge_allowed(state,actor,actor.hex,patch.hex): return C.fail("INVALID_PATCH","Settlement movement patches must be adjacent and respect the exact wall/gate edge.")
			state.actors[patch.actor_id].hex = patch.hex.duplicate()
		"cell_blocking_set":
			if not C.exact_fields(patch, ["type", "cell_id", "ground_blocked", "air_blocked", "all_blocked"]) or not patch.cell_id is String: return C.fail("INVALID_PATCH", "Invalid cell blocking patch fields.")
			var cell_key := ""
			for key in state.hexes:
				if state.hexes[key].id == patch.cell_id: cell_key = key; break
			if cell_key.is_empty(): return C.fail("INVALID_PATCH", "Unknown stable cell.")
			for field in ["ground_blocked", "air_blocked", "all_blocked"]:
				if not patch[field] is bool: return C.fail("INVALID_PATCH", "Blocking values must be bool.")
			for field in ["ground_blocked", "air_blocked", "all_blocked"]: state.hexes[cell_key][field] = patch[field]
		"actor_status_set":
			if not C.exact_fields(patch, ["type", "actor_id", "status_id", "status"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not patch.status_id is String or not valid_status(patch.status_id, patch.status): return C.fail("INVALID_PATCH", "Invalid typed status patch.")
			state.actors[patch.actor_id].statuses[patch.status_id] = patch.status.duplicate(true)
		"actor_status_remove":
			if not C.exact_fields(patch, ["type", "actor_id", "status_id"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not state.actors[patch.actor_id].statuses.has(patch.status_id): return C.fail("INVALID_PATCH", "Unknown status removal.")
			state.actors[patch.actor_id].statuses.erase(patch.status_id)
		"flag_set":
			if not C.exact_fields(patch, ["type", "flag_id", "value"]) or not patch.flag_id is String or not state.flags.has(patch.flag_id) or patch.value is Dictionary or patch.value is Array: return C.fail("INVALID_PATCH", "Invalid stable scalar flag patch.")
			state.flags[patch.flag_id] = patch.value
		"patrol_advance":
			if not internal_hook or not C.exact_fields(patch, ["type", "actor_id", "index"]) or not patch.actor_id is String or not state.actors.has(patch.actor_id) or not C.integer(patch.index): return C.fail("INVALID_PATCH", "Patrol progression is a configured internal hook only.")
			var actor: Dictionary = state.actors[patch.actor_id]
			if not "patrol" in actor.hooks or patch.index != (actor.patrol.index + 1) % actor.patrol.route.size(): return C.fail("INVALID_PATCH", "Invalid patrol progression.")
			actor.patrol.index = patch.index
		_:
			return C.fail("UNKNOWN_PATCH", "Unknown typed patch: " + patch.type)
	return {"ok": true}

static func stable(before: Dictionary, after: Dictionary) -> bool:
	for collection in ["actors", "items", "hexes", "scenes", "story_anchors"]:
		if before[collection].size() != after[collection].size(): return false
		for id in before[collection]:
			if not after[collection].has(id) or before[collection][id].id != after[collection][id].id: return false
	for id in before.scenes:
		if C.bytes(before.scenes[id]) != C.bytes(after.scenes[id]): return false
	if C.bytes(before.story_anchors) != C.bytes(after.story_anchors): return false
	for id in before.hexes:
		if before.hexes[id].q != after.hexes[id].q or before.hexes[id].r != after.hexes[id].r or before.hexes[id].scene_id != after.hexes[id].scene_id: return false
	if C.bytes(before.get("scene_hexes", {})) != C.bytes(after.get("scene_hexes", {})) or not SceneTransitions.stable(before, after): return false
	for id in before.actors:
		if C.bytes(before.actors[id].get("traversal_profile")) != C.bytes(after.actors[id].get("traversal_profile")): return false
		if C.bytes(before.actors[id].hooks) != C.bytes(after.actors[id].hooks): return false
		if C.bytes(before.actors[id].get("combat_profile")) != C.bytes(after.actors[id].get("combat_profile")): return false
	for id in before.items:
		for field in ["condition_source", "interaction_profile", "weapon_profile", "physical_traits"]:
			if C.bytes(before.items[id].get(field)) != C.bytes(after.items[id].get(field)): return false
	return StatusContent.stable(before,after) and NPCState.stable(before,after) and before.world_id == after.world_id and Effects.stable_environment(before, after) and Settlement.stable(before, after) and Creative.Content.stable(before, after)

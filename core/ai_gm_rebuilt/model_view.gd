extends RefCounted
const V3RiversProjection = preload("res://view/generated_v3_rivers/projection.gd")
const StatusDetails=preload("res://view/status_gameplay/details.gd")
const V3EquipmentProjection=preload("res://view/generated_v3_equipment/projection.gd")
const V3EnemyProjection=preload("res://view/generated_v3_enemy/projection.gd")
const V3NPCProjection=preload("res://view/generated_v3_npc/projection.gd")
const NPCProjection=preload("res://core/source_npc/projection.gd")
const VegetationProjection=preload("res://core/generated_v3_vegetation/projection.gd")
const StaticEntityProjection = preload("res://core/source_entities/static_projection.gd")
const V3VillageProjection = preload("res://view/generated_v3_village/projection.gd")
const SourceEntityProjection = preload("res://core/source_entities/projection.gd")
const V3InventoryProjection = preload("res://view/generated_v3_inventory/projection.gd")
const V3Projection = preload("res://view/generated_v3_adventure/projection.gd")
const InventoryProjection = preload("res://view/generated_inventory/projection.gd")
const GeneratedProjection = preload("res://view/generated_adventure/projection.gd")
const EntityCatalog = preload("res://view/playable_build/entity_catalog.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ACTOR_FIELDS := ["id", "name", "hex", "scene_id", "role", "faction", "health", "stamina", "inventory", "statuses", "observed_dialogue", "equipment", "combat_profile", "traversal_profile", "status_body", "status_actions", "status_details"]
const ITEM_FIELDS := ["id", "name", "description", "quantity", "hex", "scene_id", "owner_actor_id", "condition_source", "weapon_profile", "interaction_profile", "custody_revision", "physical_traits", "status_source", "status_on_hit"]
const CELL_FIELDS := ["id", "q", "r", "scene_id", "terrain", "ground_blocked", "air_blocked", "all_blocked"]

static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result

static func validate_policy(state: Dictionary, policy: Variant) -> Dictionary:
	if not C.exact_fields(policy, ["npc_secret_allowlist", "public_flag_ids"]) or not policy.npc_secret_allowlist is Array or not policy.public_flag_ids is Array: return C.fail("INVALID_PROJECTION", "Projection requires explicit secret and flag allowlists.")
	for path in policy.npc_secret_allowlist:
		if not path is String: return C.fail("INVALID_PROJECTION", "Secret allowlist entries are exact pointers.")
		var tokens: PackedStringArray = path.split("/")
		if tokens.size() != 5 or tokens[0] != "" or tokens[1] != "actors" or tokens[3] != "secrets" or tokens[4].is_empty() or not state.actors.has(tokens[2]) or state.actors[tokens[2]].get("role") == "player" or not C.pointer(state, path).ok: return C.fail("INVALID_PROJECTION", "Only individual existing NPC secret fields can be allowlisted.")
	for flag_id in policy.public_flag_ids:
		if not flag_id is String or not state.flags.has(flag_id): return C.fail("INVALID_PROJECTION", "Unknown public flag allowlist entry.")
	return {"ok": true}

static func facts(snapshot: Dictionary, policy: Dictionary, focus: Dictionary = {}) -> Dictionary:
	var result:Dictionary=_base_facts(snapshot,policy,focus)
	if snapshot.has("status_foundation"):
		for actor_id in result.get("actors",{}):
			if snapshot.actors.has(actor_id):result.actors[actor_id]["status_details"]=StatusDetails.public_details(snapshot,snapshot.actors[actor_id])
	return C.normalized(result)

static func _base_facts(snapshot: Dictionary, policy: Dictionary, focus: Dictionary = {}) -> Dictionary:
	if V3RiversProjection.active(snapshot): return V3RiversProjection.facts(snapshot,focus)
	if V3EquipmentProjection.active(snapshot): return V3EquipmentProjection.facts(snapshot,focus)
	if V3EnemyProjection.active(snapshot): return V3EnemyProjection.facts(snapshot,focus)
	if V3NPCProjection.active(snapshot): return V3NPCProjection.facts(snapshot,focus)
	if V3VillageProjection.active(snapshot): return V3VillageProjection.facts(snapshot,focus)
	if V3InventoryProjection.active(snapshot): return V3InventoryProjection.facts(snapshot,focus)
	if V3Projection.active(snapshot): return V3Projection.facts(snapshot,focus)
	if InventoryProjection.active(snapshot): return InventoryProjection.facts(snapshot, focus)
	if GeneratedProjection.active(snapshot): return GeneratedProjection.facts(snapshot,focus)
	var result := {"schema_version": snapshot.schema_version, "world_id": snapshot.world_id, "state_version": snapshot.state_version, "turn": snapshot.turn, "actors": {}, "items": {}, "hexes": {}, "scenes": {}, "story_anchors": {}, "flags": {}}
	for id in snapshot.actors: result.actors[id] = pick(snapshot.actors[id], ACTOR_FIELDS)
	for id in snapshot.items: result.items[id] = pick(snapshot.items[id], ITEM_FIELDS)
	for id in snapshot.hexes: result.hexes[id] = pick(snapshot.hexes[id], CELL_FIELDS)
	if snapshot.has("scene_hexes"):
		result.scene_hexes = {}
		for scene_id in snapshot.scene_hexes:
			result.scene_hexes[scene_id] = {}
			for key in snapshot.scene_hexes[scene_id]: result.scene_hexes[scene_id][key] = pick(snapshot.scene_hexes[scene_id][key], CELL_FIELDS)
	for id in snapshot.scenes: result.scenes[id] = pick(snapshot.scenes[id], ["id", "name", "layer_id", "hex_ids", "renderer_id", "navigation_id", "bundle_id"])
	if snapshot.has("scene_transitions"):
		result.scene_transitions = {}
		for id in snapshot.scene_transitions:
			result.scene_transitions[id] = pick(snapshot.scene_transitions[id], ["id", "name", "source_scene_id", "source_hex", "destination_scene_id", "landing_hex", "return_entrance_id", "stamina_cost", "enabled"])
	for id in snapshot.story_anchors: result.story_anchors[id] = pick(snapshot.story_anchors[id], ["id", "text"])
	var content=preload("res://view/playable_build/settlement_content.gd")
	if content.active(snapshot):
		result.settlement=content.public_facts(snapshot)
		result.settlements={}
		for place in content.all_settlements():result.settlements[place.id]=content.public_facts(snapshot,place.id)
	if snapshot.has("physical_catalog"):
		for field in ["physical_catalog","passage_targets","creative_placements","creative_relations"]: result[field] = C.normalized(snapshot[field])
	if snapshot.has("combat_turn"): result.combat_turn = pick(snapshot.combat_turn, ["schema_version", "phase", "enemy_actor_id", "round"])
	if snapshot.has("environment_entities"):
		result.environment_entities = {}
		for id in snapshot.environment_entities:
			result.environment_entities[id] = entity_view(EntityCatalog.entity(id, snapshot))
	for id in policy.public_flag_ids: result.flags[id] = snapshot.flags[id]
	for path in policy.npc_secret_allowlist:
		var tokens: PackedStringArray = path.split("/")
		var actor_id: String = tokens[2]
		if not result.actors[actor_id].has("secrets"): result.actors[actor_id].secrets = {}
		result.actors[actor_id].secrets[tokens[4].replace("~1", "/").replace("~0", "~")] = C.normalized(C.pointer(snapshot, path).value)
	return C.normalized(result)

static func focus_view(focus: Dictionary, projected: Dictionary) -> Dictionary:
	if focus.is_empty(): return {}
	if focus.get("catalog_version")=="source-npc-focus/v1":return NPCProjection.frozen_focus(focus,historical_cell_fields(focus.get("facts",{}).get("supporting_cell",{})))
	if focus.get("catalog_version")=="source-vegetation-focus/v1":return VegetationProjection.frozen_focus(focus)
	if focus.get("catalog_version")=="source-static-focus/v1":return StaticEntityProjection.frozen_focus(focus,historical_cell_fields(focus.get("facts",{}).get("supporting_cell",{})))
	if focus.get("catalog_version")=="source-entity-focus/v1":return SourceEntityProjection.frozen_focus(focus,historical_cell_fields(focus.get("facts",{}).get("supporting_cell",{})))
	var result: Dictionary = pick(focus, ["schema_version", "world_id", "kind", "id", "hex", "catalog_version", "entity_revision", "scene_id"])
	if focus.get("catalog_version") == "generated-inventory-focus/v1":
		# Historical receipts must project their frozen facts, never present custody.
		result.facts = pick(focus.facts,["scene_id","source_identity","selection_is_action"])
		result.facts.item = pick(focus.facts.get("item",{}),InventoryProjection.ITEM_FIELDS)
		result.facts.supporting_cell = pick(focus.facts.get("supporting_cell",{}),GeneratedProjection.CELL_FIELDS)
	elif focus.get("catalog_version") == "creative-scene-focus/v1":
		result.facts = pick(focus.facts,["scene_id","physical_catalog","selection_is_action"])
		result.facts.supporting_cell = pick(focus.facts.get("supporting_cell",{}),CELL_FIELDS)
		if focus.kind == "item":
			result.facts.item = pick(focus.facts.get("item",{}),ITEM_FIELDS)
			result.facts.placement = pick(focus.facts.get("placement",{}),["schema_version","target_id","anchor_id","posture","revision"])
		else:
			# Both objects are exact catalog/relation schemas, still list the public fields.
			result.facts.passage_target = pick(focus.facts.get("passage_target",{}),["schema_version","id","name","scene_id","catalog_id","endpoints","support_hex","anchor_id","width_mm","min_section_mm","max_section_mm","required_bearing","revision","geometry_policy","pose_frames","source_support"])
			result.facts.state = pick(focus.facts.get("state",{}),["posture","revision","ground_blocking","relation"])
	elif focus.get("catalog_version") == "active-scene-entities/v1":
		result.facts = {"entity": entity_view(focus.facts.entity), "supporting_cell": pick(focus.facts.supporting_cell, CELL_FIELDS), "selection_is_action": false}
	elif focus.kind == "actor": result.facts = projected.actors[focus.id].duplicate(true)
	elif focus.kind == "tile":
		var cells: Dictionary = projected.get("scene_hexes",{}).get(focus.get("scene_id",""),projected.hexes)
		result.facts = cells["%d,%d" % [focus.hex[0], focus.hex[1]]].duplicate(true)
	elif focus.kind == "tree":
		result.facts = {"observable_feature": pick(focus.facts.observable_feature, ["id", "hex", "slot", "catalog_version", "vegetation_type", "local_position", "size", "descriptive_numeric_quantum", "exact_recipe_transform_f64_hex"]), "supporting_cell": pick(focus.facts.supporting_cell, CELL_FIELDS), "presentation_only": true, "patchable_entity": false}
	elif focus.kind == "mountain": result.facts = {"supporting_cell": pick(focus.facts.supporting_cell, CELL_FIELDS), "region_id": focus.id, "scope": focus.facts.scope}
	else: result.facts = pick(focus.facts, ["id", "name", "kind", "hex", "hex_key"])
	return C.normalized(result)

static func historical_focus(focus: Dictionary, policy: Dictionary) -> Dictionary:
	if focus.is_empty(): return {}
	var projected: Dictionary = {"actors": {}, "hexes": {}}
	if focus.kind == "actor":
		var actor: Dictionary = pick(focus.facts, ACTOR_FIELDS)
		for path in policy.npc_secret_allowlist:
			var tokens: PackedStringArray = path.split("/")
			if tokens[2] != focus.id: continue
			var secret_key: String = tokens[4].replace("~1", "/").replace("~0", "~")
			if focus.facts.get("secrets", {}).has(secret_key):
				if not actor.has("secrets"): actor.secrets = {}
				actor.secrets[secret_key] = C.normalized(focus.facts.secrets[secret_key])
		projected.actors[focus.id] = actor
	elif focus.kind == "tile":
		var key := "%d,%d" % [focus.hex[0],focus.hex[1]]
		projected.hexes[key] = pick(focus.facts,historical_cell_fields(focus.facts))
		if focus.has("scene_id"): projected.scene_hexes={focus.scene_id:{key:pick(focus.facts,historical_cell_fields(focus.facts))}}
	return focus_view(focus, projected)

static func historical_cell_fields(cell: Dictionary) -> Array:
	if cell.get("source_cell_version")==V3RiversProjection.CELL_VERSION:return V3RiversProjection.CELL_FIELDS
	if cell.get("source_cell_version")==V3Projection.CELL_VERSION:return V3Projection.CELL_FIELDS
	return GeneratedProjection.CELL_FIELDS if cell.get("source_cell_version")=="generated_macro_cell/v1" else CELL_FIELDS

static func entity_view(entity: Dictionary) -> Dictionary:
	var result := pick(entity, ["id", "kind", "name", "hex", "scene_id", "catalog_version", "bundle_id"])
	result.source = pick(entity.get("source", {}), ["instance_row", "instance_sha256", "source_mesh_sha256", "new_source_face_index", "legacy_parent_face_index", "source_region", "mountain_manifest_sha256", "authored_prop", "authored_content", "content_sha256"])
	result.public_facts = pick(entity.get("public_facts", {}), ["vegetation_type", "position", "height", "crown_radius", "visible_form", "support_hexes", "bounds_xz", "description", "lit", "gate_id", "flight_policy", "attack_policy", "settlement_id", "architectural_kit", "site_kind", "footprint_hex_count", "blocking_scope"])
	result.state = pick(entity.get("state", {}), ["posture", "revision", "ground_blocking"])
	return result

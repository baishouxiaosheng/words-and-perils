extends RefCounted
## Bounded public facts only. No Source, Generator, mesh, graph or Engine reads.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventoryProjection = preload("res://view/generated_v3_inventory/projection.gd")
const EntityProjection = preload("res://core/source_entities/projection.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const StaticCatalog = preload("res://core/source_entities/static_catalog.gd")
const StaticProjection = preload("res://core/source_entities/static_projection.gd")
const ID := "generated_v3_village_inventory_context/v1"
const PROFILE := "generated_v3_village_inventory/v1"
const WORLD_PREFIX := "generated_v3_village_inventory_v1_"
const CELL_VERSION := InventoryProjection.CELL_VERSION
const CELL_FIELDS := InventoryProjection.CELL_FIELDS
const ACTOR_FIELDS := InventoryProjection.ACTOR_FIELDS
const SOURCE_FIELDS := ["source_contract","profile","source_schema","recipe_version","recipe_id","seed","seed_token","board_radius","content_hash","renderer_profile","geometry_hash","runtime_hash","navigation_id","projection_id","terrain_mapping_id","spawn_policy","pipeline_sha256","base_runtime_hash","inventory_profile","inventory_profile_hash","entity_profile","entity_catalog_hash"]
const SOURCE_EXTRA_FIELDS := ["inventory_runtime_hash","village_inventory_profile","village_inventory_profile_hash","placement_hash","placement_profile","placement_context_hash","effective_navigation_id","effective_navigation_hash","static_entity_profile","static_entity_catalog_hash"]
const RADIUS := InventoryProjection.RADIUS
const MAX_CELLS := InventoryProjection.MAX_CELLS
static func active(state: Dictionary) -> bool:
	var metadata: Variant = state.get("generated_world",{})
	# Any remaining combined marker owns rejection, never the older projector.
	return (metadata is Dictionary and (metadata.get("profile") == PROFILE or metadata.get("village_inventory_profile") == PROFILE or metadata.get("static_entity_profile") == PROFILE or metadata.get("projection_id") == ID or metadata.has("inventory_runtime_hash") or metadata.has("static_entity_catalog") or metadata.has("placement_hash") or metadata.has("effective_navigation_hash"))) or str(state.get("world_id","")).begins_with(WORLD_PREFIX)
static func matching_identity(state: Dictionary) -> bool:
	var metadata: Variant = state.get("generated_world",{})
	if not metadata is Dictionary or not C.safe(state): return false
	if metadata.get("source_contract") != "generated_v3_source/v1" or metadata.get("profile") != PROFILE or metadata.get("village_inventory_profile") != PROFILE or metadata.get("static_entity_profile") != PROFILE or metadata.get("projection_id") != ID or metadata.get("source_schema") != "coastal_source_v3/prototype1": return false
	if metadata.get("inventory_profile") != InventoryProjection.PROFILE or metadata.get("entity_profile") != InventoryProjection.PROFILE or metadata.get("placement_profile") != "dry_village/v1" or metadata.get("effective_navigation_id") != "generated_v3_placement_navigation/v1": return false
	for field in ["content_hash","geometry_hash","base_runtime_hash","inventory_runtime_hash","inventory_profile_hash","entity_catalog_hash","village_inventory_profile_hash","placement_hash","placement_context_hash","effective_navigation_hash","static_entity_catalog_hash","runtime_hash"]:
		if not Catalog.valid_hash(metadata.get(field)): return false
	if state.get("world_id") != WORLD_PREFIX + metadata.content_hash or not state.get("actors") is Dictionary or not state.get("items") is Dictionary or not state.get("scenes") is Dictionary or not state.get("hexes") is Dictionary or not state.get("story_anchors") is Dictionary or not state.get("flags") is Dictionary: return false
	if not state.actors.get("actor_player") is Dictionary or state.actors.actor_player.get("scene_id") != "scene_generated_v3" or not state.scenes.has("scene_generated_v3"): return false
	if not Catalog.validate_world(state).get("ok",false) or not StaticCatalog.validate_world(state).get("ok",false): return false
	if state.items.keys() != ["item_travel_bundle"] or metadata.entity_catalog.entries.keys() != ["item_travel_bundle"]: return false
	return metadata.runtime_hash == C.digest({"profile":PROFILE,"profile_hash":metadata.village_inventory_profile_hash,"base_runtime_hash":metadata.base_runtime_hash,"inventory_runtime_hash":metadata.inventory_runtime_hash,"entity_catalog_hash":metadata.entity_catalog_hash,"placement_hash":metadata.placement_hash,"placement_profile":metadata.placement_profile,"placement_context_hash":metadata.placement_context_hash,"effective_navigation_hash":metadata.effective_navigation_hash,"static_entity_catalog_hash":metadata.static_entity_catalog_hash})
static func pick(value: Dictionary, fields: Array) -> Dictionary: return EntityProjection.pick(value,fields)
static func facts(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	if not matching_identity(state): return {}
	var actor: Dictionary = state.actors.actor_player
	var result := {"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"static_entities":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,SOURCE_FIELDS+SOURCE_EXTRA_FIELDS),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS,"total_map_cells":state.hexes.size(),"omitted_cells":"outside bounded public context; not evidence of absence","selection_is_action":false,"navigation_scope":"scene.navigation_id names the unchanged terrain layer; generated_source.effective_navigation_id names the validated building-obstruction overlay used for actual movement and pickup reach","descriptive_quantum":"exact V3 source values at 1/4096; biome is separate from legal terrain cost","river_scope":"source drainage descriptor only; no river surface, crossing or bridge effects","item_scope":"one registered starting whole-stack travel bundle with exact recorded custody","static_scope":"source-bound settlement/building/road selection and cell observation only; no pickup, conversation, gate, interior or NPC effects; roads have no cost bonus"}}
	for key in state.hexes:
		var cell: Dictionary = state.hexes[key]
		var dq: int = cell.q-actor.hex[0]; var dr: int = cell.r-actor.hex[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) <= RADIUS: result.hexes[key] = pick(cell,CELL_FIELDS)
	if focus.get("kind") in ["tile","item","settlement","building","road"] and focus.get("hex") is Array and focus.hex.size() == 2 and C.integer(focus.hex[0]) and C.integer(focus.hex[1]):
		var key: String = "%d,%d" % focus.hex
		if state.hexes.has(key): result.hexes[key] = pick(state.hexes[key],CELL_FIELDS)
	for id in state.items: result.items[id] = EntityProjection.public_item(state.items[id])
	for id in state.generated_world.static_entity_catalog.entries:
		var descriptor: Dictionary = state.generated_world.static_entity_catalog.entries[id]
		var include: bool = focus.get("id") == id
		for support in descriptor.supported_hexes:
			if result.hexes.has("%d,%d" % support): include = true
		if include: result.static_entities[id] = StaticProjection.public_descriptor(descriptor)
	var scene := pick(state.scenes[actor.scene_id],["id","name","layer_id","renderer_id","navigation_id","bundle_id"])
	scene.hex_ids = []
	for cell in result.hexes.values(): scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id] = scene
	return C.normalized(result)

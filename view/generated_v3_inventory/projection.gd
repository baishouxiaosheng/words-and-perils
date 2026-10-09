extends RefCounted
## Bounded inventory-profile projection. It depends only on public field
## projectors, never Source/Engine/Generator or mutable view state.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseProjection = preload("res://view/generated_v3_adventure/projection.gd")
const EntityProjection = preload("res://core/source_entities/projection.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const ID := "generated_v3_inventory_context/v1"
const PROFILE := "generated_v3_inventory/v1"
const CELL_VERSION := BaseProjection.CELL_VERSION
const CELL_FIELDS := BaseProjection.CELL_FIELDS
const ACTOR_FIELDS := BaseProjection.ACTOR_FIELDS
const SOURCE_FIELDS := BaseProjection.SOURCE_FIELDS
const SOURCE_EXTRA_FIELDS := ["base_runtime_hash","inventory_profile","inventory_profile_hash","entity_profile","entity_catalog_hash"]
const RADIUS := BaseProjection.RADIUS
const MAX_CELLS := BaseProjection.MAX_CELLS
static func active(state: Dictionary) -> bool:
	# Malformed markers stay in the closed projector rather than falling through
	# to the old exploration or unbounded generic public context.
	var source: Variant = state.get("generated_world",{})
	return (source is Dictionary and (source.get("profile") == PROFILE or source.get("inventory_profile") == PROFILE or source.get("entity_profile") == PROFILE or source.get("projection_id") == ID)) or str(state.get("world_id","")).begins_with("generated_v3_inventory_v1_")
static func matching_identity(state: Dictionary) -> bool:
	var source: Variant = state.get("generated_world",{})
	return source is Dictionary and source.get("source_contract") == "generated_v3_source/v1" and source.get("profile") == PROFILE and source.get("inventory_profile") == PROFILE and source.get("entity_profile") == PROFILE and source.get("projection_id") == ID and source.get("source_schema") == "coastal_source_v3/prototype1" and state.get("world_id") == "generated_v3_inventory_v1_" + str(source.get("content_hash","")) and state.get("actors",{}).get("actor_player",{}).get("scene_id") == "scene_generated_v3" and state.get("scenes",{}).has("scene_generated_v3") and Catalog.validate_world(state).get("ok",false) and state.items.keys() == ["item_travel_bundle"] and state.generated_world.entity_catalog.entries.keys() == ["item_travel_bundle"]
static func pick(value: Dictionary, fields: Array) -> Dictionary:
	return BaseProjection.pick(value,fields)
static func facts(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	if not matching_identity(state): return {}
	var actor: Dictionary = state.actors.actor_player
	var result := {"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,SOURCE_FIELDS+SOURCE_EXTRA_FIELDS),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS,"total_map_cells":state.hexes.size(),"omitted_cells":"outside bounded public context; not evidence of absence","selection_is_action":false,"descriptive_quantum":"exact V3 source values at 1/4096; biome is separate from legal terrain cost","river_scope":"source drainage descriptor only; no river surface, crossing, bridge or object action"}}
	for key in state.hexes:
		var cell: Dictionary = state.hexes[key]
		var dq: int = cell.q-actor.hex[0]; var dr: int = cell.r-actor.hex[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) <= RADIUS: result.hexes[key] = pick(cell,CELL_FIELDS)
	if focus.get("kind") in ["tile","item"] and focus.get("hex") is Array and focus.hex.size() == 2 and C.integer(focus.hex[0]) and C.integer(focus.hex[1]):
		var key: String = "%d,%d" % focus.hex
		if state.hexes.has(key): result.hexes[key] = pick(state.hexes[key],CELL_FIELDS)
	for id in state.items: result.items[id] = EntityProjection.public_item(state.items[id])
	result.context_scope["item_scope"] = "one registered starting travel bundle; recorded custody is public and never generated loot"
	var scene := pick(state.scenes[actor.scene_id],["id","name","layer_id","renderer_id","navigation_id","bundle_id"])
	scene.hex_ids = []
	for cell in result.hexes.values(): scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id] = scene
	return C.normalized(result)

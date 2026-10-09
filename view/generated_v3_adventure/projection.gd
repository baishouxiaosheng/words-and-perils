extends RefCounted
## Bounded V3 public data only. No Source, Engine, Generator or renderer preload:
## ModelView can dispatch here without an authority/preload cycle.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ID := "generated_v3_public_context/v1"
const CELL_VERSION := "generated_v3_cell/v1"
const CELL_FIELDS := ["id","q","r","scene_id","terrain","ground_blocked","air_blocked","all_blocked","source_cell_version","terrain_mapping_id","biome","elevation","ocean","temperature","moisture","rainfall","flow","flow_to","river","uplift","plateau_weight","plateau_core"]
const ACTOR_FIELDS := ["id","name","hex","scene_id","role","faction","health","stamina","inventory","statuses"]
const SOURCE_FIELDS := ["source_contract","profile","source_schema","recipe_version","recipe_id","seed","seed_token","board_radius","content_hash","renderer_profile","geometry_hash","runtime_hash","navigation_id","projection_id","terrain_mapping_id","spawn_policy","pipeline_sha256"]
const RADIUS := 4
const MAX_CELLS := 62
static func active(state: Dictionary) -> bool:
	# A malformed V3 marker still belongs to this closed projector; never fall
	# through into the general unbounded legacy context during a rejection.
	var source: Variant = state.get("generated_world",{})
	return (source is Dictionary and (source.get("source_contract") == "generated_v3_source/v1" or source.get("projection_id") == ID)) or str(state.get("world_id","")).begins_with("generated_v3_v1_")
static func matching_identity(state: Dictionary) -> bool:
	var source: Variant = state.get("generated_world",{})
	return source is Dictionary and source.get("source_contract") == "generated_v3_source/v1" and source.get("projection_id") == ID and source.get("source_schema") == "coastal_source_v3/prototype1" and state.get("world_id") == "generated_v3_v1_" + str(source.get("content_hash","")) and state.get("actors",{}).get("actor_player",{}).get("scene_id") == "scene_generated_v3" and state.get("scenes",{}).has("scene_generated_v3")
static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result
static func facts(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	if not matching_identity(state): return {}
	var actor: Dictionary = state.actors.actor_player
	var result := {"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,SOURCE_FIELDS),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS,"total_map_cells":state.hexes.size(),"omitted_cells":"outside bounded public context; not evidence of absence","selection_is_action":false,"descriptive_quantum":"exact V3 source values at 1/4096; biome is separate from legal terrain cost","river_scope":"source drainage descriptor only; no river surface, crossing, bridge or object action"}}
	for key in state.hexes:
		var cell: Dictionary = state.hexes[key]
		var dq: int = cell.q-actor.hex[0]; var dr: int = cell.r-actor.hex[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) <= RADIUS: result.hexes[key] = pick(cell,CELL_FIELDS)
	if focus.get("kind") == "tile" and focus.get("hex") is Array and focus.hex.size() == 2 and C.integer(focus.hex[0]) and C.integer(focus.hex[1]):
		var key: String = "%d,%d" % focus.hex
		if state.hexes.has(key): result.hexes[key] = pick(state.hexes[key],CELL_FIELDS)
	var scene := pick(state.scenes[actor.scene_id],["id","name","layer_id","renderer_id","navigation_id","bundle_id"])
	scene.hex_ids = []
	for cell in result.hexes.values(): scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id] = scene
	return C.normalized(result)

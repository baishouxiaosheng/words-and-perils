extends RefCounted
## Version-scoped public context; old coast projection and pending hashes are unchanged.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ID := "generated_public_context/v1"
const CELL_FIELDS := ["id","q","r","scene_id","terrain","ground_blocked","air_blocked","all_blocked","source_cell_version","biome","landform","source_terrain","plateau_region","elevation_q4096","temperature_q4096","moisture_q4096","slope_q4096","river","road","bridge"]
const ACTOR_FIELDS := ["id","name","hex","scene_id","role","faction","health","stamina","inventory","statuses"]
const RADIUS := 4
const MAX_CELLS := 62
static func active(state: Dictionary) -> bool:
	var source: Dictionary=state.get("generated_world",{})
	return source.get("source_contract")=="generated_macro_source/v1" and source.get("projection_id")==ID and state.get("world_id")=="generated_macro_v1_"+str(source.get("content_hash","")) and state.get("actors",{}).get("actor_player",{}).get("scene_id")=="scene_generated" and state.get("scenes",{}).has("scene_generated")
static func pick(value: Dictionary,fields: Array) -> Dictionary:
	var result := {}
	for field in fields:
		if value.has(field):result[field]=C.normalized(value[field])
	return result
static func facts(state: Dictionary,focus: Dictionary={}) -> Dictionary:
	var actor: Dictionary=state.actors.actor_player
	var result := {"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,["source_contract","generator_version","seed","board_radius","content_hash","runtime_hash","navigation_id","projection_id","pipeline_sha256"]),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS,"total_map_cells":state.hexes.size(),"omitted_cells":"outside bounded public context; not evidence that absent","selection_is_action":false,"descriptive_quantum":"q4096 values are source values multiplied by4096"}}
	for key in state.hexes:
		var cell: Dictionary=state.hexes[key]
		var dq: int=cell.q-actor.hex[0];var dr: int=cell.r-actor.hex[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))<=RADIUS:result.hexes[key]=pick(cell,CELL_FIELDS)
	if focus.get("kind")=="tile" and focus.get("hex") is Array:
		var key: String="%d,%d"%focus.hex
		if state.hexes.has(key):result.hexes[key]=pick(state.hexes[key],CELL_FIELDS)
	var scene: Dictionary=pick(state.scenes[actor.scene_id],["id","name","layer_id","renderer_id","navigation_id","bundle_id"])
	scene.hex_ids=[]
	for cell in result.hexes.values():scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id]=scene
	return C.normalized(result)

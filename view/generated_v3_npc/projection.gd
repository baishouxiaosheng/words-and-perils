extends RefCounted
## Bounded public facts only. No Source, Generator, mesh, graph or Engine reads.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventoryProjection = preload("res://view/generated_v3_inventory/projection.gd")
const EntityProjection = preload("res://core/source_entities/projection.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const StaticCatalog = preload("res://core/source_entities/static_catalog.gd")
const StaticProjection = preload("res://core/source_entities/static_projection.gd")
const ID := "generated_v3_village_npc_context/v1"
const PROFILE := "generated_v3_village_npc/v1"
const WORLD_PREFIX := "generated_v3_village_npc_v1_"
const CELL_VERSION := InventoryProjection.CELL_VERSION
const CELL_FIELDS := InventoryProjection.CELL_FIELDS
const ACTOR_FIELDS := InventoryProjection.ACTOR_FIELDS
const SOURCE_FIELDS := ["source_contract","profile","source_schema","recipe_version","recipe_id","seed","seed_token","board_radius","content_hash","renderer_profile","geometry_hash","runtime_hash","navigation_id","projection_id","terrain_mapping_id","spawn_policy","pipeline_sha256","base_runtime_hash","inventory_profile","inventory_profile_hash","entity_profile","entity_catalog_hash"]
const SOURCE_EXTRA_FIELDS := ["inventory_runtime_hash","village_inventory_profile","village_inventory_profile_hash","placement_hash","placement_profile","placement_context_hash","effective_navigation_id","effective_navigation_hash","static_entity_profile","static_entity_catalog_hash"]
const RADIUS := InventoryProjection.RADIUS
const MAX_CELLS := InventoryProjection.MAX_CELLS
const NPCState=preload("res://core/source_npc/state.gd")
const NPCCatalog=preload("res://core/source_npc/catalog.gd")
const NPCFocus=preload("res://core/source_npc/focus.gd")
const NPCProjection=preload("res://core/source_npc/projection.gd")
const VegetationCatalog=preload("res://core/generated_v3_vegetation/catalog.gd")
const VegetationProjection=preload("res://core/generated_v3_vegetation/projection.gd")
const EXTRA=["npc_profile","npc_profile_hash","base_village_runtime_hash","npc_catalog_hash","npc_reservation_hash","features","vegetation_profile","vegetation_hash","vegetation_catalog_hash","vegetation_base_runtime_hash"]
static func active(state: Dictionary) -> bool:
	var m: Variant=state.get("generated_world",{})
	return state.has("npc_state") or (m is Dictionary and (m.has("npc_profile") or m.has("npc_catalog") or m.has("npc_catalog_hash") or m.has("vegetation_entity_catalog") or m.has("vegetation_profile") or m.has("vegetation_hash") or m.has("vegetation_catalog_hash") or m.has("vegetation_base_runtime_hash") or m.has("base_village_runtime_hash") or m.get("profile")==PROFILE or m.get("projection_id")==ID)) or str(state.get("world_id","")).begins_with(WORLD_PREFIX)
static func matching_identity(state: Dictionary) -> bool:
	var m: Variant=state.get("generated_world",{})
	if not m is Dictionary or not C.safe(state) or m.get("profile")!=PROFILE or m.get("npc_profile")!=PROFILE or m.get("projection_id")!=ID or m.get("source_contract")!="generated_v3_source/v1":return false
	if not C.exact_fields(m.get("features"),["vegetation"]) or not m.features.vegetation is bool:return false
	for field in ["content_hash","geometry_hash","runtime_hash","npc_profile_hash","base_village_runtime_hash","npc_catalog_hash","npc_reservation_hash"]:
		if not Catalog.valid_hash(m.get(field)):return false
	if state.get("world_id")!=WORLD_PREFIX+C.digest({"source":m.content_hash,"features":m.features}) or not state.get("actors",{}).has("actor_player"):return false
	if not NPCState.validate_world(state).ok or not Catalog.validate_world(state).ok or not StaticCatalog.validate_world(state).ok:return false
	if m.features.vegetation:
		if not VegetationCatalog.validate_world(state).ok:return false
	else:
		for field in ["vegetation_profile","vegetation_hash","vegetation_entity_catalog","vegetation_catalog_hash","vegetation_base_runtime_hash"]:
			if m.has(field):return false
	return m.runtime_hash==C.digest({"profile":PROFILE,"profile_hash":m.npc_profile_hash,"base_village_runtime_hash":m.base_village_runtime_hash,"npc_catalog_hash":m.npc_catalog_hash,"npc_reservation_hash":m.npc_reservation_hash,"features":m.features,"vegetation_hash":m.get("vegetation_hash",""),"vegetation_catalog_hash":m.get("vegetation_catalog_hash","")})
static func pick(value: Dictionary,fields: Array) -> Dictionary:return EntityProjection.pick(value,fields)
static func facts(state: Dictionary,focus: Dictionary={}) -> Dictionary:
	if not matching_identity(state):return {}
	var actor: Dictionary=state.actors.actor_player
	var result={"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"npc_targets":{},"learned_facts":NPCProjection.learned_facts(state.npc_state,"actor_player"),"static_entities":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,SOURCE_FIELDS+SOURCE_EXTRA_FIELDS+EXTRA),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS+1,"total_map_cells":state.hexes.size(),"omitted_cells":"radius4 plus exact selected support; omitted is not absent","selection_is_action":false,"navigation_scope":"scene.navigation_id=terrain; effective_navigation_id/hash=terrain plus building obstruction for move/reach","river_scope":"metadata only; no physical crossing effects","static_scope":"nearby summaries; full selected witness once in attention_focus; omitted geometry does not imply clear passage","npc_scope":"one registered topic; assessed talk costs1 stamina/1turn; learned_facts belongs to this snapshot, provisional if staged","vegetation_scope":"optional selectable plants; no gathering effects","vegetation_display":"near-player/pack crowns may hide for readability; plant state unchanged"}}
	# A named aggregate preserves exact pipeline provenance without repeating
	# its verbose per-file implementation manifest in every model request.
	result.generated_source.erase("pipeline_sha256")
	result.generated_source["pipeline_digest"]=C.digest(state.generated_world.pipeline_sha256)
	result.context_scope["pipeline_digest_convention"]="SHA256(canonical JSON pipeline_sha256 map); per-file entries omitted"
	result.context_scope["actor_scope"]="actors=traveler; exact NPC public state=npc_targets"
	for key in state.hexes:
		var cell: Dictionary=state.hexes[key]
		var q: int=cell.q-actor.hex[0];var r: int=cell.r-actor.hex[1]
		if maxi(absi(q),maxi(absi(r),absi(q+r)))<=RADIUS:result.hexes[key]=pick(cell,CELL_FIELDS)
	if focus.get("hex") is Array and focus.hex.size()==2 and C.integer(focus.hex[0]) and C.integer(focus.hex[1]):
		var key: String="%d,%d"%focus.hex
		if state.hexes.has(key):result.hexes[key]=pick(state.hexes[key],CELL_FIELDS)
	for id in state.items:result.items[id]=EntityProjection.public_item(state.items[id])
	for id in state.generated_world.npc_catalog.entries:
		var resolved: Dictionary=NPCFocus.resolve(NPCFocus.make_reference(id,state),state)
		if not resolved.ok:return {}
		result.npc_targets[id]=NPCProjection.target_summary(resolved.focus)
	for id in state.generated_world.static_entity_catalog.entries:
		var d: Dictionary=state.generated_world.static_entity_catalog.entries[id]
		var include: bool=id==focus.get("id")
		for h in d.supported_hexes:
			if result.hexes.has("%d,%d"%h):include=true
		if include:result.static_entities[id]=pick(d,["id","kind","name","scene_id","supported_hexes"])
	result.context_scope["static_catalog_hash"]=state.generated_world.static_entity_catalog_hash
	result.context_scope["total_static_entities"]=state.generated_world.static_entity_catalog.entries.size()
	result.context_scope["returned_static_entities"]=result.static_entities.size()
	if state.generated_world.features.vegetation:
		var vegetation: Dictionary=VegetationProjection.context(state,focus)
		if vegetation.is_empty():return {}
		result["vegetation"]=vegetation
	var scene: Dictionary=pick(state.scenes[actor.scene_id],["id","name","layer_id","renderer_id","navigation_id","bundle_id"])
	scene.hex_ids=[]
	for cell in result.hexes.values():scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id]=scene
	return C.normalized(result)

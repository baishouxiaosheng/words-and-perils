extends RefCounted
## Bounded public facts only. No Source, Generator, mesh, graph or Engine reads.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventoryProjection = preload("res://view/generated_v3_inventory/projection.gd")
const EntityProjection = preload("res://core/source_entities/projection.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const StaticCatalog = preload("res://core/source_entities/static_catalog.gd")
const StaticProjection = preload("res://core/source_entities/static_projection.gd")
const ID := "generated_v3_village_equipment_context/v1"
const PROFILE := "generated_v3_village_equipment/v1"
const WORLD_PREFIX := "generated_v3_village_equipment_v1_"
const CELL_VERSION := InventoryProjection.CELL_VERSION
const CELL_FIELDS := InventoryProjection.CELL_FIELDS
const ACTOR_FIELDS := ["id","name","hex","scene_id","role","faction","health","stamina","inventory","statuses","equipment","combat_profile","hooks"]
const WEAPON_FIELDS := ["id","name","description","quantity","owner_actor_id","custody_revision","interaction_profile","weapon_profile"]
const EnemyCatalog=preload("res://core/source_equipment/catalog.gd")
const SOURCE_FIELDS := ["source_contract","profile","source_schema","recipe_version","recipe_id","seed","seed_token","board_radius","content_hash","renderer_profile","geometry_hash","runtime_hash","navigation_id","projection_id","terrain_mapping_id","spawn_policy","pipeline_sha256","base_runtime_hash","inventory_profile","inventory_profile_hash","entity_profile","entity_catalog_hash"]
const SOURCE_EXTRA_FIELDS := ["inventory_runtime_hash","village_inventory_profile","village_inventory_profile_hash","placement_hash","placement_profile","placement_context_hash","effective_navigation_id","effective_navigation_hash","static_entity_profile","static_entity_catalog_hash"]
const RADIUS := 3
const MAX_CELLS := 39
const NPCState=preload("res://core/source_npc/state.gd")
const NPCCatalog=preload("res://core/source_npc/catalog.gd")
const NPCFocus=preload("res://core/source_npc/focus.gd")
const NPCProjection=preload("res://core/source_npc/projection.gd")
const VegetationCatalog=preload("res://core/generated_v3_vegetation/catalog.gd")
const VegetationProjection=preload("res://core/generated_v3_vegetation/projection.gd")
const EXTRA=["npc_profile","npc_profile_hash","base_village_runtime_hash","npc_catalog_hash","npc_reservation_hash","features","vegetation_profile","vegetation_hash","vegetation_catalog_hash","vegetation_base_runtime_hash"]
static func active(state:Dictionary)->bool:
	var m:Variant=state.get("generated_world",{})
	return (m is Dictionary and (m.has("equipment_profile") or m.has("equipment_catalog") or m.get("profile")==PROFILE or m.get("projection_id")==ID)) or str(state.get("world_id","")).begins_with(WORLD_PREFIX)
static func matching_identity(state:Dictionary)->bool:
	var m:Variant=state.get("generated_world",{})
	if not m is Dictionary or not C.safe(state) or m.get("profile")!=PROFILE or m.get("equipment_profile")!=PROFILE or m.get("projection_id")!=ID or m.get("source_contract")!="generated_v3_source/v1":return false
	if not C.exact_fields(m.get("features"),["vegetation"]) or not m.features.vegetation is bool:return false
	if state.get("world_id")!=WORLD_PREFIX+C.digest({"source":m.get("content_hash"),"features":m.features}):return false
	if not NPCState.validate_world(state).ok or not Catalog.validate_world(state).ok or not StaticCatalog.validate_world(state).ok or not EnemyCatalog.validate(state).ok:return false
	for field in ["content_hash","geometry_hash","runtime_hash","enemy_profile_hash","enemy_base_runtime_hash","enemy_catalog_hash","enemy_occupancy_hash","equipment_profile_hash","equipment_base_runtime_hash","equipment_catalog_hash"]:
		if not Catalog.valid_hash(m.get(field)):return false
	if not m.get("enemy_melee_neighbors") is Array or m.enemy_melee_neighbors.size()>6:return false
	for key in m.enemy_melee_neighbors:
		if not key is String or not state.get("hexes",{}).has(key):return false
	if m.features.vegetation:
		if not VegetationCatalog.validate_world(state).ok:return false
	else:
		for field in ["vegetation_profile","vegetation_hash","vegetation_entity_catalog","vegetation_catalog_hash","vegetation_base_runtime_hash"]:
			if m.has(field):return false
	return m.get("runtime_hash")==EnemyCatalog.runtime_digest(m)
static func pick(value: Dictionary,fields: Array) -> Dictionary:return EntityProjection.pick(value,fields)
static func facts(state: Dictionary,focus: Dictionary={}) -> Dictionary:
	if not matching_identity(state):return {}
	var actor: Dictionary=state.actors.actor_player
	var result={"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{"actor_player":pick(actor,ACTOR_FIELDS)},"items":{},"npc_targets":{},"learned_facts":NPCProjection.learned_facts(state.npc_state,"actor_player"),"static_entities":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":state.flags.duplicate(true),"generated_source":pick(state.generated_world,SOURCE_FIELDS+SOURCE_EXTRA_FIELDS+EXTRA+["enemy_profile","enemy_profile_hash","enemy_base_runtime_hash","enemy_catalog_hash","enemy_occupancy_hash","equipment_profile","equipment_profile_hash","equipment_base_runtime_hash","equipment_catalog_hash"]),"context_scope":{"schema_version":ID,"center":actor.hex.duplicate(),"radius":RADIUS,"max_cells":MAX_CELLS,"total_map_cells":state.hexes.size(),"omitted_cells":"radius3 plus exact selected and enemy support; omitted is not absent","selection_is_action":false,"navigation_scope":"scene.navigation_id=terrain; effective_navigation_id/hash=terrain plus building obstruction for move/reach","river_scope":"metadata only; no physical crossing effects","static_scope":"nearby summaries; full selected witness once in attention_focus; omitted geometry does not imply clear passage","equipment_scope":"weapons are inspected in actor/inventory facts, not forged selectable bundle targets; pickup/equip each commits one action, no stamina cost; existing poison ticks once","npc_scope":"one registered topic; assessed talk costs1 stamina/1turn; learned_facts belongs to this snapshot, provisional if staged","vegetation_scope":"optional selectable plants; no gathering effects","vegetation_display":"near-player/pack crowns may hide for readability; plant state unchanged"}}
	# A named aggregate preserves exact pipeline provenance without repeating
	# its verbose per-file implementation manifest in every model request.
	result.generated_source.erase("pipeline_sha256")
	result.generated_source["pipeline_digest"]=C.digest(state.generated_world.pipeline_sha256)
	result.context_scope["pipeline_digest_convention"]="SHA256(canonical JSON pipeline_sha256 map); per-file entries omitted"
	result.context_scope["actor_scope"]="actors=traveler and one known stationary hostile; exact friendly NPC public state=npc_targets"
	result.context_scope["combat_scope"]="separately assessed melee, downed-enemy blade pickup and owned staff/blade equipment; exact dry edge for loot; downed hostile remains occupied; no live theft, weapon drop/transfer, new loot, ranged or magic"
	result["combat_turn"]=state.combat_turn.duplicate(true)
	result.actors[EnemyCatalog.ENEMY]=pick(state.actors[EnemyCatalog.ENEMY],ACTOR_FIELDS)
	result["combat_space"]={"occupied_hex":state.actors[EnemyCatalog.ENEMY].hex.duplicate(),"enemy_melee_neighbors":state.generated_world.enemy_melee_neighbors.duplicate(),"range_policy":"exact dry village neighbor edge, never axial distance alone","occupancy":"enemy cell alive or downed; no passage","complete_enemy_reach":true,"other_edges":"local engine authoritative; omitted is not clear"}
	for key in state.hexes:
		var cell: Dictionary=state.hexes[key]
		var q: int=cell.q-actor.hex[0];var r: int=cell.r-actor.hex[1]
		if maxi(absi(q),maxi(absi(r),absi(q+r)))<=RADIUS:result.hexes[key]=pick(cell,CELL_FIELDS)
	if focus.get("hex") is Array and focus.hex.size()==2 and C.integer(focus.hex[0]) and C.integer(focus.hex[1]):
		var key: String="%d,%d"%focus.hex
		if state.hexes.has(key):result.hexes[key]=pick(state.hexes[key],CELL_FIELDS)
	var enemy_hex:Array=state.actors[EnemyCatalog.ENEMY].hex
	var enemy_key:String="%d,%d"%enemy_hex
	result.hexes[enemy_key]=pick(state.hexes[enemy_key],CELL_FIELDS)
	for id in state.items:result.items[id]=pick(state.items[id],WEAPON_FIELDS) if id in [EnemyCatalog.STAFF,EnemyCatalog.BLADE] else EntityProjection.public_item(state.items[id])
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

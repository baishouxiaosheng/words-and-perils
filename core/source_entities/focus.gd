extends RefCounted
## Source-independent read-only item identity and exact frozen custody witnesses.
## A live reference follows its owner. Historical facts never follow live custody.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells=preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Catalog=preload("res://core/source_entities/catalog.gd")
const PublicProjection=preload("res://core/source_entities/projection.gd")
const VERSION:="source-entity-focus/v1"
const REF_FIELDS:=["world_id","kind","id","hex","scene_id","catalog_version","catalog_id","entity_revision"]
const FACT_FIELDS:=["scene_id","source_identity","catalog_identity","descriptor","item","supporting_cell","custody_witness","selection_is_action"]
const IDENTITY_FIELDS:=["source_contract","profile","inventory_profile","content_hash","geometry_hash","base_runtime_hash","runtime_hash","entity_profile","entity_catalog_hash"]
static func reference_for(focus:Dictionary) -> Dictionary:return PublicProjection.pick(focus,REF_FIELDS)
static func source_identity(state:Dictionary) -> Dictionary:return PublicProjection.pick(state.get("generated_world",{}),IDENTITY_FIELDS)
static func valid_hex(value:Variant) -> bool:return value is Array and value.size()==2 and C.integer(value[0]) and C.integer(value[1])
static func cell(state:Dictionary,scene_id:String,hex:Variant) -> Dictionary:
	if not valid_hex(hex) or not state.get("scenes",{}).has(scene_id):return {}
	var found:Dictionary=Cells.cell(state,scene_id,hex)
	return found if found.get("scene_id")==scene_id and found.get("q")==hex[0] and found.get("r")==hex[1] else {}
static func _public_item_shape(item:Variant) -> bool:
	if not item is Dictionary or not C.safe(item):return false
	for field in item:
		if not field in PublicProjection.ITEM_FIELDS:return false
	return C.integer(item.get("custody_revision")) and item.custody_revision>=0
static func live_witness(id:String,state:Dictionary) -> Dictionary:
	if not Catalog.validate_world(state).ok:return {}
	var descriptor_:Dictionary=state.generated_world.entity_catalog.entries.get(id,{})
	var item:Variant=state.items.get(id)
	if descriptor_.is_empty() or not _public_item_shape(item) or not Catalog.item_matches_descriptor(item,descriptor_) or not C.integer(state.get("turn")) or item.custody_revision>state.turn:return {}
	var owners:Array=[]
	for actor_id in state.actors:
		var actor:Variant=state.actors[actor_id]
		if not actor is Dictionary or not actor.get("inventory") is Array:return {}
		var occurrences:int=actor.inventory.count(id)
		if occurrences>1:return {}
		if occurrences==1:owners.append(actor_id)
	if item.has("owner_actor_id"):
		if not item.owner_actor_id is String or item.has("hex") or item.has("scene_id") or owners!=[item.owner_actor_id] or not state.actors.has(item.owner_actor_id):return {}
		var owner:Dictionary=state.actors[item.owner_actor_id]
		if not owner.get("scene_id") is String or cell(state,owner.scene_id,owner.get("hex")).is_empty():return {}
		return {"kind":"carried","owner_actor_id":item.owner_actor_id,"scene_id":owner.scene_id,"hex":owner.hex.duplicate(),"inventory_item_id":id}
	if not owners.is_empty() or not item.get("scene_id") is String or cell(state,item.scene_id,item.get("hex")).is_empty():return {}
	return {"kind":"ground","scene_id":item.scene_id,"hex":item.hex.duplicate()}
static func make_reference(id:String,state:Dictionary) -> Dictionary:
	var witness:=live_witness(id,state)
	if witness.is_empty():return {}
	return C.normalized({"world_id":state.world_id,"kind":"item","id":id,"hex":witness.hex,"scene_id":witness.scene_id,"catalog_version":VERSION,"catalog_id":state.generated_world.entity_catalog.catalog_hash,"entity_revision":state.items[id].custody_revision})
static func resolve(reference:Dictionary,state:Dictionary) -> Dictionary:
	if not C.exact_fields(reference,REF_FIELDS) or not C.safe(reference) or not reference.get("id") is String:return C.fail("ENTITY_FOCUS","目标需要完整的身份、位置与版本，请重新选择。")
	var current:=make_reference(reference.id,state)
	if current.is_empty() or C.bytes(reference)!=C.bytes(current):return C.fail("ENTITY_FOCUS","目标的位置、归属或版本已变化，请重新选择。")
	var focus:Dictionary=current.duplicate(true)
	focus["schema_version"]=1
	focus["facts"]={"scene_id":current.scene_id,"source_identity":source_identity(state),"catalog_identity":Catalog.identity(state),"descriptor":Catalog.descriptor(current.id,state),"item":PublicProjection.public_item(state.items[current.id]),"supporting_cell":cell(state,current.scene_id,current.hex).duplicate(true),"custody_witness":live_witness(current.id,state),"selection_is_action":false}
	return {"ok":true,"focus":C.normalized(focus)}
static func validate_historical(value:Dictionary,world:Dictionary) -> Array:
	if not Catalog.validate_world(world).ok or not C.exact_fields(value,REF_FIELDS+["schema_version","facts"]) or not C.safe(value):return ["Historical entity requires its exact immutable catalog and frozen witness."]
	var catalog:Dictionary=world.generated_world.entity_catalog
	if value.schema_version!=1 or value.catalog_version!=VERSION or value.world_id!=world.world_id or value.catalog_id!=catalog.catalog_hash or value.kind!="item" or not value.id is String or not catalog.entries.has(value.id) or not value.scene_id is String or cell(world,value.scene_id,value.hex).is_empty() or not C.integer(value.entity_revision) or value.entity_revision<0:return ["Historical entity identity is invalid."]
	var facts:Variant=value.facts
	if not C.exact_fields(facts,FACT_FIELDS) or facts.scene_id!=value.scene_id or not facts.selection_is_action is bool or facts.selection_is_action or C.bytes(facts.source_identity)!=C.bytes(source_identity(world)) or C.bytes(facts.catalog_identity)!=C.bytes(Catalog.identity(world)) or C.bytes(facts.descriptor)!=C.bytes(catalog.entries[value.id]) or C.bytes(facts.supporting_cell)!=C.bytes(cell(world,value.scene_id,value.hex)):return ["Historical entity source, descriptor or supporting cell changed."]
	var item:Variant=facts.item;var witness:Variant=facts.custody_witness
	if not _public_item_shape(item) or not Catalog.item_matches_descriptor(item,facts.descriptor) or item.custody_revision!=value.entity_revision or not C.integer(world.items[value.id].get("custody_revision")) or item.custody_revision>world.items[value.id].custody_revision or item.custody_revision>world.turn:return ["Historical entity facts or custody revision are invalid."]
	if item.has("owner_actor_id"):
		if not C.exact_fields(witness,["kind","owner_actor_id","scene_id","hex","inventory_item_id"]) or witness.kind!="carried" or not item.owner_actor_id is String or not world.actors.has(item.owner_actor_id) or item.has("hex") or item.has("scene_id") or witness.owner_actor_id!=item.owner_actor_id or witness.inventory_item_id!=value.id:return ["Historical carried entity lacks its frozen owner witness."]
	else:
		if not C.exact_fields(witness,["kind","scene_id","hex"]) or witness.kind!="ground" or item.get("scene_id")!=value.scene_id or C.bytes(item.get("hex"))!=C.bytes(value.hex):return ["Historical ground entity lacks its frozen location witness."]
	if witness.scene_id!=value.scene_id or C.bytes(witness.hex)!=C.bytes(value.hex):return ["Historical supporting location differs from frozen custody."]
	return []

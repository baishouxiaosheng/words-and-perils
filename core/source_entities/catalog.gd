extends RefCounted
## Immutable identity only. No source generation, renderer, action or custody policy.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const ID:="source_entity_catalog/v1"
const MAX_ENTITIES:=64
const MAX_BYTES:=65536
const FIELDS:=["schema_version","profile_id","source_identity","entries","catalog_hash"]
const SOURCE_FIELDS:=["source_contract","content_hash","geometry_hash","source_runtime_hash"]
const ITEM_DESCRIPTOR_FIELDS:=["id","kind","name","description","quantity","interaction_profile"]
static func valid_hash(value:Variant) -> bool:
	if not value is String or value.length()!=64:return false
	for character in value:
		if not character in "0123456789abcdef":return false
	return true
static func valid_text(value:Variant,maximum:int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.to_utf8_buffer().size()<=maximum
static func valid_id(value:Variant) -> bool:
	# Current BasicActions uses IDs as exact JSON Pointer tokens. Reject reserved
	# slash/tilde, whitespace and controls rather than silently aliasing a path.
	if not value is String or value.is_empty() or value.length()>128:return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-":return false
	return true
static func valid_descriptor(value:Variant) -> bool:
	if not C.exact_fields(value,ITEM_DESCRIPTOR_FIELDS) or not C.safe(value):return false
	if value.kind!="item" or not valid_id(value.id) or not valid_text(value.name,256) or not valid_text(value.description,4096) or not C.integer(value.quantity) or value.quantity<1 or value.quantity>1000000:return false
	return value.interaction_profile is Dictionary and C.bytes(value.interaction_profile).to_utf8_buffer().size()<=2048
static func build(profile_id:String,base_identity:Dictionary,descriptors:Array) -> Dictionary:
	if not valid_text(profile_id,128) or descriptors.is_empty() or descriptors.size()>MAX_ENTITIES:return C.fail("ENTITY_CATALOG","实体目录需要明确版本和有限的登记对象。")
	var source:Dictionary={"source_contract":base_identity.get("source_contract"),"content_hash":base_identity.get("content_hash"),"source_runtime_hash":base_identity.get("runtime_hash")}
	if base_identity.has("geometry_hash"):source.geometry_hash=base_identity.geometry_hash
	var entries:Dictionary={}
	for descriptor_ in descriptors:
		if not valid_descriptor(descriptor_) or entries.has(descriptor_.id):return C.fail("ENTITY_CATALOG","登记对象的身份或描述无效，或ID重复。")
		entries[descriptor_.id]=descriptor_.duplicate(true)
	var catalog:Dictionary=C.normalized({"schema_version":ID,"profile_id":profile_id,"source_identity":source,"entries":entries})
	catalog["catalog_hash"]=C.digest(catalog)
	var checked:=validate(catalog)
	return {"ok":true,"catalog":catalog} if checked.ok else checked
static func validate(value:Variant) -> Dictionary:
	if not C.exact_fields(value,FIELDS) or not C.safe(value) or value.schema_version!=ID or not valid_text(value.profile_id,128) or not value.entries is Dictionary or value.entries.is_empty() or value.entries.size()>MAX_ENTITIES or not valid_hash(value.catalog_hash):return C.fail("ENTITY_CATALOG","实体目录结构无效。")
	var source:Variant=value.source_identity
	if not source is Dictionary or not valid_text(source.get("source_contract"),128) or not valid_hash(source.get("content_hash")) or not valid_hash(source.get("source_runtime_hash")):return C.fail("ENTITY_SOURCE","实体目录缺少真实来源身份。")
	for field in source:
		if not field in SOURCE_FIELDS:return C.fail("ENTITY_SOURCE","实体来源包含未登记字段。")
	if source.has("geometry_hash") and not valid_hash(source.geometry_hash):return C.fail("ENTITY_SOURCE","实体地形身份无效。")
	for id in value.entries:
		if not valid_descriptor(value.entries[id]) or value.entries[id].id!=id:return C.fail("ENTITY_CATALOG","对象ID与登记描述不一致。")
	var payload:Dictionary=value.duplicate(true);payload.erase("catalog_hash")
	if C.digest(payload)!=value.catalog_hash or C.bytes(value).to_utf8_buffer().size()>MAX_BYTES:return C.fail("ENTITY_CATALOG","实体目录身份或大小不匹配。")
	return {"ok":true}
static func validate_world(state:Dictionary) -> Dictionary:
	var metadata:Variant=state.get("generated_world")
	if not metadata is Dictionary:return C.fail("ENTITY_SOURCE","当前世界没有登记实体目录。")
	var catalog:Variant=metadata.get("entity_catalog")
	var checked:=validate(catalog)
	if not checked.ok:return checked
	if metadata.get("entity_profile")!=catalog.profile_id or metadata.get("entity_catalog_hash")!=catalog.catalog_hash or not valid_text(state.get("world_id"),256):return C.fail("ENTITY_SOURCE","实体目录不属于当前世界版本。")
	for field in ["source_contract","content_hash","geometry_hash"]:
		if catalog.source_identity.has(field) and metadata.get(field)!=catalog.source_identity[field]:return C.fail("ENTITY_SOURCE","实体目录与实际地图不一致。")
	if metadata.get("base_runtime_hash")!=catalog.source_identity.source_runtime_hash:return C.fail("ENTITY_SOURCE","实体目录与原始地图运行身份不一致。")
	if not state.get("items") is Dictionary or not state.get("actors") is Dictionary or not state.get("scenes") is Dictionary:return C.fail("ENTITY_WORLD","实体所在世界资料不完整。")
	for id in catalog.entries:
		if not state.items.has(id) or state.actors.has(id) or state.scenes.has(id) or not item_matches_descriptor(state.items[id],catalog.entries[id]):return C.fail("ENTITY_IDENTITY","登记物品与当前资料不一致。")
	return {"ok":true}
static func descriptor(id:String,state:Dictionary) -> Dictionary:
	if not validate_world(state).ok:return {}
	return state.generated_world.entity_catalog.entries.get(id,{}).duplicate(true)
static func item_matches_descriptor(item:Variant,descriptor_:Variant) -> bool:
	if not item is Dictionary or not valid_descriptor(descriptor_):return false
	for field in ["id","name","description","quantity","interaction_profile"]:
		if not item.has(field) or C.bytes(item[field])!=C.bytes(descriptor_[field]):return false
	return true
static func identity(state:Dictionary) -> Dictionary:
	if not validate_world(state).ok:return {}
	var catalog:Dictionary=state.generated_world.entity_catalog
	return {"schema_version":ID,"profile_id":catalog.profile_id,"catalog_hash":catalog.catalog_hash}

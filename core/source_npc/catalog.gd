extends RefCounted
## Source-neutral immutable NPC identity. Source must authenticate placement and
## deterministically rebuild this catalogue; hashes alone are not admission.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const IDs = preload("res://core/source_entities/catalog.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const ID := "source_npc_catalog/v1"
const MAX_NPCS := 16
const MAX_BYTES := 65536
const FIELDS := ["schema_version","profile_id","source_identity","entries","catalog_hash"]
const SOURCE_FIELDS := ["source_contract","content_hash","geometry_hash","source_runtime_hash","placement_hash"]
const ACTOR_FIELDS := ["id","name","description","role","faction","health","stamina","inventory","statuses","hooks","scene_id","hex","location_revision"]
const DESCRIPTOR_FIELDS := ["id","kind","name","description","role","faction","health","stamina","inventory","statuses","hooks","scene_id","hex","location_revision","placement_witness","topics","facts"]
const PLACEMENT_FIELDS := ["schema_version","placement_hash","settlement_id","role","hex","position_q40","position_scale","support_witness"]

static func valid_id(value: Variant) -> bool: return IDs.valid_id(value)
static func valid_hash(value: Variant) -> bool: return IDs.valid_hash(value)
static func valid_hex(value: Variant) -> bool:
	return value is Array and value.size() == 2 and C.integer(value[0]) and C.integer(value[1]) and absf(float(value[0])) <= 1000 and absf(float(value[1])) <= 1000
static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result
static func source_binding(base_identity: Dictionary) -> Dictionary:
	return {"source_contract":base_identity.get("source_contract"),"content_hash":base_identity.get("content_hash"),"geometry_hash":base_identity.get("geometry_hash"),"source_runtime_hash":base_identity.get("runtime_hash",base_identity.get("source_runtime_hash")),"placement_hash":base_identity.get("placement_hash")}
static func stable_id(profile_id: String, base_identity: Dictionary, placement: Dictionary, role: String) -> String:
	# Logical identity is independent of pose/support and mutable revisions.
	# Exact placement remains bound by catalog_hash and Source admission.
	return "npc_" + C.digest({"profile_id":profile_id,"source_identity":source_binding(base_identity),"settlement_id":placement.get("settlement_id"),"role_slot":placement.get("role"),"role":role}).substr(0,40)
static func valid_placement(value: Variant) -> bool:
	if not C.exact_fields(value,PLACEMENT_FIELDS) or not C.safe(value): return false
	if not IDs.valid_text(value.schema_version,128) or not valid_hash(value.placement_hash) or not valid_id(value.settlement_id) or not valid_id(value.role) or not valid_hex(value.hex): return false
	if not value.position_q40 is Array or value.position_q40.size() != 3 or value.position_scale != 1099511627776: return false
	for coordinate in value.position_q40:
		if not C.integer(coordinate): return false
	return value.support_witness is Dictionary and not value.support_witness.is_empty() and C.bytes(value.support_witness).to_utf8_buffer().size() <= 4096
static func valid_descriptor(value: Variant) -> bool:
	if not C.exact_fields(value,DESCRIPTOR_FIELDS) or not C.safe(value) or value.kind != "actor" or not valid_id(value.id): return false
	for field in ["name","description","role","faction"]:
		if not IDs.valid_text(value[field],4096 if field == "description" else 256): return false
	if not valid_id(value.scene_id) or not valid_hex(value.hex) or not C.integer(value.location_revision) or value.location_revision != 0 or not valid_placement(value.placement_witness) or C.bytes(value.hex) != C.bytes(value.placement_witness.hex): return false
	for field in ["health","stamina"]:
		var pool: Variant = value[field]
		if not C.exact_fields(pool,["current","max"]) or not C.integer(pool.current) or not C.integer(pool.max) or pool.current < 1 or pool.max < pool.current or pool.max > 1000000: return false
	if C.bytes(value.inventory) != "[]" or C.bytes(value.statuses) != "{}" or C.bytes(value.hooks) != "[]": return false
	if not value.topics is Dictionary or value.topics.is_empty() or value.topics.size() > 8 or not value.facts is Dictionary or value.facts.is_empty() or value.facts.size() > 16: return false
	var used: Dictionary = {}
	for topic_id in value.topics:
		var topic: Variant = value.topics[topic_id]
		if not valid_id(topic_id) or not C.exact_fields(topic,["id","label","fact_ids"]) or topic.id != topic_id or not IDs.valid_text(topic.label,256) or not topic.fact_ids is Array or topic.fact_ids.is_empty() or topic.fact_ids.size() > 16: return false
		var seen: Dictionary = {}
		for fact_id in topic.fact_ids:
			if not valid_id(fact_id) or not value.facts.has(fact_id) or seen.has(fact_id) or used.has(fact_id): return false
			seen[fact_id] = true; used[fact_id] = true
	if used.size() != value.facts.size(): return false
	for fact_id in value.facts:
		var fact: Variant = value.facts[fact_id]
		if not valid_id(fact_id) or not C.exact_fields(fact,["id","summary","payload"]) or fact.id != fact_id or not IDs.valid_text(fact.summary,2048) or not fact.payload is Dictionary or fact.payload.is_empty() or C.bytes(fact.payload).to_utf8_buffer().size() > 4096: return false
	return C.bytes(value).to_utf8_buffer().size() <= 16384
static func actor_from_descriptor(descriptor_: Dictionary) -> Dictionary:
	return pick(descriptor_,ACTOR_FIELDS) if valid_descriptor(descriptor_) else {}
static func actor_matches_descriptor(actor: Variant, descriptor_: Dictionary) -> bool:
	return C.exact_fields(actor,ACTOR_FIELDS) and C.bytes(actor) == C.bytes(actor_from_descriptor(descriptor_))
static func build(profile_id: String, base_identity: Dictionary, descriptors: Array) -> Dictionary:
	if not IDs.valid_text(profile_id,128) or descriptors.is_empty() or descriptors.size() > MAX_NPCS: return C.fail("NPC_CATALOG","人物目录需要有限且明确的版本与人物。")
	var entries: Dictionary = {}; var fact_ids: Dictionary = {}
	for descriptor_ in descriptors:
		if not valid_descriptor(descriptor_) or entries.has(descriptor_.id): return C.fail("NPC_CATALOG","人物描述无效或身份重复。")
		if descriptor_.id != stable_id(profile_id,base_identity,descriptor_.placement_witness,descriptor_.role): return C.fail("NPC_IDENTITY","人物身份必须绑定来源、安放与角色。")
		for old in ["entity_catalog","static_entity_catalog"]:
			var old_catalog: Variant = base_identity.get(old,{})
			if not old_catalog is Dictionary or not old_catalog.get("entries",{}) is Dictionary: return C.fail("NPC_COLLISION","已有实体目录结构无效。")
			if old_catalog.get("entries",{}).has(descriptor_.id): return C.fail("NPC_COLLISION","人物不能占用已有物品或静态实体身份。")
		for fact_id in descriptor_.facts:
			if fact_ids.has(fact_id): return C.fail("NPC_COLLISION","事实身份不能在人物间重复。")
			fact_ids[fact_id] = true
		entries[descriptor_.id] = descriptor_.duplicate(true)
	var catalog: Dictionary = C.normalized({"schema_version":ID,"profile_id":profile_id,"source_identity":source_binding(base_identity),"entries":entries})
	catalog.catalog_hash = C.digest(catalog)
	var checked: Dictionary = validate(catalog)
	return {"ok":true,"catalog":catalog} if checked.ok else checked
static func validate(value: Variant) -> Dictionary:
	if not C.exact_fields(value,FIELDS) or not C.safe(value) or value.schema_version != ID or not IDs.valid_text(value.profile_id,128) or not valid_hash(value.catalog_hash) or not value.entries is Dictionary or value.entries.is_empty() or value.entries.size() > MAX_NPCS: return C.fail("NPC_CATALOG","人物目录结构无效。")
	if not C.exact_fields(value.source_identity,SOURCE_FIELDS) or not IDs.valid_text(value.source_identity.source_contract,128): return C.fail("NPC_SOURCE","人物缺少不可变来源。")
	for field in ["content_hash","geometry_hash","source_runtime_hash","placement_hash"]:
		if not valid_hash(value.source_identity[field]): return C.fail("NPC_SOURCE","人物来源身份无效。")
	var seen_facts: Dictionary = {}
	for id in value.entries:
		var descriptor_: Variant = value.entries[id]
		if not valid_descriptor(descriptor_) or descriptor_.id != id or descriptor_.placement_witness.placement_hash != value.source_identity.placement_hash or id != stable_id(value.profile_id,value.source_identity,descriptor_.placement_witness,descriptor_.role): return C.fail("NPC_IDENTITY","人物描述与来源、安放身份不一致。")
		for fact_id in descriptor_.facts:
			if seen_facts.has(fact_id): return C.fail("NPC_COLLISION","事实身份重复。")
			seen_facts[fact_id] = true
	var payload: Dictionary = value.duplicate(true); payload.erase("catalog_hash")
	if C.digest(payload) != value.catalog_hash or C.bytes(value).to_utf8_buffer().size() > MAX_BYTES: return C.fail("NPC_CATALOG","人物目录摘要或大小不匹配。")
	return {"ok":true}
static func validate_world(state: Dictionary) -> Dictionary:
	var metadata: Variant = state.get("generated_world")
	if not metadata is Dictionary: return C.fail("NPC_SOURCE","当前世界没有人物来源。")
	var checked: Dictionary = validate(metadata.get("npc_catalog"))
	if not checked.ok: return checked
	var catalog: Dictionary = metadata.npc_catalog
	if metadata.get("npc_profile") != catalog.profile_id or metadata.get("npc_catalog_hash") != catalog.catalog_hash or metadata.get("base_village_runtime_hash") != catalog.source_identity.source_runtime_hash: return C.fail("NPC_SOURCE","人物目录不属于当前村落版本。")
	for field in ["source_contract","content_hash","geometry_hash","placement_hash"]:
		if metadata.get(field) != catalog.source_identity[field]: return C.fail("NPC_SOURCE","人物与地图来源或村落安放不一致。")
	if not state.get("actors") is Dictionary or not state.get("items") is Dictionary or not state.get("scenes") is Dictionary or not IDs.valid_text(state.get("world_id"),256): return C.fail("NPC_WORLD","人物世界资料不完整。")
	for id in catalog.entries:
		var descriptor_: Dictionary = catalog.entries[id]
		if not state.actors.has(id) or state.items.has(id) or state.scenes.has(id) or not actor_matches_descriptor(state.actors[id],descriptor_): return C.fail("NPC_IDENTITY","人物公共形态或身份与目录不一致。")
		for old in ["entity_catalog","static_entity_catalog"]:
			var old_catalog: Variant = metadata.get(old,{})
			if not old_catalog is Dictionary or not old_catalog.get("entries",{}) is Dictionary: return C.fail("NPC_COLLISION","已有实体目录结构无效。")
			if old_catalog.get("entries",{}).has(id): return C.fail("NPC_COLLISION","人物身份与已有目录冲突。")
		if not state.scenes.has(descriptor_.scene_id): return C.fail("NPC_LOCATION","人物场景未安装。")
		var cell: Dictionary = Cells.cell(state,descriptor_.scene_id,descriptor_.hex)
		if cell.is_empty() or cell.get("scene_id") != descriptor_.scene_id or cell.get("q") != descriptor_.hex[0] or cell.get("r") != descriptor_.hex[1] or cell.get("id") == id: return C.fail("NPC_LOCATION","人物缺少准确支持地格。")
	return {"ok":true}
static func fact_evidence_hash(catalog: Dictionary, npc_id: String, topic_id: String, fact_id: String) -> String:
	if not validate(catalog).ok or not catalog.entries.has(npc_id): return ""
	var entry: Dictionary = catalog.entries[npc_id]
	if not entry.topics.has(topic_id) or not fact_id in entry.topics[topic_id].fact_ids: return ""
	return C.digest({"schema_version":"source_npc_fact_evidence/v1","source_identity":catalog.source_identity,"catalog_hash":catalog.catalog_hash,"npc_id":npc_id,"placement_witness":entry.placement_witness,"topic":entry.topics[topic_id],"fact":entry.facts[fact_id]})
static func descriptor(id: String, state: Dictionary) -> Dictionary:
	return state.generated_world.npc_catalog.entries.get(id,{}).duplicate(true) if validate_world(state).ok else {}
static func identity(state: Dictionary) -> Dictionary:
	return pick(state.generated_world.npc_catalog,["schema_version","profile_id","catalog_hash"]) if validate_world(state).ok else {}

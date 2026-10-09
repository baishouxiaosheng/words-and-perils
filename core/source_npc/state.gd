extends RefCounted
## Typed bounded contact/knowledge state. Caller owns the transaction and turn.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/source_npc/catalog.gd")
const ID := "source_npc_state/v1"
const MAX_CONTACTS := 1000000
const CONTACT_FIELDS := ["revision","contacted","conversation_count","last_action_id","last_action_start_turn"]
const FACT_FIELDS := ["fact_id","npc_id","topic_id","catalog_hash","evidence_hash","summary","payload","first_action_id","first_action_start_turn"]
const PATCH_FIELDS := ["type","observer_id","npc_id","topic_id","catalog_hash","expected_revision","action_id","action_start_turn","facts"]

static func empty(catalog: Dictionary, observer_ids: Array = ["actor_player"]) -> Dictionary:
	if not Catalog.validate(catalog).ok or observer_ids.is_empty() or observer_ids.size() > 64: return {}
	var contacts: Dictionary = {}; var learned: Dictionary = {}
	for id in catalog.entries: contacts[id] = {"revision":0,"contacted":false,"conversation_count":0,"last_action_id":"","last_action_start_turn":-1}
	for id in observer_ids:
		if not Catalog.valid_id(id) or learned.has(id) or catalog.entries.has(id): return {}
		learned[id] = {}
	return {"schema_version":ID,"contacts":contacts,"learned_facts":learned}
static func valid_contact(value: Variant, turn: int) -> bool:
	if not C.exact_fields(value,CONTACT_FIELDS) or not C.safe(value) or not C.integer(value.revision) or not C.integer(value.conversation_count) or value.revision != value.conversation_count or value.revision < 0 or value.revision > MAX_CONTACTS or not value.contacted is bool or not value.last_action_id is String or not C.integer(value.last_action_start_turn): return false
	if value.revision == 0: return not value.contacted and value.last_action_id.is_empty() and value.last_action_start_turn == -1
	return value.contacted and not value.last_action_id.strip_edges().is_empty() and value.last_action_id.to_utf8_buffer().size() <= 512 and value.last_action_start_turn >= 0 and value.last_action_start_turn <= turn and value.revision <= value.last_action_start_turn + 1
static func _fact_matches(value: Variant, catalog: Dictionary) -> bool:
	if not C.exact_fields(value,FACT_FIELDS) or not C.safe(value) or not Catalog.valid_id(value.fact_id) or not Catalog.valid_id(value.npc_id) or not Catalog.valid_id(value.topic_id) or value.catalog_hash != catalog.catalog_hash or not catalog.entries.has(value.npc_id): return false
	var descriptor_: Dictionary = catalog.entries[value.npc_id]
	if not descriptor_.topics.has(value.topic_id) or not value.fact_id in descriptor_.topics[value.topic_id].fact_ids: return false
	var authored: Dictionary = descriptor_.facts[value.fact_id]
	return value.evidence_hash == Catalog.fact_evidence_hash(catalog,value.npc_id,value.topic_id,value.fact_id) and value.summary == authored.summary and C.bytes(value.payload) == C.bytes(authored.payload) and value.first_action_id is String and not value.first_action_id.strip_edges().is_empty() and value.first_action_id.to_utf8_buffer().size() <= 512 and C.integer(value.first_action_start_turn) and value.first_action_start_turn >= 0
static func validate_world(world: Dictionary) -> Dictionary:
	# Optional block keeps unrelated worlds byte-compatible.
	var metadata: Variant = world.get("generated_world",{})
	if not metadata is Dictionary:
		# This optional hook must not impose a new metadata schema on legacy
		# worlds with no typed NPC block. Source admission validates its envelope.
		return C.fail("NPC_SOURCE","人物来源元数据必须是对象。") if world.has("npc_state") else {"ok":true}
	var has_marker: bool = world.has("npc_state") or metadata.has("base_village_runtime_hash")
	for field in metadata:
		if (field is String or field is StringName) and str(field).begins_with("npc_"): has_marker = true
	if not has_marker: return {"ok":true}
	var checked: Dictionary = Catalog.validate_world(world)
	if not checked.ok: return checked
	if not C.integer(world.get("turn")) or world.turn < 0: return C.fail("NPC_STATE","人物状态需要有效回合。")
	var value: Variant = world.get("npc_state")
	if not C.exact_fields(value,["schema_version","contacts","learned_facts"]) or not C.safe(value) or value.schema_version != ID or not value.contacts is Dictionary or not value.learned_facts is Dictionary or value.learned_facts.is_empty() or value.learned_facts.size() > 64 or C.bytes(value).to_utf8_buffer().size() > 131072: return C.fail("NPC_STATE","人物接触与知识状态结构无效。")
	var catalog: Dictionary = world.generated_world.npc_catalog
	if value.contacts.size() != catalog.entries.size(): return C.fail("NPC_STATE","人物状态不能增加或遗漏目录身份。")
	for npc_id in catalog.entries:
		if not value.contacts.has(npc_id) or not valid_contact(value.contacts[npc_id],int(world.turn)): return C.fail("NPC_STATE","人物接触版本或回合无效。")
	for observer_id in value.learned_facts:
		var facts: Variant = value.learned_facts[observer_id]
		if not Catalog.valid_id(observer_id) or not world.actors.has(observer_id) or catalog.entries.has(observer_id) or not facts is Dictionary or facts.size() > Catalog.MAX_NPCS * 16: return C.fail("NPC_FACT","学习者或事实集合无效。")
		for fact_id in facts:
			var fact: Variant = facts[fact_id]
			if not _fact_matches(fact,catalog) or fact_id != fact.fact_id or fact.first_action_start_turn > world.turn: return C.fail("NPC_FACT","学到的事实不属于有限目录，或最初凭据无效。")
			var contact: Dictionary = value.contacts[fact.npc_id]
			if not contact.contacted or fact.first_action_start_turn > contact.last_action_start_turn: return C.fail("NPC_FACT","学到的事实没有人物接触凭据。")
	return {"ok":true}
static func validate_committed(world: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_world(world)
	if not checked.ok or not world.has("npc_state"): return checked
	for contact in world.npc_state.contacts.values():
		if contact.conversation_count > world.turn or (contact.contacted and contact.last_action_start_turn >= world.turn): return C.fail("NPC_COMMITTED", "人物接触记录不能领先于已提交回合。")
	for facts in world.npc_state.learned_facts.values():
		for fact in facts.values():
			if fact.first_action_start_turn >= world.turn: return C.fail("NPC_COMMITTED", "最初知识凭据必须来自已提交行动。")
	return {"ok":true}
static func make_patch(world: Dictionary, observer_id: String, npc_id: String, topic_id: String, action_id: String) -> Dictionary:
	if not validate_world(world).ok or not world.has("npc_state") or not world.npc_state.learned_facts.has(observer_id) or not world.npc_state.contacts.has(npc_id) or action_id.strip_edges().is_empty() or action_id.to_utf8_buffer().size() > 512: return {}
	var catalog: Dictionary = world.generated_world.npc_catalog
	var descriptor_: Dictionary = catalog.entries[npc_id]
	var contact: Dictionary = world.npc_state.contacts[npc_id]
	if not descriptor_.topics.has(topic_id) or contact.revision >= MAX_CONTACTS or contact.last_action_id == action_id or contact.last_action_start_turn >= world.turn: return {}
	var facts: Array = []
	for fact_id in descriptor_.topics[topic_id].fact_ids:
		var old: Dictionary = world.npc_state.learned_facts[observer_id].get(fact_id,{})
		var authored: Dictionary = descriptor_.facts[fact_id]
		facts.append(old.duplicate(true) if not old.is_empty() else {"fact_id":fact_id,"npc_id":npc_id,"topic_id":topic_id,"catalog_hash":catalog.catalog_hash,"evidence_hash":Catalog.fact_evidence_hash(catalog,npc_id,topic_id,fact_id),"summary":authored.summary,"payload":authored.payload.duplicate(true),"first_action_id":action_id,"first_action_start_turn":world.turn})
	return C.normalized({"type":"npc_conversation_record","observer_id":observer_id,"npc_id":npc_id,"topic_id":topic_id,"catalog_hash":catalog.catalog_hash,"expected_revision":contact.revision,"action_id":action_id,"action_start_turn":world.turn,"facts":facts})
static func validate_patch(world: Dictionary, patch: Variant) -> Dictionary:
	if not C.exact_fields(patch,PATCH_FIELDS) or not C.safe(patch) or patch.type != "npc_conversation_record": return C.fail("NPC_PATCH","人物对话需要精确类型凭据。")
	for field in ["observer_id","npc_id","topic_id"]:
		if not Catalog.valid_id(patch[field]): return C.fail("NPC_PATCH","人物对话身份无效。")
	if not patch.action_id is String or not C.integer(patch.action_start_turn) or not C.integer(patch.expected_revision): return C.fail("NPC_PATCH","人物对话版本或行动凭据无效。")
	var expected: Dictionary = make_patch(world,patch.observer_id,patch.npc_id,patch.topic_id,patch.action_id)
	if expected.is_empty() or C.bytes(patch) != C.bytes(expected): return C.fail("NPC_PATCH","人物对话事实、首次凭据或版本不符合当前有限目录。")
	return {"ok":true}
static func apply(world: Dictionary, patch: Variant) -> Dictionary:
	var checked: Dictionary = validate_patch(world,patch)
	if not checked.ok: return checked
	# Construct detached block; failed input never partially mutates authority.
	var next: Dictionary = world.npc_state.duplicate(true)
	var contact: Dictionary = next.contacts[patch.npc_id]
	contact.revision += 1; contact.conversation_count += 1; contact.contacted = true
	contact.last_action_id = patch.action_id; contact.last_action_start_turn = patch.action_start_turn
	for fact in patch.facts:
		if not next.learned_facts[patch.observer_id].has(fact.fact_id): next.learned_facts[patch.observer_id][fact.fact_id] = fact.duplicate(true)
	var candidate: Dictionary = world.duplicate(true)
	candidate.npc_state = C.normalized(next)
	checked = validate_world(candidate)
	if not checked.ok: return checked
	world.npc_state = candidate.npc_state
	return {"ok":true}
static func stable(before: Dictionary, after: Dictionary) -> bool:
	if not before.has("npc_state") and not after.has("npc_state"): return true
	if not before.has("npc_state") or not after.has("npc_state") or not validate_world(before).ok or not validate_world(after).ok: return false
	if C.bytes(before.generated_world) != C.bytes(after.generated_world): return false
	var old: Dictionary = before.npc_state; var next: Dictionary = after.npc_state
	if C.bytes(old) == C.bytes(next): return true
	if old.learned_facts.size() != next.learned_facts.size(): return false
	var changed_npc: String = ""; var changed_observer: String = ""
	for observer in old.learned_facts:
		if not next.learned_facts.has(observer): return false
		for fact_id in old.learned_facts[observer]:
			if C.bytes(old.learned_facts[observer][fact_id]) != C.bytes(next.learned_facts[observer].get(fact_id)): return false
		if C.bytes(old.learned_facts[observer]) != C.bytes(next.learned_facts[observer]):
			if not changed_observer.is_empty(): return false
			changed_observer = observer
	for npc_id in old.contacts:
		var a: Dictionary = old.contacts[npc_id]; var b: Dictionary = next.contacts[npc_id]
		if C.bytes(a) == C.bytes(b): continue
		if not changed_npc.is_empty() or b.revision != a.revision + 1 or b.last_action_start_turn != before.turn: return false
		changed_npc = npc_id
	if changed_npc.is_empty(): return false
	# Reconstruct only the bounded typed NPC block; the caller remains the sole
	# authority for stamina, turn advancement, navigation and atomic commit.
	var observers: Array = old.learned_facts.keys() if changed_observer.is_empty() else [changed_observer]
	for observer in observers:
		for topic_id in before.generated_world.npc_catalog.entries[changed_npc].topics:
			var patch: Dictionary = make_patch(before,observer,changed_npc,topic_id,next.contacts[changed_npc].last_action_id)
			if patch.is_empty(): continue
			var expected: Dictionary = old.duplicate(true)
			var contact: Dictionary = expected.contacts[changed_npc]
			contact.revision += 1; contact.conversation_count += 1; contact.contacted = true
			contact.last_action_id = patch.action_id; contact.last_action_start_turn = patch.action_start_turn
			for fact in patch.facts:
				if not expected.learned_facts[observer].has(fact.fact_id): expected.learned_facts[observer][fact.fact_id] = fact.duplicate(true)
			if C.bytes(expected) == C.bytes(next): return true
	return false
static func public_effect(patch: Dictionary, _unused_context: Dictionary = {}) -> Dictionary:
	# Only already-validated frozen patches belong here. This projection never
	# re-reads current catalog/contact/knowledge, including after fresh reload.
	if not C.exact_fields(patch,PATCH_FIELDS) or not C.safe(patch) or patch.type != "npc_conversation_record" or not patch.facts is Array or not C.integer(patch.expected_revision): return {}
	var learned: Array = []; var repeated: Array = []
	for fact in patch.facts:
		if not C.exact_fields(fact,FACT_FIELDS): return {}
		if fact.first_action_id == patch.action_id: learned.append(fact.duplicate(true))
		else: repeated.append(fact.fact_id)
	return C.normalized({"type":"npc_conversation_record","observer_id":patch.observer_id,"npc_id":patch.npc_id,"topic_id":patch.topic_id,"contact_revision":int(patch.expected_revision)+1,"newly_learned_facts":learned,"already_known_fact_ids":repeated,"action_id":patch.action_id,"action_start_turn":patch.action_start_turn})

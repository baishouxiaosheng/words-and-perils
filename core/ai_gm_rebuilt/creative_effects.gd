extends RefCounted
## Trusted whole-object placement and persistent ground-edge relations. No model patches.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content = preload("res://view/playable_build/creative_content.gd")
const POSE_SCHEMA := "anchor_pose/v1"
const RELATION_SCHEMA := "interaction_relation/v1"
const MECHANISM := "span_brace/v1"
const MAX_RECORDS := 128

static func relation_id(source_id: String, target_id: String) -> String:
	return "brace_" + C.digest([MECHANISM, source_id, target_id])
static func active_source(state: Dictionary, source_id: String) -> bool:
	for relation in state.get("creative_relations", {}).values():
		if relation is Dictionary and relation.get("source_item_id") is String and relation.source_item_id == source_id and relation.get("active") is bool and relation.active: return true
	return false
static func active_target(state: Dictionary, target_id: String) -> bool:
	for relation in state.get("creative_relations", {}).values():
		if relation is Dictionary and relation.get("target_id") is String and relation.target_id == target_id and relation.get("active") is bool and relation.active: return true
	return false
static func distance(a: Array, b: Array) -> int:
	var q: int = a[0]-b[0]; var r: int = a[1]-b[1]
	return maxi(absi(q), maxi(absi(r), absi(q+r)))
static func flight(actor: Dictionary) -> bool:
	for status in actor.get("statuses", {}).values():
		if status.get("kind") == "flight" and status.get("remaining_turns",0)>0: return true
	return false
static func edge_allowed(state: Dictionary, actor: Dictionary, from: Array, to: Array) -> bool:
	if flight(actor): return true
	for relation in state.get("creative_relations", {}).values():
		if not relation.active: continue
		var target: Dictionary = state.passage_targets[relation.target_id]
		if target.scene_id == actor.scene_id and ((from == target.endpoints[0] and to == target.endpoints[1]) or (to == target.endpoints[0] and from == target.endpoints[1])): return false
	return true
static func source_count(state: Dictionary) -> int:
	var result := 0
	for item in state.items.values():
		if item.has("physical_traits"): result += 1
	return result
static func validate_state(state: Dictionary) -> Dictionary:
	var catalog: Dictionary = Content.validate_catalog(state)
	if not catalog.ok: return catalog
	if not state.has("physical_catalog"): return {"ok":true}
	for field in ["creative_placements", "creative_relations"]:
		if not state.get(field) is Dictionary: return C.fail("CREATIVE_STATE", "Creative state needs exact bounded placement and relation maps.")
	if state.creative_placements.size() > mini(MAX_RECORDS, source_count(state)) or state.creative_relations.size() > mini(MAX_RECORDS, source_count(state)*state.passage_targets.size()): return C.fail("CREATIVE_CAPACITY", "Anchors or retained source-target relation pairs exceed their separate limits.")
	for source_id in state.creative_placements:
		var pose: Variant = state.creative_placements[source_id]
		if not C.exact_fields(pose,["schema_version","target_id","anchor_id","posture","revision"]) or not pose.schema_version is String or pose.schema_version != POSE_SCHEMA or not pose.target_id is String or not state.passage_targets.has(pose.target_id) or not pose.posture in ["loose","braced"] or not _revision(pose.revision): return C.fail("CREATIVE_POSE", "Malformed fixed-anchor placement.")
		if not state.items.has(source_id) or not state.items[source_id].has("physical_traits"): return C.fail("CREATIVE_POSE", "Placement source must be an installed physical object.")
		var target: Dictionary = state.passage_targets[pose.target_id]; var item: Dictionary = state.items[source_id]
		if not pose.anchor_id is String or pose.anchor_id != target.anchor_id or item.has("owner_actor_id") or item.get("quantity",0) != 1 or item.get("scene_id","") != target.scene_id or item.get("hex",[]) != target.support_hex: return C.fail("CREATIVE_POSE", "Source custody, support and fixed anchor disagree.")
		if (pose.posture == "braced") != active_source(state,source_id): return C.fail("CREATIVE_POSE", "Braced pose requires its actual active source relation.")
	var sources := {}; var targets := {}
	for id in state.creative_relations:
		var relation: Variant = state.creative_relations[id]
		if not C.exact_fields(relation,["schema_version","id","mechanism","source_item_id","target_id","source_deployment_revision","target_revision","active","revision"]) or not relation.schema_version is String or relation.schema_version != RELATION_SCHEMA or not relation.id is String or relation.id != id or not relation.mechanism is String or relation.mechanism != MECHANISM or not relation.source_item_id is String or not relation.target_id is String or not relation.active is bool or not _revision(relation.revision) or not _revision(relation.source_deployment_revision) or not _revision(relation.target_revision): return C.fail("CREATIVE_RELATION", "Malformed bounded source relation.")
		if id != relation_id(relation.source_item_id,relation.target_id) or not state.items.has(relation.source_item_id) or not state.items[relation.source_item_id].has("physical_traits") or not state.passage_targets.has(relation.target_id) or relation.target_revision != state.passage_targets[relation.target_id].revision: return C.fail("CREATIVE_RELATION", "Relation identity, source or target provenance changed.")
		if not relation.active: continue
		var pose: Dictionary = state.creative_placements.get(relation.source_item_id,{})
		if sources.has(relation.source_item_id) or targets.has(relation.target_id) or pose.get("target_id") != relation.target_id or pose.get("posture") != "braced" or state.items[relation.source_item_id].get("custody_revision",0) != relation.source_deployment_revision: return C.fail("CREATIVE_RELATION", "Duplicate or orphan active relation.")
		sources[relation.source_item_id] = true; targets[relation.target_id] = true
	return {"ok":true}
static func _revision(value: Variant) -> bool: return C.integer(value) and value >= 0 and value < 1000000000

static func apply(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not state.has("physical_catalog"): return C.fail("CREATIVE_CATALOG", "No trusted physical catalog is installed in this world.")
	match patch.type:
		"creative_source_place": return _place(state,patch)
		"creative_relation_set": return _relation(state,patch)
	return C.fail("UNKNOWN_PATCH", "Unknown creative mechanism effect.")
static func _place(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch,["type","source_item_id","target_id","expected_custody_revision","expected_placement_revision","posture"]) or not patch.source_item_id is String or not state.items.has(patch.source_item_id) or not patch.target_id is String or not state.passage_targets.has(patch.target_id) or not patch.posture in ["loose","braced"] or not _revision(patch.expected_custody_revision) or not C.integer(patch.expected_placement_revision): return C.fail("CREATIVE_PATCH", "Malformed source placement operation.")
	var item: Dictionary = state.items[patch.source_item_id]; var target: Dictionary = state.passage_targets[patch.target_id]
	var previous: Dictionary = state.creative_placements.get(item.id,{})
	if not item.has("physical_traits") or item.quantity != 1 or not item.get("interaction_profile",{}).get("movable",false) or active_source(state,item.id): return C.fail("CREATIVE_SOURCE", "Source must be one available movable physical object without an active brace.")
	if item.get("custody_revision",0) != patch.expected_custody_revision or previous.get("revision",-1) != patch.expected_placement_revision: return C.fail("CREATIVE_STALE", "Source custody or fixed pose changed.")
	if previous.is_empty() and state.creative_placements.size() >= mini(MAX_RECORDS,source_count(state)): return C.fail("CREATIVE_CAPACITY", "No free fixed-anchor placement record.")
	if previous.get("target_id") == target.id and previous.get("posture") == patch.posture and item.get("hex",[]) == target.support_hex and item.get("scene_id","") == target.scene_id: return {"ok":true}
	var moved: bool = item.has("owner_actor_id") or item.get("hex",[]) != target.support_hex or item.get("scene_id","") != target.scene_id
	for actor in state.actors.values():
		actor.inventory.erase(item.id)
		for slot in actor.get("equipment",{}).keys():
			if actor.equipment[slot] == item.id: actor.equipment.erase(slot)
	item.erase("owner_actor_id"); item.hex = target.support_hex.duplicate(); item.scene_id = target.scene_id
	if moved: item["custody_revision"] = int(item.get("custody_revision",0)) + 1
	state.creative_placements[item.id] = {"schema_version":POSE_SCHEMA,"target_id":target.id,"anchor_id":target.anchor_id,"posture":patch.posture,"revision":int(previous.get("revision",-1))+1}
	return {"ok":true}
static func _relation(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch,["type","source_item_id","target_id","expected_relation_revision","expected_source_revision","active"]) or not patch.source_item_id is String or not state.items.has(patch.source_item_id) or not patch.target_id is String or not state.passage_targets.has(patch.target_id) or not patch.active is bool or not C.integer(patch.expected_relation_revision) or not _revision(patch.expected_source_revision): return C.fail("CREATIVE_PATCH", "Malformed exact relation operation.")
	var item: Dictionary = state.items[patch.source_item_id]; var target: Dictionary = state.passage_targets[patch.target_id]
	var id := relation_id(item.id,target.id); var previous: Dictionary = state.creative_relations.get(id,{})
	var pose: Dictionary = state.creative_placements.get(item.id,{})
	if previous.get("revision",-1) != patch.expected_relation_revision or item.get("custody_revision",0) != patch.expected_source_revision or pose.get("target_id") != target.id or pose.get("posture") != "braced" or item.get("hex",[]) != target.support_hex or item.get("scene_id","") != target.scene_id or item.has("owner_actor_id"): return C.fail("CREATIVE_STALE", "Relation must bind the current exact deployed object and target.")
	if patch.active:
		if active_source(state,item.id) or active_target(state,target.id): return C.fail("CREATIVE_DUPLICATE", "A source or passage already has an active brace.")
		if previous.is_empty() and state.creative_relations.size() >= mini(MAX_RECORDS,source_count(state)*state.passage_targets.size()): return C.fail("CREATIVE_CAPACITY", "Retained relation-pair capacity is full.")
	else:
		if previous.is_empty() or not previous.active: return C.fail("CREATIVE_INACTIVE", "Only the exact active brace may be removed.")
		pose.posture = "loose"; pose.revision += 1
	state.creative_relations[id] = {"schema_version":RELATION_SCHEMA,"id":id,"mechanism":MECHANISM,"source_item_id":item.id,"target_id":target.id,"source_deployment_revision":int(item.get("custody_revision",0)),"target_revision":target.revision,"active":patch.active,"revision":int(previous.get("revision",-1))+1}
	return {"ok":true}

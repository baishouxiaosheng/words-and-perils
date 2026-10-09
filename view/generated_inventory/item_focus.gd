extends RefCounted
## Read-only exact identity for the existing generated travel bundle.
## No inventory profile/source/rules/save-schema change and no item creation.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicProjection = preload("res://view/generated_inventory/projection.gd")
const VERSION := "generated-inventory-focus/v1"
const ITEM := "item_travel_bundle"
const SCENE := "scene_generated"
const REF_FIELDS := ["world_id","kind","id","hex","scene_id","catalog_version","entity_revision"]
const FACT_FIELDS := ["scene_id","source_identity","supporting_cell","selection_is_action","item"]
const IDENTITY_FIELDS := ["source_contract","content_hash","runtime_hash","inventory_profile","inventory_profile_hash"]
static func active(state: Dictionary) -> bool:
	if not PublicProjection.active(state) or not state.get("items",{}).get(ITEM) is Dictionary:return false
	var item: Dictionary=state.items[ITEM]
	for field in ["id","name","description","quantity","interaction_profile","custody_revision"]:
		if not item.has(field):return false
	return item.id==ITEM and item.quantity==1 and C.integer(item.custody_revision) and item.custody_revision>=0
static func identity(state: Dictionary) -> Dictionary:
	return PublicProjection.BaseProjection.pick(state.get("generated_world",{}),IDENTITY_FIELDS)
static func make_reference(id: String,state: Dictionary) -> Dictionary:
	if not active(state) or id != ITEM: return {}
	var item: Dictionary = state.items[id]
	if item.get("id") != id or item.get("quantity") != 1 or not C.integer(item.get("custody_revision")) or item.custody_revision < 0 or item.custody_revision > state.get("turn",-1): return {}
	var hex: Array = []
	if item.has("owner_actor_id"):
		if item.owner_actor_id != "actor_player" or item.has("hex") or item.has("scene_id") or int(item.custody_revision)%2 != 0: return {}
		var owner: Dictionary = state.get("actors",{}).get(item.owner_actor_id,{})
		if owner.get("scene_id") != SCENE or not id in owner.get("inventory",[]): return {}
		hex = owner.get("hex",[]).duplicate()
	else:
		if item.get("scene_id") != SCENE or not item.get("hex") is Array or int(item.custody_revision)%2 != 1: return {}
		hex = item.hex.duplicate()
	if not valid_cell(state,hex): return {}
	return {"world_id":state.world_id,"kind":"item","id":id,"hex":hex,"scene_id":SCENE,"catalog_version":VERSION,"entity_revision":item.custody_revision}
static func valid_cell(state: Dictionary,hex: Variant) -> bool:
	if not hex is Array or hex.size()!=2 or not C.integer(hex[0]) or not C.integer(hex[1]): return false
	var cell: Dictionary = state.get("hexes",{}).get("%d,%d"%hex,{})
	return cell.get("scene_id") == SCENE and not cell.get("ground_blocked",true) and not cell.get("all_blocked",true)
static func resolve(reference: Dictionary,state: Dictionary) -> Dictionary:
	if not C.exact_fields(reference,REF_FIELDS):return C.fail("GENERATED_ITEM_FOCUS","行礼包目标需要完整的身份、位置与版本，请重新选择。")
	var current := make_reference(str(reference.get("id","")),state)
	if current.is_empty() or C.bytes(reference)!=C.bytes(current):return C.fail("GENERATED_ITEM_FOCUS","行礼包的位置或归属已变化，请重新选择。")
	var focus := current.duplicate(true)
	focus["schema_version"] = 1
	focus["facts"] = {"scene_id":SCENE,"source_identity":identity(state),"supporting_cell":state.hexes["%d,%d"%current.hex].duplicate(true),"selection_is_action":false,"item":PublicProjection.BaseProjection.pick(state.items[ITEM],PublicProjection.ITEM_FIELDS)}
	return {"ok":true,"focus":C.normalized(focus)}
static func validate_historical(value: Dictionary,world: Dictionary) -> Array:
	if not active(world) or not C.exact_fields(value,REF_FIELDS+["schema_version","facts"]):return ["Historical generated item requires its exact inventory profile."]
	if value.get("schema_version") != 1 or value.get("catalog_version") != VERSION or value.get("world_id") != world.world_id or value.get("kind") != "item" or value.get("id") != ITEM or value.get("scene_id") != SCENE or not valid_cell(world,value.get("hex")) or not C.integer(value.get("entity_revision")) or value.entity_revision < 0:return ["Historical generated item identity is invalid."]
	var facts: Variant = value.get("facts")
	if not C.exact_fields(facts,FACT_FIELDS) or facts.scene_id != SCENE or facts.selection_is_action != false or not facts.selection_is_action is bool or C.bytes(facts.source_identity) != C.bytes(identity(world)) or C.bytes(facts.supporting_cell) != C.bytes(world.hexes["%d,%d"%value.hex]):return ["Historical generated item source or supporting cell changed."]
	var item: Variant = facts.item
	if not item is Dictionary or not C.safe(item):return ["Historical generated item facts are malformed."]
	for field in item:
		if not field in PublicProjection.ITEM_FIELDS:return ["Historical generated item has an unsupported public field."]
	for field in ["id","name","description","quantity","interaction_profile"]:
		if not item.has(field) or C.bytes(item[field]) != C.bytes(world.items[ITEM][field]):return ["Historical generated item changed immutable capability or identity."]
	if not C.integer(item.get("custody_revision")) or item.custody_revision != value.entity_revision or item.custody_revision > world.items[ITEM].custody_revision:return ["Historical generated custody revision is invalid."]
	if item.has("owner_actor_id"):
		if item.owner_actor_id != "actor_player" or item.has("hex") or item.has("scene_id") or int(item.custody_revision)%2 != 0:return ["Historical carried generated item has invalid custody."]
	elif item.get("scene_id") != SCENE or C.bytes(item.get("hex")) != C.bytes(value.hex) or int(item.custody_revision)%2 != 1:return ["Historical ground generated item has invalid custody."]
	return []

extends RefCounted
## Frozen public evidence only; caller supplies its explicit public-cell whitelist.
## No current world, catalog lookup, renderer or terrain adapter is consulted.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const ITEM_FIELDS:=["id","name","description","quantity","hex","scene_id","owner_actor_id","interaction_profile","custody_revision"]
const FOCUS_FIELDS:=["schema_version","world_id","kind","id","hex","scene_id","catalog_version","catalog_id","entity_revision"]
static func pick(value:Dictionary,fields:Array) -> Dictionary:
	var result:Dictionary={}
	for field in fields:
		if value.has(field):result[field]=C.normalized(value[field])
	return result
static func public_item(item:Dictionary) -> Dictionary:return pick(item,ITEM_FIELDS)
static func frozen_focus(focus:Dictionary,cell_fields:Array) -> Dictionary:
	if focus.is_empty():return {}
	var result:=pick(focus,FOCUS_FIELDS)
	var facts:Dictionary=focus.get("facts",{})
	result.facts=pick(facts,["scene_id","source_identity","catalog_identity","descriptor","custody_witness","selection_is_action"])
	result.facts.item=public_item(facts.get("item",{}))
	result.facts.supporting_cell=pick(facts.get("supporting_cell",{}),cell_fields)
	return C.normalized(result)

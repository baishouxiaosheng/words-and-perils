extends RefCounted
## Accepts frozen values only. Never resolves a live world, actor or catalogue.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ACTOR_FIELDS := ["id","name","description","role","faction","health","stamina","inventory","statuses","hooks","scene_id","hex","location_revision"]
const FOCUS_FIELDS := ["schema_version","world_id","kind","id","hex","scene_id","catalog_version","catalog_id","location_revision","contact_revision"]
static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result
static func public_actor(actor: Dictionary) -> Dictionary: return pick(actor,ACTOR_FIELDS)
static func public_descriptor(descriptor_: Dictionary) -> Dictionary:
	var result: Dictionary = pick(descriptor_,["id","kind","name","description","role","faction"])
	result["offered_topics"] = []
	var topics: Dictionary = descriptor_.get("topics",{})
	var ids: Array = topics.keys(); ids.sort()
	for id in ids: result.offered_topics.append(pick(topics[id],["id","label"]))
	return result
static func frozen_focus(focus: Dictionary, cell_fields: Array) -> Dictionary:
	if focus.is_empty(): return {}
	var result: Dictionary = pick(focus,FOCUS_FIELDS)
	var facts: Dictionary = focus.get("facts",{})
	result.facts = pick(facts,["scene_id","source_identity","catalog_identity","location_witness","public_state","selection_is_action"])
	result.facts.descriptor = public_descriptor(facts.get("descriptor",{}))
	result.facts.actor = public_actor(facts.get("actor",{}))
	result.facts.supporting_cell = pick(facts.get("supporting_cell",{}),cell_fields)
	return C.normalized(result)
static func target_summary(focus: Dictionary) -> Dictionary:
	if focus.is_empty(): return {}
	var facts: Dictionary = focus.get("facts",{})
	var result: Dictionary = pick(focus,["id","scene_id","hex","catalog_id","location_revision","contact_revision"])
	result["actor"] = public_actor(facts.get("actor",{}))
	result["descriptor"] = public_descriptor(facts.get("descriptor",{}))
	result["public_state"] = facts.get("public_state",{}).duplicate(true)
	return C.normalized(result)
static func learned_facts(npc_state: Dictionary, observer_id: String) -> Dictionary:
	return npc_state.get("learned_facts",{}).get(observer_id,{}).duplicate(true)

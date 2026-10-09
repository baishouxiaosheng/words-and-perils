extends RefCounted
## Explicit opt-in plan adapter. The original Basic source remains frozen because
## its real file hash participates in legacy generated-world/NPC/vegetation IDs.
## Parent resolvers still validate aim, range, costs, outcomes and non-lethal hits.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content=preload("res://core/status_gameplay/content.gd")
static func adapt(snapshot:Dictionary,assessment:Dictionary,plan:Dictionary)->Dictionary:
	if not plan.get("ok",false) or not Content.active(snapshot):return plan
	if not snapshot.get("status_foundation",{}).get("instances") is Dictionary:return C.fail("STATUS_HIT_STORE","Weapon status adaptation requires the admitted typed store.")
	# Preserve all branch gates/order and other effects. Never mutate the input
	# snapshot, assessment, or a retained parent-plan value.
	var result:Dictionary=plan.duplicate(true)
	for branch in result.branches:
		var patches:Array=[]
		for patch in branch.patches:
			if patch.get("type")!="actor_status_set" or patch.get("status_id")!="weapon_poison" or patch.get("status",{}).get("kind")!="poison":
				patches.append(patch);continue
			var source:Variant=assessment.get("bindings",{}).get("weapon_item_id")
			if not source is String or source.is_empty() or not snapshot.items.has(source):return C.fail("STATUS_HIT_SOURCE","A frozen weapon poison patch requires its validated weapon binding.")
			var already_poisoned:=false
			for status in snapshot.status_foundation.instances.values():
				if status.owner_kind=="actor" and status.owner_id==patch.actor_id and status.definition_id=="poison":already_poisoned=true;break
			if not already_poisoned:
				patches.append({"type":"status_v2_apply","definition_id":"poison","owner_kind":"actor","owner_id":patch.actor_id,"source_id":source,"parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0}})
		branch.patches=patches
	return result

extends RefCounted
## Honest authored fixtures; never a free-language interpreter.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Actions = preload("res://core/ai_gm_rebuilt/creative_actions.gd")
const Content = preload("res://view/playable_build/creative_content.gd")
const KINDS := ["brace_plank","brace_oar","brace_bar","remove_brace"]
static func goal(kind: String, facts: Dictionary, focus: Dictionary = {}) -> String:
	if not facts.has("physical_catalog") or not kind in KINDS: return ""
	var actor: Dictionary = facts.actors.actor_player
	var source_id: String = {"brace_plank":"item_brace_plank","brace_oar":"item_brace_oar","brace_bar":"item_brace_bar"}.get(kind,"item_brace_plank")
	var target_id: String = ""
	if focus.get("kind") == "passage_edge" and facts.passage_targets.has(focus.get("id","")): target_id = focus.id
	if target_id.is_empty():
		for target in facts.passage_targets.values():
			if target.support_hex == actor.hex: target_id = target.id; break
	if target_id.is_empty(): target_id = Content.passage_targets().keys()[0]
	if kind == "remove_brace":
		for relation in facts.creative_relations.values():
			if relation.active and relation.target_id == target_id: source_id = relation.source_item_id; break
	return public_goal("remove_obstruction" if kind=="remove_brace" else "place_obstruction",facts,source_id,target_id)
static func public_goal(operation: String, facts: Dictionary, source_id: String, target_id: String) -> String:
	if not facts.get("items",{}).has(source_id) or not facts.get("passage_targets",{}).has(target_id): return ""
	var verb := "取下" if operation == "remove_obstruction" else "横置"
	var consequence := "解除这一根支撑并留在窄口旁，之后另行拾取" if operation == "remove_obstruction" else "卡住支座来阻止地面直接通过；未卡稳则放在窄口旁"
	return "【署名创意样例】%s%s（%s）到%s（%s），%s。" % [verb,facts.items[source_id].name,source_id,facts.passage_targets[target_id].name,target_id,consequence]
static func find_goal(request: Dictionary) -> Dictionary:
	var facts: Dictionary = request.context.facts
	for source_id in facts.items:
		if not facts.items[source_id].has("physical_traits"): continue
		for target_id in facts.get("passage_targets",{}):
			for operation in ["place_obstruction","remove_obstruction"]:
				if request.context.goal == public_goal(operation,facts,source_id,target_id): return {"source_id":source_id,"target_id":target_id,"operation":operation}
	return {}
static func assessment(request: Dictionary, source_id: String, target_id: String, operation := "place_obstruction") -> Dictionary:
	var facts: Dictionary = request.context.facts
	if request.context.actor_id != "actor_player" or request.context.goal != public_goal(operation,facts,source_id,target_id): return C.fail("FIXTURE_SCOPE","Creative fixture requires its complete explicit authored goal; free wording requires an independent assessment.")
	var target: Dictionary = facts.passage_targets[target_id]
	var paths: Array = ["/actors/actor_player","/items/"+source_id,"/passage_targets/"+target_id,"/physical_catalog","/creative_placements","/creative_relations"]
	for h in target.endpoints: paths.append(("/scene_hexes/"+target.scene_id+"/" if facts.get("scene_hexes",{}).has(target.scene_id) else "/hexes/")+"%d,%d"%h)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found := C.pointer(facts,path)
		if not found.ok: return C.fail("FIXTURE_FACT","Creative public fact was not transmitted.")
		var id := "creative_"+str(refs.size()); refs.append({"id":id,"path":path,"expected":found.value}); ids.append(id)
	var components: Array = []
	for id in (["release"] if operation=="remove_obstruction" else ["placement","stability"]):
		components.append({"id":id,"parameters":{"A":2,"D":2,"P":0},"disposition":"possible","fact_ref_ids":ids.duplicate()})
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"操作已评估，尚未移动物品、阻断道路或扣除体力。","interpretation":"明确署名的通用刚性物件—窄口支撑样例；未调用模型，物理事实来自编写且验证的内容。","resolver_id":Actions.ID,"bindings":{"actor_id":"actor_player","operation":operation,"source":{"kind":"item","id":source_id},"target":{"kind":"passage_edge","id":target_id},"mechanism":"span_brace/v1","intended_effect":"restore_ground_traversal" if operation=="remove_obstruction" else "restrict_ground_traversal"},"components":components,"fact_refs":refs,"provenance":{"provider":"项目作者 · 明确署名通用物件样例 creative_object/v1","live":false,"kind":"fixture"}}}

extends RefCounted
## Exact labelled offline examples only; arbitrary prose remains manual-assessment input.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const AUTHOR := "项目作者 · typed_effects/v1 离线规则样例（未调用模型）"
static func goal(kind: String, _state: Dictionary = {}, focus: Dictionary = {}) -> String:
	match kind:
		"fell":
			if focus.get("kind") != "tree" or not str(focus.get("id", "")).begins_with("tree:"): return ""
			return "【署名规则样例】尝试放倒关注的树（%s），让它的归属地面成为阻挡。" % focus.id
		"poison": return "【署名规则样例】给自己使用一份苦叶毒剂，评估两回合、每回合一点伤害的毒性效果。"
		"flight": return "【署名规则样例】给自己使用一份轻羽药剂，评估三回合飞行，仍遵守空中、全域与跨水限制。"
	return ""
static func assessment(request: Dictionary, kind: String) -> Dictionary:
	if request.is_empty() or request.get("phase") != "assessment": return C.fail("EXAMPLE_PHASE", "Begin an explicitly labelled example intention first.")
	var context: Dictionary = request.context; var facts: Dictionary = context.facts; var focus: Dictionary = context.attention_focus
	if context.goal != goal(kind, facts, focus) or context.actor_id != "actor_player": return C.fail("EXAMPLE_SCOPE", "Only the exact labelled goal is an authored example. Free text needs an external manual assessment.")
	var refs: Array = [{"id": "actor", "path": "/actors/actor_player", "expected": facts.actors.actor_player}]
	var bindings: Dictionary = {"actor_id": "actor_player"}; var components: Array = []; var resolver := ""
	if kind == "fell":
		var entity: Dictionary = focus.get("facts", {}).get("entity", {})
		if entity.is_empty() or entity.kind != "tree": return C.fail("EXAMPLE_TARGET", "Select a real source-bound scene tree first.")
		var key := Traversal.key(entity.hex)
		refs.append({"id": "tree", "path": "/attention_focus/facts/entity", "expected": entity})
		refs.append({"id": "ground", "path": "/hexes/" + key, "expected": facts.hexes[key]})
		bindings["target_entity_id"] = entity.id; bindings["operation"] = "fell"
		resolver = "coast_manipulate_environment_v1"
		for id in ["control", "force"]: components.append({"id": id, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "certain", "fact_ref_ids": ["actor", "tree", "ground"]})
	elif kind in ["poison", "flight"]:
		var item_id := "item_poison_vial" if kind == "poison" else "item_feather_vial"
		if not facts.items.has(item_id): return C.fail("EXAMPLE_SOURCE", "This save has no authored condition source; older saves are never silently granted supplies.")
		refs.append({"id": "source", "path": "/items/" + item_id, "expected": facts.items[item_id]})
		bindings["target_actor_id"] = "actor_player"; bindings["source_item_id"] = item_id
		resolver = "coast_apply_condition_v1"
		components = [{"id": "delivery", "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "certain", "fact_ref_ids": ["actor", "source"]}, {"id": "effect", "parameters": {"A": 3, "D": 1, "P": 0, "duration": 2 if kind == "poison" else 3, "magnitude": 1}, "disposition": "certain", "fact_ref_ids": ["actor", "source"]}]
	else: return C.fail("EXAMPLE_KIND", "Unknown typed rule example.")
	# Historical saved replies advertise their exact old resolver; only new
	# registries select v2. Never reinterpret an old frozen fixture.
	var v2: String = resolver.trim_suffix("_v1")+"_v2"
	if v2 in request.get("contract",{}).get("resolver_ids",[]): resolver=v2
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "署名离线规则样例已给出有限参数；尚未提交，事实未变。", "interpretation": "精确署名样例，仅验证类型化后果与持续状态，不是真实模型判断。", "resolver_id": resolver, "bindings": bindings, "components": components, "fact_refs": refs, "provenance": {"provider": AUTHOR, "live": false, "kind": "fixture"}}}
